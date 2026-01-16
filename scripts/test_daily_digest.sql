-- ============================================
-- Test Daily Digest Notification
-- ============================================
-- This script helps you trigger a test daily digest notification
-- Run this in Supabase SQL Editor or via psql

-- ============================================
-- STEP 1: Check your digest settings
-- ============================================
\echo '=== Step 1: Your Digest Settings ==='
SELECT
    p.id as user_id,
    p.email,
    p.notification_digest_enabled,
    p.digest_time_hour,
    p.digest_frequency,
    p.digest_day_of_week,
    p.timezone,
    (SELECT COUNT(*) FROM public.push_tokens pt WHERE pt.user_id = p.id) as push_token_count,
    public.is_pro(p.id) as is_pro
FROM public.profiles p
WHERE p.notification_digest_enabled = true
ORDER BY p.email;

-- ============================================
-- STEP 2: Check recent activity
-- ============================================
\echo '\n=== Step 2: Recent Activity (Last 24 Hours) ==='
SELECT
    dal.user_id,
    p.email,
    COUNT(*) as activity_count,
    ARRAY_AGG(DISTINCT dal.activity_type) as activity_types,
    MIN(dal.created_at) as first_activity,
    MAX(dal.created_at) as last_activity
FROM public.daily_activity_log dal
JOIN public.profiles p ON p.id = dal.user_id
WHERE dal.created_at >= NOW() - INTERVAL '24 hours'
GROUP BY dal.user_id, p.email
ORDER BY activity_count DESC;

-- ============================================
-- STEP 3: Create test activity if needed
-- ============================================
\echo '\n=== Step 3: Create Test Activity (Optional) ==='
\echo 'Uncomment the following block to create test activity:'

/*
-- Replace these variables with your actual IDs
DO $$
DECLARE
    v_user_id uuid := 'YOUR_USER_ID';  -- The user who will receive the digest
    v_event_id uuid := 'YOUR_EVENT_ID'; -- An event they're part of
    v_list_id uuid := 'YOUR_LIST_ID';   -- A list in that event
BEGIN
    -- Create test activity entries
    INSERT INTO public.daily_activity_log (user_id, event_id, list_id, activity_type, activity_data)
    VALUES
        (v_user_id, v_event_id, v_list_id, 'new_list', '{"list_name": "Test List for Digest"}'::jsonb),
        (v_user_id, v_event_id, v_list_id, 'new_item', '{"list_name": "Test List", "item_count": 3}'::jsonb),
        (v_user_id, v_event_id, v_list_id, 'new_claim', '{"list_name": "Test List", "claim_count": 2}'::jsonb);

    RAISE NOTICE 'Created test activity for user %', v_user_id;
END $$;
*/

-- ============================================
-- STEP 4: Trigger digest generation
-- ============================================
\echo '\n=== Step 4: Generate Digest ==='
\echo 'Generating digest for current hour...'

-- Get current hour in UTC (or specify a different hour)
-- To test a specific hour, replace NULL with the hour (0-23)
-- Example: SELECT public.generate_and_send_daily_digests(9);

SELECT public.generate_and_send_daily_digests(NULL) as result;

-- To test for a specific hour (e.g., hour 9):
-- SELECT public.generate_and_send_daily_digests(9);

-- ============================================
-- STEP 5: Check queued notifications
-- ============================================
\echo '\n=== Step 5: Check Queued Digest Notifications ==='
SELECT
    nq.id,
    p.email,
    nq.title,
    nq.body,
    nq.data,
    nq.sent,
    nq.created_at
FROM public.notification_queue nq
JOIN public.profiles p ON p.id = nq.user_id
WHERE nq.data->>'type' = 'digest'
ORDER BY nq.created_at DESC
LIMIT 10;

-- ============================================
-- STEP 6: Manually send queued notifications
-- ============================================
\echo '\n=== Step 6: Send Push Notifications ==='
\echo 'To send the queued notifications, you have two options:'
\echo ''
\echo 'Option A: Call the edge function (via curl or HTTP client):'
\echo 'POST https://YOUR_PROJECT.supabase.co/functions/v1/send-push-notifications'
\echo ''
\echo 'Option B: Call the database trigger function:'

-- This will mark the cron job to run immediately
SELECT cron.schedule('send-push-notifications-manual', '* * * * *', $$
    SELECT net.http_post(
        url := current_setting('app.settings.supabase_url') || '/functions/v1/send-push-notifications',
        headers := jsonb_build_object('Content-Type', 'application/json')
    );
$$);

-- Or simply wait for the cron job to run (it runs every minute)

-- ============================================
-- STEP 7: Verify notifications were sent
-- ============================================
\echo '\n=== Step 7: Check Sent Status ==='
\echo 'Run this after a minute to verify notifications were sent:'

SELECT
    nq.id,
    p.email,
    nq.title,
    LEFT(nq.body, 50) as body_preview,
    nq.sent,
    nq.sent_at,
    nq.created_at
FROM public.notification_queue nq
JOIN public.profiles p ON p.id = nq.user_id
WHERE nq.data->>'type' = 'digest'
  AND nq.created_at >= NOW() - INTERVAL '1 hour'
ORDER BY nq.created_at DESC;

-- ============================================
-- TROUBLESHOOTING
-- ============================================
\echo '\n=== Troubleshooting Tips ==='
\echo '1. No notifications queued?'
\echo '   - Check that notification_digest_enabled = true'
\echo '   - Verify you have a push token (check push_tokens table)'
\echo '   - Ensure you are a Pro user (check is_pro())'
\echo '   - Make sure digest_time_hour matches the hour you tested'
\echo '   - Check that you have activity in daily_activity_log'
\echo ''
\echo '2. Notifications queued but not sent?'
\echo '   - Wait 1 minute for the cron job to run'
\echo '   - Manually call: POST /functions/v1/send-push-notifications'
\echo '   - Check edge function logs in Supabase Dashboard'
\echo ''
\echo '3. Check your timezone conversion:'

-- Show what hour it is in each user's timezone
SELECT
    p.email,
    p.timezone,
    p.digest_time_hour as configured_hour,
    EXTRACT(HOUR FROM (NOW() AT TIME ZONE p.timezone))::integer as current_local_hour,
    CASE
        WHEN EXTRACT(HOUR FROM (NOW() AT TIME ZONE p.timezone))::integer = p.digest_time_hour
        THEN 'MATCHES - Should send now!'
        ELSE 'Does not match'
    END as status
FROM public.profiles p
WHERE p.notification_digest_enabled = true;

-- ============================================
-- QUICK TEST: Force a digest for your user
-- ============================================
\echo '\n=== Quick Test: Force Digest for Specific User ==='
\echo 'Uncomment to manually queue a digest notification:'

/*
-- Replace with your user ID
DO $$
DECLARE
    v_user_id uuid := 'YOUR_USER_ID';
    v_event_name text;
    v_summary text := '';
    v_activity_count int := 0;
BEGIN
    -- Get activity summary
    SELECT
        e.name,
        COUNT(DISTINCT dal.id)
    INTO v_event_name, v_activity_count
    FROM public.daily_activity_log dal
    JOIN public.events e ON e.id = dal.event_id
    WHERE dal.user_id = v_user_id
      AND dal.created_at >= NOW() - INTERVAL '24 hours'
    GROUP BY e.name
    LIMIT 1;

    IF v_activity_count > 0 THEN
        v_summary := format('%s: %s new activities', v_event_name, v_activity_count);
    ELSE
        v_summary := 'Test digest notification (no recent activity)';
    END IF;

    -- Queue the notification
    INSERT INTO public.notification_queue (user_id, title, body, data)
    VALUES (
        v_user_id,
        'Daily Digest',
        v_summary,
        jsonb_build_object(
            'type', 'digest',
            'timestamp', NOW()
        )
    );

    RAISE NOTICE 'Queued digest for user %', v_user_id;
END $$;

-- Now send it
-- Call: POST /functions/v1/send-push-notifications
-- Or wait for the cron job (runs every minute)
*/
