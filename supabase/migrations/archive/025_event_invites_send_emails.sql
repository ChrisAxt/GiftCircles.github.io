-- Migration: Add email sending to event invites
-- When inviting someone to an event, always send an email
-- If they have an account, also send a push notification

-- Update send_event_invite to also send emails
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
  v_event_date date;
  v_join_code text;
  v_inviter_name text;
  v_has_push_token boolean;
  v_request_id bigint;
  v_email_url text;
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

  -- Get event details
  select title, event_date, join_code
  into v_event_title, v_event_date, v_join_code
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

  -- Send email invitation (for both registered and unregistered users)
  -- Note: Update the URL to match your Supabase project
  v_email_url := 'https://bqgakovbbbiudmggduvu.supabase.co/functions/v1/send-invite-email';

  select net.http_post(
    url := v_email_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJxZ2Frb3ZiYmJpdWRtZ2dkdXZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcwNTY1MjEsImV4cCI6MjA3MjYzMjUyMX0.i81E7-w03a1v6BV2FwGpuNRA9tTVWF3nATgJeeO5g1k'
    ),
    body := jsonb_build_object(
      'to', p_invitee_email,
      'inviterName', v_inviter_name,
      'eventName', v_event_title,
      'eventDate', v_event_date,
      'joinCode', v_join_code,
      'eventTimezone', 'UTC'
    )
  ) into v_request_id;

  -- If user is registered and has push tokens, also queue notification
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

-- Update the signup trigger to also send emails for pending invites
create or replace function public.update_invites_on_user_signup()
returns trigger
language plpgsql
security definer
as $$
declare
  v_invite record;
  v_event_title text;
  v_event_date date;
  v_join_code text;
  v_inviter_name text;
  v_request_id bigint;
  v_email_url text;
begin
  -- Update all pending invites for this email
  update public.event_invites
  set invitee_id = NEW.id
  where lower(invitee_email) = lower(NEW.email)
    and invitee_id is null
    and status = 'pending';

  -- Send notifications for all pending invites
  for v_invite in
    select ei.id, ei.event_id, ei.inviter_id, ei.invitee_email
    from public.event_invites ei
    where ei.invitee_id = NEW.id
      and ei.status = 'pending'
  loop
    -- Get event details
    select e.title, e.event_date, e.join_code
    into v_event_title, v_event_date, v_join_code
    from public.events e
    where e.id = v_invite.event_id;

    -- Get inviter name
    select coalesce(display_name, 'Someone') into v_inviter_name
    from public.profiles
    where id = v_invite.inviter_id;

    -- Send email (they just signed up, so send them the invite email)
    -- Note: Update the URL to match your Supabase project
    v_email_url := 'https://bqgakovbbbiudmggduvu.supabase.co/functions/v1/send-invite-email';

    select net.http_post(
      url := v_email_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJxZ2Frb3ZiYmJpdWRtZ2dkdXZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcwNTY1MjEsImV4cCI6MjA3MjYzMjUyMX0.i81E7-w03a1v6BV2FwGpuNRA9tTVWF3nATgJeeO5g1k'
      ),
      body := jsonb_build_object(
        'to', v_invite.invitee_email,
        'inviterName', v_inviter_name,
        'eventName', v_event_title,
        'eventDate', v_event_date,
        'joinCode', v_join_code,
        'eventTimezone', 'UTC'
      )
    ) into v_request_id;

    -- Queue push notification if user has push tokens
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
