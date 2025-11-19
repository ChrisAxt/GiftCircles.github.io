--
-- PostgreSQL database dump
--

\restrict SRoQselunXZPFvuOXFh2AVnbmZFKzN0TizJmRxwTMHXIehrVE4m37ZwHS7qXiD7

-- Dumped from database version 17.4
-- Dumped by pg_dump version 17.7 (Ubuntu 17.7-3.pgdg24.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'SECURITY BEST PRACTICES:
1. All SECURITY DEFINER functions use SET search_path TO prevent search path attacks
2. All user input is parameterized (no string concatenation in queries)
3. All functions validate input and check authorization
4. Rate limiting is applied to sensitive operations
5. All security events are logged to audit table
6. Foreign key constraints prevent orphaned records
7. CHECK constraints validate data integrity';


--
-- Name: list_visibility; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.list_visibility AS ENUM (
    'event',
    'selected'
);


--
-- Name: member_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.member_role AS ENUM (
    'giver',
    'recipient',
    'admin'
);


--
-- Name: _next_occurrence(date, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._next_occurrence(p_date date, p_freq text, p_interval integer DEFAULT 1) RETURNS date
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
select case p_freq
  when 'weekly'  then p_date + (7 * p_interval)
  when 'monthly' then (p_date + (interval '1 month' * p_interval))::date
  when 'yearly'  then (p_date + (interval '1 year'  * p_interval))::date
  else p_date
end;
$$;


--
-- Name: _pick_new_admin(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._pick_new_admin(p_event_id uuid) RETURNS uuid
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select user_id
  from public.event_members
  where event_id = p_event_id
  order by created_at nulls last, user_id
  limit 1
$$;


--
-- Name: _test_admin_for_event_title(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._test_admin_for_event_title(p_title text) RETURNS uuid
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT em.user_id
  FROM public.event_members em
  JOIN public.events e ON e.id = em.event_id
  WHERE e.title = p_title AND em.role = 'admin'
  LIMIT 1
$$;


--
-- Name: _test_any_member_for_event_title(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._test_any_member_for_event_title(p_title text) RETURNS uuid
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT em.user_id
  FROM public.event_members em
  JOIN public.events e ON e.id = em.event_id
  WHERE e.title = p_title
  ORDER BY (em.role = 'admin') DESC
  LIMIT 1
$$;


--
-- Name: _test_create_list_for_event(uuid, text, public.list_visibility); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._test_create_list_for_event(p_event_id uuid, p_name text, p_vis public.list_visibility) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
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
$_$;


--
-- Name: accept_claim_split(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.accept_claim_split(p_request_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_request record;
BEGIN
  -- Validate user is authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get the request details
  SELECT * INTO v_request
  FROM public.claim_split_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Split request not found';
  END IF;

  -- Validate user is the original claimer
  IF v_request.original_claimer_id != auth.uid() THEN
    RAISE EXCEPTION 'Only the original claimer can accept this request';
  END IF;

  -- Validate request is still pending
  IF v_request.status != 'pending' THEN
    RAISE EXCEPTION 'Request has already been responded to';
  END IF;

  -- Validate requester hasn't already claimed the item
  IF EXISTS (
    SELECT 1 FROM public.claims
    WHERE item_id = v_request.item_id AND claimer_id = v_request.requester_id
  ) THEN
    RAISE EXCEPTION 'Requester has already claimed this item';
  END IF;

  -- Create a claim for the requester
  INSERT INTO public.claims (
    item_id,
    claimer_id,
    quantity,
    note
  ) VALUES (
    v_request.item_id,
    v_request.requester_id,
    1,
    'Split claim'
  );

  -- Update the request status
  UPDATE public.claim_split_requests
  SET
    status = 'accepted',
    responded_at = now()
  WHERE id = p_request_id;
END;
$$;


--
-- Name: accept_event_invite(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.accept_event_invite(p_invite_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_invite record;
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();

  -- Get invite details including invited_role
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
$$;


--
-- Name: add_list_recipient(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_list_recipient(p_list_id uuid, p_recipient_email text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
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
$_$;


--
-- Name: allowed_event_slots(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.allowed_event_slots(p_user uuid DEFAULT auth.uid()) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select case when public.is_pro(p_user) then 1000000 else 3 end;
$$;


--
-- Name: assign_items_randomly(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assign_items_randomly(p_list_id uuid) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user uuid;
  v_list record;
  v_is_admin boolean;
  v_available_members uuid[];
  v_unassigned_members uuid[];
  v_items uuid[];
  v_mode text;
  v_item_id uuid;
  v_member_id uuid;
  v_member_idx int;
  v_assignments_made int := 0;
BEGIN
  v_user := auth.uid();

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Get list details
  SELECT l.*, l.random_assignment_mode, l.random_assignment_enabled, l.event_id, l.created_by
  INTO v_list
  FROM public.lists l
  WHERE l.id = p_list_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'list_not_found';
  END IF;

  IF NOT v_list.random_assignment_enabled THEN
    RAISE EXCEPTION 'random_assignment_not_enabled';
  END IF;

  -- Check if user is list owner or event admin
  SELECT
    (v_list.created_by = v_user) OR
    EXISTS(
      SELECT 1 FROM public.event_members em
      WHERE em.event_id = v_list.event_id
        AND em.user_id = v_user
        AND em.role = 'admin'
    ) OR
    EXISTS(
      SELECT 1 FROM public.events e
      WHERE e.id = v_list.event_id
        AND e.owner_id = v_user
    )
  INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  -- Get available members for assignment
  v_available_members := public.get_available_members_for_assignment(p_list_id);

  IF array_length(v_available_members, 1) IS NULL OR array_length(v_available_members, 1) = 0 THEN
    RAISE EXCEPTION 'no_available_members';
  END IF;

  v_mode := v_list.random_assignment_mode;

  -- Get unassigned items (items without any assignments)
  SELECT array_agg(i.id ORDER BY i.created_at)
  INTO v_items
  FROM public.items i
  WHERE i.list_id = p_list_id
    AND NOT EXISTS (
      SELECT 1 FROM public.claims c
      WHERE c.item_id = i.id
        AND c.assigned_to IS NOT NULL
    );

  IF array_length(v_items, 1) IS NULL OR array_length(v_items, 1) = 0 THEN
    -- No new items to assign
    UPDATE public.lists
    SET random_assignment_executed_at = now()
    WHERE id = p_list_id;

    RETURN json_build_object(
      'success', true,
      'assignments_made', 0,
      'member_count', array_length(v_available_members, 1),
      'message', 'no_new_items_to_assign'
    );
  END IF;

  -- All assignment operations are wrapped in implicit transaction
  -- If any INSERT fails, entire function rolls back

  -- Execute assignment based on mode
  IF v_mode = 'one_per_member' THEN
    -- Assign one item per member, prioritizing members with no assignments
    v_member_idx := 1;

    FOREACH v_item_id IN ARRAY v_items
    LOOP
      -- Get members who don't have any assignments yet
      SELECT array_agg(m.user_id ORDER BY random())
      INTO v_unassigned_members
      FROM (
        SELECT unnest(v_available_members) AS user_id
      ) m
      WHERE NOT EXISTS (
        SELECT 1 FROM public.claims c
        JOIN public.items i ON i.id = c.item_id
        WHERE c.assigned_to = m.user_id
          AND i.list_id = p_list_id
      );

      -- Exit if all members have at least one assignment
      EXIT WHEN array_length(v_unassigned_members, 1) IS NULL OR array_length(v_unassigned_members, 1) = 0;

      -- Assign to first member in shuffled array
      v_member_id := v_unassigned_members[1];

      -- Create assignment (claim with assigned_to)
      -- Use INSERT ... ON CONFLICT to ensure idempotency
      INSERT INTO public.claims (item_id, claimer_id, assigned_to)
      VALUES (v_item_id, v_member_id, v_member_id)
      ON CONFLICT (item_id, claimer_id) DO UPDATE
      SET assigned_to = EXCLUDED.assigned_to;

      v_assignments_made := v_assignments_made + 1;
    END LOOP;

  ELSIF v_mode = 'distribute_all' THEN
    -- Distribute all items as evenly as possible
    v_member_idx := 1;

    FOREACH v_item_id IN ARRAY v_items
    LOOP
      -- Get member with fewest assignments for this list
      SELECT m.user_id INTO v_member_id
      FROM (SELECT unnest(v_available_members) AS user_id) m
      LEFT JOIN (
        SELECT c.assigned_to, COUNT(*) as assignment_count
        FROM public.claims c
        JOIN public.items i ON i.id = c.item_id
        WHERE i.list_id = p_list_id
          AND c.assigned_to IS NOT NULL
        GROUP BY c.assigned_to
      ) counts ON counts.assigned_to = m.user_id
      ORDER BY COALESCE(counts.assignment_count, 0), random()
      LIMIT 1;

      IF v_member_id IS NULL THEN
        EXIT;
      END IF;

      -- Create assignment with idempotency
      INSERT INTO public.claims (item_id, claimer_id, assigned_to)
      VALUES (v_item_id, v_member_id, v_member_id)
      ON CONFLICT (item_id, claimer_id) DO UPDATE
      SET assigned_to = EXCLUDED.assigned_to;

      v_assignments_made := v_assignments_made + 1;
    END LOOP;

  ELSE
    RAISE EXCEPTION 'invalid_assignment_mode';
  END IF;

  -- Update execution timestamp
  UPDATE public.lists
  SET random_assignment_executed_at = now()
  WHERE id = p_list_id;

  RETURN json_build_object(
    'success', true,
    'assignments_made', v_assignments_made,
    'member_count', array_length(v_available_members, 1),
    'mode', v_mode
  );

EXCEPTION
  WHEN OTHERS THEN
    -- Log error and re-raise to trigger rollback
    RAISE WARNING 'assign_items_randomly failed for list %: % %', p_list_id, SQLERRM, SQLSTATE;
    RAISE;
END;
$$;


--
-- Name: FUNCTION assign_items_randomly(p_list_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.assign_items_randomly(p_list_id uuid) IS 'Randomly assigns list items to event members. Transaction-safe with automatic rollback on error. Idempotent.';


--
-- Name: autojoin_event_as_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.autojoin_event_as_admin() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  insert into public.event_members(event_id, user_id, role)
  values (new.id, new.owner_id, 'admin')
  on conflict do nothing;
  return new;
end;
$$;


--
-- Name: backfill_event_member_stats(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.backfill_event_member_stats() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  -- For each event member, calculate their stats
  -- Include collaborative mode claims (where user is both giver and recipient)

  INSERT INTO event_member_stats (event_id, user_id, total_claims, unpurchased_claims)
  SELECT
    em.event_id,
    em.user_id,
    COALESCE(COUNT(c.id), 0) as total_claims,
    COALESCE(COUNT(c.id) FILTER (WHERE c.purchased = false), 0) as unpurchased_claims
  FROM event_members em
  LEFT JOIN lists l ON l.event_id = em.event_id
  LEFT JOIN items i ON i.list_id = l.id
  LEFT JOIN claims c ON c.item_id = i.id AND c.claimer_id = em.user_id
  LEFT JOIN list_recipients lr ON lr.list_id = l.id AND lr.user_id = em.user_id
  WHERE
    -- Include claims in collaborative mode
    (
      COALESCE(l.random_assignment_enabled, false) = true
      AND COALESCE(l.random_receiver_assignment_enabled, false) = true
    )
    -- OR include claims where user is NOT a recipient
    OR lr.list_id IS NULL
  GROUP BY em.event_id, em.user_id
  ON CONFLICT (event_id, user_id) DO UPDATE SET
    total_claims = EXCLUDED.total_claims,
    unpurchased_claims = EXCLUDED.unpurchased_claims,
    updated_at = now();
END;
$$;


--
-- Name: FUNCTION backfill_event_member_stats(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.backfill_event_member_stats() IS 'Backfills event_member_stats table with existing claim data including collaborative mode. Can be run to fix existing stats.';


--
-- Name: can_claim_item(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_claim_item(p_item_id uuid, p_user uuid) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  WITH i AS (
    SELECT i.id, i.list_id, l.event_id, l.random_assignment_enabled, l.created_by
    FROM public.items i
    JOIN public.lists l ON l.id = i.list_id
    WHERE i.id = p_item_id
  ),

  is_admin AS (
    SELECT EXISTS (
      SELECT 1
      FROM i
      LEFT JOIN public.event_members em ON em.event_id = i.event_id AND em.user_id = p_user
      LEFT JOIN public.events e ON e.id = i.event_id
      WHERE i.created_by = p_user
         OR em.role = 'admin'
         OR e.owner_id = p_user
    ) AS admin_check
  ),

  is_assigned AS (
    SELECT EXISTS (
      SELECT 1
      FROM public.claims c
      WHERE c.item_id = p_item_id
        AND c.assigned_to = p_user
    ) AS assigned_check
  )

  SELECT
    -- Must be event member
    EXISTS (
      SELECT 1 FROM i
      JOIN public.event_members em
        ON em.event_id = i.event_id AND em.user_id = p_user
    )
    -- Must not be a recipient of the list
    AND NOT EXISTS (
      SELECT 1 FROM public.list_recipients lr
      JOIN i ON i.list_id = lr.list_id
      WHERE lr.user_id = p_user
    )
    -- If random assignment enabled, must be assigned to user OR user is admin
    AND (
      NOT (SELECT random_assignment_enabled FROM i)
      OR (SELECT admin_check FROM is_admin)
      OR (SELECT assigned_check FROM is_assigned)
    )
$$;


--
-- Name: FUNCTION can_claim_item(p_item_id uuid, p_user uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.can_claim_item(p_item_id uuid, p_user uuid) IS 'Checks if a user can claim an item. For random assignment lists, only assigned users or admins can claim.';


--
-- Name: can_create_event(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_create_event(p_user uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select case
    when public.is_pro(p_user, now()) then true
    -- Count TOTAL event memberships (owned + joined)
    else (select count(*) < 3 from public.event_members where user_id = p_user)
  end;
$$;


--
-- Name: can_join_event(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_join_event(p_user uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select case
    when public.is_pro(p_user, now()) then true
    -- Count TOTAL event memberships (owned + joined)
    else (select count(*) < 3 from public.event_members where user_id = p_user)
  end;
$$;


--
-- Name: can_view_list(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_view_list(p_list uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT public.is_member_of_event(l.event_id)
     AND NOT EXISTS (
           SELECT 1
           FROM public.list_exclusions e
           WHERE e.list_id = p_list
             AND e.user_id = auth.uid()
         )
  FROM public.lists l
  WHERE l.id = p_list;
$$;


--
-- Name: can_view_list(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_view_list(uuid, uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
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
  $_$;


--
-- Name: check_and_queue_purchase_reminders(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_and_queue_purchase_reminders() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_user record;
  v_event record;
  v_event_date date;
  v_days_until int;
  v_claimed_count int;
  v_total_count int;
  v_title text;
  v_body text;
begin
  -- Loop through users who have reminder_days set AND are pro
  for v_user in
    select p.id, p.reminder_days
    from public.profiles p
    where p.reminder_days is not null
      and p.reminder_days > 0
      -- NEW: Only process pro users
      and public.is_pro(p.id, now()) = true
      -- Only process if they have push tokens
      and exists (
        select 1 from public.push_tokens pt where pt.user_id = p.id
      )
  loop
    -- For each user, check their events
    for v_event in
      select distinct e.id, e.title, e.event_date
      from public.events e
      join public.event_members em on em.event_id = e.id
      where em.user_id = v_user.id
        and e.event_date is not null
        and e.event_date >= current_date
    loop
      v_event_date := v_event.event_date;
      v_days_until := v_event_date - current_date;

      -- Check if we should send reminder for this event
      if v_days_until = v_user.reminder_days then
        -- Count user's claimed items for this event
        select count(distinct c.id)
        into v_claimed_count
        from public.claims c
        join public.items i on i.id = c.item_id
        join public.lists l on l.id = i.list_id
        where l.event_id = v_event.id
          and c.claimer_id = v_user.id
          and c.purchased = false;

        -- Only send if they have unpurchased claims
        if v_claimed_count > 0 then
          -- Build notification
          v_title := 'Purchase Reminder: ' || v_event.title;
          if v_claimed_count = 1 then
            v_body := 'You have 1 unpurchased item for ' || v_event.title || ' in ' || v_days_until || ' days.';
          else
            v_body := 'You have ' || v_claimed_count || ' unpurchased items for ' || v_event.title || ' in ' || v_days_until || ' days.';
          end if;

          -- Queue notification
          insert into public.notification_queue (user_id, title, body, data)
          values (
            v_user.id,
            v_title,
            v_body,
            jsonb_build_object(
              'type', 'purchase_reminder',
              'event_id', v_event.id,
              'event_title', v_event.title,
              'days_until', v_days_until,
              'unpurchased_count', v_claimed_count
            )
          );
        end if;
      end if;
    end loop;
  end loop;
end;
$$;


--
-- Name: FUNCTION check_and_queue_purchase_reminders(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.check_and_queue_purchase_reminders() IS 'Queues purchase reminder notifications for pro users with unpurchased claims. Runs daily via cron.';


--
-- Name: check_rate_limit(text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_rate_limit(p_action text, p_max_requests integer DEFAULT 100, p_window_seconds integer DEFAULT 60) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id uuid;
  v_window_start timestamptz;
  v_current_count int;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    -- Anonymous users get stricter limits
    p_max_requests := LEAST(p_max_requests, 10);
  END IF;

  -- Calculate current window start (floor to window boundary)
  v_window_start := date_trunc('minute', now()) -
    ((EXTRACT(EPOCH FROM date_trunc('minute', now()))::int % p_window_seconds) * interval '1 second');

  -- Get or create rate limit record
  INSERT INTO public.rate_limit_tracking (user_id, action, window_start, request_count)
  VALUES (COALESCE(v_user_id, '00000000-0000-0000-0000-000000000000'::uuid), p_action, v_window_start, 1)
  ON CONFLICT (user_id, action, window_start)
  DO UPDATE SET request_count = rate_limit_tracking.request_count + 1
  RETURNING request_count INTO v_current_count;

  -- Check if limit exceeded
  IF v_current_count > p_max_requests THEN
    PERFORM log_security_event(
      'rate_limit_exceeded',
      'rate_limit',
      NULL,
      false,
      format('User exceeded rate limit for action: %s', p_action),
      jsonb_build_object('action', p_action, 'count', v_current_count, 'limit', p_max_requests)
    );
    RETURN false;
  END IF;

  RETURN true;
END;
$$;


--
-- Name: FUNCTION check_rate_limit(p_action text, p_max_requests integer, p_window_seconds integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.check_rate_limit(p_action text, p_max_requests integer, p_window_seconds integer) IS 'Checks if user has exceeded rate limit for a given action. Returns false if limit exceeded.';


--
-- Name: claim_counts_for_lists(uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.claim_counts_for_lists(p_list_ids uuid[]) RETURNS TABLE(list_id uuid, claim_count integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: claim_item(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.claim_item(p_item_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: cleanup_old_activity_logs(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cleanup_old_activity_logs() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  delete from public.daily_activity_log
  where created_at < now() - interval '7 days';
end;
$$;


--
-- Name: cleanup_old_invites(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cleanup_old_invites() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  delete from public.event_invites
  where status in ('accepted', 'declined')
    and responded_at < now() - interval '30 days';
end;
$$;


--
-- Name: cleanup_old_notifications(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cleanup_old_notifications() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  delete from public.notification_queue
  where sent = true
    and created_at < now() - interval '7 days';
end;
$$;


--
-- Name: cleanup_old_reminders(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cleanup_old_reminders() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  delete from public.sent_reminders sr
  using public.events e
  where sr.event_id = e.id
    and (e.event_date < now() - interval '7 days' or e.event_date is null);
end;
$$;


--
-- Name: cleanup_orphaned_lists(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cleanup_orphaned_lists() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: cleanup_rate_limit_tracking(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cleanup_rate_limit_tracking() RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  DELETE FROM public.rate_limit_tracking
  WHERE window_start < (now() - interval '1 hour');
$$;


--
-- Name: FUNCTION cleanup_rate_limit_tracking(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cleanup_rate_limit_tracking() IS 'Cleans up old rate limit tracking records. Should be run periodically.';


--
-- Name: cleanup_reminder_on_purchase(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cleanup_reminder_on_purchase() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  -- If item was marked as purchased, remove any pending reminders
  if NEW.purchased = true and OLD.purchased = false then
    delete from public.sent_reminders
    where claim_id = NEW.id;
  end if;

  return NEW;
end;
$$;


--
-- Name: create_event_and_admin(text, date, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_event_and_admin(p_title text, p_event_date date, p_recurrence text, p_description text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_event_id uuid;
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

  -- Create event
  insert into public.events (title, description, event_date, owner_id, recurrence)
  values (trim(p_title), p_description, p_event_date, v_user, coalesce(p_recurrence, 'none'))
  returning id into v_event_id;

  -- Make creator an admin member
  insert into public.event_members (event_id, user_id, role)
  values (v_event_id, v_user, 'admin')
  on conflict do nothing;

  return v_event_id;
end;
$$;


--
-- Name: create_event_and_admin(text, date, text, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_event_and_admin(p_title text, p_event_date date, p_recurrence text, p_description text, p_admin_only_invites boolean DEFAULT false) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_event_id uuid;
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

  -- Create event with admin_only_invites setting
  insert into public.events (title, description, event_date, owner_id, recurrence, admin_only_invites)
  values (trim(p_title), p_description, p_event_date, v_user, coalesce(p_recurrence, 'none'), coalesce(p_admin_only_invites, false))
  returning id into v_event_id;

  -- Make creator an admin member
  insert into public.event_members (event_id, user_id, role)
  values (v_event_id, v_user, 'admin')
  on conflict do nothing;

  return v_event_id;
end;
$$;


--
-- Name: create_event_and_admin(text, date, text, text, boolean, text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_event_and_admin(p_title text, p_event_date date, p_recurrence text, p_description text, p_admin_only_invites boolean DEFAULT false, p_admin_emails text[] DEFAULT ARRAY[]::text[]) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
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
$_$;


--
-- Name: create_list_with_people(uuid, text, public.list_visibility, uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_list_with_people(p_event_id uuid, p_name text, p_visibility public.list_visibility DEFAULT 'event'::public.list_visibility, p_recipients uuid[] DEFAULT '{}'::uuid[]) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;


--
-- Name: create_list_with_people(uuid, text, public.list_visibility, uuid[], uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_list_with_people(p_event_id uuid, p_name text, p_visibility public.list_visibility DEFAULT 'event'::public.list_visibility, p_recipients uuid[] DEFAULT '{}'::uuid[], p_viewers uuid[] DEFAULT '{}'::uuid[]) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;


--
-- Name: create_list_with_people(uuid, text, public.list_visibility, uuid[], uuid[], uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_list_with_people(p_event_id uuid, p_name text, p_visibility public.list_visibility DEFAULT 'event'::public.list_visibility, p_recipients uuid[] DEFAULT '{}'::uuid[], p_hidden_recipients uuid[] DEFAULT '{}'::uuid[], p_viewers uuid[] DEFAULT '{}'::uuid[]) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;


--
-- Name: create_list_with_people(uuid, text, public.list_visibility, uuid[], uuid[], uuid[], text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_list_with_people(p_event_id uuid, p_name text, p_visibility public.list_visibility DEFAULT 'event'::public.list_visibility, p_recipients uuid[] DEFAULT '{}'::uuid[], p_hidden_recipients uuid[] DEFAULT '{}'::uuid[], p_viewers uuid[] DEFAULT '{}'::uuid[], p_custom_recipient_name text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;


--
-- Name: create_list_with_people(uuid, text, text, text, uuid[], text[], uuid[], uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_list_with_people(p_event_id uuid, p_name text, p_visibility text, p_custom_recipient_name text, p_recipient_user_ids uuid[], p_recipient_emails text[], p_viewer_ids uuid[], p_exclusion_ids uuid[]) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;


--
-- Name: create_list_with_people(uuid, text, public.list_visibility, uuid[], uuid[], uuid[], text, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_list_with_people(p_event_id uuid, p_name text, p_visibility public.list_visibility DEFAULT 'event'::public.list_visibility, p_recipients uuid[] DEFAULT '{}'::uuid[], p_hidden_recipients uuid[] DEFAULT '{}'::uuid[], p_viewers uuid[] DEFAULT '{}'::uuid[], p_custom_recipient_name text DEFAULT NULL::text, p_random_assignment_enabled boolean DEFAULT false, p_random_assignment_mode text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_user uuid;
  v_list_id uuid;
  v_is_member boolean;
BEGIN
  v_user := auth.uid();

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Check membership in event
  SELECT EXISTS(
    SELECT 1 FROM public.event_members
    WHERE event_id = p_event_id AND user_id = v_user
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RAISE EXCEPTION 'not_an_event_member';
  END IF;

  -- Validate random assignment mode if enabled
  IF p_random_assignment_enabled THEN
    IF p_random_assignment_mode IS NULL OR
       p_random_assignment_mode NOT IN ('one_per_member', 'distribute_all') THEN
      RAISE EXCEPTION 'invalid_random_assignment_mode';
    END IF;
  END IF;

  -- Create list with all fields including random assignment settings
  INSERT INTO public.lists (
    event_id,
    name,
    created_by,
    visibility,
    custom_recipient_name,
    random_assignment_enabled,
    random_assignment_mode
  )
  VALUES (
    p_event_id,
    trim(p_name),
    v_user,
    COALESCE(p_visibility, 'event'),
    p_custom_recipient_name,
    p_random_assignment_enabled,
    CASE WHEN p_random_assignment_enabled THEN p_random_assignment_mode ELSE NULL END
  )
  RETURNING id INTO v_list_id;

  -- Add recipients (per-recipient can_view flag)
  IF array_length(p_recipients, 1) IS NOT NULL THEN
    INSERT INTO public.list_recipients (list_id, user_id, can_view)
    SELECT v_list_id, r, NOT (r = ANY(COALESCE(p_hidden_recipients, '{}')))
    FROM unnest(p_recipients) AS r;
  END IF;

  -- Add explicit viewers (only matters when visibility = 'selected')
  IF COALESCE(p_visibility, 'event') = 'selected'
     AND array_length(p_viewers, 1) IS NOT NULL THEN
    INSERT INTO public.list_viewers (list_id, user_id)
    SELECT v_list_id, v
    FROM unnest(p_viewers) AS v;
  END IF;

  RETURN v_list_id;
END;
$$;


--
-- Name: FUNCTION create_list_with_people(p_event_id uuid, p_name text, p_visibility public.list_visibility, p_recipients uuid[], p_hidden_recipients uuid[], p_viewers uuid[], p_custom_recipient_name text, p_random_assignment_enabled boolean, p_random_assignment_mode text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.create_list_with_people(p_event_id uuid, p_name text, p_visibility public.list_visibility, p_recipients uuid[], p_hidden_recipients uuid[], p_viewers uuid[], p_custom_recipient_name text, p_random_assignment_enabled boolean, p_random_assignment_mode text) IS 'Creates a list with recipients, viewers, and optional random assignment configuration';


--
-- Name: create_list_with_people(uuid, text, public.list_visibility, uuid[], uuid[], uuid[], text, boolean, text, boolean, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_list_with_people(p_event_id uuid, p_name text, p_visibility public.list_visibility DEFAULT 'event'::public.list_visibility, p_recipients uuid[] DEFAULT '{}'::uuid[], p_hidden_recipients uuid[] DEFAULT '{}'::uuid[], p_viewers uuid[] DEFAULT '{}'::uuid[], p_custom_recipient_name text DEFAULT NULL::text, p_random_assignment_enabled boolean DEFAULT false, p_random_assignment_mode text DEFAULT NULL::text, p_random_receiver_assignment_enabled boolean DEFAULT false, p_for_everyone boolean DEFAULT false) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_user uuid;
  v_list_id uuid;
  v_is_member boolean;
BEGIN
  v_user := auth.uid();

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Check membership in event
  SELECT EXISTS(
    SELECT 1 FROM public.event_members
    WHERE event_id = p_event_id AND user_id = v_user
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RAISE EXCEPTION 'not_an_event_member';
  END IF;

  -- Validate random assignment mode if enabled
  IF p_random_assignment_enabled THEN
    IF p_random_assignment_mode IS NULL OR
       p_random_assignment_mode NOT IN ('one_per_member', 'distribute_all') THEN
      RAISE EXCEPTION 'invalid_random_assignment_mode';
    END IF;
  END IF;

  -- Input validation
  IF p_name IS NULL OR trim(p_name) = '' THEN
    RAISE EXCEPTION 'list_name_required';
  END IF;

  IF length(trim(p_name)) > 255 THEN
    RAISE EXCEPTION 'list_name_too_long';
  END IF;

  -- All operations are atomic within this function (implicit transaction)
  -- If any step fails, entire function rolls back automatically

  -- Create list with all fields including random assignment settings
  INSERT INTO public.lists (
    event_id,
    name,
    created_by,
    visibility,
    custom_recipient_name,
    random_assignment_enabled,
    random_assignment_mode,
    random_receiver_assignment_enabled,
    for_everyone
  )
  VALUES (
    p_event_id,
    trim(p_name),
    v_user,
    COALESCE(p_visibility, 'event'),
    p_custom_recipient_name,
    p_random_assignment_enabled,
    CASE WHEN p_random_assignment_enabled THEN p_random_assignment_mode ELSE NULL END,
    p_random_receiver_assignment_enabled,
    p_for_everyone
  )
  RETURNING id INTO v_list_id;

  -- Add recipients (per-recipient can_view flag)
  IF array_length(p_recipients, 1) IS NOT NULL THEN
    INSERT INTO public.list_recipients (list_id, user_id, can_view)
    SELECT v_list_id, r, NOT (r = ANY(COALESCE(p_hidden_recipients, '{}')))
    FROM unnest(p_recipients) AS r
    WHERE r IS NOT NULL;  -- Safety check for NULL UUIDs
  END IF;

  -- Add explicit viewers (only matters when visibility = 'selected')
  IF COALESCE(p_visibility, 'event') = 'selected'
     AND array_length(p_viewers, 1) IS NOT NULL THEN
    INSERT INTO public.list_viewers (list_id, user_id)
    SELECT v_list_id, v
    FROM unnest(p_viewers) AS v
    WHERE v IS NOT NULL  -- Safety check for NULL UUIDs
      AND NOT EXISTS (
        -- Don't duplicate if already a recipient
        SELECT 1 FROM public.list_recipients lr
        WHERE lr.list_id = v_list_id AND lr.user_id = v
      );
  END IF;

  RETURN v_list_id;

EXCEPTION
  WHEN OTHERS THEN
    -- Log the error (PostgreSQL 13+ syntax)
    RAISE WARNING 'create_list_with_people failed: % %', SQLERRM, SQLSTATE;
    -- Re-raise the exception to rollback transaction
    RAISE;
END;
$$;


--
-- Name: FUNCTION create_list_with_people(p_event_id uuid, p_name text, p_visibility public.list_visibility, p_recipients uuid[], p_hidden_recipients uuid[], p_viewers uuid[], p_custom_recipient_name text, p_random_assignment_enabled boolean, p_random_assignment_mode text, p_random_receiver_assignment_enabled boolean, p_for_everyone boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.create_list_with_people(p_event_id uuid, p_name text, p_visibility public.list_visibility, p_recipients uuid[], p_hidden_recipients uuid[], p_viewers uuid[], p_custom_recipient_name text, p_random_assignment_enabled boolean, p_random_assignment_mode text, p_random_receiver_assignment_enabled boolean, p_for_everyone boolean) IS 'Creates a list with recipients, viewers, and optional random assignment configuration. Transaction-safe with automatic rollback on error.';


--
-- Name: debug_my_claims(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.debug_my_claims() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  DECLARE
    result jsonb;
  BEGIN
    SELECT jsonb_build_object(
      'user_id', auth.uid(),
      'claim_count', (SELECT COUNT(*) FROM claims WHERE claimer_id =
  auth.uid()),
      'claims_visible', (
        SELECT jsonb_agg(jsonb_build_object(
          'id', c.id,
          'item_id', c.item_id,
          'item_name', i.name
        ))
        FROM claims c
        LEFT JOIN items i ON i.id = c.item_id
        WHERE c.claimer_id = auth.uid()
      )
    ) INTO result;

    RETURN result;
  END;
  $$;


--
-- Name: decline_event_invite(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.decline_event_invite(p_invite_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;


--
-- Name: delete_item(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_item(p_item_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id uuid;
  v_item record;
  v_is_authorized boolean;
  v_event_member_count int;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    PERFORM log_security_event('delete_item', 'item', p_item_id, false, 'not_authenticated');
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Validate input
  IF p_item_id IS NULL THEN
    RAISE EXCEPTION 'item_id_required';
  END IF;

  -- Rate limit check
  IF NOT check_rate_limit('delete_item', 50, 60) THEN
    RAISE EXCEPTION 'rate_limit_exceeded';
  END IF;

  -- Get item details
  SELECT i.*, l.event_id, l.created_by as list_creator
  INTO v_item
  FROM public.items i
  JOIN public.lists l ON l.id = i.list_id
  WHERE i.id = p_item_id;

  IF NOT FOUND THEN
    PERFORM log_security_event('delete_item', 'item', p_item_id, false, 'not_found');
    RAISE EXCEPTION 'not_found';
  END IF;

  -- Get event member count
  SELECT COUNT(*)
  INTO v_event_member_count
  FROM public.event_members
  WHERE event_id = v_item.event_id;

  -- Check authorization
  SELECT
    -- Item creator
    (v_item.created_by = v_user_id)
    -- OR list creator
    OR (v_item.list_creator = v_user_id)
    -- OR event admin
    OR EXISTS (
      SELECT 1 FROM public.event_members em
      WHERE em.event_id = v_item.event_id
        AND em.user_id = v_user_id
        AND em.role = 'admin'
    )
    -- OR event owner
    OR EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = v_item.event_id
        AND e.owner_id = v_user_id
    )
    -- OR last member in event
    OR (v_event_member_count = 1)
  INTO v_is_authorized;

  IF NOT v_is_authorized THEN
    PERFORM log_security_event('delete_item', 'item', p_item_id, false, 'not_authorized');
    RAISE EXCEPTION 'not_authorized';
  END IF;

  -- Check if item has claims
  IF EXISTS (SELECT 1 FROM public.claims WHERE item_id = p_item_id) THEN
    PERFORM log_security_event('delete_item', 'item', p_item_id, false, 'has_claims');
    RAISE EXCEPTION 'has_claims';
  END IF;

  -- Delete item
  DELETE FROM public.items WHERE id = p_item_id;

  -- Log success
  PERFORM log_security_event('delete_item', 'item', p_item_id, true);
END;
$$;


--
-- Name: FUNCTION delete_item(p_item_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.delete_item(p_item_id uuid) IS 'Securely deletes an item with authorization checks, rate limiting, and audit logging.';


--
-- Name: delete_list(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_list(p_list_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id uuid;
  v_list record;
  v_is_authorized boolean;
  v_event_member_count int;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    PERFORM log_security_event('delete_list', 'list', p_list_id, false, 'not_authenticated');
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Validate input
  IF p_list_id IS NULL THEN
    RAISE EXCEPTION 'list_id_required';
  END IF;

  -- Rate limit check
  IF NOT check_rate_limit('delete_list', 20, 60) THEN
    RAISE EXCEPTION 'rate_limit_exceeded';
  END IF;

  -- Get list details
  SELECT l.*, l.event_id, l.created_by
  INTO v_list
  FROM public.lists l
  WHERE l.id = p_list_id;

  IF NOT FOUND THEN
    PERFORM log_security_event('delete_list', 'list', p_list_id, false, 'not_found');
    RAISE EXCEPTION 'not_found';
  END IF;

  -- Get event member count
  SELECT COUNT(*)
  INTO v_event_member_count
  FROM public.event_members
  WHERE event_id = v_list.event_id;

  -- Check authorization
  SELECT
    -- List creator
    (v_list.created_by = v_user_id)
    -- OR event admin
    OR EXISTS (
      SELECT 1 FROM public.event_members em
      WHERE em.event_id = v_list.event_id
        AND em.user_id = v_user_id
        AND em.role = 'admin'
    )
    -- OR event owner
    OR EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = v_list.event_id
        AND e.owner_id = v_user_id
    )
    -- OR last member in event
    OR (v_event_member_count = 1)
  INTO v_is_authorized;

  IF NOT v_is_authorized THEN
    PERFORM log_security_event('delete_list', 'list', p_list_id, false, 'not_authorized');
    RAISE EXCEPTION 'not_authorized';
  END IF;

  -- Delete list (CASCADE will delete items and claims)
  DELETE FROM public.lists WHERE id = p_list_id;

  -- Log success
  PERFORM log_security_event('delete_list', 'list', p_list_id, true);
END;
$$;


--
-- Name: FUNCTION delete_list(p_list_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.delete_list(p_list_id uuid) IS 'Securely deletes a list with authorization checks, rate limiting, and audit logging.';


--
-- Name: deny_claim_split(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deny_claim_split(p_request_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_request record;
BEGIN
  -- Validate user is authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get the request details
  SELECT * INTO v_request
  FROM public.claim_split_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Split request not found';
  END IF;

  -- Validate user is the original claimer
  IF v_request.original_claimer_id != auth.uid() THEN
    RAISE EXCEPTION 'Only the original claimer can deny this request';
  END IF;

  -- Validate request is still pending
  IF v_request.status != 'pending' THEN
    RAISE EXCEPTION 'Request has already been responded to';
  END IF;

  -- Update the request status
  UPDATE public.claim_split_requests
  SET
    status = 'denied',
    responded_at = now()
  WHERE id = p_request_id;
END;
$$;


--
-- Name: ensure_event_owner_member(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_event_owner_member() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: event_claim_counts_for_user(uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.event_claim_counts_for_user(p_event_ids uuid[]) RETURNS TABLE(event_id uuid, claim_count integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: event_id_for_item(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.event_id_for_item(i_id uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select l.event_id
  from public.items i
  join public.lists l on l.id = i.list_id
  where i.id = i_id
$$;


--
-- Name: event_id_for_list(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.event_id_for_list(uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
  SELECT event_id FROM public.lists WHERE id = $1
$_$;


--
-- Name: event_is_accessible(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.event_is_accessible(p_event_id uuid, p_user uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
  $$;


--
-- Name: events_for_current_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.events_for_current_user() RETURNS TABLE(id uuid, title text, event_date date, join_code text, created_at timestamp with time zone, member_count bigint, total_items bigint, claimed_count bigint, accessible boolean, rownum integer, my_claims bigint, my_unpurchased_claims bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  WITH me AS (
    SELECT auth.uid() AS uid
  ),
  my_events AS (
    SELECT e.*
    FROM events e
    JOIN event_members em ON em.event_id = e.id
    JOIN me ON me.uid = em.user_id
  ),
  counts AS (
    SELECT
      l.event_id,
      count(DISTINCT l.id) AS list_count,
      count(i.id) AS total_items
    FROM lists l
    LEFT JOIN items i ON i.list_id = l.id
    GROUP BY l.event_id
  ),
  claim_counts AS (
    -- NEW LOGIC: Count CLAIMED ITEMS from ALL visible lists (not just lists I created)
    -- Exclude lists where I'm the recipient (to protect gift surprises)
    -- This matches EventDetailScreen's totalClaimsVisible calculation
    SELECT
      l.event_id,
      COUNT(DISTINCT i.id) AS claimed_count
    FROM lists l
    JOIN items i ON i.list_id = l.id
    WHERE
      -- User can view this list (uses can_view_list for privacy/visibility checks)
      public.can_view_list(l.id, (SELECT uid FROM me)) = true
      -- AND user is NOT a recipient on this list (gift surprise protection)
      AND NOT EXISTS (
        SELECT 1 FROM list_recipients lr
        WHERE lr.list_id = l.id AND lr.user_id = (SELECT uid FROM me)
      )
      -- AND item has at least one claim
      AND EXISTS (
        SELECT 1 FROM claims c WHERE c.item_id = i.id
      )
    GROUP BY l.event_id
  ),
  ranked AS (
    SELECT
      e.id,
      e.title,
      e.event_date,
      e.join_code,
      e.created_at,
      (SELECT count(*) FROM event_members em2 WHERE em2.event_id = e.id) AS member_count,
      COALESCE(ct.total_items, 0) AS total_items,
      COALESCE(cc.claimed_count, 0) AS claimed_count,
      COALESCE(ems.total_claims, 0) AS my_claims,
      COALESCE(ems.unpurchased_claims, 0) AS my_unpurchased_claims,
      row_number() OVER (ORDER BY e.created_at ASC NULLS LAST, e.id) AS rownum
    FROM my_events e
    LEFT JOIN counts ct ON ct.event_id = e.id
    LEFT JOIN claim_counts cc ON cc.event_id = e.id
    LEFT JOIN event_member_stats ems ON ems.event_id = e.id AND ems.user_id = (SELECT uid FROM me)
  )
  SELECT
    r.id,
    r.title,
    r.event_date,
    r.join_code,
    r.created_at,
    r.member_count,
    r.total_items,
    r.claimed_count,
    (r.rownum <= public.allowed_event_slots()) AS accessible,
    r.rownum,
    r.my_claims,
    r.my_unpurchased_claims
  FROM ranked r
  ORDER BY r.created_at DESC NULLS LAST, r.id;
$$;


--
-- Name: events_for_current_user_optimized(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.events_for_current_user_optimized() RETURNS TABLE(id uuid, title text, event_date date, join_code text, created_at timestamp with time zone, member_count bigint, total_items bigint, claimed_count bigint, accessible boolean, rownum integer, my_claims bigint, my_unpurchased_claims bigint, members jsonb, member_user_ids uuid[])
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  WITH me AS (
    SELECT auth.uid() AS uid
  ),
  my_events AS (
    SELECT e.*
    FROM events e
    JOIN event_members em ON em.event_id = e.id
    CROSS JOIN me
    WHERE em.user_id = me.uid
  ),
  counts AS (
    SELECT
      l.event_id,
      count(DISTINCT l.id) AS list_count,
      count(i.id) AS total_items
    FROM lists l
    LEFT JOIN items i ON i.list_id = l.id
    GROUP BY l.event_id
  ),
  claims AS (
    -- Show claims on lists created by current user
    SELECT l.event_id, count(DISTINCT c.id) AS claimed_count
    FROM lists l
    JOIN items i ON i.list_id = l.id
    LEFT JOIN claims c ON c.item_id = i.id
    CROSS JOIN me
    WHERE l.created_by = me.uid
    GROUP BY l.event_id
  ),
  event_members_with_profiles AS (
    -- Get all members with their profile names for events user is in
    SELECT
      em.event_id,
      em.user_id,
      COALESCE(p.display_name, '') AS display_name
    FROM event_members em
    LEFT JOIN profiles p ON p.id = em.user_id
    WHERE em.event_id IN (SELECT id FROM my_events)
  ),
  ranked AS (
    SELECT
      e.id,
      e.title,
      e.event_date,
      e.join_code,
      e.created_at,
      (SELECT count(*) FROM event_members em2 WHERE em2.event_id = e.id) AS member_count,
      COALESCE(ct.total_items, 0) AS total_items,
      COALESCE(cl.claimed_count, 0) AS claimed_count,
      COALESCE(ems.total_claims, 0) AS my_claims,
      COALESCE(ems.unpurchased_claims, 0) AS my_unpurchased_claims,
      row_number() OVER (ORDER BY e.created_at ASC NULLS LAST, e.id) AS rownum,
      -- Aggregate members with profile names into JSONB array
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'user_id', emp.user_id,
            'display_name', emp.display_name
          )
        )
        FROM event_members_with_profiles emp
        WHERE emp.event_id = e.id
      ) AS members,
      -- Also provide array of user IDs for backward compatibility
      (
        SELECT array_agg(emp.user_id)
        FROM event_members_with_profiles emp
        WHERE emp.event_id = e.id
      ) AS member_user_ids
    FROM my_events e
    LEFT JOIN counts ct ON ct.event_id = e.id
    LEFT JOIN claims cl ON cl.event_id = e.id
    LEFT JOIN event_member_stats ems ON ems.event_id = e.id AND ems.user_id = (SELECT uid FROM me)
  )
  SELECT
    r.id,
    r.title,
    r.event_date,
    r.join_code,
    r.created_at,
    r.member_count,
    r.total_items,
    r.claimed_count,
    (r.rownum <= public.allowed_event_slots()) AS accessible,
    r.rownum,
    r.my_claims,
    r.my_unpurchased_claims,
    COALESCE(r.members, '[]'::jsonb) AS members,
    COALESCE(r.member_user_ids, ARRAY[]::uuid[]) AS member_user_ids
  FROM ranked r
  ORDER BY r.created_at DESC NULLS LAST, r.id;
$$;


--
-- Name: FUNCTION events_for_current_user_optimized(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.events_for_current_user_optimized() IS 'Optimized version of events_for_current_user that returns member details and profile names in a single query, eliminating N+1 queries.

Return columns:
- members: JSONB array of event members with format: [{"user_id": "uuid", "display_name": "Name"}]
- member_user_ids: Array of member user IDs for backward compatibility

Use the members field to avoid additional queries to event_members and profiles tables.';


--
-- Name: execute_random_receiver_assignment(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.execute_random_receiver_assignment(p_list_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_list record;
  v_event_id uuid;
  v_items_count integer;
  v_members_count integer;
  v_item record;
  v_giver_id uuid;
  v_recipient_id uuid;
  v_eligible_recipients uuid[];
  v_random_index integer;
  v_retry_count integer;
  v_max_retries integer := 10;
BEGIN
  -- Validate user is authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get list details
  SELECT l.*, l.event_id INTO v_list
  FROM public.lists l
  WHERE l.id = p_list_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'List not found';
  END IF;

  -- Verify user has permission (list creator or event admin)
  IF v_list.created_by != auth.uid() THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.event_members
      WHERE event_id = v_list.event_id
        AND user_id = auth.uid()
        AND role = 'admin'
    ) THEN
      RAISE EXCEPTION 'Only list creator or event admin can execute assignment';
    END IF;
  END IF;

  -- Check if receiver assignment is enabled
  IF NOT v_list.random_receiver_assignment_enabled THEN
    RAISE EXCEPTION 'Random receiver assignment is not enabled for this list';
  END IF;

  -- Get eligible members (all event members who are givers, excluding recipients-only)
  v_event_id := v_list.event_id;

  SELECT COUNT(*) INTO v_members_count
  FROM public.event_members em
  WHERE em.event_id = v_event_id
    AND em.role IN ('giver', 'admin');

  -- Need at least 2 members to assign different givers and receivers
  IF v_members_count < 2 THEN
    RAISE EXCEPTION 'Need at least 2 members to use random receiver assignment';
  END IF;

  -- Get items count
  SELECT COUNT(*) INTO v_items_count
  FROM public.items
  WHERE list_id = p_list_id;

  IF v_items_count = 0 THEN
    RAISE EXCEPTION 'No items in list to assign';
  END IF;

  -- Loop through each item and assign a receiver
  FOR v_item IN
    SELECT i.id, i.list_id
    FROM public.items i
    WHERE i.list_id = p_list_id
  LOOP
    -- Get the giver (assigned_to from claims)
    SELECT c.claimer_id INTO v_giver_id
    FROM public.claims c
    WHERE c.item_id = v_item.id
      AND c.assigned_to IS NOT NULL
    LIMIT 1;

    -- If no giver assigned yet, skip this item
    IF v_giver_id IS NULL THEN
      CONTINUE;
    END IF;

    -- Get eligible recipients (all givers/admins except the giver themselves)
    SELECT ARRAY_AGG(em.user_id) INTO v_eligible_recipients
    FROM public.event_members em
    WHERE em.event_id = v_event_id
      AND em.role IN ('giver', 'admin')
      AND em.user_id != v_giver_id;

    -- If no eligible recipients, skip
    IF v_eligible_recipients IS NULL OR array_length(v_eligible_recipients, 1) = 0 THEN
      CONTINUE;
    END IF;

    -- Randomly select a recipient
    v_random_index := floor(random() * array_length(v_eligible_recipients, 1)) + 1;
    v_recipient_id := v_eligible_recipients[v_random_index];

    -- Update the item with assigned recipient
    UPDATE public.items
    SET assigned_recipient_id = v_recipient_id
    WHERE id = v_item.id;
  END LOOP;

  -- Update the list to mark when receiver assignment was executed
  UPDATE public.lists
  SET random_assignment_executed_at = now()
  WHERE id = p_list_id;

END;
$$;


--
-- Name: FUNCTION execute_random_receiver_assignment(p_list_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.execute_random_receiver_assignment(p_list_id uuid) IS 'Randomly assigns a recipient to each item in a list where random receiver assignment is enabled. Only the giver (claimer) will know who their assigned recipient is.';


--
-- Name: generate_and_send_daily_digests(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_and_send_daily_digests(p_hour integer DEFAULT NULL::integer) RETURNS TABLE(digests_sent integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
  v_user_local_time timestamp with time zone;
  v_user_local_hour int;
  v_user_local_dow int;
begin
  -- Use provided hour or current hour (UTC)
  v_target_hour := coalesce(p_hour, extract(hour from now())::int);

  -- Process each user who has digest enabled
  for v_user in
    select distinct
      p.id as user_id,
      p.display_name,
      p.digest_frequency,
      p.digest_day_of_week,
      p.digest_time_hour,
      coalesce(p.timezone, 'UTC') as timezone
    from public.profiles p
    where p.notification_digest_enabled = true
      -- Only process if they have push tokens
      and exists (
        select 1 from public.push_tokens pt where pt.user_id = p.id
      )
  loop
    -- Convert current UTC time to user's local timezone
    begin
      v_user_local_time := now() AT TIME ZONE v_user.timezone;
      v_user_local_hour := extract(hour from v_user_local_time)::int;
      v_user_local_dow := extract(dow from v_user_local_time)::int;
    exception when others then
      -- If timezone is invalid, fall back to UTC
      v_user_local_time := now();
      v_user_local_hour := extract(hour from v_user_local_time)::int;
      v_user_local_dow := extract(dow from v_user_local_time)::int;
    end;

    -- Check if user's LOCAL time matches their digest schedule
    if v_user_local_hour != v_user.digest_time_hour then
      continue; -- Not the right hour for this user
    end if;

    -- Check day of week for weekly digests
    if v_user.digest_frequency = 'weekly' and v_user_local_dow != v_user.digest_day_of_week then
      continue; -- Not the right day for this user
    end if;

    -- Set lookback interval based on frequency
    v_lookback_interval := case
      when v_user.digest_frequency = 'weekly' then interval '7 days'
      else interval '24 hours'
    end;

    -- Check if user has activity in lookback period
    if not exists (
      select 1
      from public.daily_activity_log dal
      where dal.user_id = v_user.user_id
        and dal.created_at >= now() - v_lookback_interval
        and dal.created_at < now()
    ) then
      continue; -- No activity to report
    end if;

    -- Aggregate activity for this user with event and list details
    with activity_details as (
      select
        dal.event_id,
        dal.activity_type,
        dal.activity_data->>'list_name' as list_name,
        dal.activity_data->>'event_title' as event_title,
        count(*) as count
      from public.daily_activity_log dal
      where dal.user_id = v_user.user_id
        and dal.created_at >= now() - v_lookback_interval
        and dal.created_at < now()
      group by dal.event_id, dal.activity_type, dal.activity_data->>'list_name', dal.activity_data->>'event_title'
    ),
    event_summaries as (
      select
        ad.event_title,
        jsonb_agg(
          jsonb_build_object(
            'activity_type', ad.activity_type,
            'list_name', ad.list_name,
            'count', ad.count
          )
        ) as activities
      from activity_details ad
      group by ad.event_id, ad.event_title
    )
    select
      jsonb_agg(
        jsonb_build_object(
          'event_title', es.event_title,
          'activities', es.activities
        )
      ),
      array_agg(es.event_title)
    into v_activity_summary, v_events_affected
    from event_summaries es;

    -- Build notification title and body with detailed breakdown
    declare
      v_event jsonb;
      v_activity jsonb;
      v_lines text[] := array[]::text[];
      v_event_title text;
      v_list_name text;
      v_activity_type text;
      v_activity_count int;
      v_activity_text text;
    begin
      -- Build detailed lines per event/list
      if v_activity_summary is not null then
        for v_event in select jsonb_array_elements(v_activity_summary)
        loop
          v_event_title := v_event->>'event_title';

          for v_activity in select jsonb_array_elements(v_event->'activities')
          loop
            v_list_name := v_activity->>'list_name';
            v_activity_type := v_activity->>'activity_type';
            v_activity_count := (v_activity->>'count')::int;

            -- Format activity text based on type
            v_activity_text := case v_activity_type
              when 'new_list' then
                v_activity_count || ' new list' || case when v_activity_count > 1 then 's' else '' end
              when 'new_item' then
                v_activity_count || ' new item' || case when v_activity_count > 1 then 's' else '' end
              when 'new_claim' then
                v_activity_count || ' new claim' || case when v_activity_count > 1 then 's' else '' end
              when 'unclaim' then
                v_activity_count || ' unclaim' || case when v_activity_count > 1 then 's' else '' end
              else
                v_activity_count || ' ' || v_activity_type
            end;

            -- Format line: "Event-List: activity" or "Event: activity" for new_list
            if v_activity_type = 'new_list' then
              v_lines := array_append(v_lines, v_event_title || ': ' || v_activity_text);
            else
              v_lines := array_append(v_lines, v_event_title || '-' || coalesce(v_list_name, 'Unknown') || ': ' || v_activity_text);
            end if;
          end loop;
        end loop;
      end if;

      -- Skip if no lines generated
      if array_length(v_lines, 1) is null or array_length(v_lines, 1) = 0 then
        continue;
      end if;

      v_title := case
        when v_user.digest_frequency = 'weekly' then 'Your Weekly GiftCircles Summary'
        else 'Your Daily GiftCircles Summary'
      end;

      -- Join lines with newlines for the body
      v_body := array_to_string(v_lines, E'\n');

      -- Queue notification
      insert into public.notification_queue (user_id, title, body, data)
      values (
        v_user.user_id,
        v_title,
        v_body,
        jsonb_build_object(
          'type', 'digest',
          'frequency', v_user.digest_frequency,
          'summary', v_activity_summary
        )
      );

      v_count := v_count + 1;
    end;
  end loop;

  return query select v_count;
end;
$$;


--
-- Name: FUNCTION generate_and_send_daily_digests(p_hour integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.generate_and_send_daily_digests(p_hour integer) IS 'Generates and queues digest notifications with detailed activity breakdown per event and list. Shows format like "Christmas-List name: 1 new claim" instead of generic counts.';


--
-- Name: get_available_members_for_assignment(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_available_members_for_assignment(p_list_id uuid) RETURNS uuid[]
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_event_id uuid;
  v_list_creator uuid;
  v_random_receiver_enabled boolean;
  v_member_ids uuid[];
BEGIN
  -- Get list details
  SELECT event_id, created_by, COALESCE(random_receiver_assignment_enabled, false)
  INTO v_event_id, v_list_creator, v_random_receiver_enabled
  FROM public.lists
  WHERE id = p_list_id;

  IF v_event_id IS NULL THEN
    RAISE EXCEPTION 'list_not_found';
  END IF;

  -- Get all event members
  -- ONLY exclude recipients if random_receiver_assignment is NOT enabled
  -- When receiver assignment IS enabled, recipients should also be givers (Secret Santa style)
  IF v_random_receiver_enabled THEN
    -- Include all event members (don't exclude recipients)
    SELECT array_agg(em.user_id ORDER BY random())
    INTO v_member_ids
    FROM public.event_members em
    WHERE em.event_id = v_event_id;
  ELSE
    -- Exclude recipients (old behavior for simple random giver assignment)
    SELECT array_agg(em.user_id ORDER BY random())
    INTO v_member_ids
    FROM public.event_members em
    WHERE em.event_id = v_event_id
      AND NOT EXISTS (
        SELECT 1 FROM public.list_recipients lr
        WHERE lr.list_id = p_list_id AND lr.user_id = em.user_id
      );
  END IF;

  RETURN COALESCE(v_member_ids, ARRAY[]::uuid[]);
END;
$$;


--
-- Name: FUNCTION get_available_members_for_assignment(p_list_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_available_members_for_assignment(p_list_id uuid) IS 'Returns shuffled array of event members eligible for random item assignment. When random_receiver_assignment_enabled is true, includes all members (Secret Santa style). Otherwise, excludes recipients.';


--
-- Name: get_claim_counts_by_list(uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_claim_counts_by_list(p_list_ids uuid[]) RETURNS TABLE(list_id uuid, claimed_count bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();

  -- Return claim counts (number of items with at least 1 claim) for each list
  -- For combined random assignment: all members see total count (collaborative mode)
  -- For single random assignment modes: counts filtered by user visibility

  RETURN QUERY
  WITH visible_lists AS (
    -- Filter to only lists the user can view
    SELECT
      l.id,
      l.event_id,
      l.visibility,
      l.created_by,
      l.random_assignment_enabled,
      l.random_receiver_assignment_enabled
    FROM lists l
    WHERE l.id = ANY(p_list_ids)
      AND (
        -- User created the list
        l.created_by = v_user_id
        -- OR user is a recipient
        OR EXISTS (
          SELECT 1 FROM list_recipients lr
          WHERE lr.list_id = l.id AND lr.user_id = v_user_id
        )
        -- OR list visibility is 'event' and user is event member
        OR (
          l.visibility = 'event'
          AND EXISTS (
            SELECT 1 FROM event_members em
            WHERE em.event_id = l.event_id AND em.user_id = v_user_id
          )
        )
        -- OR list visibility is 'selected' and user is viewer
        OR (
          l.visibility = 'selected'
          AND EXISTS (
            SELECT 1 FROM list_viewers lv
            WHERE lv.list_id = l.id AND lv.user_id = v_user_id
          )
        )
      )
      -- Exclude lists where user is excluded
      AND NOT EXISTS (
        SELECT 1 FROM list_exclusions le
        WHERE le.list_id = l.id AND le.user_id = v_user_id
      )
  ),
  user_permissions AS (
    -- Determine if user is admin/owner for each list
    SELECT
      vl.id as list_id,
      (
        vl.created_by = v_user_id
        OR EXISTS (
          SELECT 1 FROM event_members em
          WHERE em.event_id = vl.event_id
            AND em.user_id = v_user_id
            AND em.role = 'admin'
        )
        OR EXISTS (
          SELECT 1 FROM events e
          WHERE e.id = vl.event_id AND e.owner_id = v_user_id
        )
      ) as is_admin,
      -- Check if this is combined random assignment (collaborative mode)
      (
        vl.random_assignment_enabled = true
        AND vl.random_receiver_assignment_enabled = true
      ) as is_collaborative
    FROM visible_lists vl
  ),
  visible_items AS (
    -- Get items the user can see based on list mode
    SELECT DISTINCT i.id as item_id, i.list_id
    FROM items i
    INNER JOIN visible_lists vl ON vl.id = i.list_id
    INNER JOIN user_permissions up ON up.list_id = vl.id
    WHERE
      -- For combined random assignment (collaborative): all members see all items
      up.is_collaborative = true
      -- OR admins/owners/creators always see all items
      OR up.is_admin = true
      -- OR for random giver assignment only: only see items assigned to you
      OR (
        vl.random_assignment_enabled = true
        AND COALESCE(vl.random_receiver_assignment_enabled, false) = false
        AND EXISTS (
          SELECT 1 FROM claims c
          WHERE c.item_id = i.id AND c.assigned_to = v_user_id
        )
      )
      -- OR for random receiver assignment only: hide from assigned recipients
      OR (
        COALESCE(vl.random_assignment_enabled, false) = false
        AND vl.random_receiver_assignment_enabled = true
        AND i.assigned_recipient_id != v_user_id
      )
      -- OR for non-random lists: see all items
      OR (
        COALESCE(vl.random_assignment_enabled, false) = false
        AND COALESCE(vl.random_receiver_assignment_enabled, false) = false
      )
  ),
  items_with_claims AS (
    -- Get visible items that have at least one claim
    SELECT DISTINCT vi.list_id, vi.item_id
    FROM visible_items vi
    WHERE EXISTS (
      SELECT 1 FROM claims c WHERE c.item_id = vi.item_id
    )
  )
  SELECT
    vl.id as list_id,
    COALESCE(COUNT(iwc.item_id), 0) as claimed_count
  FROM visible_lists vl
  LEFT JOIN items_with_claims iwc ON iwc.list_id = vl.id
  GROUP BY vl.id;
END;
$$;


--
-- Name: FUNCTION get_claim_counts_by_list(p_list_ids uuid[]); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_claim_counts_by_list(p_list_ids uuid[]) IS 'Returns claim counts for lists. In combined random assignment (collaborative mode), all members see total counts. In single random modes, counts filtered by visibility. Claim details remain private.';


--
-- Name: get_list_recipients(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_list_recipients(p_list_id uuid) RETURNS TABLE(list_id uuid, user_id uuid, recipient_email text, display_name text, is_registered boolean, is_event_member boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;


--
-- Name: get_my_pending_invites(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_pending_invites() RETURNS TABLE(invite_id uuid, event_id uuid, event_title text, event_date date, inviter_name text, invited_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;


--
-- Name: get_my_split_requests(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_split_requests() RETURNS TABLE(request_id uuid, item_id uuid, item_name text, event_id uuid, event_title text, list_name text, requester_id uuid, requester_name text, created_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  -- Validate user is authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  RETURN QUERY
  SELECT
    csr.id as request_id,
    csr.item_id,
    i.name as item_name,
    l.event_id,
    e.title as event_title,
    l.name as list_name,
    csr.requester_id,
    COALESCE(p.display_name, 'Unknown User') as requester_name,
    csr.created_at
  FROM public.claim_split_requests csr
  JOIN public.items i ON csr.item_id = i.id
  JOIN public.lists l ON i.list_id = l.id
  JOIN public.events e ON l.event_id = e.id
  LEFT JOIN public.profiles p ON csr.requester_id = p.id
  WHERE csr.original_claimer_id = auth.uid()
    AND csr.status = 'pending'
  ORDER BY csr.created_at DESC;
END;
$$;


--
-- Name: grant_manual_pro(uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.grant_manual_pro(p_user_id uuid, p_grant boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  UPDATE public.profiles
  SET manual_pro = p_grant
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found: %', p_user_id;
  END IF;
END;
$$;


--
-- Name: FUNCTION grant_manual_pro(p_user_id uuid, p_grant boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.grant_manual_pro(p_user_id uuid, p_grant boolean) IS 'Manually grant or revoke pro status for a user. This override persists through RevenueCat syncs. Usage: SELECT grant_manual_pro(''user-id'', true);';


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: initialize_event_member_stats(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.initialize_event_member_stats() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  -- When a new event member is added, initialize their stats
  IF TG_OP = 'INSERT' THEN
    INSERT INTO event_member_stats (event_id, user_id, total_claims, unpurchased_claims)
    VALUES (NEW.event_id, NEW.user_id, 0, 0)
    ON CONFLICT (event_id, user_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION initialize_event_member_stats(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.initialize_event_member_stats() IS 'Trigger function that initializes event_member_stats when a new member joins an event';


--
-- Name: is_event_admin(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_event_admin(e_id uuid) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.event_members em
    WHERE em.event_id = e_id
      AND em.user_id  = auth.uid()
      AND em.role     = 'admin'
  );
$$;


--
-- Name: is_event_admin(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_event_admin(e_id uuid, u_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists(select 1 from public.event_members em where em.event_id=e_id and em.user_id=u_id and em.role='admin')
$$;


--
-- Name: is_event_member(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_event_member(p_event_id uuid) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.event_members em
    WHERE em.event_id = p_event_id
      AND em.user_id  = auth.uid()
  );
$$;


--
-- Name: is_event_member(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_event_member(e_id uuid, u_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists(select 1 from public.event_members em
                where em.event_id = e_id and em.user_id = u_id)
$$;


--
-- Name: is_last_event_member(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_last_event_member(e_id uuid, u_id uuid) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  SELECT
    -- User must be a member
    EXISTS (
      SELECT 1 FROM public.event_members
      WHERE event_id = e_id AND user_id = u_id
    )
    AND
    -- Only one member total
    (SELECT count(*) FROM public.event_members WHERE event_id = e_id) = 1
$$;


--
-- Name: is_list_recipient(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_list_recipient(l_id uuid, u_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists(
    select 1
    from public.list_recipients lr
    where lr.list_id = l_id and lr.user_id = u_id
  )
$$;


--
-- Name: is_member_of_event(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_member_of_event(p_event uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT public.is_member_of_event_secure(p_event, auth.uid());
$$;


--
-- Name: is_member_of_event(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_member_of_event(e_id uuid, u_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT public.is_member_of_event_secure(e_id, u_id);
$$;


--
-- Name: is_member_of_event_secure(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_member_of_event_secure(p_event_id uuid, p_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.event_members
    WHERE event_id = p_event_id
      AND user_id = p_user_id
  );
$$;


--
-- Name: is_pro(uuid, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_pro(p_user uuid, p_at timestamp with time zone DEFAULT now()) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  select coalesce(
    (select
      -- User is pro if ANY of these are true:
      manual_pro = true                                    -- Manual override
      OR plan = 'pro'                                      -- RevenueCat set to pro
      OR (pro_until is not null and pro_until >= p_at)   -- Pro subscription not expired
     from public.profiles
     where id = p_user
    ),
    false
  );
$$;


--
-- Name: FUNCTION is_pro(p_user uuid, p_at timestamp with time zone); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.is_pro(p_user uuid, p_at timestamp with time zone) IS 'Returns true if user is pro. Checks manual_pro flag, plan column, and pro_until expiration.';


--
-- Name: is_pro_v2(uuid, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_pro_v2(p_user uuid, p_at timestamp with time zone DEFAULT now()) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: is_sole_event_member(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_sole_event_member(p_event_id uuid, p_user_id uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: join_event(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.join_event(p_code text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: leave_event(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.leave_event(p_event_id uuid) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: link_list_recipients_on_signup(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.link_list_recipients_on_signup() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;


--
-- Name: list_claim_counts_for_user(uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_claim_counts_for_user(p_list_ids uuid[]) RETURNS TABLE(list_id uuid, claim_count integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: list_claims_for_user(uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_claims_for_user(p_item_ids uuid[]) RETURNS TABLE(item_id uuid, claimer_id uuid)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT c.item_id, c.claimer_id
  FROM public.claims c
  INNER JOIN public.items i ON i.id = c.item_id
  INNER JOIN public.lists l ON l.id = i.list_id
  WHERE
    -- Only include items from the requested item IDs
    c.item_id = ANY(p_item_ids)
    -- User must be an event member
    AND EXISTS (
      SELECT 1 FROM public.event_members em
      WHERE em.event_id = l.event_id AND em.user_id = v_user_id
    )
    -- User must not be excluded from the list
    AND NOT EXISTS (
      SELECT 1 FROM public.list_exclusions le
      WHERE le.list_id = l.id AND le.user_id = v_user_id
    )
    -- Apply claim visibility rules
    AND (
      -- Rule 1: Always show your own claims
      c.claimer_id = v_user_id

      -- Rule 2: List creator sees all claims
      OR l.created_by = v_user_id

      -- Rule 3: Event admin sees all claims
      OR EXISTS (
        SELECT 1 FROM public.event_members em
        WHERE em.event_id = l.event_id
          AND em.user_id = v_user_id
          AND em.role = 'admin'
      )

      -- Rule 4: Event owner sees all claims
      OR EXISTS (
        SELECT 1 FROM public.events e
        WHERE e.id = l.event_id AND e.owner_id = v_user_id
      )

      -- Rule 5: Collaborative mode (both random features) - show claims assigned to you
      OR (
        COALESCE(l.random_assignment_enabled, false) = true
        AND COALESCE(l.random_receiver_assignment_enabled, false) = true
        AND c.assigned_to = v_user_id
      )

      -- Rule 6: Non-random lists - show claims if you're NOT a recipient
      OR (
        COALESCE(l.random_assignment_enabled, false) = false
        AND COALESCE(l.random_receiver_assignment_enabled, false) = false
        AND NOT EXISTS (
          SELECT 1 FROM public.list_recipients lr
          WHERE lr.list_id = l.id AND lr.user_id = v_user_id
        )
      )

      -- Rule 7: Single random mode - show assigned claims if NOT a recipient
      OR (
        COALESCE(l.random_assignment_enabled, false) = true
        AND COALESCE(l.random_receiver_assignment_enabled, false) = false
        AND c.assigned_to = v_user_id
        AND NOT EXISTS (
          SELECT 1 FROM public.list_recipients lr
          WHERE lr.list_id = l.id AND lr.user_id = v_user_id
        )
      )
    );
END;
$$;


--
-- Name: FUNCTION list_claims_for_user(p_item_ids uuid[]); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.list_claims_for_user(p_item_ids uuid[]) IS 'Returns claims visible to current user. Simplified version that inlines all visibility checks. Collaborative mode shows claims assigned to user regardless of recipient status.';


--
-- Name: list_id_for_item(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_id_for_item(i_id uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select list_id from public.items where id = i_id
$$;


--
-- Name: log_activity_for_digest(uuid, uuid, uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_activity_for_digest(p_event_id uuid, p_list_id uuid, p_exclude_user_id uuid, p_activity_type text, p_activity_data jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION log_activity_for_digest(p_event_id uuid, p_list_id uuid, p_exclude_user_id uuid, p_activity_type text, p_activity_data jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.log_activity_for_digest(p_event_id uuid, p_list_id uuid, p_exclude_user_id uuid, p_activity_type text, p_activity_data jsonb) IS 'Logs activity for digest notifications while respecting list visibility, exclusions, and gift surprise rules. Excludes list recipients from claim/unclaim activities.';


--
-- Name: log_security_event(text, text, uuid, boolean, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_security_event(p_action text, p_resource_type text DEFAULT NULL::text, p_resource_id uuid DEFAULT NULL::uuid, p_success boolean DEFAULT true, p_error_message text DEFAULT NULL::text, p_metadata jsonb DEFAULT NULL::jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO public.security_audit_log (
    user_id,
    action,
    resource_type,
    resource_id,
    success,
    error_message,
    metadata
  )
  VALUES (
    auth.uid(),
    p_action,
    p_resource_type,
    p_resource_id,
    p_success,
    p_error_message,
    p_metadata
  );
EXCEPTION
  WHEN OTHERS THEN
    -- Don't fail the operation if audit logging fails
    RAISE WARNING 'Failed to log security event: %', SQLERRM;
END;
$$;


--
-- Name: FUNCTION log_security_event(p_action text, p_resource_type text, p_resource_id uuid, p_success boolean, p_error_message text, p_metadata jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.log_security_event(p_action text, p_resource_type text, p_resource_id uuid, p_success boolean, p_error_message text, p_metadata jsonb) IS 'Logs security events to audit log. Used by SECURITY DEFINER functions.';


--
-- Name: mark_orphaned_lists_for_deletion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mark_orphaned_lists_for_deletion() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: notify_new_claim(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_new_claim() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: notify_new_item(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_new_item() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: notify_new_list(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_new_list() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: notify_unclaim(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_unclaim() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION notify_unclaim(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.notify_unclaim() IS 'Triggered when a claim is deleted (unclaimed). Sends instant notifications and logs digest activity. Excludes list recipients from seeing who unclaimed.';


--
-- Name: queue_notification_for_event_members(uuid, uuid, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_notification_for_event_members(p_event_id uuid, p_exclude_user_id uuid, p_notification_type text, p_title text, p_data jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: FUNCTION queue_notification_for_event_members(p_event_id uuid, p_exclude_user_id uuid, p_notification_type text, p_title text, p_data jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.queue_notification_for_event_members(p_event_id uuid, p_exclude_user_id uuid, p_notification_type text, p_title text, p_data jsonb) IS 'Queues instant notifications for event members who have opted in (instant_notifications_enabled = true) and have push tokens registered. Excludes the user who triggered the action.';


--
-- Name: queue_notification_for_list_activity(uuid, uuid, uuid, text, text, jsonb, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_notification_for_list_activity(p_list_id uuid, p_event_id uuid, p_exclude_user_id uuid, p_notification_type text, p_title text, p_data jsonb, p_exclude_recipients boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: FUNCTION queue_notification_for_list_activity(p_list_id uuid, p_event_id uuid, p_exclude_user_id uuid, p_notification_type text, p_title text, p_data jsonb, p_exclude_recipients boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.queue_notification_for_list_activity(p_list_id uuid, p_event_id uuid, p_exclude_user_id uuid, p_notification_type text, p_title text, p_data jsonb, p_exclude_recipients boolean) IS 'Queues instant notifications for list activities (new list, new item, claim, unclaim) with privacy checks. Uses can_view_list() to respect list visibility, exclusions, and viewers. Optionally excludes list recipients for claim/unclaim notifications.';


--
-- Name: recalculate_event_member_stats(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recalculate_event_member_stats(p_event_id uuid, p_user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_total_claims bigint;
  v_unpurchased_claims bigint;
BEGIN
  -- Calculate claim counts for this user in this event
  -- For collaborative mode (both random features): include all claims
  -- For other modes: exclude claims on lists where user is the recipient

  SELECT
    COUNT(c.id),
    COUNT(c.id) FILTER (WHERE c.purchased = false)
  INTO v_total_claims, v_unpurchased_claims
  FROM claims c
  JOIN items i ON i.id = c.item_id
  JOIN lists l ON l.id = i.list_id
  WHERE l.event_id = p_event_id
    AND c.claimer_id = p_user_id
    AND (
      -- Include claims in collaborative mode (both random features enabled)
      (
        COALESCE(l.random_assignment_enabled, false) = true
        AND COALESCE(l.random_receiver_assignment_enabled, false) = true
      )
      -- OR include claims on non-recipient lists
      OR NOT EXISTS (
        SELECT 1 FROM list_recipients lr
        WHERE lr.list_id = l.id AND lr.user_id = p_user_id
      )
    );

  -- Upsert the stats
  INSERT INTO event_member_stats (event_id, user_id, total_claims, unpurchased_claims, updated_at)
  VALUES (p_event_id, p_user_id, v_total_claims, v_unpurchased_claims, now())
  ON CONFLICT (event_id, user_id)
  DO UPDATE SET
    total_claims = EXCLUDED.total_claims,
    unpurchased_claims = EXCLUDED.unpurchased_claims,
    updated_at = now();
END;
$$;


--
-- Name: FUNCTION recalculate_event_member_stats(p_event_id uuid, p_user_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.recalculate_event_member_stats(p_event_id uuid, p_user_id uuid) IS 'Recalculates and updates claim statistics for a specific user in a specific event. Includes collaborative mode claims.';


--
-- Name: refresh_event_member_stats(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_event_member_stats(p_event_id uuid, p_user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_total_claims integer;
  v_unpurchased_claims integer;
BEGIN
  -- Calculate actual claims for this user in this event
  SELECT
    COUNT(c.id),
    COUNT(c.id) FILTER (WHERE c.purchased = false)
  INTO v_total_claims, v_unpurchased_claims
  FROM claims c
  JOIN items i ON i.id = c.item_id
  JOIN lists l ON l.id = i.list_id
  WHERE l.event_id = p_event_id
    AND c.claimer_id = p_user_id;

  -- Update or insert the stats
  INSERT INTO event_member_stats (event_id, user_id, total_claims, unpurchased_claims, updated_at)
  VALUES (p_event_id, p_user_id, v_total_claims, v_unpurchased_claims, NOW())
  ON CONFLICT (event_id, user_id)
  DO UPDATE SET
    total_claims = v_total_claims,
    unpurchased_claims = v_unpurchased_claims,
    updated_at = NOW();

  -- If no claims left, delete the stats row
  IF v_total_claims = 0 THEN
    DELETE FROM event_member_stats
    WHERE event_id = p_event_id AND user_id = p_user_id;
  END IF;
END;
$$;


--
-- Name: remove_member(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.remove_member(p_event_id uuid, p_user_id uuid) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: request_claim_split(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.request_claim_split(p_item_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_original_claimer_id uuid;
  v_request_id uuid;
  v_list_id uuid;
  v_event_id uuid;
BEGIN
  -- Validate user is authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get the original claimer (first claimer based on created_at)
  SELECT c.claimer_id INTO v_original_claimer_id
  FROM public.claims c
  WHERE c.item_id = p_item_id
  ORDER BY c.created_at ASC
  LIMIT 1;

  -- Validate item is claimed
  IF v_original_claimer_id IS NULL THEN
    RAISE EXCEPTION 'Item is not claimed';
  END IF;

  -- Validate user is not the original claimer
  IF v_original_claimer_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot request to split your own claim';
  END IF;

  -- Validate user is not already a claimer
  IF EXISTS (
    SELECT 1 FROM public.claims
    WHERE item_id = p_item_id AND claimer_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'You have already claimed this item';
  END IF;

  -- Validate user is a member of the event
  SELECT i.list_id, l.event_id INTO v_list_id, v_event_id
  FROM public.items i
  JOIN public.lists l ON i.list_id = l.id
  WHERE i.id = p_item_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.event_members
    WHERE event_id = v_event_id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'You are not a member of this event';
  END IF;

  -- Check if there's already a pending request
  IF EXISTS (
    SELECT 1 FROM public.claim_split_requests
    WHERE item_id = p_item_id
      AND requester_id = auth.uid()
      AND original_claimer_id = v_original_claimer_id
      AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'You already have a pending split request for this item';
  END IF;

  -- Create the split request
  INSERT INTO public.claim_split_requests (
    item_id,
    requester_id,
    original_claimer_id,
    status
  ) VALUES (
    p_item_id,
    auth.uid(),
    v_original_claimer_id,
    'pending'
  )
  RETURNING id INTO v_request_id;

  RETURN v_request_id;
END;
$$;


--
-- Name: rollover_all_due_events(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rollover_all_due_events() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: sanitize_text(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sanitize_text(p_text text, p_max_length integer DEFAULT 1000) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$
BEGIN
  IF p_text IS NULL THEN
    RETURN NULL;
  END IF;

  -- Trim whitespace and limit length
  RETURN substring(trim(p_text) from 1 for p_max_length);
END;
$$;


--
-- Name: FUNCTION sanitize_text(p_text text, p_max_length integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.sanitize_text(p_text text, p_max_length integer) IS 'Sanitizes text input by trimming whitespace and limiting length.';


--
-- Name: send_event_invite(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.send_event_invite(p_event_id uuid, p_invitee_email text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
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
begin
  -- Validate inviter is event member
  if not exists (
    select 1 from public.event_members
    where event_id = p_event_id and user_id = auth.uid()
  ) then
    raise exception 'Not authorized to invite to this event';
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
$_$;


--
-- Name: send_event_invite(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.send_event_invite(p_event_id uuid, p_inviter_email text, p_recipient_email text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
declare
  v_invite_id uuid;
  v_admin_only_invites boolean;
  v_is_admin boolean;
begin
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

  -- Validate email format
  if p_recipient_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then
    raise exception 'invalid_email';
  end if;

  -- Insert invite
  insert into public.event_invites (event_id, inviter_email, recipient_email)
  values (p_event_id, p_inviter_email, p_recipient_email)
  returning id into v_invite_id;

  return v_invite_id;
end;
$_$;


--
-- Name: set_list_created_by(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_list_created_by() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if new.created_by is null then
    new.created_by := auth.uid();
  end if;
  return new;
end;
$$;


--
-- Name: set_onboarding_done(boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_onboarding_done(p_done boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  update public.profiles
  set onboarding_done = coalesce(p_done, true),
      onboarding_at   = case when coalesce(p_done, true) then now() else null end
  where id = auth.uid();
end
$$;


--
-- Name: set_plan(text, integer, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_plan(p_plan text, p_months integer DEFAULT 0, p_user uuid DEFAULT auth.uid()) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: set_profile_name(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_profile_name(p_name text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  insert into public.profiles (id, display_name)
  values (auth.uid(), p_name)
  on conflict (id) do update set display_name = excluded.display_name;
end;
$$;


--
-- Name: test_get_my_claims(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.test_get_my_claims() RETURNS TABLE(claim_id uuid, item_id uuid, purchased boolean, created_at timestamp with time zone, auth_user_id uuid, can_see_claim boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.id as claim_id,
    c.item_id,
    c.purchased,
    c.created_at,
    auth.uid() as auth_user_id,
    (c.claimer_id = auth.uid()) as can_see_claim
  FROM claims c
  WHERE c.claimer_id = auth.uid();
END;
$$;


--
-- Name: test_impersonate(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.test_impersonate(p_user_id uuid) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user_id::text)::text,
    true
  );
end;
$$;


--
-- Name: tg_set_timestamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_set_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


--
-- Name: trigger_daily_digest(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_daily_digest() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  declare
    v_url text;
    v_request_id bigint;
  begin
    v_url :=
  'https://bqgakovbbbiudmggduvu.supabase.co/functions/v1/send-daily-digest';

    -- Call the edge function WITHOUT passing hour - let it use current time
    -- This allows timezone-aware digest scheduling to work properly
    select net.http_post(
      url := v_url,
      headers := '{"Content-Type": "application/json", "Authorization": 
  "Bearer 
  eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJxZ
  2Frb3ZiYmJpdWRtZ2dkdXZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcwNTY1MjEsImV4cCI
  6MjA3MjYzMjUyMX0.i81E7-w03a1v6BV2FwGpuNRA9tTVWF3nATgJeeO5g1k"}'::jsonb,
      body := '{}'::jsonb
    ) into v_request_id;
  end;
  $$;


--
-- Name: trigger_push_notifications(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_push_notifications() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;


--
-- Name: trigger_refresh_stats_on_claim_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_refresh_stats_on_claim_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_event_id uuid;
BEGIN
  -- Get the event_id from the claim's item
  SELECT l.event_id INTO v_event_id
  FROM items i
  JOIN lists l ON l.id = i.list_id
  WHERE i.id = OLD.item_id;

  -- Refresh stats for this user in this event
  IF v_event_id IS NOT NULL THEN
    PERFORM refresh_event_member_stats(v_event_id, OLD.claimer_id);
  END IF;

  RETURN OLD;
END;
$$;


--
-- Name: trigger_refresh_stats_on_item_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_refresh_stats_on_item_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_event_id uuid;
  v_claimer_id uuid;
BEGIN
  -- Get event_id from the item's list
  SELECT event_id INTO v_event_id
  FROM lists
  WHERE id = OLD.list_id;

  -- Refresh stats for all users who had claims on this item
  IF v_event_id IS NOT NULL THEN
    FOR v_claimer_id IN
      SELECT DISTINCT claimer_id FROM claims WHERE item_id = OLD.id
    LOOP
      PERFORM refresh_event_member_stats(v_event_id, v_claimer_id);
    END LOOP;
  END IF;

  RETURN OLD;
END;
$$;


--
-- Name: trigger_refresh_stats_on_list_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_refresh_stats_on_list_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_claimer_id uuid;
BEGIN
  -- Refresh stats for all users who had claims on items in this list
  FOR v_claimer_id IN
    SELECT DISTINCT c.claimer_id
    FROM claims c
    JOIN items i ON i.id = c.item_id
    WHERE i.list_id = OLD.id
  LOOP
    PERFORM refresh_event_member_stats(OLD.event_id, v_claimer_id);
  END LOOP;

  RETURN OLD;
END;
$$;


--
-- Name: unclaim_item(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.unclaim_item(p_item_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: unmark_orphaned_lists_on_member_join(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.unmark_orphaned_lists_on_member_join() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  -- When a new member joins an event, remove any orphaned list markers for that event
  DELETE FROM public.orphaned_lists
  WHERE event_id = NEW.event_id;

  RETURN NEW;
END;
$$;


--
-- Name: update_event_member_stats_on_claim_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_event_member_stats_on_claim_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_event_id uuid;
  v_claimer_id uuid;
  v_old_claimer_id uuid;
BEGIN
  -- Handle INSERT and UPDATE
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    -- Get event_id and claimer_id from the new claim
    SELECT l.event_id, NEW.claimer_id
    INTO v_event_id, v_claimer_id
    FROM items i
    JOIN lists l ON l.id = i.list_id
    WHERE i.id = NEW.item_id;

    -- Recalculate stats for this user in this event
    IF v_event_id IS NOT NULL AND v_claimer_id IS NOT NULL THEN
      PERFORM recalculate_event_member_stats(v_event_id, v_claimer_id);
    END IF;
  END IF;

  -- Handle UPDATE where claimer_id changed (claim reassignment)
  IF TG_OP = 'UPDATE' AND OLD.claimer_id IS DISTINCT FROM NEW.claimer_id THEN
    -- Get event_id for old claimer
    SELECT l.event_id
    INTO v_event_id
    FROM items i
    JOIN lists l ON l.id = i.list_id
    WHERE i.id = OLD.item_id;

    -- Recalculate stats for old claimer
    IF v_event_id IS NOT NULL AND OLD.claimer_id IS NOT NULL THEN
      PERFORM recalculate_event_member_stats(v_event_id, OLD.claimer_id);
    END IF;
  END IF;

  -- Handle DELETE
  IF TG_OP = 'DELETE' THEN
    -- Get event_id and claimer_id from the deleted claim
    SELECT l.event_id, OLD.claimer_id
    INTO v_event_id, v_claimer_id
    FROM items i
    JOIN lists l ON l.id = i.list_id
    WHERE i.id = OLD.item_id;

    -- Recalculate stats for this user in this event
    IF v_event_id IS NOT NULL AND v_claimer_id IS NOT NULL THEN
      PERFORM recalculate_event_member_stats(v_event_id, v_claimer_id);
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$;


--
-- Name: FUNCTION update_event_member_stats_on_claim_change(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.update_event_member_stats_on_claim_change() IS 'Trigger function that updates event_member_stats when claims are added, updated, or deleted';


--
-- Name: update_event_member_stats_on_list_event_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_event_member_stats_on_list_event_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id uuid;
BEGIN
  -- Only handle UPDATE where event_id changed
  IF TG_OP = 'UPDATE' AND OLD.event_id IS DISTINCT FROM NEW.event_id THEN
    -- Get all users who have claims on items in this list
    FOR v_user_id IN
      SELECT DISTINCT c.claimer_id
      FROM claims c
      JOIN items i ON i.id = c.item_id
      WHERE i.list_id = NEW.id
    LOOP
      -- Recalculate for old event
      PERFORM recalculate_event_member_stats(OLD.event_id, v_user_id);
      -- Recalculate for new event
      PERFORM recalculate_event_member_stats(NEW.event_id, v_user_id);
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION update_event_member_stats_on_list_event_change(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.update_event_member_stats_on_list_event_change() IS 'Trigger function that updates event_member_stats when a list is moved to a different event';


--
-- Name: update_event_member_stats_on_recipient_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_event_member_stats_on_recipient_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_event_id uuid;
  v_affected_users uuid[];
BEGIN
  -- Get event_id from the list
  SELECT l.event_id
  INTO v_event_id
  FROM lists l
  WHERE l.id = COALESCE(NEW.list_id, OLD.list_id);

  IF v_event_id IS NULL THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    ELSE
      RETURN NEW;
    END IF;
  END IF;

  -- When a user is added/removed as recipient, their claim stats might change
  -- because we exclude claims on lists where user is recipient

  -- Collect affected user IDs
  v_affected_users := ARRAY[]::uuid[];

  IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.user_id IS NOT NULL THEN
    v_affected_users := array_append(v_affected_users, NEW.user_id);
  END IF;

  IF TG_OP IN ('DELETE', 'UPDATE') AND OLD.user_id IS NOT NULL THEN
    v_affected_users := array_append(v_affected_users, OLD.user_id);
  END IF;

  -- Recalculate stats for each affected user
  FOR i IN 1..array_length(v_affected_users, 1) LOOP
    PERFORM recalculate_event_member_stats(v_event_id, v_affected_users[i]);
  END LOOP;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$;


--
-- Name: FUNCTION update_event_member_stats_on_recipient_change(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.update_event_member_stats_on_recipient_change() IS 'Trigger function that updates event_member_stats when list recipients change';


--
-- Name: update_invites_on_user_signup(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_invites_on_user_signup() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth'
    AS $$
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
$$;


--
-- Name: validate_email(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_email(p_email text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $_$
BEGIN
  RETURN p_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';
END;
$_$;


--
-- Name: FUNCTION validate_email(p_email text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.validate_email(p_email text) IS 'Validates if a text value is a valid email address.';


--
-- Name: validate_uuid(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_uuid(p_value text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$
BEGIN
  -- Try to cast to UUID
  PERFORM p_value::uuid;
  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    RETURN false;
END;
$$;


--
-- Name: FUNCTION validate_uuid(p_value text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.validate_uuid(p_value text) IS 'Validates if a text value is a valid UUID.';


--
-- Name: whoami(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.whoami() RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select jsonb_build_object(
    'uid', auth.uid(),
    'role', current_setting('request.jwt.claim.role', true)
  );
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: claim_split_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.claim_split_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    item_id uuid NOT NULL,
    requester_id uuid NOT NULL,
    original_claimer_id uuid NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    responded_at timestamp with time zone,
    CONSTRAINT claim_split_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'denied'::text])))
);


--
-- Name: claims; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.claims (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    item_id uuid NOT NULL,
    claimer_id uuid NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    note text,
    created_at timestamp with time zone DEFAULT now(),
    purchased boolean DEFAULT false NOT NULL,
    assigned_to uuid,
    CONSTRAINT chk_claims_quantity_positive CHECK ((quantity > 0)),
    CONSTRAINT claims_quantity_check CHECK ((quantity > 0))
);

ALTER TABLE ONLY public.claims FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE claims; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.claims IS 'Multiple permissive policies exist for flexibility. Consider consolidating if performance issues arise.';


--
-- Name: COLUMN claims.assigned_to; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.claims.assigned_to IS 'For random assignment lists: the user this item was assigned to. NULL for manual claims.';


--
-- Name: daily_activity_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_activity_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    event_id uuid NOT NULL,
    activity_type text NOT NULL,
    activity_data jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT daily_activity_log_activity_type_check CHECK ((activity_type = ANY (ARRAY['new_list'::text, 'new_item'::text, 'new_claim'::text, 'unclaim'::text])))
);


--
-- Name: event_invites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_invites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    inviter_id uuid NOT NULL,
    invitee_email text NOT NULL,
    invitee_id uuid,
    status text DEFAULT 'pending'::text NOT NULL,
    invited_at timestamp with time zone DEFAULT now(),
    responded_at timestamp with time zone,
    invited_role public.member_role DEFAULT 'giver'::public.member_role NOT NULL,
    CONSTRAINT event_invites_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'declined'::text])))
);


--
-- Name: event_member_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_member_stats (
    event_id uuid NOT NULL,
    user_id uuid NOT NULL,
    total_claims bigint DEFAULT 0 NOT NULL,
    unpurchased_claims bigint DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE event_member_stats; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.event_member_stats IS 'Materialized claim statistics per user per event. Updated automatically via triggers for performance.';


--
-- Name: COLUMN event_member_stats.total_claims; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.event_member_stats.total_claims IS 'Total number of claims by this user in this event (excluding claims on lists where user is recipient)';


--
-- Name: COLUMN event_member_stats.unpurchased_claims; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.event_member_stats.unpurchased_claims IS 'Number of unpurchased claims by this user in this event (excluding claims on lists where user is recipient)';


--
-- Name: event_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_members (
    event_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role public.member_role DEFAULT 'giver'::public.member_role NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE ONLY public.event_members FORCE ROW LEVEL SECURITY;


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    description text,
    event_date date,
    join_code text DEFAULT replace((gen_random_uuid())::text, '-'::text, ''::text) NOT NULL,
    owner_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    recurrence text DEFAULT 'none'::text NOT NULL,
    last_rolled_at date,
    admin_only_invites boolean DEFAULT false NOT NULL,
    CONSTRAINT chk_events_date_reasonable CHECK (((event_date IS NULL) OR (event_date >= '2020-01-01'::date))),
    CONSTRAINT events_recurrence_check CHECK ((recurrence = ANY (ARRAY['none'::text, 'weekly'::text, 'monthly'::text, 'yearly'::text])))
);

ALTER TABLE ONLY public.events FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE events; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.events IS 'Multiple permissive policies exist for flexibility. Consider consolidating if performance issues arise.';


--
-- Name: items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    list_id uuid NOT NULL,
    name text NOT NULL,
    url text,
    price numeric(12,2),
    notes text,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    assigned_recipient_id uuid,
    CONSTRAINT chk_items_price_positive CHECK (((price IS NULL) OR (price >= (0)::numeric)))
);

ALTER TABLE ONLY public.items FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN items.assigned_recipient_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.items.assigned_recipient_id IS 'For random receiver assignment lists: the user this item is intended for. NULL for regular lists. The giver (claimer) should not equal this recipient.';


--
-- Name: list_exclusions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.list_exclusions (
    list_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.list_exclusions FORCE ROW LEVEL SECURITY;


--
-- Name: list_recipients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.list_recipients (
    list_id uuid NOT NULL,
    user_id uuid,
    can_view boolean DEFAULT true NOT NULL,
    recipient_email text,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    CONSTRAINT list_recipients_user_or_email_check CHECK ((((user_id IS NOT NULL) AND (recipient_email IS NULL)) OR ((user_id IS NULL) AND (recipient_email IS NOT NULL))))
);

ALTER TABLE ONLY public.list_recipients FORCE ROW LEVEL SECURITY;


--
-- Name: list_viewers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.list_viewers (
    list_id uuid NOT NULL,
    user_id uuid NOT NULL
);

ALTER TABLE ONLY public.list_viewers FORCE ROW LEVEL SECURITY;


--
-- Name: lists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lists (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    name text NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    visibility public.list_visibility DEFAULT 'event'::public.list_visibility NOT NULL,
    custom_recipient_name text,
    random_assignment_enabled boolean DEFAULT false NOT NULL,
    random_assignment_mode text,
    random_assignment_executed_at timestamp with time zone,
    random_receiver_assignment_enabled boolean DEFAULT false NOT NULL,
    for_everyone boolean DEFAULT false NOT NULL,
    CONSTRAINT lists_random_assignment_mode_check CHECK ((random_assignment_mode = ANY (ARRAY['one_per_member'::text, 'distribute_all'::text])))
);

ALTER TABLE ONLY public.lists FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN lists.random_assignment_enabled; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lists.random_assignment_enabled IS 'When true, items are randomly assigned and members can only see their assignments.';


--
-- Name: COLUMN lists.random_assignment_mode; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lists.random_assignment_mode IS 'Assignment mode: one_per_member (1 item each) or distribute_all (all items distributed evenly).';


--
-- Name: COLUMN lists.random_assignment_executed_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lists.random_assignment_executed_at IS 'Timestamp of the last random assignment execution.';


--
-- Name: COLUMN lists.random_receiver_assignment_enabled; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lists.random_receiver_assignment_enabled IS 'When true, each item is randomly assigned to a specific recipient. Only the giver knows who will receive their item.';


--
-- Name: COLUMN lists.for_everyone; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lists.for_everyone IS 'When true, this list is for all event members. All members can claim items (but cannot see who claimed them).';


--
-- Name: notification_queue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_queue (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    data jsonb,
    sent boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: orphaned_lists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orphaned_lists (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    list_id uuid NOT NULL,
    event_id uuid NOT NULL,
    excluded_user_id uuid NOT NULL,
    marked_at timestamp with time zone DEFAULT now() NOT NULL,
    delete_at timestamp with time zone DEFAULT (now() + '30 days'::interval) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    display_name text,
    avatar_url text,
    created_at timestamp with time zone DEFAULT now(),
    onboarding_done boolean DEFAULT false NOT NULL,
    onboarding_at timestamp with time zone,
    plan text DEFAULT 'free'::text NOT NULL,
    pro_until timestamp with time zone,
    reminder_days integer,
    currency character varying(3) DEFAULT 'USD'::character varying,
    notification_digest_enabled boolean DEFAULT false,
    digest_time_hour integer DEFAULT 9,
    digest_frequency text DEFAULT 'daily'::text,
    digest_day_of_week integer DEFAULT 1,
    last_support_screen_shown timestamp with time zone,
    timezone text DEFAULT 'UTC'::text,
    manual_pro boolean DEFAULT false,
    instant_notifications_enabled boolean DEFAULT false,
    CONSTRAINT chk_profiles_digest_day_valid CHECK (((digest_day_of_week >= 0) AND (digest_day_of_week <= 6))),
    CONSTRAINT chk_profiles_digest_hour_valid CHECK (((digest_time_hour >= 0) AND (digest_time_hour <= 23))),
    CONSTRAINT chk_profiles_reminder_days_valid CHECK (((reminder_days >= 0) AND (reminder_days <= 365))),
    CONSTRAINT profiles_digest_day_of_week_check CHECK (((digest_day_of_week >= 0) AND (digest_day_of_week <= 6))),
    CONSTRAINT profiles_digest_frequency_check CHECK ((digest_frequency = ANY (ARRAY['daily'::text, 'weekly'::text]))),
    CONSTRAINT profiles_digest_time_hour_check CHECK (((digest_time_hour >= 0) AND (digest_time_hour <= 23))),
    CONSTRAINT profiles_reminder_days_check CHECK (((reminder_days >= 0) AND (reminder_days <= 30)))
);

ALTER TABLE ONLY public.profiles FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN profiles.reminder_days; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.reminder_days IS 'Days before event to send purchase reminder. NULL = disabled. Pro feature only.';


--
-- Name: COLUMN profiles.currency; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.currency IS 'ISO 4217 currency code (e.g., USD, EUR, GBP)';


--
-- Name: COLUMN profiles.notification_digest_enabled; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.notification_digest_enabled IS 'Whether user receives activity digest notifications. Pro feature only.';


--
-- Name: COLUMN profiles.digest_time_hour; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.digest_time_hour IS 'Hour of day (0-23) to send daily digest in user local time';


--
-- Name: COLUMN profiles.digest_frequency; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.digest_frequency IS 'Frequency of digest notifications: daily or weekly';


--
-- Name: COLUMN profiles.digest_day_of_week; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.digest_day_of_week IS 'Day of week for weekly digest (0=Sunday, 1=Monday, ..., 6=Saturday)';


--
-- Name: COLUMN profiles.last_support_screen_shown; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.last_support_screen_shown IS 'Timestamp when support screen was last shown to user. Support screen shows every 30 days for free users (checked via profiles.plan and profiles.pro_until)';


--
-- Name: COLUMN profiles.timezone; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.timezone IS 'User timezone in IANA format (e.g., America/New_York, Europe/London). Used to deliver digest notifications at user local time.';


--
-- Name: COLUMN profiles.manual_pro; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.manual_pro IS 'Manual pro override flag. When true, user is treated as pro regardless of RevenueCat subscription. For testing/admin purposes only.';


--
-- Name: COLUMN profiles.instant_notifications_enabled; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.instant_notifications_enabled IS 'When true, user receives instant push notifications for list/item/claim activity. When false (default), user only receives digest notifications. Purchase reminders are always sent regardless of this setting.';


--
-- Name: push_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.push_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    token text NOT NULL,
    platform text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT push_tokens_platform_check CHECK ((platform = ANY (ARRAY['ios'::text, 'android'::text, 'web'::text])))
);


--
-- Name: rate_limit_tracking; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rate_limit_tracking (
    user_id uuid NOT NULL,
    action text NOT NULL,
    window_start timestamp with time zone NOT NULL,
    request_count integer DEFAULT 1 NOT NULL
);


--
-- Name: security_audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.security_audit_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    action text NOT NULL,
    resource_type text,
    resource_id uuid,
    ip_address inet,
    user_agent text,
    success boolean NOT NULL,
    error_message text,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE security_audit_log; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.security_audit_log IS 'Security audit log for tracking sensitive operations. Only accessible via SECURITY DEFINER functions.';


--
-- Name: sent_reminders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sent_reminders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    claim_id uuid NOT NULL,
    event_id uuid NOT NULL,
    sent_at timestamp with time zone DEFAULT now()
);


--
-- Name: user_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_plans (
    user_id uuid NOT NULL,
    pro_until timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    note text
);

ALTER TABLE ONLY public.user_plans FORCE ROW LEVEL SECURITY;


--
-- Data for Name: claim_split_requests; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.claim_split_requests (id, item_id, requester_id, original_claimer_id, status, created_at, responded_at) FROM stdin;
2d5aafef-c27f-4956-8541-8d200b5c4d02	f20c705a-0f5b-4c11-bcc0-5129daabc0ab	0881f0e0-4254-4f76-b487-99b40dd08f10	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	accepted	2025-11-11 18:22:18.556266+00	2025-11-11 18:22:30.398353+00
\.


--
-- Data for Name: claims; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.claims (id, item_id, claimer_id, quantity, note, created_at, purchased, assigned_to) FROM stdin;
33274dc6-a8e8-489d-a59e-2db000f21ae1	1e72fd24-4755-4e9e-b0bb-7bfbb2d9c02c	0881f0e0-4254-4f76-b487-99b40dd08f10	1	\N	2025-11-16 08:24:52.973959+00	f	\N
4a961375-ca68-47fb-9e79-a9197fe22628	6c098f6c-f734-4ad4-a97b-fd4eb28e50b6	76657cf1-b6ae-4956-808e-0cce2b6b786e	1	\N	2025-11-04 16:36:19.718676+00	f	\N
b26fbb67-ae22-494a-bb47-d12437441ce3	c7609500-f8d5-454d-bc64-56fc1ab51f85	0881f0e0-4254-4f76-b487-99b40dd08f10	1	\N	2025-11-07 12:03:11.957569+00	t	\N
3011afb7-3460-48f1-9823-09bd352887e1	49782fcc-4ad6-45f3-a12e-7ffe6f7163f7	0881f0e0-4254-4f76-b487-99b40dd08f10	1	\N	2025-11-07 11:34:38.310903+00	t	\N
17fb2e42-2c67-492b-98b9-ae6636b43b22	c9598198-41a0-409a-b1e9-1070d625b662	1264aa19-a50f-484c-a70e-09ec38588b89	1	\N	2025-11-08 16:36:17.186556+00	f	\N
e548fbad-8111-4638-9d42-f81979082cc1	0d696f96-82f5-4694-8a49-f89aad444857	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	1	\N	2025-11-11 18:12:53.840555+00	f	\N
2854dbed-fa2e-4aa7-8cf0-5e7d49f23629	c4bc9c53-90fd-4a98-b47c-ed80af41a995	1264aa19-a50f-484c-a70e-09ec38588b89	1	\N	2025-11-11 18:14:03.931842+00	f	\N
e4914539-7663-4936-b057-702bb7102c2e	8dc28afa-38a0-4131-811c-d89ebecfc5c4	1264aa19-a50f-484c-a70e-09ec38588b89	1	\N	2025-11-11 18:15:27.170902+00	f	\N
7a2285c6-d8de-4011-b485-8c0cf52aaa2b	f20c705a-0f5b-4c11-bcc0-5129daabc0ab	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	1	\N	2025-11-11 18:22:09.785995+00	f	\N
eff97763-6f70-4329-9e9f-8630a10a91e8	b4ca359a-3d01-4474-814c-b126c5696e0e	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	1	\N	2025-11-11 18:28:13.989025+00	f	\N
44943e9e-db01-4707-aae3-40b7dd4f2b04	d29de562-1b76-4100-96d6-f34e8ab05700	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	1	\N	2025-11-11 18:31:29.414881+00	f	\N
90257ecf-25d9-4d1c-a800-f5bbee5f33ec	f4881d4b-5c49-4025-aed3-de3d3cd107b6	0881f0e0-4254-4f76-b487-99b40dd08f10	1	\N	2025-11-11 18:32:56.062985+00	f	\N
142c1271-97a0-4ddf-825d-6c5aaee9c7a5	91172816-d99c-410f-8ca9-3670f39914a7	0881f0e0-4254-4f76-b487-99b40dd08f10	1	\N	2025-11-11 18:37:19.769282+00	f	\N
947e4a50-db31-426c-81b3-d53a596b4cee	1855340a-0842-4cca-a1f2-99b1f08ccfb1	0881f0e0-4254-4f76-b487-99b40dd08f10	1	\N	2025-11-11 18:21:50.606014+00	t	\N
6990c4e4-a4de-408d-93fe-9f495a0b4182	0a480b65-dc9d-45db-a439-d5f003783c45	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	1	\N	2025-11-14 08:03:00.589383+00	f	\N
260a6e29-869b-4896-b278-3af01700a2de	f20c705a-0f5b-4c11-bcc0-5129daabc0ab	0881f0e0-4254-4f76-b487-99b40dd08f10	1	Split claim	2025-11-11 18:22:30.398353+00	t	\N
b0f299ef-d196-4795-8f64-61cbb6e01c49	2a22e9f8-b027-4a1b-b1f7-60a2d510584f	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	1	\N	2025-11-16 08:05:57.301887+00	f	\N
\.


--
-- Data for Name: daily_activity_log; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.daily_activity_log (id, user_id, event_id, activity_type, activity_data, created_at) FROM stdin;
c4002b1f-863b-4a74-bfe8-5d8836636e9f	0881f0e0-4254-4f76-b487-99b40dd08f10	7a98e60a-60a2-4687-8423-abddfc34a80f	new_item	{"item_id": "867ab307-8cb9-4044-8bd0-3c7c5598e111", "list_id": "9e0973f1-a776-411d-8a3c-358118516afa", "item_name": "Kokbok man fyller i själv", "list_name": "Emma🤷🏻‍♀️s wishlist", "event_title": "Christmas", "creator_name": "Emma Molgaard"}	2025-11-13 09:28:30.838837+00
6c899e53-8b9e-48b0-925e-45eb202d54c6	0881f0e0-4254-4f76-b487-99b40dd08f10	743e2f40-4470-47d6-ad5c-7ab10a663788	new_item	{"item_id": "2b5867ee-34f0-4e26-9a09-9e0efad6d168", "list_id": "1689395f-5c60-4b46-9db0-67de6625080d", "item_name": "Chair", "list_name": "Test notification", "event_title": "Chris' birthday", "creator_name": "Sarah Axt"}	2025-11-14 07:06:08.788551+00
b4434f8e-b305-4a0e-93c8-2aa52dfea7e9	0881f0e0-4254-4f76-b487-99b40dd08f10	743e2f40-4470-47d6-ad5c-7ab10a663788	new_list	{"list_id": "247af0c3-7289-4a20-8bea-54ca74ac74c7", "list_name": "What Chris needs", "event_title": "Chris' birthday", "creator_name": "Sarah Axt"}	2025-11-14 07:06:49.75001+00
a8aaa526-637d-4699-a747-c7802b271ed0	0881f0e0-4254-4f76-b487-99b40dd08f10	743e2f40-4470-47d6-ad5c-7ab10a663788	new_item	{"item_id": "0a480b65-dc9d-45db-a439-d5f003783c45", "list_id": "247af0c3-7289-4a20-8bea-54ca74ac74c7", "item_name": "Hug", "list_name": "What Chris needs", "event_title": "Chris' birthday", "creator_name": "Sarah Axt"}	2025-11-14 07:09:11.665292+00
32dfaee9-ef31-4f2f-a090-0c3fa905253f	0881f0e0-4254-4f76-b487-99b40dd08f10	743e2f40-4470-47d6-ad5c-7ab10a663788	new_claim	{"item_id": "0a480b65-dc9d-45db-a439-d5f003783c45", "list_id": "247af0c3-7289-4a20-8bea-54ca74ac74c7", "claim_id": "9ac002eb-d90a-4f71-8564-3dc6103fe6da", "item_name": "Hug", "list_name": "What Chris needs", "event_title": "Chris' birthday", "claimer_name": "Sarah Axt"}	2025-11-14 07:28:08.497521+00
8e3538b1-2917-4347-994f-2d5e191f7a48	0881f0e0-4254-4f76-b487-99b40dd08f10	7a98e60a-60a2-4687-8423-abddfc34a80f	new_claim	{"item_id": "2a22e9f8-b027-4a1b-b1f7-60a2d510584f", "list_id": "ecb7d1e2-1fd0-404c-be6c-c56fd287b007", "claim_id": "b0f299ef-d196-4795-8f64-61cbb6e01c49", "item_name": "Chess set", "list_name": "Tomas secret", "event_title": "Christmas", "claimer_name": "Sarah Axt"}	2025-11-16 08:05:57.301887+00
51fd7029-bf36-4882-922d-b4afd3f2ea16	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	7a98e60a-60a2-4687-8423-abddfc34a80f	unclaim	{"item_id": "1e72fd24-4755-4e9e-b0bb-7bfbb2d9c02c", "list_id": "a6979636-d39a-4bbd-a1b9-928babb92e7a", "claim_id": "1f96c3a9-8ecf-4a38-947c-b944de5e0bf4", "item_name": "Frying pan", "list_name": "Thyra's list", "event_title": "Christmas", "unclaimer_name": "Chris Axt"}	2025-11-16 08:24:06.199772+00
2424b8bb-809f-4c7d-823e-8cc3768b2ce9	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	7a98e60a-60a2-4687-8423-abddfc34a80f	new_claim	{"item_id": "1e72fd24-4755-4e9e-b0bb-7bfbb2d9c02c", "list_id": "a6979636-d39a-4bbd-a1b9-928babb92e7a", "claim_id": "867c63a4-d990-41c4-89f0-3d3f213db1fb", "item_name": "Frying pan", "list_name": "Thyra's list", "event_title": "Christmas", "claimer_name": "Chris Axt"}	2025-11-16 08:24:22.54892+00
a2db11b6-6c0f-47d3-9fcb-e545aacbc733	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	7a98e60a-60a2-4687-8423-abddfc34a80f	unclaim	{"item_id": "1e72fd24-4755-4e9e-b0bb-7bfbb2d9c02c", "list_id": "a6979636-d39a-4bbd-a1b9-928babb92e7a", "claim_id": "867c63a4-d990-41c4-89f0-3d3f213db1fb", "item_name": "Frying pan", "list_name": "Thyra's list", "event_title": "Christmas", "unclaimer_name": "Chris Axt"}	2025-11-16 08:24:50.677751+00
b4eb34da-1f2b-45fa-b383-e1b7040fbcdf	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	7a98e60a-60a2-4687-8423-abddfc34a80f	new_claim	{"item_id": "1e72fd24-4755-4e9e-b0bb-7bfbb2d9c02c", "list_id": "a6979636-d39a-4bbd-a1b9-928babb92e7a", "claim_id": "33274dc6-a8e8-489d-a59e-2db000f21ae1", "item_name": "Frying pan", "list_name": "Thyra's list", "event_title": "Christmas", "claimer_name": "Chris Axt"}	2025-11-16 08:24:52.973959+00
\.


--
-- Data for Name: event_invites; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.event_invites (id, event_id, inviter_id, invitee_email, invitee_id, status, invited_at, responded_at, invited_role) FROM stdin;
8f206d6a-863d-44a1-87c4-d291bae7f118	b40aca00-c0fd-4804-bfaa-893d9111d770	1264aa19-a50f-484c-a70e-09ec38588b89	sgmolgaard@gmail.com	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	accepted	2025-10-11 09:04:07.816256+00	2025-10-11 09:04:35.266418+00	giver
199abafc-23d7-4b11-84eb-0255c8ef3bfc	7a98e60a-60a2-4687-8423-abddfc34a80f	0881f0e0-4254-4f76-b487-99b40dd08f10	sgmolgaard@gmail.com	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	accepted	2025-10-11 09:12:15.076421+00	2025-10-11 09:13:58.728484+00	giver
3c77da51-78ce-4763-a094-b3e7b7a0da82	7a98e60a-60a2-4687-8423-abddfc34a80f	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	douglasmolgaard@gmail.com	be884d3f-71f2-484b-9a19-5e3097e7d74e	accepted	2025-10-11 09:15:19.714443+00	2025-10-11 09:15:33.925452+00	giver
663c1220-0b7b-4b0b-a1e5-5380adbb031a	7a98e60a-60a2-4687-8423-abddfc34a80f	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	annakmolgaard@gmail.com	76657cf1-b6ae-4956-808e-0cce2b6b786e	accepted	2025-10-11 09:16:05.320222+00	2025-10-11 09:20:24.28077+00	giver
a076674f-52f3-49a6-9cf4-eb9646c439e9	7a98e60a-60a2-4687-8423-abddfc34a80f	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	emmolgaard@gmail.com	1264aa19-a50f-484c-a70e-09ec38588b89	accepted	2025-10-11 09:17:13.166793+00	2025-10-11 09:22:53.130666+00	giver
bf8e19bf-d504-4d4e-b655-8bcb9055d8ed	7a98e60a-60a2-4687-8423-abddfc34a80f	1264aa19-a50f-484c-a70e-09ec38588b89	thelocoooooo@gmail.com	c88ebcdb-8a4c-4839-ae12-78ad7e6e2c72	accepted	2025-10-11 14:06:07.012729+00	2025-10-11 15:46:33.584679+00	giver
d7b87e66-049f-4635-a319-bbe15cfe1f77	7a98e60a-60a2-4687-8423-abddfc34a80f	0881f0e0-4254-4f76-b487-99b40dd08f10	osangarr@gmail.com	77125c99-44be-4be8-975f-86ffb849f6bd	accepted	2025-10-11 09:22:18.256019+00	2025-10-11 17:19:36.514082+00	giver
fc900db0-0000-4152-ac61-3cbc65eb37e6	743e2f40-4470-47d6-ad5c-7ab10a663788	0881f0e0-4254-4f76-b487-99b40dd08f10	sgmolgaard@gmail.com	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	accepted	2025-10-11 17:51:42.058856+00	2025-10-11 17:52:10.90133+00	giver
1ddf4b33-ea58-448a-8b7f-f52dbf284d5a	743e2f40-4470-47d6-ad5c-7ab10a663788	0881f0e0-4254-4f76-b487-99b40dd08f10	osangarr@gmail.com	77125c99-44be-4be8-975f-86ffb849f6bd	accepted	2025-10-11 17:52:04.190656+00	2025-10-12 09:39:30.385453+00	giver
d021a7d7-4278-4f38-ace1-c4a99b6117b1	78617fe1-b69a-4d45-9457-d124fb6da05b	0881f0e0-4254-4f76-b487-99b40dd08f10	chrisaxt.swe@gmail.com	962f043b-340e-4f3f-9d45-2f3816580648	accepted	2025-10-12 14:13:14.387015+00	2025-10-12 14:13:21.110835+00	giver
38fdf6a4-2643-4ccd-8210-b201376265c5	78617fe1-b69a-4d45-9457-d124fb6da05b	962f043b-340e-4f3f-9d45-2f3816580648	chris.axt1@gmail.com	0881f0e0-4254-4f76-b487-99b40dd08f10	accepted	2025-10-13 11:57:22.803371+00	2025-10-13 11:59:07.439664+00	giver
c598ef57-a7c3-4494-94aa-5da25c565777	7a98e60a-60a2-4687-8423-abddfc34a80f	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	thyramolgaard@gmail.com	bd7a30c2-5513-4896-8db8-0771ce6873f8	accepted	2025-11-02 09:52:14.884802+00	2025-11-02 09:56:35.52733+00	giver
\.


--
-- Data for Name: event_member_stats; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.event_member_stats (event_id, user_id, total_claims, unpurchased_claims, updated_at) FROM stdin;
7a98e60a-60a2-4687-8423-abddfc34a80f	76657cf1-b6ae-4956-808e-0cce2b6b786e	1	1	2025-11-07 14:23:53.768164+00
d782262f-4593-40be-b889-cc694fe6dcd0	962f043b-340e-4f3f-9d45-2f3816580648	0	0	2025-11-10 12:38:34.999306+00
8f2a2049-a968-4c33-b6c0-5456f9252d3d	962f043b-340e-4f3f-9d45-2f3816580648	0	0	2025-11-10 12:38:52.37949+00
7a98e60a-60a2-4687-8423-abddfc34a80f	1264aa19-a50f-484c-a70e-09ec38588b89	3	3	2025-11-11 18:15:27.170902+00
743e2f40-4470-47d6-ad5c-7ab10a663788	0881f0e0-4254-4f76-b487-99b40dd08f10	0	0	2025-11-14 07:06:49.75001+00
743e2f40-4470-47d6-ad5c-7ab10a663788	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	1	1	2025-11-14 08:03:00.589383+00
7a98e60a-60a2-4687-8423-abddfc34a80f	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	5	5	2025-11-16 08:05:57.301887+00
7a98e60a-60a2-4687-8423-abddfc34a80f	0881f0e0-4254-4f76-b487-99b40dd08f10	7	3	2025-11-16 08:24:52.973959+00
\.


--
-- Data for Name: event_members; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.event_members (event_id, user_id, role, created_at) FROM stdin;
bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb01	00000000-0000-4000-8000-000000000001	admin	2025-11-01 14:48:44.34851+00
7a98e60a-60a2-4687-8423-abddfc34a80f	bd7a30c2-5513-4896-8db8-0771ce6873f8	giver	2025-11-02 09:56:35.52733+00
d782262f-4593-40be-b889-cc694fe6dcd0	962f043b-340e-4f3f-9d45-2f3816580648	admin	2025-11-10 12:38:34.999306+00
8f2a2049-a968-4c33-b6c0-5456f9252d3d	962f043b-340e-4f3f-9d45-2f3816580648	admin	2025-11-10 12:38:52.37949+00
b40aca00-c0fd-4804-bfaa-893d9111d770	1264aa19-a50f-484c-a70e-09ec38588b89	admin	2025-10-11 09:00:36.309051+00
b40aca00-c0fd-4804-bfaa-893d9111d770	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	giver	2025-10-11 09:04:35.266418+00
7a98e60a-60a2-4687-8423-abddfc34a80f	0881f0e0-4254-4f76-b487-99b40dd08f10	admin	2025-10-11 09:11:25.454767+00
7a98e60a-60a2-4687-8423-abddfc34a80f	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	giver	2025-10-11 09:13:58.728484+00
7a98e60a-60a2-4687-8423-abddfc34a80f	be884d3f-71f2-484b-9a19-5e3097e7d74e	giver	2025-10-11 09:15:33.925452+00
7a98e60a-60a2-4687-8423-abddfc34a80f	76657cf1-b6ae-4956-808e-0cce2b6b786e	giver	2025-10-11 09:20:24.28077+00
7a98e60a-60a2-4687-8423-abddfc34a80f	1264aa19-a50f-484c-a70e-09ec38588b89	giver	2025-10-11 09:22:53.130666+00
7a98e60a-60a2-4687-8423-abddfc34a80f	c88ebcdb-8a4c-4839-ae12-78ad7e6e2c72	giver	2025-10-11 15:46:33.584679+00
7a98e60a-60a2-4687-8423-abddfc34a80f	77125c99-44be-4be8-975f-86ffb849f6bd	giver	2025-10-11 17:19:36.514082+00
743e2f40-4470-47d6-ad5c-7ab10a663788	0881f0e0-4254-4f76-b487-99b40dd08f10	admin	2025-10-11 17:50:51.730067+00
743e2f40-4470-47d6-ad5c-7ab10a663788	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	giver	2025-10-11 17:52:10.90133+00
743e2f40-4470-47d6-ad5c-7ab10a663788	77125c99-44be-4be8-975f-86ffb849f6bd	giver	2025-10-12 09:39:30.385453+00
78617fe1-b69a-4d45-9457-d124fb6da05b	962f043b-340e-4f3f-9d45-2f3816580648	admin	2025-10-12 14:13:21.110835+00
\.


--
-- Data for Name: events; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.events (id, title, description, event_date, join_code, owner_id, created_at, recurrence, last_rolled_at, admin_only_invites) FROM stdin;
d782262f-4593-40be-b889-cc694fe6dcd0	Event 2	\N	2025-11-21	116515aeb7fe4750aa34b1b5f7b35310	962f043b-340e-4f3f-9d45-2f3816580648	2025-11-10 12:38:34.999306+00	none	\N	f
8f2a2049-a968-4c33-b6c0-5456f9252d3d	Birthday	\N	2025-11-30	f8548b9f14ce415caa1078229539563e	962f043b-340e-4f3f-9d45-2f3816580648	2025-11-10 12:38:52.37949+00	none	\N	f
78617fe1-b69a-4d45-9457-d124fb6da05b	Test claims	This is a detailed description of some shit	2025-11-19	027c5d81d2fc4fa6a615cd95a22d3cfc	962f043b-340e-4f3f-9d45-2f3816580648	2025-10-12 14:12:56.142872+00	weekly	2025-11-12	f
7a98e60a-60a2-4687-8423-abddfc34a80f	Christmas	\N	2025-12-25	9f6b7d2217844a059aa1a36da57812fd	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-10-11 09:11:25.454767+00	yearly	\N	f
b40aca00-c0fd-4804-bfaa-893d9111d770	Emmas B-day! 🎉🥳	\N	2026-06-05	da7835b6c80e40b0974391b7634a6c53	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 09:00:36.309051+00	none	\N	f
743e2f40-4470-47d6-ad5c-7ab10a663788	Chris' birthday	\N	2025-12-17	5d7edb45b66440818bc6cb4603c76c30	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-10-11 17:50:51.730067+00	yearly	\N	f
bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb01	Fresh Event	\N	\N	FRESH99	00000000-0000-4000-8000-000000000001	2025-11-01 14:48:44.34851+00	none	\N	f
\.


--
-- Data for Name: items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.items (id, list_id, name, url, price, notes, created_by, created_at, assigned_recipient_id) FROM stdin;
a6090029-67df-48cc-83d6-f8a5797bbf54	9e0973f1-a776-411d-8a3c-358118516afa	Mop set	https://amzn.eu/d/6s5iFcQ	303.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-11-08 16:26:28.259069+00	\N
9e346977-260b-4932-b6be-24b9a3476ba4	9e0973f1-a776-411d-8a3c-358118516afa	Sleep mask	https://amzn.eu/d/2vbAcRW	180.00	Behöver ej vara denna	1264aa19-a50f-484c-a70e-09ec38588b89	2025-11-08 16:35:14.965326+00	\N
b65a733b-dae0-4a5e-9128-8097b148ace6	b76debc4-1d61-46fb-844e-5c934cf4e797	Moroccanoil Treatment	https://www.deloox.se/produkt/1075140/moroccanoil-treatment-100-ml.html?pcid=1912&pid=1075140	512.00	Liten flaska uppskattas också!	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 09:07:05.240058+00	\N
3bcfbdf9-2aa6-41a9-9401-76b77740b40c	db921861-a6e8-44fd-97d3-2b56b19e1869	Egg cooker	\N	\N	\N	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	2025-10-11 09:22:27.125395+00	\N
3cf99b20-69f2-409b-b77f-5e67cfd2bf78	28b0a6b7-28bb-4d47-ba84-b2df44a1948c	Godis	https://www.arkenzoo.se/itsybitsy-cat-freeze-dried-notlever	54.90	\N	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-10-11 14:51:52.850204+00	\N
91a9ff11-1d8c-43ee-b231-d8925f2367d6	cb59656f-bf92-4823-a825-90790d04e3d3	White board	https://www.amazon.se/Amazon-Basics-magnetisk-whiteboard-aluminiumlister/dp/B077TGBB72/ref=asc_df_B077TGBB72?mcid=1afda8d2c6f33e178ffa57d706cc3700&tag=shpngadsglesm-21&linkCode=df0&hvadid=719763806861&hvpos=&hvnetw=g&hvrand=12356677099886875506&hvpone=&hvptwo=&hvqmt=&hvdev=m&hvdvcmdl=&hvlocint=&hvlocphy=1012480&hvtargid=pla-475734670055&psc=1&language=sv_SE&gad_source=1	245.00	\N	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-10-11 13:26:38.771697+00	\N
6c098f6c-f734-4ad4-a97b-fd4eb28e50b6	28b0a6b7-28bb-4d47-ba84-b2df44a1948c	More godis	\N	\N	\N	77125c99-44be-4be8-975f-86ffb849f6bd	2025-10-11 17:28:22.882736+00	\N
70302c75-9494-4258-9226-52ec120d25ae	6fe4b461-01d6-47ad-ab5d-b7f0a247a5cb	Automatic ball thrower	\N	\N	\N	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-10-11 13:36:43.532259+00	\N
d6b6dbf3-bd8e-4447-87a3-e07c7e2f1564	9e0973f1-a776-411d-8a3c-358118516afa	sun moon stars perfume	\N	\N	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 13:41:04.952522+00	\N
bc7bb9ad-e83b-4589-81c8-35c3a917ef61	9e0973f1-a776-411d-8a3c-358118516afa	Eye lash serum	https://lyko.com/sv/lenoites/lenoites-eye-lash-serum-5-ml?utm_source=adtraction&utm_medium=affiliate&utm_campaign=Gowish.com&utm_content=1117786221&at_gd=2689E3925D18FA2FF9BE3D009EA7D8A1E8BA45F8	325.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 13:43:25.459902+00	\N
68d828f0-8e87-41f8-b3ae-060577dc6380	9e0973f1-a776-411d-8a3c-358118516afa	Air up vattenflaska	https://shop.air-up.com/se/sv/bottles/twist/bottle-tritan-650ml-hot-pink	379.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 13:44:46.202369+00	\N
46b99997-8874-4d53-a302-8dd1530a14ac	9e0973f1-a776-411d-8a3c-358118516afa	Värmefilt	\N	\N	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 13:45:27.999285+00	\N
8532a32f-3195-4454-a22b-d55e1170e045	9e0973f1-a776-411d-8a3c-358118516afa	Kohl eyeliner	https://kohlbra.com/products/kohlbra-package?variant=48201586999509	485.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 13:48:39.255763+00	\N
62e22380-31fb-4af5-929e-f6970adeab4b	9e0973f1-a776-411d-8a3c-358118516afa	How to be more shrek	https://www.adlibris.com/sv/bok/how-to-be-more-shrek-9780593234068?gad_source=1&gbraid=0AAAAAD_BAOfyOb-cHLYAS1h_gcPiYE0Rj&affId=3193470&utm_source=tradedoubler&utm_medium=affiliate&utm_campaign=GoWish+SE&tduid=27a0e7ac566ab9e30c395ef1a0424c5f	146.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 13:50:02.757074+00	\N
2f764423-9b4a-4b38-b34b-30c68626bda2	9e0973f1-a776-411d-8a3c-358118516afa	Lash lift kit	https://avabeauty.se/products/lash-lift-kit	199.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 13:53:11.147036+00	\N
07c8ee91-cb3f-48f5-ae44-e67d1c945ecb	9e0973f1-a776-411d-8a3c-358118516afa	gjutjärnsgryta	\N	\N	Gärna i en annan färg än svart eller grå	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 14:10:03.693685+00	\N
bc317c5c-67bd-41a1-b4a9-69eafe1451dd	cb59656f-bf92-4823-a825-90790d04e3d3	Tradera gift card	https://www.tradera.com	\N	\N	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-10-11 13:34:44.866104+00	\N
c58030c5-c60b-457c-b7db-5c0f2de3fb8e	6fe4b461-01d6-47ad-ab5d-b7f0a247a5cb	Big bone	\N	\N	\N	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-10-11 14:11:28.054097+00	\N
ff8668ae-5869-46d6-8f8b-576b5ac83570	9e0973f1-a776-411d-8a3c-358118516afa	paintbrushes	https://amzn.eu/d/9Df5StU	239.00	Behöver ej vara just dessa, men något som ger en bred variation av borstar	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 14:21:31.884716+00	\N
84f1848f-03c0-4938-9f58-f72294aebe3f	9e0973f1-a776-411d-8a3c-358118516afa	LED lampa med klämma	https://amzn.eu/d/eXuUuVP	164.00	Behöver ej vara denna! Så länge den är stor nog att kunna lysa upp en tavla när jag målar!	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 14:26:30.459111+00	\N
13d423df-e969-4b72-8336-ebe203f5b5a8	db921861-a6e8-44fd-97d3-2b56b19e1869	Taco Cat Goat Cheese Pizza Game	https://www.adlibris.com/sv/produkt/taco-cat-goat-cheese-pizza-seendkno-47752536?article=P47752536&utm_source=google&utm_medium=cpc&utm_campaign=AR-SE%3A+Z+-+pMAX+Shopping+-+Generic+-+Spel+%26+Pussel+-+Low&gad_source=1&gad_campaignid=22633102252&gclid=Cj0KCQjwgKjHBhChARIsAPJR3xeOJt1RaXJFyEnEJlXls63NX0cGg1DXczNj6ibJ3tP4l2Elh773zeIaAmlsEALw_wcB	159.00	\N	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	2025-10-11 09:24:08.171686+00	\N
a28a9d0b-5525-4b99-a5d6-ca4c91e2067f	db921861-a6e8-44fd-97d3-2b56b19e1869	Lady million perfume	https://www.deloox.se/produkt/1021107/rabanne-lady-million-eau-de-parfum-30-ml.html?pid=1021107&pcid=1906&gad_source=1&gad_campaignid=17178717993&gclid=Cj0KCQjwgKjHBhChARIsAPJR3xcaGOTHYPhGXGWKbKVAX7Q5hlk95ABWUTCKQZvuVnscM094i2IfE6MaApWsEALw_wcB	549.00	\N	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	2025-10-11 14:35:32.152871+00	\N
593deec8-cd5a-4db0-b34f-ade663f4eab0	9e0973f1-a776-411d-8a3c-358118516afa	Cursive handwriting workbook for Adults	https://amzn.eu/d/5Nb7wvg	129.00	Behöver inte vara just denna	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 14:35:35.502025+00	\N
0d696f96-82f5-4694-8a49-f89aad444857	cb59656f-bf92-4823-a825-90790d04e3d3	Dean Koontz - Relentless	https://www.bokborsen.se/	\N	English book - second hand okay	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-10-11 10:04:00.922757+00	\N
07589175-ad4d-4ba5-993e-97d5c51c25a5	cb59656f-bf92-4823-a825-90790d04e3d3	Dan Brown - The secret of secrets	https://www.bokborsen.se/	\N	English book - second hand okay	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-10-11 10:03:36.20839+00	\N
0fcfbc6a-c51f-474e-92c2-8dbb034d00c5	9e0973f1-a776-411d-8a3c-358118516afa	Anything SHREK related	\N	\N	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 14:47:13.573136+00	\N
5dda86ed-42a8-434b-b915-4e35f67c17c4	9e0973f1-a776-411d-8a3c-358118516afa	Krydd malare	https://www.boozt.com/se/sv/house-doctor/mortar-w-pestle-hdarb-brown_32662607/228129421?localLanguage=1&volume=5&st=699&cq_src=google_ads&cq_cmp=22710376051&cq_con=176578698370&cq_term=&cq_med=pla&cq_plac=&cq_net=g&cq_pos=&cq_plt=gp&gad_source=1&gad_campaignid=22710376051&gbraid=0AAAAADf1iSi67v8F8t8U0kBNbERvYxye-&gclid=Cj0KCQjwgKjHBhChARIsAPJR3xf0DgCu9tG7gXMajgAOL9d6H4MKxtUE-miTfOM0xeVtRhX0nkWzGxAaAp2UEALw_wcB	276.00	Behöver ej vara denna, så länge de i marmor \nSecond hand OK	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 14:57:57.513433+00	\N
1d2f8288-17c2-4577-8e3c-17ab6560d6f7	9e0973f1-a776-411d-8a3c-358118516afa	Hues And Cues Nordic - Brädspel	https://www.boozt.com/se/sv/asmodee/hues-and-cues-nordic_32943913	276.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 15:03:30.875202+00	\N
b8837ff1-61cf-4011-b6f7-dfdea56d0e13	9e0973f1-a776-411d-8a3c-358118516afa	Liten radio	https://amzn.eu/d/gAUWLPI	349.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 15:09:24.203328+00	\N
b6678fe3-10f3-42fb-ae0c-5904ea2782ef	9e0973f1-a776-411d-8a3c-358118516afa	Bop it game	https://amzn.eu/d/0PAEnFC	269.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 15:12:37.980337+00	\N
ece46ef5-a3ec-4602-9b09-0dd44ce5c8cc	9e0973f1-a776-411d-8a3c-358118516afa	Cluedo brädspel	https://amzn.eu/d/dDLnQUD	357.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 15:15:18.850865+00	\N
f20c705a-0f5b-4c11-bcc0-5129daabc0ab	9e0973f1-a776-411d-8a3c-358118516afa	Catan - board game	\N	\N	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 15:04:47.734802+00	\N
cf3b7815-22ed-4472-8e82-1c67193a9bab	9e0973f1-a776-411d-8a3c-358118516afa	Wavelength board game	https://amzn.eu/d/2ni2WaA	553.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 15:01:22.583438+00	\N
1855340a-0842-4cca-a1f2-99b1f08ccfb1	9e0973f1-a776-411d-8a3c-358118516afa	glass straws	\N	\N	fun shapes and colors	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 15:20:01.089878+00	\N
66645c5a-a4d3-47c7-9c7c-a20486a59245	9e0973f1-a776-411d-8a3c-358118516afa	candle warmer	https://amzn.eu/d/iyOaCgW	465.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 15:30:58.634599+00	\N
e251b3f1-c307-4d3a-b8e6-6da248acaeaa	9e0973f1-a776-411d-8a3c-358118516afa	Brödlåda	https://amzn.eu/d/fgvZrNy	393.00	Behöver ej vara just denna	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 22:09:57.8703+00	\N
2a22e9f8-b027-4a1b-b1f7-60a2d510584f	ecb7d1e2-1fd0-404c-be6c-c56fd287b007	Chess set	https://www.clasohlson.com/se/Schack-i-trä,-29,5-x-29,5-cm/p/31-6555?utm_source=google&utm_medium=cpc&utm_campaign=SE_CO_AO_EVM_SEM_Google_pMax_Generic&utm_id=21897558452&gad_source=1&gad_campaignid=21901444282&gbraid=0AAAAADvHbiUCO_lF504YMsv39ZkcAqxGz&gclid=Cj0KCQjwgKjHBhChARIsAPJR3xcf3pwv82STFe2oNgwiSSN0PBur_8gI0vMfiKNVHCJymSCP6TGutLgaAsKUEALw_wcB	199.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 22:19:24.364729+00	\N
d0367086-b218-4431-b1e9-4717f08584f1	9e0973f1-a776-411d-8a3c-358118516afa	Grillstekpanna	https://www.ikea.com/se/sv/p/vardagen-grillpanna-gjutjaern-20560670/	359.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 22:36:03.994499+00	\N
e861436a-eb21-4f21-988e-af95621ccc8c	9e0973f1-a776-411d-8a3c-358118516afa	Stake knifes	https://www.mio.se/p/birk-grillbestick-12-delar/462037?id=M2192731	199.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 22:38:50.385678+00	\N
9a01219d-25fd-41e8-8661-d982d7cf0c81	9e0973f1-a776-411d-8a3c-358118516afa	measuring cup	https://amzn.eu/d/6oluNZW	171.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 22:45:21.048943+00	\N
af5ed29a-dbe7-46c0-abd2-183e39cb2685	ecb7d1e2-1fd0-404c-be6c-c56fd287b007	Liten dammsugare	https://amzn.eu/d/0ufwMuL	299.00	Behöver ej va denna	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 22:52:59.054339+00	\N
e8113c22-0ba2-4781-a460-626c488b8d67	b76debc4-1d61-46fb-844e-5c934cf4e797	Vas	https://royaldesign.se/nash-vas-215-cm-off-white	196.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-12 13:24:40.956909+00	\N
1b9bc1d6-5b32-48a0-a8a5-eae508af4860	9e0973f1-a776-411d-8a3c-358118516afa	Cookbook holder	https://amzn.eu/d/8e5xxTO	181.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-12 13:41:13.017791+00	\N
b4ca359a-3d01-4474-814c-b126c5696e0e	9e0973f1-a776-411d-8a3c-358118516afa	Svamp kniv	\N	\N	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-12 14:05:52.758299+00	\N
91172816-d99c-410f-8ca9-3670f39914a7	ecb7d1e2-1fd0-404c-be6c-c56fd287b007	Tool box	https://amzn.eu/d/cVxgx38	208.00	Behöver ej vara just den	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 22:15:36.894902+00	\N
3a92c3d8-878d-4ec6-b115-96a6cc8272b1	ecb7d1e2-1fd0-404c-be6c-c56fd287b007	Magnetisk verktygs armband	https://amzn.eu/d/bM7MMLD	114.00	\N	1264aa19-a50f-484c-a70e-09ec38588b89	2025-11-08 16:48:02.700652+00	\N
8dc28afa-38a0-4131-811c-d89ebecfc5c4	cb59656f-bf92-4823-a825-90790d04e3d3	HDMI splitter	https://www.amazon.se/-/en/UGREEN-Switch-Bi-Directional-Splitter-Monitor/dp/B07H7JCCKM	159.99	\N	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-11-08 20:28:06.324365+00	\N
1b291427-55b3-4334-a2c2-3cd6f2e6ebe5	92985602-082e-4d3f-9bb8-29cfb5113f2d	HDD dock	https://www.amazon.se/TooQ-TQDS-802B-dockningsstation-anslutningsbas-CLONe-funktion/dp/B00FRBQD08/ref=asc_df_B00FRBQD08?mcid=ef8ff9fd96813e8e84ba718c40844661&tag=shpngadsglesm-21&linkCode=df0&hvadid=719810828564&hvpos=&hvnetw=g&hvrand=18381142573684537112&hvpone=&hvptwo=&hvqmt=&hvdev=m&hvdvcmdl=&hvlocint=&hvlocphy=9062341&hvtargid=pla-925790243964&psc=1&language=sv_SE&gad_source=1	241.00	\N	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-11-08 21:12:20.35928+00	\N
d7fb36e6-ce72-4700-bae8-48da1937766d	92985602-082e-4d3f-9bb8-29cfb5113f2d	Raspberry pi 4 2gb/4gb	\N	\N	Second hand okay	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-11-08 21:14:27.09792+00	\N
51e32319-e3a5-4bbf-9cd0-c2c582bd6449	92985602-082e-4d3f-9bb8-29cfb5113f2d	Hornbach gift card	https://www.hornbach.se/service/presentkort/	\N	\N	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-11-08 21:25:56.816416+00	\N
c4bc9c53-90fd-4a98-b47c-ed80af41a995	db921861-a6e8-44fd-97d3-2b56b19e1869	Checkers	\N	\N	Game	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	2025-11-09 14:22:40.124001+00	\N
41657e8e-8c43-4a61-b511-01563359eeea	cb59656f-bf92-4823-a825-90790d04e3d3	Hand blender	https://www.amazon.se/Russell-Hobbs-hastigheter-pulsfunktion-27141-56/dp/B0DGQT8M6V/ref=asc_df_B0DGQT8M6V?mcid=287ed485e4db37068fe2dd14356093ae&tag=shpngadsglede-21&linkCode=df0&hvadid=724412858547&hvpos=&hvnetw=g&hvrand=9807790458193525576&hvpone=&hvptwo=&hvqmt=&hvdev=c&hvdvcmdl=&hvlocint=&hvlocphy=9062341&hvtargid=pla-2379354559386&language=sv_SE&gad_source=1&th=1	330.00	\N	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-11-11 11:55:42.295809+00	\N
2bf2a287-5fd9-47b9-b92c-25462ca8fb32	9e0973f1-a776-411d-8a3c-358118516afa	Hair bonnet silk lång	https://amzn.eu/d/6na7RsF	125.00	Önskar mig både denna och en mindre	1264aa19-a50f-484c-a70e-09ec38588b89	2025-11-11 18:08:23.756616+00	\N
6af17648-e4fc-4d56-bb1a-eb6ac21689c0	db921861-a6e8-44fd-97d3-2b56b19e1869	Hair straighter	\N	\N	\N	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	2025-10-14 17:51:15.056146+00	\N
a5f2c446-4f00-4cd3-b174-4a8f6de69c55	9e0973f1-a776-411d-8a3c-358118516afa	Hår boonet silk liten	https://www.mykitsch.se/products/cherry-print-oversized-satin-bonnet	200.00	Tyckte den va söt, behövde inte vara just den! \nÖnskar mig både denna och den långa	1264aa19-a50f-484c-a70e-09ec38588b89	2025-11-11 18:09:42.450981+00	\N
b4229424-5a86-4eed-a056-aeb013160ed7	9e0973f1-a776-411d-8a3c-358118516afa	UPS flashdrive 4-i-1	https://amzn.eu/d/fXhbDbn	349.00	Behöver ej va just denna	1264aa19-a50f-484c-a70e-09ec38588b89	2025-11-11 18:26:08.861223+00	\N
681ec7c5-7c35-4de9-81b3-463ea4e0913f	db921861-a6e8-44fd-97d3-2b56b19e1869	Loop earplugs	https://www.loopearplugs.com/products/engage	349.00	The one in the link I want specifically - clear color	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	2025-10-17 14:42:52.754121+00	\N
867ab307-8cb9-4044-8bd0-3c7c5598e111	9e0973f1-a776-411d-8a3c-358118516afa	Kokbok man fyller i själv	https://amzn.eu/d/h3DY6NO	175.00	Behöver ej vara denna	1264aa19-a50f-484c-a70e-09ec38588b89	2025-11-13 09:28:30.838837+00	\N
8baec216-37ff-4b33-bc46-06ebeb6575ca	92985602-082e-4d3f-9bb8-29cfb5113f2d	Test notification	\N	\N	\N	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-11-13 16:58:00.744727+00	\N
2b5867ee-34f0-4e26-9a09-9e0efad6d168	1689395f-5c60-4b46-9db0-67de6625080d	Chair	\N	1000.00	\N	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	2025-11-14 07:06:08.788551+00	\N
0a480b65-dc9d-45db-a439-d5f003783c45	247af0c3-7289-4a20-8bea-54ca74ac74c7	Hug	\N	5000.00	\N	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	2025-11-14 07:09:11.665292+00	\N
413f4fc3-35da-48eb-be01-5a911ead2967	db921861-a6e8-44fd-97d3-2b56b19e1869	The perils of Lady Catherine De Bourgh by Claudia Gray	\N	\N	Book	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	2025-10-18 11:05:21.892532+00	\N
411be2f2-6774-4163-b5ec-eee5a19c6f72	4ed8df20-1eac-4a6a-ad34-282483043e43	Sub	\N	43.00	\N	962f043b-340e-4f3f-9d45-2f3816580648	2025-10-20 05:59:55.046448+00	\N
cb56c3f2-a91c-4855-8986-c8445ae0ecd5	4ed8df20-1eac-4a6a-ad34-282483043e43	Jsib	\N	649.00	\N	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-10-20 06:00:57.842668+00	\N
042804bd-d83a-45ec-ab1b-04a1bf1ca0b9	cb59656f-bf92-4823-a825-90790d04e3d3	Magnifying lamp	https://www.amazon.se/Ricyea-LED-lupplampa-ljusstyrkeniv%C3%A5er-skrivbordslampa-f%C3%B6rstoringsglas/dp/B0CR5TLF6T/ref=cm_cr_arp_d_product_top?ie=UTF8&th=1	249.00	\N	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-10-23 04:44:00.249121+00	\N
5621d9c3-5654-448f-9311-6ac1e1cdb90e	9e0973f1-a776-411d-8a3c-358118516afa	Vattenkokare	https://www.clasohlson.com/se/Vattenkokare-i-plast,-1,7-liter/p/44-4973	199.00	Den beigea	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 16:08:26.22083+00	\N
dce7c234-3dc4-4cdb-b4a3-be7c6fe6dd49	2fdc37d9-0dee-4fb5-89e3-35581fe4f2cf	Doftljus in a jars	\N	\N	\N	76657cf1-b6ae-4956-808e-0cce2b6b786e	2025-11-02 17:59:03.068589+00	\N
d29de562-1b76-4100-96d6-f34e8ab05700	2fdc37d9-0dee-4fb5-89e3-35581fe4f2cf	Mary Kay ansiktsmask man kan sova med	\N	\N	\N	76657cf1-b6ae-4956-808e-0cce2b6b786e	2025-11-02 18:22:23.640814+00	\N
55893e7a-68af-40b4-a1b4-1283f8a5c581	2fdc37d9-0dee-4fb5-89e3-35581fe4f2cf	Set of small parfyms	https://www.google.com/aclk?sa=L&ai=DChsSEwi10JOUjdSQAxVAVJEFHfrXDAMYACICCAEQGRoCbHI&co=1&gclid=EAIaIQobChMItdCTlI3UkAMVQFSRBR361wwDEAQYBiABEgJJIfD_BwE&cit=EAIaIQobChMItdCTlI3UkAMVQFSRBR361wwDEAQYBiABEgJJIfD_BwE&ei=wqMHaZiFE9SP1fIPves1&cce=2&sig=AOD64_1yB3b2RC4YSiO5brK-QVWmNzmSoQ&ctype=5&q=&sqi=2&ved=2ahUKEwiY7o6UjdSQAxXUR1UIHb11DQAQwg8oAHoECAgQLQ&adurl=	\N	\N	76657cf1-b6ae-4956-808e-0cce2b6b786e	2025-11-02 18:06:25.434658+00	\N
f4881d4b-5c49-4025-aed3-de3d3cd107b6	2fdc37d9-0dee-4fb5-89e3-35581fe4f2cf	4 kg hantlar	\N	\N	\N	76657cf1-b6ae-4956-808e-0cce2b6b786e	2025-11-02 20:48:44.926875+00	\N
569beb41-b7ec-421b-a712-094e195e2928	2fdc37d9-0dee-4fb5-89e3-35581fe4f2cf	Dekorationstråd	https://www.skapamer.se/metalltrad-8-farger-0-5-mm-50-m?aref=ref-adwords_agid-160678819881_cid-20891130169_mt-_kw-_pl-_dv-m&gad_source=1&gclid=EAIaIQobChMI-9mDuovUkAMVW0GRBR2ldxM1EAQYESABEgIe_PD_BwE	\N	\N	76657cf1-b6ae-4956-808e-0cce2b6b786e	2025-11-02 18:27:52.954346+00	\N
4b55089b-7bae-4d4b-aaa0-52749541ad9c	a6979636-d39a-4bbd-a1b9-928babb92e7a	Disposable camera	https://amzn.eu/d/5C0etdc	\N	\N	bd7a30c2-5513-4896-8db8-0771ce6873f8	2025-11-02 23:22:57.327032+00	\N
1e72fd24-4755-4e9e-b0bb-7bfbb2d9c02c	a6979636-d39a-4bbd-a1b9-928babb92e7a	Frying pan	https://amzn.eu/d/hr2rCe0	\N	Want a non-toxic, PTFE & PFOA free, frying pan	bd7a30c2-5513-4896-8db8-0771ce6873f8	2025-11-02 23:31:33.251036+00	\N
3012cd9c-bbdc-40b2-b7c1-2c9e360cbe3d	a6979636-d39a-4bbd-a1b9-928babb92e7a	Sun, moon and stars perfume	https://amzn.eu/d/dYD7LJz	\N	\N	bd7a30c2-5513-4896-8db8-0771ce6873f8	2025-11-02 23:33:19.952248+00	\N
aacf8834-13c1-46f9-a193-8f473fed5e1b	a6979636-d39a-4bbd-a1b9-928babb92e7a	3L pressure cooker	\N	\N	\N	bd7a30c2-5513-4896-8db8-0771ce6873f8	2025-11-02 23:47:21.012797+00	\N
c9598198-41a0-409a-b1e9-1070d625b662	a6979636-d39a-4bbd-a1b9-928babb92e7a	Heatless curlers	https://amzn.eu/d/fXAP9KT	\N	\N	bd7a30c2-5513-4896-8db8-0771ce6873f8	2025-11-02 23:50:36.285039+00	\N
9bdb4a97-5e1f-4ba6-851e-3506092eddbe	a6979636-d39a-4bbd-a1b9-928babb92e7a	Potatispress	\N	\N	Stainless steal, would like something that could last, possible good thrift find	bd7a30c2-5513-4896-8db8-0771ce6873f8	2025-11-04 10:42:25.917481+00	\N
49782fcc-4ad6-45f3-a12e-7ffe6f7163f7	c3bc37a0-92c6-415a-819c-680d00e44a59	Massaging foot bath	\N	\N	\N	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-11-07 08:30:07.865764+00	\N
c7609500-f8d5-454d-bc64-56fc1ab51f85	c3bc37a0-92c6-415a-819c-680d00e44a59	Karaoke speaker	\N	\N	\N	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-11-07 12:03:07.414995+00	\N
\.


--
-- Data for Name: list_exclusions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.list_exclusions (list_id, user_id, created_at) FROM stdin;
ecb7d1e2-1fd0-404c-be6c-c56fd287b007	c88ebcdb-8a4c-4839-ae12-78ad7e6e2c72	2025-10-11 22:12:34.723034+00
c3bc37a0-92c6-415a-819c-680d00e44a59	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	2025-11-07 08:29:24.401376+00
\.


--
-- Data for Name: list_recipients; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.list_recipients (list_id, user_id, can_view, recipient_email, id) FROM stdin;
ecb7d1e2-1fd0-404c-be6c-c56fd287b007	c88ebcdb-8a4c-4839-ae12-78ad7e6e2c72	t	\N	3a46020c-42a1-4ff9-b99e-596b432e1f1c
4ed8df20-1eac-4a6a-ad34-282483043e43	962f043b-340e-4f3f-9d45-2f3816580648	t	\N	8d7a45e7-d7dd-4370-a3a5-e4ed821f8bc6
a6979636-d39a-4bbd-a1b9-928babb92e7a	bd7a30c2-5513-4896-8db8-0771ce6873f8	t	\N	1492254b-1ed1-4aa6-93c1-648233a3ab44
2fdc37d9-0dee-4fb5-89e3-35581fe4f2cf	76657cf1-b6ae-4956-808e-0cce2b6b786e	t	\N	60ade97d-4d77-41a6-a7c7-a8f769ff9b2f
c3bc37a0-92c6-415a-819c-680d00e44a59	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	t	\N	ac2c4557-7d33-4d3a-8489-63aeea148315
92985602-082e-4d3f-9bb8-29cfb5113f2d	0881f0e0-4254-4f76-b487-99b40dd08f10	t	\N	708d9de3-bd95-4976-b3ac-54bb8e5fe89e
1689395f-5c60-4b46-9db0-67de6625080d	0881f0e0-4254-4f76-b487-99b40dd08f10	t	\N	9157330f-0dca-4448-ba86-e374e7dd35fd
247af0c3-7289-4a20-8bea-54ca74ac74c7	0881f0e0-4254-4f76-b487-99b40dd08f10	t	\N	d7650e5a-b1c2-44ef-a496-8a9f107f9151
b76debc4-1d61-46fb-844e-5c934cf4e797	1264aa19-a50f-484c-a70e-09ec38588b89	t	\N	d2a884f1-67c0-4359-882b-717b537a69f3
cb59656f-bf92-4823-a825-90790d04e3d3	0881f0e0-4254-4f76-b487-99b40dd08f10	t	\N	143db408-1591-438f-bdf7-c5b764f3f2fa
db921861-a6e8-44fd-97d3-2b56b19e1869	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	t	\N	2184de62-ba25-4141-aa4d-a0756a01b910
34cb89c8-3501-40a0-8d7e-561c288499b0	be884d3f-71f2-484b-9a19-5e3097e7d74e	t	\N	13b9b053-da3b-4fa0-8b5b-e9824a42517f
9e0973f1-a776-411d-8a3c-358118516afa	1264aa19-a50f-484c-a70e-09ec38588b89	t	\N	36b89469-f37b-4bcd-a641-e07dc2e47e20
\.


--
-- Data for Name: list_viewers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.list_viewers (list_id, user_id) FROM stdin;
\.


--
-- Data for Name: lists; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.lists (id, event_id, name, created_by, created_at, visibility, custom_recipient_name, random_assignment_enabled, random_assignment_mode, random_assignment_executed_at, random_receiver_assignment_enabled, for_everyone) FROM stdin;
1689395f-5c60-4b46-9db0-67de6625080d	743e2f40-4470-47d6-ad5c-7ab10a663788	Test notification	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-11-14 06:59:11.384339+00	event	\N	f	\N	\N	f	f
247af0c3-7289-4a20-8bea-54ca74ac74c7	743e2f40-4470-47d6-ad5c-7ab10a663788	What Chris needs	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	2025-11-14 07:06:49.75001+00	event	\N	f	\N	\N	f	f
b76debc4-1d61-46fb-844e-5c934cf4e797	b40aca00-c0fd-4804-bfaa-893d9111d770	Wish list	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 09:02:23.463962+00	event	\N	f	\N	\N	f	f
cb59656f-bf92-4823-a825-90790d04e3d3	7a98e60a-60a2-4687-8423-abddfc34a80f	Chris' list	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-10-11 09:19:06.567607+00	event	\N	f	\N	\N	f	f
db921861-a6e8-44fd-97d3-2b56b19e1869	7a98e60a-60a2-4687-8423-abddfc34a80f	Sarah's wishlist	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	2025-10-11 09:19:19.147673+00	event	\N	f	\N	\N	f	f
34cb89c8-3501-40a0-8d7e-561c288499b0	7a98e60a-60a2-4687-8423-abddfc34a80f	Pappa’s list	be884d3f-71f2-484b-9a19-5e3097e7d74e	2025-10-11 09:31:51.786004+00	event	\N	f	\N	\N	f	f
6fe4b461-01d6-47ad-ab5d-b7f0a247a5cb	7a98e60a-60a2-4687-8423-abddfc34a80f	Buddy's list	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-10-11 09:32:09.520097+00	event	Buddy	f	\N	\N	f	f
9e0973f1-a776-411d-8a3c-358118516afa	7a98e60a-60a2-4687-8423-abddfc34a80f	Emma🤷🏻‍♀️s wishlist	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 09:32:26.833375+00	event	\N	f	\N	\N	f	f
28b0a6b7-28bb-4d47-ba84-b2df44a1948c	7a98e60a-60a2-4687-8423-abddfc34a80f	Cats list	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-10-11 14:38:31.301322+00	event	Viggo & Jussi	f	\N	\N	f	f
ecb7d1e2-1fd0-404c-be6c-c56fd287b007	7a98e60a-60a2-4687-8423-abddfc34a80f	Tomas secret	1264aa19-a50f-484c-a70e-09ec38588b89	2025-10-11 22:12:34.608726+00	event	\N	f	\N	\N	f	f
3c1d7339-554d-4977-9100-830a9a43515a	78617fe1-b69a-4d45-9457-d124fb6da05b	Claim	962f043b-340e-4f3f-9d45-2f3816580648	2025-10-12 14:13:56.993419+00	event	User	f	\N	\N	f	f
3ed15bc8-7fcc-4ade-9e71-53b2eb97822b	78617fe1-b69a-4d45-9457-d124fb6da05b	Test 2	962f043b-340e-4f3f-9d45-2f3816580648	2025-10-12 15:55:20.689637+00	event	Test	f	\N	\N	f	f
4ed8df20-1eac-4a6a-ad34-282483043e43	78617fe1-b69a-4d45-9457-d124fb6da05b	Random recipient test	962f043b-340e-4f3f-9d45-2f3816580648	2025-10-20 05:34:44.359808+00	event	\N	t	one_per_member	2025-10-20 06:00:12.877849+00	t	t
a6979636-d39a-4bbd-a1b9-928babb92e7a	7a98e60a-60a2-4687-8423-abddfc34a80f	Thyra's list	bd7a30c2-5513-4896-8db8-0771ce6873f8	2025-11-02 09:58:06.2052+00	event	\N	f	\N	\N	f	f
c3bc37a0-92c6-415a-819c-680d00e44a59	7a98e60a-60a2-4687-8423-abddfc34a80f	Sarah's secret list	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-11-07 08:29:24.289592+00	event	\N	f	\N	\N	f	f
92985602-082e-4d3f-9bb8-29cfb5113f2d	743e2f40-4470-47d6-ad5c-7ab10a663788	Birthday list	0881f0e0-4254-4f76-b487-99b40dd08f10	2025-11-08 21:11:53.502549+00	event	\N	f	\N	\N	f	f
2fdc37d9-0dee-4fb5-89e3-35581fe4f2cf	7a98e60a-60a2-4687-8423-abddfc34a80f	Mamma	76657cf1-b6ae-4956-808e-0cce2b6b786e	2025-11-02 17:57:08.756002+00	event	\N	f	\N	\N	f	f
\.


--
-- Data for Name: notification_queue; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notification_queue (id, user_id, title, body, data, sent, created_at) FROM stdin;
f5084561-042b-4d23-929d-cc18700452f1	0881f0e0-4254-4f76-b487-99b40dd08f10	Emma Molgaard added an item to Emma🤷🏻‍♀️s wishlist		{"item_id": "867ab307-8cb9-4044-8bd0-3c7c5598e111", "list_id": "9e0973f1-a776-411d-8a3c-358118516afa", "event_id": "7a98e60a-60a2-4687-8423-abddfc34a80f", "item_name": "Kokbok man fyller i själv", "list_name": "Emma🤷🏻‍♀️s wishlist", "event_title": "Christmas", "creator_name": "Emma Molgaard"}	t	2025-11-13 09:28:30.838837+00
5cf43f2e-5289-40de-a0fc-d73243812e25	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	Emma Molgaard added an item to Emma🤷🏻‍♀️s wishlist		{"item_id": "867ab307-8cb9-4044-8bd0-3c7c5598e111", "list_id": "9e0973f1-a776-411d-8a3c-358118516afa", "event_id": "7a98e60a-60a2-4687-8423-abddfc34a80f", "item_name": "Kokbok man fyller i själv", "list_name": "Emma🤷🏻‍♀️s wishlist", "event_title": "Christmas", "creator_name": "Emma Molgaard"}	t	2025-11-13 09:28:30.838837+00
9df3752c-8b6e-4b7f-b2de-c045dfb7173d	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	Chris Axt created a new list: Test notification		{"list_id": "1689395f-5c60-4b46-9db0-67de6625080d", "event_id": "743e2f40-4470-47d6-ad5c-7ab10a663788", "list_name": "Test notification", "event_title": "Chris' birthday", "creator_name": "Chris Axt"}	t	2025-11-14 06:59:11.384339+00
93105348-2fc1-4e27-9733-03d3e0a0bb9a	0881f0e0-4254-4f76-b487-99b40dd08f10	Sarah Axt created a new list: What Chris needs		{"list_id": "247af0c3-7289-4a20-8bea-54ca74ac74c7", "event_id": "743e2f40-4470-47d6-ad5c-7ab10a663788", "list_name": "What Chris needs", "event_title": "Chris' birthday", "creator_name": "Sarah Axt"}	t	2025-11-14 07:06:49.75001+00
ce1c8e27-06c0-4cd0-8906-e39dfb9ddd84	0881f0e0-4254-4f76-b487-99b40dd08f10	Sarah Axt claimed Hug from What Chris needs		{"item_id": "0a480b65-dc9d-45db-a439-d5f003783c45", "list_id": "247af0c3-7289-4a20-8bea-54ca74ac74c7", "claim_id": "9ac002eb-d90a-4f71-8564-3dc6103fe6da", "event_id": "743e2f40-4470-47d6-ad5c-7ab10a663788", "item_name": "Hug", "list_name": "What Chris needs", "event_title": "Chris' birthday", "claimer_name": "Sarah Axt"}	t	2025-11-14 07:28:08.497521+00
587cdebb-05ee-4c24-b6c8-9e47b6e1bd87	0881f0e0-4254-4f76-b487-99b40dd08f10	Your Daily GiftCircles Summary	1 new claim today.	{"type": "digest", "summary": [{"counts": {"new_claim": 1}, "event_title": "Christmas"}], "frequency": "daily", "time_period": "today"}	t	2025-11-16 08:38:52.462532+00
adaecbe4-14c1-412c-ba27-258115b8c828	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	Chris Axt added an item to Birthday list		{"item_id": "8baec216-37ff-4b33-bc46-06ebeb6575ca", "list_id": "92985602-082e-4d3f-9bb8-29cfb5113f2d", "event_id": "743e2f40-4470-47d6-ad5c-7ab10a663788", "item_name": "Test notification", "list_name": "Birthday list", "event_title": "Chris' birthday", "creator_name": "Chris Axt"}	t	2025-11-13 16:58:00.744727+00
6938b1cd-d07d-4b77-9731-36a0589aaac7	0881f0e0-4254-4f76-b487-99b40dd08f10	Sarah Axt added an item to Test notification		{"item_id": "2b5867ee-34f0-4e26-9a09-9e0efad6d168", "list_id": "1689395f-5c60-4b46-9db0-67de6625080d", "event_id": "743e2f40-4470-47d6-ad5c-7ab10a663788", "item_name": "Chair", "list_name": "Test notification", "event_title": "Chris' birthday", "creator_name": "Sarah Axt"}	t	2025-11-14 07:06:08.788551+00
0b1841eb-e11e-4ff6-9ba2-b606054b68cd	0881f0e0-4254-4f76-b487-99b40dd08f10	Sarah Axt added an item to What Chris needs		{"item_id": "0a480b65-dc9d-45db-a439-d5f003783c45", "list_id": "247af0c3-7289-4a20-8bea-54ca74ac74c7", "event_id": "743e2f40-4470-47d6-ad5c-7ab10a663788", "item_name": "Hug", "list_name": "What Chris needs", "event_title": "Chris' birthday", "creator_name": "Sarah Axt"}	t	2025-11-14 07:09:11.665292+00
7a7403d2-42f3-48c7-b6c3-86dac5f366cb	0881f0e0-4254-4f76-b487-99b40dd08f10	Your Daily GiftCircles Summary	1 new claim today.	{"type": "digest", "summary": [{"counts": {"new_claim": 1}, "event_title": "Christmas"}], "frequency": "daily", "time_period": "today"}	t	2025-11-16 08:37:26.308617+00
e79a1590-567c-4f8e-b6ca-c5fdd10c5989	0881f0e0-4254-4f76-b487-99b40dd08f10	Your Daily GiftCircles Summary	Christmas-Tomas secret: 1 new claim	{"type": "digest", "summary": [{"activities": [{"count": 1, "list_name": "Tomas secret", "activity_type": "new_claim"}], "event_title": "Christmas"}], "frequency": "daily"}	t	2025-11-16 08:52:31.286785+00
6f65cc93-0e38-47a9-b40b-7367e488ece6	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	Your Daily GiftCircles Summary	Christmas-Thyra's list: 2 new claims\nChristmas-Thyra's list: 2 unclaims	{"type": "digest", "summary": [{"activities": [{"count": 2, "list_name": "Thyra's list", "activity_type": "new_claim"}, {"count": 2, "list_name": "Thyra's list", "activity_type": "unclaim"}], "event_title": "Christmas"}], "frequency": "daily"}	t	2025-11-16 08:52:31.286785+00
\.


--
-- Data for Name: orphaned_lists; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.orphaned_lists (id, list_id, event_id, excluded_user_id, marked_at, delete_at, created_at) FROM stdin;
\.


--
-- Data for Name: profiles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.profiles (id, display_name, avatar_url, created_at, onboarding_done, onboarding_at, plan, pro_until, reminder_days, currency, notification_digest_enabled, digest_time_hour, digest_frequency, digest_day_of_week, last_support_screen_shown, timezone, manual_pro, instant_notifications_enabled) FROM stdin;
f56d77a9-9b57-40fa-a9d2-5b2dea219617	Jane	\N	2025-11-12 14:51:00.75186+00	t	2025-11-12 14:51:18.827256+00	free	\N	\N	USD	t	9	daily	1	2025-11-12 14:51:10.725+00	Europe/Stockholm	t	f
962f043b-340e-4f3f-9d45-2f3816580648	Chris Swe	\N	2025-10-05 12:06:00.912581+00	t	2025-11-10 09:11:08.146199+00	free	\N	\N	SEK	f	9	daily	1	2025-11-10 09:20:38.938+00	Europe/Stockholm	f	f
0881f0e0-4254-4f76-b487-99b40dd08f10	Chris Axt	\N	2025-09-20 10:38:33.807183+00	t	2025-11-12 07:08:50.579186+00	free	\N	14	SEK	t	9	daily	\N	2025-11-12 07:08:42.513+00	Europe/Stockholm	t	f
00000000-0000-4000-8000-000000000001	alice	\N	2025-10-02 12:19:30.359098+00	f	\N	free	\N	\N	USD	f	9	daily	1	\N	UTC	f	f
00000000-0000-4000-8000-000000000002	bob	\N	2025-10-02 12:19:30.359098+00	f	\N	free	\N	\N	USD	f	9	daily	1	\N	UTC	f	f
00000000-0000-4000-8000-000000000003	carl	\N	2025-10-02 12:19:30.359098+00	f	\N	free	\N	\N	USD	f	9	daily	1	\N	UTC	f	f
1264aa19-a50f-484c-a70e-09ec38588b89	Emma Molgaard	\N	2025-10-11 08:56:41.21296+00	t	2025-10-11 08:58:47.872886+00	free	\N	\N	SEK	f	9	daily	1	\N	Europe/Stockholm	f	f
be884d3f-71f2-484b-9a19-5e3097e7d74e	Douglas Molgaard	\N	2025-10-11 09:10:42.754333+00	t	2025-10-11 09:12:12.42562+00	free	\N	\N	USD	f	9	daily	1	\N	UTC	f	f
76657cf1-b6ae-4956-808e-0cce2b6b786e	Anna Molgaard	\N	2025-10-11 09:20:02.551435+00	t	2025-10-11 09:20:21.853348+00	free	\N	\N	USD	f	9	daily	1	\N	UTC	f	f
c88ebcdb-8a4c-4839-ae12-78ad7e6e2c72	Tomas Qerimaj	\N	2025-10-11 09:49:14.507996+00	t	2025-10-11 09:49:19.948544+00	free	\N	\N	USD	f	9	daily	1	\N	UTC	f	f
77125c99-44be-4be8-975f-86ffb849f6bd	Monique Axt	\N	2025-10-02 16:41:30.778025+00	t	2025-10-09 16:12:58.563208+00	free	\N	\N	USD	f	9	daily	1	\N	UTC	f	f
bd7a30c2-5513-4896-8db8-0771ce6873f8	Thyra	\N	2025-11-02 09:45:35.414574+00	t	2025-11-02 09:45:52.565497+00	free	\N	\N	GBP	f	9	daily	1	\N	UTC	f	f
dcffc6d0-b7bf-416a-9f6d-e91f23adf918	Sarah Axt	\N	2025-09-20 06:26:33.93472+00	t	2025-09-20 06:31:13.054609+00	free	\N	\N	SEK	t	9	daily	1	2025-11-13 19:13:04.666+00	Europe/Stockholm	f	f
60962cdf-762c-4bcd-8b2f-526a98b03b36	Gianmarco Iachella	\N	2025-11-13 19:35:57.713678+00	t	2025-11-13 19:37:24.486702+00	free	\N	\N	USD	f	9	daily	1	2025-11-13 19:36:17.297+00	Europe/Stockholm	t	f
4a2756b6-1c32-4cd6-ad11-9a1f2eaa988b	Reviewer	\N	2025-11-12 11:08:44.398475+00	t	2025-11-12 11:09:14.278187+00	free	\N	1	USD	f	9	daily	1	2025-11-12 11:08:55.484+00	Europe/Stockholm	t	f
46d90106-695f-47d1-b291-430152293733	crawlerrobo	\N	2025-11-11 09:34:44.040326+00	f	\N	free	\N	\N	USD	f	9	daily	1	\N	UTC	f	f
\.


--
-- Data for Name: push_tokens; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.push_tokens (id, user_id, token, platform, created_at, updated_at) FROM stdin;
6f3047dc-00cd-466f-aca1-901f7e0bc997	0881f0e0-4254-4f76-b487-99b40dd08f10	ExponentPushToken[9IIgvjH6yLXaSY8-jbQsV9]	android	2025-10-05 14:58:25.49461+00	2025-10-05 14:58:25.49461+00
3b173191-5e7b-4098-a389-5887fe4e1d09	0881f0e0-4254-4f76-b487-99b40dd08f10	ExponentPushToken[Jh8veFEfTUa9ezWt3X1PLB]	android	2025-10-05 19:30:58.677153+00	2025-10-05 19:30:58.677153+00
62aa67dc-283a-4364-87bc-87432f2910f4	0881f0e0-4254-4f76-b487-99b40dd08f10	ExponentPushToken[8fFvETJ-2X2_cNxvU6VCUt]	android	2025-10-05 19:50:44.261375+00	2025-10-05 19:50:44.261375+00
89d6adc2-99c0-4275-bbf0-5fa97ace555f	0881f0e0-4254-4f76-b487-99b40dd08f10	ExponentPushToken[N5kX9CAVmhGJA1Yfp2o6ni]	android	2025-10-06 10:33:38.962355+00	2025-10-06 10:33:38.962355+00
8a89e486-9034-44ed-81a4-6e6c5ae4ab91	0881f0e0-4254-4f76-b487-99b40dd08f10	ExponentPushToken[PL0TkxPtdGGwguCXh-GTb7]	android	2025-10-06 12:50:20.315938+00	2025-10-06 12:50:20.315938+00
545aacb2-b83d-4083-98cd-3c2675e6527f	962f043b-340e-4f3f-9d45-2f3816580648	ExponentPushToken[7gDr3QFH1ZEvwgnMFR5nTV]	ios	2025-10-07 16:13:45.250297+00	2025-10-07 16:13:45.250297+00
645f050d-619d-428a-a584-ae7370d9b0cd	962f043b-340e-4f3f-9d45-2f3816580648	c56a3ec36acef45b8e66551d6403d214a8d3a7460c22dbcde355f57fb6395be6	ios	2025-10-09 14:01:09.512434+00	2025-10-09 14:01:09.512434+00
29f998f4-3e54-4e75-ada6-18743fc0419f	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	ExponentPushToken[jFzWWdFibiIJInyCals6By]	android	2025-10-10 17:20:42.152637+00	2025-10-10 17:20:42.152637+00
5a762d2e-8f78-4fd2-804b-f6f9c5a8ca77	0881f0e0-4254-4f76-b487-99b40dd08f10	ExponentPushToken[ulvmfwLt8uMIKzD_XqwL83]	android	2025-11-12 08:30:12.637643+00	2025-11-12 08:30:12.637643+00
97c4ea41-a20f-465b-ae2e-0f89941d06b4	f56d77a9-9b57-40fa-a9d2-5b2dea219617	ExponentPushToken[ryNMr9PQyoDRKDWSdeOEne]	android	2025-11-13 06:43:17.908594+00	2025-11-13 06:43:17.908594+00
32f95f49-9554-4f43-915e-60190d070063	f56d77a9-9b57-40fa-a9d2-5b2dea219617	ExponentPushToken[5j-NYnK8bZVrUEIHKDZ_N6]	android	2025-11-13 07:57:20.797729+00	2025-11-13 07:57:20.797729+00
b061397f-6c19-4519-b159-ab0d493a45aa	0881f0e0-4254-4f76-b487-99b40dd08f10	ExponentPushToken[eCQDqgLWf92HtEA_746UAE]	android	2025-11-13 14:20:08.051362+00	2025-11-13 14:20:08.051362+00
64fad2ef-4b71-41e3-b055-8adda79d141d	dcffc6d0-b7bf-416a-9f6d-e91f23adf918	ExponentPushToken[VHJb4WMaYZ3EoCpl4keLF6]	android	2025-11-13 19:14:15.743322+00	2025-11-13 19:14:15.743322+00
\.


--
-- Data for Name: rate_limit_tracking; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.rate_limit_tracking (user_id, action, window_start, request_count) FROM stdin;
\.


--
-- Data for Name: security_audit_log; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.security_audit_log (id, user_id, action, resource_type, resource_id, ip_address, user_agent, success, error_message, metadata, created_at) FROM stdin;
30e3d5aa-ede4-43d9-a996-b550aee8663f	0881f0e0-4254-4f76-b487-99b40dd08f10	delete_item	item	9187ea5f-dec4-49c8-9666-d2715eb4b1e3	\N	\N	t	\N	\N	2025-10-23 04:43:24.991666+00
e1f03b0c-403b-4244-84c2-1f36ebf133dc	76657cf1-b6ae-4956-808e-0cce2b6b786e	delete_item	item	2d03c0f0-6c6f-4710-9fc6-6e2d854bca9d	\N	\N	t	\N	\N	2025-11-02 18:21:29.595509+00
921aa2dc-c907-43fa-bea7-5edfe4f30c4c	0881f0e0-4254-4f76-b487-99b40dd08f10	delete_list	list	81882ae5-5113-486f-b246-b877c8837d5c	\N	\N	t	\N	\N	2025-11-07 13:12:35.547044+00
80378f84-3733-4a0e-ab98-9bb7a820b408	0881f0e0-4254-4f76-b487-99b40dd08f10	delete_list	list	3e12f5ef-f1a8-40ef-8649-6351c0b5ca1c	\N	\N	t	\N	\N	2025-11-07 13:12:44.163771+00
ef05cae9-9b0a-4ef1-aab3-a9fcfd51c3df	4a2756b6-1c32-4cd6-ad11-9a1f2eaa988b	delete_item	item	d3ef1753-1943-4ea0-93d6-37ad4d86fbcf	\N	\N	t	\N	\N	2025-11-12 15:12:49.606518+00
\.


--
-- Data for Name: sent_reminders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.sent_reminders (id, user_id, claim_id, event_id, sent_at) FROM stdin;
\.


--
-- Data for Name: user_plans; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_plans (user_id, pro_until, created_at, updated_at, note) FROM stdin;
\.


--
-- Name: claim_split_requests claim_split_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_split_requests
    ADD CONSTRAINT claim_split_requests_pkey PRIMARY KEY (id);


--
-- Name: claims claims_item_id_claimer_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claims
    ADD CONSTRAINT claims_item_id_claimer_id_key UNIQUE (item_id, claimer_id);


--
-- Name: claims claims_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claims
    ADD CONSTRAINT claims_pkey PRIMARY KEY (id);


--
-- Name: daily_activity_log daily_activity_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_activity_log
    ADD CONSTRAINT daily_activity_log_pkey PRIMARY KEY (id);


--
-- Name: event_invites event_invites_event_id_invitee_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_invites
    ADD CONSTRAINT event_invites_event_id_invitee_email_key UNIQUE (event_id, invitee_email);


--
-- Name: event_invites event_invites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_invites
    ADD CONSTRAINT event_invites_pkey PRIMARY KEY (id);


--
-- Name: event_member_stats event_member_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_member_stats
    ADD CONSTRAINT event_member_stats_pkey PRIMARY KEY (event_id, user_id);


--
-- Name: event_members event_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_members
    ADD CONSTRAINT event_members_pkey PRIMARY KEY (event_id, user_id);


--
-- Name: events events_join_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_join_code_key UNIQUE (join_code);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: items items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_pkey PRIMARY KEY (id);


--
-- Name: list_exclusions list_exclusions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_exclusions
    ADD CONSTRAINT list_exclusions_pkey PRIMARY KEY (list_id, user_id);


--
-- Name: list_recipients list_recipients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_recipients
    ADD CONSTRAINT list_recipients_pkey PRIMARY KEY (id);


--
-- Name: list_viewers list_viewers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_viewers
    ADD CONSTRAINT list_viewers_pkey PRIMARY KEY (list_id, user_id);


--
-- Name: lists lists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lists
    ADD CONSTRAINT lists_pkey PRIMARY KEY (id);


--
-- Name: notification_queue notification_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_queue
    ADD CONSTRAINT notification_queue_pkey PRIMARY KEY (id);


--
-- Name: orphaned_lists orphaned_lists_list_id_excluded_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orphaned_lists
    ADD CONSTRAINT orphaned_lists_list_id_excluded_user_id_key UNIQUE (list_id, excluded_user_id);


--
-- Name: orphaned_lists orphaned_lists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orphaned_lists
    ADD CONSTRAINT orphaned_lists_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: push_tokens push_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_tokens
    ADD CONSTRAINT push_tokens_pkey PRIMARY KEY (id);


--
-- Name: push_tokens push_tokens_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_tokens
    ADD CONSTRAINT push_tokens_token_key UNIQUE (token);


--
-- Name: rate_limit_tracking rate_limit_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_limit_tracking
    ADD CONSTRAINT rate_limit_tracking_pkey PRIMARY KEY (user_id, action, window_start);


--
-- Name: security_audit_log security_audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.security_audit_log
    ADD CONSTRAINT security_audit_log_pkey PRIMARY KEY (id);


--
-- Name: sent_reminders sent_reminders_claim_id_event_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sent_reminders
    ADD CONSTRAINT sent_reminders_claim_id_event_id_key UNIQUE (claim_id, event_id);


--
-- Name: sent_reminders sent_reminders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sent_reminders
    ADD CONSTRAINT sent_reminders_pkey PRIMARY KEY (id);


--
-- Name: user_plans user_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_plans
    ADD CONSTRAINT user_plans_pkey PRIMARY KEY (user_id);


--
-- Name: claim_split_requests_pending_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX claim_split_requests_pending_unique ON public.claim_split_requests USING btree (item_id, requester_id, original_claimer_id) WHERE (status = 'pending'::text);


--
-- Name: idx_claim_split_requests_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claim_split_requests_item ON public.claim_split_requests USING btree (item_id);


--
-- Name: idx_claim_split_requests_original_claimer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claim_split_requests_original_claimer ON public.claim_split_requests USING btree (original_claimer_id) WHERE (status = 'pending'::text);


--
-- Name: idx_claims_assigned_to; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claims_assigned_to ON public.claims USING btree (assigned_to);


--
-- Name: idx_claims_assigned_to_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claims_assigned_to_item ON public.claims USING btree (assigned_to, item_id) WHERE (assigned_to IS NOT NULL);


--
-- Name: INDEX idx_claims_assigned_to_item; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_claims_assigned_to_item IS 'Composite index for random assignment queries checking who is assigned to items.';


--
-- Name: idx_claims_claimer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claims_claimer_id ON public.claims USING btree (claimer_id);


--
-- Name: idx_claims_claimer_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claims_claimer_item ON public.claims USING btree (claimer_id, item_id);


--
-- Name: idx_claims_claimer_purchased; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claims_claimer_purchased ON public.claims USING btree (claimer_id, purchased);


--
-- Name: INDEX idx_claims_claimer_purchased; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_claims_claimer_purchased IS 'Composite index for calculating unpurchased claims per user.';


--
-- Name: idx_claims_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claims_item_id ON public.claims USING btree (item_id);


--
-- Name: idx_daily_activity_log_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_daily_activity_log_event ON public.daily_activity_log USING btree (event_id, created_at);


--
-- Name: idx_daily_activity_log_user_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_daily_activity_log_user_date ON public.daily_activity_log USING btree (user_id, created_at);


--
-- Name: idx_event_invites_email_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_invites_email_status ON public.event_invites USING btree (invitee_email, status) WHERE (status = 'pending'::text);


--
-- Name: INDEX idx_event_invites_email_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_event_invites_email_status IS 'Partial index for finding pending invites by email.';


--
-- Name: idx_event_invites_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_invites_event_id ON public.event_invites USING btree (event_id);


--
-- Name: idx_event_invites_invitee_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_invites_invitee_email ON public.event_invites USING btree (invitee_email);


--
-- Name: idx_event_invites_invitee_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_invites_invitee_id ON public.event_invites USING btree (invitee_id);


--
-- Name: idx_event_invites_inviter_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_invites_inviter_id ON public.event_invites USING btree (inviter_id);


--
-- Name: idx_event_invites_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_invites_status ON public.event_invites USING btree (status);


--
-- Name: idx_event_member_stats_covering; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_member_stats_covering ON public.event_member_stats USING btree (user_id, event_id) INCLUDE (total_claims, unpurchased_claims);


--
-- Name: INDEX idx_event_member_stats_covering; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_event_member_stats_covering IS 'Covering index allowing index-only scans for user claim stats.';


--
-- Name: idx_event_member_stats_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_member_stats_event ON public.event_member_stats USING btree (event_id);


--
-- Name: idx_event_member_stats_updated; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_member_stats_updated ON public.event_member_stats USING btree (updated_at);


--
-- Name: idx_event_member_stats_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_member_stats_user ON public.event_member_stats USING btree (user_id);


--
-- Name: idx_event_members_composite_rls; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_members_composite_rls ON public.event_members USING btree (event_id, user_id, role) WHERE (role IS NOT NULL);


--
-- Name: INDEX idx_event_members_composite_rls; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_event_members_composite_rls IS 'Composite index for RLS policies checking admin/member status. Covers most common RLS pattern.';


--
-- Name: idx_event_members_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_members_event_id ON public.event_members USING btree (event_id);


--
-- Name: idx_event_members_event_user_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_members_event_user_role ON public.event_members USING btree (event_id, user_id, role);


--
-- Name: idx_event_members_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_event_members_user_id ON public.event_members USING btree (user_id);


--
-- Name: idx_events_id_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_id_owner ON public.events USING btree (id, owner_id);


--
-- Name: idx_events_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_owner_id ON public.events USING btree (owner_id);


--
-- Name: INDEX idx_events_owner_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_events_owner_id IS 'Index for checking event ownership in RLS policies.';


--
-- Name: idx_items_assigned_recipient_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_assigned_recipient_id ON public.items USING btree (assigned_recipient_id);


--
-- Name: idx_items_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_created_by ON public.items USING btree (created_by);


--
-- Name: INDEX idx_items_created_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_items_created_by IS 'Index for checking item ownership and creator.';


--
-- Name: idx_items_list_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_list_id ON public.items USING btree (list_id);


--
-- Name: idx_items_list_recipient_composite; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_items_list_recipient_composite ON public.items USING btree (list_id, assigned_recipient_id) WHERE (assigned_recipient_id IS NOT NULL);


--
-- Name: INDEX idx_items_list_recipient_composite; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_items_list_recipient_composite IS 'Composite index for random receiver assignment queries.';


--
-- Name: idx_list_exclusions_composite; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_list_exclusions_composite ON public.list_exclusions USING btree (list_id, user_id);


--
-- Name: INDEX idx_list_exclusions_composite; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_list_exclusions_composite IS 'Composite index for checking if user is excluded from a list.';


--
-- Name: idx_list_exclusions_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_list_exclusions_uid ON public.list_exclusions USING btree (user_id);


--
-- Name: idx_list_recipients_composite; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_list_recipients_composite ON public.list_recipients USING btree (list_id, user_id) WHERE (user_id IS NOT NULL);


--
-- Name: INDEX idx_list_recipients_composite; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_list_recipients_composite IS 'Composite index for checking recipient status in RLS policies and queries.';


--
-- Name: idx_list_recipients_list_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_list_recipients_list_user ON public.list_recipients USING btree (list_id, user_id);


--
-- Name: idx_list_recipients_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_list_recipients_uid ON public.list_recipients USING btree (user_id);


--
-- Name: idx_list_viewers_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_list_viewers_uid ON public.list_viewers USING btree (user_id);


--
-- Name: idx_lists_composite_joins; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lists_composite_joins ON public.lists USING btree (id, event_id, created_by);


--
-- Name: INDEX idx_lists_composite_joins; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_lists_composite_joins IS 'Composite index covering most common list JOIN patterns and WHERE clauses.';


--
-- Name: idx_lists_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lists_created_by ON public.lists USING btree (created_by);


--
-- Name: idx_lists_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lists_event_id ON public.lists USING btree (event_id);


--
-- Name: idx_lists_random_assignment_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lists_random_assignment_enabled ON public.lists USING btree (random_assignment_enabled) WHERE (random_assignment_enabled = true);


--
-- Name: idx_lists_random_modes; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lists_random_modes ON public.lists USING btree (event_id, random_assignment_enabled, random_receiver_assignment_enabled);


--
-- Name: INDEX idx_lists_random_modes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_lists_random_modes IS 'Composite index for queries filtering by random assignment modes.';


--
-- Name: idx_lists_random_receiver_assignment_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lists_random_receiver_assignment_enabled ON public.lists USING btree (random_receiver_assignment_enabled) WHERE (random_receiver_assignment_enabled = true);


--
-- Name: idx_notification_queue_sent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_queue_sent ON public.notification_queue USING btree (sent, created_at);


--
-- Name: idx_notification_queue_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_queue_user_id ON public.notification_queue USING btree (user_id);


--
-- Name: idx_orphaned_lists_delete_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orphaned_lists_delete_at ON public.orphaned_lists USING btree (delete_at);


--
-- Name: idx_orphaned_lists_list_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orphaned_lists_list_id ON public.orphaned_lists USING btree (list_id);


--
-- Name: idx_profiles_currency; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_currency ON public.profiles USING btree (currency);


--
-- Name: idx_profiles_id_display_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_id_display_name ON public.profiles USING btree (id) INCLUDE (display_name);


--
-- Name: INDEX idx_profiles_id_display_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_profiles_id_display_name IS 'Covering index for profile lookups in optimized events_for_current_user. Enables index-only scans.';


--
-- Name: idx_profiles_last_support_screen; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_last_support_screen ON public.profiles USING btree (last_support_screen_shown);


--
-- Name: idx_push_tokens_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_push_tokens_user_id ON public.push_tokens USING btree (user_id);


--
-- Name: idx_rate_limit_tracking_window; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rate_limit_tracking_window ON public.rate_limit_tracking USING btree (window_start);


--
-- Name: idx_security_audit_log_action_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_security_audit_log_action_created ON public.security_audit_log USING btree (action, created_at DESC);


--
-- Name: idx_security_audit_log_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_security_audit_log_created ON public.security_audit_log USING btree (created_at DESC);


--
-- Name: idx_security_audit_log_user_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_security_audit_log_user_created ON public.security_audit_log USING btree (user_id, created_at DESC);


--
-- Name: idx_sent_reminders_claim_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sent_reminders_claim_event ON public.sent_reminders USING btree (claim_id, event_id);


--
-- Name: idx_sent_reminders_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sent_reminders_event_id ON public.sent_reminders USING btree (event_id);


--
-- Name: idx_sent_reminders_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sent_reminders_user_id ON public.sent_reminders USING btree (user_id);


--
-- Name: list_recipients_email_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX list_recipients_email_unique ON public.list_recipients USING btree (list_id, lower(recipient_email)) WHERE (recipient_email IS NOT NULL);


--
-- Name: list_recipients_user_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX list_recipients_user_unique ON public.list_recipients USING btree (list_id, user_id) WHERE (user_id IS NOT NULL);


--
-- Name: profiles link_invites_on_profile_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER link_invites_on_profile_insert AFTER INSERT ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_invites_on_user_signup();


--
-- Name: claims on_claim_delete_refresh_stats; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_claim_delete_refresh_stats AFTER DELETE ON public.claims FOR EACH ROW EXECUTE FUNCTION public.trigger_refresh_stats_on_claim_delete();


--
-- Name: items on_item_delete_refresh_stats; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_item_delete_refresh_stats AFTER DELETE ON public.items FOR EACH ROW EXECUTE FUNCTION public.trigger_refresh_stats_on_item_delete();


--
-- Name: lists on_list_delete_refresh_stats; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_list_delete_refresh_stats BEFORE DELETE ON public.lists FOR EACH ROW EXECUTE FUNCTION public.trigger_refresh_stats_on_list_delete();


--
-- Name: user_plans set_timestamp; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_timestamp BEFORE UPDATE ON public.user_plans FOR EACH ROW EXECUTE FUNCTION public.tg_set_timestamp();


--
-- Name: events trg_autojoin_event; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_autojoin_event AFTER INSERT ON public.events FOR EACH ROW EXECUTE FUNCTION public.autojoin_event_as_admin();


--
-- Name: events trg_ensure_event_owner_member; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ensure_event_owner_member AFTER INSERT ON public.events FOR EACH ROW EXECUTE FUNCTION public.ensure_event_owner_member();


--
-- Name: lists trg_set_list_created_by; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_list_created_by BEFORE INSERT ON public.lists FOR EACH ROW EXECUTE FUNCTION public.set_list_created_by();


--
-- Name: claims trigger_cleanup_reminder_on_purchase; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_cleanup_reminder_on_purchase AFTER UPDATE ON public.claims FOR EACH ROW WHEN (((new.purchased = true) AND (old.purchased = false))) EXECUTE FUNCTION public.cleanup_reminder_on_purchase();


--
-- Name: event_members trigger_initialize_event_member_stats; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_initialize_event_member_stats AFTER INSERT ON public.event_members FOR EACH ROW EXECUTE FUNCTION public.initialize_event_member_stats();


--
-- Name: profiles trigger_link_recipients_on_signup; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_link_recipients_on_signup AFTER INSERT ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.link_list_recipients_on_signup();


--
-- Name: event_members trigger_mark_orphaned_lists; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_mark_orphaned_lists AFTER DELETE ON public.event_members FOR EACH ROW EXECUTE FUNCTION public.mark_orphaned_lists_for_deletion();


--
-- Name: claims trigger_notify_new_claim; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_notify_new_claim AFTER INSERT ON public.claims FOR EACH ROW EXECUTE FUNCTION public.notify_new_claim();


--
-- Name: TRIGGER trigger_notify_new_claim ON claims; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TRIGGER trigger_notify_new_claim ON public.claims IS 'Sends notifications and logs digest activity when item is claimed';


--
-- Name: items trigger_notify_new_item; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_notify_new_item AFTER INSERT ON public.items FOR EACH ROW EXECUTE FUNCTION public.notify_new_item();


--
-- Name: TRIGGER trigger_notify_new_item ON items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TRIGGER trigger_notify_new_item ON public.items IS 'Sends notifications and logs digest activity when new item is added';


--
-- Name: lists trigger_notify_new_list; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_notify_new_list AFTER INSERT ON public.lists FOR EACH ROW EXECUTE FUNCTION public.notify_new_list();


--
-- Name: TRIGGER trigger_notify_new_list ON lists; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TRIGGER trigger_notify_new_list ON public.lists IS 'Sends notifications and logs digest activity when new list is created';


--
-- Name: claims trigger_notify_unclaim; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_notify_unclaim AFTER DELETE ON public.claims FOR EACH ROW EXECUTE FUNCTION public.notify_unclaim();


--
-- Name: TRIGGER trigger_notify_unclaim ON claims; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TRIGGER trigger_notify_unclaim ON public.claims IS 'Sends notifications and logs digest activity when items are unclaimed';


--
-- Name: event_members trigger_unmark_orphaned_lists; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_unmark_orphaned_lists AFTER INSERT ON public.event_members FOR EACH ROW EXECUTE FUNCTION public.unmark_orphaned_lists_on_member_join();


--
-- Name: claims trigger_update_event_member_stats_on_claim; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_event_member_stats_on_claim AFTER INSERT OR DELETE OR UPDATE ON public.claims FOR EACH ROW EXECUTE FUNCTION public.update_event_member_stats_on_claim_change();


--
-- Name: lists trigger_update_event_member_stats_on_list_event; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_event_member_stats_on_list_event AFTER UPDATE ON public.lists FOR EACH ROW WHEN ((old.event_id IS DISTINCT FROM new.event_id)) EXECUTE FUNCTION public.update_event_member_stats_on_list_event_change();


--
-- Name: list_recipients trigger_update_event_member_stats_on_recipient; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_event_member_stats_on_recipient AFTER INSERT OR DELETE OR UPDATE ON public.list_recipients FOR EACH ROW EXECUTE FUNCTION public.update_event_member_stats_on_recipient_change();


--
-- Name: profiles trigger_update_invites_on_signup; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_update_invites_on_signup AFTER INSERT ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_invites_on_user_signup();


--
-- Name: claim_split_requests claim_split_requests_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_split_requests
    ADD CONSTRAINT claim_split_requests_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE;


--
-- Name: claim_split_requests claim_split_requests_original_claimer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_split_requests
    ADD CONSTRAINT claim_split_requests_original_claimer_id_fkey FOREIGN KEY (original_claimer_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: claim_split_requests claim_split_requests_requester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_split_requests
    ADD CONSTRAINT claim_split_requests_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: claims claims_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claims
    ADD CONSTRAINT claims_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: claims claims_claimer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claims
    ADD CONSTRAINT claims_claimer_id_fkey FOREIGN KEY (claimer_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: claims claims_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claims
    ADD CONSTRAINT claims_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE;


--
-- Name: daily_activity_log daily_activity_log_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_activity_log
    ADD CONSTRAINT daily_activity_log_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: daily_activity_log daily_activity_log_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_activity_log
    ADD CONSTRAINT daily_activity_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: event_invites event_invites_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_invites
    ADD CONSTRAINT event_invites_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: event_invites event_invites_invitee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_invites
    ADD CONSTRAINT event_invites_invitee_id_fkey FOREIGN KEY (invitee_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: event_invites event_invites_inviter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_invites
    ADD CONSTRAINT event_invites_inviter_id_fkey FOREIGN KEY (inviter_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: event_member_stats event_member_stats_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_member_stats
    ADD CONSTRAINT event_member_stats_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: event_member_stats event_member_stats_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_member_stats
    ADD CONSTRAINT event_member_stats_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: event_members event_members_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_members
    ADD CONSTRAINT event_members_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: event_members event_members_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_members
    ADD CONSTRAINT event_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: events events_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: daily_activity_log fk_daily_activity_log_event_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_activity_log
    ADD CONSTRAINT fk_daily_activity_log_event_id FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: daily_activity_log fk_daily_activity_log_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_activity_log
    ADD CONSTRAINT fk_daily_activity_log_user_id FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: event_invites fk_event_invites_event_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_invites
    ADD CONSTRAINT fk_event_invites_event_id FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: event_invites fk_event_invites_invitee_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_invites
    ADD CONSTRAINT fk_event_invites_invitee_id FOREIGN KEY (invitee_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: event_invites fk_event_invites_inviter_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_invites
    ADD CONSTRAINT fk_event_invites_inviter_id FOREIGN KEY (inviter_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: event_members fk_event_members_event_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_members
    ADD CONSTRAINT fk_event_members_event_id FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: event_members fk_event_members_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_members
    ADD CONSTRAINT fk_event_members_user_id FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: list_exclusions fk_list_exclusions_list_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_exclusions
    ADD CONSTRAINT fk_list_exclusions_list_id FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;


--
-- Name: list_exclusions fk_list_exclusions_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_exclusions
    ADD CONSTRAINT fk_list_exclusions_user_id FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: list_viewers fk_list_viewers_list_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_viewers
    ADD CONSTRAINT fk_list_viewers_list_id FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;


--
-- Name: list_viewers fk_list_viewers_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_viewers
    ADD CONSTRAINT fk_list_viewers_user_id FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: notification_queue fk_notification_queue_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_queue
    ADD CONSTRAINT fk_notification_queue_user_id FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: orphaned_lists fk_orphaned_lists_event_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orphaned_lists
    ADD CONSTRAINT fk_orphaned_lists_event_id FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: orphaned_lists fk_orphaned_lists_excluded_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orphaned_lists
    ADD CONSTRAINT fk_orphaned_lists_excluded_user_id FOREIGN KEY (excluded_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: orphaned_lists fk_orphaned_lists_list_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orphaned_lists
    ADD CONSTRAINT fk_orphaned_lists_list_id FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;


--
-- Name: push_tokens fk_push_tokens_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_tokens
    ADD CONSTRAINT fk_push_tokens_user_id FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: sent_reminders fk_sent_reminders_claim_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sent_reminders
    ADD CONSTRAINT fk_sent_reminders_claim_id FOREIGN KEY (claim_id) REFERENCES public.claims(id) ON DELETE CASCADE;


--
-- Name: sent_reminders fk_sent_reminders_event_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sent_reminders
    ADD CONSTRAINT fk_sent_reminders_event_id FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: sent_reminders fk_sent_reminders_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sent_reminders
    ADD CONSTRAINT fk_sent_reminders_user_id FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: user_plans fk_user_plans_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_plans
    ADD CONSTRAINT fk_user_plans_user_id FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: items items_assigned_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_assigned_recipient_id_fkey FOREIGN KEY (assigned_recipient_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: items items_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: items items_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_list_id_fkey FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;


--
-- Name: list_exclusions list_exclusions_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_exclusions
    ADD CONSTRAINT list_exclusions_list_id_fkey FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;


--
-- Name: list_exclusions list_exclusions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_exclusions
    ADD CONSTRAINT list_exclusions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: list_recipients list_recipients_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_recipients
    ADD CONSTRAINT list_recipients_list_id_fkey FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;


--
-- Name: list_recipients list_recipients_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_recipients
    ADD CONSTRAINT list_recipients_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: list_viewers list_viewers_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_viewers
    ADD CONSTRAINT list_viewers_list_id_fkey FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;


--
-- Name: list_viewers list_viewers_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_viewers
    ADD CONSTRAINT list_viewers_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: lists lists_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lists
    ADD CONSTRAINT lists_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: lists lists_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lists
    ADD CONSTRAINT lists_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: notification_queue notification_queue_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_queue
    ADD CONSTRAINT notification_queue_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: orphaned_lists orphaned_lists_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orphaned_lists
    ADD CONSTRAINT orphaned_lists_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: orphaned_lists orphaned_lists_excluded_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orphaned_lists
    ADD CONSTRAINT orphaned_lists_excluded_user_id_fkey FOREIGN KEY (excluded_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: orphaned_lists orphaned_lists_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orphaned_lists
    ADD CONSTRAINT orphaned_lists_list_id_fkey FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: push_tokens push_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_tokens
    ADD CONSTRAINT push_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: security_audit_log security_audit_log_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.security_audit_log
    ADD CONSTRAINT security_audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: sent_reminders sent_reminders_claim_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sent_reminders
    ADD CONSTRAINT sent_reminders_claim_id_fkey FOREIGN KEY (claim_id) REFERENCES public.claims(id) ON DELETE CASCADE;


--
-- Name: sent_reminders sent_reminders_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sent_reminders
    ADD CONSTRAINT sent_reminders_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: sent_reminders sent_reminders_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sent_reminders
    ADD CONSTRAINT sent_reminders_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: user_plans user_plans_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_plans
    ADD CONSTRAINT user_plans_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: daily_activity_log No public access to activity log; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "No public access to activity log" ON public.daily_activity_log USING (false);


--
-- Name: notification_queue No public access to notification queue; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "No public access to notification queue" ON public.notification_queue USING (false);


--
-- Name: sent_reminders No public access to sent_reminders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "No public access to sent_reminders" ON public.sent_reminders USING (false) WITH CHECK (false);


--
-- Name: claim_split_requests Original claimers can update split requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Original claimers can update split requests" ON public.claim_split_requests FOR UPDATE USING ((original_claimer_id = ( SELECT auth.uid() AS uid)));


--
-- Name: claim_split_requests Requesters can delete their pending requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Requesters can delete their pending requests" ON public.claim_split_requests FOR DELETE USING (((requester_id = ( SELECT auth.uid() AS uid)) AND (status = 'pending'::text)));


--
-- Name: claim_split_requests Users can create split requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can create split requests" ON public.claim_split_requests FOR INSERT WITH CHECK ((requester_id = ( SELECT auth.uid() AS uid)));


--
-- Name: push_tokens Users can delete own tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete own tokens" ON public.push_tokens FOR DELETE USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: push_tokens Users can insert own tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert own tokens" ON public.push_tokens FOR INSERT WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: push_tokens Users can update own tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update own tokens" ON public.push_tokens FOR UPDATE USING ((user_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: push_tokens Users can view own tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view own tokens" ON public.push_tokens FOR SELECT USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: claim_split_requests Users can view their split requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view their split requests" ON public.claim_split_requests FOR SELECT USING (((requester_id = ( SELECT auth.uid() AS uid)) OR (original_claimer_id = ( SELECT auth.uid() AS uid))));


--
-- Name: claims admins can delete any claims; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "admins can delete any claims" ON public.claims FOR DELETE USING (public.is_event_admin(public.event_id_for_item(item_id), ( SELECT auth.uid() AS uid)));


--
-- Name: events admins can delete events; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "admins can delete events" ON public.events FOR DELETE USING (public.is_event_admin(id, ( SELECT auth.uid() AS uid)));


--
-- Name: claim_split_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.claim_split_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: claims; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.claims ENABLE ROW LEVEL SECURITY;

--
-- Name: claims claims_delete_admins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY claims_delete_admins ON public.claims AS RESTRICTIVE FOR DELETE TO authenticated USING (public.is_event_admin(public.event_id_for_item(item_id)));


--
-- Name: claims claims_select_visible; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY claims_select_visible ON public.claims FOR SELECT USING (((claimer_id = auth.uid()) OR public.can_view_list(public.list_id_for_item(item_id), auth.uid())));


--
-- Name: claims claims_update_by_claimer; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY claims_update_by_claimer ON public.claims FOR UPDATE USING ((( SELECT auth.uid() AS uid) = claimer_id)) WITH CHECK ((( SELECT auth.uid() AS uid) = claimer_id));


--
-- Name: claims claims_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY claims_update_own ON public.claims FOR UPDATE USING ((( SELECT auth.uid() AS uid) = claimer_id)) WITH CHECK ((( SELECT auth.uid() AS uid) = claimer_id));


--
-- Name: daily_activity_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.daily_activity_log ENABLE ROW LEVEL SECURITY;

--
-- Name: events delete events by owner or last member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "delete events by owner or last member" ON public.events FOR DELETE USING (((owner_id = ( SELECT auth.uid() AS uid)) OR public.is_last_event_member(id, ( SELECT auth.uid() AS uid))));


--
-- Name: items delete items by creator or last member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "delete items by creator or last member" ON public.items FOR DELETE USING (((created_by = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM public.lists l
  WHERE ((l.id = items.list_id) AND ((l.created_by = ( SELECT auth.uid() AS uid)) OR public.is_last_event_member(l.event_id, ( SELECT auth.uid() AS uid))))))));


--
-- Name: list_recipients delete list_recipients by creator or last member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "delete list_recipients by creator or last member" ON public.list_recipients FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.lists l
  WHERE ((l.id = list_recipients.list_id) AND ((l.created_by = ( SELECT auth.uid() AS uid)) OR public.is_last_event_member(l.event_id, ( SELECT auth.uid() AS uid)))))));


--
-- Name: lists delete lists by creator or last member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "delete lists by creator or last member" ON public.lists FOR DELETE USING (((created_by = ( SELECT auth.uid() AS uid)) OR public.is_last_event_member(event_id, ( SELECT auth.uid() AS uid))));


--
-- Name: claims delete own claims; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "delete own claims" ON public.claims FOR DELETE USING ((claimer_id = ( SELECT auth.uid() AS uid)));


--
-- Name: event_members delete own event membership; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "delete own event membership" ON public.event_members FOR DELETE USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: event_invites; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.event_invites ENABLE ROW LEVEL SECURITY;

--
-- Name: event_invites event_invites_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY event_invites_delete ON public.event_invites FOR DELETE USING (((( SELECT auth.uid() AS uid) = inviter_id) OR (EXISTS ( SELECT 1
   FROM public.event_members em
  WHERE ((em.event_id = event_invites.event_id) AND (em.user_id = ( SELECT auth.uid() AS uid)) AND (em.role = 'admin'::public.member_role))))));


--
-- Name: event_invites event_invites_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY event_invites_insert ON public.event_invites FOR INSERT WITH CHECK (((( SELECT auth.uid() AS uid) = inviter_id) AND (EXISTS ( SELECT 1
   FROM public.event_members em
  WHERE ((em.event_id = event_invites.event_id) AND (em.user_id = ( SELECT auth.uid() AS uid)))))));


--
-- Name: event_invites event_invites_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY event_invites_select ON public.event_invites FOR SELECT USING (((( SELECT auth.uid() AS uid) = inviter_id) OR (( SELECT auth.uid() AS uid) = invitee_id) OR (EXISTS ( SELECT 1
   FROM public.event_members em
  WHERE ((em.event_id = event_invites.event_id) AND (em.user_id = ( SELECT auth.uid() AS uid)))))));


--
-- Name: event_invites event_invites_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY event_invites_update ON public.event_invites FOR UPDATE USING ((( SELECT auth.uid() AS uid) = invitee_id));


--
-- Name: event_member_stats; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.event_member_stats ENABLE ROW LEVEL SECURITY;

--
-- Name: event_member_stats event_member_stats_no_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY event_member_stats_no_delete ON public.event_member_stats FOR DELETE USING (false);


--
-- Name: event_member_stats event_member_stats_no_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY event_member_stats_no_insert ON public.event_member_stats FOR INSERT WITH CHECK (false);


--
-- Name: event_member_stats event_member_stats_no_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY event_member_stats_no_update ON public.event_member_stats FOR UPDATE USING (false);


--
-- Name: event_member_stats event_member_stats_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY event_member_stats_select ON public.event_member_stats FOR SELECT USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: event_members; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.event_members ENABLE ROW LEVEL SECURITY;

--
-- Name: event_members event_members_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY event_members_select ON public.event_members FOR SELECT USING (public.is_member_of_event(event_id, ( SELECT auth.uid() AS uid)));


--
-- Name: events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

--
-- Name: events events: update by admins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "events: update by admins" ON public.events FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.event_members em
  WHERE ((em.event_id = events.id) AND (em.user_id = ( SELECT auth.uid() AS uid)) AND (em.role = 'admin'::public.member_role))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.event_members em
  WHERE ((em.event_id = events.id) AND (em.user_id = ( SELECT auth.uid() AS uid)) AND (em.role = 'admin'::public.member_role)))));


--
-- Name: events insert events when owner is self; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "insert events when owner is self" ON public.events FOR INSERT WITH CHECK ((owner_id = ( SELECT auth.uid() AS uid)));


--
-- Name: list_recipients insert list_recipients by creator; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "insert list_recipients by creator" ON public.list_recipients FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.lists l
  WHERE ((l.id = list_recipients.list_id) AND (l.created_by = ( SELECT auth.uid() AS uid))))));


--
-- Name: items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;

--
-- Name: items items_select_with_receiver_assignment; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY items_select_with_receiver_assignment ON public.items FOR SELECT USING (((EXISTS ( SELECT 1
   FROM public.claims c
  WHERE ((c.item_id = items.id) AND (c.claimer_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM (public.lists l
     JOIN public.event_members em ON ((em.event_id = l.event_id)))
  WHERE ((l.id = items.list_id) AND (em.user_id = auth.uid()) AND public.can_view_list(l.id, auth.uid()) AND (((l.random_assignment_enabled = true) AND (l.random_receiver_assignment_enabled = true)) OR (l.created_by = auth.uid()) OR (em.role = 'admin'::public.member_role) OR (EXISTS ( SELECT 1
           FROM public.events e
          WHERE ((e.id = l.event_id) AND (e.owner_id = auth.uid())))) OR ((l.random_assignment_enabled = true) AND (COALESCE(l.random_receiver_assignment_enabled, false) = false) AND ((l.random_assignment_executed_at IS NULL) OR (EXISTS ( SELECT 1
           FROM public.claims c
          WHERE ((c.item_id = items.id) AND (c.assigned_to = auth.uid())))))) OR ((COALESCE(l.random_assignment_enabled, false) = false) AND (l.random_receiver_assignment_enabled = true) AND (items.assigned_recipient_id <> auth.uid())) OR ((COALESCE(l.random_assignment_enabled, false) = false) AND (COALESCE(l.random_receiver_assignment_enabled, false) = false))))))));


--
-- Name: list_exclusions le_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY le_select ON public.list_exclusions FOR SELECT USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: list_exclusions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.list_exclusions ENABLE ROW LEVEL SECURITY;

--
-- Name: list_exclusions list_exclusions_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY list_exclusions_delete ON public.list_exclusions FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.lists l
  WHERE ((l.id = list_exclusions.list_id) AND ((l.created_by = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
           FROM public.event_members em
          WHERE ((em.event_id = l.event_id) AND (em.user_id = ( SELECT auth.uid() AS uid)) AND (em.role = 'admin'::public.member_role)))))))));


--
-- Name: list_exclusions list_exclusions_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY list_exclusions_insert ON public.list_exclusions FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM public.lists l
  WHERE ((l.id = list_exclusions.list_id) AND (l.created_by = ( SELECT auth.uid() AS uid))))));


--
-- Name: list_exclusions list_exclusions_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY list_exclusions_select ON public.list_exclusions FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.lists l
  WHERE ((l.id = list_exclusions.list_id) AND (l.created_by = ( SELECT auth.uid() AS uid))))) OR (user_id = ( SELECT auth.uid() AS uid))));


--
-- Name: list_recipients; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.list_recipients ENABLE ROW LEVEL SECURITY;

--
-- Name: list_recipients list_recipients_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY list_recipients_insert ON public.list_recipients FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.lists l
  WHERE ((l.id = list_recipients.list_id) AND (l.created_by = ( SELECT auth.uid() AS uid))))));


--
-- Name: list_recipients list_recipients_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY list_recipients_select ON public.list_recipients FOR SELECT USING (public.can_view_list(list_id, ( SELECT auth.uid() AS uid)));


--
-- Name: list_viewers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.list_viewers ENABLE ROW LEVEL SECURITY;

--
-- Name: lists; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lists ENABLE ROW LEVEL SECURITY;

--
-- Name: lists lists_delete_admins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lists_delete_admins ON public.lists AS RESTRICTIVE FOR DELETE TO authenticated USING (public.is_event_admin(event_id));


--
-- Name: lists lists_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lists_insert ON public.lists AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (public.is_event_member(event_id));


--
-- Name: lists lists_select_visible; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lists_select_visible ON public.lists FOR SELECT USING (public.can_view_list(id, auth.uid()));


--
-- Name: list_viewers lv_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lv_select ON public.list_viewers FOR SELECT USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: items members can insert items into their event lists; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "members can insert items into their event lists" ON public.items FOR INSERT WITH CHECK (((( SELECT auth.role() AS role) = 'authenticated'::text) AND (created_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM (public.lists l
     JOIN public.event_members em ON ((em.event_id = l.event_id)))
  WHERE ((l.id = items.list_id) AND (em.user_id = ( SELECT auth.uid() AS uid)))))));


--
-- Name: items members can select items in their events; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "members can select items in their events" ON public.items FOR SELECT USING (((EXISTS ( SELECT 1
   FROM (public.lists l
     JOIN public.event_members em ON ((em.event_id = l.event_id)))
  WHERE ((l.id = items.list_id) AND (em.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM public.claims c
  WHERE ((c.item_id = items.id) AND (c.claimer_id = auth.uid()))))));


--
-- Name: user_plans no_client_writes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY no_client_writes ON public.user_plans TO authenticated USING (false) WITH CHECK (false);


--
-- Name: notification_queue; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notification_queue ENABLE ROW LEVEL SECURITY;

--
-- Name: orphaned_lists; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.orphaned_lists ENABLE ROW LEVEL SECURITY;

--
-- Name: orphaned_lists orphaned_lists_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY orphaned_lists_select ON public.orphaned_lists FOR SELECT USING (false);


--
-- Name: events owners can delete events; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owners can delete events" ON public.events FOR DELETE USING ((owner_id = ( SELECT auth.uid() AS uid)));


--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles are readable by logged in users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "profiles are readable by logged in users" ON public.profiles FOR SELECT TO authenticated USING (true);


--
-- Name: push_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: rate_limit_tracking; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rate_limit_tracking ENABLE ROW LEVEL SECURITY;

--
-- Name: rate_limit_tracking rate_limit_tracking_no_public_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rate_limit_tracking_no_public_access ON public.rate_limit_tracking USING (false) WITH CHECK (false);


--
-- Name: POLICY rate_limit_tracking_no_public_access ON rate_limit_tracking; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY rate_limit_tracking_no_public_access ON public.rate_limit_tracking IS 'Rate limit tracking is only accessible via SECURITY DEFINER functions. No direct user access allowed.';


--
-- Name: user_plans read_own_plan; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY read_own_plan ON public.user_plans FOR SELECT TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id));


--
-- Name: security_audit_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.security_audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: security_audit_log security_audit_log_no_public_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY security_audit_log_no_public_access ON public.security_audit_log USING (false);


--
-- Name: events select events for members; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "select events for members" ON public.events FOR SELECT USING (public.is_event_member(id, ( SELECT auth.uid() AS uid)));


--
-- Name: events select events for owners; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "select events for owners" ON public.events FOR SELECT USING ((owner_id = ( SELECT auth.uid() AS uid)));


--
-- Name: sent_reminders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sent_reminders ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles server-side insert when id exists in auth.users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "server-side insert when id exists in auth.users" ON public.profiles FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM auth.users u
  WHERE (u.id = profiles.id))));


--
-- Name: events update events by owner or last member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "update events by owner or last member" ON public.events FOR UPDATE USING (((owner_id = ( SELECT auth.uid() AS uid)) OR public.is_last_event_member(id, ( SELECT auth.uid() AS uid)))) WITH CHECK (((owner_id = ( SELECT auth.uid() AS uid)) OR public.is_last_event_member(id, ( SELECT auth.uid() AS uid))));


--
-- Name: items update items by creator or last member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "update items by creator or last member" ON public.items FOR UPDATE USING (((created_by = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM public.lists l
  WHERE ((l.id = items.list_id) AND ((l.created_by = ( SELECT auth.uid() AS uid)) OR public.is_last_event_member(l.event_id, ( SELECT auth.uid() AS uid))))))));


--
-- Name: list_recipients update list_recipients by creator or last member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "update list_recipients by creator or last member" ON public.list_recipients FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.lists l
  WHERE ((l.id = list_recipients.list_id) AND ((l.created_by = ( SELECT auth.uid() AS uid)) OR public.is_last_event_member(l.event_id, ( SELECT auth.uid() AS uid)))))));


--
-- Name: lists update lists by creator or last member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "update lists by creator or last member" ON public.lists FOR UPDATE USING (((created_by = ( SELECT auth.uid() AS uid)) OR public.is_last_event_member(event_id, ( SELECT auth.uid() AS uid))));


--
-- Name: user_plans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_plans ENABLE ROW LEVEL SECURITY;

--
-- Name: user_plans user_plans_self; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_plans_self ON public.user_plans USING ((user_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: profiles users can insert their own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "users can insert their own profile" ON public.profiles FOR INSERT WITH CHECK ((id = ( SELECT auth.uid() AS uid)));


--
-- Name: profiles users can update their own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "users can update their own profile" ON public.profiles FOR UPDATE USING ((id = ( SELECT auth.uid() AS uid))) WITH CHECK ((id = ( SELECT auth.uid() AS uid)));


--
-- PostgreSQL database dump complete
--

\unrestrict SRoQselunXZPFvuOXFh2AVnbmZFKzN0TizJmRxwTMHXIehrVE4m37ZwHS7qXiD7

