-- Add my_claims and my_unpurchased_claims back to events_for_current_user
-- These fields are needed for the stats cards in EventListScreen

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
    SELECT
      l.event_id,
      COUNT(c.id) AS claimed_count
    FROM lists l
    JOIN items i ON i.list_id = l.id
    LEFT JOIN claims c ON c.item_id = i.id
    WHERE l.created_by = auth.uid()
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
