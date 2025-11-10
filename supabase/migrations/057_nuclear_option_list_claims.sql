-- Migration: Nuclear option - completely rewrite list_claims_for_user without can_view_list dependency
-- Date: 2025-01-20
-- Description: The can_view_list function might be causing issues. This version inlines all visibility logic.

BEGIN;

DROP FUNCTION IF EXISTS public.list_claims_for_user(uuid[]);

CREATE FUNCTION public.list_claims_for_user(p_item_ids uuid[])
RETURNS TABLE(item_id uuid, claimer_id uuid)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT c.item_id, c.claimer_id
  FROM public.claims c
  INNER JOIN public.items i ON i.id = c.item_id
  INNER JOIN public.lists l ON l.id = i.list_id
  WHERE
    -- Only include items from the requested item IDs
    c.item_id = ANY(p_item_ids)
    -- User must be an event member
    AND EXISTS (
      SELECT 1 FROM public.event_members em
      WHERE em.event_id = l.event_id AND em.user_id = v_user_id
    )
    -- User must not be excluded from the list
    AND NOT EXISTS (
      SELECT 1 FROM public.list_exclusions le
      WHERE le.list_id = l.id AND le.user_id = v_user_id
    )
    -- Apply claim visibility rules
    AND (
      -- Rule 1: Always show your own claims
      c.claimer_id = v_user_id

      -- Rule 2: List creator sees all claims
      OR l.created_by = v_user_id

      -- Rule 3: Event admin sees all claims
      OR EXISTS (
        SELECT 1 FROM public.event_members em
        WHERE em.event_id = l.event_id
          AND em.user_id = v_user_id
          AND em.role = 'admin'
      )

      -- Rule 4: Event owner sees all claims
      OR EXISTS (
        SELECT 1 FROM public.events e
        WHERE e.id = l.event_id AND e.owner_id = v_user_id
      )

      -- Rule 5: Collaborative mode (both random features) - show claims assigned to you
      OR (
        COALESCE(l.random_assignment_enabled, false) = true
        AND COALESCE(l.random_receiver_assignment_enabled, false) = true
        AND c.assigned_to = v_user_id
      )

      -- Rule 6: Non-random lists - show claims if you're NOT a recipient
      OR (
        COALESCE(l.random_assignment_enabled, false) = false
        AND COALESCE(l.random_receiver_assignment_enabled, false) = false
        AND NOT EXISTS (
          SELECT 1 FROM public.list_recipients lr
          WHERE lr.list_id = l.id AND lr.user_id = v_user_id
        )
      )

      -- Rule 7: Single random mode - show assigned claims if NOT a recipient
      OR (
        COALESCE(l.random_assignment_enabled, false) = true
        AND COALESCE(l.random_receiver_assignment_enabled, false) = false
        AND c.assigned_to = v_user_id
        AND NOT EXISTS (
          SELECT 1 FROM public.list_recipients lr
          WHERE lr.list_id = l.id AND lr.user_id = v_user_id
        )
      )
    );
END;
$function$;

COMMENT ON FUNCTION public.list_claims_for_user(uuid[]) IS
'Returns claims visible to current user. Simplified version that inlines all visibility checks. Collaborative mode shows claims assigned to user regardless of recipient status.';

-- Verify
DO $$
BEGIN
  RAISE NOTICE 'list_claims_for_user function updated successfully';
END;
$$;

COMMIT;
