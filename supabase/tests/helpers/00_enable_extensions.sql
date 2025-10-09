-- Ensure pgTAP is available and put its schema on the search_path
create extension if not exists pgtap;

do $$
declare
  tap_schema text;
begin
  select n.nspname
    into tap_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgtap';

  if tap_schema is null then
    raise exception 'pgtap extension not found after CREATE EXTENSION';
  end if;

  -- Make pgTAP functions resolvable without schema-qualifying
  execute format('set search_path = %I, public, pg_catalog', tap_schema);
end$$;
