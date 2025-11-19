-- Automatically update event_member_stats when claims/items/lists are deleted
-- This ensures the stats always reflect reality

BEGIN;

-- Function to recalculate stats for a user in an event
CREATE OR REPLACE FUNCTION public.refresh_event_member_stats(p_event_id uuid, p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Trigger function for when claims are deleted
CREATE OR REPLACE FUNCTION public.trigger_refresh_stats_on_claim_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Trigger function for when items are deleted (deletes claims via CASCADE, then refresh stats)
CREATE OR REPLACE FUNCTION public.trigger_refresh_stats_on_item_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Trigger function for when lists are deleted
CREATE OR REPLACE FUNCTION public.trigger_refresh_stats_on_list_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Create triggers
DROP TRIGGER IF EXISTS on_claim_delete_refresh_stats ON claims;
CREATE TRIGGER on_claim_delete_refresh_stats
  AFTER DELETE ON claims
  FOR EACH ROW
  EXECUTE FUNCTION trigger_refresh_stats_on_claim_delete();

DROP TRIGGER IF EXISTS on_item_delete_refresh_stats ON items;
CREATE TRIGGER on_item_delete_refresh_stats
  AFTER DELETE ON items
  FOR EACH ROW
  EXECUTE FUNCTION trigger_refresh_stats_on_item_delete();

DROP TRIGGER IF EXISTS on_list_delete_refresh_stats ON lists;
CREATE TRIGGER on_list_delete_refresh_stats
  BEFORE DELETE ON lists
  FOR EACH ROW
  EXECUTE FUNCTION trigger_refresh_stats_on_list_delete();

COMMIT;
