-- Minimal seed used by tests (idempotent) — Supabase-friendly
-- Picks existing users from auth.users; does NOT write to auth schema.

begin;

do $$
declare
  v_alice uuid;
  v_bob   uuid;
  v_event uuid;
  v_list  uuid;
begin
  -- Pick two existing auth users (at least one must exist)
  select id into v_alice from auth.users order by created_at limit 1;
  if v_alice is null then
    raise exception 'No users in auth.users; create at least one user in your Supabase project to run tests.';
  end if;

  select id into v_bob from auth.users where id <> v_alice order by created_at limit 1;
  if v_bob is null then
    v_bob := v_alice;
  end if;

  -- ===== Event (owned by v_alice) =====
  select id into v_event from public.events where title = 'Test Event' limit 1;
  if v_event is null then
    insert into public.events (title, owner_id, event_date, join_code, recurrence)
    values ('Test Event', v_alice, current_date + 7, 'ABC123', 'none')
    returning id into v_event;
  end if;

  -- ===== Members =====
  insert into public.event_members (event_id, user_id, role)
  values (v_event, v_alice, 'admin')
  on conflict do nothing;

  insert into public.event_members (event_id, user_id, role)
  values (v_event, v_bob, 'giver')
  on conflict do nothing;

  -- ===== One list on that event (created by v_alice) =====
  select id into v_list from public.lists where event_id = v_event and name = 'Test List' limit 1;
  if v_list is null then
    insert into public.lists (event_id, name, visibility, created_by)
    values (v_event, 'Test List', 'event', v_alice)
    returning id into v_list;
  end if;

  -- ===== Recipient (v_bob) =====
  insert into public.list_recipients (list_id, user_id)
  values (v_list, v_bob)
  on conflict do nothing;

  -- ===== One item (use your real columns: name + created_by) =====
  -- If your table requires additional columns, add them here.
  insert into public.items (list_id, name, created_by)
  values (v_list, 'Sample Item', v_alice)
  on conflict do nothing;
end $$;

commit;
