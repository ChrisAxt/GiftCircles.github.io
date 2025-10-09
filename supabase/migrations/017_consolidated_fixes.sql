-- Migration 017: Consolidated Fixes
-- Date: 2025-10-06
-- Description: Bug fixes for list recipient invites, notification system, and free tier limits
-- This consolidates all fixes from the notification and invite system improvements

BEGIN;

-- ============================================================================
-- FIX 1: Update add_list_recipient with better error handling and auth
-- ============================================================================
-- Bug: add_list_recipient was failing silently when adding recipients
-- Fix: Better authorization checks, error handling, and notification queue integration

CREATE OR REPLACE FUNCTION public.add_list_recipient(
  p_list_id uuid,
  p_recipient_email text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_recipient_id uuid;
  v_event_id uuid;
  v_list_name text;
  v_creator_name text;
  v_event_title text;
  v_invite_id uuid;
  v_is_member boolean;
  v_list_creator uuid;
BEGIN
  -- Get list info and creator
  SELECT l.event_id, l.name, l.created_by, e.title
  INTO v_event_id, v_list_name, v_list_creator, v_event_title
  FROM public.lists l
  JOIN public.events e ON e.id = l.event_id
  WHERE l.id = p_list_id;

  IF v_event_id IS NULL THEN
    RAISE EXCEPTION 'List not found';
  END IF;

  -- Check authorization - must be list creator OR event member
  IF NOT (auth.uid() = v_list_creator OR EXISTS (
    SELECT 1 FROM public.event_members
    WHERE event_id = v_event_id AND user_id = auth.uid()
  )) THEN
    RAISE EXCEPTION 'Not authorized to modify this list. Caller: %, Creator: %', auth.uid(), v_list_creator;
  END IF;

  -- Normalize email
  p_recipient_email := lower(trim(p_recipient_email));

  -- Validate email format
  IF p_recipient_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
    RAISE EXCEPTION 'Invalid email format';
  END IF;

  -- Get creator name
  SELECT coalesce(display_name, 'Someone') INTO v_creator_name
  FROM public.profiles
  WHERE id = auth.uid();

  -- Check if email belongs to a registered user
  SELECT id INTO v_recipient_id
  FROM auth.users
  WHERE lower(email) = p_recipient_email;

  -- If registered user, check if they're already an event member
  IF v_recipient_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.event_members
      WHERE event_id = v_event_id
        AND user_id = v_recipient_id
    ) INTO v_is_member;
  ELSE
    v_is_member := false;
  END IF;

  -- Add recipient to list (check if already exists first)
  IF NOT EXISTS (
    SELECT 1 FROM public.list_recipients
    WHERE list_id = p_list_id
      AND (
        (user_id = v_recipient_id AND v_recipient_id IS NOT NULL)
        OR (lower(recipient_email) = p_recipient_email)
      )
  ) THEN
    -- If user is registered, use user_id only. Otherwise use email only.
    IF v_recipient_id IS NOT NULL THEN
      INSERT INTO public.list_recipients (list_id, user_id)
      VALUES (p_list_id, v_recipient_id);
    ELSE
      INSERT INTO public.list_recipients (list_id, recipient_email)
      VALUES (p_list_id, p_recipient_email);
    END IF;
  ELSE
    -- Update existing record if user_id changed (user signed up)
    UPDATE public.list_recipients
    SET user_id = v_recipient_id, recipient_email = NULL
    WHERE list_id = p_list_id
      AND lower(recipient_email) = p_recipient_email
      AND user_id IS NULL
      AND v_recipient_id IS NOT NULL;
  END IF;

  -- If user is not an event member, send invite
  IF NOT v_is_member THEN
    BEGIN
      -- Send event invite
      SELECT public.send_event_invite(v_event_id, p_recipient_email)
      INTO v_invite_id;

      -- If user is registered, also send a list notification
      IF v_recipient_id IS NOT NULL THEN
        INSERT INTO public.notification_queue (user_id, title, body, data)
        VALUES (
          v_recipient_id,
          'Gift List Created',
          v_creator_name || ' created a gift list for you in ' || v_event_title,
          jsonb_build_object(
            'type', 'list_for_recipient',
            'list_id', p_list_id,
            'event_id', v_event_id,
            'invite_id', v_invite_id
          )
        );
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Log the error but don't fail the entire operation
      RAISE WARNING 'Failed to send invite/notification: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
    END;
  END IF;

  RETURN v_recipient_id;
END;
$$;

-- ============================================================================
-- FIX 2: Add free tier limit check to accept_event_invite
-- ============================================================================
-- Bug: Free users with 3 events could accept invites, creating inaccessible 4th event
-- Fix: Check can_join_event() before accepting invite

CREATE OR REPLACE FUNCTION public.accept_event_invite(
  p_invite_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_invite record;
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();

  -- Get invite details
  SELECT * INTO v_invite
  FROM public.event_invites
  WHERE id = p_invite_id
    AND invitee_id = v_user_id
    AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invite not found or already responded';
  END IF;

  -- Check if user can join (free tier limit check)
  IF NOT public.can_join_event(v_user_id) THEN
    RAISE EXCEPTION 'free_limit_reached'
      USING HINT = 'You can only be a member of 3 events on the free plan. Upgrade to join more events.';
  END IF;

  -- Add user to event as giver
  INSERT INTO public.event_members (event_id, user_id, role)
  VALUES (v_invite.event_id, v_user_id, 'giver')
  ON CONFLICT DO NOTHING;

  -- Update invite status
  UPDATE public.event_invites
  SET status = 'accepted',
      responded_at = now()
  WHERE id = p_invite_id;
END;
$$;

-- ============================================================================
-- FIX 3: Improve notification_queue RLS policies
-- ============================================================================
-- Bug: notification_queue had overly restrictive RLS
-- Fix: Allow users to view their own notifications

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "notification_queue_select" ON public.notification_queue;
DROP POLICY IF EXISTS "notification_queue_insert" ON public.notification_queue;
DROP POLICY IF EXISTS "notification_queue_update" ON public.notification_queue;

-- Users can view their own notifications
CREATE POLICY "notification_queue_select"
  ON public.notification_queue FOR SELECT
  USING (user_id = auth.uid());

-- System can insert notifications (via SECURITY DEFINER functions)
CREATE POLICY "notification_queue_insert"
  ON public.notification_queue FOR INSERT
  WITH CHECK (true);

-- System can update notifications (via SECURITY DEFINER functions or edge functions)
CREATE POLICY "notification_queue_update"
  ON public.notification_queue FOR UPDATE
  USING (true);

COMMIT;

-- Verification queries
DO $$
BEGIN
  RAISE NOTICE '✅ Migration 017 completed successfully';
  RAISE NOTICE '   - Updated add_list_recipient with better auth and error handling';
  RAISE NOTICE '   - Added free tier limit check to accept_event_invite';
  RAISE NOTICE '   - Improved notification_queue RLS policies';
END $$;
