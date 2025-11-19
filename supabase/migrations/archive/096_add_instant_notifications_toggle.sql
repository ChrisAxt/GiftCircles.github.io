-- Migration: Add instant notifications toggle (separate from digest)
-- Created: 2025-11-14
-- Purpose: Allow users to opt-in to instant notifications (off by default)
--          This is separate from the digest notifications toggle
--
-- Changes:
-- 1. Add instant_notifications_enabled column to profiles (default false)
-- 2. Update queue_notification_for_event_members to check this setting
-- 3. Keep purchase reminders always enabled (they're time-sensitive)

BEGIN;

-- ============================================================================
-- 1. Add instant_notifications_enabled column to profiles
-- ============================================================================

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS instant_notifications_enabled boolean DEFAULT false;

COMMENT ON COLUMN public.profiles.instant_notifications_enabled IS
'When true, user receives instant push notifications for list/item/claim activity. When false (default), user only receives digest notifications. Purchase reminders are always sent regardless of this setting.';

-- ============================================================================
-- 2. Update queue_notification_for_event_members to check instant setting
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
  -- Queue notifications for event members who:
  -- 1. Are not the excluded user
  -- 2. Have push tokens registered
  -- 3. Have instant_notifications_enabled = true (opted in)
  --
  -- NOTE: Purchase reminders bypass this check (handled separately)
  INSERT INTO public.notification_queue (user_id, title, body, data)
  SELECT
    em.user_id,
    p_title,
    '', -- Empty body, title contains the message
    p_data
  FROM public.event_members em
  JOIN public.profiles p ON p.id = em.user_id
  WHERE em.event_id = p_event_id
    AND em.user_id != p_exclude_user_id
    -- User has instant notifications enabled (opted in)
    AND p.instant_notifications_enabled = true
    -- User has push tokens
    AND EXISTS (
      SELECT 1
      FROM public.push_tokens pt
      WHERE pt.user_id = em.user_id
    );
END;
$function$;

COMMENT ON FUNCTION public.queue_notification_for_event_members IS
'Queues instant notifications for event members who have opted in (instant_notifications_enabled = true) and have push tokens registered. Excludes the user who triggered the action.';

COMMIT;

-- Summary of Changes:
-- 1. Added profiles.instant_notifications_enabled column (default false = off)
-- 2. Updated queue_notification_for_event_members to check instant_notifications_enabled
-- 3. Instant notifications are now opt-in (off by default)
-- 4. Digest notifications remain independent (controlled by notification_digest_enabled)
--
-- Notification types affected:
-- ✓ list_created (new lists)
-- ✓ new_item (items added)
-- ✓ item_claimed (items claimed)
-- ✓ event_invite (event invitations - may want to keep always-on)
-- ✓ event_update (event changes)
--
-- Not affected (always sent when applicable):
-- ✓ purchase_reminder (time-sensitive, always sent)
-- ✓ digest (controlled by separate toggle: notification_digest_enabled)
