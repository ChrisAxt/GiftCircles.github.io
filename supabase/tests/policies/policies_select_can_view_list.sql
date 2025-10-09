\ir ../helpers/00_enable_extensions.sql
\ir ../helpers/02_seed_minimal.sql

BEGIN;

-- We will run exactly 2 assertions.
SELECT plan(2);

-- Ensure there is at least ONE list on "Test Event".
-- Impersonate an ADMIN (helper is SECURITY DEFINER, bypasses RLS safely).
SELECT set_config(
  'request.jwt.claims',
  json_build_object('sub', public._test_admin_for_event_title('Test Event')::text,
                    'role','authenticated')::text,
  true
);
SELECT pg_catalog.set_config('role','authenticated',true);

WITH ev AS (
  SELECT id FROM public.events WHERE title = 'Test Event' LIMIT 1
)
SELECT public._test_create_list_for_event(ev.id, 'Test List', 'event'::list_visibility)
FROM ev
WHERE NOT EXISTS (
  SELECT 1 FROM public.lists l WHERE l.event_id = ev.id
);

-- (1) MEMBER can see lists in Test Event
SELECT set_config(
  'request.jwt.claims',
  json_build_object('sub', public._test_any_member_for_event_title('Test Event')::text,
                    'role','authenticated')::text,
  true
);
SELECT pg_catalog.set_config('role','authenticated',true);

WITH counts AS (
  SELECT
    (SELECT count(*)
       FROM public.lists l
       JOIN public.events e ON e.id = l.event_id
      WHERE e.title='Test Event') AS visible_lists
)
SELECT ok( (visible_lists >= 1), 'member can see lists in Test Event')
FROM counts;

-- (2) OUTSIDER cannot see NON-PUBLIC lists from Test Event
SELECT set_config(
  'request.jwt.claims',
  json_build_object('sub', gen_random_uuid()::text, 'role','authenticated')::text,
  true
);
SELECT pg_catalog.set_config('role','authenticated',true);

WITH counts AS (
  SELECT
    (SELECT count(*)
       FROM public.lists l
       JOIN public.events e ON e.id = l.event_id
      WHERE e.title='Test Event'
        AND COALESCE(l.visibility::text,'event') <> 'public') AS non_public_visible
)
SELECT is(non_public_visible::text, '0',
          'outsider cannot see non-public lists in Test Event')
FROM counts;

-- Report & rollback (keep DB clean for the next test file).
SELECT * FROM finish();
ROLLBACK;
