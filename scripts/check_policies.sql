-- Check if migration 018 policies exist

-- Check for the helper function
SELECT EXISTS (
  SELECT 1 FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public'
    AND p.proname = 'is_last_event_member'
) as function_exists;

-- Check all policies on lists table
SELECT
  schemaname,
  tablename,
  policyname,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'lists'
ORDER BY cmd, policyname;

-- Check all policies on events table
SELECT
  schemaname,
  tablename,
  policyname,
  cmd
FROM pg_policies
WHERE tablename = 'events'
ORDER BY cmd, policyname;

-- Check all policies on items table
SELECT
  schemaname,
  tablename,
  policyname,
  cmd
FROM pg_policies
WHERE tablename = 'items'
ORDER BY cmd, policyname;

-- Test the is_last_event_member function with your event
-- Replace with your actual event_id and user_id
DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '=== Test is_last_event_member function ===';
  RAISE NOTICE 'Replace these values with your actual event_id and user_id:';
  RAISE NOTICE 'SELECT public.is_last_event_member(''YOUR_EVENT_ID''::uuid, ''YOUR_USER_ID''::uuid);';
  RAISE NOTICE 'SELECT count(*) FROM public.event_members WHERE event_id = ''YOUR_EVENT_ID''::uuid;';
END $$;
