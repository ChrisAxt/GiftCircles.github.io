-- Migration: Update free tier limits to count total memberships
-- Purpose: Free users limited to 3 total events (owned + joined), can only access 3 most recent
-- Date: 2025-10-02

BEGIN;

-- ============================================================================
-- 1. Update can_create_event to count total memberships, not just owned
-- ============================================================================
CREATE OR REPLACE FUNCTION public.can_create_event(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  select case
    when public.is_pro(p_user, now()) then true
    -- Count TOTAL event memberships (owned + joined)
    else (select count(*) < 3 from public.event_members where user_id = p_user)
  end;
$function$;

-- ============================================================================
-- 2. Create can_join_event function (same logic as can_create_event)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.can_join_event(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  select case
    when public.is_pro(p_user, now()) then true
    -- Count TOTAL event memberships (owned + joined)
    else (select count(*) < 3 from public.event_members where user_id = p_user)
  end;
$function$;

-- ============================================================================
-- 3. Update events_for_current_user to return only 3 most recent for free users
-- ============================================================================
-- Drop existing function first since return type is changing
DROP FUNCTION IF EXISTS public.events_for_current_user();

CREATE OR REPLACE FUNCTION public.events_for_current_user()
RETURNS TABLE(
  id uuid,
  title text,
  event_date date,
  join_code text,
  created_at timestamptz,
  member_count bigint,
  total_items bigint,
  claimed_count bigint,
  accessible boolean
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  with user_is_pro as (
    select public.is_pro(auth.uid(), now()) as is_pro
  ),
  user_event_memberships as (
    select
      em.event_id,
      em.created_at as joined_at,
      row_number() over (order by em.created_at desc) as recency_rank
    from public.event_members em
    where em.user_id = auth.uid()
  ),
  accessible_events as (
    select
      uem.event_id,
      case
        -- Pro users can access all events
        when (select is_pro from user_is_pro) then true
        -- Free users can only access their 3 most recent
        when uem.recency_rank <= 3 then true
        else false
      end as is_accessible
    from user_event_memberships uem
  )
  select
    e.id,
    e.title,
    e.event_date,
    e.join_code,
    e.created_at,
    (select count(*) from public.event_members em2 where em2.event_id = e.id) as member_count,
    (select count(*) from public.lists l join public.items i on i.list_id = l.id where l.event_id = e.id) as total_items,
    (select count(*) from public.lists l join public.items i on i.list_id = l.id join public.claims c on c.item_id = i.id where l.event_id = e.id) as claimed_count,
    coalesce(ae.is_accessible, false) as accessible
  from public.events e
  join accessible_events ae on ae.event_id = e.id
  order by e.created_at desc;
$function$;

-- ============================================================================
-- 4. Update join_event to check membership limit
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

  -- Find event by join code
  select id into v_event_id
  from public.events
  where join_code = upper(trim(p_code));

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
