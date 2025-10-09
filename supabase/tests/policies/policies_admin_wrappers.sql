\ir ../helpers/00_enable_extensions.sql

select plan(3);

-- events: update policy exists and uses admin check
-- Note: Schema uses EXISTS subquery instead of is_event_admin(id) wrapper
select ok(
  (
    select position('event_members' in pg_get_expr(pol.polqual, c.oid)) > 0
       and position('role' in pg_get_expr(pol.polqual, c.oid)) > 0
       and position('admin' in pg_get_expr(pol.polqual, c.oid)) > 0
    from pg_policy pol
    join pg_class c on c.oid = pol.polrelid
    where pol.polname = 'events: update by admins'
  ),
  'events update policy checks admin role'
);

-- events: delete must use is_event_admin(id, auth.uid())
select ok(
  (
    select position('is_event_admin(id' in pg_get_expr(pol.polqual, c.oid)) > 0
    from pg_policy pol
    join pg_class c on c.oid = pol.polrelid
    where pol.polname = 'admins can delete events'
  ),
  'events delete uses 2-arg is_event_admin'
);

-- claims: there must be a DELETE policy whose predicate references is_event_admin(...)
select ok(
  exists (
    select 1
    from pg_policy pol
    join pg_class c on c.oid = pol.polrelid
    where c.relnamespace = 'public'::regnamespace
      and c.relname = 'claims'
      and pol.polcmd = 'd'   -- delete
      and position('is_event_admin(' in pg_get_expr(pol.polqual, c.oid)) > 0
  ),
  'claims delete policy uses is_event_admin(...)'
);

select * from finish();
