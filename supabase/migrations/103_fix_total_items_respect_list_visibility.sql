-- Migration: Fix total_items in events_for_current_user to respect list visibility
-- Created: 2025-11-27
-- Purpose: The total_items count was including items from lists the user cannot see
--
-- Issue: The counts CTE counted ALL items in the event regardless of list visibility.
--        This caused the event card to show incorrect item counts (e.g., showing 3 items
--        when the user can only see 1 item from lists they have access to).
--
-- Fix: Update counts CTE to only count items from lists the user can view using can_view_list()
--      This matches the logic used for claim_counts and EventDetailScreen's item counting.

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
    -- FIXED: Only count items from lists the user can view
    SELECT
      l.event_id,
      count(DISTINCT l.id) AS list_count,
      count(i.id) AS total_items
    FROM lists l
    LEFT JOIN items i ON i.list_id = l.id
    WHERE
      -- User can view this list (respects visibility, exclusions, etc.)
      public.can_view_list(l.id, (SELECT uid FROM me)) = true
    GROUP BY l.event_id
  ),
  claim_counts AS (
    -- Count CLAIMED ITEMS from ALL visible lists (not just lists I created)
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
-- Updated counts CTE (lines 46-55) to add WHERE clause:
-- - public.can_view_list(l.id, (SELECT uid FROM me)) = true
--
-- This ensures total_items only includes items from lists the user has permission to see.
-- The fix makes EventListScreen item counts match EventDetailScreen's item counting logic.
--
-- Before: Counted ALL items in the event (including hidden/excluded lists)
-- After: Only counts items from lists user can view (respecting visibility/exclusions)
