-- Fix events_for_current_user to show ALL visible claims, not just on user's own lists
--
-- Problem: The function only counts claims on lists created by the current user.
-- This is wrong - it should count claims on ALL lists the user can view.
--
-- Solution: Remove the created_by filter and count claims on all visible lists.

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
  rownum integer
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
    CROSS JOIN me
    WHERE em.user_id = me.uid
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
    -- Count claims on ALL lists the user can view (not just lists they created)
    SELECT
      l.event_id,
      COUNT(c.id) AS claimed_count
    FROM lists l
    JOIN items i ON i.list_id = l.id
    LEFT JOIN claims c ON c.item_id = i.id
    CROSS JOIN me
    WHERE (
      -- Can view if: created by user
      l.created_by = me.uid
      -- OR user is a recipient
      OR EXISTS (
        SELECT 1 FROM list_recipients lr
        WHERE lr.list_id = l.id AND lr.user_id = me.uid
      )
      -- OR visibility is 'event' and user is event member
      OR (
        l.visibility = 'event'
        AND EXISTS (
          SELECT 1 FROM event_members em
          WHERE em.event_id = l.event_id AND em.user_id = me.uid
        )
      )
      -- OR visibility is 'selected' and user is viewer
      OR (
        l.visibility = 'selected'
        AND EXISTS (
          SELECT 1 FROM list_viewers lv
          WHERE lv.list_id = l.id AND lv.user_id = me.uid
        )
      )
    )
    -- Exclude lists where user is explicitly excluded
    AND NOT EXISTS (
      SELECT 1 FROM list_exclusions le
      WHERE le.list_id = l.id AND le.user_id = me.uid
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
      row_number() OVER (ORDER BY e.created_at ASC NULLS LAST, e.id) AS rownum
    FROM my_events e
    LEFT JOIN counts ct ON ct.event_id = e.id
    LEFT JOIN claim_counts cc ON cc.event_id = e.id
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
    r.rownum
  FROM ranked r
  ORDER BY r.created_at DESC NULLS LAST, r.id;
$function$;

COMMIT;
