\ir ../helpers/00_enable_extensions.sql
\ir ../helpers/02_seed_minimal.sql

BEGIN;

-- run SQL and return SQLSTATE or 'ok'
CREATE OR REPLACE FUNCTION public.test_try(sql text)
RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE sql;
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RETURN sqlstate;
END; $$;

SELECT plan(4);

-- (1) outsider cannot INSERT list -> expect 42501
SELECT set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid()::text, 'role', 'authenticated')::text, true);
SELECT pg_catalog.set_config('role','authenticated',true);

SELECT is(
  public.test_try($$
    INSERT INTO public.lists(event_id, name, visibility, created_by)
    VALUES ((SELECT id FROM public.events WHERE title='Test Event' LIMIT 1),
            'X outsider','event', gen_random_uuid());
  $$),
  '42501',
  'outsider cannot insert list'
);

-- (2) non-admin member cannot DELETE event -> expect 42501; if none exists, skip
WITH nonadmin AS (
  SELECT em.user_id AS uid
  FROM public.event_members em
  JOIN public.events e ON e.id = em.event_id
  WHERE e.title='Test Event' AND em.role <> 'admin' LIMIT 1
), has_nonadmin AS (SELECT EXISTS (SELECT 1 FROM nonadmin) present)
SELECT CASE WHEN present THEN
  set_config('request.jwt.claims',
    json_build_object('sub', (SELECT uid FROM nonadmin)::text, 'role', 'authenticated')::text, true)
ELSE
  set_config('request.jwt.claims',
    json_build_object('sub', gen_random_uuid()::text, 'role', 'authenticated')::text, true)
END FROM has_nonadmin;

SELECT pg_catalog.set_config('role','authenticated',true);

WITH has_nonadmin AS (
  SELECT EXISTS (
    SELECT 1 FROM public.event_members em
    JOIN public.events e ON e.id = em.event_id
    WHERE e.title='Test Event' AND em.role <> 'admin'
  ) present
)
SELECT CASE WHEN present THEN
  is(
    public.test_try($$
      DELETE FROM public.events
       WHERE id = (SELECT id FROM public.events WHERE title='Test Event' LIMIT 1);
    $$),
    '42501',
    'member cannot delete event'
  )
ELSE
  ok(true, 'no non-admin member; skipping delete-denial check')
END
FROM has_nonadmin;

-- (3) admin can UPDATE event -> expect ok
SELECT set_config('request.jwt.claims',
  json_build_object('sub',
    (SELECT em.user_id
       FROM public.event_members em
       JOIN public.events e ON e.id=em.event_id
      WHERE e.title='Test Event' AND em.role='admin' LIMIT 1)::text,
    'role','authenticated')::text, true);
SELECT pg_catalog.set_config('role','authenticated',true);

SELECT is(
  public.test_try($$
    UPDATE public.events SET title = title
     WHERE id = (SELECT id FROM public.events WHERE title='Test Event' LIMIT 1);
  $$),
  'ok',
  'admin can update event'
);

-- (4) outsider cannot UPDATE an item -> expect 42501; skip if no items
SELECT set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid()::text, 'role', 'authenticated')::text, true);
SELECT pg_catalog.set_config('role','authenticated',true);

WITH has_item AS (
  SELECT EXISTS (
    SELECT 1 FROM public.items i
    JOIN public.lists  l ON l.id = i.list_id
    JOIN public.events e ON e.id = l.event_id
    WHERE e.title='Test Event'
  ) present
)
SELECT CASE WHEN present THEN
  is(
    public.test_try($$
      UPDATE public.items SET name = name
       WHERE id = (
        SELECT i.id
          FROM public.items i
          JOIN public.lists  l ON l.id = i.list_id
          JOIN public.events e ON e.id = l.event_id
         WHERE e.title='Test Event' LIMIT 1
       );
    $$),
    '42501',
    'outsider cannot update item'
  )
ELSE
  ok(true, 'no items; skipping outsider update assertion')
END
FROM has_item;

SELECT * FROM finish();
ROLLBACK;
