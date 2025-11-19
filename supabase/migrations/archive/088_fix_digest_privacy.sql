-- Migration: Fix digest privacy violations
-- Created: 2025-11-12
-- Purpose: Update log_activity_for_digest to respect list visibility, exclusions, and prevent spoiling gift surprises

BEGIN;

-- ============================================================================
-- 1. Update log_activity_for_digest function to respect privacy rules
-- ============================================================================

-- Drop the old version of the function (4 parameters) before creating new version (5 parameters)
DROP FUNCTION IF EXISTS public.log_activity_for_digest(uuid, uuid, text, jsonb);

CREATE OR REPLACE FUNCTION public.log_activity_for_digest(
  p_event_id uuid,
  p_list_id uuid,  -- NEW: List ID for privacy checks
  p_exclude_user_id uuid,
  p_activity_type text,
  p_activity_data jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
begin
  -- Log activity for event members who have digest enabled
  -- AND can view this list according to visibility rules
  insert into public.daily_activity_log (user_id, event_id, activity_type, activity_data)
  select
    em.user_id,
    p_event_id,
    p_activity_type,
    p_activity_data
  from public.event_members em
  join public.profiles p on p.id = em.user_id
  where em.event_id = p_event_id
    -- User is not the one who performed the action
    and em.user_id != coalesce(p_exclude_user_id, '00000000-0000-0000-0000-000000000000'::uuid)
    -- User has digest enabled
    and p.notification_digest_enabled = true
    -- NEW: User can view this list (respects visibility, exclusions, viewers)
    and public.can_view_list(p_list_id, em.user_id) = true
    -- NEW: For claims, exclude the list owner (recipient shouldn't see who claimed their items)
    and (
      p_activity_type != 'new_claim'
      or
      em.user_id != (select created_by from public.lists where id = p_list_id)
    );
end;
$function$;

COMMENT ON FUNCTION public.log_activity_for_digest IS 'Logs activity for digest notifications while respecting list visibility, exclusions, and gift surprise rules';

-- ============================================================================
-- 2. Update notify_new_list to pass list_id
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_new_list()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_creator_name text;
  v_event_title text;
begin
  -- Get creator name
  select display_name into v_creator_name
  from public.profiles
  where id = NEW.created_by;

  -- Get event title
  select title into v_event_title
  from public.events
  where id = NEW.event_id;

  -- Queue instant notification for eligible event members
  perform public.queue_notification_for_event_members(
    NEW.event_id,
    NEW.created_by,
    'list_created',
    v_creator_name || ' created a new list: ' || NEW.name,
    jsonb_build_object(
      'list_id', NEW.id,
      'event_id', NEW.event_id,
      'creator_name', v_creator_name,
      'list_name', NEW.name,
      'event_title', v_event_title
    )
  );

  -- ALSO log activity for digest users (with privacy checks)
  perform public.log_activity_for_digest(
    NEW.event_id,
    NEW.id,  -- Pass list_id for privacy filtering
    NEW.created_by,
    'new_list',
    jsonb_build_object(
      'list_id', NEW.id,
      'list_name', NEW.name,
      'creator_name', v_creator_name,
      'event_title', v_event_title
    )
  );

  return NEW;
end;
$function$;

-- ============================================================================
-- 3. Update notify_new_item to pass list_id
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_new_item()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_list_id uuid;
  v_list_name text;
  v_event_id uuid;
  v_event_title text;
  v_creator_name text;
begin
  -- Get list details
  select l.id, l.name, l.event_id
  into v_list_id, v_list_name, v_event_id
  from public.lists l
  where l.id = NEW.list_id;

  -- Get event title
  select title into v_event_title
  from public.events
  where id = v_event_id;

  -- Get creator name
  select display_name into v_creator_name
  from public.profiles
  where id = NEW.created_by;

  -- Queue instant notification for eligible event members
  perform public.queue_notification_for_event_members(
    v_event_id,
    NEW.created_by,
    'new_item',
    v_creator_name || ' added an item to ' || v_list_name,
    jsonb_build_object(
      'item_id', NEW.id,
      'list_id', v_list_id,
      'event_id', v_event_id,
      'item_name', NEW.name,
      'list_name', v_list_name,
      'creator_name', v_creator_name,
      'event_title', v_event_title
    )
  );

  -- ALSO log activity for digest users (with privacy checks)
  perform public.log_activity_for_digest(
    v_event_id,
    v_list_id,  -- Pass list_id for privacy filtering
    NEW.created_by,
    'new_item',
    jsonb_build_object(
      'item_id', NEW.id,
      'item_name', NEW.name,
      'list_id', v_list_id,
      'list_name', v_list_name,
      'creator_name', v_creator_name,
      'event_title', v_event_title
    )
  );

  return NEW;
end;
$function$;

-- ============================================================================
-- 4. Update notify_new_claim to pass list_id
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_new_claim()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_item_name text;
  v_list_id uuid;
  v_list_name text;
  v_event_id uuid;
  v_event_title text;
  v_claimer_name text;
  v_list_owner_id uuid;
begin
  -- Get item and list details
  select i.name, i.list_id
  into v_item_name, v_list_id
  from public.items i
  where i.id = NEW.item_id;

  -- Get list details and owner
  select l.name, l.event_id, l.created_by
  into v_list_name, v_event_id, v_list_owner_id
  from public.lists l
  where l.id = v_list_id;

  -- Get event title
  select title into v_event_title
  from public.events
  where id = v_event_id;

  -- Get claimer name
  select display_name into v_claimer_name
  from public.profiles
  where id = NEW.claimer_id;

  -- Queue instant notification for eligible event members
  perform public.queue_notification_for_event_members(
    v_event_id,
    NEW.claimer_id,
    'item_claimed',
    v_claimer_name || ' claimed ' || v_item_name || ' from ' || v_list_name,
    jsonb_build_object(
      'claim_id', NEW.id,
      'item_id', NEW.item_id,
      'list_id', v_list_id,
      'event_id', v_event_id,
      'item_name', v_item_name,
      'list_name', v_list_name,
      'claimer_name', v_claimer_name,
      'event_title', v_event_title
    )
  );

  -- ALSO log activity for digest users (with privacy checks)
  -- This will automatically exclude the list owner (recipient) from seeing who claimed their items
  perform public.log_activity_for_digest(
    v_event_id,
    v_list_id,  -- Pass list_id for privacy filtering
    NEW.claimer_id,
    'new_claim',
    jsonb_build_object(
      'claim_id', NEW.id,
      'item_id', NEW.item_id,
      'item_name', v_item_name,
      'list_id', v_list_id,
      'list_name', v_list_name,
      'claimer_name', v_claimer_name,
      'event_title', v_event_title
    )
  );

  return NEW;
end;
$function$;

COMMIT;

-- Summary of Changes:
-- 1. Updated log_activity_for_digest to:
--    - Require list_id parameter
--    - Use can_view_list() to respect visibility settings
--    - Exclude recipients from seeing claims on their own lists
-- 2. Updated notify_new_list to pass list_id (NEW.id)
-- 3. Updated notify_new_item to pass list_id (v_list_id)
-- 4. Updated notify_new_claim to pass list_id (v_list_id)
--
-- Privacy protections now enforced:
-- ✓ List visibility settings (event vs selected)
-- ✓ list_exclusions table
-- ✓ list_viewers table
-- ✓ Recipients don't see who claimed items from their lists
-- ✓ Random assignment visibility rules
-- ✓ Secret Santa mode protected
