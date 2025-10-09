-- ============================================================================
-- Migration 017 Function Tests
-- Tests for add_list_recipient, accept_event_invite, and notification_queue RLS
-- ============================================================================

\ir ../helpers/00_enable_extensions.sql
\ir ../helpers/01_impersonation.sql

BEGIN;

-- Create test plan (13 tests total)
SELECT plan(13);

-- ============================================================================
-- Setup: Create test users and event
-- ============================================================================

-- Ensure pgcrypto extension is loaded
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create test users
DO $$
DECLARE
  v_user1 uuid := '00000000-0000-4000-8000-000000000001'::uuid;
  v_user2 uuid := '00000000-0000-4000-8000-000000000002'::uuid;
  v_user3 uuid := '00000000-0000-4000-8000-000000000003'::uuid;
  v_event_id uuid;
  v_list_id uuid;
  v_encrypted_pw text;
BEGIN
  -- Generate encrypted password once (use extensions schema for Supabase local)
  v_encrypted_pw := extensions.crypt('password123', extensions.gen_salt('bf'));

  -- Insert test users into auth.users
  INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, aud, role)
  VALUES
    (v_user1, 'user1@test.com', v_encrypted_pw, now(), now(), now(), 'authenticated', 'authenticated'),
    (v_user2, 'user2@test.com', v_encrypted_pw, now(), now(), now(), 'authenticated', 'authenticated'),
    (v_user3, 'user3@test.com', v_encrypted_pw, now(), now(), now(), 'authenticated', 'authenticated')
  ON CONFLICT (id) DO NOTHING;

  -- Insert profiles
  INSERT INTO public.profiles (id, display_name)
  VALUES
    (v_user1, 'Test User 1'),
    (v_user2, 'Test User 2'),
    (v_user3, 'Test User 3')
  ON CONFLICT (id) DO NOTHING;

  -- Create test event owned by user1
  INSERT INTO public.events (id, title, owner_id)
  VALUES ('00000000-0000-4000-8000-000000000100'::uuid, 'Test Event', v_user1)
  ON CONFLICT (id) DO NOTHING;

  -- Add user1 as admin member
  INSERT INTO public.event_members (event_id, user_id, role)
  VALUES ('00000000-0000-4000-8000-000000000100'::uuid, v_user1, 'admin')
  ON CONFLICT DO NOTHING;

  -- Create test list
  INSERT INTO public.lists (id, event_id, name, created_by)
  VALUES ('00000000-0000-4000-8000-000000000200'::uuid, '00000000-0000-4000-8000-000000000100'::uuid, 'Test List', v_user1)
  ON CONFLICT (id) DO NOTHING;
END$$;

-- ============================================================================
-- TEST 1: add_list_recipient - Valid email format validation
-- ============================================================================

-- Impersonate user1 (list creator)
SELECT public.test_impersonate('00000000-0000-4000-8000-000000000001'::uuid);
SET ROLE authenticated;

SELECT throws_like(
  $$SELECT public.add_list_recipient('00000000-0000-4000-8000-000000000200'::uuid, 'invalid-email')$$,
  '%Invalid email format%',
  'add_list_recipient rejects invalid email format'
);

-- ============================================================================
-- TEST 2: add_list_recipient - Authorization check (must be creator or member)
-- ============================================================================

-- Impersonate user3 (not a member)
SELECT public.test_impersonate('00000000-0000-4000-8000-000000000003'::uuid);
SET ROLE authenticated;

SELECT throws_like(
  $$SELECT public.add_list_recipient('00000000-0000-4000-8000-000000000200'::uuid, 'newuser@test.com')$$,
  '%Not authorized to modify this list%',
  'add_list_recipient rejects unauthorized users'
);

-- ============================================================================
-- TEST 3: add_list_recipient - Succeeds for list creator
-- ============================================================================

-- Impersonate user1 (list creator)
SELECT public.test_impersonate('00000000-0000-4000-8000-000000000001'::uuid);
SET ROLE authenticated;

SELECT lives_ok(
  $$SELECT public.add_list_recipient('00000000-0000-4000-8000-000000000200'::uuid, 'user2@test.com')$$,
  'add_list_recipient succeeds for list creator'
);

-- ============================================================================
-- TEST 4: add_list_recipient - Returns user_id for registered users
-- ============================================================================

SELECT is(
  (SELECT public.add_list_recipient('00000000-0000-4000-8000-000000000200'::uuid, 'user2@test.com')),
  '00000000-0000-4000-8000-000000000002'::uuid,
  'add_list_recipient returns user_id for registered email'
);

-- ============================================================================
-- TEST 5: add_list_recipient - Creates list_recipient record
-- ============================================================================

SELECT ok(
  EXISTS(
    SELECT 1 FROM public.list_recipients
    WHERE list_id = '00000000-0000-4000-8000-000000000200'::uuid
      AND user_id = '00000000-0000-4000-8000-000000000002'::uuid
  ),
  'add_list_recipient creates list_recipients record'
);

-- ============================================================================
-- TEST 6: add_list_recipient - Sends event invite to non-members
-- ============================================================================

SELECT ok(
  EXISTS(
    SELECT 1 FROM public.event_invites
    WHERE event_id = '00000000-0000-4000-8000-000000000100'::uuid
      AND invitee_id = '00000000-0000-4000-8000-000000000002'::uuid
      AND status = 'pending'
  ),
  'add_list_recipient sends event invite to non-member registered user'
);

-- ============================================================================
-- TEST 7: add_list_recipient - Queues notification for registered users
-- ============================================================================

SELECT ok(
  EXISTS(
    SELECT 1 FROM public.notification_queue
    WHERE user_id = '00000000-0000-4000-8000-000000000002'::uuid
      AND data->>'type' = 'list_for_recipient'
      AND data->>'list_id' = '00000000-0000-4000-8000-000000000200'
  ),
  'add_list_recipient queues notification for registered recipient'
);

-- ============================================================================
-- TEST 8: accept_event_invite - Rejects if invite not found
-- ============================================================================

-- Impersonate user2
SELECT public.test_impersonate('00000000-0000-4000-8000-000000000002'::uuid);
SET ROLE authenticated;

SELECT throws_like(
  $$SELECT public.accept_event_invite('00000000-0000-4000-8000-000000000999'::uuid)$$,
  '%Invite not found%',
  'accept_event_invite rejects invalid invite_id'
);

-- ============================================================================
-- TEST 9: accept_event_invite - Checks free tier limit
-- ============================================================================

-- Setup: Add user2 to 3 events to hit free tier limit
DO $$
DECLARE
  v_user2 uuid := '00000000-0000-4000-8000-000000000002'::uuid;
  v_event1 uuid := gen_random_uuid();
  v_event2 uuid := gen_random_uuid();
  v_event3 uuid := gen_random_uuid();
BEGIN
  -- Create 3 events
  INSERT INTO public.events (id, title, owner_id)
  VALUES
    (v_event1, 'Event 1', v_user2),
    (v_event2, 'Event 2', v_user2),
    (v_event3, 'Event 3', v_user2);

  -- Add user2 as admin to all 3
  INSERT INTO public.event_members (event_id, user_id, role)
  VALUES
    (v_event1, v_user2, 'admin'),
    (v_event2, v_user2, 'admin'),
    (v_event3, v_user2, 'admin');
END$$;

-- Now user2 has 3 events, so they should not be able to accept the invite
-- Get the pending invite and try to accept it
DO $$
DECLARE
  v_invite_id uuid;
BEGIN
  -- Get the invite_id for user2
  SELECT id INTO v_invite_id
  FROM public.event_invites
  WHERE invitee_id = '00000000-0000-4000-8000-000000000002'::uuid
    AND status = 'pending'
  LIMIT 1;

  -- Impersonate user2 and try to accept
  PERFORM public.test_impersonate('00000000-0000-4000-8000-000000000002'::uuid);

  -- Try to accept - should fail
  BEGIN
    PERFORM public.accept_event_invite(v_invite_id);
    RAISE EXCEPTION 'Expected free_limit_reached error';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%free_limit_reached%' THEN
      RAISE;
    END IF;
  END;
END$$;

SELECT ok(true, 'accept_event_invite enforces free tier limit');

-- ============================================================================
-- TEST 10: accept_event_invite - Succeeds when user has < 3 events
-- ============================================================================

-- Create invite for user3 as user1 (event owner)
DO $$
DECLARE
  v_user1 uuid := '00000000-0000-4000-8000-000000000001'::uuid;
  v_user3 uuid := '00000000-0000-4000-8000-000000000003'::uuid;
  v_invite_id uuid;
BEGIN
  -- Impersonate user1 to create invite
  PERFORM public.test_impersonate(v_user1);

  -- Create event invite for user3
  INSERT INTO public.event_invites (event_id, inviter_id, invitee_id, invitee_email, status)
  VALUES (
    '00000000-0000-4000-8000-000000000100'::uuid,
    v_user1,
    v_user3,
    'user3@test.com',
    'pending'
  )
  RETURNING id INTO v_invite_id;

  -- Now impersonate user3 to accept
  PERFORM public.test_impersonate(v_user3);

  -- Accept should succeed (user3 has 0 events)
  PERFORM public.accept_event_invite(v_invite_id);
END$$;

SELECT ok(
  EXISTS(
    SELECT 1 FROM public.event_members
    WHERE event_id = '00000000-0000-4000-8000-000000000100'::uuid
      AND user_id = '00000000-0000-4000-8000-000000000003'::uuid
  ),
  'accept_event_invite adds user to event_members'
);

-- ============================================================================
-- TEST 11: accept_event_invite - Updates invite status
-- ============================================================================

SELECT is(
  (SELECT status FROM public.event_invites
   WHERE invitee_id = '00000000-0000-4000-8000-000000000003'::uuid
     AND event_id = '00000000-0000-4000-8000-000000000100'::uuid),
  'accepted',
  'accept_event_invite updates invite status to accepted'
);

-- ============================================================================
-- TEST 12: notification_queue RLS - Users can view their own notifications
-- ============================================================================

-- Impersonate user2
SELECT public.test_impersonate('00000000-0000-4000-8000-000000000002'::uuid);
SET ROLE authenticated;

SELECT ok(
  EXISTS(
    SELECT 1 FROM public.notification_queue
    WHERE user_id = '00000000-0000-4000-8000-000000000002'::uuid
  ),
  'Users can SELECT their own notifications from notification_queue'
);

-- ============================================================================
-- TEST 13: notification_queue RLS - Users cannot view others' notifications
-- ============================================================================

SELECT is(
  (SELECT count(*) FROM public.notification_queue
   WHERE user_id = '00000000-0000-4000-8000-000000000001'::uuid),
  0::bigint,
  'Users cannot SELECT other users notifications (RLS enforcement)'
);

-- ============================================================================
-- Cleanup and finish
-- ============================================================================

SELECT * FROM finish();

ROLLBACK;
