-- Investigate how user 0881f0e0-4254-4f76-b487-99b40dd08f10 can access event 54d44ede-12c2-4729-b3d1-1948700bc495
--
-- The user is NOT an event member, yet they report seeing item counts

-- 1. Check all event members
SELECT 'All Event Members:' as test;
SELECT em.user_id, p.display_name, em.role
FROM event_members em
LEFT JOIN profiles p ON p.id = em.user_id
WHERE em.event_id = '54d44ede-12c2-4729-b3d1-1948700bc495';

-- 2. Check if user is a recipient on ANY list in this event
SELECT 'User as Recipient on Lists:' as test;
SELECT lr.list_id, l.name as list_name
FROM list_recipients lr
JOIN lists l ON l.id = lr.list_id
WHERE l.event_id = '54d44ede-12c2-4729-b3d1-1948700bc495'
  AND lr.user_id = '0881f0e0-4254-4f76-b487-99b40dd08f10';

-- 3. Check if user is a viewer on ANY list in this event
SELECT 'User as Viewer on Lists:' as test;
SELECT lv.list_id, l.name as list_name
FROM list_viewers lv
JOIN lists l ON l.id = lv.list_id
WHERE l.event_id = '54d44ede-12c2-4729-b3d1-1948700bc495'
  AND lv.user_id = '0881f0e0-4254-4f76-b487-99b40dd08f10';

-- 4. Check all lists in the event and which ones user can see
SELECT 'All Lists in Event and Visibility:' as test;
SELECT
  l.id,
  l.name,
  l.visibility,
  l.created_by,
  l.created_by = '0881f0e0-4254-4f76-b487-99b40dd08f10' as user_is_creator,
  EXISTS(SELECT 1 FROM list_recipients lr WHERE lr.list_id = l.id AND lr.user_id = '0881f0e0-4254-4f76-b487-99b40dd08f10') as user_is_recipient,
  EXISTS(SELECT 1 FROM list_viewers lv WHERE lv.list_id = l.id AND lv.user_id = '0881f0e0-4254-4f76-b487-99b40dd08f10') as user_is_viewer,
  EXISTS(SELECT 1 FROM list_exclusions le WHERE le.list_id = l.id AND le.user_id = '0881f0e0-4254-4f76-b487-99b40dd08f10') as user_is_excluded,
  can_view_list(l.id, '0881f0e0-4254-4f76-b487-99b40dd08f10'::uuid) as can_view,
  (SELECT COUNT(*) FROM items WHERE list_id = l.id) as item_count
FROM lists l
WHERE l.event_id = '54d44ede-12c2-4729-b3d1-1948700bc495'
ORDER BY l.created_at DESC;

-- 5. Total items user SHOULD see (via can_view_list)
SELECT 'Total Items User Can See:' as test;
SELECT
  COUNT(i.*) as visible_item_count,
  COUNT(DISTINCT i.list_id) as visible_list_count
FROM items i
JOIN lists l ON l.id = i.list_id
WHERE l.event_id = '54d44ede-12c2-4729-b3d1-1948700bc495'
  AND can_view_list(l.id, '0881f0e0-4254-4f76-b487-99b40dd08f10'::uuid) = true;

-- 6. Check if user created the event
SELECT 'Event Details:' as test;
SELECT
  e.id,
  e.name,
  e.owner_id,
  e.owner_id = '0881f0e0-4254-4f76-b487-99b40dd08f10' as user_is_owner
FROM events e
WHERE e.id = '54d44ede-12c2-4729-b3d1-1948700bc495';

-- 7. Test the event_is_accessible RPC function (used by the app)
SELECT 'event_is_accessible() Test:' as test;
SELECT event_is_accessible(
  '54d44ede-12c2-4729-b3d1-1948700bc495'::uuid,
  '0881f0e0-4254-4f76-b487-99b40dd08f10'::uuid
) as is_accessible;
