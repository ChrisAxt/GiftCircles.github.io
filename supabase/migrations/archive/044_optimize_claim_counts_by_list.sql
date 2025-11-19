-- Migration: Optimize claim counts by list for EventDetailScreen
-- Date: 2025-01-17
-- Description: Create optimized RPC to get claim counts per list, bypassing expensive RLS evaluation.
--              This dramatically improves EventDetailScreen load time.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_claim_counts_by_list(p_list_ids uuid[])
RETURNS TABLE(list_id uuid, claimed_count bigint)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Return claim counts (number of items with at least 1 claim) for each list
  -- Only includes lists the current user can view

  RETURN QUERY
  WITH visible_lists AS (
    -- Filter to only lists the user can view
    SELECT l.id, l.event_id, l.visibility, l.created_by
    FROM lists l
    WHERE l.id = ANY(p_list_ids)
      AND (
        -- User created the list
        l.created_by = auth.uid()
        -- OR user is a recipient
        OR EXISTS (
          SELECT 1 FROM list_recipients lr
          WHERE lr.list_id = l.id AND lr.user_id = auth.uid()
        )
        -- OR list visibility is 'event' and user is event member
        OR (
          l.visibility = 'event'
          AND EXISTS (
            SELECT 1 FROM event_members em
            WHERE em.event_id = l.event_id AND em.user_id = auth.uid()
          )
        )
        -- OR list visibility is 'selected' and user is viewer
        OR (
          l.visibility = 'selected'
          AND EXISTS (
            SELECT 1 FROM list_viewers lv
            WHERE lv.list_id = l.id AND lv.user_id = auth.uid()
          )
        )
      )
      -- Exclude lists where user is excluded
      AND NOT EXISTS (
        SELECT 1 FROM list_exclusions le
        WHERE le.list_id = l.id AND le.user_id = auth.uid()
      )
  ),
  items_with_claims AS (
    -- Get all items from visible lists that have at least one claim
    SELECT DISTINCT i.list_id, i.id as item_id
    FROM items i
    INNER JOIN visible_lists vl ON vl.id = i.list_id
    WHERE EXISTS (
      SELECT 1 FROM claims c WHERE c.item_id = i.id
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

COMMENT ON FUNCTION public.get_claim_counts_by_list(uuid[]) IS
'Returns claim counts (items with at least 1 claim) for specified lists. Only includes lists user can view. Optimized with SECURITY DEFINER to bypass RLS.';

COMMIT;
