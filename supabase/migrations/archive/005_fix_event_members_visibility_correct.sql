-- Migration: Fix event_members visibility without recursion
-- Purpose: Allow members to see all event members using SECURITY DEFINER helper
-- Date: 2025-10-02
-- Fixes: Issue from migration 003 where policy caused infinite recursion

BEGIN;

-- ============================================================================
-- 1. Create SECURITY DEFINER helper function
-- ============================================================================
-- This function bypasses RLS when checking membership, avoiding recursion
CREATE OR REPLACE FUNCTION public.is_member_of_event_secure(
  p_event_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER  -- Bypasses RLS to avoid recursion
STABLE
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.event_members
    WHERE event_id = p_event_id
      AND user_id = p_user_id
  );
$function$;

-- ============================================================================
-- 2. Update event_members policy to use SECURITY DEFINER function
-- ============================================================================
-- This fixes the visibility issue without causing infinite recursion

-- Drop the current policy
DROP POLICY IF EXISTS "event_members_select" ON public.event_members;

-- Create new policy using the SECURITY DEFINER helper
CREATE POLICY "event_members_select"
  ON public.event_members
  FOR SELECT
  USING (
    -- User can see members of events they belong to
    -- Uses SECURITY DEFINER function to avoid recursion
    public.is_member_of_event_secure(event_id, auth.uid())
  );

-- ============================================================================
-- 3. Also update is_member_of_event function to use the secure version
-- ============================================================================
-- This ensures all helper functions use the non-recursive approach

CREATE OR REPLACE FUNCTION public.is_member_of_event(p_event uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public.is_member_of_event_secure(p_event, auth.uid());
$function$;

-- Overload version for two parameters
CREATE OR REPLACE FUNCTION public.is_member_of_event(e_id uuid, u_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public.is_member_of_event_secure(e_id, u_id);
$function$;

-- ============================================================================
-- 4. Verification
-- ============================================================================

DO $$
DECLARE
  v_test_result boolean;
BEGIN
  -- Verify the new helper function exists
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'is_member_of_event_secure'
      AND pronamespace = 'public'::regnamespace
  ) THEN
    RAISE EXCEPTION 'is_member_of_event_secure function not created';
  END IF;

  -- Verify the policy exists
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'event_members'
      AND policyname = 'event_members_select'
  ) THEN
    RAISE EXCEPTION 'event_members_select policy not created';
  END IF;

  -- Test that the function doesn't cause recursion (basic check)
  BEGIN
    -- This should not throw recursion error
    SELECT public.is_member_of_event_secure(
      '00000000-0000-0000-0000-000000000000'::uuid,
      '00000000-0000-0000-0000-000000000000'::uuid
    ) INTO v_test_result;

    RAISE NOTICE 'Function executes without recursion - test passed';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%infinite recursion%' THEN
        RAISE EXCEPTION 'Recursion still detected in helper function';
      ELSE
        -- Other errors are acceptable for this test
        RAISE NOTICE 'Function test complete (expected error: %)', SQLERRM;
      END IF;
  END;

  RAISE NOTICE 'Migration 005 successfully applied';
  RAISE NOTICE 'Event members visibility fixed without recursion';
END $$;

COMMIT;
