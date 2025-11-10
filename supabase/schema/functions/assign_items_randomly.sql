-- Function: assign_items_randomly
-- Description: Randomly assign list items to event members
-- Parameters:
--   p_list_id: The list to assign items for
-- Returns: JSON with assignment stats

CREATE OR REPLACE FUNCTION public.assign_items_randomly(p_list_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user uuid;
  v_list record;
  v_is_admin boolean;
  v_available_members uuid[];
  v_unassigned_members uuid[];
  v_items uuid[];
  v_mode text;
  v_item_id uuid;
  v_member_id uuid;
  v_member_idx int;
  v_assignments_made int := 0;
  v_existing_assignments record;
BEGIN
  v_user := auth.uid();

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Get list details
  SELECT l.*, l.random_assignment_mode, l.random_assignment_enabled, l.event_id, l.created_by
  INTO v_list
  FROM public.lists l
  WHERE l.id = p_list_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'list_not_found';
  END IF;

  IF NOT v_list.random_assignment_enabled THEN
    RAISE EXCEPTION 'random_assignment_not_enabled';
  END IF;

  -- Check if user is list owner or event admin
  SELECT
    (v_list.created_by = v_user) OR
    EXISTS(
      SELECT 1 FROM public.event_members em
      WHERE em.event_id = v_list.event_id
        AND em.user_id = v_user
        AND em.role = 'admin'
    ) OR
    EXISTS(
      SELECT 1 FROM public.events e
      WHERE e.id = v_list.event_id
        AND e.owner_id = v_user
    )
  INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  -- Get available members for assignment
  v_available_members := public.get_available_members_for_assignment(p_list_id);

  IF array_length(v_available_members, 1) IS NULL OR array_length(v_available_members, 1) = 0 THEN
    RAISE EXCEPTION 'no_available_members';
  END IF;

  v_mode := v_list.random_assignment_mode;

  -- Get unassigned items (items without any assignments)
  SELECT array_agg(i.id ORDER BY i.created_at)
  INTO v_items
  FROM public.items i
  WHERE i.list_id = p_list_id
    AND NOT EXISTS (
      SELECT 1 FROM public.claims c
      WHERE c.item_id = i.id
        AND c.assigned_to IS NOT NULL
    );

  IF array_length(v_items, 1) IS NULL OR array_length(v_items, 1) = 0 THEN
    -- No new items to assign, but check if we need to reassign based on mode
    -- For now, just return success with 0 assignments
    UPDATE public.lists
    SET random_assignment_executed_at = now()
    WHERE id = p_list_id;

    RETURN json_build_object(
      'success', true,
      'assignments_made', 0,
      'message', 'no_new_items_to_assign'
    );
  END IF;

  -- Execute assignment based on mode
  IF v_mode = 'one_per_member' THEN
    -- Assign one item per member, prioritizing members with no assignments
    v_member_idx := 1;

    FOREACH v_item_id IN ARRAY v_items
    LOOP
      -- Get members who don't have any assignments yet
      SELECT array_agg(m.user_id ORDER BY random())
      INTO v_unassigned_members
      FROM (
        SELECT unnest(v_available_members) AS user_id
      ) m
      WHERE NOT EXISTS (
        SELECT 1 FROM public.claims c
        JOIN public.items i ON i.id = c.item_id
        WHERE c.assigned_to = m.user_id
          AND i.list_id = p_list_id
      );

      -- Exit if all members have at least one assignment
      -- This ensures "one per member" means exactly one, not multiple
      EXIT WHEN array_length(v_unassigned_members, 1) IS NULL OR array_length(v_unassigned_members, 1) = 0;

      -- Assign to first member in shuffled array
      v_member_id := v_unassigned_members[1];

      -- Create assignment (claim with assigned_to)
      INSERT INTO public.claims (item_id, claimer_id, assigned_to)
      VALUES (v_item_id, v_member_id, v_member_id)
      ON CONFLICT DO NOTHING;

      v_assignments_made := v_assignments_made + 1;
    END LOOP;

  ELSIF v_mode = 'distribute_all' THEN
    -- Distribute all items as evenly as possible
    v_member_idx := 1;

    FOREACH v_item_id IN ARRAY v_items
    LOOP
      -- Get member with fewest assignments for this list
      SELECT m.user_id INTO v_member_id
      FROM (SELECT unnest(v_available_members) AS user_id) m
      LEFT JOIN (
        SELECT c.assigned_to, COUNT(*) as assignment_count
        FROM public.claims c
        JOIN public.items i ON i.id = c.item_id
        WHERE i.list_id = p_list_id
          AND c.assigned_to IS NOT NULL
        GROUP BY c.assigned_to
      ) counts ON counts.assigned_to = m.user_id
      ORDER BY COALESCE(counts.assignment_count, 0), random()
      LIMIT 1;

      IF v_member_id IS NULL THEN
        EXIT;
      END IF;

      -- Create assignment
      INSERT INTO public.claims (item_id, claimer_id, assigned_to)
      VALUES (v_item_id, v_member_id, v_member_id)
      ON CONFLICT DO NOTHING;

      v_assignments_made := v_assignments_made + 1;
    END LOOP;

  ELSE
    RAISE EXCEPTION 'invalid_assignment_mode';
  END IF;

  -- Update execution timestamp
  UPDATE public.lists
  SET random_assignment_executed_at = now()
  WHERE id = p_list_id;

  RETURN json_build_object(
    'success', true,
    'assignments_made', v_assignments_made,
    'member_count', array_length(v_available_members, 1),
    'mode', v_mode
  );
END;
$function$;

COMMENT ON FUNCTION public.assign_items_randomly(uuid) IS
'Randomly assigns list items to event members based on the list random_assignment_mode. Only list owner or event admin can execute.';
