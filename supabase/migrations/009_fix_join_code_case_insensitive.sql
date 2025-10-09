-- Migration: Fix join_event to be case-insensitive
-- Purpose: Match join codes regardless of case (they're stored lowercase, users might type uppercase)
-- Date: 2025-10-02

BEGIN;

-- ============================================================================
-- Update join_event to do case-insensitive matching
-- ============================================================================
CREATE OR REPLACE FUNCTION public.join_event(p_code text)
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

  -- Validate code
  if trim(coalesce(p_code, '')) = '' then
    raise exception 'invalid_parameter: code_required';
  end if;

  -- Check free tier membership limit
  if not public.can_join_event(v_user) then
    raise exception 'free_limit_reached';
  end if;

  -- Find event by join code (case-insensitive)
  select id into v_event_id
  from public.events
  where lower(join_code) = lower(trim(p_code));

  if v_event_id is null then
    raise exception 'invalid_join_code';
  end if;

  -- Add user as giver member
  insert into public.event_members (event_id, user_id, role)
  values (v_event_id, v_user, 'giver')
  on conflict (event_id, user_id) do nothing;

  return v_event_id;
end;
$function$;

COMMIT;
