-- Detailed step-by-step diagnosis of list_claims_for_user
-- Replace the UUIDs with your actual values

-- First, get your user ID
SELECT auth.uid() as my_user_id;

-- Get all items in the list
SELECT id, name, list_id FROM items WHERE list_id = '4ed8df20-1eac-4a6a-ad34-282483043e43';

-- Get all claims for those items
SELECT
  c.id as claim_id,
  c.item_id,
  c.claimer_id,
  c.assigned_to,
  i.name as item_name
FROM claims c
JOIN items i ON i.id = c.item_id
WHERE i.list_id = '4ed8df20-1eac-4a6a-ad34-282483043e43';

-- Check if you can view the list
SELECT
  l.id,
  l.name,
  public.can_view_list(l.id, auth.uid()) as can_view,
  l.created_by,
  l.created_by = auth.uid() as is_creator,
  auth.uid() as current_user
FROM lists l
WHERE l.id = '4ed8df20-1eac-4a6a-ad34-282483043e43';

-- Check list configuration
SELECT
  l.id,
  l.name,
  COALESCE(l.random_assignment_enabled, false) as random_assignment_enabled,
  COALESCE(l.random_receiver_assignment_enabled, false) as random_receiver_assignment_enabled,
  (COALESCE(l.random_assignment_enabled, false) = true AND
   COALESCE(l.random_receiver_assignment_enabled, false) = true) as is_collaborative
FROM lists l
WHERE l.id = '4ed8df20-1eac-4a6a-ad34-282483043e43';

-- Check if you're a recipient
SELECT
  lr.list_id,
  lr.user_id,
  auth.uid() as current_user,
  lr.user_id = auth.uid() as is_recipient
FROM list_recipients lr
WHERE lr.list_id = '4ed8df20-1eac-4a6a-ad34-282483043e43'
  AND lr.user_id = auth.uid();

-- Now test the actual logic from list_claims_for_user step by step
WITH visible_items AS (
  SELECT i.id AS item_id, i.list_id
  FROM public.items i
  WHERE i.list_id = '4ed8df20-1eac-4a6a-ad34-282483043e43'
    AND public.can_view_list(i.list_id, auth.uid())
)
SELECT
  'visible_items' as step,
  COUNT(*) as count,
  array_agg(item_id) as item_ids
FROM visible_items;

-- Test list_info CTE
WITH visible_items AS (
  SELECT i.id AS item_id, i.list_id
  FROM public.items i
  WHERE i.list_id = '4ed8df20-1eac-4a6a-ad34-282483043e43'
    AND public.can_view_list(i.list_id, auth.uid())
),
list_info AS (
  SELECT DISTINCT
    vi.list_id,
    l.created_by,
    l.event_id,
    COALESCE(l.random_assignment_enabled, false) as random_assignment_enabled,
    COALESCE(l.random_receiver_assignment_enabled, false) as random_receiver_assignment_enabled,
    (COALESCE(l.random_assignment_enabled, false) = true AND
     COALESCE(l.random_receiver_assignment_enabled, false) = true) as is_collaborative,
    (
      l.created_by = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.event_members em
        WHERE em.event_id = l.event_id
          AND em.user_id = auth.uid()
          AND em.role = 'admin'
      )
      OR EXISTS (
        SELECT 1 FROM public.events e
        WHERE e.id = l.event_id AND e.owner_id = auth.uid()
      )
    ) as is_admin,
    EXISTS (
      SELECT 1 FROM public.list_recipients lr
      WHERE lr.list_id = l.id AND lr.user_id = auth.uid()
    ) as is_recipient,
    auth.uid() as current_user
  FROM visible_items vi
  INNER JOIN public.lists l ON l.id = vi.list_id
)
SELECT * FROM list_info;

-- Test the final query with all conditions shown
WITH visible_items AS (
  SELECT i.id AS item_id, i.list_id
  FROM public.items i
  WHERE i.list_id = '4ed8df20-1eac-4a6a-ad34-282483043e43'
    AND public.can_view_list(i.list_id, auth.uid())
),
list_info AS (
  SELECT DISTINCT
    vi.list_id,
    l.created_by,
    l.event_id,
    COALESCE(l.random_assignment_enabled, false) as random_assignment_enabled,
    COALESCE(l.random_receiver_assignment_enabled, false) as random_receiver_assignment_enabled,
    (COALESCE(l.random_assignment_enabled, false) = true AND
     COALESCE(l.random_receiver_assignment_enabled, false) = true) as is_collaborative,
    (
      l.created_by = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.event_members em
        WHERE em.event_id = l.event_id
          AND em.user_id = auth.uid()
          AND em.role = 'admin'
      )
      OR EXISTS (
        SELECT 1 FROM public.events e
        WHERE e.id = l.event_id AND e.owner_id = auth.uid()
      )
    ) as is_admin,
    EXISTS (
      SELECT 1 FROM public.list_recipients lr
      WHERE lr.list_id = l.id AND lr.user_id = auth.uid()
    ) as is_recipient
  FROM visible_items vi
  INNER JOIN public.lists l ON l.id = vi.list_id
)
SELECT
  c.item_id,
  c.claimer_id,
  i.name as item_name,
  auth.uid() as current_user,
  -- Show which rule matches
  c.claimer_id = auth.uid() as rule1_own_claim,
  li.is_admin as rule2_is_admin,
  (li.is_collaborative = true AND c.assigned_to = auth.uid()) as rule3_collaborative,
  (li.random_assignment_enabled = false AND li.random_receiver_assignment_enabled = false AND li.is_recipient = false) as rule4_non_random,
  (li.random_assignment_enabled = true AND li.is_collaborative = false AND li.is_recipient = false AND c.assigned_to = auth.uid()) as rule5_single_random,
  -- Show the WHERE clause result
  (
    c.claimer_id = auth.uid()
    OR li.is_admin = true
    OR (li.is_collaborative = true AND c.assigned_to = auth.uid())
    OR (li.random_assignment_enabled = false AND li.random_receiver_assignment_enabled = false AND li.is_recipient = false)
    OR (li.random_assignment_enabled = true AND li.is_collaborative = false AND li.is_recipient = false AND c.assigned_to = auth.uid())
  ) as should_be_visible
FROM public.claims c
INNER JOIN visible_items vi ON vi.item_id = c.item_id
INNER JOIN list_info li ON li.list_id = vi.list_id
INNER JOIN items i ON i.id = c.item_id;
