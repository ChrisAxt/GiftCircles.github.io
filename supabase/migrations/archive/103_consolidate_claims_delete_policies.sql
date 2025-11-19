-- Migration 103: Consolidate Claims DELETE Policies
-- Fixes: multiple_permissive_policies warnings for claims DELETE
--
-- Claims can be deleted by:
-- 1. The user who made the claim (unclaiming their own claim)
-- 2. The event admin (when deleting items in their event)
-- 3. The item creator (when deleting their own item)

BEGIN;

DROP POLICY IF EXISTS "admins can delete any claims" ON public.claims;
DROP POLICY IF EXISTS "delete own claims" ON public.claims;

CREATE POLICY "claims_delete"
  ON public.claims
  AS PERMISSIVE
  FOR DELETE
  USING (
    -- User can delete their own claim (unclaim)
    claimer_id = (SELECT auth.uid())
    OR
    -- Admin of the event can delete any claim
    EXISTS (
      SELECT 1
      FROM public.items i
      JOIN public.lists l ON l.id = i.list_id
      JOIN public.event_members em ON em.event_id = l.event_id
      WHERE i.id = item_id
        AND em.user_id = (SELECT auth.uid())
        AND em.role = 'admin'::public.member_role
    )
    OR
    -- Item creator can delete claims on their item
    EXISTS (
      SELECT 1
      FROM public.items i
      WHERE i.id = item_id
        AND i.created_by = (SELECT auth.uid())
    )
  );

COMMIT;
