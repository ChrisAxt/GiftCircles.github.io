-- Check if notification triggers are set up correctly

-- 1. Check if triggers exist
SELECT
  trigger_name,
  event_manipulation,
  event_object_table,
  action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND trigger_name LIKE '%notify%'
ORDER BY event_object_table, trigger_name;

-- Expected triggers:
-- - trigger_notify_new_list (on lists, AFTER INSERT)
-- - trigger_notify_new_item (on items, AFTER INSERT)
-- - trigger_notify_new_claim (on claims, AFTER INSERT)

-- 2. Check if trigger functions exist
SELECT
  proname as function_name,
  prosrc as function_body
FROM pg_proc
WHERE proname LIKE 'notify_%'
  AND pronamespace = 'public'::regnamespace;

-- Expected functions:
-- - notify_new_list()
-- - notify_new_item()
-- - notify_new_claim()

-- 3. Check notification queue table
SELECT
  count(*) as total_notifications,
  count(*) FILTER (WHERE sent = false) as unsent_notifications,
  count(*) FILTER (WHERE sent = true) as sent_notifications
FROM public.notification_queue;

-- 4. Check recent notifications by type
SELECT
  data->>'type' as notification_type,
  count(*) as count,
  max(created_at) as last_created
FROM public.notification_queue
GROUP BY data->>'type'
ORDER BY count DESC;

-- 5. Test: Check if you have push tokens registered
-- Replace with your user ID
\echo '\n=== Your Push Tokens ==='
\echo 'To check your push tokens, run:'
\echo 'SELECT * FROM public.push_tokens WHERE user_id = ''YOUR_USER_ID''::uuid;'

-- 6. Sample query to see recent notifications
\echo '\n=== Recent Notifications ==='
SELECT
  id,
  title,
  body,
  data->>'type' as type,
  sent,
  created_at
FROM public.notification_queue
ORDER BY created_at DESC
LIMIT 10;
