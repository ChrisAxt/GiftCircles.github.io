-- Migration: Add timezone support for digest notifications
-- Created: 2025-11-12
-- Purpose: Allow users to receive digests at their local time instead of UTC
--
-- Changes:
-- 1. Add timezone column to profiles table (IANA timezone format)
-- 2. Update generate_and_send_daily_digests to convert local time to UTC
-- 3. Handle daylight saving time automatically

BEGIN;

-- ============================================================================
-- 1. Add timezone column to profiles table
-- ============================================================================

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS timezone text DEFAULT 'UTC';

COMMENT ON COLUMN public.profiles.timezone IS 'User timezone in IANA format (e.g., America/New_York, Europe/London). Used to deliver digest notifications at user local time.';

-- ============================================================================
-- 2. Update generate_and_send_daily_digests to handle timezone conversion
-- ============================================================================

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
  v_user_local_time timestamp with time zone;
  v_user_local_hour int;
  v_user_local_dow int;
begin
  -- Use provided hour or current hour (UTC)
  v_target_hour := coalesce(p_hour, extract(hour from now())::int);

  -- Process each user who has digest enabled
  -- NOW WITH TIMEZONE CONVERSION: Check if user's local time matches their digest settings
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
'Generates and queues digest notifications for users. NOW WITH TIMEZONE SUPPORT: Converts user local time to UTC to deliver digests at correct local time. Handles DST automatically.';

COMMIT;

-- Summary of Changes:
-- 1. Added profiles.timezone column (IANA format, defaults to UTC)
-- 2. Updated generate_and_send_daily_digests to:
--    - Convert current UTC time to user's local timezone
--    - Check if user's LOCAL hour matches digest_time_hour
--    - Check if user's LOCAL day matches digest_day_of_week
--    - Handle invalid timezones gracefully (falls back to UTC)
--    - Automatically handles daylight saving time
--
-- How it works:
-- - User sets "Tuesday 9:00 AM" in their preferences
-- - App stores timezone (e.g., "America/New_York") when digest is enabled
-- - Hourly cron runs at every UTC hour (0-23)
-- - For each user, system converts current UTC time → user's local time
-- - If local time matches user's settings, digest is sent
-- - Example: User in EST (UTC-5) wants 9 AM → digest sends when UTC is 14:00 (or 13:00 in DST)
--
-- Valid timezone examples:
-- - America/New_York (Eastern Time)
-- - America/Los_Angeles (Pacific Time)
-- - Europe/London (GMT/BST)
-- - Europe/Paris (CET/CEST)
-- - Asia/Tokyo (JST)
-- - Australia/Sydney (AEDT/AEST)
