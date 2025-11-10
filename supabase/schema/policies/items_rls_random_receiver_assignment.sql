-- RLS Policy updates for items table to support random assignment modes
-- Combined mode (giver+receiver): All members see all items (collaborative planning)
-- Single modes: Restricted visibility based on assignment
-- Claim details remain private via claims RLS policy

-- Drop existing items SELECT policy and recreate with updated logic
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
      AND (
        -- For combined random assignment (giver + receiver): all members see all items
        -- This enables collaborative gift planning while keeping claims private
        (
          l.random_assignment_enabled = true
          AND l.random_receiver_assignment_enabled = true
        )
        -- OR user is list creator/admin/owner (always see all items)
        OR l.created_by = auth.uid()
        OR em.role = 'admin'
        OR EXISTS (
          SELECT 1 FROM public.events e
          WHERE e.id = l.event_id AND e.owner_id = auth.uid()
        )
        -- OR for random giver assignment ONLY (no receiver): only see assigned items
        OR (
          l.random_assignment_enabled = true
          AND COALESCE(l.random_receiver_assignment_enabled, false) = false
          AND EXISTS (
            SELECT 1 FROM public.claims c
            WHERE c.item_id = items.id
              AND c.assigned_to = auth.uid()
          )
        )
        -- OR for random receiver assignment ONLY (no giver): hide from assigned recipients
        OR (
          COALESCE(l.random_assignment_enabled, false) = false
          AND l.random_receiver_assignment_enabled = true
          AND items.assigned_recipient_id != auth.uid()
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
'Users can see items in lists they can view. For combined random assignment (giver+receiver), all members see all items for collaborative planning. For single random assignment modes, visibility is restricted. List creators/admins/owners always see all items.';
