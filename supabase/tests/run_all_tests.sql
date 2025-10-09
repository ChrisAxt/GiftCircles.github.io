-- ============================================================================
-- GiftCircles Test Suite Runner
-- Runs all database tests in the correct order
-- ============================================================================

\echo '========================================='
\echo 'GiftCircles Test Suite'
\echo '========================================='
\echo ''

-- Smoke Tests (Quick validation of core functionality)
\echo '--- Running Smoke Tests ---'
\i supabase/tests/smoke/integrity_smoke.sql
\i supabase/tests/smoke/policies_smoke.sql
\i supabase/tests/smoke/rpc_smoke.sql
\echo ''

-- RPC Tests (Function validation)
\echo '--- Running RPC Tests ---'
\i supabase/tests/rpc/rpc_validation.sql
\i supabase/tests/rpc/claim_counts_visibility.sql
\i supabase/tests/rpc/secdef_audit.sql
\i supabase/tests/rpc/rpc_fuzz_validation.sql
\i supabase/tests/rpc/migration_017_tests.sql
\echo ''

-- Policy Tests (RLS validation)
\echo '--- Running Policy Tests ---'
\i supabase/tests/policies/rls_write_matrix.sql
\i supabase/tests/policies/rls_write_denials.sql
\i supabase/tests/policies/policies_select_can_view_list.sql
\i supabase/tests/policies/policies_admin_wrappers.sql
\echo ''

-- Integrity Tests (Foreign keys, cascades, data consistency)
\echo '--- Running Integrity Tests ---'
\i supabase/tests/integrity/rls_and_fk_tests.sql
\i supabase/tests/integrity/cascade_runtime.sql
\echo ''

\echo '========================================='
\echo 'All Tests Complete!'
\echo '========================================='
