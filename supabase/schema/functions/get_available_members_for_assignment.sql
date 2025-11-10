-- Function: get_available_members_for_assignment
-- Description: Get list of event members eligible for random assignment
--              When random_receiver_assignment is enabled, includes all members (Secret Santa style)
--              Otherwise, excludes recipients
-- Returns: Array of user_ids in random order

CREATE OR REPLACE FUNCTION public.get_available_members_for_assignment(p_list_id uuid)
RETURNS uuid[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_event_id uuid;
  v_list_creator uuid;
  v_random_receiver_enabled boolean;
  v_member_ids uuid[];
BEGIN
  -- Get list details
  SELECT event_id, created_by, COALESCE(random_receiver_assignment_enabled, false)
  INTO v_event_id, v_list_creator, v_random_receiver_enabled
  FROM public.lists
  WHERE id = p_list_id;

  IF v_event_id IS NULL THEN
    RAISE EXCEPTION 'list_not_found';
  END IF;

  -- Get all event members
  -- ONLY exclude recipients if random_receiver_assignment is NOT enabled
  -- When receiver assignment IS enabled, recipients should also be givers (Secret Santa style)
  IF v_random_receiver_enabled THEN
    -- Include all event members (don't exclude recipients)
    SELECT array_agg(em.user_id ORDER BY random())
    INTO v_member_ids
    FROM public.event_members em
    WHERE em.event_id = v_event_id;
  ELSE
    -- Exclude recipients (old behavior for simple random giver assignment)
    SELECT array_agg(em.user_id ORDER BY random())
    INTO v_member_ids
    FROM public.event_members em
    WHERE em.event_id = v_event_id
      AND NOT EXISTS (
        SELECT 1 FROM public.list_recipients lr
        WHERE lr.list_id = p_list_id AND lr.user_id = em.user_id
      );
  END IF;

  RETURN COALESCE(v_member_ids, ARRAY[]::uuid[]);
END;
$function$;

COMMENT ON FUNCTION public.get_available_members_for_assignment(uuid) IS
'Returns shuffled array of event members eligible for random item assignment. When random_receiver_assignment_enabled is true, includes all members (Secret Santa style). Otherwise, excludes recipients.';
