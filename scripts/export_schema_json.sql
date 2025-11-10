-- ============================================================================
-- Database Schema Export - JSON Format
-- ============================================================================
-- Exports schema as JSON for easy parsing and review
--
-- Usage:
--   psql $DATABASE_URL -f scripts/export_schema_json.sql -o schema.json
-- ============================================================================

-- Set output format
\t
\a
\f ','

-- Tables with columns
\echo '=== TABLES ==='
SELECT jsonb_pretty(jsonb_agg(
  jsonb_build_object(
    'table_name', tablename,
    'rls_enabled', rowsecurity,
    'columns', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'column_name', column_name,
          'data_type', data_type,
          'is_nullable', is_nullable,
          'column_default', column_default
        ) ORDER BY ordinal_position
      )
      FROM information_schema.columns c
      WHERE c.table_schema = 'public'
        AND c.table_name = t.tablename
    )
  ) ORDER BY tablename
))
FROM pg_tables t
WHERE schemaname = 'public';

\echo ''
\echo '=== CONSTRAINTS ==='
SELECT jsonb_pretty(jsonb_agg(
  jsonb_build_object(
    'table', conrelid::regclass::text,
    'constraint_name', conname,
    'constraint_type', CASE contype
      WHEN 'p' THEN 'PRIMARY KEY'
      WHEN 'f' THEN 'FOREIGN KEY'
      WHEN 'u' THEN 'UNIQUE'
      WHEN 'c' THEN 'CHECK'
      ELSE contype::text
    END,
    'definition', pg_get_constraintdef(oid)
  ) ORDER BY conrelid::regclass::text, conname
))
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace;

\echo ''
\echo '=== INDEXES ==='
SELECT jsonb_pretty(jsonb_agg(
  jsonb_build_object(
    'table', tablename,
    'index_name', indexname,
    'definition', indexdef
  ) ORDER BY tablename, indexname
))
FROM pg_indexes
WHERE schemaname = 'public';

\echo ''
\echo '=== RLS POLICIES ==='
SELECT jsonb_pretty(jsonb_agg(
  jsonb_build_object(
    'table', tablename,
    'policy_name', policyname,
    'permissive', permissive,
    'command', cmd,
    'using_expression', qual,
    'with_check_expression', with_check
  ) ORDER BY tablename, policyname
))
FROM pg_policies
WHERE schemaname = 'public';

\echo ''
\echo '=== FUNCTIONS ==='
SELECT jsonb_pretty(jsonb_agg(
  jsonb_build_object(
    'function_name', proname,
    'arguments', pg_get_function_arguments(oid),
    'return_type', pg_get_function_result(oid),
    'language', (SELECT lanname FROM pg_language WHERE oid = prolang),
    'security', CASE WHEN prosecdef THEN 'DEFINER' ELSE 'INVOKER' END,
    'config', proconfig
  ) ORDER BY proname
))
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace;

\echo ''
\echo '=== TRIGGERS ==='
SELECT jsonb_pretty(jsonb_agg(
  jsonb_build_object(
    'table', c.relname,
    'trigger_name', t.tgname,
    'definition', pg_get_triggerdef(t.oid)
  ) ORDER BY c.relname, t.tgname
))
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relnamespace = 'public'::regnamespace
  AND NOT t.tgisinternal;
