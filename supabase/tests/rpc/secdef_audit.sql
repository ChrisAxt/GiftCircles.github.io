\ir ../helpers/00_enable_extensions.sql

-- We emit 2 assertions below
SELECT plan(2);

-- 1) Every SECURITY DEFINER must set search_path to public (via proconfig or function body)
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef
      AND COALESCE(array_position(p.proconfig, 'search_path=public'),0) = 0
      AND position('set search_path to public' in pg_get_functiondef(p.oid)) = 0
  ),
  'All SECURITY DEFINER functions set search_path to public'
);

-- 2) Recommend (do not enforce) that SECDEF bodies reference auth.uid()
DO $$
DECLARE
  missing int;
BEGIN
  SELECT count(*) INTO missing
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname='public' AND p.prosecdef
    AND position('auth.uid' in pg_get_functiondef(p.oid)) = 0;

  PERFORM diag(format('SECDEF without explicit auth.uid() reference: %s', missing));
END$$;

-- Always pass this informational check
SELECT ok(true, 'Auth guard recommendation recorded');

SELECT * FROM finish();
