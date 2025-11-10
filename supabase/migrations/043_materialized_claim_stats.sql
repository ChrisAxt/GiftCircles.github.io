-- Migration: Add materialized claim statistics for performance
-- Date: 2025-01-17
-- Description: Create event_member_stats table to store pre-computed claim counts per user per event.
--              This eliminates expensive RLS policy evaluation on every claim query.
--              Stats are automatically updated via triggers on claims, items, lists, and list_recipients.

BEGIN;

-- ============================================================================
-- STEP 1: Create event_member_stats table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.event_member_stats (
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  total_claims bigint NOT NULL DEFAULT 0,
  unpurchased_claims bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, user_id)
);

-- Indexes for fast lookups
CREATE INDEX idx_event_member_stats_event ON public.event_member_stats(event_id);
CREATE INDEX idx_event_member_stats_user ON public.event_member_stats(user_id);
CREATE INDEX idx_event_member_stats_updated ON public.event_member_stats(updated_at);

COMMENT ON TABLE public.event_member_stats IS
'Materialized claim statistics per user per event. Updated automatically via triggers for performance.';

COMMENT ON COLUMN public.event_member_stats.total_claims IS
'Total number of claims by this user in this event (excluding claims on lists where user is recipient)';

COMMENT ON COLUMN public.event_member_stats.unpurchased_claims IS
'Number of unpurchased claims by this user in this event (excluding claims on lists where user is recipient)';

-- ============================================================================
-- STEP 2: Create helper function to recalculate stats for a user in an event
-- ============================================================================

CREATE OR REPLACE FUNCTION public.recalculate_event_member_stats(
  p_event_id uuid,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_total_claims bigint;
  v_unpurchased_claims bigint;
BEGIN
  -- Calculate claim counts for this user in this event
  -- Exclude claims on lists where user is the recipient
  SELECT
    COUNT(c.id),
    COUNT(c.id) FILTER (WHERE c.purchased = false)
  INTO v_total_claims, v_unpurchased_claims
  FROM claims c
  JOIN items i ON i.id = c.item_id
  JOIN lists l ON l.id = i.list_id
  WHERE l.event_id = p_event_id
    AND c.claimer_id = p_user_id
    -- Exclude claims on lists where user is recipient
    AND NOT EXISTS (
      SELECT 1 FROM list_recipients lr
      WHERE lr.list_id = l.id AND lr.user_id = p_user_id
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

COMMENT ON FUNCTION public.recalculate_event_member_stats(uuid, uuid) IS
'Recalculates and updates claim statistics for a specific user in a specific event';

-- ============================================================================
-- STEP 3: Create trigger function for claims table
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_event_member_stats_on_claim_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Create trigger on claims table
DROP TRIGGER IF EXISTS trigger_update_event_member_stats_on_claim ON public.claims;
CREATE TRIGGER trigger_update_event_member_stats_on_claim
  AFTER INSERT OR UPDATE OR DELETE ON public.claims
  FOR EACH ROW
  EXECUTE FUNCTION update_event_member_stats_on_claim_change();

COMMENT ON FUNCTION public.update_event_member_stats_on_claim_change() IS
'Trigger function that updates event_member_stats when claims are added, updated, or deleted';

-- ============================================================================
-- STEP 4: Create trigger function for list_recipients table
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_event_member_stats_on_recipient_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Create trigger on list_recipients table
DROP TRIGGER IF EXISTS trigger_update_event_member_stats_on_recipient ON public.list_recipients;
CREATE TRIGGER trigger_update_event_member_stats_on_recipient
  AFTER INSERT OR UPDATE OR DELETE ON public.list_recipients
  FOR EACH ROW
  EXECUTE FUNCTION update_event_member_stats_on_recipient_change();

COMMENT ON FUNCTION public.update_event_member_stats_on_recipient_change() IS
'Trigger function that updates event_member_stats when list recipients change';

-- ============================================================================
-- STEP 5: Create trigger function for lists table (when list changes events)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_event_member_stats_on_list_event_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Create trigger on lists table
DROP TRIGGER IF EXISTS trigger_update_event_member_stats_on_list_event ON public.lists;
CREATE TRIGGER trigger_update_event_member_stats_on_list_event
  AFTER UPDATE ON public.lists
  FOR EACH ROW
  WHEN (OLD.event_id IS DISTINCT FROM NEW.event_id)
  EXECUTE FUNCTION update_event_member_stats_on_list_event_change();

COMMENT ON FUNCTION public.update_event_member_stats_on_list_event_change() IS
'Trigger function that updates event_member_stats when a list is moved to a different event';

-- ============================================================================
-- STEP 5b: Create trigger function for event_members table (initialize stats)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.initialize_event_member_stats()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Create trigger on event_members table
DROP TRIGGER IF EXISTS trigger_initialize_event_member_stats ON public.event_members;
CREATE TRIGGER trigger_initialize_event_member_stats
  AFTER INSERT ON public.event_members
  FOR EACH ROW
  EXECUTE FUNCTION initialize_event_member_stats();

COMMENT ON FUNCTION public.initialize_event_member_stats() IS
'Trigger function that initializes event_member_stats when a new member joins an event';

-- ============================================================================
-- STEP 6: Backfill existing data
-- ============================================================================

-- Function to backfill all existing stats
CREATE OR REPLACE FUNCTION public.backfill_event_member_stats()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- For each event member, calculate their stats
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
  -- Exclude claims on lists where user is recipient
  LEFT JOIN list_recipients lr ON lr.list_id = l.id AND lr.user_id = em.user_id
  WHERE lr.list_id IS NULL  -- Only include if NOT a recipient
  GROUP BY em.event_id, em.user_id
  ON CONFLICT (event_id, user_id) DO UPDATE SET
    total_claims = EXCLUDED.total_claims,
    unpurchased_claims = EXCLUDED.unpurchased_claims,
    updated_at = now();
END;
$$;

-- Execute backfill
SELECT backfill_event_member_stats();

COMMENT ON FUNCTION public.backfill_event_member_stats() IS
'Backfills event_member_stats table with existing claim data. Run once during migration.';

-- ============================================================================
-- STEP 7: Create RLS policies for event_member_stats
-- ============================================================================

ALTER TABLE public.event_member_stats ENABLE ROW LEVEL SECURITY;

-- Users can only see their own stats
CREATE POLICY "event_member_stats_select"
ON public.event_member_stats
FOR SELECT
USING (user_id = auth.uid());

-- No direct INSERT/UPDATE/DELETE - only via triggers
CREATE POLICY "event_member_stats_no_insert"
ON public.event_member_stats
FOR INSERT
WITH CHECK (false);

CREATE POLICY "event_member_stats_no_update"
ON public.event_member_stats
FOR UPDATE
USING (false);

CREATE POLICY "event_member_stats_no_delete"
ON public.event_member_stats
FOR DELETE
USING (false);

COMMENT ON POLICY "event_member_stats_select" ON public.event_member_stats IS
'Users can only view their own statistics';

-- ============================================================================
-- STEP 8: Update events_for_current_user to include stats
-- ============================================================================

-- Drop existing function to allow return type change
DROP FUNCTION IF EXISTS public.events_for_current_user();

CREATE OR REPLACE FUNCTION public.events_for_current_user()
 RETURNS TABLE(
   id uuid,
   title text,
   event_date date,
   join_code text,
   created_at timestamp with time zone,
   member_count bigint,
   total_items bigint,
   claimed_count bigint,
   accessible boolean,
   rownum integer,
   my_claims bigint,
   my_unpurchased_claims bigint
 )
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

COMMENT ON FUNCTION public.events_for_current_user() IS
'Returns all events for the current user with counts. Uses materialized stats for my_claims and my_unpurchased_claims.';

COMMIT;
