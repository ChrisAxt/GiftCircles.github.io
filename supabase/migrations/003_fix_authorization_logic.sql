-- Migration: Fix authorization logic and visibility policies
-- Purpose: Fix event_members visibility and can_create_event counting
-- Date: 2025-10-02

BEGIN;

-- ============================================================================
-- 1. Fix can_create_event to count OWNED events, not memberships
-- ============================================================================
CREATE OR REPLACE FUNCTION public.can_create_event(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  select case
    when public.is_pro(p_user, now()) then true
    -- Count events OWNED by user, not events they're a member of
    else (select count(*) < 3 from public.events where owner_id = p_user)
  end;
$function$;

-- ============================================================================
-- 2. Fix event_members visibility - remove restrictive policy
-- ============================================================================
-- The current policy only allows members to see other members AFTER they join
-- This breaks the UX when someone joins - they can't see existing members immediately
-- We need to allow members to see all members of events they belong to

-- Drop the old restrictive policy
DROP POLICY IF EXISTS "event_members_select" ON public.event_members;

-- Create new permissive policy that allows members to see all event members
CREATE POLICY "event_members_select_all"
  ON public.event_members
  FOR SELECT
  USING (
    -- User can see members of events they belong to
    EXISTS (
      SELECT 1
      FROM public.event_members em
      WHERE em.event_id = event_members.event_id
        AND em.user_id = auth.uid()
    )
  );

-- ============================================================================
-- 3. Add claims visibility for list creators and event admins
-- ============================================================================
-- Currently users can only see their own claims
-- This breaks functionality where list owners need to see who claimed their items
-- And admins need to manage claims

-- Drop old restrictive policies
DROP POLICY IF EXISTS "claims_select_by_claimer" ON public.claims;

-- Create comprehensive claims SELECT policy
CREATE POLICY "claims_select_visible"
  ON public.claims
  FOR SELECT
  USING (
    -- User can see their own claims
    auth.uid() = claimer_id
    OR
    -- User can see claims on items from lists they created
    EXISTS (
      SELECT 1
      FROM public.items i
      JOIN public.lists l ON l.id = i.list_id
      WHERE i.id = claims.item_id
        AND l.created_by = auth.uid()
    )
    OR
    -- Event admins can see all claims in their events
    EXISTS (
      SELECT 1
      FROM public.items i
      JOIN public.lists l ON l.id = i.list_id
      JOIN public.event_members em ON em.event_id = l.event_id
      WHERE i.id = claims.item_id
        AND em.user_id = auth.uid()
        AND em.role = 'admin'
    )
  );

-- ============================================================================
-- 4. Verify changes
-- ============================================================================
DO $$
BEGIN
  -- Verify event_members policy exists
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'event_members'
      AND policyname = 'event_members_select_all'
  ) THEN
    RAISE EXCEPTION 'event_members_select_all policy not created';
  END IF;

  -- Verify claims policy exists
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'claims'
      AND policyname = 'claims_select_visible'
  ) THEN
    RAISE EXCEPTION 'claims_select_visible policy not created';
  END IF;

  RAISE NOTICE 'Authorization fixes successfully applied';
END $$;

COMMIT;
