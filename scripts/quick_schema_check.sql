-- Quick Schema Check (Safe for Supabase Studio SQL Editor)
-- Run this in the SQL editor to get a quick overview

-- ============================================================================
-- TABLES
-- ============================================================================
SELECT 'TABLES' AS section, COUNT(*) AS count
FROM pg_tables WHERE schemaname = 'public'
UNION ALL

-- ============================================================================
-- CONSTRAINTS
-- ============================================================================
SELECT 'CONSTRAINTS' AS section, COUNT(*) AS count
FROM pg_constraint WHERE connamespace = 'public'::regnamespace
UNION ALL

-- ============================================================================
-- INDEXES
-- ============================================================================
SELECT 'INDEXES' AS section, COUNT(*) AS count
FROM pg_indexes WHERE schemaname = 'public'
UNION ALL

-- ============================================================================
-- POLICIES
-- ============================================================================
SELECT 'POLICIES' AS section, COUNT(*) AS count
FROM pg_policies WHERE schemaname = 'public'
UNION ALL

-- ============================================================================
-- FUNCTIONS
-- ============================================================================
SELECT 'FUNCTIONS' AS section, COUNT(*) AS count
FROM pg_proc WHERE pronamespace = 'public'::regnamespace
UNION ALL

-- ============================================================================
-- TRIGGERS
-- ============================================================================
SELECT 'TRIGGERS' AS section, COUNT(*) AS count
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'public' AND NOT t.tgisinternal;

-- ============================================================================
-- DETAILED TABLE LIST
-- ============================================================================
SELECT
  tablename,
  rowsecurity AS rls_enabled,
  (SELECT COUNT(*) FROM pg_policies p WHERE p.tablename = t.tablename) AS policies,
  (SELECT COUNT(*) FROM pg_indexes i WHERE i.tablename = t.tablename) AS indexes
FROM pg_tables t
WHERE schemaname = 'public'
ORDER BY tablename;

-- ============================================================================
-- RLS STATUS
-- ============================================================================
SELECT
  'RLS Enabled' AS status,
  COUNT(*) AS table_count
FROM pg_tables
WHERE schemaname = 'public' AND rowsecurity = true
UNION ALL
SELECT
  'RLS Disabled' AS status,
  COUNT(*) AS table_count
FROM pg_tables
WHERE schemaname = 'public' AND rowsecurity = false;

-- ============================================================================
-- SECURITY DEFINER FUNCTIONS
-- ============================================================================
SELECT
  proname AS function_name,
  pg_get_function_arguments(oid) AS arguments,
  CASE WHEN prosecdef THEN 'DEFINER' ELSE 'INVOKER' END AS security,
  array_to_string(proconfig, ', ') AS config
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND prosecdef = true
ORDER BY proname;
