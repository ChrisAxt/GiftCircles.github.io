-- Test Notification Triggers
-- This script helps you test if notifications are being queued correctly

-- ============================================
-- SETUP: Replace these with your actual IDs
-- ============================================
\set user1_id 'YOUR_USER_1_ID'
\set user2_id 'YOUR_USER_2_ID'
\set event_id 'YOUR_EVENT_ID'

-- ============================================
-- Test 1: Check if users have push tokens
-- ============================================
\echo '\n=== Test 1: Push Tokens Check ==='
SELECT
  user_id,
  token,
  platform,
  created_at
FROM public.push_tokens
WHERE user_id IN (:'user1_id', :'user2_id');

-- If no tokens, you need to enable push notifications in the app first!

-- ============================================
-- Test 2: Manually insert a test list
-- ============================================
\echo '\n=== Test 2: Creating Test List ==='

-- Clear any existing test data
DELETE FROM public.lists
WHERE name = 'TEST NOTIFICATION LIST';

-- Insert a test list (this should trigger notify_new_list)
INSERT INTO public.lists (event_id, name, created_by)
VALUES (:'event_id', 'TEST NOTIFICATION LIST', :'user1_id')
RETURNING id, name, created_by;

-- Check if notification was queued
\echo '\nChecking notification queue...'
SELECT
  id,
  user_id,
  title,
  body,
  data->>'type' as notification_type,
  sent,
  created_at
FROM public.notification_queue
WHERE title LIKE '%TEST NOTIFICATION LIST%'
ORDER BY created_at DESC
LIMIT 5;

-- ============================================
-- Test 3: Manually insert a test item
-- ============================================
\echo '\n=== Test 3: Creating Test Item ==='

-- Get the test list ID
DO $$
DECLARE
  v_list_id uuid;
BEGIN
  SELECT id INTO v_list_id
  FROM public.lists
  WHERE name = 'TEST NOTIFICATION LIST'
  LIMIT 1;

  IF v_list_id IS NOT NULL THEN
    -- Insert a test item (this should trigger notify_new_item)
    INSERT INTO public.items (list_id, name, created_by)
    VALUES (v_list_id, 'TEST ITEM FOR NOTIFICATIONS', :'user1_id');

    RAISE NOTICE 'Test item created in list %', v_list_id;
  ELSE
    RAISE NOTICE 'Test list not found - run Test 2 first';
  END IF;
END $$;

-- Check if notification was queued
\echo '\nChecking notification queue...'
SELECT
  id,
  user_id,
  title,
  body,
  data->>'type' as notification_type,
  sent,
  created_at
FROM public.notification_queue
WHERE title LIKE '%TEST ITEM%'
ORDER BY created_at DESC
LIMIT 5;

-- ============================================
-- Test 4: Manually insert a test claim
-- ============================================
\echo '\n=== Test 4: Creating Test Claim ==='

-- Get the test item ID
DO $$
DECLARE
  v_item_id uuid;
  v_existing_claim uuid;
BEGIN
  SELECT id INTO v_item_id
  FROM public.items
  WHERE name = 'TEST ITEM FOR NOTIFICATIONS'
  LIMIT 1;

  IF v_item_id IS NOT NULL THEN
    -- Check if already claimed
    SELECT id INTO v_existing_claim
    FROM public.claims
    WHERE item_id = v_item_id AND claimer_id = :'user2_id';

    IF v_existing_claim IS NOT NULL THEN
      RAISE NOTICE 'Item already claimed, deleting old claim first';
      DELETE FROM public.claims WHERE id = v_existing_claim;
    END IF;

    -- Insert a test claim (this should trigger notify_new_claim)
    INSERT INTO public.claims (item_id, claimer_id)
    VALUES (v_item_id, :'user2_id');

    RAISE NOTICE 'Test claim created for item %', v_item_id;
  ELSE
    RAISE NOTICE 'Test item not found - run Test 3 first';
  END IF;
END $$;

-- Check if notification was queued
\echo '\nChecking notification queue...'
SELECT
  id,
  user_id,
  title,
  body,
  data->>'type' as notification_type,
  sent,
  created_at
FROM public.notification_queue
WHERE title = 'Item Claimed'
ORDER BY created_at DESC
LIMIT 5;

-- ============================================
-- Test 5: Check all notifications queued
-- ============================================
\echo '\n=== Test 5: All Queued Notifications ==='
SELECT
  id,
  user_id,
  title,
  body,
  data->>'type' as notification_type,
  sent,
  created_at
FROM public.notification_queue
ORDER BY created_at DESC
LIMIT 20;

-- ============================================
-- Test 6: Manually trigger push notification send
-- ============================================
\echo '\n=== Test 6: Trigger Push Notification Processing ==='
\echo 'To manually send the queued notifications, run:'
\echo 'SELECT public.trigger_push_notifications();'
\echo '\nOr call the edge function directly:'
\echo 'POST https://YOUR_PROJECT.supabase.co/functions/v1/send-push-notifications'

-- ============================================
-- Cleanup
-- ============================================
\echo '\n=== Cleanup ==='
\echo 'To clean up test data, run:'
\echo 'DELETE FROM public.lists WHERE name = ''TEST NOTIFICATION LIST'';'
\echo '\nNote: This will cascade delete the test items and claims too.'
