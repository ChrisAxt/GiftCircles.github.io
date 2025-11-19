-- Migration: Add admin_only_invites feature
-- Date: 2025-10-14
-- Description: Adds the ability to restrict event invitations to admin members only

-- Add admin_only_invites column to events table
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS admin_only_invites boolean NOT NULL DEFAULT false;

-- Update create_event_and_admin function to include admin_only_invites parameter
CREATE OR REPLACE FUNCTION public.create_event_and_admin(p_title text, p_event_date date, p_recurrence text, p_description text, p_admin_only_invites boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user uuid := auth.uid();
  v_event_id uuid;
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

  -- Create event with admin_only_invites setting
  insert into public.events (title, description, event_date, owner_id, recurrence, admin_only_invites)
  values (trim(p_title), p_description, p_event_date, v_user, coalesce(p_recurrence, 'none'), coalesce(p_admin_only_invites, false))
  returning id into v_event_id;

  -- Make creator an admin member
  insert into public.event_members (event_id, user_id, role)
  values (v_event_id, v_user, 'admin')
  on conflict do nothing;

  return v_event_id;
end;
$function$;

-- Update send_event_invite function to enforce admin-only restriction
CREATE OR REPLACE FUNCTION public.send_event_invite(p_event_id uuid, p_inviter_email text, p_recipient_email text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_invite_id uuid;
  v_admin_only_invites boolean;
  v_is_admin boolean;
begin
  -- Check if event has admin-only invites restriction
  select admin_only_invites into v_admin_only_invites
  from public.events
  where id = p_event_id;

  -- If admin-only invites is enabled, verify user is admin
  if v_admin_only_invites then
    select exists (
      select 1 from public.event_members
      where event_id = p_event_id
        and user_id = auth.uid()
        and role = 'admin'
    ) into v_is_admin;

    if not v_is_admin then
      raise exception 'Only admins can invite to this event';
    end if;
  end if;

  -- Validate email format
  if p_recipient_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then
    raise exception 'invalid_email';
  end if;

  -- Insert invite
  insert into public.event_invites (event_id, inviter_email, recipient_email)
  values (p_event_id, p_inviter_email, p_recipient_email)
  returning id into v_invite_id;

  return v_invite_id;
end;
$function$;
