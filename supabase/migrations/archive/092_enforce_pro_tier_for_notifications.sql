-- Migration: Enforce pro tier requirement for purchase reminders and digest notifications
-- Created: 2025-11-12
-- Purpose: Ensure free tier users cannot receive purchase reminders or digest notifications,
--          even if settings are manually enabled in the database

BEGIN;

-- ============================================================================
-- 1. Cleanup: Disable reminders and digest for all free tier users
-- ============================================================================

UPDATE public.profiles
SET
  reminder_days = NULL,
  notification_digest_enabled = false
WHERE
  -- User is NOT pro (either plan != 'pro' OR pro_until expired/null)
  (plan != 'pro' OR plan IS NULL OR plan != 'pro')
  AND (pro_until IS NULL OR pro_until < NOW())
  -- AND they have either feature enabled
  AND (reminder_days IS NOT NULL OR notification_digest_enabled = true);

COMMENT ON COLUMN public.profiles.reminder_days IS
'Days before event to send purchase reminder. NULL = disabled. Pro feature only.';

COMMENT ON COLUMN public.profiles.notification_digest_enabled IS
'Whether user receives activity digest notifications. Pro feature only.';

-- ============================================================================
-- 2. Update check_and_queue_purchase_reminders to enforce pro requirement
-- ============================================================================

DROP FUNCTION IF EXISTS public.check_and_queue_purchase_reminders();

CREATE OR REPLACE FUNCTION public.check_and_queue_purchase_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
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
$function$;

COMMENT ON FUNCTION public.check_and_queue_purchase_reminders IS
'Queues purchase reminder notifications for pro users with unpurchased claims. Runs daily via cron.';

-- ============================================================================
-- 3. Update generate_and_send_daily_digests to enforce pro requirement
-- ============================================================================

DROP FUNCTION IF EXISTS public.generate_and_send_daily_digests(integer);

CREATE OR REPLACE FUNCTION public.generate_and_send_daily_digests(p_hour integer DEFAULT NULL::integer)
RETURNS TABLE(digests_sent integer)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  v_user record;
  v_count int := 0;
  v_target_hour int;
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

  -- Process each user who has digest enabled AND is pro
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
      -- NEW: Only process pro users
      and public.is_pro(p.id, now()) = true
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
      if v_activity_summary is not null then
        for v_event in select jsonb_array_elements(v_activity_summary)
        loop
          v_total_lists := v_total_lists + coalesce((v_event->'counts'->>'new_list')::int, 0);
          v_total_items := v_total_items + coalesce((v_event->'counts'->>'new_item')::int, 0);
          v_total_claims := v_total_claims + coalesce((v_event->'counts'->>'new_claim')::int, 0);
        end loop;
      end if;

      -- Set time period text
      v_time_period := case
        when v_user.digest_frequency = 'weekly' then 'this week'
        else 'today'
      end;

      -- Build title and body
      if v_total_lists + v_total_items + v_total_claims = 0 then
        continue; -- Skip if no activity
      end if;

      v_title := case
        when v_user.digest_frequency = 'weekly' then 'Your Weekly GiftCircles Summary'
        else 'Your Daily GiftCircles Summary'
      end;

      -- Build body with counts
      declare
        v_parts text[] := array[]::text[];
      begin
        if v_total_lists > 0 then
          v_parts := array_append(v_parts, v_total_lists || ' new list' || case when v_total_lists > 1 then 's' else '' end);
        end if;
        if v_total_items > 0 then
          v_parts := array_append(v_parts, v_total_items || ' new item' || case when v_total_items > 1 then 's' else '' end);
        end if;
        if v_total_claims > 0 then
          v_parts := array_append(v_parts, v_total_claims || ' new claim' || case when v_total_claims > 1 then 's' else '' end);
        end if;

        v_body := array_to_string(v_parts, ', ') || ' ' || v_time_period || '.';
      end;

      -- Queue notification
      insert into public.notification_queue (user_id, title, body, data)
      values (
        v_user.user_id,
        v_title,
        v_body,
        jsonb_build_object(
          'type', 'digest',
          'frequency', v_user.digest_frequency,
          'time_period', v_time_period,
          'summary', v_activity_summary
        )
      );

      v_count := v_count + 1;
    end;
  end loop;

  return query select v_count;
end;
$function$;

COMMENT ON FUNCTION public.generate_and_send_daily_digests IS
'Generates and queues digest notifications for pro users only. Uses timezone conversion to deliver at correct local time.';

COMMIT;

-- Summary of Changes:
-- 1. Disabled reminder_days and notification_digest_enabled for all current free tier users
-- 2. Added pro tier check to check_and_queue_purchase_reminders() function
-- 3. Added pro tier check to generate_and_send_daily_digests() function
-- 4. Updated function comments to indicate pro-only requirement
--
-- Result:
-- ✅ UI already blocks free users from enabling these features (upgrade prompt)
-- ✅ Backend now enforces pro requirement when sending notifications
-- ✅ Existing free users have features disabled
-- ✅ Database manipulation cannot bypass restrictions
-- ✅ Security: Only pro users receive purchase reminders and digest notifications
