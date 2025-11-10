-- One-time recalculation of all event_member_stats to fix any stale data
-- This ensures all users have correct stats after we've fixed the triggers

BEGIN;

-- Delete all existing stats
TRUNCATE TABLE event_member_stats;

-- Recalculate stats for all users who have claims
INSERT INTO event_member_stats (event_id, user_id, total_claims, unpurchased_claims, updated_at)
SELECT
  l.event_id,
  c.claimer_id,
  COUNT(c.id) as total_claims,
  COUNT(c.id) FILTER (WHERE c.purchased = false) as unpurchased_claims,
  NOW() as updated_at
FROM claims c
JOIN items i ON i.id = c.item_id
JOIN lists l ON l.id = i.list_id
GROUP BY l.event_id, c.claimer_id
HAVING COUNT(c.id) > 0;

COMMIT;
