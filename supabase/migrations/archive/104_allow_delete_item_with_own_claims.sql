-- Migration 104: Allow deleting items with claims if user is authorized
-- Fixes: Item creators/admins/owners can delete items even if claimed
--
-- New behavior: Allow deletion if:
-- - User is the only claimer on the item, OR
-- - User is an event admin, OR
-- - User is the event owner
-- This aligns with the claims_delete policy from migration 103.

BEGIN;

CREATE OR REPLACE FUNCTION public.delete_item(p_item_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;
  v_item record;
  v_is_authorized boolean;
  v_can_delete_claims boolean;
  v_event_member_count int;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    PERFORM public.log_security_event('delete_item', 'item', p_item_id, false, 'not_authenticated');
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Validate input
  IF p_item_id IS NULL THEN
    RAISE EXCEPTION 'item_id_required';
  END IF;

  -- Rate limit check
  IF NOT public.check_rate_limit('delete_item', 50, 60) THEN
    RAISE EXCEPTION 'rate_limit_exceeded';
  END IF;

  -- Get item details
  SELECT i.*, l.event_id, l.created_by as list_creator
  INTO v_item
  FROM public.items i
  JOIN public.lists l ON l.id = i.list_id
  WHERE i.id = p_item_id;

  IF NOT FOUND THEN
    PERFORM public.log_security_event('delete_item', 'item', p_item_id, false, 'not_found');
    RAISE EXCEPTION 'not_found';
  END IF;

  -- Get event member count
  SELECT COUNT(*)
  INTO v_event_member_count
  FROM public.event_members
  WHERE event_id = v_item.event_id;

  -- Check authorization to delete the item
  SELECT
    -- Item creator
    v_item.created_by = v_user_id
    -- OR list creator
    OR v_item.list_creator = v_user_id
    -- OR event admin
    OR EXISTS (
      SELECT 1 FROM public.event_members em
      WHERE em.event_id = v_item.event_id
        AND em.user_id = v_user_id
        AND em.role = 'admin'::public.member_role
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
    PERFORM public.log_security_event('delete_item', 'item', p_item_id, false, 'not_authorized');
    RAISE EXCEPTION 'not_authorized';
  END IF;

  -- Check if item has claims that the user cannot delete
  -- User can delete item with claims if:
  -- 1. User is the claimer of ALL claims on the item, OR
  -- 2. User is an event admin, OR
  -- 3. User is the event owner, OR
  -- 4. User is the item creator (can delete claims on their own items)
  IF EXISTS (SELECT 1 FROM public.claims WHERE item_id = p_item_id) THEN
    SELECT
      -- User is item creator (can delete any claims on their item)
      v_item.created_by = v_user_id
      -- OR user is event admin
      OR EXISTS (
        SELECT 1 FROM public.event_members em
        WHERE em.event_id = v_item.event_id
          AND em.user_id = v_user_id
          AND em.role = 'admin'::public.member_role
      )
      -- OR user is event owner
      OR EXISTS (
        SELECT 1 FROM public.events e
        WHERE e.id = v_item.event_id
          AND e.owner_id = v_user_id
      )
      -- OR user is the claimer of ALL claims on this item
      OR NOT EXISTS (
        SELECT 1 FROM public.claims c
        WHERE c.item_id = p_item_id
          AND c.claimer_id != v_user_id
      )
    INTO v_can_delete_claims;

    IF NOT v_can_delete_claims THEN
      PERFORM public.log_security_event('delete_item', 'item', p_item_id, false, 'has_claims');
      RAISE EXCEPTION 'has_claims';
    END IF;
  END IF;

  -- Delete item (claims will be deleted via CASCADE)
  DELETE FROM public.items WHERE id = p_item_id;

  -- Log success
  PERFORM public.log_security_event('delete_item', 'item', p_item_id, true);
END;
$$;

COMMENT ON FUNCTION public.delete_item(p_item_id uuid) IS 'Securely deletes an item with authorization checks. Allows deletion even if claimed when user is item creator, admin, or owner.';

COMMIT;
