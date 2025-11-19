-- Migration: Auto-invite non-member list recipients (Safe Version)
-- When creating a list for someone not in the event, automatically invite them

-- NOTE: This migration can be safely applied even if partially applied before
-- All operations use "IF NOT EXISTS" or "IF EXISTS" to be idempotent

-- ============================================================================
-- PART 1: Update list_recipients table structure
-- ============================================================================

-- Add new columns if they don't exist
DO $$
BEGIN
  -- Add recipient_email column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'list_recipients'
      AND column_name = 'recipient_email'
  ) THEN
    ALTER TABLE public.list_recipients ADD COLUMN recipient_email text;
  END IF;

  -- Add id column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'list_recipients'
      AND column_name = 'id'
  ) THEN
    ALTER TABLE public.list_recipients ADD COLUMN id uuid DEFAULT gen_random_uuid();
  END IF;
END $$;

-- Drop old primary key and make user_id nullable
DO $$
BEGIN
  -- Drop old primary key if it exists
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'list_recipients_pkey'
      AND conrelid = 'public.list_recipients'::regclass
  ) THEN
    ALTER TABLE public.list_recipients DROP CONSTRAINT list_recipients_pkey;
  END IF;

  -- Make user_id nullable
  ALTER TABLE public.list_recipients ALTER COLUMN user_id DROP NOT NULL;

  -- Add new primary key on id
  ALTER TABLE public.list_recipients ADD CONSTRAINT list_recipients_pkey PRIMARY KEY (id);
END $$;

-- Create unique indexes to prevent duplicates
DROP INDEX IF EXISTS public.list_recipients_user_unique;
CREATE UNIQUE INDEX list_recipients_user_unique
  ON public.list_recipients (list_id, user_id)
  WHERE user_id IS NOT NULL;

DROP INDEX IF EXISTS public.list_recipients_email_unique;
CREATE UNIQUE INDEX list_recipients_email_unique
  ON public.list_recipients (list_id, lower(recipient_email))
  WHERE recipient_email IS NOT NULL;

-- Add constraint: must have either user_id OR recipient_email
ALTER TABLE public.list_recipients
  DROP CONSTRAINT IF EXISTS list_recipients_user_or_email_check;

ALTER TABLE public.list_recipients
  ADD CONSTRAINT list_recipients_user_or_email_check
  CHECK (
    (user_id IS NOT NULL AND recipient_email IS NULL)
    OR
    (user_id IS NULL AND recipient_email IS NOT NULL)
  );

-- ============================================================================
-- PART 2: Create functions
-- ============================================================================

-- Function to add recipient and auto-invite if needed
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
BEGIN
  -- Validate user can modify this list
  IF NOT EXISTS (
    SELECT 1 FROM public.lists
    WHERE id = p_list_id
      AND created_by = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not authorized to modify this list';
  END IF;

  -- Normalize email
  p_recipient_email := lower(trim(p_recipient_email));

  -- Validate email format
  IF p_recipient_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
    RAISE EXCEPTION 'Invalid email format';
  END IF;

  -- Get list and event info
  SELECT l.event_id, l.name, e.title
  INTO v_event_id, v_list_name, v_event_title
  FROM public.lists l
  JOIN public.events e ON e.id = l.event_id
  WHERE l.id = p_list_id;

  -- Get creator name
  SELECT coalesce(display_name, 'Someone') INTO v_creator_name
  FROM public.profiles
  WHERE id = auth.uid();

  -- Check if email belongs to a registered user (using security definer context)
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
    INSERT INTO public.list_recipients (list_id, user_id, recipient_email)
    VALUES (p_list_id, v_recipient_id, p_recipient_email);
  ELSE
    -- Update existing record if user_id changed (user signed up)
    UPDATE public.list_recipients
    SET user_id = v_recipient_id
    WHERE list_id = p_list_id
      AND lower(recipient_email) = p_recipient_email
      AND user_id IS NULL
      AND v_recipient_id IS NOT NULL;
  END IF;

  -- If user is not an event member, send invite
  IF NOT v_is_member THEN
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
  END IF;

  RETURN v_recipient_id;
END;
$$;

-- Function to get recipient info (including non-registered)
CREATE OR REPLACE FUNCTION public.get_list_recipients(p_list_id uuid)
RETURNS TABLE (
  list_id uuid,
  user_id uuid,
  recipient_email text,
  display_name text,
  is_registered boolean,
  is_event_member boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    lr.list_id,
    lr.user_id,
    lr.recipient_email,
    coalesce(p.display_name, lr.recipient_email) AS display_name,
    lr.user_id IS NOT NULL AS is_registered,
    EXISTS (
      SELECT 1 FROM public.event_members em
      JOIN public.lists l ON l.event_id = em.event_id
      WHERE l.id = lr.list_id
        AND em.user_id = lr.user_id
    ) AS is_event_member
  FROM public.list_recipients lr
  LEFT JOIN public.profiles p ON p.id = lr.user_id
  WHERE lr.list_id = p_list_id;
END;
$$;

-- Trigger to auto-link recipients when user signs up
CREATE OR REPLACE FUNCTION public.link_list_recipients_on_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_recipient record;
  v_list_name text;
  v_event_title text;
  v_creator_name text;
BEGIN
  -- Update all list_recipients for this email
  FOR v_recipient IN
    UPDATE public.list_recipients lr
    SET user_id = NEW.id
    WHERE lower(recipient_email) = lower(NEW.email)
      AND user_id IS NULL
    RETURNING lr.list_id, lr.recipient_email
  LOOP
    -- Get list and event info (using security definer context to access auth.users)
    SELECT l.name, e.title
    INTO v_list_name, v_event_title
    FROM public.lists l
    JOIN public.events e ON e.id = l.event_id
    WHERE l.id = v_recipient.list_id;

    -- Get creator name (using profiles, not auth.users directly)
    SELECT coalesce(p.display_name, 'Someone') INTO v_creator_name
    FROM public.lists l
    LEFT JOIN public.profiles p ON p.id = l.created_by
    WHERE l.id = v_recipient.list_id;

    -- Send notification about the list
    IF EXISTS (SELECT 1 FROM public.push_tokens WHERE user_id = NEW.id) THEN
      INSERT INTO public.notification_queue (user_id, title, body, data)
      VALUES (
        NEW.id,
        'Gift List Created',
        v_creator_name || ' created a gift list for you in ' || v_event_title,
        jsonb_build_object(
          'type', 'list_for_recipient',
          'list_id', v_recipient.list_id
        )
      );
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

-- Create trigger
DROP TRIGGER IF EXISTS trigger_link_recipients_on_signup ON public.profiles;
CREATE TRIGGER trigger_link_recipients_on_signup
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.link_list_recipients_on_signup();

-- ============================================================================
-- PART 3: Update RLS policies
-- ============================================================================

DROP POLICY IF EXISTS "list_recipients_select" ON public.list_recipients;
CREATE POLICY "list_recipients_select"
  ON public.list_recipients FOR SELECT
  USING (
    -- Event members can see all recipients
    EXISTS (
      SELECT 1 FROM public.lists l
      JOIN public.event_members em ON em.event_id = l.event_id
      WHERE l.id = list_recipients.list_id
        AND em.user_id = auth.uid()
    )
    OR
    -- Recipients can see themselves (if registered)
    auth.uid() = user_id
  );

DROP POLICY IF EXISTS "list_recipients_insert" ON public.list_recipients;
CREATE POLICY "list_recipients_insert"
  ON public.list_recipients FOR INSERT
  WITH CHECK (
    -- List creator can add recipients
    EXISTS (
      SELECT 1 FROM public.lists l
      WHERE l.id = list_recipients.list_id
        AND l.created_by = auth.uid()
    )
  );

DROP POLICY IF EXISTS "list_recipients_delete" ON public.list_recipients;
CREATE POLICY "list_recipients_delete"
  ON public.list_recipients FOR DELETE
  USING (
    -- List creator can remove recipients
    EXISTS (
      SELECT 1 FROM public.lists l
      WHERE l.id = list_recipients.list_id
        AND l.created_by = auth.uid()
    )
  );
