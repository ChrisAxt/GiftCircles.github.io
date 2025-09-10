-- Enable needed extensions
create extension if not exists pgcrypto; -- for gen_random_uuid()

-- 1) Profiles (mirror of auth.users)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  created_at timestamp with time zone default now()
);

alter table public.profiles enable row level security;

create policy "profiles are readable by logged in users"
  on public.profiles for select
  using (auth.uid() is not null);

create policy "users can update their own profile"
  on public.profiles for update
  using (id = auth.uid());

-- 2) Events
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  event_date date,
  join_code text unique not null default replace(gen_random_uuid()::text,'-',''),
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamp with time zone default now()
);

alter table public.events enable row level security;

-- 3) Event Members
do $$ begin
  create type member_role as enum ('giver','recipient','admin');
exception when duplicate_object then null; end $$;

create table if not exists public.event_members (
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role member_role not null default 'giver',
  created_at timestamp with time zone default now(),
  primary key (event_id, user_id)
);

alter table public.event_members enable row level security;

-- 4) Lists
create table if not exists public.lists (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  name text not null,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamp with time zone default now()
);

alter table public.lists enable row level security;

-- 5) List Recipients
create table if not exists public.list_recipients (
  list_id uuid not null references public.lists(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (list_id, user_id)
);

alter table public.list_recipients enable row level security;

-- 6) Items
create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.lists(id) on delete cascade,
  name text not null,
  url text,
  price numeric(12,2),
  notes text,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamp with time zone default now()
);

alter table public.items enable row level security;

-- 7) Claims
create table if not exists public.claims (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  claimer_id uuid not null references auth.users(id) on delete cascade,
  quantity integer not null default 1 check (quantity > 0),
  note text,
  created_at timestamp with time zone default now(),
  unique (item_id, claimer_id)
);

alter table public.claims enable row level security;

-- Helper functions
create or replace function public.event_id_for_list(l_id uuid)
returns uuid language sql stable as $$
  select event_id from public.lists where id = l_id
$$;

create or replace function public.event_id_for_item(i_id uuid)
returns uuid language sql stable as $$
  select l.event_id from public.items i join public.lists l on l.id = i.list_id where i.id = i_id
$$;

create or replace function public.is_event_member(e_id uuid, u_id uuid)
returns boolean language sql stable as $$
  select exists(
    select 1 from public.event_members em
    where em.event_id = e_id and em.user_id = u_id
  )
$$;

create or replace function public.is_list_recipient(l_id uuid, u_id uuid)
returns boolean language sql stable as $$
  select exists(
    select 1 from public.list_recipients lr
    where lr.list_id = l_id and lr.user_id = u_id
  )
$$;

-- Auto‑membership trigger
create or replace function public.autojoin_event_as_admin()
returns trigger language plpgsql as $$
begin
  insert into public.event_members(event_id, user_id, role)
  values (new.id, new.owner_id, 'admin')
  on conflict do nothing;
  return new;
end;$$;

drop trigger if exists trg_autojoin_event on public.events;
create trigger trg_autojoin_event
  after insert on public.events
  for each row execute procedure public.autojoin_event_as_admin();

-- Join by code RPC
create or replace function public.join_event(p_join_code text)
returns uuid
language plpgsql security definer as $$
declare v_event_id uuid;
begin
  select id into v_event_id from public.events where join_code = p_join_code;
  if v_event_id is null then
    raise exception 'Invalid join code';
  end if;
  insert into public.event_members(event_id, user_id, role)
  values (v_event_id, auth.uid(), 'giver')
  on conflict do nothing;
  return v_event_id;
end;$$;

-- EVENTS
drop policy if exists "select events for members" on public.events;
create policy "select events for members"
  on public.events for select
  using (public.is_event_member(id, auth.uid()));

drop policy if exists "insert events when owner is self" on public.events;
create policy "insert events when owner is self"
  on public.events for insert
  with check (owner_id = auth.uid());

-- EVENT_MEMBERS
drop policy if exists "select membership for members" on public.event_members;
create policy "select membership for members"
  on public.event_members for select
  using (public.is_event_member(event_id, auth.uid()));

drop policy if exists "users can insert their own membership" on public.event_members;
create policy "users can insert their own membership"
  on public.event_members for insert
  with check (user_id = auth.uid());

drop policy if exists "admins can update roles" on public.event_members;
create policy "admins can update roles"
  on public.event_members for update
  using (
    exists(
      select 1 from public.event_members em2
      where em2.event_id = event_id and em2.user_id = auth.uid() and em2.role = 'admin'
    )
  )
  with check (true);

-- LISTS
drop policy if exists "select lists for members" on public.lists;
create policy "select lists for members"
  on public.lists for select
  using (public.is_event_member(event_id, auth.uid()));

drop policy if exists "insert lists by members" on public.lists;
create policy "insert lists by members"
  on public.lists for insert
  with check (public.is_event_member(event_id, auth.uid()) and created_by = auth.uid());

-- LIST_RECIPIENTS
drop policy if exists "select list_recipients for members" on public.list_recipients;
create policy "select list_recipients for members"
  on public.list_recipients for select
  using ( public.is_event_member(public.event_id_for_list(list_id), auth.uid()) );

drop policy if exists "insert list_recipients by admins" on public.list_recipients;
create policy "insert list_recipients by admins"
  on public.list_recipients for insert
  with check (
    exists(
      select 1 from public.event_members em
      where em.event_id = public.event_id_for_list(list_id)
        and em.user_id = auth.uid()
        and em.role = 'admin'
    )
  );

-- ITEMS
drop policy if exists "select items for members" on public.items;
create policy "select items for members"
  on public.items for select
  using ( public.is_event_member(public.event_id_for_list(list_id), auth.uid()) );

drop policy if exists "insert items by members" on public.items;
create policy "insert items by members"
  on public.items for insert
  with check (
    public.is_event_member(public.event_id_for_list(list_id), auth.uid())
    and created_by = auth.uid()
  );

-- CLAIMS
drop policy if exists "select claims for non-recipients" on public.claims;
create policy "select claims for non-recipients"
  on public.claims for select
  using (
    public.is_event_member(public.event_id_for_item(item_id), auth.uid())
    and not exists (
      select 1
      from public.items i
      join public.list_recipients lr on lr.list_id = i.list_id
      where i.id = public.claims.item_id and lr.user_id = auth.uid()
    )
  );

drop policy if exists "insert claims by non-recipients" on public.claims;
create policy "insert claims by non-recipients"
  on public.claims for insert
  with check (
    public.is_event_member(public.event_id_for_item(item_id), auth.uid())
    and not exists (
      select 1
      from public.items i
      join public.list_recipients lr on lr.list_id = i.list_id
      where i.id = public.claims.item_id and lr.user_id = auth.uid()
    )
    and claimer_id = auth.uid()
  );

drop policy if exists "delete own claims" on public.claims;
create policy "delete own claims"
  on public.claims for delete
  using (claimer_id = auth.uid());

