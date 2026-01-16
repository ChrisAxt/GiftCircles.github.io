-- Test digest generation for Chris Axt only

-- 1. Get Chris Axt's user ID
DO $$
DECLARE
    v_chris_id uuid := '0881f0e0-4254-4f76-b487-99b40dd08f10';
    v_activity_summary jsonb;
    v_title text;
    v_body text;
    v_activity_count int;
BEGIN
    -- Check if Chris has activity in last 24 hours
    SELECT COUNT(*) INTO v_activity_count
    FROM public.daily_activity_log
    WHERE user_id = v_chris_id
      AND created_at >= NOW() - INTERVAL '24 hours';

    IF v_activity_count = 0 THEN
        RAISE NOTICE 'No activity found for Chris Axt in last 24 hours';
        RETURN;
    END IF;

    -- Build activity summary
    WITH activity_details AS (
        SELECT
            dal.event_id,
            dal.activity_type,
            dal.activity_data->>'list_name' AS list_name,
            dal.activity_data->>'event_title' AS event_title,
            COUNT(*) AS count
        FROM public.daily_activity_log dal
        WHERE dal.user_id = v_chris_id
          AND dal.created_at >= NOW() - INTERVAL '24 hours'
        GROUP BY dal.event_id, dal.activity_type, dal.activity_data->>'list_name', dal.activity_data->>'event_title'
    ),
    event_summaries AS (
        SELECT
            ad.event_title,
            jsonb_agg(
                jsonb_build_object(
                    'activity_type', ad.activity_type,
                    'list_name', ad.list_name,
                    'count', ad.count
                )
            ) AS activities
        FROM activity_details ad
        GROUP BY ad.event_id, ad.event_title
    )
    SELECT jsonb_agg(
        jsonb_build_object(
            'event_title', es.event_title,
            'activities', es.activities
        )
    )
    INTO v_activity_summary
    FROM event_summaries es;

    -- Build notification body
    DECLARE
        v_event jsonb;
        v_activity jsonb;
        v_lines text[] := array[]::text[];
        v_event_title text;
        v_list_name text;
        v_activity_type text;
        v_activity_count_item int;
        v_activity_text text;
    BEGIN
        IF v_activity_summary IS NOT NULL THEN
            FOR v_event IN SELECT jsonb_array_elements(v_activity_summary)
            LOOP
                v_event_title := v_event->>'event_title';

                FOR v_activity IN SELECT jsonb_array_elements(v_event->'activities')
                LOOP
                    v_list_name := v_activity->>'list_name';
                    v_activity_type := v_activity->>'activity_type';
                    v_activity_count_item := (v_activity->>'count')::int;

                    v_activity_text := CASE v_activity_type
                        WHEN 'new_list' THEN v_activity_count_item || ' new list' || CASE WHEN v_activity_count_item > 1 THEN 's' ELSE '' END
                        WHEN 'new_item' THEN v_activity_count_item || ' new item' || CASE WHEN v_activity_count_item > 1 THEN 's' ELSE '' END
                        WHEN 'new_claim' THEN v_activity_count_item || ' new claim' || CASE WHEN v_activity_count_item > 1 THEN 's' ELSE '' END
                        WHEN 'unclaim' THEN v_activity_count_item || ' unclaim' || CASE WHEN v_activity_count_item > 1 THEN 's' ELSE '' END
                        ELSE v_activity_count_item || ' ' || v_activity_type
                    END;

                    IF v_activity_type = 'new_list' THEN
                        v_lines := array_append(v_lines, v_event_title || ': ' || v_activity_text);
                    ELSE
                        v_lines := array_append(v_lines, v_event_title || '-' || COALESCE(v_list_name, 'Unknown') || ': ' || v_activity_text);
                    END IF;
                END LOOP;
            END LOOP;
        END IF;

        IF array_length(v_lines, 1) IS NULL OR array_length(v_lines, 1) = 0 THEN
            RAISE NOTICE 'No activity to report';
            RETURN;
        END IF;

        v_title := 'Your Daily GiftCircles Summary';
        v_body := array_to_string(v_lines, E'\n');

        -- Queue notification for Chris Axt only
        INSERT INTO public.notification_queue (user_id, title, body, data)
        VALUES (
            v_chris_id,
            v_title,
            v_body,
            jsonb_build_object(
                'type', 'digest',
                'frequency', 'daily',
                'summary', v_activity_summary
            )
        );

        RAISE NOTICE 'Digest queued for Chris Axt: %', v_body;
    END;
END $$;

-- Check what was just queued
SELECT
    p.display_name,
    nq.title,
    nq.body,
    nq.sent,
    nq.created_at
FROM public.notification_queue nq
JOIN public.profiles p ON p.id = nq.user_id
WHERE nq.user_id = '0881f0e0-4254-4f76-b487-99b40dd08f10'
  AND nq.data->>'type' = 'digest'
ORDER BY nq.created_at DESC
LIMIT 5;
