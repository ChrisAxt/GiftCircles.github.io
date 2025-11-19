-- Migration: Drop Unused Indexes (OPTIONAL)
-- Date: 2025-10-08
-- Description: Drops indexes that have been verified as unused
--
-- ⚠️  WARNING: Only run this migration AFTER verifying in production that
--    these indexes are truly unused. See verification steps below.

-- ============================================================================
-- VERIFICATION STEPS (Run these BEFORE applying this migration)
-- ============================================================================

-- 1. Check index usage statistics:
/*
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan as times_used,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
AND indexrelname IN ('idx_list_recipients_uid', 'idx_list_exclusions_uid')
ORDER BY indexrelname;
*/

-- 2. Check what columns these indexes cover:
/*
SELECT
    i.indexname,
    t.tablename,
    array_agg(a.attname ORDER BY array_position(ix.indkey, a.attnum)) as columns
FROM pg_indexes i
JOIN pg_class c ON c.relname = i.indexname
JOIN pg_index ix ON ix.indexrelid = c.oid
JOIN pg_class t ON t.oid = ix.indrelid
JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
WHERE i.schemaname = 'public'
AND i.indexrelname IN ('idx_list_recipients_uid', 'idx_list_exclusions_uid')
GROUP BY i.indexname, t.tablename;
*/

-- 3. Check if there are queries that SHOULD use these indexes:
/*
-- For list_recipients.user_id:
EXPLAIN ANALYZE
SELECT * FROM public.list_recipients WHERE user_id = 'some-uuid';

-- For list_exclusions.user_id:
EXPLAIN ANALYZE
SELECT * FROM public.list_exclusions WHERE user_id = 'some-uuid';
*/

-- ============================================================================
-- DECISION CRITERIA
-- ============================================================================

-- Drop the index if ALL of the following are true:
-- ✓ idx_scan = 0 (never used) after running production workload for 1-2 weeks
-- ✓ No queries filter or JOIN on this column
-- ✓ The column is not used in WHERE clauses in your application
-- ✓ The table has other indexes that can handle typical queries
-- ✓ You've verified the RLS policies don't implicitly use this column

-- Keep the index if ANY of the following are true:
-- ✗ Database is new/test (no real usage data yet)
-- ✗ Seasonal queries might use it (e.g., year-end reports)
-- ✗ Future features might need it
-- ✗ The table is small (< 1000 rows) - index overhead is negligible

-- ============================================================================
-- ACTUAL MIGRATION (Uncomment when ready)
-- ============================================================================

-- DROP INDEX IF EXISTS public.idx_list_recipients_uid;
-- DROP INDEX IF EXISTS public.idx_list_exclusions_uid;

-- ============================================================================
-- IMPORTANT NOTES
-- ============================================================================

-- ℹ️  About idx_list_recipients_uid:
-- This index is on list_recipients(user_id).
-- Consider if you ever query:
-- - "Find all list_recipients for a specific user"
-- - JOINs on user_id
-- - RLS policies that filter by user_id
--
-- If yes → Keep the index
-- If no → Can drop it

-- ℹ️  About idx_list_exclusions_uid:
-- This index is on list_exclusions(user_id).
-- We kept this in migration 022 when we dropped list_exclusions_user_idx.
-- The RLS policy "le_select" filters by user_id, so this index IS used.
--
-- Recommendation: DO NOT DROP THIS INDEX
-- The linter may report it as "unused" if you haven't queried the table yet,
-- but the RLS policy will use it once you start querying.

-- Verification query after dropping:
DO $$
DECLARE
  v_idx_count int;
BEGIN
  -- Check if indexes still exist
  SELECT count(*) INTO v_idx_count
  FROM pg_indexes
  WHERE schemaname = 'public'
  AND indexname IN ('idx_list_recipients_uid', 'idx_list_exclusions_uid');

  IF v_idx_count > 0 THEN
    RAISE NOTICE 'ℹ️  Unused indexes still present (commented out by default)';
    RAISE NOTICE 'Review and uncomment DROP statements when ready';
  ELSE
    RAISE NOTICE '✅ Unused indexes have been dropped';
  END IF;
END $$;
