-- Migration: Fix list_visibility validation to match actual enum values
-- Purpose: Remove 'public' from validation checks since it's not in the enum
-- Date: 2025-10-02

BEGIN;

-- ============================================================================
-- Update create_list_with_people validation (6-arg version)
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

  -- Validate visibility value (only 'event' and 'selected' are valid)
  if p_visibility not in ('event', 'selected') then
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
-- Update create_list_with_people (5-arg version for backwards compatibility)
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

  -- Validate visibility value (only 'event' and 'selected' are valid)
  if p_visibility not in ('event', 'selected') then
    raise exception 'invalid_parameter: invalid_visibility';
  end if;

  -- Create list
  insert into public.lists (event_id, name, created_by, visibility)
  values (p_event_id, trim(p_name), v_user, coalesce(p_visibility, 'event'))
  returning id into v_list_id;

  -- Add recipients
  if array_length(p_recipients, 1) is not null then
    insert into public.list_recipients (list_id, user_id, can_view)
    select v_list_id, r, true
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

COMMIT;
