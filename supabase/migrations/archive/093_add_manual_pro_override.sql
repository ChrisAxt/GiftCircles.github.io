-- Migration: Add manual pro override for testing
-- Created: 2025-11-12
-- Purpose: Allow manually granting pro status that won't be overwritten by RevenueCat sync

BEGIN;

-- ============================================================================
-- 1. Add manual_pro column to profiles
-- ============================================================================

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS manual_pro boolean DEFAULT false;

COMMENT ON COLUMN public.profiles.manual_pro IS
'Manual pro override flag. When true, user is treated as pro regardless of RevenueCat subscription. For testing/admin purposes only.';

-- ============================================================================
-- 2. Update is_pro() function to respect manual_pro flag
-- ============================================================================

-- Drop all versions of is_pro function
DROP FUNCTION IF EXISTS public.is_pro(uuid);
DROP FUNCTION IF EXISTS public.is_pro(uuid, timestamp with time zone);

CREATE OR REPLACE FUNCTION public.is_pro(p_user uuid, p_at timestamp with time zone DEFAULT now())
RETURNS boolean
LANGUAGE sql
STABLE
AS $function$
  select coalesce(
    (select
      -- User is pro if ANY of these are true:
      manual_pro = true                                    -- Manual override
      OR plan = 'pro'                                      -- RevenueCat set to pro
      OR (pro_until is not null and pro_until >= p_at)   -- Pro subscription not expired
     from public.profiles
     where id = p_user
    ),
    false
  );
$function$;

COMMENT ON FUNCTION public.is_pro IS
'Returns true if user is pro. Checks manual_pro flag, plan column, and pro_until expiration.';

-- ============================================================================
-- 3. Create helper function to grant manual pro status
-- ============================================================================

CREATE OR REPLACE FUNCTION public.grant_manual_pro(
  p_user_id uuid,
  p_grant boolean DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.profiles
  SET manual_pro = p_grant
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found: %', p_user_id;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.grant_manual_pro IS
'Manually grant or revoke pro status for a user. This override persists through RevenueCat syncs. Usage: SELECT grant_manual_pro(''user-id'', true);';

COMMIT;

-- Summary of Changes:
-- 1. Added manual_pro column to profiles table (default false)
-- 2. Updated is_pro() function to check manual_pro flag FIRST
-- 3. Added grant_manual_pro() helper function for easy pro grants
--
-- Usage Examples:
--
-- Grant pro to user:
--   SELECT grant_manual_pro('0881f0e0-4254-4f76-b487-99b40dd08f10', true);
--
-- Revoke manual pro:
--   SELECT grant_manual_pro('0881f0e0-4254-4f76-b487-99b40dd08f10', false);
--
-- Check who has manual pro:
--   SELECT id, display_name, manual_pro, plan FROM profiles WHERE manual_pro = true;
--
-- Key Benefits:
-- ✅ RevenueCat can stay fully enabled
-- ✅ Manual pro flag won't be overwritten by RevenueCat sync
-- ✅ Easy to grant/revoke for testing
-- ✅ Works with all existing pro checks (is_pro function)
-- ✅ Can grant to multiple testers easily
