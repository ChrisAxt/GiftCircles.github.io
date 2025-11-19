-- Migration 019: Fix Duplicate Policies
-- Date: 2025-10-07
-- Description: Remove old restrictive policies that conflict with migration 018
--              The old policies only allowed creators to edit/delete, blocking last members

BEGIN;

-- ============================================================================
-- DROP OLD RESTRICTIVE POLICIES
-- ============================================================================

-- ITEMS: Drop old creator-only policies
DROP POLICY IF EXISTS "creators can update own items" ON public.items;
DROP POLICY IF EXISTS "creators can delete own items" ON public.items;
DROP POLICY IF EXISTS "items_update" ON public.items;
DROP POLICY IF EXISTS "items_insert" ON public.items;
DROP POLICY IF EXISTS "items_select_visible" ON public.items;

-- LISTS: Drop old creator-only policies if they exist
DROP POLICY IF EXISTS "creators can update own lists" ON public.lists;
DROP POLICY IF EXISTS "creators can delete own lists" ON public.lists;
DROP POLICY IF EXISTS "lists_update" ON public.lists;
DROP POLICY IF EXISTS "lists_delete" ON public.lists;

-- EVENTS: Drop old owner-only policies if they exist
DROP POLICY IF EXISTS "owners can update own events" ON public.events;
DROP POLICY IF EXISTS "owners can delete own events" ON public.events;
DROP POLICY IF EXISTS "events_update" ON public.events;
DROP POLICY IF EXISTS "events_delete" ON public.events;

-- LIST_RECIPIENTS: Drop old policies if they exist
DROP POLICY IF EXISTS "list_recipients_update" ON public.list_recipients;
DROP POLICY IF EXISTS "list_recipients_delete" ON public.list_recipients;

-- ============================================================================
-- VERIFY: The new policies from migration 018 should remain
-- ============================================================================

-- These should still exist:
-- - "update items by creator or last member" (items UPDATE)
-- - "delete items by creator or last member" (items DELETE)
-- - "update lists by creator or last member" (lists UPDATE)
-- - "delete lists by creator or last member" (lists DELETE)
-- - "update events by owner or last member" (events UPDATE)
-- - "delete events by owner or last member" (events DELETE)

COMMIT;

-- Verification
DO $$
DECLARE
  v_items_update_count int;
  v_items_delete_count int;
  v_lists_update_count int;
  v_lists_delete_count int;
  v_events_update_count int;
  v_events_delete_count int;
BEGIN
  -- Count remaining policies
  SELECT count(*) INTO v_items_update_count
  FROM pg_policies WHERE tablename = 'items' AND cmd = 'UPDATE';

  SELECT count(*) INTO v_items_delete_count
  FROM pg_policies WHERE tablename = 'items' AND cmd = 'DELETE';

  SELECT count(*) INTO v_lists_update_count
  FROM pg_policies WHERE tablename = 'lists' AND cmd = 'UPDATE';

  SELECT count(*) INTO v_lists_delete_count
  FROM pg_policies WHERE tablename = 'lists' AND cmd = 'DELETE';

  SELECT count(*) INTO v_events_update_count
  FROM pg_policies WHERE tablename = 'events' AND cmd = 'UPDATE';

  SELECT count(*) INTO v_events_delete_count
  FROM pg_policies WHERE tablename = 'events' AND cmd = 'DELETE';

  RAISE NOTICE '✅ Migration 019 completed successfully';
  RAISE NOTICE '   - Removed duplicate/conflicting policies';
  RAISE NOTICE '   - Items: % UPDATE, % DELETE policies remaining', v_items_update_count, v_items_delete_count;
  RAISE NOTICE '   - Lists: % UPDATE, % DELETE policies remaining', v_lists_update_count, v_lists_delete_count;
  RAISE NOTICE '   - Events: % UPDATE, % DELETE policies remaining', v_events_update_count, v_events_delete_count;
  RAISE NOTICE '';
  RAISE NOTICE '⚠️  If counts are 0, re-run migration 018 to recreate the correct policies';
END $$;
