-- Fix claims SELECT policy to allow users to see their own claims
--
-- Problem: The current policy only allows viewing claims if you can view the list.
-- This prevents users from seeing items they've claimed on lists they can't normally view.
--
-- Solution: Add an OR condition to allow users to always see claims where they are the claimer.

BEGIN;

-- Drop the existing restrictive policy
DROP POLICY IF EXISTS "claims_select_visible" ON public.claims;

-- Create a new policy that allows:
-- 1. Viewing claims on lists you can view (for seeing who claimed items on your lists)
-- 2. Viewing your own claims (for the "My Claims" screen)
CREATE POLICY "claims_select_visible"
  ON public.claims
  AS PERMISSIVE
  FOR SELECT
  USING (
    -- Can view if you're the claimer (for "My Claims" screen)
    (claimer_id = auth.uid())
    OR
    -- Can view if you have permission to see the list (for list owners/participants)
    can_view_list(list_id_for_item(item_id), auth.uid())
  );

COMMIT;
