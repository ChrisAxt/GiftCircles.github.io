-- Migration 100: Fix Function Search Path Security
-- Fixes: function_search_path_mutable warnings from Supabase Linter
--
-- Setting search_path to '' prevents search path injection attacks where
-- malicious schemas could override function behavior.
-- All functions are recreated with fully schema-qualified references.

BEGIN;

-- ============================================================================
-- 1. Fix is_pro
-- ============================================================================
CREATE OR REPLACE FUNCTION public.is_pro(p_user uuid, p_at timestamp with time zone DEFAULT now())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = p_user
      AND plan = 'pro'
  );
$$;

-- ============================================================================
-- 2. Fix log_activity_for_digest
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
SET search_path = ''
AS $function$
BEGIN
  -- Log activity for event members who have digest enabled
  -- AND can view this list according to visibility rules
  INSERT INTO public.daily_activity_log (user_id, event_id, activity_type, activity_data)
  SELECT
    em.user_id,
    p_event_id,
    p_activity_type,
    p_activity_data
  FROM public.event_members em
  JOIN public.profiles p ON p.id = em.user_id
  WHERE em.event_id = p_event_id
    -- User is not the one who performed the action
    AND em.user_id != COALESCE(p_exclude_user_id, '00000000-0000-0000-0000-000000000000'::uuid)
    -- User has digest enabled
    AND p.notification_digest_enabled = true
    -- User can view this list (respects visibility, exclusions, viewers)
    AND public.can_view_list(p_list_id, em.user_id) = true
    -- For claims/unclaims: exclude list recipients (they shouldn't see who claimed/unclaimed their items)
    AND (
      p_activity_type NOT IN ('new_claim', 'unclaim')
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

-- ============================================================================
-- 3. Fix check_and_queue_purchase_reminders
-- ============================================================================
CREATE OR REPLACE FUNCTION public.check_and_queue_purchase_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid;
  v_display_name text;
  v_unpurchased_count int;
  v_event_count int;
  v_days_until_event int;
BEGIN
  -- Find users with unpurchased claims for events happening in 3 days
  FOR v_user_id, v_display_name, v_unpurchased_count, v_event_count, v_days_until_event IN
    SELECT
      p.id,
      p.display_name,
      COUNT(DISTINCT c.id) as unpurchased_count,
      COUNT(DISTINCT e.id) as event_count,
      MIN(e.event_date - CURRENT_DATE) as days_until
    FROM public.profiles p
    JOIN public.claims c ON c.claimer_id = p.id AND c.purchased = false
    JOIN public.items i ON i.id = c.item_id
    JOIN public.lists l ON l.id = i.list_id
    JOIN public.events e ON e.id = l.event_id
    WHERE
      e.event_date - CURRENT_DATE = 3
      AND p.plan = 'pro'
      AND EXISTS (SELECT 1 FROM public.push_tokens pt WHERE pt.user_id = p.id)
    GROUP BY p.id, p.display_name
    HAVING COUNT(DISTINCT c.id) > 0
  LOOP
    -- Queue notification
    INSERT INTO public.notification_queue (user_id, title, body, data)
    VALUES (
      v_user_id,
      'Purchase Reminder',
      format('You have %s unpurchased item(s) for %s event(s) in %s days!',
             v_unpurchased_count, v_event_count, v_days_until_event),
      jsonb_build_object(
        'type', 'purchase_reminder',
        'unpurchased_count', v_unpurchased_count,
        'event_count', v_event_count,
        'days_until', v_days_until_event
      )
    );
  END LOOP;
END;
$function$;

-- ============================================================================
-- 4. Fix notify_new_list
-- ============================================================================
CREATE OR REPLACE FUNCTION public.notify_new_list()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_creator_name text;
  v_event_title text;
BEGIN
  -- Get creator name
  SELECT display_name INTO v_creator_name
  FROM public.profiles
  WHERE id = NEW.created_by;

  -- Get event title
  SELECT title INTO v_event_title
  FROM public.events
  WHERE id = NEW.event_id;

  -- Queue instant notification for eligible event members with privacy checks
  PERFORM public.queue_notification_for_list_activity(
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
  PERFORM public.log_activity_for_digest(
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

  RETURN NEW;
END;
$function$;

-- ============================================================================
-- 5. Fix notify_new_item
-- ============================================================================
CREATE OR REPLACE FUNCTION public.notify_new_item()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_list_id uuid;
  v_list_name text;
  v_event_id uuid;
  v_event_title text;
  v_creator_name text;
BEGIN
  -- Get list details
  SELECT l.id, l.name, l.event_id
  INTO v_list_id, v_list_name, v_event_id
  FROM public.lists l
  WHERE l.id = NEW.list_id;

  -- Get event title
  SELECT title INTO v_event_title
  FROM public.events
  WHERE id = v_event_id;

  -- Get creator name
  SELECT display_name INTO v_creator_name
  FROM public.profiles
  WHERE id = NEW.created_by;

  -- Queue instant notification for eligible event members with privacy checks
  PERFORM public.queue_notification_for_list_activity(
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
  PERFORM public.log_activity_for_digest(
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

  RETURN NEW;
END;
$function$;

-- ============================================================================
-- 6. Fix notify_new_claim
-- ============================================================================
CREATE OR REPLACE FUNCTION public.notify_new_claim()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_item_name text;
  v_list_id uuid;
  v_list_name text;
  v_event_id uuid;
  v_event_title text;
  v_claimer_name text;
BEGIN
  -- Get item and list details
  SELECT i.name, i.list_id
  INTO v_item_name, v_list_id
  FROM public.items i
  WHERE i.id = NEW.item_id;

  -- Get list details
  SELECT l.name, l.event_id
  INTO v_list_name, v_event_id
  FROM public.lists l
  WHERE l.id = v_list_id;

  -- Get event title
  SELECT title INTO v_event_title
  FROM public.events
  WHERE id = v_event_id;

  -- Get claimer name
  SELECT display_name INTO v_claimer_name
  FROM public.profiles
  WHERE id = NEW.claimer_id;

  -- Queue instant notification for eligible event members with privacy checks
  -- EXCLUDES list recipients (they should never see who claimed their items)
  PERFORM public.queue_notification_for_list_activity(
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
  PERFORM public.log_activity_for_digest(
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

  RETURN NEW;
END;
$function$;

-- ============================================================================
-- 7. Fix notify_unclaim
-- ============================================================================
CREATE OR REPLACE FUNCTION public.notify_unclaim()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_item_name text;
  v_list_id uuid;
  v_list_name text;
  v_event_id uuid;
  v_event_title text;
  v_unclaimer_name text;
BEGIN
  -- Get item and list details
  SELECT i.name, i.list_id
  INTO v_item_name, v_list_id
  FROM public.items i
  WHERE i.id = OLD.item_id;

  -- Get list details
  SELECT l.name, l.event_id
  INTO v_list_name, v_event_id
  FROM public.lists l
  WHERE l.id = v_list_id;

  -- Get event title
  SELECT title INTO v_event_title
  FROM public.events
  WHERE id = v_event_id;

  -- Get unclaimer name
  SELECT display_name INTO v_unclaimer_name
  FROM public.profiles
  WHERE id = OLD.claimer_id;

  -- Queue instant notification for eligible event members with privacy checks
  -- EXCLUDES list recipients (they should never see who unclaimed their items)
  PERFORM public.queue_notification_for_list_activity(
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
  PERFORM public.log_activity_for_digest(
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

  RETURN OLD;
END;
$function$;

-- ============================================================================
-- 8. Fix grant_manual_pro
-- ============================================================================
CREATE OR REPLACE FUNCTION public.grant_manual_pro(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  UPDATE public.profiles
  SET plan = 'pro'
  WHERE id = p_user_id;
END;
$function$;

COMMIT;
