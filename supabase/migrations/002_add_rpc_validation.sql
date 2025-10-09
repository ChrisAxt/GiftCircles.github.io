-- Migration: Add input validation to RPC functions
-- Purpose: Validate user inputs to prevent errors and improve security
-- Date: 2025-10-02

BEGIN;

-- ============================================================================
-- 1. Update create_event_and_admin with validation
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_event_and_admin(
  p_title text,
  p_event_date date,
  p_recurrence text,
  p_description text
)
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

  -- Create event
  insert into public.events (title, description, event_date, owner_id, recurrence)
  values (trim(p_title), p_description, p_event_date, v_user, coalesce(p_recurrence, 'none'))
  returning id into v_event_id;

  -- Make creator an admin member
  insert into public.event_members (event_id, user_id, role)
  values (v_event_id, v_user, 'admin')
  on conflict do nothing;

  return v_event_id;
end;
$function$;

-- ============================================================================
-- 2. Update create_list_with_people with validation (6-arg version)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_list_with_people(
  p_event_id uuid,
  p_name text,
  p_visibility list_visibility DEFAULT 'event'::list_visibility,
  p_recipients uuid[] DEFAULT '{}'::uuid[],
  p_hidden_recipients uuid[] DEFAULT '{}'::uuid[],
  p_viewers uuid[] DEFAULT '{}'::uuid[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_user    uuid := auth.uid();
  v_list_id uuid;
begin
  -- Authentication check
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  -- Validate list name (not empty after trimming)
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'invalid_parameter: name_required';
  end if;

  -- Validate event_id exists and user is a member
  if not public.is_event_member(p_event_id, v_user) then
    raise exception 'not_authorized: must_be_event_member';
  end if;

  -- Validate visibility value
  if p_visibility not in ('event', 'selected', 'public') then
    raise exception 'invalid_parameter: invalid_visibility';
  end if;

  -- Create list
  insert into public.lists (event_id, name, created_by, visibility)
  values (p_event_id, trim(p_name), v_user, coalesce(p_visibility, 'event'))
  returning id into v_list_id;

  -- Add recipients
  if array_length(p_recipients, 1) is not null then
    insert into public.list_recipients (list_id, user_id, can_view)
    select v_list_id, r, not (r = any(coalesce(p_hidden_recipients, '{}')))
    from unnest(p_recipients) as r;
  end if;

  -- Add viewers for 'selected' visibility
  if coalesce(p_visibility, 'event') = 'selected'
     and array_length(p_viewers, 1) is not null then
    insert into public.list_viewers (list_id, user_id)
    select v_list_id, v
    from unnest(p_viewers) as v;
  end if;

  return v_list_id;
end;
$function$;

-- ============================================================================
-- 3. Update create_list_with_people (5-arg version for backwards compatibility)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_list_with_people(
  p_event_id uuid,
  p_name text,
  p_visibility list_visibility DEFAULT 'event'::list_visibility,
  p_recipients uuid[] DEFAULT '{}'::uuid[],
  p_viewers uuid[] DEFAULT '{}'::uuid[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_user    uuid := auth.uid();
  v_list_id uuid;
begin
  -- Authentication check
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  -- Validate list name (not empty after trimming)
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'invalid_parameter: name_required';
  end if;

  -- Validate event_id exists and user is a member
  if not public.is_event_member(p_event_id, v_user) then
    raise exception 'not_authorized: must_be_event_member';
  end if;

  -- Validate visibility value
  if p_visibility not in ('event', 'selected', 'public') then
    raise exception 'invalid_parameter: invalid_visibility';
  end if;

  -- Create list
  insert into public.lists (event_id, name, created_by, visibility)
  values (p_event_id, trim(p_name), v_user, coalesce(p_visibility, 'event'))
  returning id into v_list_id;

  -- Add recipients
  if array_length(p_recipients, 1) is not null then
    insert into public.list_recipients (list_id, user_id)
    select v_list_id, unnest(p_recipients);
  end if;

  -- Add viewers for 'selected' visibility
  if coalesce(p_visibility, 'event') = 'selected' and array_length(p_viewers, 1) is not null then
    insert into public.list_viewers (list_id, user_id)
    select v_list_id, unnest(p_viewers);
  end if;

  return v_list_id;
end;
$function$;

-- ============================================================================
-- 4. Update join_event with validation
-- ============================================================================
CREATE OR REPLACE FUNCTION public.join_event(p_code text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_event_id uuid;
  v_user_id  uuid := auth.uid();
begin
  -- Authentication check
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  -- Validate join code (not empty after trimming)
  if trim(coalesce(p_code, '')) = '' then
    raise exception 'invalid_parameter: code_required';
  end if;

  -- Find event by code (case-insensitive, trimmed)
  select id
    into v_event_id
  from public.events
  where upper(join_code) = upper(trim(p_code))
  limit 1;

  if v_event_id is null then
    raise exception 'invalid_join_code';
  end if;

  -- Add user as member
  insert into public.event_members(event_id, user_id, role)
  values (v_event_id, v_user_id, 'giver')
  on conflict (event_id, user_id) do nothing;

  return v_event_id;
end;
$function$;

COMMIT;
