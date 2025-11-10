-- Migration: Fix RLS for rate_limit_tracking table
-- Date: 2025-01-20
-- Description: Enable RLS on rate_limit_tracking table to fix security linter warning

BEGIN;

-- Enable RLS on rate_limit_tracking
ALTER TABLE public.rate_limit_tracking ENABLE ROW LEVEL SECURITY;

-- Add RLS policies
-- Only allow server-side functions to access this table
-- Users should not have direct access to rate limit tracking

DROP POLICY IF EXISTS "rate_limit_tracking_no_public_access" ON public.rate_limit_tracking;
CREATE POLICY "rate_limit_tracking_no_public_access"
ON public.rate_limit_tracking
FOR ALL
USING (false)
WITH CHECK (false);

COMMENT ON POLICY "rate_limit_tracking_no_public_access" ON public.rate_limit_tracking IS
'Rate limit tracking is only accessible via SECURITY DEFINER functions. No direct user access allowed.';

-- Log completion
DO $$
BEGIN
  RAISE NOTICE 'RLS enabled on rate_limit_tracking table';
  RAISE NOTICE 'Rate limit tracking is now protected and only accessible via server functions';
END;
$$;

COMMIT;
