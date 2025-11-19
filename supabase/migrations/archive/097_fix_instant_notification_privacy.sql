-- Migration: Fix instant notification privacy and add unclaim notifications
-- Created: 2025-11-14
-- Purpose: Ensure instant notifications respect list visibility and recipient privacy
--          Add unclaim notifications with same privacy rules as claims
--
-- Changes:
-- 1. Create queue_notification_for_list_activity that respects can_view_list
-- 2. Update notify_new_list, notify_new_item, notify_new_claim to use new function
-- 3. Create notify_unclaim function and trigger
-- 4. Update log_activity_for_digest to handle unclaim activity

BEGIN;

-- ============================================================================
-- 1. Create privacy-aware notification queue function for list activities
-- ============================================================================

CREATE OR REPLACE FUNCTION public.queue_notification_for_list_activity(
  p_list_id uuid,
  p_event_id uuid,
  p_exclude_user_id uuid,
  p_notification_type text,
  p_title text,
  p_data jsonb,
  p_exclude_recipients boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Queue notifications for event members who:
  -- 1. Are not the excluded user (action creator)
  -- 2. Have push tokens registered
  -- 3. Have instant_notifications_enabled = true (opted in)
  -- 4. Can view the list according to visibility rules (can_view_list checks list_exclusions, visibility, viewers)
  -- 5. For claims/unclaims: Are not list recipients (they should never see who claimed/unclaimed)
  INSERT INTO public.notification_queue (user_id, title, body, data)
  SELECT
    em.user_id,
    p_title,
    '', -- Empty body, title contains the message
    p_data
  FROM public.event_members em
  JOIN public.profiles p ON p.id = em.user_id
  WHERE em.event_id = p_event_id
    -- User is not the one who performed the action
    AND em.user_id != p_exclude_user_id
    -- User has instant notifications enabled (opted in)
    AND p.instant_notifications_enabled = true
    -- User has push tokens
    AND EXISTS (
      SELECT 1
      FROM public.push_tokens pt
      WHERE pt.user_id = em.user_id
    )
    -- User can view this list (respects visibility, exclusions, viewers)
    AND public.can_view_list(p_list_id, em.user_id) = true
    -- For claims/unclaims: exclude list recipients (they should never see who claimed/unclaimed)
    AND (
      p_exclude_recipients = false
      OR
      NOT EXISTS (
        SELECT 1
        FROM public.list_recipients lr
        WHERE lr.list_id = p_list_id
          AND lr.user_id = em.user_id
      )
    );
END;
$function$;

COMMENT ON FUNCTION public.queue_notification_for_list_activity IS
'Queues instant notifications for list activities (new list, new item, claim, unclaim) with privacy checks. Uses can_view_list() to respect list visibility, exclusions, and viewers. Optionally excludes list recipients for claim/unclaim notifications.';

-- ============================================================================
-- 2. Update notify_new_list to use privacy-aware function
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

  -- Queue instant notification for eligible event members with privacy checks
  perform public.queue_notification_for_list_activity(
    NEW.id,              -- list_id for privacy checks
    NEW.event_id,
    NEW.created_by,      -- exclude list creator
    'list_created',
    v_creator_name || ' created a new list: ' || NEW.name,
    jsonb_build_object(
      'list_id', NEW.id,
      'event_id', NEW.event_id,
      'creator_name', v_creator_name,
      'list_name', NEW.name,
      'event_title', v_event_title,
      'type', 'list_created'
    ),
    false                -- don't exclude recipients (they can see list creation)
  );

  -- ALSO log activity for digest users (with privacy checks)
  perform public.log_activity_for_digest(
    NEW.event_id,
    NEW.id,              -- Pass list_id for privacy filtering
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
-- 3. Update notify_new_item to use privacy-aware function
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

  -- Queue instant notification for eligible event members with privacy checks
  perform public.queue_notification_for_list_activity(
    v_list_id,           -- list_id for privacy checks
    v_event_id,
    NEW.created_by,      -- exclude item creator
    'new_item',
    v_creator_name || ' added an item to ' || v_list_name,
    jsonb_build_object(
      'item_id', NEW.id,
      'list_id', v_list_id,
      'event_id', v_event_id,
      'item_name', NEW.name,
      'list_name', v_list_name,
      'creator_name', v_creator_name,
      'event_title', v_event_title,
      'type', 'new_item'
    ),
    false                -- don't exclude recipients (they can see items added)
  );

  -- ALSO log activity for digest users (with privacy checks)
  perform public.log_activity_for_digest(
    v_event_id,
    v_list_id,           -- Pass list_id for privacy filtering
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
-- 4. Update notify_new_claim to use privacy-aware function and exclude recipients
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
begin
  -- Get item and list details
  select i.name, i.list_id
  into v_item_name, v_list_id
  from public.items i
  where i.id = NEW.item_id;

  -- Get list details
  select l.name, l.event_id
  into v_list_name, v_event_id
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

  -- Queue instant notification for eligible event members with privacy checks
  -- EXCLUDES list recipients (they should never see who claimed their items)
  perform public.queue_notification_for_list_activity(
    v_list_id,           -- list_id for privacy checks
    v_event_id,
    NEW.claimer_id,      -- exclude claimer
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
      'event_title', v_event_title,
      'type', 'item_claimed'
    ),
    true                 -- exclude recipients (they should never see who claimed)
  );

  -- ALSO log activity for digest users (with privacy checks)
  -- This will automatically exclude list recipients via log_activity_for_digest
  perform public.log_activity_for_digest(
    v_event_id,
    v_list_id,           -- Pass list_id for privacy filtering
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

-- ============================================================================
-- 5. Create notify_unclaim function for DELETE operations on claims
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_unclaim()
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
  v_unclaimer_name text;
begin
  -- Get item and list details
  select i.name, i.list_id
  into v_item_name, v_list_id
  from public.items i
  where i.id = OLD.item_id;

  -- Get list details
  select l.name, l.event_id
  into v_list_name, v_event_id
  from public.lists l
  where l.id = v_list_id;

  -- Get event title
  select title into v_event_title
  from public.events
  where id = v_event_id;

  -- Get unclaimer name
  select display_name into v_unclaimer_name
  from public.profiles
  where id = OLD.claimer_id;

  -- Queue instant notification for eligible event members with privacy checks
  -- EXCLUDES list recipients (they should never see who unclaimed their items)
  perform public.queue_notification_for_list_activity(
    v_list_id,           -- list_id for privacy checks
    v_event_id,
    OLD.claimer_id,      -- exclude unclaimer
    'item_unclaimed',
    v_unclaimer_name || ' unclaimed ' || v_item_name || ' from ' || v_list_name,
    jsonb_build_object(
      'claim_id', OLD.id,
      'item_id', OLD.item_id,
      'list_id', v_list_id,
      'event_id', v_event_id,
      'item_name', v_item_name,
      'list_name', v_list_name,
      'unclaimer_name', v_unclaimer_name,
      'event_title', v_event_title,
      'type', 'item_unclaimed'
    ),
    true                 -- exclude recipients (they should never see who unclaimed)
  );

  -- ALSO log activity for digest users (with privacy checks)
  -- This will automatically exclude list recipients via log_activity_for_digest
  perform public.log_activity_for_digest(
    v_event_id,
    v_list_id,           -- Pass list_id for privacy filtering
    OLD.claimer_id,
    'unclaim',
    jsonb_build_object(
      'claim_id', OLD.id,
      'item_id', OLD.item_id,
      'item_name', v_item_name,
      'list_id', v_list_id,
      'list_name', v_list_name,
      'unclaimer_name', v_unclaimer_name,
      'event_title', v_event_title
    )
  );

  return OLD;
end;
$function$;

COMMENT ON FUNCTION public.notify_unclaim IS
'Triggered when a claim is deleted (unclaimed). Sends instant notifications and logs digest activity. Excludes list recipients from seeing who unclaimed.';

-- ============================================================================
-- 6. Create trigger for unclaim notifications
-- ============================================================================

DROP TRIGGER IF EXISTS trigger_notify_unclaim ON public.claims;
CREATE TRIGGER trigger_notify_unclaim
  AFTER DELETE ON public.claims
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_unclaim();

COMMENT ON TRIGGER trigger_notify_unclaim ON public.claims IS 'Sends notifications and logs digest activity when items are unclaimed';

-- ============================================================================
-- 7. Update log_activity_for_digest to handle unclaim activity and exclude recipients
-- ============================================================================

CREATE OR REPLACE FUNCTION public.log_activity_for_digest(
  p_event_id uuid,
  p_list_id uuid,
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
    -- User can view this list (respects visibility, exclusions, viewers)
    and public.can_view_list(p_list_id, em.user_id) = true
    -- For claims/unclaims: exclude list recipients (they shouldn't see who claimed/unclaimed their items)
    and (
      p_activity_type not in ('new_claim', 'unclaim')
      or
      not exists (
        select 1
        from public.list_recipients lr
        where lr.list_id = p_list_id
          and lr.user_id = em.user_id
      )
    );
end;
$function$;

COMMENT ON FUNCTION public.log_activity_for_digest IS 'Logs activity for digest notifications while respecting list visibility, exclusions, and gift surprise rules. Excludes list recipients from claim/unclaim activities.';

COMMIT;

-- Summary of Changes:
-- 1. Created queue_notification_for_list_activity that uses can_view_list() for privacy
-- 2. Updated notify_new_list to use new function (excludes list creator + list_exclusions)
-- 3. Updated notify_new_item to use new function (excludes item creator + list_exclusions)
-- 4. Updated notify_new_claim to use new function (excludes claimer + list recipients + list_exclusions)
-- 5. Created notify_unclaim function (excludes unclaimer + list recipients + list_exclusions)
-- 6. Created trigger_notify_unclaim trigger on claims DELETE
-- 7. Updated log_activity_for_digest to exclude recipients from claim/unclaim activities
--
-- Privacy protections now enforced for BOTH instant and digest notifications:
-- ✓ List visibility settings (event vs selected)
-- ✓ list_exclusions table
-- ✓ list_viewers table
-- ✓ Recipients don't see who claimed/unclaimed items from their lists
-- ✓ Action creators don't get notified about their own actions
-- ✓ Same privacy rules for instant and digest notifications
