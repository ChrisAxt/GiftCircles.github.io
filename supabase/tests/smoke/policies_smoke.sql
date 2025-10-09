-- Check policy definitions use canonical helpers
do $$
declare v text;
begin
  select pg_get_expr(pol.polqual, c.oid) into v
  from pg_policy pol join pg_class c on c.oid=pol.polrelid
  where pol.polname='items_select_visible';
  if position('can_view_list(list_id)' in v) = 0 then
    raise exception 'items_select_visible must use can_view_list(list_id)';
  end if;

  select pg_get_expr(pol.polqual, c.oid) into v
  from pg_policy pol join pg_class c on c.oid=pol.polrelid
  where pol.polname='events: update by admins';
  if position('is_event_admin(id)' in v) = 0 then
    raise exception 'events: update by admins must use is_event_admin(id)';
  end if;
end$$;
