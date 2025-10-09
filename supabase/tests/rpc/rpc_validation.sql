\ir ../helpers/00_enable_extensions.sql

begin;

-- Impersonate a real user and set the DB role so auth.uid() works
do $$
declare v_user uuid;
begin
  select id into v_user from auth.users order by created_at limit 1;
  if v_user is null then
    raise exception 'No users in auth.users; create at least one user to run RPC tests.';
  end if;

  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_user::text, 'role', 'authenticated')::text,
    true
  );
end$$;

set role authenticated;

select plan(3);

-- Empty title → invalid_parameter/title_required
select throws_like(
  $$ select public.create_event_and_admin(''::text, current_date, 'none', null) $$,
  'invalid_parameter%',
  'empty title rejected'
);

-- Bad recurrence → invalid_parameter/bad_recurrence
select throws_like(
  $$ select public.create_event_and_admin('X', current_date, 'often', null) $$,
  'invalid_parameter%',
  'bad recurrence rejected'
);

-- Join code required
select throws_like(
  $$ select public.join_event(''::text) $$,
  'invalid_parameter%',
  'empty join code rejected'
);

select * from finish();

commit;
