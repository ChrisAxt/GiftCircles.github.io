-- Migration: Final comprehensive fix for list_claims_for_user
-- Date: 2025-01-20
-- Description: This migration can be safely re-run. It ensures list_claims_for_user
--              correctly returns claims in collaborative mode (both random features enabled).
--
-- Key fix: In collaborative mode, users are BOTH givers and recipients. The old logic
--          excluded all claims on lists where user is a recipient, which broke collaborative mode.

BEGIN;

-- Drop and recreate to ensure we have the latest version
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

  -- Return empty if not authenticated
  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH visible_items AS (
    -- Get items the user can view
    SELECT i.id AS item_id, i.list_id
    FROM public.items i
    WHERE i.id = ANY(p_item_ids)
      AND public.can_view_list(i.list_id, v_user_id)
  ),

  list_info AS (
    -- Get list configuration for each item
    SELECT DISTINCT
      vi.list_id,
      l.created_by,
      l.event_id,
      COALESCE(l.random_assignment_enabled, false) as random_assignment_enabled,
      COALESCE(l.random_receiver_assignment_enabled, false) as random_receiver_assignment_enabled,
      -- Collaborative mode = both random features enabled
      (COALESCE(l.random_assignment_enabled, false) = true AND
       COALESCE(l.random_receiver_assignment_enabled, false) = true) as is_collaborative,
      -- Check if user is admin/owner
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
      ) as is_admin,
      -- Check if user is a recipient
      EXISTS (
        SELECT 1 FROM public.list_recipients lr
        WHERE lr.list_id = l.id AND lr.user_id = v_user_id
      ) as is_recipient
    FROM visible_items vi
    INNER JOIN public.lists l ON l.id = vi.list_id
  )

  -- Return claims based on visibility rules
  SELECT DISTINCT c.item_id, c.claimer_id
  FROM public.claims c
  INNER JOIN visible_items vi ON vi.item_id = c.item_id
  INNER JOIN list_info li ON li.list_id = vi.list_id
  WHERE
    -- Rule 1: Always show your own claims (by claimer_id)
    c.claimer_id = v_user_id

    -- Rule 2: Admins/owners see all claims
    OR li.is_admin = true

    -- Rule 3: Collaborative mode - show claims assigned to you (even if you're also a recipient)
    OR (li.is_collaborative = true AND c.assigned_to = v_user_id)

    -- Rule 4: Non-random lists - show claims if you're NOT a recipient
    OR (
      li.random_assignment_enabled = false
      AND li.random_receiver_assignment_enabled = false
      AND li.is_recipient = false
    )

    -- Rule 5: Single random mode (giver OR receiver, not both) - show assigned claims if NOT a recipient
    OR (
      li.random_assignment_enabled = true
      AND li.is_collaborative = false
      AND li.is_recipient = false
      AND c.assigned_to = v_user_id
    );
END;
$function$;

COMMENT ON FUNCTION public.list_claims_for_user(uuid[]) IS
'Returns claims visible to the current user for specified items. In collaborative mode (both random assignment features enabled), users see claims assigned to them regardless of recipient status. In other modes, recipients do not see claims. Admins always see all claims.';

-- Verify the function was created
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'list_claims_for_user'
  ) THEN
    RAISE EXCEPTION 'Failed to create list_claims_for_user function';
  END IF;

  RAISE NOTICE 'list_claims_for_user function successfully created/updated';
END;
$$;

COMMIT;
