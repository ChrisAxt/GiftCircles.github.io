-- Migration: Add ability to invite admins during event creation
-- Date: 2025-10-14
-- Description: Adds invited_role to event_invites and updates create_event_and_admin to accept admin emails

-- Add invited_role column to event_invites table
ALTER TABLE public.event_invites
ADD COLUMN IF NOT EXISTS invited_role public.member_role NOT NULL DEFAULT 'giver'::public.member_role;

-- Update create_event_and_admin function to accept admin emails array
CREATE OR REPLACE FUNCTION public.create_event_and_admin(
  p_title text,
  p_event_date date,
  p_recurrence text,
  p_description text,
  p_admin_only_invites boolean DEFAULT false,
  p_admin_emails text[] DEFAULT ARRAY[]::text[]
)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user uuid := auth.uid();
  v_event_id uuid;
  v_admin_email text;
  v_invitee_id uuid;
  v_user_email text;
begin
  -- Authentication check
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  -- Validate title (not empty after trimming)
  if trim(coalesce(p_title, '')) = '' then
    raise exception 'invalid_parameter: title_required';
  end if;

  -- Validate recurrence value
  if p_recurrence not in ('none', 'weekly', 'monthly', 'yearly') then
    raise exception 'invalid_parameter: invalid_recurrence';
  end if;

  -- Validate event_date (must be in the future or today)
  if p_event_date < current_date then
    raise exception 'invalid_parameter: event_date_must_be_future';
  end if;

  -- Check free tier limits
  if not public.can_create_event(v_user) then
    raise exception 'free_limit_reached';
  end if;

  -- Get creator's email for inviter_id
  select email into v_user_email
  from auth.users
  where id = v_user;

  -- Create event with admin_only_invites setting
  insert into public.events (title, description, event_date, owner_id, recurrence, admin_only_invites)
  values (trim(p_title), p_description, p_event_date, v_user, coalesce(p_recurrence, 'none'), coalesce(p_admin_only_invites, false))
  returning id into v_event_id;

  -- Make creator an admin member
  insert into public.event_members (event_id, user_id, role)
  values (v_event_id, v_user, 'admin')
  on conflict do nothing;

  -- Invite additional admins if provided
  if array_length(p_admin_emails, 1) > 0 then
    foreach v_admin_email in array p_admin_emails
    loop
      -- Normalize email
      v_admin_email := lower(trim(v_admin_email));

      -- Skip if empty or invalid
      if v_admin_email = '' or v_admin_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then
        continue;
      end if;

      -- Skip if it's the creator's email
      if v_admin_email = lower(v_user_email) then
        continue;
      end if;

      -- Check if user exists
      select id into v_invitee_id
      from auth.users
      where lower(email) = v_admin_email;

      -- Create invite with admin role
      insert into public.event_invites (event_id, inviter_id, invitee_email, invitee_id, invited_role)
      values (v_event_id, v_user, v_admin_email, v_invitee_id, 'admin')
      on conflict (event_id, invitee_email) do update
        set invited_role = 'admin',
            inviter_id = v_user,
            invitee_id = excluded.invitee_id,
            status = 'pending',
            invited_at = now(),
            responded_at = null;

      -- Note: Email sending will be handled by existing edge functions/triggers
    end loop;
  end if;

  return v_event_id;
end;
$function$;

-- Update the handle_new_user trigger function to respect invited_role
-- This ensures when a user signs up, they get the correct role based on their invite
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_email text;
  v_display_name text;
  v_invite_record record;
begin
  v_email := lower(trim(new.email));

  -- Extract display name from metadata
  if new.raw_user_meta_data is not null and new.raw_user_meta_data->>'full_name' is not null then
    v_display_name := trim(new.raw_user_meta_data->>'full_name');
  else
    v_display_name := split_part(v_email, '@', 1);
  end if;

  -- Create or update profile
  insert into public.profiles (id, display_name)
  values (new.id, v_display_name)
  on conflict (id) do nothing;

  -- Auto-accept any pending invites with the invited_role
  for v_invite_record in
    select event_id, invited_role
    from public.event_invites
    where lower(invitee_email) = v_email
      and status = 'pending'
  loop
    -- Add user to event with the role specified in the invite
    insert into public.event_members (event_id, user_id, role)
    values (v_invite_record.event_id, new.id, v_invite_record.invited_role)
    on conflict (event_id, user_id) do nothing;

    -- Mark invite as accepted
    update public.event_invites
    set status = 'accepted',
        invitee_id = new.id,
        responded_at = now()
    where event_id = v_invite_record.event_id
      and lower(invitee_email) = v_email;
  end loop;

  return new;
end;
$function$;
