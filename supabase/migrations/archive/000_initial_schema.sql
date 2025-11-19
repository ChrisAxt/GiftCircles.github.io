-- Initial Schema Migration
-- Purpose: Create all base tables, types, functions, and policies
-- Date: 2025-10-06 (retroactive - represents initial state)

BEGIN;

-- Enable needed extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- for gen_random_uuid()

-- ============================================================================
-- TYPES
-- ============================================================================

DO $$ BEGIN
  CREATE TYPE member_role AS ENUM ('giver','recipient','admin');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE list_visibility AS ENUM ('everyone','givers','recipients','custom');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE invite_status AS ENUM ('pending','accepted','declined');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- TABLES
-- ============================================================================

-- 1) Profiles (mirror of auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text,
  avatar_url text,
  created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 2) Events
CREATE TABLE IF NOT EXISTS public.events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text,
  event_date date,
  join_code text UNIQUE NOT NULL DEFAULT replace(gen_random_uuid()::text,'-',''),
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

-- 3) Event Members
CREATE TABLE IF NOT EXISTS public.event_members (
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role member_role NOT NULL DEFAULT 'giver',
  created_at timestamp with time zone DEFAULT now(),
  PRIMARY KEY (event_id, user_id)
);

ALTER TABLE public.event_members ENABLE ROW LEVEL SECURITY;

-- 4) Lists
CREATE TABLE IF NOT EXISTS public.lists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  name text NOT NULL,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.lists ENABLE ROW LEVEL SECURITY;

-- 5) List Recipients
CREATE TABLE IF NOT EXISTS public.list_recipients (
  list_id uuid NOT NULL REFERENCES public.lists(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_email text,
  recipient_name text,
  PRIMARY KEY (list_id, user_id)
);

ALTER TABLE public.list_recipients ENABLE ROW LEVEL SECURITY;

-- 6) Items
CREATE TABLE IF NOT EXISTS public.items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  list_id uuid NOT NULL REFERENCES public.lists(id) ON DELETE CASCADE,
  name text NOT NULL,
  url text,
  price numeric(12,2),
  notes text,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;

-- 7) Claims
CREATE TABLE IF NOT EXISTS public.claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id uuid NOT NULL REFERENCES public.items(id) ON DELETE CASCADE,
  claimer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  quantity integer NOT NULL DEFAULT 1 CHECK (quantity > 0),
  note text,
  created_at timestamp with time zone DEFAULT now(),
  UNIQUE (item_id, claimer_id)
);

ALTER TABLE public.claims ENABLE ROW LEVEL SECURITY;

-- 8) List Viewers (for custom visibility)
CREATE TABLE IF NOT EXISTS public.list_viewers (
  list_id uuid NOT NULL REFERENCES public.lists(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  PRIMARY KEY (list_id, user_id)
);

ALTER TABLE public.list_viewers ENABLE ROW LEVEL SECURITY;

-- 9) List Exclusions (users who cannot see list)
CREATE TABLE IF NOT EXISTS public.list_exclusions (
  list_id uuid NOT NULL REFERENCES public.lists(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  PRIMARY KEY (list_id, user_id)
);

ALTER TABLE public.list_exclusions ENABLE ROW LEVEL SECURITY;

-- 10) User Plans
CREATE TABLE IF NOT EXISTS public.user_plans (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_type text NOT NULL DEFAULT 'free',
  expires_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.user_plans ENABLE ROW LEVEL SECURITY;

-- 11) Notification Queue
CREATE TABLE IF NOT EXISTS public.notification_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title text NOT NULL,
  body text NOT NULL,
  data jsonb,
  sent boolean DEFAULT false,
  sent_at timestamp with time zone,
  expo_response jsonb,
  created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.notification_queue ENABLE ROW LEVEL SECURITY;

-- 12) User Devices (push notification tokens)
CREATE TABLE IF NOT EXISTS public.user_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  expo_push_token text NOT NULL,
  device_name text,
  last_used_at timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  UNIQUE(user_id, expo_push_token)
);

ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;

-- 13) Event Invites
CREATE TABLE IF NOT EXISTS public.event_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  inviter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invitee_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  invitee_email text NOT NULL,
  status invite_status NOT NULL DEFAULT 'pending',
  created_at timestamp with time zone DEFAULT now(),
  responded_at timestamp with time zone
);

ALTER TABLE public.event_invites ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.event_id_for_list(l_id uuid)
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT event_id FROM public.lists WHERE id = l_id
$$;

CREATE OR REPLACE FUNCTION public.event_id_for_item(i_id uuid)
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT l.event_id FROM public.items i JOIN public.lists l ON l.id = i.list_id WHERE i.id = i_id
$$;

CREATE OR REPLACE FUNCTION public.is_event_member(e_id uuid, u_id uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.event_members em
    WHERE em.event_id = e_id AND em.user_id = u_id
  )
$$;

CREATE OR REPLACE FUNCTION public.is_list_recipient(l_id uuid, u_id uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.list_recipients lr
    WHERE lr.list_id = l_id AND lr.user_id = u_id
  )
$$;

CREATE OR REPLACE FUNCTION public.is_pro(u_id uuid, at_time timestamptz)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_plans
    WHERE user_id = u_id
      AND plan_type != 'free'
      AND (expires_at IS NULL OR expires_at > at_time)
  );
$$;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Auto-join event as admin when creating event
CREATE OR REPLACE FUNCTION public.autojoin_event_as_admin()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.event_members(event_id, user_id, role)
  VALUES (NEW.id, NEW.owner_id, 'admin')
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END;$$;

DROP TRIGGER IF EXISTS trg_autojoin_event ON public.events;
CREATE TRIGGER trg_autojoin_event
  AFTER INSERT ON public.events
  FOR EACH ROW EXECUTE PROCEDURE public.autojoin_event_as_admin();

-- ============================================================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================================================

-- PROFILES
CREATE POLICY "profiles are readable by logged in users"
  ON public.profiles FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "users can update their own profile"
  ON public.profiles FOR UPDATE
  USING (id = auth.uid());

-- EVENTS
CREATE POLICY "select events for members"
  ON public.events FOR SELECT
  USING (public.is_event_member(id, auth.uid()));

CREATE POLICY "insert events when owner is self"
  ON public.events FOR INSERT
  WITH CHECK (owner_id = auth.uid());

-- EVENT_MEMBERS
CREATE POLICY "select membership for members"
  ON public.event_members FOR SELECT
  USING (public.is_event_member(event_id, auth.uid()));

CREATE POLICY "users can insert their own membership"
  ON public.event_members FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- LISTS
CREATE POLICY "select lists for members"
  ON public.lists FOR SELECT
  USING (public.is_event_member(event_id, auth.uid()));

CREATE POLICY "insert lists by members"
  ON public.lists FOR INSERT
  WITH CHECK (public.is_event_member(event_id, auth.uid()) AND created_by = auth.uid());

-- LIST_RECIPIENTS
CREATE POLICY "select list_recipients for members"
  ON public.list_recipients FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.lists l
      WHERE l.id = list_id
        AND public.is_event_member(l.event_id, auth.uid())
    )
  );

CREATE POLICY "insert list_recipients by list creator"
  ON public.list_recipients FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.lists l
      WHERE l.id = list_id
        AND l.created_by = auth.uid()
    )
  );

-- ITEMS
CREATE POLICY "select items for members"
  ON public.items FOR SELECT
  USING (public.is_event_member(public.event_id_for_item(id), auth.uid()));

CREATE POLICY "insert items by list creator or recipient"
  ON public.items FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.lists l
      WHERE l.id = list_id
        AND public.is_event_member(l.event_id, auth.uid())
        AND (l.created_by = auth.uid() OR public.is_list_recipient(list_id, auth.uid()))
    )
    AND created_by = auth.uid()
  );

-- CLAIMS
CREATE POLICY "select claims for non-recipients"
  ON public.claims FOR SELECT
  USING (
    public.is_event_member(public.event_id_for_item(item_id), auth.uid())
    AND NOT EXISTS (
      SELECT 1 FROM public.items i
      JOIN public.lists l ON l.id = i.list_id
      WHERE i.id = item_id
        AND public.is_list_recipient(l.id, auth.uid())
    )
  );

CREATE POLICY "insert claims by non-recipients"
  ON public.claims FOR INSERT
  WITH CHECK (
    claimer_id = auth.uid()
    AND public.is_event_member(public.event_id_for_item(item_id), auth.uid())
    AND NOT EXISTS (
      SELECT 1 FROM public.items i
      JOIN public.lists l ON l.id = i.list_id
      WHERE i.id = item_id
        AND public.is_list_recipient(l.id, auth.uid())
    )
  );

CREATE POLICY "update own claims"
  ON public.claims FOR UPDATE
  USING (claimer_id = auth.uid());

CREATE POLICY "delete own claims"
  ON public.claims FOR DELETE
  USING (claimer_id = auth.uid());

-- USER_PLANS
CREATE POLICY "users can view their own plan"
  ON public.user_plans FOR SELECT
  USING (user_id = auth.uid());

-- USER_DEVICES
CREATE POLICY "users can view their own devices"
  ON public.user_devices FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "users can insert their own devices"
  ON public.user_devices FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "users can update their own devices"
  ON public.user_devices FOR UPDATE
  USING (user_id = auth.uid());

CREATE POLICY "users can delete their own devices"
  ON public.user_devices FOR DELETE
  USING (user_id = auth.uid());

-- NOTIFICATION_QUEUE
CREATE POLICY "notification_queue_select"
  ON public.notification_queue FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "notification_queue_insert"
  ON public.notification_queue FOR INSERT
  WITH CHECK (true);

CREATE POLICY "notification_queue_update"
  ON public.notification_queue FOR UPDATE
  USING (true);

-- EVENT_INVITES
CREATE POLICY "users can view their own invites"
  ON public.event_invites FOR SELECT
  USING (invitee_id = auth.uid() OR inviter_id = auth.uid());

CREATE POLICY "event members can insert invites"
  ON public.event_invites FOR INSERT
  WITH CHECK (
    inviter_id = auth.uid()
    AND public.is_event_member(event_id, auth.uid())
  );

CREATE POLICY "invitees can update their invite status"
  ON public.event_invites FOR UPDATE
  USING (invitee_id = auth.uid());

COMMIT;
