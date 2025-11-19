-- Migration: Fix claimed_count in events_for_current_user to match EventDetailScreen logic
-- Created: 2025-11-12
-- Purpose: Make EventList screen show same claim counts as EventDetail screen
--
-- Issue: EventList only counted claims on lists YOU created, but EventDetail counts
--        claims on ALL visible lists (excluding lists where you're the recipient).
--        This caused confusing discrepancies between the two screens.
--
-- Fix: Update claim_counts CTE to:
--      1. Count claims from ALL lists user can view (respecting privacy/visibility)
--      2. Exclude lists where user is a recipient (gift surprise protection)
--      3. Use same logic as EventDetailScreen's totalClaimsVisible calculation

BEGIN;

DROP FUNCTION IF EXISTS public.events_for_current_user();

CREATE OR REPLACE FUNCTION public.events_for_current_user()
RETURNS TABLE(
  id uuid,
  title text,
  event_date date,
  join_code text,
  created_at timestamp with time zone,
  member_count bigint,
  total_items bigint,
  claimed_count bigint,
  accessible boolean,
  rownum integer,
  my_claims bigint,
  my_unpurchased_claims bigint
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH me AS (
    SELECT auth.uid() AS uid
  ),
  my_events AS (
    SELECT e.*
    FROM events e
    JOIN event_members em ON em.event_id = e.id
    JOIN me ON me.uid = em.user_id
  ),
  counts AS (
    SELECT
      l.event_id,
      count(DISTINCT l.id) AS list_count,
      count(i.id) AS total_items
    FROM lists l
    LEFT JOIN items i ON i.list_id = l.id
    GROUP BY l.event_id
  ),
  claim_counts AS (
    -- NEW LOGIC: Count CLAIMED ITEMS from ALL visible lists (not just lists I created)
    -- Exclude lists where I'm the recipient (to protect gift surprises)
    -- This matches EventDetailScreen's totalClaimsVisible calculation
    SELECT
      l.event_id,
      COUNT(DISTINCT i.id) AS claimed_count
    FROM lists l
    JOIN items i ON i.list_id = l.id
    WHERE
      -- User can view this list (uses can_view_list for privacy/visibility checks)
      public.can_view_list(l.id, (SELECT uid FROM me)) = true
      -- AND user is NOT a recipient on this list (gift surprise protection)
      AND NOT EXISTS (
        SELECT 1 FROM list_recipients lr
        WHERE lr.list_id = l.id AND lr.user_id = (SELECT uid FROM me)
      )
      -- AND item has at least one claim
      AND EXISTS (
        SELECT 1 FROM claims c WHERE c.item_id = i.id
      )
    GROUP BY l.event_id
  ),
  ranked AS (
    SELECT
      e.id,
      e.title,
      e.event_date,
      e.join_code,
      e.created_at,
      (SELECT count(*) FROM event_members em2 WHERE em2.event_id = e.id) AS member_count,
      COALESCE(ct.total_items, 0) AS total_items,
      COALESCE(cc.claimed_count, 0) AS claimed_count,
      COALESCE(ems.total_claims, 0) AS my_claims,
      COALESCE(ems.unpurchased_claims, 0) AS my_unpurchased_claims,
      row_number() OVER (ORDER BY e.created_at ASC NULLS LAST, e.id) AS rownum
    FROM my_events e
    LEFT JOIN counts ct ON ct.event_id = e.id
    LEFT JOIN claim_counts cc ON cc.event_id = e.id
    LEFT JOIN event_member_stats ems ON ems.event_id = e.id AND ems.user_id = (SELECT uid FROM me)
  )
  SELECT
    r.id,
    r.title,
    r.event_date,
    r.join_code,
    r.created_at,
    r.member_count,
    r.total_items,
    r.claimed_count,
    (r.rownum <= public.allowed_event_slots()) AS accessible,
    r.rownum,
    r.my_claims,
    r.my_unpurchased_claims
  FROM ranked r
  ORDER BY r.created_at DESC NULLS LAST, r.id;
$function$;

COMMIT;

-- Summary of Changes:
-- Updated claim_counts CTE (lines 45-66) to:
-- 1. Use can_view_list() to respect privacy/visibility rules
-- 2. Exclude lists where user is a recipient (gift surprise protection)
-- 3. Count claims from ALL visible lists (not just lists created by user)
--
-- This makes EventListScreen claim counts match EventDetailScreen exactly.
--
-- Before: Only counted claims on lists YOU created
-- After: Counts claims on ALL visible lists (excluding lists where you're recipient)
