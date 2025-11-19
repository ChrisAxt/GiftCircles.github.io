-- Migration 101: Fix RLS Performance Issues
-- Fixes: auth_rls_initplan warnings from Supabase Linter
--
-- Problem: Policies using auth.uid() directly re-evaluate for each row.
-- Solution: Wrap in (SELECT auth.uid()) to evaluate once per query.
--
-- IMPORTANT: These policies already use (SELECT auth.uid()) from migration 022,
-- but they're still being flagged. This may be due to the can_view_list() and
-- list_id_for_item() helper functions internally using auth.uid() without SELECT.
-- We'll recreate them to ensure compliance.

BEGIN;

-- ============================================================================
-- 1. Fix claims_select_visible policy
-- ============================================================================
-- Note: This policy was updated in migration 067 to allow viewing own claims
-- The auth_rls_initplan warning comes from the can_view_list() call
DROP POLICY IF EXISTS "claims_select_visible" ON public.claims;

CREATE POLICY "claims_select_visible"
  ON public.claims
  AS PERMISSIVE
  FOR SELECT
  USING (
    -- Can view if you're the claimer (for "My Claims" screen)
    claimer_id = (SELECT auth.uid())
    OR
    -- Can view if you have permission to see the list (for list owners/participants)
    public.can_view_list(public.list_id_for_item(item_id), (SELECT auth.uid()))
  );

-- ============================================================================
-- 2. Fix lists_select_visible policy
-- ============================================================================
DROP POLICY IF EXISTS "lists_select_visible" ON public.lists;

CREATE POLICY "lists_select_visible"
  ON public.lists
  AS PERMISSIVE
  FOR SELECT
  USING (public.can_view_list(id, (SELECT auth.uid())));

-- ============================================================================
-- 3. Fix items SELECT policies - consolidate into single policy
-- ============================================================================
-- These are the two duplicate policies causing multiple_permissive_policies warning
DROP POLICY IF EXISTS "members can select items in their events" ON public.items;
DROP POLICY IF EXISTS "items_select_with_receiver_assignment" ON public.items;

-- Create single consolidated policy that preserves both behaviors:
-- 1. Member of event can see items (original policy)
-- 2. Must be able to view the list (respects visibility settings)
CREATE POLICY "items_select"
  ON public.items
  AS PERMISSIVE
  FOR SELECT
  USING (
    -- User must be member of event that contains this list
    EXISTS (
      SELECT 1
      FROM public.lists l
      JOIN public.event_members em ON em.event_id = l.event_id
      WHERE l.id = list_id
        AND em.user_id = (SELECT auth.uid())
    )
    -- AND must be able to view the specific list (respects visibility, exclusions, etc.)
    AND public.can_view_list(list_id, (SELECT auth.uid()))
  );

COMMIT;
