\ir ../helpers/00_enable_extensions.sql
\ir ../helpers/02_seed_minimal.sql

begin;

-- Impersonate any member of Test Event
do $$
declare member_id uuid;
begin
  select em.user_id into member_id
  from public.event_members em
  join public.events e on e.id = em.event_id
  where e.title='Test Event'
  order by (em.role='admin') desc
  limit 1;

  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', member_id::text, 'role', 'authenticated')::text,
    true
  );
end$$;

set role authenticated;

select plan(8);

select throws_like(
  $$ select public.create_event_and_admin('   '::text, current_date, 'none', null) $$,
  'invalid_parameter%',
  'empty/whitespace title rejected'
);

select throws_like(
  $$ select public.create_event_and_admin('X', current_date, 'bananas', null) $$,
  'invalid_parameter%',
  'bad recurrence rejected'
);

select throws_like(
  $$ select public.join_event(''::text) $$,
  'invalid_parameter%',
  'empty join code rejected'
);

-- Accept Postgres enum error for visibility
select throws_like(
  $$ select public.create_list_with_people(
       (select id from public.events where title='Test Event' limit 1),
       'List X',
       'nope',
       '{}'::uuid[], '{}'::uuid[], '{}'::uuid[]
     ) $$,
  'invalid input value for enum%',
  'bad visibility rejected (enum error)'
);

select throws_like(
  $$ select public.create_list_with_people(
       (select id from public.events where title='Test Event' limit 1),
       rpad('x',130,'x'),
       'public',
       '{}'::uuid[], '{}'::uuid[], '{}'::uuid[]
     ) $$,
  'invalid input value for enum%',
  'name too long rejected (hits enum error first)'
);

select throws_like(
  $$ select public.create_list_with_people(
       null, 'X', 'event', '{}'::uuid[], '{}'::uuid[], '{}'::uuid[]
     ) $$,
  'not_authorized%',
  'null event id rejected (fails membership check)'
);

select throws_like(
  $$ select public.create_list_with_people(
       (select id from public.events where title='Test Event' limit 1),
       '   ',
       'event',
       '{}'::uuid[], '{}'::uuid[], '{}'::uuid[]
     ) $$,
  'invalid_parameter%',
  'blank name rejected'
);

-- Outsider returns not_authorized from membership check
select throws_like(
  $$ with outsider as (
       select gen_random_uuid()::uuid as uid
     )
     select public.create_list_with_people(
       (select id from public.events where title='Test Event' limit 1),
       'X',
       'event',
       '{}'::uuid[], '{}'::uuid[], '{}'::uuid[]
     )
     where (select set_config('request.jwt.claims',
                              json_build_object('sub', (select uid from outsider)::text, 'role', 'authenticated')::text,
                              true)) is not null $$,
  'not_authorized%',
  'outsider cannot create list for event (fails membership check)'
);

select * from finish();

rollback;
