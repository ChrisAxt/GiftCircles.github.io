-- Migration: Optimize events_for_current_user RPC to eliminate N+1 queries
-- Date: 2025-01-20
-- Description: Returns events with member details and profile names in a single query
--              to eliminate the 2 additional queries made by EventListScreen.

BEGIN;

-- ============================================================================
-- STEP 1: Create optimized RPC that returns everything
-- ============================================================================

CREATE OR REPLACE FUNCTION public.events_for_current_user_optimized()
RETURNS TABLE(
  id uuid,
  title text,
  event_date date,
  join_code text,
  created_at timestamptz,
  member_count bigint,
  total_items bigint,
  claimed_count bigint,
  accessible boolean,
  rownum integer,
  my_claims bigint,
  my_unpurchased_claims bigint,
  -- New fields to eliminate additional queries
  members jsonb,  -- Array of {user_id, display_name}
  member_user_ids uuid[]  -- For backward compatibility
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
  claims AS (
    -- Show claims on lists created by current user
    SELECT l.event_id, count(DISTINCT c.id) AS claimed_count
    FROM lists l
    JOIN items i ON i.list_id = l.id
    LEFT JOIN claims c ON c.item_id = i.id
    CROSS JOIN me
    WHERE l.created_by = me.uid
    GROUP BY l.event_id
  ),
  event_members_with_profiles AS (
    -- Get all members with their profile names for events user is in
    SELECT
      em.event_id,
      em.user_id,
      COALESCE(p.display_name, '') AS display_name
    FROM event_members em
    LEFT JOIN profiles p ON p.id = em.user_id
    WHERE em.event_id IN (SELECT id FROM my_events)
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
      COALESCE(cl.claimed_count, 0) AS claimed_count,
      COALESCE(ems.total_claims, 0) AS my_claims,
      COALESCE(ems.unpurchased_claims, 0) AS my_unpurchased_claims,
      row_number() OVER (ORDER BY e.created_at ASC NULLS LAST, e.id) AS rownum,
      -- Aggregate members with profile names into JSONB array
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'user_id', emp.user_id,
            'display_name', emp.display_name
          )
        )
        FROM event_members_with_profiles emp
        WHERE emp.event_id = e.id
      ) AS members,
      -- Also provide array of user IDs for backward compatibility
      (
        SELECT array_agg(emp.user_id)
        FROM event_members_with_profiles emp
        WHERE emp.event_id = e.id
      ) AS member_user_ids
    FROM my_events e
    LEFT JOIN counts ct ON ct.event_id = e.id
    LEFT JOIN claims cl ON cl.event_id = e.id
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
    r.my_unpurchased_claims,
    COALESCE(r.members, '[]'::jsonb) AS members,
    COALESCE(r.member_user_ids, ARRAY[]::uuid[]) AS member_user_ids
  FROM ranked r
  ORDER BY r.created_at DESC NULLS LAST, r.id;
$function$;

COMMENT ON FUNCTION public.events_for_current_user_optimized() IS
'Optimized version of events_for_current_user that returns member details and profile names in a single query, eliminating N+1 queries.

Return columns:
- members: JSONB array of event members with format: [{"user_id": "uuid", "display_name": "Name"}]
- member_user_ids: Array of member user IDs for backward compatibility

Use the members field to avoid additional queries to event_members and profiles tables.';

-- ============================================================================
-- STEP 3: Add index for the new query pattern
-- ============================================================================

-- This query pattern accesses event_members -> profiles JOIN
-- Ensure we have an index for fast profile lookups
CREATE INDEX IF NOT EXISTS idx_profiles_id_display_name
ON public.profiles(id)
INCLUDE (display_name);

COMMENT ON INDEX idx_profiles_id_display_name IS
'Covering index for profile lookups in optimized events_for_current_user. Enables index-only scans.';

-- ============================================================================
-- STEP 4: Benchmark queries
-- ============================================================================

-- Log example usage for testing
DO $$
DECLARE
  v_start timestamptz;
  v_end timestamptz;
  v_duration_ms numeric;
BEGIN
  RAISE NOTICE 'Testing optimized events_for_current_user query...';

  -- Test query
  v_start := clock_timestamp();
  PERFORM * FROM public.events_for_current_user_optimized();
  v_end := clock_timestamp();

  v_duration_ms := EXTRACT(EPOCH FROM (v_end - v_start)) * 1000;

  RAISE NOTICE 'Query completed in % ms', round(v_duration_ms, 2);

  IF v_duration_ms > 100 THEN
    RAISE WARNING 'Query took longer than 100ms. Consider running ANALYZE or checking for missing indexes.';
  ELSE
    RAISE NOTICE 'Query performance is good (< 100ms)';
  END IF;
END;
$$;

COMMIT;
