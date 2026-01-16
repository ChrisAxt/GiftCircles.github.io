-- Migration: Manual Event Rollover - Functions
-- Created: 2026-01-05
-- Purpose: Functions for manual rollover, event flagging, and notification queueing

BEGIN;

-- ============================================================================
-- 1. Manual Rollover Function
-- ============================================================================

-- Drop old version if it exists (with 2 parameters)
DROP FUNCTION IF EXISTS public.rollover_event_manual(uuid, boolean);

-- Create new simplified version (with 1 parameter)
CREATE OR REPLACE FUNCTION public.rollover_event_manual(
  p_event_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_event RECORD;
  v_user_id uuid := auth.uid();
  v_new_date date;
  v_items_deleted integer := 0;
  v_result jsonb;
BEGIN
  -- Authentication check
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Get event details
  SELECT id, title, event_date, recurrence, owner_id, needs_rollover
  INTO v_event
  FROM public.events
  WHERE id = p_event_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'event_not_found';
  END IF;

  -- Authorization: Only owner can rollover
  IF v_event.owner_id != v_user_id THEN
    RAISE EXCEPTION 'not_authorized: Only event owner can rollover events';
  END IF;

  -- Validate recurrence
  IF v_event.recurrence = 'none' THEN
    RAISE EXCEPTION 'invalid_operation: Cannot rollover non-recurring events';
  END IF;

  -- Validate event has passed
  IF v_event.event_date >= CURRENT_DATE THEN
    RAISE EXCEPTION 'invalid_operation: Event has not passed yet';
  END IF;

  -- Calculate new date
  v_new_date := v_event.event_date;
  LOOP
    v_new_date := CASE v_event.recurrence
      WHEN 'weekly' THEN v_new_date + INTERVAL '7 days'
      WHEN 'monthly' THEN v_new_date + INTERVAL '1 month'
      WHEN 'yearly' THEN v_new_date + INTERVAL '1 year'
    END;
    EXIT WHEN v_new_date > CURRENT_DATE;
  END LOOP;

  -- Delete only claimed items (claims will cascade delete)
  WITH deleted AS (
    DELETE FROM public.items i
    USING public.lists l
    WHERE i.list_id = l.id
      AND l.event_id = p_event_id
      AND EXISTS (
        SELECT 1 FROM public.claims c WHERE c.item_id = i.id
      )
    RETURNING i.id
  )
  SELECT COUNT(*) INTO v_items_deleted FROM deleted;

  -- Update event with new date and reset flags
  UPDATE public.events
  SET
    event_date = v_new_date,
    last_rolled_at = now(),
    needs_rollover = false,
    rollover_notification_sent = false
  WHERE id = p_event_id;

  -- Build result
  v_result := jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'old_date', v_event.event_date,
    'new_date', v_new_date,
    'items_deleted', v_items_deleted
  );

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.rollover_event_manual IS
'Manually rolls over a recurring event to the next occurrence. Deletes only claimed items (and their claims). Unclaimed items remain. Only event owner can execute.';

-- ============================================================================
-- 2. Flag Events Needing Rollover
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_events_needing_rollover()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE public.events
  SET needs_rollover = true
  WHERE recurrence != 'none'
    AND event_date IS NOT NULL
    AND event_date < CURRENT_DATE
    AND needs_rollover = false;
END;
$$;

COMMENT ON FUNCTION public.update_events_needing_rollover IS
'Flags recurring events that have passed their event_date. Called daily by cron job.';

-- ============================================================================
-- 3. Check and Queue Rollover Notifications
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_and_queue_rollover_notifications()
RETURNS TABLE(notifications_queued integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_event RECORD;
  v_count int := 0;
  v_owner_local_time timestamp with time zone;
  v_owner_local_hour int;
BEGIN
  FOR v_event IN
    SELECT
      e.id,
      e.title,
      e.event_date,
      e.owner_id,
      e.recurrence,
      COALESCE(p.timezone, 'UTC') as owner_timezone
    FROM public.events e
    JOIN public.profiles p ON p.id = e.owner_id
    WHERE e.recurrence != 'none'
      AND e.event_date IS NOT NULL
      AND e.event_date < CURRENT_DATE
      AND e.needs_rollover = true
      AND e.rollover_notification_sent = false
      AND public.is_pro(e.owner_id, now()) = true
      AND EXISTS (
        SELECT 1 FROM public.push_tokens pt WHERE pt.user_id = e.owner_id
      )
  LOOP
    -- Convert to owner's local time
    BEGIN
      v_owner_local_time := now() AT TIME ZONE v_event.owner_timezone;
      v_owner_local_hour := EXTRACT(hour FROM v_owner_local_time)::int;
    EXCEPTION WHEN OTHERS THEN
      -- Fall back to UTC if timezone is invalid
      v_owner_local_time := now();
      v_owner_local_hour := EXTRACT(hour FROM v_owner_local_time)::int;
    END;

    -- Only send at 9 AM local time
    IF v_owner_local_hour != 9 THEN
      CONTINUE;
    END IF;

    -- Queue notification
    INSERT INTO public.notification_queue (user_id, title, body, data)
    VALUES (
      v_event.owner_id,
      'Event Rollover: ' || v_event.title,
      'Your recurring event "' || v_event.title || '" has passed. Tap to rollover for the next occurrence.',
      jsonb_build_object(
        'type', 'event_rollover',
        'event_id', v_event.id,
        'event_title', v_event.title,
        'event_date', v_event.event_date,
        'recurrence', v_event.recurrence
      )
    );

    -- Mark notification sent
    UPDATE public.events
    SET rollover_notification_sent = true
    WHERE id = v_event.id;

    v_count := v_count + 1;
  END LOOP;

  RETURN QUERY SELECT v_count;
END;
$$;

COMMENT ON FUNCTION public.check_and_queue_rollover_notifications IS
'Checks for events needing rollover and queues notifications at 9 AM owner local time. Called hourly by cron job.';

COMMIT;
