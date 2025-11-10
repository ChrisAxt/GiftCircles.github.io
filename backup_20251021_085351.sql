

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";






COMMENT ON SCHEMA "public" IS 'SECURITY BEST PRACTICES:
1. All SECURITY DEFINER functions use SET search_path TO prevent search path attacks
2. All user input is parameterized (no string concatenation in queries)
3. All functions validate input and check authorization
4. Rate limiting is applied to sensitive operations
5. All security events are logged to audit table
6. Foreign key constraints prevent orphaned records
7. CHECK constraints validate data integrity';



CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgtap" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."list_visibility" AS ENUM (
    'event',
    'selected'
);


ALTER TYPE "public"."list_visibility" OWNER TO "postgres";


CREATE TYPE "public"."member_role" AS ENUM (
    'giver',
    'recipient',
    'admin'
);


ALTER TYPE "public"."member_role" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_next_occurrence"("p_date" "date", "p_freq" "text", "p_interval" integer DEFAULT 1) RETURNS "date"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
select case p_freq
  when 'weekly'  then p_date + (7 * p_interval)
  when 'monthly' then (p_date + (interval '1 month' * p_interval))::date
  when 'yearly'  then (p_date + (interval '1 year'  * p_interval))::date
  else p_date
end;
$$;


ALTER FUNCTION "public"."_next_occurrence"("p_date" "date", "p_freq" "text", "p_interval" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_pick_new_admin"("p_event_id" "uuid") RETURNS "uuid"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select user_id
  from public.event_members
  where event_id = p_event_id
  order by created_at nulls last, user_id
  limit 1
$$;


ALTER FUNCTION "public"."_pick_new_admin"("p_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_test_admin_for_event_title"("p_title" "text") RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT em.user_id
  FROM public.event_members em
  JOIN public.events e ON e.id = em.event_id
  WHERE e.title = p_title AND em.role = 'admin'
  LIMIT 1
$$;


ALTER FUNCTION "public"."_test_admin_for_event_title"("p_title" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_test_any_member_for_event_title"("p_title" "text") RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT em.user_id
  FROM public.event_members em
  JOIN public.events e ON e.id = em.event_id
  WHERE e.title = p_title
  ORDER BY (em.role = 'admin') DESC
  LIMIT 1
$$;


ALTER FUNCTION "public"."_test_any_member_for_event_title"("p_title" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_test_create_list_for_event"("p_event_id" "uuid", "p_name" "text", "p_vis" "public"."list_visibility") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."_test_create_list_for_event"("p_event_id" "uuid", "p_name" "text", "p_vis" "public"."list_visibility") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."accept_claim_split"("p_request_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."accept_claim_split"("p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."accept_event_invite"("p_invite_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."accept_event_invite"("p_invite_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."add_list_recipient"("p_list_id" "uuid", "p_recipient_email" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."add_list_recipient"("p_list_id" "uuid", "p_recipient_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."allowed_event_slots"("p_user" "uuid" DEFAULT "auth"."uid"()) RETURNS integer
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select case when public.is_pro(p_user) then 1000000 else 3 end;
$$;


ALTER FUNCTION "public"."allowed_event_slots"("p_user" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_items_randomly"("p_list_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."assign_items_randomly"("p_list_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."assign_items_randomly"("p_list_id" "uuid") IS 'Randomly assigns list items to event members. Transaction-safe with automatic rollback on error. Idempotent.';



CREATE OR REPLACE FUNCTION "public"."autojoin_event_as_admin"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  insert into public.event_members(event_id, user_id, role)
  values (new.id, new.owner_id, 'admin')
  on conflict do nothing;
  return new;
end;
$$;


ALTER FUNCTION "public"."autojoin_event_as_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."backfill_event_member_stats"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."backfill_event_member_stats"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."backfill_event_member_stats"() IS 'Backfills event_member_stats table with existing claim data including collaborative mode. Can be run to fix existing stats.';



CREATE OR REPLACE FUNCTION "public"."can_claim_item"("p_item_id" "uuid", "p_user" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."can_claim_item"("p_item_id" "uuid", "p_user" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."can_claim_item"("p_item_id" "uuid", "p_user" "uuid") IS 'Checks if a user can claim an item. For random assignment lists, only assigned users or admins can claim.';



CREATE OR REPLACE FUNCTION "public"."can_create_event"("p_user" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select case
    when public.is_pro(p_user, now()) then true
    -- Count TOTAL event memberships (owned + joined)
    else (select count(*) < 3 from public.event_members where user_id = p_user)
  end;
$$;


ALTER FUNCTION "public"."can_create_event"("p_user" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_join_event"("p_user" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select case
    when public.is_pro(p_user, now()) then true
    -- Count TOTAL event memberships (owned + joined)
    else (select count(*) < 3 from public.event_members where user_id = p_user)
  end;
$$;


ALTER FUNCTION "public"."can_join_event"("p_user" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_view_list"("p_list" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."can_view_list"("p_list" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_view_list"("uuid", "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."can_view_list"("uuid", "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_and_queue_purchase_reminders"() RETURNS TABLE("reminders_queued" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."check_and_queue_purchase_reminders"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_rate_limit"("p_action" "text", "p_max_requests" integer DEFAULT 100, "p_window_seconds" integer DEFAULT 60) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."check_rate_limit"("p_action" "text", "p_max_requests" integer, "p_window_seconds" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."check_rate_limit"("p_action" "text", "p_max_requests" integer, "p_window_seconds" integer) IS 'Checks if user has exceeded rate limit for a given action. Returns false if limit exceeded.';



CREATE OR REPLACE FUNCTION "public"."claim_counts_for_lists"("p_list_ids" "uuid"[]) RETURNS TABLE("list_id" "uuid", "claim_count" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."claim_counts_for_lists"("p_list_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_item"("p_item_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."claim_item"("p_item_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_old_activity_logs"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  delete from public.daily_activity_log
  where created_at < now() - interval '7 days';
end;
$$;


ALTER FUNCTION "public"."cleanup_old_activity_logs"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_old_invites"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  delete from public.event_invites
  where status in ('accepted', 'declined')
    and responded_at < now() - interval '30 days';
end;
$$;


ALTER FUNCTION "public"."cleanup_old_invites"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_old_notifications"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  delete from public.notification_queue
  where sent = true
    and created_at < now() - interval '7 days';
end;
$$;


ALTER FUNCTION "public"."cleanup_old_notifications"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_old_reminders"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  delete from public.sent_reminders sr
  using public.events e
  where sr.event_id = e.id
    and (e.event_date < now() - interval '7 days' or e.event_date is null);
end;
$$;


ALTER FUNCTION "public"."cleanup_old_reminders"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_orphaned_lists"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."cleanup_orphaned_lists"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_rate_limit_tracking"() RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  DELETE FROM public.rate_limit_tracking
  WHERE window_start < (now() - interval '1 hour');
$$;


ALTER FUNCTION "public"."cleanup_rate_limit_tracking"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cleanup_rate_limit_tracking"() IS 'Cleans up old rate limit tracking records. Should be run periodically.';



CREATE OR REPLACE FUNCTION "public"."cleanup_reminder_on_purchase"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."cleanup_reminder_on_purchase"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_event_and_admin"("p_title" "text", "p_event_date" "date", "p_recurrence" "text", "p_description" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."create_event_and_admin"("p_title" "text", "p_event_date" "date", "p_recurrence" "text", "p_description" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_event_and_admin"("p_title" "text", "p_event_date" "date", "p_recurrence" "text", "p_description" "text", "p_admin_only_invites" boolean DEFAULT false) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."create_event_and_admin"("p_title" "text", "p_event_date" "date", "p_recurrence" "text", "p_description" "text", "p_admin_only_invites" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_event_and_admin"("p_title" "text", "p_event_date" "date", "p_recurrence" "text", "p_description" "text", "p_admin_only_invites" boolean DEFAULT false, "p_admin_emails" "text"[] DEFAULT ARRAY[]::"text"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."create_event_and_admin"("p_title" "text", "p_event_date" "date", "p_recurrence" "text", "p_description" "text", "p_admin_only_invites" boolean, "p_admin_emails" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility" DEFAULT 'event'::"public"."list_visibility", "p_recipients" "uuid"[] DEFAULT '{}'::"uuid"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility" DEFAULT 'event'::"public"."list_visibility", "p_recipients" "uuid"[] DEFAULT '{}'::"uuid"[], "p_viewers" "uuid"[] DEFAULT '{}'::"uuid"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_viewers" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility" DEFAULT 'event'::"public"."list_visibility", "p_recipients" "uuid"[] DEFAULT '{}'::"uuid"[], "p_hidden_recipients" "uuid"[] DEFAULT '{}'::"uuid"[], "p_viewers" "uuid"[] DEFAULT '{}'::"uuid"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility" DEFAULT 'event'::"public"."list_visibility", "p_recipients" "uuid"[] DEFAULT '{}'::"uuid"[], "p_hidden_recipients" "uuid"[] DEFAULT '{}'::"uuid"[], "p_viewers" "uuid"[] DEFAULT '{}'::"uuid"[], "p_custom_recipient_name" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[], "p_custom_recipient_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "text", "p_custom_recipient_name" "text", "p_recipient_user_ids" "uuid"[], "p_recipient_emails" "text"[], "p_viewer_ids" "uuid"[], "p_exclusion_ids" "uuid"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "text", "p_custom_recipient_name" "text", "p_recipient_user_ids" "uuid"[], "p_recipient_emails" "text"[], "p_viewer_ids" "uuid"[], "p_exclusion_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility" DEFAULT 'event'::"public"."list_visibility", "p_recipients" "uuid"[] DEFAULT '{}'::"uuid"[], "p_hidden_recipients" "uuid"[] DEFAULT '{}'::"uuid"[], "p_viewers" "uuid"[] DEFAULT '{}'::"uuid"[], "p_custom_recipient_name" "text" DEFAULT NULL::"text", "p_random_assignment_enabled" boolean DEFAULT false, "p_random_assignment_mode" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[], "p_custom_recipient_name" "text", "p_random_assignment_enabled" boolean, "p_random_assignment_mode" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[], "p_custom_recipient_name" "text", "p_random_assignment_enabled" boolean, "p_random_assignment_mode" "text") IS 'Creates a list with recipients, viewers, and optional random assignment configuration';



CREATE OR REPLACE FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility" DEFAULT 'event'::"public"."list_visibility", "p_recipients" "uuid"[] DEFAULT '{}'::"uuid"[], "p_hidden_recipients" "uuid"[] DEFAULT '{}'::"uuid"[], "p_viewers" "uuid"[] DEFAULT '{}'::"uuid"[], "p_custom_recipient_name" "text" DEFAULT NULL::"text", "p_random_assignment_enabled" boolean DEFAULT false, "p_random_assignment_mode" "text" DEFAULT NULL::"text", "p_random_receiver_assignment_enabled" boolean DEFAULT false, "p_for_everyone" boolean DEFAULT false) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[], "p_custom_recipient_name" "text", "p_random_assignment_enabled" boolean, "p_random_assignment_mode" "text", "p_random_receiver_assignment_enabled" boolean, "p_for_everyone" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[], "p_custom_recipient_name" "text", "p_random_assignment_enabled" boolean, "p_random_assignment_mode" "text", "p_random_receiver_assignment_enabled" boolean, "p_for_everyone" boolean) IS 'Creates a list with recipients, viewers, and optional random assignment configuration. Transaction-safe with automatic rollback on error.';



CREATE OR REPLACE FUNCTION "public"."decline_event_invite"("p_invite_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."decline_event_invite"("p_invite_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_item"("p_item_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."delete_item"("p_item_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."delete_item"("p_item_id" "uuid") IS 'Securely deletes an item with authorization checks, rate limiting, and audit logging.';



CREATE OR REPLACE FUNCTION "public"."delete_list"("p_list_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."delete_list"("p_list_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."delete_list"("p_list_id" "uuid") IS 'Securely deletes a list with authorization checks, rate limiting, and audit logging.';



CREATE OR REPLACE FUNCTION "public"."deny_claim_split"("p_request_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."deny_claim_split"("p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_event_owner_member"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."ensure_event_owner_member"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."event_claim_counts_for_user"("p_event_ids" "uuid"[]) RETURNS TABLE("event_id" "uuid", "claim_count" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."event_claim_counts_for_user"("p_event_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."event_id_for_item"("i_id" "uuid") RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select l.event_id
  from public.items i
  join public.lists l on l.id = i.list_id
  where i.id = i_id
$$;


ALTER FUNCTION "public"."event_id_for_item"("i_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."event_id_for_list"("uuid") RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
  SELECT event_id FROM public.lists WHERE id = $1
$_$;


ALTER FUNCTION "public"."event_id_for_list"("uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."event_is_accessible"("p_event_id" "uuid", "p_user" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."event_is_accessible"("p_event_id" "uuid", "p_user" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."events_for_current_user"() RETURNS TABLE("id" "uuid", "title" "text", "event_date" "date", "join_code" "text", "created_at" timestamp with time zone, "member_count" bigint, "total_items" bigint, "claimed_count" bigint, "accessible" boolean, "rownum" integer, "my_claims" bigint, "my_unpurchased_claims" bigint)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
    -- Show claims on lists created by current user
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
      coalesce(ems.total_claims, 0) as my_claims,
      coalesce(ems.unpurchased_claims, 0) as my_unpurchased_claims,
      row_number() over (order by e.created_at asc nulls last, e.id) as rownum
    from my_events e
    left join counts ct on ct.event_id = e.id
    left join claims cl on cl.event_id = e.id
    left join event_member_stats ems on ems.event_id = e.id and ems.user_id = auth.uid()
  )
  select
    r.id, r.title, r.event_date, r.join_code, r.created_at,
    r.member_count, r.total_items, r.claimed_count,
    (r.rownum <= public.allowed_event_slots()) as accessible,
    r.rownum,
    r.my_claims,
    r.my_unpurchased_claims
  from ranked r
  order by r.created_at desc nulls last, r.id;
$$;


ALTER FUNCTION "public"."events_for_current_user"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."events_for_current_user"() IS 'Returns all events for the current user with counts. Uses materialized stats for my_claims and my_unpurchased_claims.';



CREATE OR REPLACE FUNCTION "public"."events_for_current_user_optimized"() RETURNS TABLE("id" "uuid", "title" "text", "event_date" "date", "join_code" "text", "created_at" timestamp with time zone, "member_count" bigint, "total_items" bigint, "claimed_count" bigint, "accessible" boolean, "rownum" integer, "my_claims" bigint, "my_unpurchased_claims" bigint, "members" "jsonb", "member_user_ids" "uuid"[])
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."events_for_current_user_optimized"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."events_for_current_user_optimized"() IS 'Optimized version of events_for_current_user that returns member details and profile names in a single query, eliminating N+1 queries.

Return columns:
- members: JSONB array of event members with format: [{"user_id": "uuid", "display_name": "Name"}]
- member_user_ids: Array of member user IDs for backward compatibility

Use the members field to avoid additional queries to event_members and profiles tables.';



CREATE OR REPLACE FUNCTION "public"."execute_random_receiver_assignment"("p_list_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."execute_random_receiver_assignment"("p_list_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."execute_random_receiver_assignment"("p_list_id" "uuid") IS 'Randomly assigns a recipient to each item in a list where random receiver assignment is enabled. Only the giver (claimer) will know who their assigned recipient is.';



CREATE OR REPLACE FUNCTION "public"."generate_and_send_daily_digests"("p_hour" integer DEFAULT NULL::integer) RETURNS TABLE("digests_sent" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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
$$;


ALTER FUNCTION "public"."generate_and_send_daily_digests"("p_hour" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_available_members_for_assignment"("p_list_id" "uuid") RETURNS "uuid"[]
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."get_available_members_for_assignment"("p_list_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_available_members_for_assignment"("p_list_id" "uuid") IS 'Returns shuffled array of event members eligible for random item assignment. When random_receiver_assignment_enabled is true, includes all members (Secret Santa style). Otherwise, excludes recipients.';



CREATE OR REPLACE FUNCTION "public"."get_claim_counts_by_list"("p_list_ids" "uuid"[]) RETURNS TABLE("list_id" "uuid", "claimed_count" bigint)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."get_claim_counts_by_list"("p_list_ids" "uuid"[]) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_claim_counts_by_list"("p_list_ids" "uuid"[]) IS 'Returns claim counts for lists. In combined random assignment (collaborative mode), all members see total counts. In single random modes, counts filtered by visibility. Claim details remain private.';



CREATE OR REPLACE FUNCTION "public"."get_list_recipients"("p_list_id" "uuid") RETURNS TABLE("list_id" "uuid", "user_id" "uuid", "recipient_email" "text", "display_name" "text", "is_registered" boolean, "is_event_member" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."get_list_recipients"("p_list_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_pending_invites"() RETURNS TABLE("invite_id" "uuid", "event_id" "uuid", "event_title" "text", "event_date" "date", "inviter_name" "text", "invited_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."get_my_pending_invites"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_split_requests"() RETURNS TABLE("request_id" "uuid", "item_id" "uuid", "item_name" "text", "event_id" "uuid", "event_title" "text", "list_name" "text", "requester_id" "uuid", "requester_name" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."get_my_split_requests"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."initialize_event_member_stats"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."initialize_event_member_stats"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."initialize_event_member_stats"() IS 'Trigger function that initializes event_member_stats when a new member joins an event';



CREATE OR REPLACE FUNCTION "public"."is_event_admin"("e_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.event_members em
    WHERE em.event_id = e_id
      AND em.user_id  = auth.uid()
      AND em.role     = 'admin'
  );
$$;


ALTER FUNCTION "public"."is_event_admin"("e_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_event_admin"("e_id" "uuid", "u_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists(select 1 from public.event_members em where em.event_id=e_id and em.user_id=u_id and em.role='admin')
$$;


ALTER FUNCTION "public"."is_event_admin"("e_id" "uuid", "u_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_event_member"("p_event_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.event_members em
    WHERE em.event_id = p_event_id
      AND em.user_id  = auth.uid()
  );
$$;


ALTER FUNCTION "public"."is_event_member"("p_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_event_member"("e_id" "uuid", "u_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists(select 1 from public.event_members em
                where em.event_id = e_id and em.user_id = u_id)
$$;


ALTER FUNCTION "public"."is_event_member"("e_id" "uuid", "u_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_last_event_member"("e_id" "uuid", "u_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."is_last_event_member"("e_id" "uuid", "u_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_list_recipient"("l_id" "uuid", "u_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists(
    select 1
    from public.list_recipients lr
    where lr.list_id = l_id and lr.user_id = u_id
  )
$$;


ALTER FUNCTION "public"."is_list_recipient"("l_id" "uuid", "u_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_member_of_event"("p_event" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT public.is_member_of_event_secure(p_event, auth.uid());
$$;


ALTER FUNCTION "public"."is_member_of_event"("p_event" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_member_of_event"("e_id" "uuid", "u_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT public.is_member_of_event_secure(e_id, u_id);
$$;


ALTER FUNCTION "public"."is_member_of_event"("e_id" "uuid", "u_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_member_of_event_secure"("p_event_id" "uuid", "p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.event_members
    WHERE event_id = p_event_id
      AND user_id = p_user_id
  );
$$;


ALTER FUNCTION "public"."is_member_of_event_secure"("p_event_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_pro"("p_user" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  select public.is_pro(p_user, now());
$$;


ALTER FUNCTION "public"."is_pro"("p_user" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_pro"("p_user" "uuid", "p_at" timestamp with time zone) RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  select coalesce(
    (select (plan = 'pro') or (pro_until is not null and pro_until >= p_at)
       from public.profiles where id = p_user),
    false
  );
$$;


ALTER FUNCTION "public"."is_pro"("p_user" "uuid", "p_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_pro_v2"("p_user" "uuid", "p_at" timestamp with time zone DEFAULT "now"()) RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."is_pro_v2"("p_user" "uuid", "p_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_sole_event_member"("p_event_id" "uuid", "p_user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."is_sole_event_member"("p_event_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."join_event"("p_code" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."join_event"("p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."leave_event"("p_event_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."leave_event"("p_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."link_list_recipients_on_signup"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."link_list_recipients_on_signup"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_claim_counts_for_user"("p_list_ids" "uuid"[]) RETURNS TABLE("list_id" "uuid", "claim_count" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."list_claim_counts_for_user"("p_list_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_claims_for_user"("p_item_ids" "uuid"[]) RETURNS TABLE("item_id" "uuid", "claimer_id" "uuid")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."list_claims_for_user"("p_item_ids" "uuid"[]) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."list_claims_for_user"("p_item_ids" "uuid"[]) IS 'Returns claims visible to current user. Simplified version that inlines all visibility checks. Collaborative mode shows claims assigned to user regardless of recipient status.';



CREATE OR REPLACE FUNCTION "public"."list_id_for_item"("i_id" "uuid") RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select list_id from public.items where id = i_id
$$;


ALTER FUNCTION "public"."list_id_for_item"("i_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_activity_for_digest"("p_event_id" "uuid", "p_exclude_user_id" "uuid", "p_activity_type" "text", "p_activity_data" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
$$;


ALTER FUNCTION "public"."log_activity_for_digest"("p_event_id" "uuid", "p_exclude_user_id" "uuid", "p_activity_type" "text", "p_activity_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_security_event"("p_action" "text", "p_resource_type" "text" DEFAULT NULL::"text", "p_resource_id" "uuid" DEFAULT NULL::"uuid", "p_success" boolean DEFAULT true, "p_error_message" "text" DEFAULT NULL::"text", "p_metadata" "jsonb" DEFAULT NULL::"jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."log_security_event"("p_action" "text", "p_resource_type" "text", "p_resource_id" "uuid", "p_success" boolean, "p_error_message" "text", "p_metadata" "jsonb") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."log_security_event"("p_action" "text", "p_resource_type" "text", "p_resource_id" "uuid", "p_success" boolean, "p_error_message" "text", "p_metadata" "jsonb") IS 'Logs security events to audit log. Used by SECURITY DEFINER functions.';



CREATE OR REPLACE FUNCTION "public"."mark_orphaned_lists_for_deletion"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."mark_orphaned_lists_for_deletion"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_new_claim"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
$$;


ALTER FUNCTION "public"."notify_new_claim"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_new_item"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
$$;


ALTER FUNCTION "public"."notify_new_item"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_new_list"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
$$;


ALTER FUNCTION "public"."notify_new_list"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recalculate_event_member_stats"("p_event_id" "uuid", "p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."recalculate_event_member_stats"("p_event_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."recalculate_event_member_stats"("p_event_id" "uuid", "p_user_id" "uuid") IS 'Recalculates and updates claim statistics for a specific user in a specific event. Includes collaborative mode claims.';



CREATE OR REPLACE FUNCTION "public"."remove_member"("p_event_id" "uuid", "p_user_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."remove_member"("p_event_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."request_claim_split"("p_item_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."request_claim_split"("p_item_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rollover_all_due_events"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."rollover_all_due_events"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sanitize_text"("p_text" "text", "p_max_length" integer DEFAULT 1000) RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
BEGIN
  IF p_text IS NULL THEN
    RETURN NULL;
  END IF;

  -- Trim whitespace and limit length
  RETURN substring(trim(p_text) from 1 for p_max_length);
END;
$$;


ALTER FUNCTION "public"."sanitize_text"("p_text" "text", "p_max_length" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."sanitize_text"("p_text" "text", "p_max_length" integer) IS 'Sanitizes text input by trimming whitespace and limiting length.';



CREATE OR REPLACE FUNCTION "public"."send_event_invite"("p_event_id" "uuid", "p_invitee_email" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."send_event_invite"("p_event_id" "uuid", "p_invitee_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_event_invite"("p_event_id" "uuid", "p_inviter_email" "text", "p_recipient_email" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."send_event_invite"("p_event_id" "uuid", "p_inviter_email" "text", "p_recipient_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_list_created_by"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if new.created_by is null then
    new.created_by := auth.uid();
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."set_list_created_by"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_onboarding_done"("p_done" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."set_onboarding_done"("p_done" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_plan"("p_plan" "text", "p_months" integer DEFAULT 0, "p_user" "uuid" DEFAULT "auth"."uid"()) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."set_plan"("p_plan" "text", "p_months" integer, "p_user" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_profile_name"("p_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.profiles (id, display_name)
  values (auth.uid(), p_name)
  on conflict (id) do update set display_name = excluded.display_name;
end;
$$;


ALTER FUNCTION "public"."set_profile_name"("p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_impersonate"("p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user_id::text)::text,
    true
  );
end;
$$;


ALTER FUNCTION "public"."test_impersonate"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tg_set_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


ALTER FUNCTION "public"."tg_set_timestamp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_daily_digest"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
$$;


ALTER FUNCTION "public"."trigger_daily_digest"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_push_notifications"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."trigger_push_notifications"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."unclaim_item"("p_item_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."unclaim_item"("p_item_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."unmark_orphaned_lists_on_member_join"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- When a new member joins an event, remove any orphaned list markers for that event
  DELETE FROM public.orphaned_lists
  WHERE event_id = NEW.event_id;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."unmark_orphaned_lists_on_member_join"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_event_member_stats_on_claim_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."update_event_member_stats_on_claim_change"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."update_event_member_stats_on_claim_change"() IS 'Trigger function that updates event_member_stats when claims are added, updated, or deleted';



CREATE OR REPLACE FUNCTION "public"."update_event_member_stats_on_list_event_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."update_event_member_stats_on_list_event_change"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."update_event_member_stats_on_list_event_change"() IS 'Trigger function that updates event_member_stats when a list is moved to a different event';



CREATE OR REPLACE FUNCTION "public"."update_event_member_stats_on_recipient_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."update_event_member_stats_on_recipient_change"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."update_event_member_stats_on_recipient_change"() IS 'Trigger function that updates event_member_stats when list recipients change';



CREATE OR REPLACE FUNCTION "public"."update_invites_on_user_signup"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
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


ALTER FUNCTION "public"."update_invites_on_user_signup"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_email"("p_email" "text") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$
BEGIN
  RETURN p_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';
END;
$_$;


ALTER FUNCTION "public"."validate_email"("p_email" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."validate_email"("p_email" "text") IS 'Validates if a text value is a valid email address.';



CREATE OR REPLACE FUNCTION "public"."validate_uuid"("p_value" "text") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."validate_uuid"("p_value" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."validate_uuid"("p_value" "text") IS 'Validates if a text value is a valid UUID.';



CREATE OR REPLACE FUNCTION "public"."whoami"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select jsonb_build_object(
    'uid', auth.uid(),
    'role', current_setting('request.jwt.claim.role', true)
  );
$$;


ALTER FUNCTION "public"."whoami"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."claim_split_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "item_id" "uuid" NOT NULL,
    "requester_id" "uuid" NOT NULL,
    "original_claimer_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "responded_at" timestamp with time zone,
    CONSTRAINT "claim_split_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'denied'::"text"])))
);


ALTER TABLE "public"."claim_split_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."claims" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "item_id" "uuid" NOT NULL,
    "claimer_id" "uuid" NOT NULL,
    "quantity" integer DEFAULT 1 NOT NULL,
    "note" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "purchased" boolean DEFAULT false NOT NULL,
    "assigned_to" "uuid",
    CONSTRAINT "chk_claims_quantity_positive" CHECK (("quantity" > 0)),
    CONSTRAINT "claims_quantity_check" CHECK (("quantity" > 0))
);

ALTER TABLE ONLY "public"."claims" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."claims" OWNER TO "postgres";


COMMENT ON TABLE "public"."claims" IS 'Multiple permissive policies exist for flexibility. Consider consolidating if performance issues arise.';



COMMENT ON COLUMN "public"."claims"."assigned_to" IS 'For random assignment lists: the user this item was assigned to. NULL for manual claims.';



CREATE TABLE IF NOT EXISTS "public"."daily_activity_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "event_id" "uuid" NOT NULL,
    "activity_type" "text" NOT NULL,
    "activity_data" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "daily_activity_log_activity_type_check" CHECK (("activity_type" = ANY (ARRAY['new_list'::"text", 'new_item'::"text", 'new_claim'::"text"])))
);


ALTER TABLE "public"."daily_activity_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."event_invites" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "event_id" "uuid" NOT NULL,
    "inviter_id" "uuid" NOT NULL,
    "invitee_email" "text" NOT NULL,
    "invitee_id" "uuid",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "invited_at" timestamp with time zone DEFAULT "now"(),
    "responded_at" timestamp with time zone,
    "invited_role" "public"."member_role" DEFAULT 'giver'::"public"."member_role" NOT NULL,
    CONSTRAINT "event_invites_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'declined'::"text"])))
);


ALTER TABLE "public"."event_invites" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."event_member_stats" (
    "event_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "total_claims" bigint DEFAULT 0 NOT NULL,
    "unpurchased_claims" bigint DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."event_member_stats" OWNER TO "postgres";


COMMENT ON TABLE "public"."event_member_stats" IS 'Materialized claim statistics per user per event. Updated automatically via triggers for performance.';



COMMENT ON COLUMN "public"."event_member_stats"."total_claims" IS 'Total number of claims by this user in this event (excluding claims on lists where user is recipient)';



COMMENT ON COLUMN "public"."event_member_stats"."unpurchased_claims" IS 'Number of unpurchased claims by this user in this event (excluding claims on lists where user is recipient)';



CREATE TABLE IF NOT EXISTS "public"."event_members" (
    "event_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "public"."member_role" DEFAULT 'giver'::"public"."member_role" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE ONLY "public"."event_members" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."event_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "event_date" "date",
    "join_code" "text" DEFAULT "replace"(("gen_random_uuid"())::"text", '-'::"text", ''::"text") NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "recurrence" "text" DEFAULT 'none'::"text" NOT NULL,
    "last_rolled_at" "date",
    "admin_only_invites" boolean DEFAULT false NOT NULL,
    CONSTRAINT "chk_events_date_reasonable" CHECK ((("event_date" IS NULL) OR ("event_date" >= '2020-01-01'::"date"))),
    CONSTRAINT "events_recurrence_check" CHECK (("recurrence" = ANY (ARRAY['none'::"text", 'weekly'::"text", 'monthly'::"text", 'yearly'::"text"])))
);

ALTER TABLE ONLY "public"."events" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."events" OWNER TO "postgres";


COMMENT ON TABLE "public"."events" IS 'Multiple permissive policies exist for flexibility. Consider consolidating if performance issues arise.';



CREATE TABLE IF NOT EXISTS "public"."items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "list_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "url" "text",
    "price" numeric(12,2),
    "notes" "text",
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "assigned_recipient_id" "uuid",
    CONSTRAINT "chk_items_price_positive" CHECK ((("price" IS NULL) OR ("price" >= (0)::numeric)))
);

ALTER TABLE ONLY "public"."items" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."items" OWNER TO "postgres";


COMMENT ON COLUMN "public"."items"."assigned_recipient_id" IS 'For random receiver assignment lists: the user this item is intended for. NULL for regular lists. The giver (claimer) should not equal this recipient.';



CREATE TABLE IF NOT EXISTS "public"."list_exclusions" (
    "list_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."list_exclusions" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."list_exclusions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."list_recipients" (
    "list_id" "uuid" NOT NULL,
    "user_id" "uuid",
    "can_view" boolean DEFAULT true NOT NULL,
    "recipient_email" "text",
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    CONSTRAINT "list_recipients_user_or_email_check" CHECK (((("user_id" IS NOT NULL) AND ("recipient_email" IS NULL)) OR (("user_id" IS NULL) AND ("recipient_email" IS NOT NULL))))
);

ALTER TABLE ONLY "public"."list_recipients" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."list_recipients" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."list_viewers" (
    "list_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL
);

ALTER TABLE ONLY "public"."list_viewers" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."list_viewers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."lists" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "event_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "visibility" "public"."list_visibility" DEFAULT 'event'::"public"."list_visibility" NOT NULL,
    "custom_recipient_name" "text",
    "random_assignment_enabled" boolean DEFAULT false NOT NULL,
    "random_assignment_mode" "text",
    "random_assignment_executed_at" timestamp with time zone,
    "random_receiver_assignment_enabled" boolean DEFAULT false NOT NULL,
    "for_everyone" boolean DEFAULT false NOT NULL,
    CONSTRAINT "lists_random_assignment_mode_check" CHECK (("random_assignment_mode" = ANY (ARRAY['one_per_member'::"text", 'distribute_all'::"text"])))
);

ALTER TABLE ONLY "public"."lists" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."lists" OWNER TO "postgres";


COMMENT ON COLUMN "public"."lists"."random_assignment_enabled" IS 'When true, items are randomly assigned and members can only see their assignments.';



COMMENT ON COLUMN "public"."lists"."random_assignment_mode" IS 'Assignment mode: one_per_member (1 item each) or distribute_all (all items distributed evenly).';



COMMENT ON COLUMN "public"."lists"."random_assignment_executed_at" IS 'Timestamp of the last random assignment execution.';



COMMENT ON COLUMN "public"."lists"."random_receiver_assignment_enabled" IS 'When true, each item is randomly assigned to a specific recipient. Only the giver knows who will receive their item.';



COMMENT ON COLUMN "public"."lists"."for_everyone" IS 'When true, this list is for all event members. All members can claim items (but cannot see who claimed them).';



CREATE TABLE IF NOT EXISTS "public"."notification_queue" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "data" "jsonb",
    "sent" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."notification_queue" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."orphaned_lists" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "list_id" "uuid" NOT NULL,
    "event_id" "uuid" NOT NULL,
    "excluded_user_id" "uuid" NOT NULL,
    "marked_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "delete_at" timestamp with time zone DEFAULT ("now"() + '30 days'::interval) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."orphaned_lists" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "display_name" "text",
    "avatar_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "onboarding_done" boolean DEFAULT false NOT NULL,
    "onboarding_at" timestamp with time zone,
    "plan" "text" DEFAULT 'free'::"text" NOT NULL,
    "pro_until" timestamp with time zone,
    "reminder_days" integer DEFAULT 3,
    "currency" character varying(3) DEFAULT 'USD'::character varying,
    "notification_digest_enabled" boolean DEFAULT false,
    "digest_time_hour" integer DEFAULT 9,
    "digest_frequency" "text" DEFAULT 'daily'::"text",
    "digest_day_of_week" integer DEFAULT 1,
    CONSTRAINT "chk_profiles_digest_day_valid" CHECK ((("digest_day_of_week" >= 0) AND ("digest_day_of_week" <= 6))),
    CONSTRAINT "chk_profiles_digest_hour_valid" CHECK ((("digest_time_hour" >= 0) AND ("digest_time_hour" <= 23))),
    CONSTRAINT "chk_profiles_reminder_days_valid" CHECK ((("reminder_days" >= 0) AND ("reminder_days" <= 365))),
    CONSTRAINT "profiles_digest_day_of_week_check" CHECK ((("digest_day_of_week" >= 0) AND ("digest_day_of_week" <= 6))),
    CONSTRAINT "profiles_digest_frequency_check" CHECK (("digest_frequency" = ANY (ARRAY['daily'::"text", 'weekly'::"text"]))),
    CONSTRAINT "profiles_digest_time_hour_check" CHECK ((("digest_time_hour" >= 0) AND ("digest_time_hour" <= 23))),
    CONSTRAINT "profiles_reminder_days_check" CHECK ((("reminder_days" >= 0) AND ("reminder_days" <= 30)))
);

ALTER TABLE ONLY "public"."profiles" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" OWNER TO "postgres";


COMMENT ON COLUMN "public"."profiles"."reminder_days" IS 'Number of days before event to send purchase reminder (0 = disabled)';



COMMENT ON COLUMN "public"."profiles"."currency" IS 'ISO 4217 currency code (e.g., USD, EUR, GBP)';



COMMENT ON COLUMN "public"."profiles"."notification_digest_enabled" IS 'Enable daily digest notifications (users can have both instant and digest)';



COMMENT ON COLUMN "public"."profiles"."digest_time_hour" IS 'Hour of day (0-23) to send daily digest in user local time';



COMMENT ON COLUMN "public"."profiles"."digest_frequency" IS 'Frequency of digest notifications: daily or weekly';



COMMENT ON COLUMN "public"."profiles"."digest_day_of_week" IS 'Day of week for weekly digest (0=Sunday, 1=Monday, ..., 6=Saturday)';



CREATE TABLE IF NOT EXISTS "public"."push_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "token" "text" NOT NULL,
    "platform" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "push_tokens_platform_check" CHECK (("platform" = ANY (ARRAY['ios'::"text", 'android'::"text", 'web'::"text"])))
);


ALTER TABLE "public"."push_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rate_limit_tracking" (
    "user_id" "uuid" NOT NULL,
    "action" "text" NOT NULL,
    "window_start" timestamp with time zone NOT NULL,
    "request_count" integer DEFAULT 1 NOT NULL
);


ALTER TABLE "public"."rate_limit_tracking" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."security_audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "action" "text" NOT NULL,
    "resource_type" "text",
    "resource_id" "uuid",
    "ip_address" "inet",
    "user_agent" "text",
    "success" boolean NOT NULL,
    "error_message" "text",
    "metadata" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."security_audit_log" OWNER TO "postgres";


COMMENT ON TABLE "public"."security_audit_log" IS 'Security audit log for tracking sensitive operations. Only accessible via SECURITY DEFINER functions.';



CREATE TABLE IF NOT EXISTS "public"."sent_reminders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "claim_id" "uuid" NOT NULL,
    "event_id" "uuid" NOT NULL,
    "sent_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."sent_reminders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_plans" (
    "user_id" "uuid" NOT NULL,
    "pro_until" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "note" "text"
);

ALTER TABLE ONLY "public"."user_plans" FORCE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_plans" OWNER TO "postgres";


ALTER TABLE ONLY "public"."claim_split_requests"
    ADD CONSTRAINT "claim_split_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."claims"
    ADD CONSTRAINT "claims_item_id_claimer_id_key" UNIQUE ("item_id", "claimer_id");



ALTER TABLE ONLY "public"."claims"
    ADD CONSTRAINT "claims_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."daily_activity_log"
    ADD CONSTRAINT "daily_activity_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."event_invites"
    ADD CONSTRAINT "event_invites_event_id_invitee_email_key" UNIQUE ("event_id", "invitee_email");



ALTER TABLE ONLY "public"."event_invites"
    ADD CONSTRAINT "event_invites_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."event_member_stats"
    ADD CONSTRAINT "event_member_stats_pkey" PRIMARY KEY ("event_id", "user_id");



ALTER TABLE ONLY "public"."event_members"
    ADD CONSTRAINT "event_members_pkey" PRIMARY KEY ("event_id", "user_id");



ALTER TABLE ONLY "public"."events"
    ADD CONSTRAINT "events_join_code_key" UNIQUE ("join_code");



ALTER TABLE ONLY "public"."events"
    ADD CONSTRAINT "events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."items"
    ADD CONSTRAINT "items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."list_exclusions"
    ADD CONSTRAINT "list_exclusions_pkey" PRIMARY KEY ("list_id", "user_id");



ALTER TABLE ONLY "public"."list_recipients"
    ADD CONSTRAINT "list_recipients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."list_viewers"
    ADD CONSTRAINT "list_viewers_pkey" PRIMARY KEY ("list_id", "user_id");



ALTER TABLE ONLY "public"."lists"
    ADD CONSTRAINT "lists_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_queue"
    ADD CONSTRAINT "notification_queue_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."orphaned_lists"
    ADD CONSTRAINT "orphaned_lists_list_id_excluded_user_id_key" UNIQUE ("list_id", "excluded_user_id");



ALTER TABLE ONLY "public"."orphaned_lists"
    ADD CONSTRAINT "orphaned_lists_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."rate_limit_tracking"
    ADD CONSTRAINT "rate_limit_tracking_pkey" PRIMARY KEY ("user_id", "action", "window_start");



ALTER TABLE ONLY "public"."security_audit_log"
    ADD CONSTRAINT "security_audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sent_reminders"
    ADD CONSTRAINT "sent_reminders_claim_id_event_id_key" UNIQUE ("claim_id", "event_id");



ALTER TABLE ONLY "public"."sent_reminders"
    ADD CONSTRAINT "sent_reminders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_plans"
    ADD CONSTRAINT "user_plans_pkey" PRIMARY KEY ("user_id");



CREATE UNIQUE INDEX "claim_split_requests_pending_unique" ON "public"."claim_split_requests" USING "btree" ("item_id", "requester_id", "original_claimer_id") WHERE ("status" = 'pending'::"text");



CREATE INDEX "idx_claim_split_requests_item" ON "public"."claim_split_requests" USING "btree" ("item_id");



CREATE INDEX "idx_claim_split_requests_original_claimer" ON "public"."claim_split_requests" USING "btree" ("original_claimer_id") WHERE ("status" = 'pending'::"text");



CREATE INDEX "idx_claims_assigned_to" ON "public"."claims" USING "btree" ("assigned_to");



CREATE INDEX "idx_claims_assigned_to_item" ON "public"."claims" USING "btree" ("assigned_to", "item_id") WHERE ("assigned_to" IS NOT NULL);



COMMENT ON INDEX "public"."idx_claims_assigned_to_item" IS 'Composite index for random assignment queries checking who is assigned to items.';



CREATE INDEX "idx_claims_claimer_id" ON "public"."claims" USING "btree" ("claimer_id");



CREATE INDEX "idx_claims_claimer_item" ON "public"."claims" USING "btree" ("claimer_id", "item_id");



CREATE INDEX "idx_claims_claimer_purchased" ON "public"."claims" USING "btree" ("claimer_id", "purchased");



COMMENT ON INDEX "public"."idx_claims_claimer_purchased" IS 'Composite index for calculating unpurchased claims per user.';



CREATE INDEX "idx_claims_item_id" ON "public"."claims" USING "btree" ("item_id");



CREATE INDEX "idx_daily_activity_log_event" ON "public"."daily_activity_log" USING "btree" ("event_id", "created_at");



CREATE INDEX "idx_daily_activity_log_user_date" ON "public"."daily_activity_log" USING "btree" ("user_id", "created_at");



CREATE INDEX "idx_event_invites_email_status" ON "public"."event_invites" USING "btree" ("invitee_email", "status") WHERE ("status" = 'pending'::"text");



COMMENT ON INDEX "public"."idx_event_invites_email_status" IS 'Partial index for finding pending invites by email.';



CREATE INDEX "idx_event_invites_event_id" ON "public"."event_invites" USING "btree" ("event_id");



CREATE INDEX "idx_event_invites_invitee_email" ON "public"."event_invites" USING "btree" ("invitee_email");



CREATE INDEX "idx_event_invites_invitee_id" ON "public"."event_invites" USING "btree" ("invitee_id");



CREATE INDEX "idx_event_invites_inviter_id" ON "public"."event_invites" USING "btree" ("inviter_id");



CREATE INDEX "idx_event_invites_status" ON "public"."event_invites" USING "btree" ("status");



CREATE INDEX "idx_event_member_stats_covering" ON "public"."event_member_stats" USING "btree" ("user_id", "event_id") INCLUDE ("total_claims", "unpurchased_claims");



COMMENT ON INDEX "public"."idx_event_member_stats_covering" IS 'Covering index allowing index-only scans for user claim stats.';



CREATE INDEX "idx_event_member_stats_event" ON "public"."event_member_stats" USING "btree" ("event_id");



CREATE INDEX "idx_event_member_stats_updated" ON "public"."event_member_stats" USING "btree" ("updated_at");



CREATE INDEX "idx_event_member_stats_user" ON "public"."event_member_stats" USING "btree" ("user_id");



CREATE INDEX "idx_event_members_composite_rls" ON "public"."event_members" USING "btree" ("event_id", "user_id", "role") WHERE ("role" IS NOT NULL);



COMMENT ON INDEX "public"."idx_event_members_composite_rls" IS 'Composite index for RLS policies checking admin/member status. Covers most common RLS pattern.';



CREATE INDEX "idx_event_members_event_id" ON "public"."event_members" USING "btree" ("event_id");



CREATE INDEX "idx_event_members_event_user_role" ON "public"."event_members" USING "btree" ("event_id", "user_id", "role");



CREATE INDEX "idx_event_members_user_id" ON "public"."event_members" USING "btree" ("user_id");



CREATE INDEX "idx_events_id_owner" ON "public"."events" USING "btree" ("id", "owner_id");



CREATE INDEX "idx_events_owner_id" ON "public"."events" USING "btree" ("owner_id");



COMMENT ON INDEX "public"."idx_events_owner_id" IS 'Index for checking event ownership in RLS policies.';



CREATE INDEX "idx_items_assigned_recipient_id" ON "public"."items" USING "btree" ("assigned_recipient_id");



CREATE INDEX "idx_items_created_by" ON "public"."items" USING "btree" ("created_by");



COMMENT ON INDEX "public"."idx_items_created_by" IS 'Index for checking item ownership and creator.';



CREATE INDEX "idx_items_list_id" ON "public"."items" USING "btree" ("list_id");



CREATE INDEX "idx_items_list_recipient_composite" ON "public"."items" USING "btree" ("list_id", "assigned_recipient_id") WHERE ("assigned_recipient_id" IS NOT NULL);



COMMENT ON INDEX "public"."idx_items_list_recipient_composite" IS 'Composite index for random receiver assignment queries.';



CREATE INDEX "idx_list_exclusions_composite" ON "public"."list_exclusions" USING "btree" ("list_id", "user_id");



COMMENT ON INDEX "public"."idx_list_exclusions_composite" IS 'Composite index for checking if user is excluded from a list.';



CREATE INDEX "idx_list_exclusions_uid" ON "public"."list_exclusions" USING "btree" ("user_id");



CREATE INDEX "idx_list_recipients_composite" ON "public"."list_recipients" USING "btree" ("list_id", "user_id") WHERE ("user_id" IS NOT NULL);



COMMENT ON INDEX "public"."idx_list_recipients_composite" IS 'Composite index for checking recipient status in RLS policies and queries.';



CREATE INDEX "idx_list_recipients_list_user" ON "public"."list_recipients" USING "btree" ("list_id", "user_id");



CREATE INDEX "idx_list_recipients_uid" ON "public"."list_recipients" USING "btree" ("user_id");



CREATE INDEX "idx_list_viewers_uid" ON "public"."list_viewers" USING "btree" ("user_id");



CREATE INDEX "idx_lists_composite_joins" ON "public"."lists" USING "btree" ("id", "event_id", "created_by");



COMMENT ON INDEX "public"."idx_lists_composite_joins" IS 'Composite index covering most common list JOIN patterns and WHERE clauses.';



CREATE INDEX "idx_lists_created_by" ON "public"."lists" USING "btree" ("created_by");



CREATE INDEX "idx_lists_event_id" ON "public"."lists" USING "btree" ("event_id");



CREATE INDEX "idx_lists_random_assignment_enabled" ON "public"."lists" USING "btree" ("random_assignment_enabled") WHERE ("random_assignment_enabled" = true);



CREATE INDEX "idx_lists_random_modes" ON "public"."lists" USING "btree" ("event_id", "random_assignment_enabled", "random_receiver_assignment_enabled");



COMMENT ON INDEX "public"."idx_lists_random_modes" IS 'Composite index for queries filtering by random assignment modes.';



CREATE INDEX "idx_lists_random_receiver_assignment_enabled" ON "public"."lists" USING "btree" ("random_receiver_assignment_enabled") WHERE ("random_receiver_assignment_enabled" = true);



CREATE INDEX "idx_notification_queue_sent" ON "public"."notification_queue" USING "btree" ("sent", "created_at");



CREATE INDEX "idx_notification_queue_user_id" ON "public"."notification_queue" USING "btree" ("user_id");



CREATE INDEX "idx_orphaned_lists_delete_at" ON "public"."orphaned_lists" USING "btree" ("delete_at");



CREATE INDEX "idx_orphaned_lists_list_id" ON "public"."orphaned_lists" USING "btree" ("list_id");



CREATE INDEX "idx_profiles_currency" ON "public"."profiles" USING "btree" ("currency");



CREATE INDEX "idx_profiles_id_display_name" ON "public"."profiles" USING "btree" ("id") INCLUDE ("display_name");



COMMENT ON INDEX "public"."idx_profiles_id_display_name" IS 'Covering index for profile lookups in optimized events_for_current_user. Enables index-only scans.';



CREATE INDEX "idx_push_tokens_user_id" ON "public"."push_tokens" USING "btree" ("user_id");



CREATE INDEX "idx_rate_limit_tracking_window" ON "public"."rate_limit_tracking" USING "btree" ("window_start");



CREATE INDEX "idx_security_audit_log_action_created" ON "public"."security_audit_log" USING "btree" ("action", "created_at" DESC);



CREATE INDEX "idx_security_audit_log_created" ON "public"."security_audit_log" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_security_audit_log_user_created" ON "public"."security_audit_log" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_sent_reminders_claim_event" ON "public"."sent_reminders" USING "btree" ("claim_id", "event_id");



CREATE INDEX "idx_sent_reminders_event_id" ON "public"."sent_reminders" USING "btree" ("event_id");



CREATE INDEX "idx_sent_reminders_user_id" ON "public"."sent_reminders" USING "btree" ("user_id");



CREATE UNIQUE INDEX "list_recipients_email_unique" ON "public"."list_recipients" USING "btree" ("list_id", "lower"("recipient_email")) WHERE ("recipient_email" IS NOT NULL);



CREATE UNIQUE INDEX "list_recipients_user_unique" ON "public"."list_recipients" USING "btree" ("list_id", "user_id") WHERE ("user_id" IS NOT NULL);



CREATE OR REPLACE TRIGGER "link_invites_on_profile_insert" AFTER INSERT ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_invites_on_user_signup"();



CREATE OR REPLACE TRIGGER "set_timestamp" BEFORE UPDATE ON "public"."user_plans" FOR EACH ROW EXECUTE FUNCTION "public"."tg_set_timestamp"();



CREATE OR REPLACE TRIGGER "trg_autojoin_event" AFTER INSERT ON "public"."events" FOR EACH ROW EXECUTE FUNCTION "public"."autojoin_event_as_admin"();



CREATE OR REPLACE TRIGGER "trg_ensure_event_owner_member" AFTER INSERT ON "public"."events" FOR EACH ROW EXECUTE FUNCTION "public"."ensure_event_owner_member"();



CREATE OR REPLACE TRIGGER "trg_set_list_created_by" BEFORE INSERT ON "public"."lists" FOR EACH ROW EXECUTE FUNCTION "public"."set_list_created_by"();



CREATE OR REPLACE TRIGGER "trigger_cleanup_reminder_on_purchase" AFTER UPDATE ON "public"."claims" FOR EACH ROW WHEN ((("new"."purchased" = true) AND ("old"."purchased" = false))) EXECUTE FUNCTION "public"."cleanup_reminder_on_purchase"();



CREATE OR REPLACE TRIGGER "trigger_initialize_event_member_stats" AFTER INSERT ON "public"."event_members" FOR EACH ROW EXECUTE FUNCTION "public"."initialize_event_member_stats"();



CREATE OR REPLACE TRIGGER "trigger_link_recipients_on_signup" AFTER INSERT ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."link_list_recipients_on_signup"();



CREATE OR REPLACE TRIGGER "trigger_mark_orphaned_lists" AFTER DELETE ON "public"."event_members" FOR EACH ROW EXECUTE FUNCTION "public"."mark_orphaned_lists_for_deletion"();



CREATE OR REPLACE TRIGGER "trigger_unmark_orphaned_lists" AFTER INSERT ON "public"."event_members" FOR EACH ROW EXECUTE FUNCTION "public"."unmark_orphaned_lists_on_member_join"();



CREATE OR REPLACE TRIGGER "trigger_update_event_member_stats_on_claim" AFTER INSERT OR DELETE OR UPDATE ON "public"."claims" FOR EACH ROW EXECUTE FUNCTION "public"."update_event_member_stats_on_claim_change"();



CREATE OR REPLACE TRIGGER "trigger_update_event_member_stats_on_list_event" AFTER UPDATE ON "public"."lists" FOR EACH ROW WHEN (("old"."event_id" IS DISTINCT FROM "new"."event_id")) EXECUTE FUNCTION "public"."update_event_member_stats_on_list_event_change"();



CREATE OR REPLACE TRIGGER "trigger_update_event_member_stats_on_recipient" AFTER INSERT OR DELETE OR UPDATE ON "public"."list_recipients" FOR EACH ROW EXECUTE FUNCTION "public"."update_event_member_stats_on_recipient_change"();



CREATE OR REPLACE TRIGGER "trigger_update_invites_on_signup" AFTER INSERT ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_invites_on_user_signup"();



ALTER TABLE ONLY "public"."claim_split_requests"
    ADD CONSTRAINT "claim_split_requests_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "public"."items"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."claim_split_requests"
    ADD CONSTRAINT "claim_split_requests_original_claimer_id_fkey" FOREIGN KEY ("original_claimer_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."claim_split_requests"
    ADD CONSTRAINT "claim_split_requests_requester_id_fkey" FOREIGN KEY ("requester_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."claims"
    ADD CONSTRAINT "claims_assigned_to_fkey" FOREIGN KEY ("assigned_to") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."claims"
    ADD CONSTRAINT "claims_claimer_id_fkey" FOREIGN KEY ("claimer_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."claims"
    ADD CONSTRAINT "claims_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "public"."items"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_activity_log"
    ADD CONSTRAINT "daily_activity_log_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_activity_log"
    ADD CONSTRAINT "daily_activity_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_invites"
    ADD CONSTRAINT "event_invites_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_invites"
    ADD CONSTRAINT "event_invites_invitee_id_fkey" FOREIGN KEY ("invitee_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_invites"
    ADD CONSTRAINT "event_invites_inviter_id_fkey" FOREIGN KEY ("inviter_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_member_stats"
    ADD CONSTRAINT "event_member_stats_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_member_stats"
    ADD CONSTRAINT "event_member_stats_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_members"
    ADD CONSTRAINT "event_members_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_members"
    ADD CONSTRAINT "event_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."events"
    ADD CONSTRAINT "events_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."claims"
    ADD CONSTRAINT "fk_claims_assigned_to" FOREIGN KEY ("assigned_to") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."claims"
    ADD CONSTRAINT "fk_claims_claimer_id" FOREIGN KEY ("claimer_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."claims"
    ADD CONSTRAINT "fk_claims_item_id" FOREIGN KEY ("item_id") REFERENCES "public"."items"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_activity_log"
    ADD CONSTRAINT "fk_daily_activity_log_event_id" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_activity_log"
    ADD CONSTRAINT "fk_daily_activity_log_user_id" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_invites"
    ADD CONSTRAINT "fk_event_invites_event_id" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_invites"
    ADD CONSTRAINT "fk_event_invites_invitee_id" FOREIGN KEY ("invitee_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_invites"
    ADD CONSTRAINT "fk_event_invites_inviter_id" FOREIGN KEY ("inviter_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_members"
    ADD CONSTRAINT "fk_event_members_event_id" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_members"
    ADD CONSTRAINT "fk_event_members_user_id" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."events"
    ADD CONSTRAINT "fk_events_owner_id" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."items"
    ADD CONSTRAINT "fk_items_assigned_recipient_id" FOREIGN KEY ("assigned_recipient_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."items"
    ADD CONSTRAINT "fk_items_created_by" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."items"
    ADD CONSTRAINT "fk_items_list_id" FOREIGN KEY ("list_id") REFERENCES "public"."lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."list_exclusions"
    ADD CONSTRAINT "fk_list_exclusions_list_id" FOREIGN KEY ("list_id") REFERENCES "public"."lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."list_exclusions"
    ADD CONSTRAINT "fk_list_exclusions_user_id" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."list_recipients"
    ADD CONSTRAINT "fk_list_recipients_list_id" FOREIGN KEY ("list_id") REFERENCES "public"."lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."list_recipients"
    ADD CONSTRAINT "fk_list_recipients_user_id" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."list_viewers"
    ADD CONSTRAINT "fk_list_viewers_list_id" FOREIGN KEY ("list_id") REFERENCES "public"."lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."list_viewers"
    ADD CONSTRAINT "fk_list_viewers_user_id" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lists"
    ADD CONSTRAINT "fk_lists_created_by" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."lists"
    ADD CONSTRAINT "fk_lists_event_id" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_queue"
    ADD CONSTRAINT "fk_notification_queue_user_id" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orphaned_lists"
    ADD CONSTRAINT "fk_orphaned_lists_event_id" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orphaned_lists"
    ADD CONSTRAINT "fk_orphaned_lists_excluded_user_id" FOREIGN KEY ("excluded_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orphaned_lists"
    ADD CONSTRAINT "fk_orphaned_lists_list_id" FOREIGN KEY ("list_id") REFERENCES "public"."lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "fk_push_tokens_user_id" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sent_reminders"
    ADD CONSTRAINT "fk_sent_reminders_claim_id" FOREIGN KEY ("claim_id") REFERENCES "public"."claims"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sent_reminders"
    ADD CONSTRAINT "fk_sent_reminders_event_id" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sent_reminders"
    ADD CONSTRAINT "fk_sent_reminders_user_id" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_plans"
    ADD CONSTRAINT "fk_user_plans_user_id" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."items"
    ADD CONSTRAINT "items_assigned_recipient_id_fkey" FOREIGN KEY ("assigned_recipient_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."items"
    ADD CONSTRAINT "items_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."items"
    ADD CONSTRAINT "items_list_id_fkey" FOREIGN KEY ("list_id") REFERENCES "public"."lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."list_exclusions"
    ADD CONSTRAINT "list_exclusions_list_id_fkey" FOREIGN KEY ("list_id") REFERENCES "public"."lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."list_exclusions"
    ADD CONSTRAINT "list_exclusions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."list_recipients"
    ADD CONSTRAINT "list_recipients_list_id_fkey" FOREIGN KEY ("list_id") REFERENCES "public"."lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."list_recipients"
    ADD CONSTRAINT "list_recipients_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."list_viewers"
    ADD CONSTRAINT "list_viewers_list_id_fkey" FOREIGN KEY ("list_id") REFERENCES "public"."lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."list_viewers"
    ADD CONSTRAINT "list_viewers_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lists"
    ADD CONSTRAINT "lists_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lists"
    ADD CONSTRAINT "lists_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_queue"
    ADD CONSTRAINT "notification_queue_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orphaned_lists"
    ADD CONSTRAINT "orphaned_lists_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orphaned_lists"
    ADD CONSTRAINT "orphaned_lists_excluded_user_id_fkey" FOREIGN KEY ("excluded_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orphaned_lists"
    ADD CONSTRAINT "orphaned_lists_list_id_fkey" FOREIGN KEY ("list_id") REFERENCES "public"."lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."security_audit_log"
    ADD CONSTRAINT "security_audit_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sent_reminders"
    ADD CONSTRAINT "sent_reminders_claim_id_fkey" FOREIGN KEY ("claim_id") REFERENCES "public"."claims"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sent_reminders"
    ADD CONSTRAINT "sent_reminders_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sent_reminders"
    ADD CONSTRAINT "sent_reminders_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_plans"
    ADD CONSTRAINT "user_plans_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "No public access to activity log" ON "public"."daily_activity_log" USING (false);



CREATE POLICY "No public access to notification queue" ON "public"."notification_queue" USING (false);



CREATE POLICY "No public access to sent_reminders" ON "public"."sent_reminders" USING (false) WITH CHECK (false);



CREATE POLICY "Original claimers can update split requests" ON "public"."claim_split_requests" FOR UPDATE USING (("original_claimer_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Requesters can delete their pending requests" ON "public"."claim_split_requests" FOR DELETE USING ((("requester_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("status" = 'pending'::"text")));



CREATE POLICY "Users can create split requests" ON "public"."claim_split_requests" FOR INSERT WITH CHECK (("requester_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can delete own tokens" ON "public"."push_tokens" FOR DELETE USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can insert own tokens" ON "public"."push_tokens" FOR INSERT WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can update own tokens" ON "public"."push_tokens" FOR UPDATE USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can view own tokens" ON "public"."push_tokens" FOR SELECT USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can view their split requests" ON "public"."claim_split_requests" FOR SELECT USING ((("requester_id" = ( SELECT "auth"."uid"() AS "uid")) OR ("original_claimer_id" = ( SELECT "auth"."uid"() AS "uid"))));



CREATE POLICY "admins can delete any claims" ON "public"."claims" FOR DELETE USING ("public"."is_event_admin"("public"."event_id_for_item"("item_id"), ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "admins can delete events" ON "public"."events" FOR DELETE USING ("public"."is_event_admin"("id", ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."claim_split_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."claims" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "claims_delete_admins" ON "public"."claims" AS RESTRICTIVE FOR DELETE TO "authenticated" USING ("public"."is_event_admin"("public"."event_id_for_item"("item_id")));



CREATE POLICY "claims_select_visible" ON "public"."claims" FOR SELECT USING ("public"."can_view_list"("public"."list_id_for_item"("item_id"), ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "claims_update_by_claimer" ON "public"."claims" FOR UPDATE USING ((( SELECT "auth"."uid"() AS "uid") = "claimer_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "claimer_id"));



CREATE POLICY "claims_update_own" ON "public"."claims" FOR UPDATE USING ((( SELECT "auth"."uid"() AS "uid") = "claimer_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "claimer_id"));



ALTER TABLE "public"."daily_activity_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "delete events by owner or last member" ON "public"."events" FOR DELETE USING ((("owner_id" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."is_last_event_member"("id", ( SELECT "auth"."uid"() AS "uid"))));



CREATE POLICY "delete items by creator or last member" ON "public"."items" FOR DELETE USING ((("created_by" = ( SELECT "auth"."uid"() AS "uid")) OR (EXISTS ( SELECT 1
   FROM "public"."lists" "l"
  WHERE (("l"."id" = "items"."list_id") AND (("l"."created_by" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."is_last_event_member"("l"."event_id", ( SELECT "auth"."uid"() AS "uid"))))))));



CREATE POLICY "delete list_recipients by creator or last member" ON "public"."list_recipients" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."lists" "l"
  WHERE (("l"."id" = "list_recipients"."list_id") AND (("l"."created_by" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."is_last_event_member"("l"."event_id", ( SELECT "auth"."uid"() AS "uid")))))));



CREATE POLICY "delete lists by creator or last member" ON "public"."lists" FOR DELETE USING ((("created_by" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."is_last_event_member"("event_id", ( SELECT "auth"."uid"() AS "uid"))));



CREATE POLICY "delete own claims" ON "public"."claims" FOR DELETE USING (("claimer_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "delete own event membership" ON "public"."event_members" FOR DELETE USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."event_invites" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "event_invites_delete" ON "public"."event_invites" FOR DELETE USING (((( SELECT "auth"."uid"() AS "uid") = "inviter_id") OR (EXISTS ( SELECT 1
   FROM "public"."event_members" "em"
  WHERE (("em"."event_id" = "event_invites"."event_id") AND ("em"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("em"."role" = 'admin'::"public"."member_role"))))));



CREATE POLICY "event_invites_insert" ON "public"."event_invites" FOR INSERT WITH CHECK (((( SELECT "auth"."uid"() AS "uid") = "inviter_id") AND (EXISTS ( SELECT 1
   FROM "public"."event_members" "em"
  WHERE (("em"."event_id" = "event_invites"."event_id") AND ("em"."user_id" = ( SELECT "auth"."uid"() AS "uid")))))));



CREATE POLICY "event_invites_select" ON "public"."event_invites" FOR SELECT USING (((( SELECT "auth"."uid"() AS "uid") = "inviter_id") OR (( SELECT "auth"."uid"() AS "uid") = "invitee_id") OR (EXISTS ( SELECT 1
   FROM "public"."event_members" "em"
  WHERE (("em"."event_id" = "event_invites"."event_id") AND ("em"."user_id" = ( SELECT "auth"."uid"() AS "uid")))))));



CREATE POLICY "event_invites_update" ON "public"."event_invites" FOR UPDATE USING ((( SELECT "auth"."uid"() AS "uid") = "invitee_id"));



ALTER TABLE "public"."event_member_stats" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "event_member_stats_no_delete" ON "public"."event_member_stats" FOR DELETE USING (false);



CREATE POLICY "event_member_stats_no_insert" ON "public"."event_member_stats" FOR INSERT WITH CHECK (false);



CREATE POLICY "event_member_stats_no_update" ON "public"."event_member_stats" FOR UPDATE USING (false);



CREATE POLICY "event_member_stats_select" ON "public"."event_member_stats" FOR SELECT USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."event_members" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "event_members_select" ON "public"."event_members" FOR SELECT USING ("public"."is_member_of_event"("event_id", ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "events: update by admins" ON "public"."events" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."event_members" "em"
  WHERE (("em"."event_id" = "events"."id") AND ("em"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("em"."role" = 'admin'::"public"."member_role"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."event_members" "em"
  WHERE (("em"."event_id" = "events"."id") AND ("em"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("em"."role" = 'admin'::"public"."member_role")))));



CREATE POLICY "insert events when owner is self" ON "public"."events" FOR INSERT WITH CHECK (("owner_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "insert list_recipients by creator" ON "public"."list_recipients" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."lists" "l"
  WHERE (("l"."id" = "list_recipients"."list_id") AND ("l"."created_by" = ( SELECT "auth"."uid"() AS "uid"))))));



ALTER TABLE "public"."items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "items_select_with_receiver_assignment" ON "public"."items" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."lists" "l"
     JOIN "public"."event_members" "em" ON (("em"."event_id" = "l"."event_id")))
  WHERE (("l"."id" = "items"."list_id") AND ("em"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND "public"."can_view_list"("l"."id", ( SELECT "auth"."uid"() AS "uid")) AND ((("l"."random_assignment_enabled" = true) AND ("l"."random_receiver_assignment_enabled" = true)) OR ("l"."created_by" = ( SELECT "auth"."uid"() AS "uid")) OR ("em"."role" = 'admin'::"public"."member_role") OR (EXISTS ( SELECT 1
           FROM "public"."events" "e"
          WHERE (("e"."id" = "l"."event_id") AND ("e"."owner_id" = ( SELECT "auth"."uid"() AS "uid"))))) OR (("l"."random_assignment_enabled" = true) AND (COALESCE("l"."random_receiver_assignment_enabled", false) = false) AND (EXISTS ( SELECT 1
           FROM "public"."claims" "c"
          WHERE (("c"."item_id" = "items"."id") AND ("c"."assigned_to" = ( SELECT "auth"."uid"() AS "uid")))))) OR ((COALESCE("l"."random_assignment_enabled", false) = false) AND ("l"."random_receiver_assignment_enabled" = true) AND ("items"."assigned_recipient_id" <> ( SELECT "auth"."uid"() AS "uid"))) OR ((COALESCE("l"."random_assignment_enabled", false) = false) AND (COALESCE("l"."random_receiver_assignment_enabled", false) = false)))))));



CREATE POLICY "le_select" ON "public"."list_exclusions" FOR SELECT USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."list_exclusions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "list_exclusions_delete" ON "public"."list_exclusions" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."lists" "l"
  WHERE (("l"."id" = "list_exclusions"."list_id") AND (("l"."created_by" = ( SELECT "auth"."uid"() AS "uid")) OR (EXISTS ( SELECT 1
           FROM "public"."event_members" "em"
          WHERE (("em"."event_id" = "l"."event_id") AND ("em"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("em"."role" = 'admin'::"public"."member_role")))))))));



CREATE POLICY "list_exclusions_insert" ON "public"."list_exclusions" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."lists" "l"
  WHERE (("l"."id" = "list_exclusions"."list_id") AND ("l"."created_by" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "list_exclusions_select" ON "public"."list_exclusions" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."lists" "l"
  WHERE (("l"."id" = "list_exclusions"."list_id") AND ("l"."created_by" = ( SELECT "auth"."uid"() AS "uid"))))) OR ("user_id" = ( SELECT "auth"."uid"() AS "uid"))));



ALTER TABLE "public"."list_recipients" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "list_recipients_insert" ON "public"."list_recipients" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."lists" "l"
  WHERE (("l"."id" = "list_recipients"."list_id") AND ("l"."created_by" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "list_recipients_select" ON "public"."list_recipients" FOR SELECT USING ("public"."can_view_list"("list_id", ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."list_viewers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."lists" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "lists_delete_admins" ON "public"."lists" AS RESTRICTIVE FOR DELETE TO "authenticated" USING ("public"."is_event_admin"("event_id"));



CREATE POLICY "lists_insert" ON "public"."lists" AS RESTRICTIVE FOR INSERT TO "authenticated" WITH CHECK ("public"."is_event_member"("event_id"));



CREATE POLICY "lists_select_visible" ON "public"."lists" FOR SELECT USING ("public"."can_view_list"("id", ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "lv_select" ON "public"."list_viewers" FOR SELECT USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "members can insert items into their event lists" ON "public"."items" FOR INSERT WITH CHECK (((( SELECT "auth"."role"() AS "role") = 'authenticated'::"text") AND ("created_by" = ( SELECT "auth"."uid"() AS "uid")) AND (EXISTS ( SELECT 1
   FROM ("public"."lists" "l"
     JOIN "public"."event_members" "em" ON (("em"."event_id" = "l"."event_id")))
  WHERE (("l"."id" = "items"."list_id") AND ("em"."user_id" = ( SELECT "auth"."uid"() AS "uid")))))));



CREATE POLICY "no_client_writes" ON "public"."user_plans" TO "authenticated" USING (false) WITH CHECK (false);



ALTER TABLE "public"."notification_queue" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."orphaned_lists" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "orphaned_lists_select" ON "public"."orphaned_lists" FOR SELECT USING (false);



CREATE POLICY "owners can delete events" ON "public"."events" FOR DELETE USING (("owner_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles are readable by logged in users" ON "public"."profiles" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."push_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rate_limit_tracking" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "rate_limit_tracking_no_public_access" ON "public"."rate_limit_tracking" USING (false) WITH CHECK (false);



COMMENT ON POLICY "rate_limit_tracking_no_public_access" ON "public"."rate_limit_tracking" IS 'Rate limit tracking is only accessible via SECURITY DEFINER functions. No direct user access allowed.';



CREATE POLICY "read_own_plan" ON "public"."user_plans" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."security_audit_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "security_audit_log_no_public_access" ON "public"."security_audit_log" USING (false);



CREATE POLICY "select events for members" ON "public"."events" FOR SELECT USING ("public"."is_event_member"("id", ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "select events for owners" ON "public"."events" FOR SELECT USING (("owner_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."sent_reminders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "server-side insert when id exists in auth.users" ON "public"."profiles" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "auth"."users" "u"
  WHERE ("u"."id" = "profiles"."id"))));



CREATE POLICY "update events by owner or last member" ON "public"."events" FOR UPDATE USING ((("owner_id" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."is_last_event_member"("id", ( SELECT "auth"."uid"() AS "uid")))) WITH CHECK ((("owner_id" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."is_last_event_member"("id", ( SELECT "auth"."uid"() AS "uid"))));



CREATE POLICY "update items by creator or last member" ON "public"."items" FOR UPDATE USING ((("created_by" = ( SELECT "auth"."uid"() AS "uid")) OR (EXISTS ( SELECT 1
   FROM "public"."lists" "l"
  WHERE (("l"."id" = "items"."list_id") AND (("l"."created_by" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."is_last_event_member"("l"."event_id", ( SELECT "auth"."uid"() AS "uid"))))))));



CREATE POLICY "update list_recipients by creator or last member" ON "public"."list_recipients" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."lists" "l"
  WHERE (("l"."id" = "list_recipients"."list_id") AND (("l"."created_by" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."is_last_event_member"("l"."event_id", ( SELECT "auth"."uid"() AS "uid")))))));



CREATE POLICY "update lists by creator or last member" ON "public"."lists" FOR UPDATE USING ((("created_by" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."is_last_event_member"("event_id", ( SELECT "auth"."uid"() AS "uid"))));



ALTER TABLE "public"."user_plans" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_plans_self" ON "public"."user_plans" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "users can insert their own profile" ON "public"."profiles" FOR INSERT WITH CHECK (("id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "users can update their own profile" ON "public"."profiles" FOR UPDATE USING (("id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("id" = ( SELECT "auth"."uid"() AS "uid")));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."claims";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."event_members";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."events";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."items";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."list_recipients";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."lists";






GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";







































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































GRANT ALL ON FUNCTION "public"."_next_occurrence"("p_date" "date", "p_freq" "text", "p_interval" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."_next_occurrence"("p_date" "date", "p_freq" "text", "p_interval" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_next_occurrence"("p_date" "date", "p_freq" "text", "p_interval" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."_pick_new_admin"("p_event_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."_pick_new_admin"("p_event_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_pick_new_admin"("p_event_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."_test_admin_for_event_title"("p_title" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_test_admin_for_event_title"("p_title" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_test_admin_for_event_title"("p_title" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_test_admin_for_event_title"("p_title" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."_test_any_member_for_event_title"("p_title" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_test_any_member_for_event_title"("p_title" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_test_any_member_for_event_title"("p_title" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_test_any_member_for_event_title"("p_title" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."_test_create_list_for_event"("p_event_id" "uuid", "p_name" "text", "p_vis" "public"."list_visibility") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_test_create_list_for_event"("p_event_id" "uuid", "p_name" "text", "p_vis" "public"."list_visibility") TO "anon";
GRANT ALL ON FUNCTION "public"."_test_create_list_for_event"("p_event_id" "uuid", "p_name" "text", "p_vis" "public"."list_visibility") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_test_create_list_for_event"("p_event_id" "uuid", "p_name" "text", "p_vis" "public"."list_visibility") TO "service_role";



GRANT ALL ON FUNCTION "public"."accept_claim_split"("p_request_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."accept_claim_split"("p_request_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_claim_split"("p_request_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."accept_event_invite"("p_invite_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."accept_event_invite"("p_invite_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_event_invite"("p_invite_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."add_list_recipient"("p_list_id" "uuid", "p_recipient_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."add_list_recipient"("p_list_id" "uuid", "p_recipient_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_list_recipient"("p_list_id" "uuid", "p_recipient_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."allowed_event_slots"("p_user" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."allowed_event_slots"("p_user" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."allowed_event_slots"("p_user" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."assign_items_randomly"("p_list_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."assign_items_randomly"("p_list_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_items_randomly"("p_list_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."autojoin_event_as_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."autojoin_event_as_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."autojoin_event_as_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."backfill_event_member_stats"() TO "anon";
GRANT ALL ON FUNCTION "public"."backfill_event_member_stats"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."backfill_event_member_stats"() TO "service_role";



GRANT ALL ON FUNCTION "public"."can_claim_item"("p_item_id" "uuid", "p_user" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can_claim_item"("p_item_id" "uuid", "p_user" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_claim_item"("p_item_id" "uuid", "p_user" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."can_create_event"("p_user" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can_create_event"("p_user" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_create_event"("p_user" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."can_join_event"("p_user" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can_join_event"("p_user" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_join_event"("p_user" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."can_view_list"("p_list" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can_view_list"("p_list" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_view_list"("p_list" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."can_view_list"("uuid", "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can_view_list"("uuid", "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_view_list"("uuid", "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_and_queue_purchase_reminders"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_and_queue_purchase_reminders"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_and_queue_purchase_reminders"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_rate_limit"("p_action" "text", "p_max_requests" integer, "p_window_seconds" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."check_rate_limit"("p_action" "text", "p_max_requests" integer, "p_window_seconds" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_rate_limit"("p_action" "text", "p_max_requests" integer, "p_window_seconds" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."claim_counts_for_lists"("p_list_ids" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_counts_for_lists"("p_list_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."claim_counts_for_lists"("p_list_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."claim_counts_for_lists"("p_list_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."claim_item"("p_item_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."claim_item"("p_item_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."claim_item"("p_item_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_old_activity_logs"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_old_activity_logs"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_old_activity_logs"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_old_invites"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_old_invites"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_old_invites"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_old_notifications"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_old_notifications"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_old_notifications"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_old_reminders"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_old_reminders"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_old_reminders"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_orphaned_lists"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_orphaned_lists"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_orphaned_lists"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_rate_limit_tracking"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_rate_limit_tracking"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_rate_limit_tracking"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_reminder_on_purchase"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_reminder_on_purchase"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_reminder_on_purchase"() TO "service_role";



GRANT ALL ON FUNCTION "public"."create_event_and_admin"("p_title" "text", "p_event_date" "date", "p_recurrence" "text", "p_description" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_event_and_admin"("p_title" "text", "p_event_date" "date", "p_recurrence" "text", "p_description" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_event_and_admin"("p_title" "text", "p_event_date" "date", "p_recurrence" "text", "p_description" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_event_and_admin"("p_title" "text", "p_event_date" "date", "p_recurrence" "text", "p_description" "text", "p_admin_only_invites" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."create_event_and_admin"("p_title" "text", "p_event_date" "date", "p_recurrence" "text", "p_description" "text", "p_admin_only_invites" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_event_and_admin"("p_title" "text", "p_event_date" "date", "p_recurrence" "text", "p_description" "text", "p_admin_only_invites" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_event_and_admin"("p_title" "text", "p_event_date" "date", "p_recurrence" "text", "p_description" "text", "p_admin_only_invites" boolean, "p_admin_emails" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."create_event_and_admin"("p_title" "text", "p_event_date" "date", "p_recurrence" "text", "p_description" "text", "p_admin_only_invites" boolean, "p_admin_emails" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_event_and_admin"("p_title" "text", "p_event_date" "date", "p_recurrence" "text", "p_description" "text", "p_admin_only_invites" boolean, "p_admin_emails" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_viewers" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_viewers" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_viewers" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[], "p_custom_recipient_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[], "p_custom_recipient_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[], "p_custom_recipient_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "text", "p_custom_recipient_name" "text", "p_recipient_user_ids" "uuid"[], "p_recipient_emails" "text"[], "p_viewer_ids" "uuid"[], "p_exclusion_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "text", "p_custom_recipient_name" "text", "p_recipient_user_ids" "uuid"[], "p_recipient_emails" "text"[], "p_viewer_ids" "uuid"[], "p_exclusion_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "text", "p_custom_recipient_name" "text", "p_recipient_user_ids" "uuid"[], "p_recipient_emails" "text"[], "p_viewer_ids" "uuid"[], "p_exclusion_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[], "p_custom_recipient_name" "text", "p_random_assignment_enabled" boolean, "p_random_assignment_mode" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[], "p_custom_recipient_name" "text", "p_random_assignment_enabled" boolean, "p_random_assignment_mode" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[], "p_custom_recipient_name" "text", "p_random_assignment_enabled" boolean, "p_random_assignment_mode" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[], "p_custom_recipient_name" "text", "p_random_assignment_enabled" boolean, "p_random_assignment_mode" "text", "p_random_receiver_assignment_enabled" boolean, "p_for_everyone" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[], "p_custom_recipient_name" "text", "p_random_assignment_enabled" boolean, "p_random_assignment_mode" "text", "p_random_receiver_assignment_enabled" boolean, "p_for_everyone" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_list_with_people"("p_event_id" "uuid", "p_name" "text", "p_visibility" "public"."list_visibility", "p_recipients" "uuid"[], "p_hidden_recipients" "uuid"[], "p_viewers" "uuid"[], "p_custom_recipient_name" "text", "p_random_assignment_enabled" boolean, "p_random_assignment_mode" "text", "p_random_receiver_assignment_enabled" boolean, "p_for_everyone" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."decline_event_invite"("p_invite_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."decline_event_invite"("p_invite_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."decline_event_invite"("p_invite_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_item"("p_item_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_item"("p_item_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_item"("p_item_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_list"("p_list_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_list"("p_list_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_list"("p_list_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."deny_claim_split"("p_request_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."deny_claim_split"("p_request_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."deny_claim_split"("p_request_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_event_owner_member"() TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_event_owner_member"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_event_owner_member"() TO "service_role";



GRANT ALL ON FUNCTION "public"."event_claim_counts_for_user"("p_event_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."event_claim_counts_for_user"("p_event_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."event_claim_counts_for_user"("p_event_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."event_id_for_item"("i_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."event_id_for_item"("i_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."event_id_for_item"("i_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."event_id_for_list"("uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."event_id_for_list"("uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."event_id_for_list"("uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."event_is_accessible"("p_event_id" "uuid", "p_user" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."event_is_accessible"("p_event_id" "uuid", "p_user" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."event_is_accessible"("p_event_id" "uuid", "p_user" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."events_for_current_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."events_for_current_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."events_for_current_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."events_for_current_user_optimized"() TO "anon";
GRANT ALL ON FUNCTION "public"."events_for_current_user_optimized"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."events_for_current_user_optimized"() TO "service_role";



GRANT ALL ON FUNCTION "public"."execute_random_receiver_assignment"("p_list_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."execute_random_receiver_assignment"("p_list_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."execute_random_receiver_assignment"("p_list_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_and_send_daily_digests"("p_hour" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."generate_and_send_daily_digests"("p_hour" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_and_send_daily_digests"("p_hour" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_available_members_for_assignment"("p_list_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_available_members_for_assignment"("p_list_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_available_members_for_assignment"("p_list_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_claim_counts_by_list"("p_list_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."get_claim_counts_by_list"("p_list_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_claim_counts_by_list"("p_list_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_list_recipients"("p_list_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_list_recipients"("p_list_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_list_recipients"("p_list_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_pending_invites"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_pending_invites"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_pending_invites"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_split_requests"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_split_requests"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_split_requests"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."initialize_event_member_stats"() TO "anon";
GRANT ALL ON FUNCTION "public"."initialize_event_member_stats"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."initialize_event_member_stats"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_event_admin"("e_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_event_admin"("e_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_event_admin"("e_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_event_admin"("e_id" "uuid", "u_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_event_admin"("e_id" "uuid", "u_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_event_admin"("e_id" "uuid", "u_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_event_member"("p_event_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_event_member"("p_event_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_event_member"("p_event_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_event_member"("e_id" "uuid", "u_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_event_member"("e_id" "uuid", "u_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_event_member"("e_id" "uuid", "u_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_last_event_member"("e_id" "uuid", "u_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_last_event_member"("e_id" "uuid", "u_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_last_event_member"("e_id" "uuid", "u_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_list_recipient"("l_id" "uuid", "u_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_list_recipient"("l_id" "uuid", "u_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_list_recipient"("l_id" "uuid", "u_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_member_of_event"("p_event" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_member_of_event"("p_event" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_member_of_event"("p_event" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_member_of_event"("e_id" "uuid", "u_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_member_of_event"("e_id" "uuid", "u_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_member_of_event"("e_id" "uuid", "u_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_member_of_event_secure"("p_event_id" "uuid", "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_member_of_event_secure"("p_event_id" "uuid", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_member_of_event_secure"("p_event_id" "uuid", "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_pro"("p_user" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_pro"("p_user" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_pro"("p_user" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_pro"("p_user" "uuid", "p_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."is_pro"("p_user" "uuid", "p_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_pro"("p_user" "uuid", "p_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_pro_v2"("p_user" "uuid", "p_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."is_pro_v2"("p_user" "uuid", "p_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_pro_v2"("p_user" "uuid", "p_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_sole_event_member"("p_event_id" "uuid", "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_sole_event_member"("p_event_id" "uuid", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_sole_event_member"("p_event_id" "uuid", "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."join_event"("p_code" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."join_event"("p_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."join_event"("p_code" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."leave_event"("p_event_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."leave_event"("p_event_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."leave_event"("p_event_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."link_list_recipients_on_signup"() TO "anon";
GRANT ALL ON FUNCTION "public"."link_list_recipients_on_signup"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."link_list_recipients_on_signup"() TO "service_role";



GRANT ALL ON FUNCTION "public"."list_claim_counts_for_user"("p_list_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."list_claim_counts_for_user"("p_list_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_claim_counts_for_user"("p_list_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."list_claims_for_user"("p_item_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."list_claims_for_user"("p_item_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_claims_for_user"("p_item_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."list_id_for_item"("i_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."list_id_for_item"("i_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_id_for_item"("i_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."log_activity_for_digest"("p_event_id" "uuid", "p_exclude_user_id" "uuid", "p_activity_type" "text", "p_activity_data" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."log_activity_for_digest"("p_event_id" "uuid", "p_exclude_user_id" "uuid", "p_activity_type" "text", "p_activity_data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_activity_for_digest"("p_event_id" "uuid", "p_exclude_user_id" "uuid", "p_activity_type" "text", "p_activity_data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."log_security_event"("p_action" "text", "p_resource_type" "text", "p_resource_id" "uuid", "p_success" boolean, "p_error_message" "text", "p_metadata" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."log_security_event"("p_action" "text", "p_resource_type" "text", "p_resource_id" "uuid", "p_success" boolean, "p_error_message" "text", "p_metadata" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_security_event"("p_action" "text", "p_resource_type" "text", "p_resource_id" "uuid", "p_success" boolean, "p_error_message" "text", "p_metadata" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_orphaned_lists_for_deletion"() TO "anon";
GRANT ALL ON FUNCTION "public"."mark_orphaned_lists_for_deletion"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_orphaned_lists_for_deletion"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_new_claim"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_new_claim"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_new_claim"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_new_item"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_new_item"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_new_item"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_new_list"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_new_list"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_new_list"() TO "service_role";



GRANT ALL ON FUNCTION "public"."recalculate_event_member_stats"("p_event_id" "uuid", "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."recalculate_event_member_stats"("p_event_id" "uuid", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."recalculate_event_member_stats"("p_event_id" "uuid", "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."remove_member"("p_event_id" "uuid", "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."remove_member"("p_event_id" "uuid", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."remove_member"("p_event_id" "uuid", "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."request_claim_split"("p_item_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."request_claim_split"("p_item_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."request_claim_split"("p_item_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."rollover_all_due_events"() TO "anon";
GRANT ALL ON FUNCTION "public"."rollover_all_due_events"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rollover_all_due_events"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sanitize_text"("p_text" "text", "p_max_length" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."sanitize_text"("p_text" "text", "p_max_length" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sanitize_text"("p_text" "text", "p_max_length" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."send_event_invite"("p_event_id" "uuid", "p_invitee_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."send_event_invite"("p_event_id" "uuid", "p_invitee_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_event_invite"("p_event_id" "uuid", "p_invitee_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."send_event_invite"("p_event_id" "uuid", "p_inviter_email" "text", "p_recipient_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."send_event_invite"("p_event_id" "uuid", "p_inviter_email" "text", "p_recipient_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_event_invite"("p_event_id" "uuid", "p_inviter_email" "text", "p_recipient_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_list_created_by"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_list_created_by"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_list_created_by"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_onboarding_done"("p_done" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."set_onboarding_done"("p_done" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_onboarding_done"("p_done" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_plan"("p_plan" "text", "p_months" integer, "p_user" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."set_plan"("p_plan" "text", "p_months" integer, "p_user" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_plan"("p_plan" "text", "p_months" integer, "p_user" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_profile_name"("p_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_profile_name"("p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_profile_name"("p_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."test_impersonate"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."test_impersonate"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."test_impersonate"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."tg_set_timestamp"() TO "anon";
GRANT ALL ON FUNCTION "public"."tg_set_timestamp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."tg_set_timestamp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_daily_digest"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_daily_digest"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_daily_digest"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_push_notifications"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_push_notifications"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_push_notifications"() TO "service_role";



GRANT ALL ON FUNCTION "public"."unclaim_item"("p_item_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."unclaim_item"("p_item_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."unclaim_item"("p_item_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."unmark_orphaned_lists_on_member_join"() TO "anon";
GRANT ALL ON FUNCTION "public"."unmark_orphaned_lists_on_member_join"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."unmark_orphaned_lists_on_member_join"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_event_member_stats_on_claim_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_event_member_stats_on_claim_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_event_member_stats_on_claim_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_event_member_stats_on_list_event_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_event_member_stats_on_list_event_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_event_member_stats_on_list_event_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_event_member_stats_on_recipient_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_event_member_stats_on_recipient_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_event_member_stats_on_recipient_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_invites_on_user_signup"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_invites_on_user_signup"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_invites_on_user_signup"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_email"("p_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."validate_email"("p_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_email"("p_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_uuid"("p_value" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."validate_uuid"("p_value" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_uuid"("p_value" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."whoami"() TO "anon";
GRANT ALL ON FUNCTION "public"."whoami"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."whoami"() TO "service_role";
























GRANT ALL ON TABLE "public"."claim_split_requests" TO "anon";
GRANT ALL ON TABLE "public"."claim_split_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."claim_split_requests" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."claims" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."claims" TO "authenticated";
GRANT ALL ON TABLE "public"."claims" TO "service_role";



GRANT ALL ON TABLE "public"."daily_activity_log" TO "anon";
GRANT ALL ON TABLE "public"."daily_activity_log" TO "authenticated";
GRANT ALL ON TABLE "public"."daily_activity_log" TO "service_role";



GRANT ALL ON TABLE "public"."event_invites" TO "anon";
GRANT ALL ON TABLE "public"."event_invites" TO "authenticated";
GRANT ALL ON TABLE "public"."event_invites" TO "service_role";



GRANT ALL ON TABLE "public"."event_member_stats" TO "anon";
GRANT ALL ON TABLE "public"."event_member_stats" TO "authenticated";
GRANT ALL ON TABLE "public"."event_member_stats" TO "service_role";



GRANT ALL ON TABLE "public"."event_members" TO "anon";
GRANT ALL ON TABLE "public"."event_members" TO "authenticated";
GRANT ALL ON TABLE "public"."event_members" TO "service_role";



GRANT ALL ON TABLE "public"."events" TO "anon";
GRANT ALL ON TABLE "public"."events" TO "authenticated";
GRANT ALL ON TABLE "public"."events" TO "service_role";



GRANT ALL ON TABLE "public"."items" TO "anon";
GRANT ALL ON TABLE "public"."items" TO "authenticated";
GRANT ALL ON TABLE "public"."items" TO "service_role";



GRANT ALL ON TABLE "public"."list_exclusions" TO "anon";
GRANT ALL ON TABLE "public"."list_exclusions" TO "authenticated";
GRANT ALL ON TABLE "public"."list_exclusions" TO "service_role";



GRANT ALL ON TABLE "public"."list_recipients" TO "anon";
GRANT ALL ON TABLE "public"."list_recipients" TO "authenticated";
GRANT ALL ON TABLE "public"."list_recipients" TO "service_role";



GRANT ALL ON TABLE "public"."list_viewers" TO "anon";
GRANT ALL ON TABLE "public"."list_viewers" TO "authenticated";
GRANT ALL ON TABLE "public"."list_viewers" TO "service_role";



GRANT ALL ON TABLE "public"."lists" TO "anon";
GRANT ALL ON TABLE "public"."lists" TO "authenticated";
GRANT ALL ON TABLE "public"."lists" TO "service_role";



GRANT ALL ON TABLE "public"."notification_queue" TO "anon";
GRANT ALL ON TABLE "public"."notification_queue" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_queue" TO "service_role";



GRANT ALL ON TABLE "public"."orphaned_lists" TO "anon";
GRANT ALL ON TABLE "public"."orphaned_lists" TO "authenticated";
GRANT ALL ON TABLE "public"."orphaned_lists" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."push_tokens" TO "anon";
GRANT ALL ON TABLE "public"."push_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."push_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."rate_limit_tracking" TO "anon";
GRANT ALL ON TABLE "public"."rate_limit_tracking" TO "authenticated";
GRANT ALL ON TABLE "public"."rate_limit_tracking" TO "service_role";



GRANT ALL ON TABLE "public"."security_audit_log" TO "anon";
GRANT ALL ON TABLE "public"."security_audit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."security_audit_log" TO "service_role";



GRANT ALL ON TABLE "public"."sent_reminders" TO "anon";
GRANT ALL ON TABLE "public"."sent_reminders" TO "authenticated";
GRANT ALL ON TABLE "public"."sent_reminders" TO "service_role";



GRANT ALL ON TABLE "public"."user_plans" TO "anon";
GRANT ALL ON TABLE "public"."user_plans" TO "authenticated";
GRANT ALL ON TABLE "public"."user_plans" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






























RESET ALL;
