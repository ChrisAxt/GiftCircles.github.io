-- Migration: Remove manual_pro column and revert is_pro function
-- Created: 2025-11-12
-- Purpose: Remove the manual_pro override system - not needed

BEGIN;

-- ============================================================================
-- 1. Drop manual_pro column
-- ============================================================================

ALTER TABLE public.profiles
DROP COLUMN IF EXISTS manual_pro;

-- ============================================================================
-- 2. Revert is_pro() function to original version
-- ============================================================================

DROP FUNCTION IF EXISTS public.is_pro(uuid);
DROP FUNCTION IF EXISTS public.is_pro(uuid, timestamp with time zone);

CREATE OR REPLACE FUNCTION public.is_pro(p_user uuid, p_at timestamp with time zone DEFAULT now())
RETURNS boolean
LANGUAGE sql
STABLE
AS $function$
  select coalesce(
    (select
      plan = 'pro'                                         -- Plan is set to pro
      OR (pro_until is not null and pro_until >= p_at)   -- Pro subscription not expired
     from public.profiles
     where id = p_user
    ),
    false
  );
$function$;

COMMENT ON FUNCTION public.is_pro IS
'Returns true if user is pro. Checks plan column and pro_until expiration.';

-- ============================================================================
-- 3. Drop grant_manual_pro function
-- ============================================================================

DROP FUNCTION IF EXISTS public.grant_manual_pro(uuid, boolean);

COMMIT;

-- Summary:
-- Removed manual_pro system completely.
-- Use direct UPDATE to set pro status:
--   UPDATE profiles SET plan = 'pro', pro_until = '2026-12-31' WHERE id = 'user-id';
