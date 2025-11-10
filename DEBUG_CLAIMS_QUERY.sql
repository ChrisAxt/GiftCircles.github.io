-- Direct SQL query to debug claim visibility
-- Run this as the user experiencing the issue

-- Step 1: Check what items exist and which have claims
SELECT
  i.id as item_id,
  i.name as item_name,
  i.list_id,
  c.id as claim_id,
  c.claimer_id,
  c.assigned_to,
  auth.uid() as current_user_id,
  l.random_assignment_enabled,
  l.random_receiver_assignment_enabled,
  -- Is this user a list recipient?
  EXISTS (
    SELECT 1 FROM list_recipients lr
    WHERE lr.list_id = l.id AND lr.user_id = auth.uid()
  ) as is_recipient,
  -- Is this user list creator/admin?
  (
    l.created_by = auth.uid()
    OR EXISTS (SELECT 1 FROM event_members em WHERE em.event_id = l.event_id AND em.user_id = auth.uid() AND em.role = 'admin')
    OR EXISTS (SELECT 1 FROM events e WHERE e.id = l.event_id AND e.owner_id = auth.uid())
  ) as is_admin
FROM items i
LEFT JOIN claims c ON c.item_id = i.id
JOIN lists l ON l.id = i.list_id
WHERE i.list_id = '4ed8df20-1eac-4a6a-ad34-282483043e43'  -- Replace with your list ID
ORDER BY i.name;

-- Step 2: Test what list_claims_for_user returns
-- (Get item IDs from step 1 results first)
SELECT * FROM list_claims_for_user(
  ARRAY[
    '9f719827-6db2-43de-a419-6d6e7375aaa3'::uuid,  -- Replace with actual item IDs
    '4c970fef-a73f-4c56-ac52-d55246dc11ce'::uuid   -- from step 1
  ]
);

-- Step 3: Check list configuration
SELECT
  id,
  name,
  random_assignment_enabled,
  random_receiver_assignment_enabled,
  created_by,
  auth.uid() as current_user,
  (random_assignment_enabled = true AND random_receiver_assignment_enabled = true) as is_collaborative
FROM lists
WHERE id = '4ed8df20-1eac-4a6a-ad34-282483043e43';  -- Replace with your list ID
