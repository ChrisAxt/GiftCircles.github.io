-- Migration: Fix items INSERT RLS for random receiver assignment
-- Date: 2025-01-17
-- Description: The items INSERT was failing when adding items to lists with random receiver assignment
--              because the SELECT policy was blocking items where user is the assigned recipient.
--              We need to allow list creators/admins to see ALL items regardless of recipient assignment.

BEGIN;

-- Drop and recreate the SELECT policy with proper logic
DROP POLICY IF EXISTS "items_select_with_receiver_assignment" ON public.items;
DROP POLICY IF EXISTS "members can select items in their events" ON public.items;

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
      AND em.user_id = auth.uid()
      -- User must be able to view the list
      AND public.can_view_list(l.id, auth.uid())
      -- Apply visibility rules
      AND (
        -- ALWAYS allow list creators/admins/owners to see all items
        l.created_by = auth.uid()
        OR em.role = 'admin'
        OR EXISTS (
          SELECT 1 FROM public.events e
          WHERE e.id = l.event_id AND e.owner_id = auth.uid()
        )
        -- OR apply normal visibility rules for non-admins
        OR (
          -- Case 1: List has no receiver assignment - use standard visibility
          (
            COALESCE(l.random_receiver_assignment_enabled, false) = false
            -- For random giver assignment: only show if assigned to user
            AND (
              l.random_assignment_enabled = false
              OR EXISTS (
                SELECT 1 FROM public.claims c
                WHERE c.item_id = items.id
                  AND c.assigned_to = auth.uid()
              )
            )
          )
          -- Case 2: List HAS receiver assignment - hide from assigned recipients
          OR (
            l.random_receiver_assignment_enabled = true
            -- User should NOT be the assigned recipient (they shouldn't see their own gift)
            AND items.assigned_recipient_id != auth.uid()
            -- User is the giver (has claim assigned to them)
            AND EXISTS (
              SELECT 1 FROM public.claims c
              WHERE c.item_id = items.id
                AND c.assigned_to = auth.uid()
            )
          )
        )
      )
  )
);

COMMENT ON POLICY "items_select_with_receiver_assignment" ON public.items IS
'Users can see items in their event lists. List creators/admins/owners always see all items. For random receiver assignment, recipients don''t see items assigned to them. For random giver assignment, only assigned givers see items.';

COMMIT;
