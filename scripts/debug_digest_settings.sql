-- Debug why digests aren't being sent

-- 1. Check your digest settings
SELECT
    p.id,
    p.display_name,
    p.notification_digest_enabled,
    p.digest_frequency,
    p.digest_time_hour as configured_hour,
    p.digest_day_of_week,
    p.timezone,
    public.is_pro(p.id) as is_pro,
    (SELECT COUNT(*) FROM public.push_tokens pt WHERE pt.user_id = p.id) as push_token_count
FROM public.profiles p
WHERE p.notification_digest_enabled = true;

-- 2. Check timezone conversion - what hour is it NOW in your timezone?
SELECT
    p.display_name,
    p.timezone,
    NOW() as utc_now,
    NOW() AT TIME ZONE p.timezone as local_now,
    EXTRACT(HOUR FROM NOW())::int as current_utc_hour,
    EXTRACT(HOUR FROM (NOW() AT TIME ZONE p.timezone))::int as current_local_hour,
    p.digest_time_hour as configured_hour,
    CASE
        WHEN EXTRACT(HOUR FROM (NOW() AT TIME ZONE p.timezone))::int = p.digest_time_hour
        THEN 'MATCHES - Should send now!'
        ELSE 'Does not match (local=' || EXTRACT(HOUR FROM (NOW() AT TIME ZONE p.timezone))::int || ', configured=' || p.digest_time_hour || ')'
    END as status
FROM public.profiles p
WHERE p.notification_digest_enabled = true;

-- 3. Check recent activity in the last 24 hours
SELECT
    COUNT(*) as activity_count,
    MIN(created_at) as first_activity,
    MAX(created_at) as last_activity
FROM public.daily_activity_log
WHERE created_at >= NOW() - INTERVAL '24 hours';

-- 4. Check activity breakdown by user
SELECT
    p.display_name,
    p.id,
    COUNT(dal.id) as activity_count,
    ARRAY_AGG(DISTINCT dal.activity_type) as activity_types,
    MIN(dal.created_at) as first_activity,
    MAX(dal.created_at) as last_activity
FROM public.daily_activity_log dal
JOIN public.profiles p ON p.id = dal.user_id
WHERE dal.created_at >= NOW() - INTERVAL '24 hours'
GROUP BY p.display_name, p.id
ORDER BY activity_count DESC;

-- 5. Check if Pro tier is blocking you
SELECT
    p.display_name,
    p.notification_digest_enabled,
    public.is_pro(p.id) as is_pro,
    CASE
        WHEN NOT public.is_pro(p.id) THEN 'NOT PRO - Digests require Pro tier!'
        ELSE 'Pro tier active'
    END as pro_status
FROM public.profiles p
WHERE p.notification_digest_enabled = true;

-- 6. Manually test digest generation for current hour
SELECT public.generate_and_send_daily_digests(NULL) as digests_queued;

-- 7. Check what was just queued
SELECT
    p.display_name,
    nq.title,
    nq.body,
    nq.sent,
    nq.created_at
FROM public.notification_queue nq
JOIN public.profiles p ON p.id = nq.user_id
WHERE nq.data->>'type' = 'digest'
ORDER BY nq.created_at DESC
LIMIT 5;
