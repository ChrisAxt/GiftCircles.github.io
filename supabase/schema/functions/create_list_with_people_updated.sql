-- Updated create_list_with_people function to support random assignment
-- This replaces the existing function with additional parameters

CREATE OR REPLACE FUNCTION public.create_list_with_people(
  p_event_id uuid,
  p_name text,
  p_visibility list_visibility DEFAULT 'event'::list_visibility,
  p_recipients uuid[] DEFAULT '{}'::uuid[],
  p_hidden_recipients uuid[] DEFAULT '{}'::uuid[],
  p_viewers uuid[] DEFAULT '{}'::uuid[],
  p_custom_recipient_name text DEFAULT NULL::text,
  p_random_assignment_enabled boolean DEFAULT false,
  p_random_assignment_mode text DEFAULT NULL::text,
  p_random_receiver_assignment_enabled boolean DEFAULT false,
  p_for_everyone boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
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
$function$;

COMMENT ON FUNCTION public.create_list_with_people(uuid, text, list_visibility, uuid[], uuid[], uuid[], text, boolean, text, boolean, boolean) IS
'Creates a list with recipients, viewers, and optional random assignment (giver and/or receiver) configuration. Supports for_everyone flag.';
