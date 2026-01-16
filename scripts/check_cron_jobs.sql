-- ============================================
-- Check Cron Jobs in Database
-- ============================================
-- This script checks what cron jobs are currently scheduled

-- ============================================
-- List all scheduled cron jobs
-- ============================================
SELECT
    jobid,
    schedule,
    command,
    nodename,
    nodeport,
    database,
    username,
    active,
    jobname
FROM cron.job
ORDER BY jobid;

-- ============================================
-- Check for digest-related cron jobs
-- ============================================
-- SELECT
--     jobid,
--     schedule,
--     command,
--     active,
--     jobname
-- FROM cron.job
-- WHERE command ILIKE '%digest%'
--    OR jobname ILIKE '%digest%';

-- ============================================
-- Check recent cron job runs
-- ============================================
-- SELECT
--     j.jobname,
--     jr.runid,
--     jr.job_pid,
--     jr.database,
--     jr.status,
--     jr.return_message,
--     jr.start_time,
--     jr.end_time
-- FROM cron.job_run_details jr
-- JOIN cron.job j ON j.jobid = jr.jobid
-- WHERE jr.start_time >= NOW() - INTERVAL '24 hours'
-- ORDER BY jr.start_time DESC
-- LIMIT 20;

-- ============================================
-- Check if pg_cron extension is enabled
-- ============================================
-- SELECT
--     extname,
--     extversion,
--     extnamespace::regnamespace AS schema
-- FROM pg_extension
-- WHERE extname = 'pg_cron';

-- ============================================
-- Summary of expected vs actual jobs
-- ============================================
-- Based on migration 014_setup_cron_jobs.sql, you should have:
-- 1. process-push-notifications (every minute: * * * * *)
-- 2. check-purchase-reminders (daily at 9 AM: 0 9 * * *)
-- 3. cleanup-old-notifications (daily at 3 AM: 0 3 * * *)
-- 4. cleanup-old-reminders (daily at 3 AM: 0 3 * * *)
-- 5. [MISSING?] generate-daily-digests (hourly or specific time)
--
-- Compare the output above with this list to see what is missing.
