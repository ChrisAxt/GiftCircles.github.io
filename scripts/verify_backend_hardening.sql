-- Backend Hardening Verification Script
-- Run this after applying all migrations to verify success

\echo '==================== BACKEND HARDENING VERIFICATION ===================='
\echo ''

-- ============================================================================
-- 1. Check Foreign Key Constraints
-- ============================================================================
\echo '1. Foreign Key Constraints (expect ~30):'
SELECT COUNT(*) as fk_count
FROM pg_constraint
WHERE contype = 'f'
  AND connamespace = 'public'::regnamespace;
\echo ''

-- ============================================================================
-- 2. Check Performance Indexes
-- ============================================================================
\echo '2. Performance Indexes on RLS-critical tables:'
SELECT
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;
\echo ''

-- ============================================================================
-- 3. Check Security Tables
-- ============================================================================
\echo '3. Security Audit Log table:'
SELECT EXISTS (
  SELECT 1 FROM pg_tables
  WHERE schemaname = 'public'
    AND tablename = 'security_audit_log'
) as audit_log_exists;

\echo '4. Rate Limit Tracking table:'
SELECT EXISTS (
  SELECT 1 FROM pg_tables
  WHERE schemaname = 'public'
    AND tablename = 'rate_limit_tracking'
) as rate_limit_exists;
\echo ''

-- ============================================================================
-- 4. Check RLS Enabled
-- ============================================================================
\echo '5. RLS Status (all should have RLS enabled):'
SELECT
  schemaname,
  tablename,
  rowsecurity as rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    'profiles',
    'events',
    'event_members',
    'lists',
    'items',
    'claims',
    'security_audit_log',
    'rate_limit_tracking'
  )
ORDER BY tablename;
\echo ''

-- ============================================================================
-- 5. Check SECURITY DEFINER Functions
-- ============================================================================
\echo '6. SECURITY DEFINER functions with SET search_path:'
SELECT
  p.proname as function_name,
  pg_get_function_arguments(p.oid) as arguments,
  CASE
    WHEN p.prosecdef THEN 'SECURITY DEFINER'
    ELSE 'SECURITY INVOKER'
  END as security,
  pg_catalog.array_to_string(p.proconfig, ', ') as config
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef = true
ORDER BY p.proname;
\echo ''

-- ============================================================================
-- 6. Test Rate Limiting
-- ============================================================================
\echo '7. Testing rate limiting function:'
SELECT public.check_rate_limit('test_verify', 10, 60) as rate_limit_ok;
\echo ''

-- ============================================================================
-- 7. Check Optimized RPC
-- ============================================================================
\echo '8. Optimized events_for_current_user_optimized function:'
SELECT EXISTS (
  SELECT 1 FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'events_for_current_user_optimized'
) as optimized_rpc_exists;
\echo ''

-- ============================================================================
-- 8. Check Materialized Stats
-- ============================================================================
\echo '9. Event Member Stats table (for claims optimization):'
SELECT EXISTS (
  SELECT 1 FROM pg_tables
  WHERE schemaname = 'public'
    AND tablename = 'event_member_stats'
) as stats_table_exists;

SELECT EXISTS (
  SELECT 1 FROM pg_matviews
  WHERE schemaname = 'public'
    AND matviewname = 'event_member_stats'
) as stats_is_materialized;
\echo ''

-- ============================================================================
-- 9. Check Duplicate Indexes Removed
-- ============================================================================
\echo '10. Duplicate indexes (should NOT exist):'
SELECT indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
    'claims_item_claimer_unique',
    'idx_claims_item_claimer_unique',
    'idx_lists_id_event_created'
  );
\echo 'If empty result above, duplicate indexes successfully removed ✓'
\echo ''

-- ============================================================================
-- 10. Check auth.uid() Optimization in RLS
-- ============================================================================
\echo '11. RLS policies using optimized auth.uid() pattern:'
SELECT
  schemaname,
  tablename,
  policyname,
  CASE
    WHEN qual LIKE '%SELECT auth.uid()%' THEN 'Optimized ✓'
    WHEN qual LIKE '%auth.uid()%' THEN 'Unoptimized (needs fix)'
    ELSE 'No auth.uid()'
  END as optimization_status
FROM pg_policies
WHERE schemaname = 'public'
  AND qual LIKE '%auth.uid()%'
ORDER BY tablename, policyname;
\echo ''

-- ============================================================================
-- 11. Transaction Safety Check
-- ============================================================================
\echo '12. Functions with transaction safety (exception handling):'
SELECT
  p.proname as function_name,
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%EXCEPTION%' THEN 'Has error handling ✓'
    ELSE 'No error handling'
  END as transaction_safety
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'create_list_with_people',
    'assign_items_randomly',
    'delete_item',
    'delete_list'
  )
ORDER BY p.proname;
\echo ''

-- ============================================================================
-- Summary
-- ============================================================================
\echo '==================== VERIFICATION SUMMARY ===================='
\echo ''
\echo 'Expected Results:'
\echo '  1. Foreign keys: ~30'
\echo '  2. Indexes: 15+'
\echo '  3. Security audit log: exists'
\echo '  4. Rate limit tracking: exists'
\echo '  5. RLS enabled: all tables'
\echo '  6. SECURITY DEFINER functions: with SET search_path'
\echo '  7. Rate limiting: working'
\echo '  8. Optimized RPC: exists'
\echo '  9. Stats table: exists'
\echo ' 10. Duplicate indexes: removed'
\echo ' 11. RLS policies: optimized'
\echo ' 12. Transaction safety: exception handling'
\echo ''
\echo 'If all checks pass, backend hardening is complete! ✓'
\echo '================================================================'
