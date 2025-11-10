-- Fix items SELECT policy to allow users to see items they've claimed
--
-- Problem: The current policy only allows viewing items if you're a member of the event.
-- However, when fetching claims with joined item data, users can't see the item details
-- for items they've claimed if they don't have general access to that list.
--
-- Solution: Add an OR condition to allow users to see items they've claimed.

BEGIN;

-- Drop the existing restrictive policy
DROP POLICY IF EXISTS "members can select items in their events" ON public.items;

-- Create a new policy that allows:
-- 1. Viewing items if you're an event member (existing behavior)
-- 2. Viewing items you've claimed (new - for "My Claims" screen with item details)
CREATE POLICY "members can select items in their events"
  ON public.items
  AS PERMISSIVE
  FOR SELECT
  USING (
    -- Can view if you're a member of the event (existing behavior)
    (
      EXISTS (
        SELECT 1
        FROM lists l
        JOIN event_members em ON (em.event_id = l.event_id)
        WHERE l.id = items.list_id
          AND em.user_id = auth.uid()
      )
    )
    OR
    -- Can view if you've claimed this item (new - for "My Claims" screen)
    (
      EXISTS (
        SELECT 1
        FROM claims c
        WHERE c.item_id = items.id
          AND c.claimer_id = auth.uid()
      )
    )
  );

COMMIT;
