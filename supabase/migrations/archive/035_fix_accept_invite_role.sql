-- Migration: Fix accept_event_invite to respect invited_role
-- Date: 2025-10-14
-- Description: Updates accept_event_invite function to use the invited_role from the invite instead of hardcoding 'giver'

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
$function$;
