-- Migration 018: Add Update and Delete Policies
-- Date: 2025-10-07
-- Description: Add missing UPDATE and DELETE policies for events, lists, and items
--              Allows creator/owner OR last remaining member to edit/delete

BEGIN;

-- ============================================================================
-- HELPER FUNCTION: Check if user is the last member of an event
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_last_event_member(e_id uuid, u_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT
    -- User must be a member
    EXISTS (
      SELECT 1 FROM public.event_members
      WHERE event_id = e_id AND user_id = u_id
    )
    AND
    -- Only one member total
    (SELECT count(*) FROM public.event_members WHERE event_id = e_id) = 1
$$;

-- ============================================================================
-- EVENTS POLICIES
-- ============================================================================

-- Allow update if: owner OR last remaining member
CREATE POLICY "update events by owner or last member"
  ON public.events FOR UPDATE
  USING (
    owner_id = auth.uid()
    OR public.is_last_event_member(id, auth.uid())
  );

-- Allow delete if: owner OR last remaining member
CREATE POLICY "delete events by owner or last member"
  ON public.events FOR DELETE
  USING (
    owner_id = auth.uid()
    OR public.is_last_event_member(id, auth.uid())
  );

-- ============================================================================
-- LISTS POLICIES
-- ============================================================================

-- Allow update if: list creator OR last remaining event member
CREATE POLICY "update lists by creator or last member"
  ON public.lists FOR UPDATE
  USING (
    created_by = auth.uid()
    OR public.is_last_event_member(event_id, auth.uid())
  );

-- Allow delete if: list creator OR last remaining event member
CREATE POLICY "delete lists by creator or last member"
  ON public.lists FOR DELETE
  USING (
    created_by = auth.uid()
    OR public.is_last_event_member(event_id, auth.uid())
  );

-- ============================================================================
-- LIST_RECIPIENTS POLICIES
-- ============================================================================

-- Allow update if: list creator OR last remaining event member
CREATE POLICY "update list_recipients by creator or last member"
  ON public.list_recipients FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.lists l
      WHERE l.id = list_id
        AND (
          l.created_by = auth.uid()
          OR public.is_last_event_member(l.event_id, auth.uid())
        )
    )
  );

-- Allow delete if: list creator OR last remaining event member
CREATE POLICY "delete list_recipients by creator or last member"
  ON public.list_recipients FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.lists l
      WHERE l.id = list_id
        AND (
          l.created_by = auth.uid()
          OR public.is_last_event_member(l.event_id, auth.uid())
        )
    )
  );

-- ============================================================================
-- ITEMS POLICIES
-- ============================================================================

-- Allow update if: item creator OR list creator OR last remaining event member
CREATE POLICY "update items by creator or last member"
  ON public.items FOR UPDATE
  USING (
    created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.lists l
      WHERE l.id = list_id
        AND (
          l.created_by = auth.uid()
          OR public.is_last_event_member(l.event_id, auth.uid())
        )
    )
  );

-- Allow delete if: item creator OR list creator OR last remaining event member
CREATE POLICY "delete items by creator or last member"
  ON public.items FOR DELETE
  USING (
    created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.lists l
      WHERE l.id = list_id
        AND (
          l.created_by = auth.uid()
          OR public.is_last_event_member(l.event_id, auth.uid())
        )
    )
  );

-- ============================================================================
-- EVENT_MEMBERS POLICIES
-- ============================================================================

-- Allow users to delete their own membership (leave event)
CREATE POLICY "delete own event membership"
  ON public.event_members FOR DELETE
  USING (user_id = auth.uid());

-- Note: We intentionally DO NOT allow updating event_members
-- Role changes should be done through admin functions in the future

COMMIT;

-- Verification queries
DO $$
DECLARE
  v_events_update_count int;
  v_events_delete_count int;
  v_lists_update_count int;
  v_lists_delete_count int;
  v_items_update_count int;
  v_items_delete_count int;
BEGIN
  -- Count policies
  SELECT count(*) INTO v_events_update_count
  FROM pg_policies
  WHERE tablename = 'events' AND cmd = 'UPDATE';

  SELECT count(*) INTO v_events_delete_count
  FROM pg_policies
  WHERE tablename = 'events' AND cmd = 'DELETE';

  SELECT count(*) INTO v_lists_update_count
  FROM pg_policies
  WHERE tablename = 'lists' AND cmd = 'UPDATE';

  SELECT count(*) INTO v_lists_delete_count
  FROM pg_policies
  WHERE tablename = 'lists' AND cmd = 'DELETE';

  SELECT count(*) INTO v_items_update_count
  FROM pg_policies
  WHERE tablename = 'items' AND cmd = 'UPDATE';

  SELECT count(*) INTO v_items_delete_count
  FROM pg_policies
  WHERE tablename = 'items' AND cmd = 'DELETE';

  RAISE NOTICE '✅ Migration 018 completed successfully';
  RAISE NOTICE '   - Added is_last_event_member() helper function';
  RAISE NOTICE '   - Events: % UPDATE policies, % DELETE policies', v_events_update_count, v_events_delete_count;
  RAISE NOTICE '   - Lists: % UPDATE policies, % DELETE policies', v_lists_update_count, v_lists_delete_count;
  RAISE NOTICE '   - Items: % UPDATE policies, % DELETE policies', v_items_update_count, v_items_delete_count;
  RAISE NOTICE '   - Users can now leave events (delete their own membership)';
  RAISE NOTICE '   - Last remaining members can edit/delete all event data';
END $$;
