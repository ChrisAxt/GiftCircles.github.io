\ir ../helpers/00_enable_extensions.sql
\ir ../helpers/02_seed_minimal.sql

-- 7 checks total
select plan(7);

-- RLS enabled + forced on core tables
select ok( exists (
  select 1
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'events'
    and c.relrowsecurity = true and c.relforcerowsecurity = true
), 'RLS forced on public.events');

select ok( exists (
  select 1
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'lists'
    and c.relrowsecurity = true and c.relforcerowsecurity = true
), 'RLS forced on public.lists');

select ok( exists (
  select 1
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'items'
    and c.relrowsecurity = true and c.relforcerowsecurity = true
), 'RLS forced on public.items');

select ok( exists (
  select 1
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'claims'
    and c.relrowsecurity = true and c.relforcerowsecurity = true
), 'RLS forced on public.claims');

-- FK delete rules (CASCADE) on key relations
select ok( exists (
  select 1
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname='public' and t.relname='items' and c.contype='f' and c.confdeltype='c'
), 'items FKs cascade on delete');

select ok( exists (
  select 1
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname='public' and t.relname='claims' and c.contype='f' and c.confdeltype='c'
), 'claims FKs cascade on delete');

select ok( exists (
  select 1
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname='public' and t.relname='lists' and c.contype='f' and c.confdeltype='c'
), 'lists FKs cascade on delete');

select * from finish();
