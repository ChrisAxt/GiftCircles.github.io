-- Identity/signature check (robust)
do $$
declare
  v_ident text;
  v_norm  text;
  ok boolean := false;
begin
  select pg_get_function_identity_arguments(p.oid)
    into v_ident
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'create_list_with_people'
  limit 1;

  if v_ident is null then
    raise exception 'create_list_with_people not found';
  end if;

  -- Strip unexpected arg names, normalize enum schema + whitespace
  v_norm := regexp_replace(v_ident, '(^|,)\s*[A-Za-z_][A-Za-z0-9_]*\s+', '\1', 'g');
  v_norm := replace(v_norm, 'public.list_visibility', 'list_visibility');
  v_norm := replace(v_norm, ' ', '');

  -- Accept either 6-arg or 5-arg form
  if v_norm = 'uuid,text,list_visibility,uuid[],uuid[],uuid[]'
     or v_norm = 'uuid,text,list_visibility,uuid[],uuid[]' then
    ok := true;
  end if;

  if not ok then
    raise exception 'create_list_with_people signature mismatch. Normalized identity: %', v_norm;
  end if;
end$$;

-- Simulate an authenticated user for RPCs that rely on auth.uid()
-- This mirrors how Supabase sets request.jwt.claims.
do $$
declare
  old text;
begin
  -- Save old claims (if any)
  select current_setting('request.jwt.claims', true) into old;

  -- Impersonate a user (any UUID is fine for smoke tests)
  perform set_config('request.jwt.claims',
                     '{"sub":"00000000-0000-4000-8000-0000000000aa"}',
                     true);

  -- Validate error contract: empty title rejected
  begin
    perform public.create_event_and_admin(''::text, current_date, 'none', null);
    raise exception 'Expected invalid_parameter for empty title';
  exception
    when others then
      if sqlerrm not like 'invalid_parameter%' then
        raise;
      end if;
  end;

  -- Restore previous claims
  perform set_config('request.jwt.claims', coalesce(old, ''), true);
end$$;
