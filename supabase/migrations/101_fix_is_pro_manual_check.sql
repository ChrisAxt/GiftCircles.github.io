-- Migration: Fix is_pro function to check manual_pro column
-- Created: 2025-11-19
-- Purpose: The is_pro() function was updated in migration 100 to only check plan = 'pro',
--          but it should also check the manual_pro column for manually granted Pro access

BEGIN;

-- Update is_pro() to check manual_pro OR plan = 'pro' OR pro_until
CREATE OR REPLACE FUNCTION public.is_pro(p_user uuid, p_at timestamp with time zone DEFAULT now())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT COALESCE(
    (SELECT
      -- User is pro if ANY of these are true:
      manual_pro = true                                    -- Manual override (persists through RevenueCat syncs)
      OR plan = 'pro'                                      -- RevenueCat set to pro
      OR (pro_until IS NOT NULL AND pro_until >= p_at)     -- Pro subscription not expired
     FROM public.profiles
     WHERE id = p_user
    ),
    false
  );
$$;

COMMENT ON FUNCTION public.is_pro IS
'Returns true if user has Pro access. Checks manual_pro flag (manual grants), plan column (RevenueCat), and pro_until expiration.';

COMMIT;

-- Summary:
-- Fixed is_pro() to check manual_pro column again
-- This allows manually granted Pro access to work for digest notifications
-- Users with manual_pro = true will now pass the is_pro() check in generate_and_send_daily_digests()
