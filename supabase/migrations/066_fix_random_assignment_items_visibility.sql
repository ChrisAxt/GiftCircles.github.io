-- Migration: Fix items visibility for random assignment lists
-- Date: 2025-01-21
-- Description: Fix RLS policy to allow members to see items in random assignment lists
--              before assignment execution, and only their assigned items after execution

BEGIN;

-- ============================================================================
-- Fix items_select_with_receiver_assignment policy
-- ============================================================================

DROP POLICY IF EXISTS "items_select_with_receiver_assignment" ON public.items;

CREATE POLICY "items_select_with_receiver_assignment"
ON public.items
AS PERMISSIVE
FOR SELECT
USING (
  EXISTS (
    SELECT 1
    FROM public.lists l
    JOIN public.event_members em ON em.event_id = l.event_id
    WHERE l.id = items.list_id
      AND em.user_id = (SELECT auth.uid())
      AND public.can_view_list(l.id, (SELECT auth.uid()))
      AND (
        -- For combined random assignment (giver + receiver): all members see all items
        (
          l.random_assignment_enabled = true
          AND l.random_receiver_assignment_enabled = true
        )
        -- OR user is list creator/admin/owner (always see all items)
        OR l.created_by = (SELECT auth.uid())
        OR em.role = 'admin'
        OR EXISTS (
          SELECT 1 FROM public.events e
          WHERE e.id = l.event_id AND e.owner_id = (SELECT auth.uid())
        )
        -- OR for random giver assignment ONLY:
        -- - See all items if assignment hasn't been executed yet
        -- - See only assigned items if assignment has been executed
        OR (
          l.random_assignment_enabled = true
          AND COALESCE(l.random_receiver_assignment_enabled, false) = false
          AND (
            -- Assignment not executed yet: see all items
            l.random_assignment_executed_at IS NULL
            OR
            -- Assignment executed: see only items assigned to this user
            EXISTS (
              SELECT 1 FROM public.claims c
              WHERE c.item_id = items.id
                AND c.assigned_to = (SELECT auth.uid())
            )
          )
        )
        -- OR for random receiver assignment ONLY: hide from assigned recipients
        OR (
          COALESCE(l.random_assignment_enabled, false) = false
          AND l.random_receiver_assignment_enabled = true
          AND items.assigned_recipient_id != (SELECT auth.uid())
        )
        -- OR for non-random lists: see all items
        OR (
          COALESCE(l.random_assignment_enabled, false) = false
          AND COALESCE(l.random_receiver_assignment_enabled, false) = false
        )
      )
  )
);

COMMENT ON POLICY "items_select_with_receiver_assignment" ON public.items IS
'Users can see items in lists they can view. For combined random assignment (giver+receiver), all members see all items. For random giver assignment ONLY: all members see items before assignment execution, but only assigned items after execution. For random receiver assignment ONLY: recipients cannot see their assigned items. List creators/admins/owners always see all items.';

-- Log completion
DO $$
BEGIN
  RAISE NOTICE 'Fixed items RLS policy for random assignment lists';
  RAISE NOTICE '- Members can now see items before assignment execution';
  RAISE NOTICE '- Members see only assigned items after execution';
END;
$$;

COMMIT;
