-- Migration: Fix backfill_event_member_stats for collaborative mode
-- Date: 2025-01-20
-- Description: Update the backfill function to also handle collaborative mode correctly

BEGIN;

CREATE OR REPLACE FUNCTION public.backfill_event_member_stats()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- For each event member, calculate their stats
  -- Include collaborative mode claims (where user is both giver and recipient)

  INSERT INTO event_member_stats (event_id, user_id, total_claims, unpurchased_claims)
  SELECT
    em.event_id,
    em.user_id,
    COALESCE(COUNT(c.id), 0) as total_claims,
    COALESCE(COUNT(c.id) FILTER (WHERE c.purchased = false), 0) as unpurchased_claims
  FROM event_members em
  LEFT JOIN lists l ON l.event_id = em.event_id
  LEFT JOIN items i ON i.list_id = l.id
  LEFT JOIN claims c ON c.item_id = i.id AND c.claimer_id = em.user_id
  LEFT JOIN list_recipients lr ON lr.list_id = l.id AND lr.user_id = em.user_id
  WHERE
    -- Include claims in collaborative mode
    (
      COALESCE(l.random_assignment_enabled, false) = true
      AND COALESCE(l.random_receiver_assignment_enabled, false) = true
    )
    -- OR include claims where user is NOT a recipient
    OR lr.list_id IS NULL
  GROUP BY em.event_id, em.user_id
  ON CONFLICT (event_id, user_id) DO UPDATE SET
    total_claims = EXCLUDED.total_claims,
    unpurchased_claims = EXCLUDED.unpurchased_claims,
    updated_at = now();
END;
$$;

COMMENT ON FUNCTION public.backfill_event_member_stats() IS
'Backfills event_member_stats table with existing claim data including collaborative mode. Can be run to fix existing stats.';

-- Run backfill to fix existing stats
SELECT backfill_event_member_stats();

COMMIT;
