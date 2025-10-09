-- Test Script for Update/Delete Permissions
-- Tests that owners, creators, and last remaining members can edit/delete

-- ============================================================================
-- Setup Test Data
-- ============================================================================

-- Replace these with actual user IDs from your database
\set user1_id 'YOUR_USER_1_ID'
\set user2_id 'YOUR_USER_2_ID'

-- Create test event
INSERT INTO public.events (id, title, owner_id)
VALUES
  ('00000000-0000-0000-0000-000000000001'::uuid, 'Test Event', :'user1_id')
ON CONFLICT (id) DO NOTHING;

-- User1 is auto-joined as admin via trigger

-- Add user2 as member
INSERT INTO public.event_members (event_id, user_id, role)
VALUES
  ('00000000-0000-0000-0000-000000000001'::uuid, :'user2_id', 'giver')
ON CONFLICT DO NOTHING;

-- Create test list by user2
INSERT INTO public.lists (id, event_id, name, created_by)
VALUES
  ('00000000-0000-0000-0000-000000000002'::uuid,
   '00000000-0000-0000-0000-000000000001'::uuid,
   'Test List',
   :'user2_id')
ON CONFLICT (id) DO NOTHING;

-- Create test item by user2
INSERT INTO public.items (id, list_id, name, created_by)
VALUES
  ('00000000-0000-0000-0000-000000000003'::uuid,
   '00000000-0000-0000-0000-000000000002'::uuid,
   'Test Item',
   :'user2_id')
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- Test 1: Check is_last_event_member function
-- ============================================================================

\echo '\n=== Test 1: is_last_event_member() Function ==='

-- Should return FALSE - there are 2 members
SELECT
  public.is_last_event_member(
    '00000000-0000-0000-0000-000000000001'::uuid,
    :'user1_id'
  ) as user1_is_last_member,
  public.is_last_event_member(
    '00000000-0000-0000-0000-000000000001'::uuid,
    :'user2_id'
  ) as user2_is_last_member,
  (SELECT count(*) FROM public.event_members
   WHERE event_id = '00000000-0000-0000-0000-000000000001'::uuid) as total_members;

-- Expected: both should be FALSE, total_members = 2

-- ============================================================================
-- Test 2: Event Owner Can Update/Delete (with 2 members)
-- ============================================================================

\echo '\n=== Test 2: Event Owner Permissions (2 members) ==='

-- Test update as owner (user1)
DO $$
BEGIN
  -- Set auth context to user1
  PERFORM set_config('request.jwt.claim.sub', :'user1_id', true);

  UPDATE public.events
  SET description = 'Updated by owner'
  WHERE id = '00000000-0000-0000-0000-000000000001'::uuid;

  RAISE NOTICE '✅ Owner can update event';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '❌ Owner cannot update event: %', SQLERRM;
END $$;

-- ============================================================================
-- Test 3: List Creator Can Update/Delete
-- ============================================================================

\echo '\n=== Test 3: List Creator Permissions ==='

-- Test update as list creator (user2)
DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', :'user2_id', true);

  UPDATE public.lists
  SET name = 'Updated by creator'
  WHERE id = '00000000-0000-0000-0000-000000000002'::uuid;

  RAISE NOTICE '✅ List creator can update list';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '❌ List creator cannot update list: %', SQLERRM;
END $$;

-- ============================================================================
-- Test 4: Item Creator Can Update/Delete
-- ============================================================================

\echo '\n=== Test 4: Item Creator Permissions ==='

-- Test update as item creator (user2)
DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', :'user2_id', true);

  UPDATE public.items
  SET name = 'Updated by creator'
  WHERE id = '00000000-0000-0000-0000-000000000003'::uuid;

  RAISE NOTICE '✅ Item creator can update item';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '❌ Item creator cannot update item: %', SQLERRM;
END $$;

-- ============================================================================
-- Test 5: Non-Creator Cannot Update (when multiple members)
-- ============================================================================

\echo '\n=== Test 5: Non-Creator Permissions (2 members) ==='

-- Test update as non-creator (user1 trying to update user2's list)
DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', :'user1_id', true);

  UPDATE public.lists
  SET name = 'Attempted update by non-creator'
  WHERE id = '00000000-0000-0000-0000-000000000002'::uuid;

  RAISE NOTICE '❌ Non-creator should NOT be able to update list';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE '✅ Non-creator correctly blocked from updating list';
WHEN OTHERS THEN
  RAISE NOTICE '⚠️  Unexpected error: %', SQLERRM;
END $$;

-- ============================================================================
-- Test 6: Remove User2 to Make User1 Last Member
-- ============================================================================

\echo '\n=== Test 6: Remove User2 (Making User1 Last Member) ==='

DELETE FROM public.event_members
WHERE event_id = '00000000-0000-0000-0000-000000000001'::uuid
  AND user_id = :'user2_id';

-- Check member count
SELECT
  public.is_last_event_member(
    '00000000-0000-0000-0000-000000000001'::uuid,
    :'user1_id'
  ) as user1_is_last_member,
  (SELECT count(*) FROM public.event_members
   WHERE event_id = '00000000-0000-0000-0000-000000000001'::uuid) as total_members;

-- Expected: user1_is_last_member = TRUE, total_members = 1

-- ============================================================================
-- Test 7: Last Member Can Update Event
-- ============================================================================

\echo '\n=== Test 7: Last Member Can Update Event ==='

DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', :'user1_id', true);

  UPDATE public.events
  SET description = 'Updated by last member'
  WHERE id = '00000000-0000-0000-0000-000000000001'::uuid;

  RAISE NOTICE '✅ Last member can update event';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '❌ Last member cannot update event: %', SQLERRM;
END $$;

-- ============================================================================
-- Test 8: Last Member Can Update Lists (Created by Others)
-- ============================================================================

\echo '\n=== Test 8: Last Member Can Update Lists ==='

DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', :'user1_id', true);

  -- User1 updating list created by user2
  UPDATE public.lists
  SET name = 'Updated by last member'
  WHERE id = '00000000-0000-0000-0000-000000000002'::uuid;

  RAISE NOTICE '✅ Last member can update lists created by others';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '❌ Last member cannot update list: %', SQLERRM;
END $$;

-- ============================================================================
-- Test 9: Last Member Can Update Items (Created by Others)
-- ============================================================================

\echo '\n=== Test 9: Last Member Can Update Items ==='

DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', :'user1_id', true);

  -- User1 updating item created by user2
  UPDATE public.items
  SET name = 'Updated by last member'
  WHERE id = '00000000-0000-0000-0000-000000000003'::uuid;

  RAISE NOTICE '✅ Last member can update items created by others';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '❌ Last member cannot update item: %', SQLERRM;
END $$;

-- ============================================================================
-- Test 10: Last Member Can Delete Everything
-- ============================================================================

\echo '\n=== Test 10: Last Member Can Delete ==='

DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', :'user1_id', true);

  -- Delete item
  DELETE FROM public.items
  WHERE id = '00000000-0000-0000-0000-000000000003'::uuid;
  RAISE NOTICE '✅ Last member can delete items';

  -- Delete list
  DELETE FROM public.lists
  WHERE id = '00000000-0000-0000-0000-000000000002'::uuid;
  RAISE NOTICE '✅ Last member can delete lists';

  -- Delete event
  DELETE FROM public.events
  WHERE id = '00000000-0000-0000-0000-000000000001'::uuid;
  RAISE NOTICE '✅ Last member can delete event';

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '❌ Last member cannot delete: %', SQLERRM;
END $$;

-- ============================================================================
-- Test 11: User Can Leave Event
-- ============================================================================

\echo '\n=== Test 11: User Can Leave Event ==='

-- Recreate event for this test
INSERT INTO public.events (id, title, owner_id)
VALUES
  ('00000000-0000-0000-0000-000000000011'::uuid, 'Leave Test Event', :'user1_id')
ON CONFLICT (id) DO UPDATE SET title = 'Leave Test Event';

INSERT INTO public.event_members (event_id, user_id, role)
VALUES
  ('00000000-0000-0000-0000-000000000011'::uuid, :'user2_id', 'giver')
ON CONFLICT DO NOTHING;

-- User2 leaves
DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', :'user2_id', true);

  DELETE FROM public.event_members
  WHERE event_id = '00000000-0000-0000-0000-000000000011'::uuid
    AND user_id = :'user2_id';

  RAISE NOTICE '✅ User can leave event (delete own membership)';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '❌ User cannot leave event: %', SQLERRM;
END $$;

-- ============================================================================
-- Cleanup
-- ============================================================================

\echo '\n=== Cleanup ==='

DELETE FROM public.events
WHERE id IN (
  '00000000-0000-0000-0000-000000000001'::uuid,
  '00000000-0000-0000-0000-000000000011'::uuid
);

\echo '✅ Test data cleaned up'
\echo '\n=== All Tests Complete ==='
