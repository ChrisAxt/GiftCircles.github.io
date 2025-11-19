-- Migration: Create queue_notification_for_event_members function
-- Created: 2025-11-12
-- Purpose: Define the missing function that queues notifications for event members

BEGIN;

-- ============================================================================
-- Create queue_notification_for_event_members function
-- ============================================================================

CREATE OR REPLACE FUNCTION public.queue_notification_for_event_members(
  p_event_id uuid,
  p_exclude_user_id uuid,
  p_notification_type text,
  p_title text,
  p_data jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Queue notifications for all event members except the excluded user
  -- Only send to users who have push tokens registered
  INSERT INTO public.notification_queue (user_id, title, body, data)
  SELECT
    em.user_id,
    p_title,
    '', -- Empty body, title contains the message
    p_data
  FROM public.event_members em
  WHERE em.event_id = p_event_id
    AND em.user_id != p_exclude_user_id
    AND EXISTS (
      SELECT 1
      FROM public.push_tokens pt
      WHERE pt.user_id = em.user_id
    );
END;
$function$;

COMMENT ON FUNCTION public.queue_notification_for_event_members IS
'Queues instant notifications for all event members (except excluded user) who have push tokens registered.';

COMMIT;

-- Summary:
-- Created queue_notification_for_event_members function that was being called by
-- trigger functions in migration 088 but was never defined.
--
-- This function:
-- 1. Takes an event ID, excluded user ID, notification type, title, and data
-- 2. Finds all event members except the excluded user
-- 3. Only includes users who have push tokens (so they can receive notifications)
-- 4. Inserts notification records into the notification_queue table
--
-- Called by:
-- - notify_new_list() trigger function (when a list is created)
-- - notify_new_item() trigger function (when an item is added)
-- - notify_new_claim() trigger function (when an item is claimed)
