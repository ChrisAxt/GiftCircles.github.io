-- Simple smoke test for migration 017 functions
-- Verifies functions exist and basic functionality works

BEGIN;

\echo '=== Migration 017 Function Tests ==='
\echo ''

-- Test 1: Check add_list_recipient function exists
\echo 'Test 1: Checking add_list_recipient exists...'
SELECT CASE
  WHEN EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'add_list_recipient'
  ) THEN '✓ PASS: add_list_recipient function exists'
  ELSE '✗ FAIL: add_list_recipient function not found'
END;

-- Test 2: Check accept_event_invite function exists
\echo 'Test 2: Checking accept_event_invite exists...'
SELECT CASE
  WHEN EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'accept_event_invite'
  ) THEN '✓ PASS: accept_event_invite function exists'
  ELSE '✗ FAIL: accept_event_invite function not found'
END;

-- Test 3: Check accept_event_invite calls can_join_event
\echo 'Test 3: Checking accept_event_invite uses can_join_event...'
SELECT CASE
  WHEN pg_get_functiondef(p.oid) LIKE '%can_join_event%'
  THEN '✓ PASS: accept_event_invite checks free tier limit'
  ELSE '✗ FAIL: accept_event_invite missing can_join_event check'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'accept_event_invite';

-- Test 4: Check notification_queue RLS policies exist
\echo 'Test 4: Checking notification_queue RLS policies...'
SELECT CASE
  WHEN COUNT(*) >= 3
  THEN '✓ PASS: notification_queue has RLS policies (' || COUNT(*) || ' policies)'
  ELSE '✗ FAIL: notification_queue missing RLS policies'
END
FROM pg_policies
WHERE tablename = 'notification_queue' AND schemaname = 'public';

-- Test 5: Check add_list_recipient has better error handling
\echo 'Test 5: Checking add_list_recipient error handling...'
SELECT CASE
  WHEN pg_get_functiondef(p.oid) LIKE '%Invalid email format%'
    AND pg_get_functiondef(p.oid) LIKE '%Not authorized%'
  THEN '✓ PASS: add_list_recipient has proper error messages'
  ELSE '✗ FAIL: add_list_recipient missing error handling'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'add_list_recipient';

\echo ''
\echo '=== All Migration 017 Checks Complete ==='

ROLLBACK;
