-- ============================================================================
-- GiftCircles Consolidated Database Schema
-- Generated from current database state
-- Date: 2025-01-13
-- ============================================================================

BEGIN;

-- ============================================================================
-- EXTENSIONS
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ============================================================================
-- TYPES (ENUMS)
-- ============================================================================

DO $$ BEGIN
  CREATE TYPE member_role AS ENUM ('giver','recipient','admin');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE list_visibility AS ENUM ('everyone','givers','recipients','custom','event','selected');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- TABLES
-- ============================================================================

-- Table: claims
CREATE TABLE IF NOT EXISTS public.claims (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  item_id uuid NOT NULL,
  claimer_id uuid NOT NULL,
  quantity integer NOT NULL DEFAULT 1,
  note text,
  created_at timestamp with time zone DEFAULT now(),
  purchased boolean NOT NULL DEFAULT false
);

-- Table: daily_activity_log
CREATE TABLE IF NOT EXISTS public.daily_activity_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  event_id uuid NOT NULL,
  activity_type text NOT NULL,
  activity_data jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now()
);

-- Table: event_invites
CREATE TABLE IF NOT EXISTS public.event_invites (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL,
  inviter_id uuid NOT NULL,
  invitee_email text NOT NULL,
  invitee_id uuid,
  status text NOT NULL DEFAULT 'pending'::text,
  invited_at timestamp with time zone DEFAULT now(),
  responded_at timestamp with time zone,
  invited_role member_role NOT NULL DEFAULT 'giver'::member_role
);

-- Table: event_members
CREATE TABLE IF NOT EXISTS public.event_members (
  event_id uuid NOT NULL,
  user_id uuid NOT NULL,
  role member_role NOT NULL DEFAULT 'giver'::member_role,
  created_at timestamp with time zone DEFAULT now()
);

-- Table: events
CREATE TABLE IF NOT EXISTS public.events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text,
  event_date date,
  join_code text NOT NULL DEFAULT replace((gen_random_uuid())::text, '-'::text, ''::text),
  owner_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  recurrence text NOT NULL DEFAULT 'none'::text,
  last_rolled_at date,
  admin_only_invites boolean NOT NULL DEFAULT false
);

-- Table: items
CREATE TABLE IF NOT EXISTS public.items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  list_id uuid NOT NULL,
  name text NOT NULL,
  url text,
  price numeric,
  notes text,
  created_by uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now()
);

-- Table: list_exclusions
CREATE TABLE IF NOT EXISTS public.list_exclusions (
  list_id uuid NOT NULL,
  user_id uuid NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Table: list_recipients
CREATE TABLE IF NOT EXISTS public.list_recipients (
  list_id uuid NOT NULL,
  user_id uuid,
  can_view boolean NOT NULL DEFAULT true,
  recipient_email text,
  id uuid NOT NULL DEFAULT gen_random_uuid()
);

-- Table: list_viewers
CREATE TABLE IF NOT EXISTS public.list_viewers (
  list_id uuid NOT NULL,
  user_id uuid NOT NULL
);

-- Table: lists
CREATE TABLE IF NOT EXISTS public.lists (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL,
  name text NOT NULL,
  created_by uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  visibility list_visibility NOT NULL DEFAULT 'event'::list_visibility,
  custom_recipient_name text
);

-- Table: notification_queue
CREATE TABLE IF NOT EXISTS public.notification_queue (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  data jsonb,
  sent boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now()
);

-- Table: orphaned_lists
CREATE TABLE IF NOT EXISTS public.orphaned_lists (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  list_id uuid NOT NULL,
  event_id uuid NOT NULL,
  excluded_user_id uuid NOT NULL,
  marked_at timestamp with time zone NOT NULL DEFAULT now(),
  delete_at timestamp with time zone NOT NULL DEFAULT (now() + '30 days'::interval),
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Table: profiles
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid NOT NULL,
  display_name text,
  avatar_url text,
  created_at timestamp with time zone DEFAULT now(),
  onboarding_done boolean NOT NULL DEFAULT false,
  onboarding_at timestamp with time zone,
  plan text NOT NULL DEFAULT 'free'::text,
  pro_until timestamp with time zone,
  reminder_days integer DEFAULT 3,
  currency character varying DEFAULT 'USD'::character varying,
  notification_digest_enabled boolean DEFAULT false,
  digest_time_hour integer DEFAULT 9,
  digest_frequency text DEFAULT 'daily'::text,
  digest_day_of_week integer DEFAULT 1
);

-- Table: push_tokens
CREATE TABLE IF NOT EXISTS public.push_tokens (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  token text NOT NULL,
  platform text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

-- Table: sent_reminders
CREATE TABLE IF NOT EXISTS public.sent_reminders (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  claim_id uuid NOT NULL,
  event_id uuid NOT NULL,
  sent_at timestamp with time zone DEFAULT now()
);

-- Table: user_plans
CREATE TABLE IF NOT EXISTS public.user_plans (
  user_id uuid NOT NULL,
  pro_until timestamp with time zone
);

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION public._next_occurrence(p_date date, p_freq text, p_interval integer DEFAULT 1)
 RETURNS date
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
select case p_freq
  when 'weekly'  then p_date + (7 * p_interval)
  when 'monthly' then (p_date + (interval '1 month' * p_interval))::date
  when 'yearly'  then (p_date + (interval '1 year'  * p_interval))::date
  else p_date
end;
$function$
;

CREATE OR REPLACE FUNCTION public._pick_new_admin(p_event_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select user_id
  from public.event_members
  where event_id = p_event_id
  order by created_at nulls last, user_id
  limit 1
$function$
;

CREATE OR REPLACE FUNCTION public._test_admin_for_event_title(p_title text)
 RETURNS uuid
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT em.user_id
  FROM public.event_members em
  JOIN public.events e ON e.id = em.event_id
  WHERE e.title = p_title AND em.role = 'admin'
  LIMIT 1
$function$
;

CREATE OR REPLACE FUNCTION public._test_any_member_for_event_title(p_title text)
 RETURNS uuid
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT em.user_id
  FROM public.event_members em
  JOIN public.events e ON e.id = em.event_id
  WHERE e.title = p_title
  ORDER BY (em.role = 'admin') DESC
  LIMIT 1
$function$
;

CREATE OR REPLACE FUNCTION public._test_create_list_for_event(p_event_id uuid, p_name text, p_vis list_visibility)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Call the specific overload by explicitly typing each placeholder.
  EXECUTE
    'SELECT public.create_list_with_people(
        $1::uuid,
        $2::text,
        $3::list_visibility,
        $4::uuid[],
        $5::uuid[]
      )'
  USING
    p_event_id,
    p_name,
    p_vis,
    ARRAY[]::uuid[],   -- recipients
    ARRAY[]::uuid[];   -- viewers
END
$function$
;

CREATE OR REPLACE FUNCTION public.accept_event_invite(p_invite_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  -- Add user to event with the role from the invite
  INSERT INTO public.event_members (event_id, user_id, role)
  VALUES (v_invite.event_id, v_user_id, COALESCE(v_invite.invited_role, 'giver'))
  ON CONFLICT DO NOTHING;

  -- Update invite status
  UPDATE public.event_invites
  SET status = 'accepted',
      responded_at = now()
  WHERE id = p_invite_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.add_list_recipient(p_list_id uuid, p_recipient_email text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.allowed_event_slots(p_user uuid DEFAULT auth.uid())
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select case when public.is_pro(p_user) then 1000000 else 3 end;
$function$
;

CREATE OR REPLACE FUNCTION public.autojoin_event_as_admin()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  insert into public.event_members(event_id, user_id, role)
  values (new.id, new.owner_id, 'admin')
  on conflict do nothing;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.can_claim_item(p_item_id uuid, p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with i as (
    select i.id, i.list_id, l.event_id
    from public.items i
    join public.lists l on l.id = i.list_id
    where i.id = p_item_id
  )
  select
    exists (
      select 1 from i
      join public.event_members em
        on em.event_id = i.event_id and em.user_id = p_user
    )
    and not exists (
      select 1 from public.list_recipients lr
      join i on i.list_id = lr.list_id
      where lr.user_id = p_user
    );
$function$
;

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
$function$
;

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
$function$
;

CREATE OR REPLACE FUNCTION public.can_view_list(p_list uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT public.is_member_of_event(l.event_id)
     AND NOT EXISTS (
           SELECT 1
           FROM public.list_exclusions e
           WHERE e.list_id = p_list
             AND e.user_id = auth.uid()
         )
  FROM public.lists l
  WHERE l.id = p_list;
$function$
;

CREATE OR REPLACE FUNCTION public.can_view_list(uuid, uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with l as (
    select event_id, visibility, created_by
    from public.lists
    where id = $1
  ),
  excluded as (
    select exists(
      select 1 from public.list_exclusions
      where list_id = $1 and user_id = $2
    ) as x
  )
  select
    exists(select 1 from l)
    and not (select x from excluded)
    and (
      exists(select 1 from l where created_by = $2)
      or
      exists(select 1 from public.list_recipients lr
             where lr.list_id = $1 and lr.user_id = $2)
      or
      exists(select 1 from l where visibility = 'event'
             and exists (select 1 from public.event_members em
                         where em.event_id = l.event_id and em.user_id = $2))
      or
      exists(select 1 from l where visibility = 'selected'
             and exists (select 1 from public.list_viewers v
                         where v.list_id = $1 and v.user_id = $2))
    );
  $function$
;

CREATE OR REPLACE FUNCTION public.check_and_queue_purchase_reminders()
 RETURNS TABLE(reminders_queued integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_reminder record;
  v_count int := 0;
begin
  -- Find all unpurchased claims for upcoming events where reminder should be sent
  for v_reminder in
    select distinct
      c.id as claim_id,
      c.claimer_id as user_id,
      c.item_id,
      i.name as item_name,
      l.id as list_id,
      l.name as list_name,
      e.id as event_id,
      e.title as event_title,
      e.event_date,
      p.reminder_days,
      p.display_name
    from public.claims c
    join public.items i on i.id = c.item_id
    join public.lists l on l.id = i.list_id
    join public.events e on e.id = l.event_id
    join public.profiles p on p.id = c.claimer_id
    where
      -- Claim is not purchased
      c.purchased = false
      -- User has reminders enabled (reminder_days > 0)
      and p.reminder_days > 0
      -- Event has a date
      and e.event_date is not null
      -- Event is in the future
      and e.event_date > now()
      -- Event is within the reminder window
      and e.event_date <= (now() + (p.reminder_days || ' days')::interval)
      -- Haven't sent a reminder for this claim/event combination yet
      and not exists (
        select 1
        from public.sent_reminders sr
        where sr.claim_id = c.id
          and sr.event_id = e.id
      )
      -- User has push tokens (only send if they can receive it)
      and exists (
        select 1
        from public.push_tokens pt
        where pt.user_id = c.claimer_id
      )
  loop
    -- Calculate days until event
    declare
      v_days_until integer;
    begin
      v_days_until := extract(day from (v_reminder.event_date - now()));

      -- Queue the notification
      insert into public.notification_queue (user_id, title, body, data)
      values (
        v_reminder.user_id,
        'Purchase Reminder',
        case
          when v_days_until = 0 then 'Today: Purchase "' || v_reminder.item_name || '" for ' || v_reminder.event_title
          when v_days_until = 1 then 'Tomorrow: Purchase "' || v_reminder.item_name || '" for ' || v_reminder.event_title
          else v_days_until || ' days: Purchase "' || v_reminder.item_name || '" for ' || v_reminder.event_title
        end,
        jsonb_build_object(
          'type', 'purchase_reminder',
          'claim_id', v_reminder.claim_id,
          'item_id', v_reminder.item_id,
          'list_id', v_reminder.list_id,
          'event_id', v_reminder.event_id,
          'days_until', v_days_until
        )
      );

      -- Mark reminder as sent
      insert into public.sent_reminders (user_id, claim_id, event_id)
      values (v_reminder.user_id, v_reminder.claim_id, v_reminder.event_id);

      v_count := v_count + 1;
    end;
  end loop;

  return query select v_count;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.claim_counts_for_lists(p_list_ids uuid[])
 RETURNS TABLE(list_id uuid, claim_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with items_by_list as (
    select i.id as item_id, i.list_id
    from public.items i
    where i.list_id = any(p_list_ids)
  )
  select ibl.list_id, count(c.id)::int as claim_count
  from items_by_list ibl
  left join public.claims c on c.item_id = ibl.item_id
  join public.lists l on l.id = ibl.list_id
  where public.can_view_list(l.id, auth.uid())
  group by ibl.list_id
$function$
;

CREATE OR REPLACE FUNCTION public.claim_item(p_item_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  u uuid := auth.uid();
begin
  if u is null then
    raise exception 'not_authenticated';
  end if;

  if not can_claim_item(p_item_id, u) then
    raise exception 'not_authorized';
  end if;

  insert into public.claims(item_id, claimer_id)
  values (p_item_id, u)
  on conflict (item_id, claimer_id) do nothing;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.cleanup_old_activity_logs()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  delete from public.daily_activity_log
  where created_at < now() - interval '7 days';
end;
$function$
;

CREATE OR REPLACE FUNCTION public.cleanup_old_invites()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  delete from public.event_invites
  where status in ('accepted', 'declined')
    and responded_at < now() - interval '30 days';
end;
$function$
;

CREATE OR REPLACE FUNCTION public.cleanup_old_notifications()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  delete from public.notification_queue
  where sent = true
    and created_at < now() - interval '7 days';
end;
$function$
;

CREATE OR REPLACE FUNCTION public.cleanup_old_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  delete from public.sent_reminders sr
  using public.events e
  where sr.event_id = e.id
    and (e.event_date < now() - interval '7 days' or e.event_date is null);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.cleanup_orphaned_lists()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_deleted_count INTEGER := 0;
  v_orphaned RECORD;
BEGIN
  -- Find all orphaned lists ready for deletion
  FOR v_orphaned IN
    SELECT ol.id, ol.list_id, ol.event_id, ol.excluded_user_id
    FROM public.orphaned_lists ol
    WHERE ol.delete_at <= NOW()
  LOOP
    -- Verify the user is still the sole member before deleting
    IF is_sole_event_member(v_orphaned.event_id, v_orphaned.excluded_user_id) THEN
      -- Verify the user is still excluded from this list
      IF EXISTS(
        SELECT 1 FROM public.list_exclusions
        WHERE list_id = v_orphaned.list_id
          AND user_id = v_orphaned.excluded_user_id
      ) THEN
        -- Delete the list (cascade will handle items, claims, etc.)
        DELETE FROM public.lists WHERE id = v_orphaned.list_id;
        v_deleted_count := v_deleted_count + 1;
      END IF;
    END IF;

    -- Remove from orphaned_lists tracking table
    DELETE FROM public.orphaned_lists WHERE id = v_orphaned.id;
  END LOOP;

  RETURN v_deleted_count;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.cleanup_reminder_on_purchase()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- If item was marked as purchased, remove any pending reminders
  if NEW.purchased = true and OLD.purchased = false then
    delete from public.sent_reminders
    where claim_id = NEW.id;
  end if;

  return NEW;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.create_event_and_admin(
  p_title text,
  p_event_date date,
  p_recurrence text,
  p_description text,
  p_admin_only_invites boolean DEFAULT false,
  p_admin_emails text[] DEFAULT ARRAY[]::text[]
)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user uuid := auth.uid();
  v_event_id uuid;
  v_admin_email text;
  v_invitee_id uuid;
  v_user_email text;
begin
  -- Authentication check
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  -- Validate title (not empty after trimming)
  if trim(coalesce(p_title, '')) = '' then
    raise exception 'invalid_parameter: title_required';
  end if;

  -- Validate recurrence value
  if p_recurrence not in ('none', 'weekly', 'monthly', 'yearly') then
    raise exception 'invalid_parameter: invalid_recurrence';
  end if;

  -- Validate event_date (must be in the future or today)
  if p_event_date < current_date then
    raise exception 'invalid_parameter: event_date_must_be_future';
  end if;

  -- Check free tier limits
  if not public.can_create_event(v_user) then
    raise exception 'free_limit_reached';
  end if;

  -- Get creator's email for inviter_id
  select email into v_user_email
  from auth.users
  where id = v_user;

  -- Create event with admin_only_invites setting
  insert into public.events (title, description, event_date, owner_id, recurrence, admin_only_invites)
  values (trim(p_title), p_description, p_event_date, v_user, coalesce(p_recurrence, 'none'), coalesce(p_admin_only_invites, false))
  returning id into v_event_id;

  -- Make creator an admin member
  insert into public.event_members (event_id, user_id, role)
  values (v_event_id, v_user, 'admin')
  on conflict do nothing;

  -- Invite additional admins if provided
  if array_length(p_admin_emails, 1) > 0 then
    foreach v_admin_email in array p_admin_emails
    loop
      -- Normalize email
      v_admin_email := lower(trim(v_admin_email));

      -- Skip if empty or invalid
      if v_admin_email = '' or v_admin_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then
        continue;
      end if;

      -- Skip if it's the creator's email
      if v_admin_email = lower(v_user_email) then
        continue;
      end if;

      -- Check if user exists
      select id into v_invitee_id
      from auth.users
      where lower(email) = v_admin_email;

      -- Create invite with admin role
      insert into public.event_invites (event_id, inviter_id, invitee_email, invitee_id, invited_role)
      values (v_event_id, v_user, v_admin_email, v_invitee_id, 'admin')
      on conflict (event_id, invitee_email) do update
        set invited_role = 'admin',
            inviter_id = v_user,
            invitee_id = excluded.invitee_id,
            status = 'pending',
            invited_at = now(),
            responded_at = null;

      -- Note: Email sending will be handled by existing edge functions/triggers
    end loop;
  end if;

  return v_event_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.create_list_with_people(p_event_id uuid, p_name text, p_visibility list_visibility DEFAULT 'event'::list_visibility, p_recipients uuid[] DEFAULT '{}'::uuid[], p_hidden_recipients uuid[] DEFAULT '{}'::uuid[], p_viewers uuid[] DEFAULT '{}'::uuid[], p_custom_recipient_name text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid;
  v_list_id uuid;
  v_is_member boolean;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  -- Check membership in event
  select exists(
    select 1 from public.event_members
    where event_id = p_event_id and user_id = v_user
  ) into v_is_member;

  if not v_is_member then
    raise exception 'not_an_event_member';
  end if;

  -- Create list with custom recipient name if provided
  insert into public.lists (event_id, name, created_by, visibility, custom_recipient_name)
  values (p_event_id, trim(p_name), v_user, coalesce(p_visibility, 'event'), p_custom_recipient_name)
  returning id into v_list_id;

  -- recipients (per-recipient can_view flag)
  if array_length(p_recipients, 1) is not null then
    insert into public.list_recipients (list_id, user_id, can_view)
    select v_list_id, r, not (r = any(coalesce(p_hidden_recipients, '{}')))
    from unnest(p_recipients) as r;
  end if;

  -- explicit viewers (only matters when visibility = 'selected')
  if coalesce(p_visibility, 'event') = 'selected'
     and array_length(p_viewers, 1) is not null then
    insert into public.list_viewers (list_id, user_id)
    select v_list_id, v
    from unnest(p_viewers) as v;
  end if;

  return v_list_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.create_list_with_people(p_event_id uuid, p_name text, p_visibility list_visibility DEFAULT 'event'::list_visibility, p_recipients uuid[] DEFAULT '{}'::uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user    uuid := auth.uid();
  v_list_id uuid;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if not public.is_event_member(p_event_id, v_user) then
    raise exception 'not_an_event_member';
  end if;

  insert into public.lists (event_id, name, created_by, visibility)
  values (p_event_id, trim(p_name), v_user, coalesce(p_visibility, 'event'))
  returning id into v_list_id;

  if array_length(p_recipients, 1) is not null then
    insert into public.list_recipients (list_id, user_id)
    select v_list_id, unnest(p_recipients);
  end if;

  return v_list_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.create_list_with_people(p_event_id uuid, p_name text, p_visibility text, p_custom_recipient_name text, p_recipient_user_ids uuid[], p_recipient_emails text[], p_viewer_ids uuid[], p_exclusion_ids uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_list_id uuid;
  v_recipient_id uuid;
  v_recipient_email text;
begin
  -- Validate inputs
  if p_name is null or trim(p_name) = '' then
    raise exception 'List name cannot be empty' using errcode = 'invalid_parameter';
  end if;

  if p_visibility not in ('private', 'shared', 'public') then
    raise exception 'Invalid visibility value' using errcode = 'invalid_parameter';
  end if;

  -- Validate user is member of event
  if not exists (
    select 1 from public.event_members
    where event_id = p_event_id and user_id = auth.uid()
  ) then
    raise exception 'Not authorized' using errcode = 'insufficient_privilege';
  end if;

  -- Create list
  insert into public.lists (event_id, name, visibility, custom_recipient_name, created_by)
  values (p_event_id, p_name, p_visibility::visibility_level, p_custom_recipient_name, auth.uid())
  returning id into v_list_id;

  -- Add user ID recipients
  if p_recipient_user_ids is not null then
    foreach v_recipient_id in array p_recipient_user_ids loop
      if not exists (
        select 1 from public.list_recipients
        where list_id = v_list_id and user_id = v_recipient_id
      ) then
        insert into public.list_recipients (list_id, user_id)
        values (v_list_id, v_recipient_id);
      end if;
    end loop;
  end if;

  -- Add email recipients (auto-invites non-members)
  if p_recipient_emails is not null then
    foreach v_recipient_email in array p_recipient_emails loop
      perform public.add_list_recipient(v_list_id, v_recipient_email);
    end loop;
  end if;

  -- Add viewers
  if p_viewer_ids is not null then
    insert into public.list_viewers (list_id, user_id)
    select v_list_id, unnest(p_viewer_ids)
    on conflict do nothing;
  end if;

  -- Add exclusions
  if p_exclusion_ids is not null then
    insert into public.list_exclusions (list_id, user_id)
    select v_list_id, unnest(p_exclusion_ids)
    on conflict do nothing;
  end if;

  return v_list_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.create_list_with_people(p_event_id uuid, p_name text, p_visibility list_visibility DEFAULT 'event'::list_visibility, p_recipients uuid[] DEFAULT '{}'::uuid[], p_viewers uuid[] DEFAULT '{}'::uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user    uuid := auth.uid();
  v_list_id uuid;
begin
  -- Authentication check
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  -- Validate list name (not empty after trimming)
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'invalid_parameter: name_required';
  end if;

  -- Validate event_id exists and user is a member
  if not public.is_event_member(p_event_id, v_user) then
    raise exception 'not_authorized: must_be_event_member';
  end if;

  -- Validate visibility value
  if p_visibility not in ('event', 'selected', 'public') then
    raise exception 'invalid_parameter: invalid_visibility';
  end if;

  -- Create list
  insert into public.lists (event_id, name, created_by, visibility)
  values (p_event_id, trim(p_name), v_user, coalesce(p_visibility, 'event'))
  returning id into v_list_id;

  -- Add recipients
  if array_length(p_recipients, 1) is not null then
    insert into public.list_recipients (list_id, user_id)
    select v_list_id, unnest(p_recipients);
  end if;

  -- Add viewers for 'selected' visibility
  if coalesce(p_visibility, 'event') = 'selected' and array_length(p_viewers, 1) is not null then
    insert into public.list_viewers (list_id, user_id)
    select v_list_id, unnest(p_viewers);
  end if;

  return v_list_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.create_list_with_people(p_event_id uuid, p_name text, p_visibility list_visibility DEFAULT 'event'::list_visibility, p_recipients uuid[] DEFAULT '{}'::uuid[], p_hidden_recipients uuid[] DEFAULT '{}'::uuid[], p_viewers uuid[] DEFAULT '{}'::uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user    uuid := auth.uid();
  v_list_id uuid;
begin
  -- Authentication check
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  -- Validate list name (not empty after trimming)
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'invalid_parameter: name_required';
  end if;

  -- Validate event_id exists and user is a member
  if not public.is_event_member(p_event_id, v_user) then
    raise exception 'not_authorized: must_be_event_member';
  end if;

  -- Validate visibility value
  if p_visibility not in ('event', 'selected', 'public') then
    raise exception 'invalid_parameter: invalid_visibility';
  end if;

  -- Create list
  insert into public.lists (event_id, name, created_by, visibility)
  values (p_event_id, trim(p_name), v_user, coalesce(p_visibility, 'event'))
  returning id into v_list_id;

  -- Add recipients
  if array_length(p_recipients, 1) is not null then
    insert into public.list_recipients (list_id, user_id, can_view)
    select v_list_id, r, not (r = any(coalesce(p_hidden_recipients, '{}')))
    from unnest(p_recipients) as r;
  end if;

  -- Add viewers for 'selected' visibility
  if coalesce(p_visibility, 'event') = 'selected'
     and array_length(p_viewers, 1) is not null then
    insert into public.list_viewers (list_id, user_id)
    select v_list_id, v
    from unnest(p_viewers) as v;
  end if;

  return v_list_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.decline_event_invite(p_invite_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  -- Update invite status
  UPDATE public.event_invites
  SET status = 'declined',
      responded_at = now()
  WHERE id = p_invite_id
    AND invitee_id = auth.uid()
    AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invite not found or already responded';
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.delete_item(p_item_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_row record;
  v_is_admin boolean := false;
  v_is_list_owner boolean := false;
  v_is_item_owner boolean := false;
  v_has_claims boolean := false;
  v_list_creator_in_event boolean := false;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select i.id, i.created_by as item_creator,
         l.id as list_id, l.created_by as list_creator, l.event_id
    into v_row
  from public.items i
  join public.lists l on l.id = i.list_id
  where i.id = p_item_id;

  if not found then
    raise exception 'not_found';
  end if;

  -- Check if user is a member of the event
  if not exists (
    select 1 from public.event_members
    where event_id = v_row.event_id
      and user_id = v_uid
  ) then
    raise exception 'not_authorized';
  end if;

  v_is_item_owner := (v_row.item_creator = v_uid);
  v_is_list_owner := (v_row.list_creator = v_uid);
  v_is_admin := exists(
    select 1 from public.event_members em
    join public.events e on e.id = em.event_id
    where em.event_id = v_row.event_id
      and em.user_id  = v_uid
      and (em.role = 'admin' or e.owner_id = v_uid)
  );

  -- Check if the list creator is still in the event
  select exists(
    select 1 from public.event_members
    where event_id = v_row.event_id
      and user_id = v_row.list_creator
  ) into v_list_creator_in_event;

  select exists(select 1 from public.claims c where c.item_id = p_item_id) into v_has_claims;

  -- Allow deletion if:
  -- 1. User is item owner, list owner, or admin, OR
  -- 2. List creator is no longer in the event (orphaned list)
  if not (v_is_item_owner or v_is_list_owner or v_is_admin or not v_list_creator_in_event) then
    raise exception 'not_authorized';
  end if;

  -- Only admins and list owners can delete items with claims
  -- Exception: if list creator is gone, any member can delete
  if v_has_claims and not (v_is_admin or v_is_list_owner or not v_list_creator_in_event) then
    raise exception 'has_claims';
  end if;

  delete from public.claims where item_id = p_item_id;
  delete from public.items  where id      = p_item_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.delete_list(p_list_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user   uuid := auth.uid();
  v_event  uuid;
  v_owner  uuid;
  v_creator_in_event boolean;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  select l.event_id, l.created_by
    into v_event, v_owner
  from public.lists l
  where l.id = p_list_id;

  if v_event is null then
    raise exception 'not_found';
  end if;

  -- Check if user is a member of the event
  if not exists (
    select 1 from public.event_members
    where event_id = v_event
      and user_id = v_user
  ) then
    raise exception 'not_authorized';
  end if;

  -- Check if the original creator is still in the event
  select exists(
    select 1 from public.event_members
    where event_id = v_event
      and user_id = v_owner
  ) into v_creator_in_event;

  -- Allow deletion if:
  -- 1. User is the creator, OR
  -- 2. User is event admin or event owner, OR
  -- 3. Creator is no longer in the event (orphaned list)
  if v_owner = v_user then
    -- User is the creator, allow deletion
    delete from public.lists where id = p_list_id;
    return;
  end if;

  -- Check if user is event admin or event owner
  if exists (
    select 1 from public.event_members em
    join public.events e on e.id = em.event_id
    where em.event_id = v_event
      and em.user_id = v_user
      and (em.role = 'admin' or e.owner_id = v_user)
  ) then
    -- User is admin/owner, allow deletion
    delete from public.lists where id = p_list_id;
    return;
  end if;

  -- Check if creator is no longer in the event
  if not v_creator_in_event then
    -- Creator is gone, any event member can delete
    delete from public.lists where id = p_list_id;
    return;
  end if;

  -- If none of the above conditions are met, user is not authorized
  raise exception 'not_authorized';
end;
$function$
;

CREATE OR REPLACE FUNCTION public.ensure_event_owner_member()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.owner_id is not null then
    insert into public.event_members(event_id, user_id, role)
    values (new.id, new.owner_id, 'admin')
    on conflict (event_id, user_id)
    do update set role = excluded.role
    where event_members.role <> 'admin';
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.event_claim_counts_for_user(p_event_ids uuid[])
 RETURNS TABLE(event_id uuid, claim_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as (select auth.uid() as uid),

  visible_lists as (
    select l.id, l.event_id
    from public.lists l, me
    where l.event_id = any(p_event_ids)
      and public.can_view_list(l.id, (select uid from me))
      and not exists (
        select 1 from public.list_recipients lr
        where lr.list_id = l.id
          and lr.user_id = (select uid from me)
      )
  ),

  items_by_event as (
    select i.id as item_id, vl.event_id
    from public.items i
    join visible_lists vl on vl.id = i.list_id
  ),

  claims_on_visible as (
    select ibe.event_id
    from public.claims c
    join items_by_event ibe on ibe.item_id = c.item_id
  )

  select event_id, count(*)::int as claim_count
  from claims_on_visible
  group by event_id;
$function$
;

CREATE OR REPLACE FUNCTION public.event_id_for_item(i_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select l.event_id
  from public.items i
  join public.lists l on l.id = i.list_id
  where i.id = i_id
$function$
;

CREATE OR REPLACE FUNCTION public.event_id_for_list(uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT event_id FROM public.lists WHERE id = $1
$function$
;

CREATE OR REPLACE FUNCTION public.event_is_accessible(p_event_id uuid, p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    with ranked as (
      select e.id,
             row_number() over (partition by em.user_id order by e.created_at desc, e.id) rn
      from public.events e
      join public.event_members em on em.event_id = e.id
      where em.user_id = p_user
    )
    select case
      when public.is_pro(p_user, now()) then true
      else exists(select 1 from ranked r where r.id = p_event_id and r.rn <= 3)
    end;
  $function$
;

CREATE OR REPLACE FUNCTION public.events_for_current_user()
 RETURNS TABLE(id uuid, title text, event_date date, join_code text, created_at timestamp with time zone, member_count bigint, total_items bigint, claimed_count bigint, accessible boolean, rownum integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as (select auth.uid() as uid),
  my_events as (
    select e.*
    from events e
    join event_members em on em.event_id = e.id
    join me on me.uid = em.user_id
  ),
  counts as (
    select
      l.event_id,
      count(distinct l.id) as list_count,
      count(i.id)          as total_items
    from lists l
    left join items i on i.list_id = l.id
    group by l.event_id
  ),
  claims as (
    select l.event_id, count(distinct c.id) as claimed_count
    from lists l
    join items i on i.list_id = l.id
    left join claims c on c.item_id = i.id
    where l.created_by = auth.uid()
    group by l.event_id
  ),
  ranked as (
    select
      e.id, e.title, e.event_date, e.join_code, e.created_at,
      (select count(*) from event_members em2 where em2.event_id = e.id) as member_count,
      coalesce(ct.total_items, 0) as total_items,
      coalesce(cl.claimed_count, 0) as claimed_count,
      row_number() over (order by e.created_at asc nulls last, e.id) as rownum
    from my_events e
    left join counts ct on ct.event_id = e.id
    left join claims cl on cl.event_id = e.id
  )
  select
    r.id, r.title, r.event_date, r.join_code, r.created_at,
    r.member_count, r.total_items, r.claimed_count,
    (r.rownum <= public.allowed_event_slots()) as accessible,
    r.rownum
  from ranked r
  order by r.created_at desc nulls last, r.id;
$function$
;

CREATE OR REPLACE FUNCTION public.generate_and_send_daily_digests(p_hour integer DEFAULT NULL::integer)
 RETURNS TABLE(digests_sent integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_user record;
  v_count int := 0;
  v_target_hour int;
  v_current_day_of_week int;
  v_activity_summary jsonb;
  v_events_affected text[];
  v_title text;
  v_body text;
  v_lookback_interval interval;
begin
  -- Use provided hour or current hour
  v_target_hour := coalesce(p_hour, extract(hour from now())::int);
  -- Get current day of week (0=Sunday, 1=Monday, ..., 6=Saturday)
  v_current_day_of_week := extract(dow from now())::int;

  -- Process each user who has digest enabled for this hour
  for v_user in
    select distinct
      p.id as user_id,
      p.display_name,
      p.digest_frequency,
      p.digest_day_of_week
    from public.profiles p
    where p.notification_digest_enabled = true
      and p.digest_time_hour = v_target_hour
      -- Filter by frequency: daily always matches, weekly only on the right day
      and (
        (p.digest_frequency = 'daily') or
        (p.digest_frequency = 'weekly' and p.digest_day_of_week = v_current_day_of_week)
      )
      -- Only process if they have activity (lookback depends on frequency)
      and exists (
        select 1
        from public.daily_activity_log dal
        where dal.user_id = p.id
          and dal.created_at >= case
            when p.digest_frequency = 'weekly' then now() - interval '7 days'
            else now() - interval '24 hours'
          end
          and dal.created_at < now()
      )
      -- Only send if they have push tokens
      and exists (
        select 1 from public.push_tokens pt where pt.user_id = p.id
      )
  loop
    -- Set lookback interval based on frequency
    v_lookback_interval := case
      when v_user.digest_frequency = 'weekly' then interval '7 days'
      else interval '24 hours'
    end;

    -- Aggregate activity for this user
    with activity_counts as (
      select
        event_id,
        activity_type,
        count(*) as count
      from public.daily_activity_log
      where user_id = v_user.user_id
        and created_at >= now() - v_lookback_interval
        and created_at < now()
      group by event_id, activity_type
    ),
    event_summaries as (
      select
        e.title as event_title,
        jsonb_object_agg(
          ac.activity_type,
          ac.count
        ) as counts
      from activity_counts ac
      join public.events e on e.id = ac.event_id
      group by e.id, e.title
    )
    select
      jsonb_agg(
        jsonb_build_object(
          'event_title', es.event_title,
          'counts', es.counts
        )
      ),
      array_agg(es.event_title)
    into v_activity_summary, v_events_affected
    from event_summaries es;

    -- Build notification title and body
    declare
      v_total_lists int := 0;
      v_total_items int := 0;
      v_total_claims int := 0;
      v_event jsonb;
      v_time_period text;
    begin
      -- Count totals across all events
      for v_event in select jsonb_array_elements(v_activity_summary)
      loop
        v_total_lists := v_total_lists + coalesce((v_event->'counts'->>'new_list')::int, 0);
        v_total_items := v_total_items + coalesce((v_event->'counts'->>'new_item')::int, 0);
        v_total_claims := v_total_claims + coalesce((v_event->'counts'->>'new_claim')::int, 0);
      end loop;

      -- Build notification text
      if v_user.digest_frequency = 'weekly' then
        v_title := 'Weekly Activity Digest';
        v_time_period := 'This week: ';
      else
        v_title := 'Daily Activity Digest';
        v_time_period := 'Yesterday: ';
      end if;

      v_body := v_time_period;

      if v_total_lists > 0 then
        v_body := v_body || v_total_lists || ' new list' || (case when v_total_lists > 1 then 's' else '' end);
      end if;

      if v_total_items > 0 then
        if v_total_lists > 0 then v_body := v_body || ', '; end if;
        v_body := v_body || v_total_items || ' new item' || (case when v_total_items > 1 then 's' else '' end);
      end if;

      if v_total_claims > 0 then
        if v_total_lists > 0 or v_total_items > 0 then v_body := v_body || ', '; end if;
        v_body := v_body || v_total_claims || ' new claim' || (case when v_total_claims > 1 then 's' else '' end);
      end if;

      -- Add event info
      if array_length(v_events_affected, 1) = 1 then
        v_body := v_body || ' in ' || v_events_affected[1];
      elsif array_length(v_events_affected, 1) = 2 then
        v_body := v_body || ' in ' || v_events_affected[1] || ' and ' || v_events_affected[2];
      elsif array_length(v_events_affected, 1) > 2 then
        v_body := v_body || ' in ' || v_events_affected[1] || ' and ' || (array_length(v_events_affected, 1) - 1) || ' other events';
      end if;
    end;

    -- Queue the digest notification
    insert into public.notification_queue (user_id, title, body, data)
    values (
      v_user.user_id,
      v_title,
      v_body,
      jsonb_build_object(
        'type', 'digest',
        'frequency', v_user.digest_frequency,
        'activity_summary', v_activity_summary,
        'generated_at', now()
      )
    );

    v_count := v_count + 1;

    -- Clean up processed activity logs for this user
    -- For weekly, keep the logs until after the digest is sent
    delete from public.daily_activity_log
    where user_id = v_user.user_id
      and created_at < now();
  end loop;

  return query select v_count;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_list_recipients(p_list_id uuid)
 RETURNS TABLE(list_id uuid, user_id uuid, recipient_email text, display_name text, is_registered boolean, is_event_member boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return query
  select
    lr.list_id,
    lr.user_id,
    lr.recipient_email,
    coalesce(p.display_name, lr.recipient_email) as display_name,
    lr.user_id is not null as is_registered,
    exists (
      select 1 from public.event_members em
      join public.lists l on l.event_id = em.event_id
      where l.id = lr.list_id
        and em.user_id = lr.user_id
    ) as is_event_member
  from public.list_recipients lr
  left join public.profiles p on p.id = lr.user_id
  where lr.list_id = p_list_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_pending_invites()
 RETURNS TABLE(invite_id uuid, event_id uuid, event_title text, event_date date, inviter_name text, invited_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return query
  select
    ei.id as invite_id,
    e.id as event_id,
    e.title as event_title,
    e.event_date,
    coalesce(p.display_name, u.email) as inviter_name,
    ei.invited_at
  from public.event_invites ei
  join public.events e on e.id = ei.event_id
  join auth.users u on u.id = ei.inviter_id
  left join public.profiles p on p.id = ei.inviter_id
  where ei.invitee_id = auth.uid()
    and ei.status = 'pending'
  order by ei.invited_at desc;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_email text;
  v_display_name text;
  v_invite_record record;
begin
  v_email := lower(trim(new.email));

  -- Extract display name from metadata
  if new.raw_user_meta_data is not null and new.raw_user_meta_data->>'full_name' is not null then
    v_display_name := trim(new.raw_user_meta_data->>'full_name');
  else
    v_display_name := split_part(v_email, '@', 1);
  end if;

  -- Create or update profile
  insert into public.profiles (id, display_name)
  values (new.id, v_display_name)
  on conflict (id) do nothing;

  -- Auto-accept any pending invites with the invited_role
  for v_invite_record in
    select event_id, invited_role
    from public.event_invites
    where lower(invitee_email) = v_email
      and status = 'pending'
  loop
    -- Add user to event with the role specified in the invite
    insert into public.event_members (event_id, user_id, role)
    values (v_invite_record.event_id, new.id, v_invite_record.invited_role)
    on conflict (event_id, user_id) do nothing;

    -- Mark invite as accepted
    update public.event_invites
    set status = 'accepted',
        invitee_id = new.id,
        responded_at = now()
    where event_id = v_invite_record.event_id
      and lower(invitee_email) = v_email;
  end loop;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.is_event_admin(e_id uuid, u_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(select 1 from public.event_members em where em.event_id=e_id and em.user_id=u_id and em.role='admin')
$function$
;

CREATE OR REPLACE FUNCTION public.is_event_admin(e_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.event_members em
    WHERE em.event_id = e_id
      AND em.user_id  = auth.uid()
      AND em.role     = 'admin'
  );
$function$
;

CREATE OR REPLACE FUNCTION public.is_event_member(p_event_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.event_members em
    WHERE em.event_id = p_event_id
      AND em.user_id  = auth.uid()
  );
$function$
;

CREATE OR REPLACE FUNCTION public.is_event_member(e_id uuid, u_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(select 1 from public.event_members em
                where em.event_id = e_id and em.user_id = u_id)
$function$
;

CREATE OR REPLACE FUNCTION public.is_last_event_member(e_id uuid, u_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  SELECT
    -- User must be a member
    EXISTS (
      SELECT 1 FROM public.event_members
      WHERE event_id = e_id AND user_id = u_id
    )
    AND
    -- Only one member total
    (SELECT count(*) FROM public.event_members WHERE event_id = e_id) = 1
$function$
;

CREATE OR REPLACE FUNCTION public.is_list_recipient(l_id uuid, u_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(
    select 1
    from public.list_recipients lr
    where lr.list_id = l_id and lr.user_id = u_id
  )
$function$
;

CREATE OR REPLACE FUNCTION public.is_member_of_event(e_id uuid, u_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT public.is_member_of_event_secure(e_id, u_id);
$function$
;

CREATE OR REPLACE FUNCTION public.is_member_of_event(p_event uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT public.is_member_of_event_secure(p_event, auth.uid());
$function$
;

CREATE OR REPLACE FUNCTION public.is_member_of_event_secure(p_event_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.event_members
    WHERE event_id = p_event_id
      AND user_id = p_user_id
  );
$function$
;

CREATE OR REPLACE FUNCTION public.is_pro(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select public.is_pro(p_user, now());
$function$
;

CREATE OR REPLACE FUNCTION public.is_pro(p_user uuid, p_at timestamp with time zone)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select (plan = 'pro') or (pro_until is not null and pro_until >= p_at)
       from public.profiles where id = p_user),
    false
  );
$function$
;

CREATE OR REPLACE FUNCTION public.is_pro_v2(p_user uuid, p_at timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  until_ts timestamptz;
begin
  if p_user is null then
    return false;
  end if;

  if to_regclass('public.user_plans') is null then
    return false;
  end if;

  select pro_until into until_ts
  from public.user_plans
  where user_id = p_user;

  return coalesce(until_ts >= p_at, false);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.is_sole_event_member(p_event_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  RETURN (
    SELECT COUNT(*) = 1
    FROM public.event_members
    WHERE event_id = p_event_id
  ) AND (
    SELECT EXISTS(
      SELECT 1
      FROM public.event_members
      WHERE event_id = p_event_id
        AND user_id = p_user_id
    )
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.join_event(p_code text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_event_id uuid;
  v_user_id  uuid := auth.uid();
begin
  -- Authentication check
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  -- Validate join code (not empty after trimming)
  if trim(coalesce(p_code, '')) = '' then
    raise exception 'invalid_parameter: code_required';
  end if;

  -- Find event by code (case-insensitive, trimmed)
  select id
    into v_event_id
  from public.events
  where upper(join_code) = upper(trim(p_code))
  limit 1;

  if v_event_id is null then
    raise exception 'invalid_join_code';
  end if;

  -- Add user as member
  insert into public.event_members(event_id, user_id, role)
  values (v_event_id, v_user_id, 'giver')
  on conflict (event_id, user_id) do nothing;

  return v_event_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.leave_event(p_event_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_role public.member_role;
  v_owner uuid;
  v_remaining integer;
  v_admins integer;
  v_new_admin uuid;
  v_deleted boolean := false;
  v_transferred boolean := false;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select role into v_role
  from public.event_members
  where event_id = p_event_id and user_id = v_uid;
  if not found then
    raise exception 'not_member';
  end if;

  select owner_id into v_owner from public.events where id = p_event_id;

  delete from public.claims c
  using public.items i, public.lists l
  where c.item_id = i.id
    and i.list_id = l.id
    and l.event_id = p_event_id
    and c.claimer_id = v_uid;

  delete from public.list_recipients lr
  using public.lists l2
  where lr.list_id = l2.id
    and l2.event_id = p_event_id
    and lr.user_id = v_uid;

  delete from public.event_members
  where event_id = p_event_id and user_id = v_uid;

  select count(*) into v_remaining
  from public.event_members
  where event_id = p_event_id;

  if v_remaining = 0 then
    delete from public.events where id = p_event_id;
    v_deleted := true;
    return json_build_object('removed', true, 'deleted_event', v_deleted, 'transferred', v_transferred, 'new_admin', null);
  end if;

  select count(*) into v_admins
  from public.event_members
  where event_id = p_event_id and role = 'admin';

  if v_admins = 0 then
    select public._pick_new_admin(p_event_id) into v_new_admin;
    if v_new_admin is not null then
      update public.event_members
      set role = 'admin'
      where event_id = p_event_id and user_id = v_new_admin;
      v_transferred := true;
    end if;
  end if;

  if v_owner = v_uid then
    select user_id into v_new_admin
    from public.event_members
    where event_id = p_event_id and role = 'admin'
    limit 1;

    if v_new_admin is null then
      select public._pick_new_admin(p_event_id) into v_new_admin;
    end if;

    if v_new_admin is not null then
      update public.events set owner_id = v_new_admin where id = p_event_id;
      v_transferred := true;
    end if;
  end if;

  return json_build_object('removed', true, 'deleted_event', v_deleted, 'transferred', v_transferred, 'new_admin', v_new_admin);
end
$function$
;

CREATE OR REPLACE FUNCTION public.link_list_recipients_on_signup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_recipient record;
  v_list_name text;
  v_event_title text;
  v_creator_name text;
BEGIN
  BEGIN
    FOR v_recipient IN
      UPDATE public.list_recipients lr
      SET user_id = NEW.id
      WHERE lower(recipient_email) = lower(NEW.email) AND user_id IS NULL
      RETURNING lr.list_id, lr.recipient_email
    LOOP
      SELECT l.name, e.title INTO v_list_name, v_event_title
      FROM public.lists l JOIN public.events e ON e.id = l.event_id
      WHERE l.id = v_recipient.list_id;

      SELECT coalesce(p.display_name, 'Someone') INTO v_creator_name
      FROM public.lists l LEFT JOIN public.profiles p ON p.id = l.created_by
      WHERE l.id = v_recipient.list_id;

      IF EXISTS (SELECT 1 FROM public.push_tokens WHERE user_id = NEW.id) THEN
        INSERT INTO public.notification_queue (user_id, title, body, data)
        VALUES (
          NEW.id,
          'Gift List Created',
          v_creator_name || ' created a gift list for you in ' || v_event_title,
          jsonb_build_object('type', 'list_for_recipient', 'list_id', v_recipient.list_id)
        );
      END IF;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    NULL; -- Don't fail signup
  END;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.list_claim_counts_for_user(p_list_ids uuid[])
 RETURNS TABLE(list_id uuid, claim_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as (select auth.uid() as uid),

  visible_lists as (
    select l.id, l.event_id
    from public.lists l, me
    where l.id = any(p_list_ids)
      and public.can_view_list(l.id, (select uid from me))
  ),

  items_by_list as (
    select i.id as item_id, i.list_id
    from public.items i
    join visible_lists vl on vl.id = i.list_id
  ),

  non_recipient_lists as (
    select vl.id as list_id
    from visible_lists vl, me
    where not exists (
      select 1 from public.list_recipients lr
      where lr.list_id = vl.id
        and lr.user_id = (select uid from me)
    )
  ),

  claims_viewable as (
    select i.list_id
    from public.claims c
    join items_by_list i on i.item_id = c.item_id
    where exists (
      select 1 from non_recipient_lists n
      where n.list_id = i.list_id
    )
  ),

  my_claims as (
    select i.list_id
    from public.claims c
    join items_by_list i on i.item_id = c.item_id
    where c.claimer_id = (select uid from me)
  ),

  merged as (
    select list_id from claims_viewable
    union all
    select list_id from my_claims
  )

  select list_id, count(*)::int as claim_count
  from merged
  group by list_id;
$function$
;

CREATE OR REPLACE FUNCTION public.list_claims_for_user(p_item_ids uuid[])
 RETURNS TABLE(item_id uuid, claimer_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as (select auth.uid() as uid),

  visible_items as (
    select i.id as item_id, i.list_id
    from public.items i, me
    where i.id = any(p_item_ids)
      and public.can_view_list(i.list_id, (select uid from me))
  ),

  non_recipient_items as (
    select vi.item_id
    from visible_items vi, me
    where not exists (
      select 1
      from public.list_recipients lr
      where lr.list_id = vi.list_id
        and lr.user_id = (select uid from me)
    )
  ),

  claims_for_viewers as (
    select c.item_id, c.claimer_id
    from public.claims c
    join non_recipient_items n on n.item_id = c.item_id
  ),

  my_claims as (
    select c.item_id, c.claimer_id
    from public.claims c, me
    where c.item_id = any(p_item_ids)
      and c.claimer_id = (select uid from me)
  )

  select * from claims_for_viewers
  union
  select * from my_claims;
$function$
;

CREATE OR REPLACE FUNCTION public.list_id_for_item(i_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select list_id from public.items where id = i_id
$function$
;

CREATE OR REPLACE FUNCTION public.log_activity_for_digest(p_event_id uuid, p_exclude_user_id uuid, p_activity_type text, p_activity_data jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  -- Log activity for all event members who have digest enabled
  insert into public.daily_activity_log (user_id, event_id, activity_type, activity_data)
  select
    em.user_id,
    p_event_id,
    p_activity_type,
    p_activity_data
  from public.event_members em
  join public.profiles p on p.id = em.user_id
  where em.event_id = p_event_id
    and em.user_id != coalesce(p_exclude_user_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and p.notification_digest_enabled = true;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mark_orphaned_lists_for_deletion()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_event_id UUID;
  v_remaining_user_id UUID;
  v_list RECORD;
BEGIN
  -- Get the event_id from the deleted member
  v_event_id := OLD.event_id;

  -- Check if there's exactly one member left in the event
  SELECT user_id INTO v_remaining_user_id
  FROM public.event_members
  WHERE event_id = v_event_id
  LIMIT 1;

  -- If no members left or more than one member, nothing to do
  IF v_remaining_user_id IS NULL THEN
    RETURN OLD;
  END IF;

  IF NOT is_sole_event_member(v_event_id, v_remaining_user_id) THEN
    RETURN OLD;
  END IF;

  -- Find all lists in this event where the remaining user is excluded
  FOR v_list IN
    SELECT l.id as list_id
    FROM public.lists l
    INNER JOIN public.list_exclusions le ON le.list_id = l.id
    WHERE l.event_id = v_event_id
      AND le.user_id = v_remaining_user_id
  LOOP
    -- Mark this list for deletion (insert or update)
    INSERT INTO public.orphaned_lists (list_id, event_id, excluded_user_id, marked_at, delete_at)
    VALUES (v_list.list_id, v_event_id, v_remaining_user_id, NOW(), NOW() + INTERVAL '30 days')
    ON CONFLICT (list_id, excluded_user_id)
    DO UPDATE SET
      marked_at = NOW(),
      delete_at = NOW() + INTERVAL '30 days';
  END LOOP;

  RETURN OLD;
END;
$function$
;

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
  -- Get item, list, and event info
  select
    i.name,
    l.id,
    l.name,
    l.created_by,
    l.event_id,
    e.title
  into
    v_item_name,
    v_list_id,
    v_list_name,
    v_list_owner_id,
    v_event_id,
    v_event_title
  from public.items i
  join public.lists l on l.id = i.list_id
  join public.events e on e.id = l.event_id
  where i.id = NEW.item_id;

  -- Get claimer display name
  select coalesce(display_name, 'Someone') into v_claimer_name
  from public.profiles
  where id = NEW.claimer_id;

  -- Instant notification: Notify the list owner if they have push tokens and aren't the claimer
  if v_list_owner_id is not null and v_list_owner_id != NEW.claimer_id then
    if exists (select 1 from public.push_tokens where user_id = v_list_owner_id) then
      insert into public.notification_queue (user_id, title, body, data)
      values (
        v_list_owner_id,
        'Item Claimed',
        v_claimer_name || ' claimed "' || v_item_name || '" from your list',
        jsonb_build_object(
          'type', 'new_claim',
          'claim_id', NEW.id,
          'item_id', NEW.item_id,
          'list_id', v_list_id,
          'event_id', v_event_id
        )
      );
    end if;
  end if;

  -- ALSO log activity for digest users (all event members)
  perform public.log_activity_for_digest(
    v_event_id,
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
$function$
;

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
  -- Get list info
  select l.id, l.name, l.event_id, e.title
  into v_list_id, v_list_name, v_event_id, v_event_title
  from public.lists l
  join public.events e on e.id = l.event_id
  where l.id = NEW.list_id;

  -- Get creator display name
  select coalesce(display_name, 'Someone') into v_creator_name
  from public.profiles
  where id = NEW.created_by;

  -- Queue instant notifications for all event members except creator
  perform public.queue_notification_for_event_members(
    v_event_id,
    NEW.created_by,
    'New Item: ' || NEW.name,
    v_creator_name || ' added an item to ' || coalesce(v_list_name, 'a list'),
    jsonb_build_object(
      'type', 'new_item',
      'item_id', NEW.id,
      'list_id', v_list_id,
      'event_id', v_event_id
    )
  );

  -- ALSO log activity for digest users
  perform public.log_activity_for_digest(
    v_event_id,
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
$function$
;

CREATE OR REPLACE FUNCTION public.notify_new_list()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_event_title text;
  v_creator_name text;
begin
  -- Get event title
  select title into v_event_title
  from public.events
  where id = NEW.event_id;

  -- Get creator display name
  select coalesce(display_name, 'Someone') into v_creator_name
  from public.profiles
  where id = NEW.created_by;

  -- Queue instant notifications for all event members except creator
  perform public.queue_notification_for_event_members(
    NEW.event_id,
    NEW.created_by,
    'New List: ' || NEW.name,
    v_creator_name || ' created a new list in ' || coalesce(v_event_title, 'an event'),
    jsonb_build_object(
      'type', 'new_list',
      'list_id', NEW.id,
      'event_id', NEW.event_id
    )
  );

  -- ALSO log activity for digest users
  perform public.log_activity_for_digest(
    NEW.event_id,
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
$function$
;

CREATE OR REPLACE FUNCTION public.remove_member(p_event_id uuid, p_user_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_actor_role public.member_role;
  v_owner uuid;
  v_target_role public.member_role;
  v_remaining integer;
  v_admins integer;
  v_new_admin uuid;
  v_deleted boolean := false;
  v_transferred boolean := false;
  v_actor_is_owner boolean := false;
begin
  if v_actor is null then
    raise exception 'not_authenticated';
  end if;
  if p_user_id = v_actor then
    raise exception 'use_leave_event_for_self';
  end if;

  select role into v_actor_role
  from public.event_members
  where event_id = p_event_id and user_id = v_actor;
  if not found then
    raise exception 'not_member';
  end if;

  select owner_id into v_owner from public.events where id = p_event_id;
  v_actor_is_owner := (v_owner = v_actor);

  if v_actor_role <> 'admin' and not v_actor_is_owner then
    raise exception 'not_authorized';
  end if;

  select role into v_target_role
  from public.event_members
  where event_id = p_event_id and user_id = p_user_id;
  if not found then
    raise exception 'target_not_member';
  end if;

  delete from public.claims c
  using public.items i, public.lists l
  where c.item_id = i.id
    and i.list_id = l.id
    and l.event_id = p_event_id
    and c.claimer_id = p_user_id;

  delete from public.list_recipients lr
  using public.lists l2
  where lr.list_id = l2.id
    and l2.event_id = p_event_id
    and lr.user_id = p_user_id;

  delete from public.event_members
  where event_id = p_event_id and user_id = p_user_id;

  select count(*) into v_remaining
  from public.event_members
  where event_id = p_event_id;

  if v_remaining = 0 then
    delete from public.events where id = p_event_id;
    v_deleted := true;
    return json_build_object('removed', true, 'deleted_event', v_deleted, 'transferred', v_transferred, 'new_admin', null);
  end if;

  if v_target_role = 'admin' then
    select count(*) into v_admins
    from public.event_members
    where event_id = p_event_id and role = 'admin';

    if v_admins = 0 then
      select public._pick_new_admin(p_event_id) into v_new_admin;
      if v_new_admin is not null then
        update public.event_members
        set role = 'admin'
        where event_id = p_event_id and user_id = v_new_admin;
        v_transferred := true;
      end if;
    end if;
  end if;

  if v_owner = p_user_id then
    select user_id into v_new_admin
    from public.event_members
    where event_id = p_event_id and role = 'admin'
    limit 1;

    if v_new_admin is null then
      select public._pick_new_admin(p_event_id) into v_new_admin;
    end if;

    if v_new_admin is not null then
      update public.events set owner_id = v_new_admin where id = p_event_id;
      v_transferred := true;
    end if;
  end if;

  return json_build_object('removed', true, 'deleted_event', v_deleted, 'transferred', v_transferred, 'new_admin', v_new_admin);
end
$function$
;

CREATE OR REPLACE FUNCTION public.rollover_all_due_events()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_count int := 0;
  rec record;
  v_new date;
begin
  for rec in
    select e.id, e.event_date, e.recurrence
    from public.events e
    where e.recurrence <> 'none'
      and e.event_date is not null
      and e.event_date <= current_date
      and (e.last_rolled_at is null or e.last_rolled_at < e.event_date)
  loop
    delete from public.items i
    using public.lists l
    where i.list_id = l.id
      and l.event_id = rec.id
      and exists (select 1 from public.claims c where c.item_id = i.id);

    delete from public.claims c
    where not exists (select 1 from public.items i where i.id = c.item_id);

    v_new := _next_occurrence(rec.event_date, rec.recurrence, 1);
    while v_new <= current_date loop
      v_new := _next_occurrence(v_new, rec.recurrence, 1);
    end loop;

    update public.events
       set event_date     = v_new,
           last_rolled_at = current_date
     where id = rec.id;

    v_count := v_count + 1;
  end loop;

  return v_count;
end
$function$
;

CREATE OR REPLACE FUNCTION public.send_event_invite(p_event_id uuid, p_invitee_email text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_invite_id uuid;
  v_invitee_id uuid;
  v_event_title text;
  v_event_date date;
  v_join_code text;
  v_inviter_name text;
  v_has_push_token boolean;
  v_request_id bigint;
  v_email_url text;
  v_admin_only_invites boolean;
  v_is_admin boolean;
begin
  -- Validate inviter is event member
  if not exists (
    select 1 from public.event_members
    where event_id = p_event_id and user_id = auth.uid()
  ) then
    raise exception 'Not authorized to invite to this event';
  end if;

  -- Check if event has admin-only invites restriction
  select admin_only_invites into v_admin_only_invites
  from public.events
  where id = p_event_id;

  -- If admin-only invites is enabled, verify user is admin
  if v_admin_only_invites then
    select exists (
      select 1 from public.event_members
      where event_id = p_event_id
        and user_id = auth.uid()
        and role = 'admin'
    ) into v_is_admin;

    if not v_is_admin then
      raise exception 'Only admins can invite to this event';
    end if;
  end if;

  -- Normalize email
  p_invitee_email := lower(trim(p_invitee_email));

  -- Validate email format (basic)
  if p_invitee_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then
    raise exception 'Invalid email format';
  end if;

  -- Check if user is already a member
  if exists (
    select 1 from public.event_members em
    join auth.users u on u.id = em.user_id
    where em.event_id = p_event_id and lower(u.email) = p_invitee_email
  ) then
    raise exception 'User is already a member of this event';
  end if;

  -- Get event details
  select title, event_date, join_code
  into v_event_title, v_event_date, v_join_code
  from public.events
  where id = p_event_id;

  -- Get inviter display name
  select coalesce(display_name, 'Someone') into v_inviter_name
  from public.profiles
  where id = auth.uid();

  -- Check if invitee is a registered user
  select id into v_invitee_id
  from auth.users
  where lower(email) = p_invitee_email;

  -- Create or update invite
  insert into public.event_invites (event_id, inviter_id, invitee_email, invitee_id)
  values (p_event_id, auth.uid(), p_invitee_email, v_invitee_id)
  on conflict (event_id, invitee_email) do update
    set inviter_id = excluded.inviter_id,
        invitee_id = excluded.invitee_id,
        status = 'pending',
        invited_at = now(),
        responded_at = null
  returning id into v_invite_id;

  -- Send email invitation (for both registered and unregistered users)
  -- Note: Update the URL to match your Supabase project
  v_email_url := 'https://bqgakovbbbiudmggduvu.supabase.co/functions/v1/send-invite-email';

  select net.http_post(
    url := v_email_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJxZ2Frb3ZiYmJpdWRtZ2dkdXZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcwNTY1MjEsImV4cCI6MjA3MjYzMjUyMX0.i81E7-w03a1v6BV2FwGpuNRA9tTVWF3nATgJeeO5g1k'
    ),
    body := jsonb_build_object(
      'to', p_invitee_email,
      'inviterName', v_inviter_name,
      'eventName', v_event_title,
      'eventDate', v_event_date,
      'joinCode', v_join_code,
      'eventTimezone', 'UTC'
    )
  ) into v_request_id;

  -- If user is registered and has push tokens, also queue notification
  if v_invitee_id is not null then
    select exists (
      select 1 from public.push_tokens where user_id = v_invitee_id
    ) into v_has_push_token;

    if v_has_push_token then
      insert into public.notification_queue (user_id, title, body, data)
      values (
        v_invitee_id,
        'Event Invitation',
        v_inviter_name || ' invited you to ' || v_event_title,
        jsonb_build_object(
          'type', 'event_invite',
          'invite_id', v_invite_id,
          'event_id', p_event_id
        )
      );
    end if;
  end if;

  return v_invite_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.set_list_created_by()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.created_by is null then
    new.created_by := auth.uid();
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.set_onboarding_done(p_done boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  update public.profiles
  set onboarding_done = coalesce(p_done, true),
      onboarding_at   = case when coalesce(p_done, true) then now() else null end
  where id = auth.uid();
end
$function$
;

CREATE OR REPLACE FUNCTION public.set_plan(p_plan text, p_months integer DEFAULT 0, p_user uuid DEFAULT auth.uid())
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_plan = 'pro' then
    update public.profiles
       set plan = 'pro',
           pro_until = case when p_months > 0 then now() + (p_months||' months')::interval else null end
     where id = p_user;
  else
    update public.profiles
       set plan = 'free',
           pro_until = null
     where id = p_user;
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.set_profile_name(p_name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.profiles (id, display_name)
  values (auth.uid(), p_name)
  on conflict (id) do update set display_name = excluded.display_name;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.test_impersonate(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user_id::text)::text,
    true
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.tg_set_timestamp()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trigger_daily_digest()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_url text;
  v_request_id bigint;
  v_current_hour int;
begin
  v_url := 'https://bqgakovbbbiudmggduvu.supabase.co/functions/v1/send-daily-digest';
  v_current_hour := extract(hour from now())::int;

  -- Call the edge function with current hour
  select net.http_post(
    url := v_url,
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJxZ2Frb3ZiYmJpdWRtZ2dkdXZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcwNTY1MjEsImV4cCI6MjA3MjYzMjUyMX0.i81E7-w03a1v6BV2FwGpuNRA9tTVWF3nATgJeeO5g1k"}'::jsonb,
    body := format('{"hour": %s}', v_current_hour)::jsonb
  ) into v_request_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.trigger_push_notifications()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_url text;
  v_request_id bigint;
begin
  v_url := 'https://bqgakovbbbiudmggduvu.supabase.co/functions/v1/send-push-notifications';

  select net.http_post(
    url := v_url,
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJxZ2Frb3ZiYmJpdWRtZ2dkdXZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcwNTY1MjEsImV4cCI6MjA3MjYzMjUyMX0.i81E7-w03a1v6BV2FwGpuNRA9tTVWF3nATgJeeO5g1k"}'::jsonb
  ) into v_request_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.unclaim_item(p_item_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  u uuid := auth.uid();
begin
  if u is null then
    raise exception 'not_authenticated';
  end if;

  delete from public.claims
  where item_id = p_item_id
    and claimer_id = u;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.unmark_orphaned_lists_on_member_join()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- When a new member joins an event, remove any orphaned list markers for that event
  DELETE FROM public.orphaned_lists
  WHERE event_id = NEW.event_id;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_invites_on_user_signup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare
  v_email text;
begin
  -- Find the user's email from auth.users using the ID we do have
  select u.email into v_email
  from auth.users u
  where u.id = NEW.id;

  if v_email is not null and length(v_email) > 0 then
    update public.event_invites
      set invitee_id = NEW.id
    where invitee_id is null
      and status = 'pending'
      and lower(invitee_email) = lower(v_email);
  end if;

  return NEW;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.whoami()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'uid', auth.uid(),
    'role', current_setting('request.jwt.claim.role', true)
  );
$function$
;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE public.claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.claims FORCE ROW LEVEL SECURITY;

ALTER TABLE public.daily_activity_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_activity_log FORCE ROW LEVEL SECURITY;

ALTER TABLE public.event_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_invites FORCE ROW LEVEL SECURITY;

ALTER TABLE public.event_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_members FORCE ROW LEVEL SECURITY;

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events FORCE ROW LEVEL SECURITY;

ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.items FORCE ROW LEVEL SECURITY;

ALTER TABLE public.list_exclusions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.list_exclusions FORCE ROW LEVEL SECURITY;

ALTER TABLE public.list_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.list_recipients FORCE ROW LEVEL SECURITY;

ALTER TABLE public.list_viewers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.list_viewers FORCE ROW LEVEL SECURITY;

ALTER TABLE public.lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lists FORCE ROW LEVEL SECURITY;

ALTER TABLE public.notification_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_queue FORCE ROW LEVEL SECURITY;

ALTER TABLE public.orphaned_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orphaned_lists FORCE ROW LEVEL SECURITY;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles FORCE ROW LEVEL SECURITY;

ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_tokens FORCE ROW LEVEL SECURITY;

ALTER TABLE public.sent_reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sent_reminders FORCE ROW LEVEL SECURITY;

ALTER TABLE public.user_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_plans FORCE ROW LEVEL SECURITY;

-- ============================================================================
-- RLS POLICIES  
-- ============================================================================

-- Policies for: claims

CREATE POLICY "admins can delete any claims"
  ON public.claims
  AS PERMISSIVE
  FOR DELETE
  USING (is_event_admin(event_id_for_item(item_id), ( SELECT auth.uid() AS uid)));

CREATE POLICY "claims_delete_admins"
  ON public.claims
  AS RESTRICTIVE
  FOR DELETE
  USING (is_event_admin(event_id_for_item(item_id)));

CREATE POLICY "claims_select_visible"
  ON public.claims
  AS PERMISSIVE
  FOR SELECT
  USING (can_view_list(list_id_for_item(item_id), ( SELECT auth.uid() AS uid)));

CREATE POLICY "claims_update_by_claimer"
  ON public.claims
  AS PERMISSIVE
  FOR UPDATE
  USING ((( SELECT auth.uid() AS uid) = claimer_id))
  WITH CHECK ((( SELECT auth.uid() AS uid) = claimer_id));

CREATE POLICY "claims_update_own"
  ON public.claims
  AS PERMISSIVE
  FOR UPDATE
  USING ((( SELECT auth.uid() AS uid) = claimer_id))
  WITH CHECK ((( SELECT auth.uid() AS uid) = claimer_id));

CREATE POLICY "delete own claims"
  ON public.claims
  AS PERMISSIVE
  FOR DELETE
  USING ((claimer_id = ( SELECT auth.uid() AS uid)));

-- Policies for: daily_activity_log

CREATE POLICY "No public access to activity log"
  ON public.daily_activity_log
  AS PERMISSIVE
  FOR ALL
  USING (false)
  WITH CHECK (null);

-- Policies for: event_invites

CREATE POLICY "event_invites_delete"
  ON public.event_invites
  AS PERMISSIVE
  FOR DELETE
  USING (((( SELECT auth.uid() AS uid) = inviter_id) OR (EXISTS ( SELECT 1
   FROM event_members em
  WHERE ((em.event_id = event_invites.event_id) AND (em.user_id = ( SELECT auth.uid() AS uid)) AND (em.role = 'admin'::member_role))))));

CREATE POLICY "event_invites_insert"
  ON public.event_invites
  AS PERMISSIVE
  FOR INSERT
  WITH CHECK (((( SELECT auth.uid() AS uid) = inviter_id) AND (EXISTS ( SELECT 1
   FROM event_members em
  WHERE ((em.event_id = event_invites.event_id) AND (em.user_id = ( SELECT auth.uid() AS uid)))))));

CREATE POLICY "event_invites_select"
  ON public.event_invites
  AS PERMISSIVE
  FOR SELECT
  USING (((( SELECT auth.uid() AS uid) = inviter_id) OR (( SELECT auth.uid() AS uid) = invitee_id) OR (EXISTS ( SELECT 1
   FROM event_members em
  WHERE ((em.event_id = event_invites.event_id) AND (em.user_id = ( SELECT auth.uid() AS uid)))))));

CREATE POLICY "event_invites_update"
  ON public.event_invites
  AS PERMISSIVE
  FOR UPDATE
  USING ((( SELECT auth.uid() AS uid) = invitee_id))
  WITH CHECK (null);

-- Policies for: event_members

CREATE POLICY "delete own event membership"
  ON public.event_members
  AS PERMISSIVE
  FOR DELETE
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "event_members_select"
  ON public.event_members
  AS PERMISSIVE
  FOR SELECT
  USING (is_member_of_event(event_id, ( SELECT auth.uid() AS uid)));

-- Policies for: events

CREATE POLICY "admins can delete events"
  ON public.events
  AS PERMISSIVE
  FOR DELETE
  USING (is_event_admin(id, ( SELECT auth.uid() AS uid)));

CREATE POLICY "delete events by owner or last member"
  ON public.events
  AS PERMISSIVE
  FOR DELETE
  USING (((owner_id = ( SELECT auth.uid() AS uid)) OR is_last_event_member(id, ( SELECT auth.uid() AS uid))));

CREATE POLICY "events: update by admins"
  ON public.events
  AS PERMISSIVE
  FOR UPDATE
  USING ((EXISTS ( SELECT 1
   FROM event_members em
  WHERE ((em.event_id = events.id) AND (em.user_id = ( SELECT auth.uid() AS uid)) AND (em.role = 'admin'::member_role)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM event_members em
  WHERE ((em.event_id = events.id) AND (em.user_id = ( SELECT auth.uid() AS uid)) AND (em.role = 'admin'::member_role)))));

CREATE POLICY "insert events when owner is self"
  ON public.events
  AS PERMISSIVE
  FOR INSERT
  WITH CHECK ((owner_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "owners can delete events"
  ON public.events
  AS PERMISSIVE
  FOR DELETE
  USING ((owner_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "select events for members"
  ON public.events
  AS PERMISSIVE
  FOR SELECT
  USING (is_event_member(id, ( SELECT auth.uid() AS uid)));

CREATE POLICY "select events for owners"
  ON public.events
  AS PERMISSIVE
  FOR SELECT
  USING ((owner_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "update events by owner or last member"
  ON public.events
  AS PERMISSIVE
  FOR UPDATE
  USING (((owner_id = ( SELECT auth.uid() AS uid)) OR is_last_event_member(id, ( SELECT auth.uid() AS uid))))
  WITH CHECK (((owner_id = ( SELECT auth.uid() AS uid)) OR is_last_event_member(id, ( SELECT auth.uid() AS uid))));

-- Policies for: items

CREATE POLICY "delete items by creator or last member"
  ON public.items
  AS PERMISSIVE
  FOR DELETE
  USING (((created_by = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM lists l
  WHERE ((l.id = items.list_id) AND ((l.created_by = ( SELECT auth.uid() AS uid)) OR is_last_event_member(l.event_id, ( SELECT auth.uid() AS uid))))))));

CREATE POLICY "members can insert items into their event lists"
  ON public.items
  AS PERMISSIVE
  FOR INSERT
  WITH CHECK (((( SELECT auth.role() AS role) = 'authenticated'::text) AND (created_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM (lists l
     JOIN event_members em ON ((em.event_id = l.event_id)))
  WHERE ((l.id = items.list_id) AND (em.user_id = ( SELECT auth.uid() AS uid)))))));

CREATE POLICY "members can select items in their events"
  ON public.items
  AS PERMISSIVE
  FOR SELECT
  USING ((EXISTS ( SELECT 1
   FROM (lists l
     JOIN event_members em ON ((em.event_id = l.event_id)))
  WHERE ((l.id = items.list_id) AND (em.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "update items by creator or last member"
  ON public.items
  AS PERMISSIVE
  FOR UPDATE
  USING (((created_by = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM lists l
  WHERE ((l.id = items.list_id) AND ((l.created_by = ( SELECT auth.uid() AS uid)) OR is_last_event_member(l.event_id, ( SELECT auth.uid() AS uid))))))))
  WITH CHECK (null);

-- Policies for: list_exclusions

CREATE POLICY "le_select"
  ON public.list_exclusions
  AS PERMISSIVE
  FOR SELECT
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "list_exclusions_delete"
  ON public.list_exclusions
  AS PERMISSIVE
  FOR DELETE
  USING (((EXISTS ( SELECT 1
   FROM ((lists l
     JOIN events e ON ((e.id = l.event_id)))
     JOIN event_members em ON ((em.event_id = e.id)))
  WHERE ((l.id = list_exclusions.list_id) AND (em.user_id = auth.uid()) AND ((l.created_by = auth.uid()) OR (em.role = 'admin'::member_role) OR (e.owner_id = auth.uid()))))) OR (user_id = auth.uid())));

CREATE POLICY "list_exclusions_insert"
  ON public.list_exclusions
  AS PERMISSIVE
  FOR INSERT
  WITH CHECK ((EXISTS ( SELECT 1
   FROM lists l
  WHERE ((l.id = list_exclusions.list_id) AND (l.created_by = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "list_exclusions_select"
  ON public.list_exclusions
  AS PERMISSIVE
  FOR SELECT
  USING (((EXISTS ( SELECT 1
   FROM lists l
  WHERE ((l.id = list_exclusions.list_id) AND (l.created_by = ( SELECT auth.uid() AS uid))))) OR (user_id = ( SELECT auth.uid() AS uid))));

-- Policies for: list_recipients

CREATE POLICY "delete list_recipients by creator or last member"
  ON public.list_recipients
  AS PERMISSIVE
  FOR DELETE
  USING ((EXISTS ( SELECT 1
   FROM lists l
  WHERE ((l.id = list_recipients.list_id) AND ((l.created_by = ( SELECT auth.uid() AS uid)) OR is_last_event_member(l.event_id, ( SELECT auth.uid() AS uid)))))));

CREATE POLICY "insert list_recipients by creator"
  ON public.list_recipients
  AS PERMISSIVE
  FOR INSERT
  WITH CHECK ((EXISTS ( SELECT 1
   FROM lists l
  WHERE ((l.id = list_recipients.list_id) AND (l.created_by = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "list_recipients_insert"
  ON public.list_recipients
  AS PERMISSIVE
  FOR INSERT
  WITH CHECK ((EXISTS ( SELECT 1
   FROM lists l
  WHERE ((l.id = list_recipients.list_id) AND (l.created_by = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "list_recipients_select"
  ON public.list_recipients
  AS PERMISSIVE
  FOR SELECT
  USING (can_view_list(list_id, ( SELECT auth.uid() AS uid)));

CREATE POLICY "update list_recipients by creator or last member"
  ON public.list_recipients
  AS PERMISSIVE
  FOR UPDATE
  USING ((EXISTS ( SELECT 1
   FROM lists l
  WHERE ((l.id = list_recipients.list_id) AND ((l.created_by = ( SELECT auth.uid() AS uid)) OR is_last_event_member(l.event_id, ( SELECT auth.uid() AS uid)))))))
  WITH CHECK (null);

-- Policies for: list_viewers

CREATE POLICY "lv_select"
  ON public.list_viewers
  AS PERMISSIVE
  FOR SELECT
  USING ((user_id = ( SELECT auth.uid() AS uid)));

-- Policies for: lists

CREATE POLICY "delete lists by creator or last member"
  ON public.lists
  AS PERMISSIVE
  FOR DELETE
  USING (((created_by = ( SELECT auth.uid() AS uid)) OR is_last_event_member(event_id, ( SELECT auth.uid() AS uid))));

CREATE POLICY "lists_delete_admins"
  ON public.lists
  AS RESTRICTIVE
  FOR DELETE
  USING (is_event_admin(event_id));

CREATE POLICY "lists_insert"
  ON public.lists
  AS RESTRICTIVE
  FOR INSERT
  WITH CHECK (is_event_member(event_id));

CREATE POLICY "lists_select_visible"
  ON public.lists
  AS PERMISSIVE
  FOR SELECT
  USING (can_view_list(id, ( SELECT auth.uid() AS uid)));

CREATE POLICY "update lists by creator or last member"
  ON public.lists
  AS PERMISSIVE
  FOR UPDATE
  USING (((created_by = ( SELECT auth.uid() AS uid)) OR is_last_event_member(event_id, ( SELECT auth.uid() AS uid))))
  WITH CHECK (null);

-- Policies for: notification_queue

CREATE POLICY "No public access to notification queue"
  ON public.notification_queue
  AS PERMISSIVE
  FOR ALL
  USING (false)
  WITH CHECK (null);

-- Policies for: orphaned_lists

CREATE POLICY "orphaned_lists_select"
  ON public.orphaned_lists
  AS PERMISSIVE
  FOR SELECT
  USING (false);

-- Policies for: profiles

CREATE POLICY "profiles are readable by logged in users"
  ON public.profiles
  AS PERMISSIVE
  FOR SELECT
  USING (true);

CREATE POLICY "server-side insert when id exists in auth.users"
  ON public.profiles
  AS PERMISSIVE
  FOR INSERT
  WITH CHECK ((EXISTS ( SELECT 1
   FROM auth.users u
  WHERE (u.id = profiles.id))));

CREATE POLICY "users can insert their own profile"
  ON public.profiles
  AS PERMISSIVE
  FOR INSERT
  WITH CHECK ((id = auth.uid()));

CREATE POLICY "users can update their own profile"
  ON public.profiles
  AS PERMISSIVE
  FOR UPDATE
  USING ((id = auth.uid()))
  WITH CHECK ((id = auth.uid()));

-- Policies for: push_tokens

CREATE POLICY "Users can delete own tokens"
  ON public.push_tokens
  AS PERMISSIVE
  FOR DELETE
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Users can insert own tokens"
  ON public.push_tokens
  AS PERMISSIVE
  FOR INSERT
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Users can update own tokens"
  ON public.push_tokens
  AS PERMISSIVE
  FOR UPDATE
  USING ((user_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Users can view own tokens"
  ON public.push_tokens
  AS PERMISSIVE
  FOR SELECT
  USING ((user_id = ( SELECT auth.uid() AS uid)));

-- Policies for: sent_reminders

CREATE POLICY "No public access to sent_reminders"
  ON public.sent_reminders
  AS PERMISSIVE
  FOR ALL
  USING (false)
  WITH CHECK (false);

-- Policies for: user_plans

CREATE POLICY "no_client_writes"
  ON public.user_plans
  AS PERMISSIVE
  FOR ALL
  USING (false)
  WITH CHECK (false);

CREATE POLICY "read_own_plan"
  ON public.user_plans
  AS PERMISSIVE
  FOR SELECT
  USING ((( SELECT auth.uid() AS uid) = user_id));

CREATE POLICY "user_plans_self"
  ON public.user_plans
  AS PERMISSIVE
  FOR ALL
  USING ((user_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));


-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Trigger: Auto-join event as admin when creating event
DROP TRIGGER IF EXISTS trg_autojoin_event ON public.events;
CREATE TRIGGER trg_autojoin_event
  AFTER INSERT ON public.events
  FOR EACH ROW
  EXECUTE FUNCTION public.autojoin_event_as_admin();

-- Trigger: Notify on new list
DROP TRIGGER IF EXISTS trigger_notify_new_list ON public.lists;
CREATE TRIGGER trigger_notify_new_list
  AFTER INSERT ON public.lists
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_new_list();

-- Trigger: Notify on new item
DROP TRIGGER IF EXISTS trigger_notify_new_item ON public.items;
CREATE TRIGGER trigger_notify_new_item
  AFTER INSERT ON public.items
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_new_item();

-- Trigger: Notify on new claim
DROP TRIGGER IF EXISTS trigger_notify_new_claim ON public.claims;
CREATE TRIGGER trigger_notify_new_claim
  AFTER INSERT ON public.claims
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_new_claim();

-- Trigger: Cleanup reminder on purchase
DROP TRIGGER IF EXISTS trigger_cleanup_reminder_on_purchase ON public.claims;
CREATE TRIGGER trigger_cleanup_reminder_on_purchase
  AFTER UPDATE ON public.claims
  FOR EACH ROW
  WHEN (NEW.purchased = true AND OLD.purchased = false)
  EXECUTE FUNCTION public.cleanup_reminder_on_purchase();

-- Trigger: Update invites on user signup
DROP TRIGGER IF EXISTS trigger_update_invites_on_signup ON public.profiles;
CREATE TRIGGER trigger_update_invites_on_signup
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.update_invites_on_user_signup();

-- Trigger: Link list recipients on signup
DROP TRIGGER IF EXISTS trigger_link_recipients_on_signup ON public.profiles;
CREATE TRIGGER trigger_link_recipients_on_signup
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.link_list_recipients_on_signup();

-- Trigger: Update timestamp on push_tokens
DROP TRIGGER IF EXISTS trigger_push_tokens_updated_at ON public.push_tokens;
CREATE TRIGGER trigger_push_tokens_updated_at
  BEFORE UPDATE ON public.push_tokens
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_set_timestamp();

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Claims indexes
CREATE INDEX IF NOT EXISTS idx_claims_item_id ON public.claims(item_id);
CREATE INDEX IF NOT EXISTS idx_claims_claimer_id ON public.claims(claimer_id);

-- Daily activity log indexes
CREATE INDEX IF NOT EXISTS idx_daily_activity_log_user_id ON public.daily_activity_log(user_id);
CREATE INDEX IF NOT EXISTS idx_daily_activity_log_event_id ON public.daily_activity_log(event_id);
CREATE INDEX IF NOT EXISTS idx_daily_activity_log_created_at ON public.daily_activity_log(created_at);

-- Event invites indexes
CREATE INDEX IF NOT EXISTS idx_event_invites_event_id ON public.event_invites(event_id);
CREATE INDEX IF NOT EXISTS idx_event_invites_invitee_email ON public.event_invites(invitee_email);
CREATE INDEX IF NOT EXISTS idx_event_invites_invitee_id ON public.event_invites(invitee_id);
CREATE INDEX IF NOT EXISTS idx_event_invites_status ON public.event_invites(status);

-- Event members indexes
CREATE INDEX IF NOT EXISTS idx_event_members_user_id ON public.event_members(user_id);
CREATE INDEX IF NOT EXISTS idx_event_members_event_id ON public.event_members(event_id);

-- Items indexes
CREATE INDEX IF NOT EXISTS idx_items_list_id ON public.items(list_id);

-- List recipients indexes
CREATE UNIQUE INDEX IF NOT EXISTS list_recipients_user_unique 
  ON public.list_recipients(list_id, user_id) 
  WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS list_recipients_email_unique 
  ON public.list_recipients(list_id, lower(recipient_email)) 
  WHERE recipient_email IS NOT NULL;

-- Lists indexes
CREATE INDEX IF NOT EXISTS idx_lists_event_id ON public.lists(event_id);
CREATE INDEX IF NOT EXISTS idx_lists_created_by ON public.lists(created_by);

-- Notification queue indexes
CREATE INDEX IF NOT EXISTS idx_notification_queue_sent ON public.notification_queue(sent, created_at);
CREATE INDEX IF NOT EXISTS idx_notification_queue_user_id ON public.notification_queue(user_id);

-- Orphaned lists indexes
CREATE INDEX IF NOT EXISTS idx_orphaned_lists_delete_at ON public.orphaned_lists(delete_at);

-- Profiles indexes  
CREATE INDEX IF NOT EXISTS idx_profiles_notification_digest ON public.profiles(notification_digest_enabled, digest_time_hour) 
  WHERE notification_digest_enabled = true;

-- Push tokens indexes
CREATE INDEX IF NOT EXISTS idx_push_tokens_user_id ON public.push_tokens(user_id);

-- Sent reminders indexes
CREATE INDEX IF NOT EXISTS idx_sent_reminders_claim_event ON public.sent_reminders(claim_id, event_id);
CREATE INDEX IF NOT EXISTS idx_sent_reminders_user_id ON public.sent_reminders(user_id);

COMMIT;

-- ============================================================================
-- SCHEMA CONSOLIDATED - END
-- ============================================================================
