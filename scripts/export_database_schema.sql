-- ============================================================================
-- Database Schema Export Script
-- ============================================================================
-- This script exports all tables, policies, functions, indexes, constraints,
-- and other database objects for review and verification.
--
-- Usage:
--   psql $DATABASE_URL -f scripts/export_database_schema.sql > schema_export.txt
-- ============================================================================

\echo '============================================================================'
\echo 'DATABASE SCHEMA EXPORT'
\echo '============================================================================'
\echo ''

-- ============================================================================
-- 1. TABLES
-- ============================================================================
\echo '1. TABLES'
\echo '============================================================================'
SELECT
  schemaname,
  tablename,
  tableowner,
  rowsecurity as rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

\echo ''
\echo '--- Table Columns ---'
SELECT
  table_name,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
ORDER BY table_name, ordinal_position;

\echo ''
\echo ''

-- ============================================================================
-- 2. CONSTRAINTS (Primary Keys, Foreign Keys, Unique, Check)
-- ============================================================================
\echo '2. CONSTRAINTS'
\echo '============================================================================'
SELECT
  conrelid::regclass AS table_name,
  conname AS constraint_name,
  CASE contype
    WHEN 'p' THEN 'PRIMARY KEY'
    WHEN 'f' THEN 'FOREIGN KEY'
    WHEN 'u' THEN 'UNIQUE'
    WHEN 'c' THEN 'CHECK'
    ELSE contype::text
  END AS constraint_type,
  pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
ORDER BY table_name, constraint_type, constraint_name;

\echo ''
\echo ''

-- ============================================================================
-- 3. INDEXES
-- ============================================================================
\echo '3. INDEXES'
\echo '============================================================================'
SELECT
  schemaname,
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

\echo ''
\echo ''

-- ============================================================================
-- 4. RLS POLICIES
-- ============================================================================
\echo '4. RLS POLICIES'
\echo '============================================================================'
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

\echo ''
\echo ''

-- ============================================================================
-- 5. FUNCTIONS
-- ============================================================================
\echo '5. FUNCTIONS'
\echo '============================================================================'
SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_arguments(p.oid) AS arguments,
  pg_get_functiondef(p.oid) AS definition,
  CASE
    WHEN p.prosecdef THEN 'SECURITY DEFINER'
    ELSE 'SECURITY INVOKER'
  END AS security,
  pg_catalog.array_to_string(p.proconfig, ', ') AS config
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
ORDER BY p.proname, p.oid;

\echo ''
\echo ''

-- ============================================================================
-- 6. TRIGGERS
-- ============================================================================
\echo '6. TRIGGERS'
\echo '============================================================================'
SELECT
  n.nspname AS schemaname,
  c.relname AS tablename,
  t.tgname AS triggername,
  pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'public'
  AND NOT t.tgisinternal
ORDER BY c.relname, t.tgname;

\echo ''
\echo ''

-- ============================================================================
-- 7. VIEWS
-- ============================================================================
\echo '7. VIEWS'
\echo '============================================================================'
SELECT
  schemaname,
  viewname,
  viewowner,
  definition
FROM pg_views
WHERE schemaname = 'public'
ORDER BY viewname;

\echo ''
\echo ''

-- ============================================================================
-- 8. MATERIALIZED VIEWS
-- ============================================================================
\echo '8. MATERIALIZED VIEWS'
\echo '============================================================================'
SELECT
  schemaname,
  matviewname,
  matviewowner,
  ispopulated,
  definition
FROM pg_matviews
WHERE schemaname = 'public'
ORDER BY matviewname;

\echo ''
\echo ''

-- ============================================================================
-- 9. SEQUENCES
-- ============================================================================
\echo '9. SEQUENCES'
\echo '============================================================================'
SELECT
  schemaname,
  sequencename,
  sequenceowner
FROM pg_sequences
WHERE schemaname = 'public'
ORDER BY sequencename;

\echo ''
\echo ''

-- ============================================================================
-- 10. EXTENSIONS
-- ============================================================================
\echo '10. EXTENSIONS'
\echo '============================================================================'
SELECT
  extname,
  extversion,
  nspname AS schema
FROM pg_extension
JOIN pg_namespace ON pg_extension.extnamespace = pg_namespace.oid
ORDER BY extname;

\echo ''
\echo ''

-- ============================================================================
-- 11. TYPES (Custom Types)
-- ============================================================================
\echo '11. CUSTOM TYPES'
\echo '============================================================================'
SELECT
  n.nspname AS schema_name,
  t.typname AS type_name,
  CASE t.typtype
    WHEN 'e' THEN 'ENUM'
    WHEN 'c' THEN 'COMPOSITE'
    WHEN 'd' THEN 'DOMAIN'
    ELSE t.typtype::text
  END AS type_category,
  CASE t.typtype
    WHEN 'e' THEN (
      SELECT string_agg(e.enumlabel, ', ' ORDER BY e.enumsortorder)
      FROM pg_enum e
      WHERE e.enumtypid = t.oid
    )
    ELSE NULL
  END AS enum_values
FROM pg_type t
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'public'
  AND t.typtype IN ('e', 'c', 'd')
ORDER BY type_name;

\echo ''
\echo ''

-- ============================================================================
-- 12. TABLE SIZES
-- ============================================================================
\echo '12. TABLE SIZES'
\echo '============================================================================'
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
  pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
  pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename)) AS indexes_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

\echo ''
\echo ''

-- ============================================================================
-- 13. MIGRATION HISTORY
-- ============================================================================
\echo '13. MIGRATION HISTORY'
\echo '============================================================================'
SELECT
  version,
  name,
  applied_at
FROM supabase_migrations.schema_migrations
ORDER BY version;

\echo ''
\echo ''

-- ============================================================================
-- 14. SECURITY SUMMARY
-- ============================================================================
\echo '14. SECURITY SUMMARY'
\echo '============================================================================'
\echo 'RLS Enabled Tables:'
SELECT
  tablename,
  rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND rowsecurity = true
ORDER BY tablename;

\echo ''
\echo 'Tables WITHOUT RLS (should be empty or system tables only):'
SELECT
  tablename
FROM pg_tables
WHERE schemaname = 'public'
  AND rowsecurity = false
ORDER BY tablename;

\echo ''
\echo 'SECURITY DEFINER Functions:'
SELECT
  p.proname AS function_name,
  pg_get_function_arguments(p.oid) AS arguments,
  pg_catalog.array_to_string(p.proconfig, ', ') AS config
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef = true
ORDER BY p.proname;

\echo ''
\echo ''

-- ============================================================================
-- 15. PERFORMANCE SUMMARY
-- ============================================================================
\echo '15. PERFORMANCE SUMMARY'
\echo '============================================================================'
\echo 'Index Usage (most used indexes):'
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan AS scans,
  idx_tup_read AS tuples_read,
  idx_tup_fetch AS tuples_fetched
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC
LIMIT 20;

\echo ''
\echo 'Unused Indexes (consider removing):'
SELECT
  schemaname,
  tablename,
  indexname
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND idx_scan = 0
  AND indexname NOT LIKE '%_pkey'
ORDER BY tablename, indexname;

\echo ''
\echo ''

-- ============================================================================
-- END OF EXPORT
-- ============================================================================
\echo '============================================================================'
\echo 'EXPORT COMPLETE'
\echo '============================================================================'
