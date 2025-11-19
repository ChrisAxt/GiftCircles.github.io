-- Migration: Simplified fix for list_claims_for_user in collaborative mode
-- Date: 2025-01-20
-- Description: The previous fix was complex. This simplifies the logic:
--              - For collaborative mode (both random features): show claims assigned to user, ignore recipient status
--              - For other modes: existing logic

BEGIN;

CREATE OR REPLACE FUNCTION public.list_claims_for_user(p_item_ids uuid[])
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
  WITH visible_items AS (
    -- Items user can view
    SELECT i.id AS item_id, i.list_id
    FROM public.items i
    WHERE i.id = ANY(p_item_ids)
      AND public.can_view_list(i.list_id, v_user_id)
  ),

  list_modes AS (
    -- Get list configuration
    SELECT DISTINCT
      l.id AS list_id,
      l.created_by,
      l.event_id,
      l.random_assignment_enabled,
      l.random_receiver_assignment_enabled,
      -- Collaborative: both features enabled
      (COALESCE(l.random_assignment_enabled, false) = true AND
       COALESCE(l.random_receiver_assignment_enabled, false) = true) AS is_collaborative,
      -- User is admin/owner of this list
      (
        l.created_by = v_user_id
        OR EXISTS (
          SELECT 1 FROM public.event_members em
          WHERE em.event_id = l.event_id
            AND em.user_id = v_user_id
            AND em.role = 'admin'
        )
        OR EXISTS (
          SELECT 1 FROM public.events e
          WHERE e.id = l.event_id AND e.owner_id = v_user_id
        )
      ) AS is_admin,
      -- User is recipient of this list
      EXISTS (
        SELECT 1 FROM public.list_recipients lr
        WHERE lr.list_id = l.id AND lr.user_id = v_user_id
      ) AS is_recipient
    FROM visible_items vi
    INNER JOIN public.lists l ON l.id = vi.list_id
  )

  -- Return claims based on mode
  SELECT DISTINCT c.item_id, c.claimer_id
  FROM public.claims c
  INNER JOIN visible_items vi ON vi.item_id = c.item_id
  INNER JOIN list_modes lm ON lm.list_id = vi.list_id
  WHERE
    -- Always show user's own claims
    c.claimer_id = v_user_id
    -- OR user is admin/owner (sees all claims)
    OR lm.is_admin = true
    -- OR collaborative mode: show claims assigned to user (even if they're a recipient)
    OR (lm.is_collaborative = true AND c.assigned_to = v_user_id)
    -- OR non-random list: show claims if not a recipient
    OR (
      COALESCE(lm.random_assignment_enabled, false) = false
      AND COALESCE(lm.random_receiver_assignment_enabled, false) = false
      AND lm.is_recipient = false
    )
    -- OR single random mode (not collaborative): show assigned claims if not a recipient
    OR (
      COALESCE(lm.random_assignment_enabled, false) = true
      AND lm.is_collaborative = false
      AND lm.is_recipient = false
      AND c.assigned_to = v_user_id
    );
END;
$function$;

COMMENT ON FUNCTION public.list_claims_for_user(uuid[]) IS
'Returns claims visible to current user. Simplified logic: collaborative mode bypasses recipient filter, other modes apply it.';

COMMIT;
