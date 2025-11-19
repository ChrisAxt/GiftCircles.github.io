-- EMERGENCY ROLLBACK: Fix Infinite Recursion in event_members Policy
-- Purpose: Immediately restore functionality after infinite recursion error
-- Date: 2025-10-02
-- Issue: Migration 003 created recursive policy that breaks all queries

BEGIN;

-- ============================================================================
-- IMMEDIATE FIX: Drop broken policy and restore original
-- ============================================================================

-- Drop the broken policy that causes infinite recursion
DROP POLICY IF EXISTS "event_members_select_all" ON public.event_members;

-- Restore the original policy (temporary - will be fixed properly in 005)
CREATE POLICY "event_members_select"
  ON public.event_members
  FOR SELECT
  USING (is_member_of_event(event_id));

-- ============================================================================
-- Verification
-- ============================================================================

DO $$
BEGIN
  -- Verify the policy exists
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'event_members'
      AND policyname = 'event_members_select'
  ) THEN
    RAISE EXCEPTION 'event_members_select policy not restored';
  END IF;

  -- Verify the broken policy is gone
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'event_members'
      AND policyname = 'event_members_select_all'
  ) THEN
    RAISE EXCEPTION 'Broken policy still exists';
  END IF;

  RAISE NOTICE 'Emergency rollback successful - app should work now';
END $$;

COMMIT;

-- ============================================================================
-- NEXT STEPS
-- ============================================================================
-- Run migration 005 to properly fix the event_members visibility issue
-- without causing infinite recursion
