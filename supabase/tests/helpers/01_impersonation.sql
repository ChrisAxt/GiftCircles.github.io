-- Helper to impersonate a user by setting JWT claims (Supabase-compatible)
-- Usage: select test_impersonate('0000-...-0001'::uuid);
create or replace function public.test_impersonate(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user_id::text)::text,
    true
  );
end;
$$;
