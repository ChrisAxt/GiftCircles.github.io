-- Test script to verify that list exclusions properly filter out lists and their items
--
-- User ID: 0881f0e0-4254-4f76-b487-99b40dd08f10
-- List ID: 33b31a3e-99fe-464a-bae7-6526013260ad
-- Event ID: 54d44ede-12c2-4729-b3d1-1948700bc495
--
-- Expected behavior: User should NOT see the list or its items in the total count

-- 1. Check if the list exclusion exists
SELECT 'List Exclusion Check:' as test;
SELECT *
FROM list_exclusions
WHERE list_id = '33b31a3e-99fe-464a-bae7-6526013260ad'
  AND user_id = '0881f0e0-4254-4f76-b487-99b40dd08f10';

-- 2. Check the list details
SELECT 'List Details:' as test;
SELECT id, event_id, name, visibility, created_by
FROM lists
WHERE id = '33b31a3e-99fe-464a-bae7-6526013260ad';

-- 3. Test the can_view_list function directly
SELECT 'can_view_list() Function Test:' as test;
SELECT can_view_list(
  '33b31a3e-99fe-464a-bae7-6526013260ad'::uuid,
  '0881f0e0-4254-4f76-b487-99b40dd08f10'::uuid
) as can_view;

-- 4. Check if user is an event member
SELECT 'Event Membership Check:' as test;
SELECT *
FROM event_members
WHERE event_id = '54d44ede-12c2-4729-b3d1-1948700bc495'
  AND user_id = '0881f0e0-4254-4f76-b487-99b40dd08f10';

-- 5. Count items in the excluded list
SELECT 'Item Count in Excluded List:' as test;
SELECT COUNT(*) as item_count
FROM items
WHERE list_id = '33b31a3e-99fe-464a-bae7-6526013260ad';

-- 6. Test what lists the user can see in this event (simulating the RLS policy)
SELECT 'Lists User Can See (via RLS simulation):' as test;
SELECT l.id, l.name, l.visibility, l.created_by,
       can_view_list(l.id, '0881f0e0-4254-4f76-b487-99b40dd08f10'::uuid) as can_view
FROM lists l
WHERE l.event_id = '54d44ede-12c2-4729-b3d1-1948700bc495'
ORDER BY l.created_at DESC;

-- 7. Test what items the user SHOULD see (only from visible lists)
SELECT 'Items User Should See:' as test;
SELECT i.id, i.list_id, l.name as list_name
FROM items i
JOIN lists l ON l.id = i.list_id
WHERE l.event_id = '54d44ede-12c2-4729-b3d1-1948700bc495'
  AND can_view_list(l.id, '0881f0e0-4254-4f76-b487-99b40dd08f10'::uuid) = true;

-- 8. Count total items the user SHOULD see
SELECT 'Total Item Count User Should See:' as test;
SELECT COUNT(*) as total_items
FROM items i
JOIN lists l ON l.id = i.list_id
WHERE l.event_id = '54d44ede-12c2-4729-b3d1-1948700bc495'
  AND can_view_list(l.id, '0881f0e0-4254-4f76-b487-99b40dd08f10'::uuid) = true;

-- 9. Check the current RLS policy on lists table
SELECT 'Current RLS Policy on lists:' as test;
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'lists'
  AND policyname LIKE '%select%';

-- 10. Check the current RLS policy on items table
SELECT 'Current RLS Policy on items:' as test;
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'items'
  AND policyname LIKE '%select%';
