-- Migration: Fix claim counts for lists with random receiver assignment
-- Date: 2025-01-20
-- Description: When querying claim counts, non-admin members should only see counts for items
--              they can view. For random receiver assignment lists, members can only see items
--              assigned to them as givers, so claim counts should reflect this.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_claim_counts_by_list(p_list_ids uuid[])
RETURNS TABLE(list_id uuid, claimed_count bigint)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();

  -- Return claim counts (number of items with at least 1 claim) for each list
  -- Only includes lists the current user can view
  -- For random receiver assignment, only counts items the user can see

  RETURN QUERY
  WITH visible_lists AS (
    -- Filter to only lists the user can view
    SELECT
      l.id,
      l.event_id,
      l.visibility,
      l.created_by,
      l.random_assignment_enabled,
      l.random_receiver_assignment_enabled
    FROM lists l
    WHERE l.id = ANY(p_list_ids)
      AND (
        -- User created the list
        l.created_by = v_user_id
        -- OR user is a recipient
        OR EXISTS (
          SELECT 1 FROM list_recipients lr
          WHERE lr.list_id = l.id AND lr.user_id = v_user_id
        )
        -- OR list visibility is 'event' and user is event member
        OR (
          l.visibility = 'event'
          AND EXISTS (
            SELECT 1 FROM event_members em
            WHERE em.event_id = l.event_id AND em.user_id = v_user_id
          )
        )
        -- OR list visibility is 'selected' and user is viewer
        OR (
          l.visibility = 'selected'
          AND EXISTS (
            SELECT 1 FROM list_viewers lv
            WHERE lv.list_id = l.id AND lv.user_id = v_user_id
          )
        )
      )
      -- Exclude lists where user is excluded
      AND NOT EXISTS (
        SELECT 1 FROM list_exclusions le
        WHERE le.list_id = l.id AND le.user_id = v_user_id
      )
  ),
  user_permissions AS (
    -- Determine if user is admin/owner for each list
    SELECT
      vl.id as list_id,
      (
        vl.created_by = v_user_id
        OR EXISTS (
          SELECT 1 FROM event_members em
          WHERE em.event_id = vl.event_id
            AND em.user_id = v_user_id
            AND em.role = 'admin'
        )
        OR EXISTS (
          SELECT 1 FROM events e
          WHERE e.id = vl.event_id AND e.owner_id = v_user_id
        )
      ) as is_admin
    FROM visible_lists vl
  ),
  visible_items AS (
    -- Get items the user can actually see based on random assignment rules
    SELECT DISTINCT i.id as item_id, i.list_id
    FROM items i
    INNER JOIN visible_lists vl ON vl.id = i.list_id
    INNER JOIN user_permissions up ON up.list_id = vl.id
    WHERE
      -- Admins/owners/creators see all items
      up.is_admin = true
      -- OR for random receiver assignment: only see items assigned to you as giver
      OR (
        vl.random_receiver_assignment_enabled = true
        AND EXISTS (
          SELECT 1 FROM claims c
          WHERE c.item_id = i.id AND c.assigned_to = v_user_id
        )
      )
      -- OR for regular random assignment (no receiver): only see items assigned to you
      OR (
        vl.random_assignment_enabled = true
        AND COALESCE(vl.random_receiver_assignment_enabled, false) = false
        AND EXISTS (
          SELECT 1 FROM claims c
          WHERE c.item_id = i.id AND c.assigned_to = v_user_id
        )
      )
      -- OR for non-random lists: see all items
      OR (
        COALESCE(vl.random_assignment_enabled, false) = false
        AND COALESCE(vl.random_receiver_assignment_enabled, false) = false
      )
  ),
  items_with_claims AS (
    -- Get visible items that have at least one claim
    SELECT DISTINCT vi.list_id, vi.item_id
    FROM visible_items vi
    WHERE EXISTS (
      SELECT 1 FROM claims c WHERE c.item_id = vi.item_id
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
'Returns claim counts (items with at least 1 claim) for specified lists. Only includes lists and items user can view. For random receiver assignment, non-admin members only see counts for their assigned items.';

COMMIT;
