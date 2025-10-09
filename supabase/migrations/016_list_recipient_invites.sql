-- Migration: Auto-invite non-member list recipients
-- When creating a list for someone not in the event, automatically invite them

-- 1. Restructure list_recipients table to support email recipients

-- Add new columns first
alter table public.list_recipients
add column if not exists recipient_email text;

alter table public.list_recipients
add column if not exists id uuid default gen_random_uuid();

-- Drop old primary key (must do this before making user_id nullable)
alter table public.list_recipients
drop constraint if exists list_recipients_pkey;

-- Now we can make user_id nullable
alter table public.list_recipients
alter column user_id drop not null;

-- Add new primary key on id
alter table public.list_recipients
add constraint list_recipients_pkey
primary key (id);

-- Create unique indexes to prevent duplicates
create unique index if not exists list_recipients_user_unique
  on public.list_recipients (list_id, user_id)
  where user_id is not null;

create unique index if not exists list_recipients_email_unique
  on public.list_recipients (list_id, lower(recipient_email))
  where recipient_email is not null;

-- Add constraint: must have either user_id OR recipient_email
alter table public.list_recipients
drop constraint if exists list_recipients_user_or_email_check;

alter table public.list_recipients
add constraint list_recipients_user_or_email_check
check (
  (user_id is not null and recipient_email is null)
  or
  (user_id is null and recipient_email is not null)
);

-- 2. Function to add recipient and auto-invite if needed
create or replace function public.add_list_recipient(
  p_list_id uuid,
  p_recipient_email text
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_recipient_id uuid;
  v_event_id uuid;
  v_list_name text;
  v_creator_name text;
  v_event_title text;
  v_invite_id uuid;
  v_is_member boolean;
begin
  -- Validate user can modify this list
  if not exists (
    select 1 from public.lists
    where id = p_list_id
      and created_by = auth.uid()
  ) then
    raise exception 'Not authorized to modify this list';
  end if;

  -- Normalize email
  p_recipient_email := lower(trim(p_recipient_email));

  -- Validate email format
  if p_recipient_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then
    raise exception 'Invalid email format';
  end if;

  -- Get list and event info
  select l.event_id, l.name, e.title
  into v_event_id, v_list_name, v_event_title
  from public.lists l
  join public.events e on e.id = l.event_id
  where l.id = p_list_id;

  -- Get creator name
  select coalesce(display_name, 'Someone') into v_creator_name
  from public.profiles
  where id = auth.uid();

  -- Check if email belongs to a registered user
  select id into v_recipient_id
  from auth.users
  where lower(email) = p_recipient_email;

  -- If registered user, check if they're already an event member
  if v_recipient_id is not null then
    select exists (
      select 1 from public.event_members
      where event_id = v_event_id
        and user_id = v_recipient_id
    ) into v_is_member;
  else
    v_is_member := false;
  end if;

  -- Add recipient to list (check if already exists first)
  if not exists (
    select 1 from public.list_recipients
    where list_id = p_list_id
      and (
        (user_id = v_recipient_id and v_recipient_id is not null)
        or (lower(recipient_email) = p_recipient_email)
      )
  ) then
    -- If user is registered, use user_id only. Otherwise use email only.
    if v_recipient_id is not null then
      insert into public.list_recipients (list_id, user_id)
      values (p_list_id, v_recipient_id);
    else
      insert into public.list_recipients (list_id, recipient_email)
      values (p_list_id, p_recipient_email);
    end if;
  else
    -- Update existing record if user_id changed (user signed up)
    update public.list_recipients
    set user_id = v_recipient_id, recipient_email = null
    where list_id = p_list_id
      and lower(recipient_email) = p_recipient_email
      and user_id is null
      and v_recipient_id is not null;
  end if;

  -- If user is not an event member, send invite
  if not v_is_member then
    -- Send event invite
    select public.send_event_invite(v_event_id, p_recipient_email)
    into v_invite_id;

    -- If user is registered, also send a list notification
    if v_recipient_id is not null then
      insert into public.notification_queue (user_id, title, body, data)
      values (
        v_recipient_id,
        'Gift List Created',
        v_creator_name || ' created a gift list for you in ' || v_event_title,
        jsonb_build_object(
          'type', 'list_for_recipient',
          'list_id', p_list_id,
          'event_id', v_event_id,
          'invite_id', v_invite_id
        )
      );
    end if;
  end if;

  return v_recipient_id;
end;
$$;

-- 3. Trigger to auto-link recipients when user signs up
create or replace function public.link_list_recipients_on_signup()
returns trigger
language plpgsql
security definer
as $$
declare
  v_recipient record;
  v_list_name text;
  v_event_title text;
  v_creator_name text;
begin
  -- Update all list_recipients for this email
  for v_recipient in
    update public.list_recipients lr
    set user_id = NEW.id, recipient_email = null
    where lower(recipient_email) = lower(NEW.email)
      and user_id is null
    returning lr.list_id, lr.recipient_email
  loop
    -- Get list and event info
    select l.name, e.title
    into v_list_name, v_event_title
    from public.lists l
    join public.events e on e.id = l.event_id
    where l.id = v_recipient.list_id;

    -- Get creator name
    select coalesce(p.display_name, u.email) into v_creator_name
    from public.lists l
    join auth.users u on u.id = l.created_by
    left join public.profiles p on p.id = l.created_by
    where l.id = v_recipient.list_id;

    -- Send notification about the list
    if exists (select 1 from public.push_tokens where user_id = NEW.id) then
      insert into public.notification_queue (user_id, title, body, data)
      values (
        NEW.id,
        'Gift List Created',
        v_creator_name || ' created a gift list for you in ' || v_event_title,
        jsonb_build_object(
          'type', 'list_for_recipient',
          'list_id', v_recipient.list_id
        )
      );
    end if;
  end loop;

  return NEW;
end;
$$;

-- Add trigger to profiles (runs after user signup)
drop trigger if exists trigger_link_recipients_on_signup on public.profiles;
create trigger trigger_link_recipients_on_signup
  after insert on public.profiles
  for each row
  execute function public.link_list_recipients_on_signup();

-- 4. Update RLS policies for list_recipients
drop policy if exists "list_recipients_select" on public.list_recipients;
create policy "list_recipients_select"
  on public.list_recipients for select
  using (
    -- Event members can see all recipients
    exists (
      select 1 from public.lists l
      join public.event_members em on em.event_id = l.event_id
      where l.id = list_recipients.list_id
        and em.user_id = auth.uid()
    )
    or
    -- Recipients can see themselves (if registered)
    auth.uid() = user_id
  );

drop policy if exists "list_recipients_insert" on public.list_recipients;
create policy "list_recipients_insert"
  on public.list_recipients for insert
  with check (
    -- List creator can add recipients
    exists (
      select 1 from public.lists l
      where l.id = list_recipients.list_id
        and l.created_by = auth.uid()
    )
  );

drop policy if exists "list_recipients_delete" on public.list_recipients;
create policy "list_recipients_delete"
  on public.list_recipients for delete
  using (
    -- List creator can remove recipients
    exists (
      select 1 from public.lists l
      where l.id = list_recipients.list_id
        and l.created_by = auth.uid()
    )
  );

-- 5. Function to get recipient info (including non-registered)
create or replace function public.get_list_recipients(p_list_id uuid)
returns table (
  list_id uuid,
  user_id uuid,
  recipient_email text,
  display_name text,
  is_registered boolean,
  is_event_member boolean
)
language plpgsql
security definer
as $$
begin
  return query
  select
    lr.list_id,
    lr.user_id,
    lr.recipient_email,
    coalesce(p.display_name, lr.recipient_email) as display_name,
    lr.user_id is not null as is_registered,
    exists (
      select 1 from public.event_members em
      join public.lists l on l.event_id = em.event_id
      where l.id = lr.list_id
        and em.user_id = lr.user_id
    ) as is_event_member
  from public.list_recipients lr
  left join public.profiles p on p.id = lr.user_id
  where lr.list_id = p_list_id;
end;
$$;

-- 6. Update create_list_with_people to support email recipients
create or replace function public.create_list_with_people(
  p_event_id uuid,
  p_name text,
  p_visibility text,
  p_custom_recipient_name text,
  p_recipient_user_ids uuid[],
  p_recipient_emails text[],
  p_viewer_ids uuid[],
  p_exclusion_ids uuid[]
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_list_id uuid;
  v_recipient_id uuid;
  v_recipient_email text;
begin
  -- Validate inputs
  if p_name is null or trim(p_name) = '' then
    raise exception 'List name cannot be empty' using errcode = 'invalid_parameter';
  end if;

  if p_visibility not in ('private', 'shared', 'public') then
    raise exception 'Invalid visibility value' using errcode = 'invalid_parameter';
  end if;

  -- Validate user is member of event
  if not exists (
    select 1 from public.event_members
    where event_id = p_event_id and user_id = auth.uid()
  ) then
    raise exception 'Not authorized' using errcode = 'insufficient_privilege';
  end if;

  -- Create list
  insert into public.lists (event_id, name, visibility, custom_recipient_name, created_by)
  values (p_event_id, p_name, p_visibility::visibility_level, p_custom_recipient_name, auth.uid())
  returning id into v_list_id;

  -- Add user ID recipients
  if p_recipient_user_ids is not null then
    foreach v_recipient_id in array p_recipient_user_ids loop
      if not exists (
        select 1 from public.list_recipients
        where list_id = v_list_id and user_id = v_recipient_id
      ) then
        insert into public.list_recipients (list_id, user_id)
        values (v_list_id, v_recipient_id);
      end if;
    end loop;
  end if;

  -- Add email recipients (auto-invites non-members)
  if p_recipient_emails is not null then
    foreach v_recipient_email in array p_recipient_emails loop
      perform public.add_list_recipient(v_list_id, v_recipient_email);
    end loop;
  end if;

  -- Add viewers
  if p_viewer_ids is not null then
    insert into public.list_viewers (list_id, user_id)
    select v_list_id, unnest(p_viewer_ids)
    on conflict do nothing;
  end if;

  -- Add exclusions
  if p_exclusion_ids is not null then
    insert into public.list_exclusions (list_id, user_id)
    select v_list_id, unnest(p_exclusion_ids)
    on conflict do nothing;
  end if;

  return v_list_id;
end;
$$;
