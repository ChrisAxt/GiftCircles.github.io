-- Migration: Event Invite System
-- Allows users to invite others to events via email
-- Sends push notifications to registered users

-- 1. Create event_invites table
create table if not exists public.event_invites (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  inviter_id uuid not null references auth.users(id) on delete cascade,
  invitee_email text not null,
  invitee_id uuid references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  invited_at timestamp with time zone default now(),
  responded_at timestamp with time zone,
  unique(event_id, invitee_email)
);

alter table public.event_invites enable row level security;

-- Index for faster lookups
create index if not exists idx_event_invites_event_id on public.event_invites(event_id);
create index if not exists idx_event_invites_invitee_email on public.event_invites(invitee_email);
create index if not exists idx_event_invites_invitee_id on public.event_invites(invitee_id);
create index if not exists idx_event_invites_status on public.event_invites(status);

-- RLS Policies
-- Event members can view invites for their events
create policy "event_invites_select"
  on public.event_invites for select
  using (
    -- Inviter can see their own invites
    auth.uid() = inviter_id
    OR
    -- Invitee can see their own invites
    auth.uid() = invitee_id
    OR
    -- Event members can see all invites for the event
    exists (
      select 1 from public.event_members em
      where em.event_id = event_invites.event_id
        and em.user_id = auth.uid()
    )
  );

-- Only event members can create invites
create policy "event_invites_insert"
  on public.event_invites for insert
  with check (
    auth.uid() = inviter_id
    and exists (
      select 1 from public.event_members em
      where em.event_id = event_invites.event_id
        and em.user_id = auth.uid()
    )
  );

-- Invitee can update their own invite (accept/decline)
create policy "event_invites_update"
  on public.event_invites for update
  using (auth.uid() = invitee_id);

-- Inviter or event admin can delete invites
create policy "event_invites_delete"
  on public.event_invites for delete
  using (
    auth.uid() = inviter_id
    or exists (
      select 1 from public.event_members em
      where em.event_id = event_invites.event_id
        and em.user_id = auth.uid()
        and em.role = 'admin'
    )
  );

-- 2. Function to send event invite
create or replace function public.send_event_invite(
  p_event_id uuid,
  p_invitee_email text
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_invite_id uuid;
  v_invitee_id uuid;
  v_event_title text;
  v_inviter_name text;
  v_has_push_token boolean;
begin
  -- Validate inviter is event member
  if not exists (
    select 1 from public.event_members
    where event_id = p_event_id and user_id = auth.uid()
  ) then
    raise exception 'Not authorized to invite to this event';
  end if;

  -- Normalize email
  p_invitee_email := lower(trim(p_invitee_email));

  -- Validate email format (basic)
  if p_invitee_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then
    raise exception 'Invalid email format';
  end if;

  -- Check if user is already a member
  if exists (
    select 1 from public.event_members em
    join auth.users u on u.id = em.user_id
    where em.event_id = p_event_id and lower(u.email) = p_invitee_email
  ) then
    raise exception 'User is already a member of this event';
  end if;

  -- Get event title
  select title into v_event_title
  from public.events
  where id = p_event_id;

  -- Get inviter display name
  select coalesce(display_name, 'Someone') into v_inviter_name
  from public.profiles
  where id = auth.uid();

  -- Check if invitee is a registered user
  select id into v_invitee_id
  from auth.users
  where lower(email) = p_invitee_email;

  -- Create or update invite
  insert into public.event_invites (event_id, inviter_id, invitee_email, invitee_id)
  values (p_event_id, auth.uid(), p_invitee_email, v_invitee_id)
  on conflict (event_id, invitee_email) do update
    set inviter_id = excluded.inviter_id,
        invitee_id = excluded.invitee_id,
        status = 'pending',
        invited_at = now(),
        responded_at = null
  returning id into v_invite_id;

  -- If user is registered and has push tokens, queue notification
  if v_invitee_id is not null then
    select exists (
      select 1 from public.push_tokens where user_id = v_invitee_id
    ) into v_has_push_token;

    if v_has_push_token then
      insert into public.notification_queue (user_id, title, body, data)
      values (
        v_invitee_id,
        'Event Invitation',
        v_inviter_name || ' invited you to ' || v_event_title,
        jsonb_build_object(
          'type', 'event_invite',
          'invite_id', v_invite_id,
          'event_id', p_event_id
        )
      );
    end if;
  end if;

  return v_invite_id;
end;
$$;

-- 3. Function to accept event invite
create or replace function public.accept_event_invite(
  p_invite_id uuid
)
returns void
language plpgsql
security definer
as $$
declare
  v_invite record;
begin
  -- Get invite details
  select * into v_invite
  from public.event_invites
  where id = p_invite_id
    and invitee_id = auth.uid()
    and status = 'pending';

  if not found then
    raise exception 'Invite not found or already responded';
  end if;

  -- Add user to event as giver
  insert into public.event_members (event_id, user_id, role)
  values (v_invite.event_id, auth.uid(), 'giver')
  on conflict do nothing;

  -- Update invite status
  update public.event_invites
  set status = 'accepted',
      responded_at = now()
  where id = p_invite_id;
end;
$$;

-- 4. Function to decline event invite
create or replace function public.decline_event_invite(
  p_invite_id uuid
)
returns void
language plpgsql
security definer
as $$
begin
  -- Update invite status
  update public.event_invites
  set status = 'declined',
      responded_at = now()
  where id = p_invite_id
    and invitee_id = auth.uid()
    and status = 'pending';

  if not found then
    raise exception 'Invite not found or already responded';
  end if;
end;
$$;

-- 5. Function to get pending invites for current user
create or replace function public.get_my_pending_invites()
returns table (
  invite_id uuid,
  event_id uuid,
  event_title text,
  event_date date,
  inviter_name text,
  invited_at timestamp with time zone
)
language plpgsql
security definer
as $$
begin
  return query
  select
    ei.id as invite_id,
    e.id as event_id,
    e.title as event_title,
    e.event_date,
    coalesce(p.display_name, u.email) as inviter_name,
    ei.invited_at
  from public.event_invites ei
  join public.events e on e.id = ei.event_id
  join auth.users u on u.id = ei.inviter_id
  left join public.profiles p on p.id = ei.inviter_id
  where ei.invitee_id = auth.uid()
    and ei.status = 'pending'
  order by ei.invited_at desc;
end;
$$;

-- 6. Trigger to update invitee_id when a new user registers
create or replace function public.update_invites_on_user_signup()
returns trigger
language plpgsql
security definer
as $$
declare
  v_invite record;
  v_event_title text;
  v_inviter_name text;
begin
  -- Update all pending invites for this email
  update public.event_invites
  set invitee_id = NEW.id
  where lower(invitee_email) = lower(NEW.email)
    and invitee_id is null
    and status = 'pending';

  -- Send notifications for all pending invites
  for v_invite in
    select ei.id, ei.event_id, ei.inviter_id
    from public.event_invites ei
    where ei.invitee_id = NEW.id
      and ei.status = 'pending'
  loop
    -- Get event title
    select title into v_event_title
    from public.events
    where id = v_invite.event_id;

    -- Get inviter name
    select coalesce(display_name, 'Someone') into v_inviter_name
    from public.profiles
    where id = v_invite.inviter_id;

    -- Queue notification if user has push tokens
    if exists (select 1 from public.push_tokens where user_id = NEW.id) then
      insert into public.notification_queue (user_id, title, body, data)
      values (
        NEW.id,
        'Event Invitation',
        v_inviter_name || ' invited you to ' || v_event_title,
        jsonb_build_object(
          'type', 'event_invite',
          'invite_id', v_invite.id,
          'event_id', v_invite.event_id
        )
      );
    end if;
  end loop;

  return NEW;
end;
$$;

-- Create trigger on profiles table (after user signup creates profile)
drop trigger if exists trigger_update_invites_on_signup on public.profiles;
create trigger trigger_update_invites_on_signup
  after insert on public.profiles
  for each row
  execute function public.update_invites_on_user_signup();

-- 7. Cleanup function to remove old declined/accepted invites
create or replace function public.cleanup_old_invites()
returns void
language plpgsql
security definer
as $$
begin
  delete from public.event_invites
  where status in ('accepted', 'declined')
    and responded_at < now() - interval '30 days';
end;
$$;
