-- Migration: Enhance digest notification with detailed activity breakdown
-- Created: 2025-11-16
-- Purpose: Show event-list specific activity in digest notifications
-- Format: "Christmas-List name: 1 new claim" instead of just "1 new claim today"

BEGIN;

CREATE OR REPLACE FUNCTION public.generate_and_send_daily_digests(p_hour integer DEFAULT NULL::integer)
RETURNS TABLE(digests_sent integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
$function$;

COMMENT ON FUNCTION public.generate_and_send_daily_digests IS
'Generates and queues digest notifications with detailed activity breakdown per event and list. Shows format like "Christmas-List name: 1 new claim" instead of generic counts.';

COMMIT;
