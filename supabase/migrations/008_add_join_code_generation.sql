-- Migration: Add join code generation to create_event_and_admin
-- Purpose: Generate unique 6-character join codes when creating events
-- Date: 2025-10-02

BEGIN;

-- ============================================================================
-- 1. Create helper function to generate random join codes
-- ============================================================================
CREATE OR REPLACE FUNCTION public.generate_join_code()
RETURNS text
LANGUAGE plpgsql
VOLATILE
AS $function$
declare
  v_code text;
  v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- Avoid confusing chars like 0/O, 1/I
  v_code_length int := 6;
  v_exists boolean;
begin
  loop
    -- Generate random code
    v_code := '';
    for i in 1..v_code_length loop
      v_code := v_code || substr(v_chars, floor(random() * length(v_chars) + 1)::int, 1);
    end loop;

    -- Check if code already exists
    select exists(select 1 from public.events where join_code = v_code) into v_exists;

    -- If unique, return it
    if not v_exists then
      return v_code;
    end if;

    -- Otherwise loop and try again
  end loop;
end;
$function$;

-- ============================================================================
-- 2. Update create_event_and_admin to generate join code
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
  v_join_code text;
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

  -- Generate unique join code
  v_join_code := public.generate_join_code();

  -- Create event with join code
  insert into public.events (title, description, event_date, owner_id, recurrence, join_code)
  values (trim(p_title), p_description, p_event_date, v_user, coalesce(p_recurrence, 'none'), v_join_code)
  returning id into v_event_id;

  -- Make creator an admin member
  insert into public.event_members (event_id, user_id, role)
  values (v_event_id, v_user, 'admin')
  on conflict do nothing;

  return v_event_id;
end;
$function$;

COMMIT;
