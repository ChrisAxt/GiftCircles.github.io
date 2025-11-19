-- REVERT: This approach causes infinite recursion
-- Instead, we'll use a dedicated RPC function for fetching claims with full details

BEGIN;

-- Drop the helper function if it exists
DROP FUNCTION IF EXISTS public.user_has_claimed_from_list(uuid, uuid);

-- Restore the original simple policy
DROP POLICY IF EXISTS "lists_select_visible" ON public.lists;

CREATE POLICY "lists_select_visible"
  ON public.lists
  AS PERMISSIVE
  FOR SELECT
  USING (can_view_list(id, auth.uid()));

COMMIT;
