-- Fix trigger_daily_digest function - remove newlines in JSON headers
-- The function was failing with "invalid input syntax for type json" due to newlines in the Authorization header

BEGIN;

CREATE OR REPLACE FUNCTION public.trigger_daily_digest()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_result int;
BEGIN
  -- Call the generate_and_send_daily_digests function directly
  -- This is simpler and avoids the HTTP call and JSON formatting issues
  SELECT * INTO v_result FROM public.generate_and_send_daily_digests(NULL);

  -- Log the result (optional, for debugging)
  RAISE NOTICE 'Daily digest triggered: % digests queued', v_result;
END;
$$;

COMMENT ON FUNCTION public.trigger_daily_digest IS
'Trigger function called by cron to generate daily digests. Calls generate_and_send_daily_digests directly.';

COMMIT;
