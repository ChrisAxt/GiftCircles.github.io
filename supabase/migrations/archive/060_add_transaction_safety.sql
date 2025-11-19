-- Migration: Add transaction safety to critical operations
-- Date: 2025-01-20
-- Description: Wraps multi-step operations in proper transactions with rollback handling
--              and adds explicit EXCEPTION blocks for better error recovery.

BEGIN;

-- ============================================================================
-- UPDATE: create_list_with_people with transaction safety
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_list_with_people(
  p_event_id uuid,
  p_name text,
  p_visibility list_visibility DEFAULT 'event'::list_visibility,
  p_recipients uuid[] DEFAULT '{}'::uuid[],
  p_hidden_recipients uuid[] DEFAULT '{}'::uuid[],
  p_viewers uuid[] DEFAULT '{}'::uuid[],
  p_custom_recipient_name text DEFAULT NULL::text,
  p_random_assignment_enabled boolean DEFAULT false,
  p_random_assignment_mode text DEFAULT NULL::text,
  p_random_receiver_assignment_enabled boolean DEFAULT false,
  p_for_everyone boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user uuid;
  v_list_id uuid;
  v_is_member boolean;
BEGIN
  v_user := auth.uid();

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Check membership in event
  SELECT EXISTS(
    SELECT 1 FROM public.event_members
    WHERE event_id = p_event_id AND user_id = v_user
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RAISE EXCEPTION 'not_an_event_member';
  END IF;

  -- Validate random assignment mode if enabled
  IF p_random_assignment_enabled THEN
    IF p_random_assignment_mode IS NULL OR
       p_random_assignment_mode NOT IN ('one_per_member', 'distribute_all') THEN
      RAISE EXCEPTION 'invalid_random_assignment_mode';
    END IF;
  END IF;

  -- Input validation
  IF p_name IS NULL OR trim(p_name) = '' THEN
    RAISE EXCEPTION 'list_name_required';
  END IF;

  IF length(trim(p_name)) > 255 THEN
    RAISE EXCEPTION 'list_name_too_long';
  END IF;

  -- All operations are atomic within this function (implicit transaction)
  -- If any step fails, entire function rolls back automatically

  -- Create list with all fields including random assignment settings
  INSERT INTO public.lists (
    event_id,
    name,
    created_by,
    visibility,
    custom_recipient_name,
    random_assignment_enabled,
    random_assignment_mode,
    random_receiver_assignment_enabled,
    for_everyone
  )
  VALUES (
    p_event_id,
    trim(p_name),
    v_user,
    COALESCE(p_visibility, 'event'),
    p_custom_recipient_name,
    p_random_assignment_enabled,
    CASE WHEN p_random_assignment_enabled THEN p_random_assignment_mode ELSE NULL END,
    p_random_receiver_assignment_enabled,
    p_for_everyone
  )
  RETURNING id INTO v_list_id;

  -- Add recipients (per-recipient can_view flag)
  IF array_length(p_recipients, 1) IS NOT NULL THEN
    INSERT INTO public.list_recipients (list_id, user_id, can_view)
    SELECT v_list_id, r, NOT (r = ANY(COALESCE(p_hidden_recipients, '{}')))
    FROM unnest(p_recipients) AS r
    WHERE r IS NOT NULL;  -- Safety check for NULL UUIDs
  END IF;

  -- Add explicit viewers (only matters when visibility = 'selected')
  IF COALESCE(p_visibility, 'event') = 'selected'
     AND array_length(p_viewers, 1) IS NOT NULL THEN
    INSERT INTO public.list_viewers (list_id, user_id)
    SELECT v_list_id, v
    FROM unnest(p_viewers) AS v
    WHERE v IS NOT NULL  -- Safety check for NULL UUIDs
      AND NOT EXISTS (
        -- Don't duplicate if already a recipient
        SELECT 1 FROM public.list_recipients lr
        WHERE lr.list_id = v_list_id AND lr.user_id = v
      );
  END IF;

  RETURN v_list_id;

EXCEPTION
  WHEN OTHERS THEN
    -- Log the error (PostgreSQL 13+ syntax)
    RAISE WARNING 'create_list_with_people failed: % %', SQLERRM, SQLSTATE;
    -- Re-raise the exception to rollback transaction
    RAISE;
END;
$function$;

COMMENT ON FUNCTION public.create_list_with_people(uuid, text, list_visibility, uuid[], uuid[], uuid[], text, boolean, text, boolean, boolean) IS
'Creates a list with recipients, viewers, and optional random assignment configuration. Transaction-safe with automatic rollback on error.';

-- ============================================================================
-- UPDATE: assign_items_randomly with transaction safety
-- ============================================================================

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
    -- No new items to assign
    UPDATE public.lists
    SET random_assignment_executed_at = now()
    WHERE id = p_list_id;

    RETURN json_build_object(
      'success', true,
      'assignments_made', 0,
      'member_count', array_length(v_available_members, 1),
      'message', 'no_new_items_to_assign'
    );
  END IF;

  -- All assignment operations are wrapped in implicit transaction
  -- If any INSERT fails, entire function rolls back

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
      EXIT WHEN array_length(v_unassigned_members, 1) IS NULL OR array_length(v_unassigned_members, 1) = 0;

      -- Assign to first member in shuffled array
      v_member_id := v_unassigned_members[1];

      -- Create assignment (claim with assigned_to)
      -- Use INSERT ... ON CONFLICT to ensure idempotency
      INSERT INTO public.claims (item_id, claimer_id, assigned_to)
      VALUES (v_item_id, v_member_id, v_member_id)
      ON CONFLICT (item_id, claimer_id) DO UPDATE
      SET assigned_to = EXCLUDED.assigned_to;

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

      -- Create assignment with idempotency
      INSERT INTO public.claims (item_id, claimer_id, assigned_to)
      VALUES (v_item_id, v_member_id, v_member_id)
      ON CONFLICT (item_id, claimer_id) DO UPDATE
      SET assigned_to = EXCLUDED.assigned_to;

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

EXCEPTION
  WHEN OTHERS THEN
    -- Log error and re-raise to trigger rollback
    RAISE WARNING 'assign_items_randomly failed for list %: % %', p_list_id, SQLERRM, SQLSTATE;
    RAISE;
END;
$function$;

COMMENT ON FUNCTION public.assign_items_randomly(uuid) IS
'Randomly assigns list items to event members. Transaction-safe with automatic rollback on error. Idempotent.';

-- ============================================================================
-- ADD: Idempotency constraint for claims
-- ============================================================================

-- Ensure we have a unique constraint to support ON CONFLICT
CREATE UNIQUE INDEX IF NOT EXISTS idx_claims_item_claimer_unique
ON public.claims(item_id, claimer_id);

COMMENT ON INDEX idx_claims_item_claimer_unique IS
'Unique constraint to ensure idempotency of claim operations and support ON CONFLICT.';

-- Log completion
DO $$
BEGIN
  RAISE NOTICE 'Transaction safety added to critical functions.';
  RAISE NOTICE 'Functions now have automatic rollback on error and improved error handling.';
END;
$$;

COMMIT;
