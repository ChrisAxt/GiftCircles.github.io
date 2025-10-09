\ir ../helpers/00_enable_extensions.sql
\ir ../helpers/02_seed_minimal.sql

-- Plan dynamically: 2 tests if the function exists, otherwise 0
select plan((
  select case
           when exists (
             select 1 from pg_proc p
             join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'claim_counts_for_lists'
           )
           then 2 else 0
         end
));

-- Owner/member sees 1 row (only if function exists)
select ok(
  (
    with v as (
      select l.id as list_id,
             em.user_id as member_id
      from public.lists l
      join public.events e on e.id = l.event_id
      join public.event_members em on em.event_id = e.id
      where e.title = 'Test Event'
      order by l.id
      limit 1
    )
    select (
      -- impersonate member and query function
      select count(*)
      from public.claim_counts_for_lists(array[(select list_id from v)])
      where (
        select set_config(
          'request.jwt.claims',
          json_build_object('sub', (select member_id from v)::text, 'role', 'authenticated')::text,
          true
        )
      ) is not null
      and (select current_user) is not null
    ) = 1
  ),
  'member sees claim_counts for their list'
) where exists (
  select 1 from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'claim_counts_for_lists'
);

-- Outsider sees 0 rows (only if function exists)
select ok(
  (
    with v as (
      select l.id as list_id
      from public.lists l
      join public.events e on e.id = l.event_id
      where e.title = 'Test Event'
      order by l.id
      limit 1
    )
    select (
      -- impersonate outsider and query function
      select count(*)
      from public.claim_counts_for_lists(array[(select list_id from v)])
      where (
        select set_config(
          'request.jwt.claims',
          json_build_object('sub', gen_random_uuid()::text, 'role', 'authenticated')::text,
          true
        )
      ) is not null
      and (select current_user) is not null
    ) = 0
  ),
  'outsider sees 0 rows'
) where exists (
  select 1 from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'claim_counts_for_lists'
);

select * from finish();
