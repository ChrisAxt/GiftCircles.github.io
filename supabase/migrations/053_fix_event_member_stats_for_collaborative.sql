-- Migration: Fix event_member_stats for collaborative mode
-- Date: 2025-01-20
-- Description: The recalculate_event_member_stats function excludes claims on lists where
--              user is a recipient. In collaborative mode (both random features enabled),
--              users are BOTH givers and recipients, so this exclusion is wrong.
--
--              Fix: Only exclude recipient claims for non-collaborative lists.

BEGIN;

CREATE OR REPLACE FUNCTION public.recalculate_event_member_stats(
  p_event_id uuid,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_total_claims bigint;
  v_unpurchased_claims bigint;
BEGIN
  -- Calculate claim counts for this user in this event
  -- For collaborative mode (both random features): include all claims
  -- For other modes: exclude claims on lists where user is the recipient

  SELECT
    COUNT(c.id),
    COUNT(c.id) FILTER (WHERE c.purchased = false)
  INTO v_total_claims, v_unpurchased_claims
  FROM claims c
  JOIN items i ON i.id = c.item_id
  JOIN lists l ON l.id = i.list_id
  WHERE l.event_id = p_event_id
    AND c.claimer_id = p_user_id
    AND (
      -- Include claims in collaborative mode (both random features enabled)
      (
        COALESCE(l.random_assignment_enabled, false) = true
        AND COALESCE(l.random_receiver_assignment_enabled, false) = true
      )
      -- OR include claims on non-recipient lists
      OR NOT EXISTS (
        SELECT 1 FROM list_recipients lr
        WHERE lr.list_id = l.id AND lr.user_id = p_user_id
      )
    );

  -- Upsert the stats
  INSERT INTO event_member_stats (event_id, user_id, total_claims, unpurchased_claims, updated_at)
  VALUES (p_event_id, p_user_id, v_total_claims, v_unpurchased_claims, now())
  ON CONFLICT (event_id, user_id)
  DO UPDATE SET
    total_claims = EXCLUDED.total_claims,
    unpurchased_claims = EXCLUDED.unpurchased_claims,
    updated_at = now();
END;
$$;

COMMENT ON FUNCTION public.recalculate_event_member_stats(uuid, uuid) IS
'Recalculates and updates claim statistics for a specific user in a specific event. Includes collaborative mode claims.';

-- Trigger a recalculation for all existing stats to fix current data
DO $$
DECLARE
  v_rec RECORD;
BEGIN
  FOR v_rec IN
    SELECT DISTINCT event_id, user_id
    FROM event_member_stats
  LOOP
    PERFORM recalculate_event_member_stats(v_rec.event_id, v_rec.user_id);
  END LOOP;
END;
$$;

COMMIT;
