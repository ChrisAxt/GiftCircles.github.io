-- Check if trigger_daily_digest function exists and what it does

-- List all digest-related functions
SELECT
    p.proname as function_name,
    pg_get_functiondef(p.oid) as function_definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname ILIKE '%digest%'
ORDER BY p.proname;
