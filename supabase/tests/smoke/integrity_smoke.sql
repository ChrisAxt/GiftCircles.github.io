-- RLS must be enabled AND forced on core tables (in public schema)
do $$
begin
  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'events'
      and c.relrowsecurity = true
      and c.relforcerowsecurity = true
  ) then
    raise exception 'RLS not forced on public.events';
  end if;

  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'lists'
      and c.relrowsecurity = true
      and c.relforcerowsecurity = true
  ) then
    raise exception 'RLS not forced on public.lists';
  end if;

  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'items'
      and c.relrowsecurity = true
      and c.relforcerowsecurity = true
  ) then
    raise exception 'RLS not forced on public.items';
  end if;

  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'claims'
      and c.relrowsecurity = true
      and c.relforcerowsecurity = true
  ) then
    raise exception 'RLS not forced on public.claims';
  end if;
end$$;

-- Key indexes must exist (adjust names if you used different ones)
do $$
begin
  if not exists (select 1 from pg_indexes where schemaname='public' and indexname='idx_lists_event_id') then
    raise exception 'Missing idx_lists_event_id';
  end if;
  if not exists (select 1 from pg_indexes where schemaname='public' and indexname='idx_items_list_id') then
    raise exception 'Missing idx_items_list_id';
  end if;
  if not exists (select 1 from pg_indexes where schemaname='public' and indexname='idx_claims_item_id') then
    raise exception 'Missing idx_claims_item_id';
  end if;
end$$;

-- FK delete rules sanity (expect CASCADE on a few key relations)
do $$
begin
  -- items.list_id -> lists.id
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where c.contype='f' and n.nspname='public' and t.relname='items' and c.confdeltype='c'
  ) then
    raise exception 'items.list_id -> lists.id should be ON DELETE CASCADE';
  end if;

  -- claims.item_id -> items.id
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where c.contype='f' and n.nspname='public' and t.relname='claims' and c.confdeltype='c'
  ) then
    raise exception 'claims.item_id -> items.id should be ON DELETE CASCADE';
  end if;

  -- lists.event_id -> events.id
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where c.contype='f' and n.nspname='public' and t.relname='lists' and c.confdeltype='c'
  ) then
    raise exception 'lists.event_id -> events.id should be ON DELETE CASCADE';
  end if;
end$$;
