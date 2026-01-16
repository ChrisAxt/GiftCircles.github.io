-- Migration: Manual Event Rollover - Cron Jobs
-- Created: 2026-01-05
-- Purpose: Disable automatic rollover and setup manual rollover cron jobs

BEGIN;

-- ============================================================================
-- 0. Enable pg_cron extension if not already enabled
-- ============================================================================

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
  RAISE NOTICE 'pg_cron extension enabled';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Could not enable pg_cron extension: %. Cron jobs will not be scheduled.', SQLERRM;
END
$$;

-- ============================================================================
-- 1. Unschedule automatic rollover cron job
-- ============================================================================

-- Remove the automatic hourly rollover job if it exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rollover-events-hourly') THEN
    PERFORM cron.unschedule('rollover-events-hourly');
    RAISE NOTICE 'Unscheduled automatic rollover cron job';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Could not unschedule rollover-events-hourly (may not exist): %', SQLERRM;
END
$$;

-- ============================================================================
-- 2. Schedule event flagging job (daily at 2 AM UTC)
-- ============================================================================

DO $body$
BEGIN
  PERFORM cron.schedule(
    'flag-events-needing-rollover',
    '0 2 * * *',
    $$SELECT public.update_events_needing_rollover();$$
  );
  RAISE NOTICE 'Scheduled flag-events-needing-rollover cron job';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Could not schedule flag-events-needing-rollover: %', SQLERRM;
END
$body$;

-- ============================================================================
-- 3. Schedule rollover notification check (hourly)
-- ============================================================================

DO $body$
BEGIN
  PERFORM cron.schedule(
    'check-rollover-notifications',
    '0 * * * *',
    $$SELECT public.check_and_queue_rollover_notifications();$$
  );
  RAISE NOTICE 'Scheduled check-rollover-notifications cron job';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Could not schedule check-rollover-notifications: %', SQLERRM;
END
$body$;

COMMIT;

-- Summary of cron job changes:
-- REMOVED: rollover-events-hourly (automatic rollover)
-- ADDED: flag-events-needing-rollover (daily at 2 AM UTC)
-- ADDED: check-rollover-notifications (hourly)
--
-- Note: pg_cron extension is created if it doesn't exist.
-- If pg_cron is not available in your Supabase project, the cron scheduling
-- will be skipped but the migration will still succeed.
