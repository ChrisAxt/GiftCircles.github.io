-- Migration: Update claim counts for collaborative combined assignment mode
-- Date: 2025-01-20
-- Description: For lists with both random assignment features, all members see all items,
--              so claim counts should show total claimed items (not filtered per user).
--              Claim details remain private - only assigned givers see who claimed what.

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
  -- For combined random assignment: all members see total count (collaborative mode)
  -- For single random assignment modes: counts filtered by user visibility

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
      ) as is_admin,
      -- Check if this is combined random assignment (collaborative mode)
      (
        vl.random_assignment_enabled = true
        AND vl.random_receiver_assignment_enabled = true
      ) as is_collaborative
    FROM visible_lists vl
  ),
  visible_items AS (
    -- Get items the user can see based on list mode
    SELECT DISTINCT i.id as item_id, i.list_id
    FROM items i
    INNER JOIN visible_lists vl ON vl.id = i.list_id
    INNER JOIN user_permissions up ON up.list_id = vl.id
    WHERE
      -- For combined random assignment (collaborative): all members see all items
      up.is_collaborative = true
      -- OR admins/owners/creators always see all items
      OR up.is_admin = true
      -- OR for random giver assignment only: only see items assigned to you
      OR (
        vl.random_assignment_enabled = true
        AND COALESCE(vl.random_receiver_assignment_enabled, false) = false
        AND EXISTS (
          SELECT 1 FROM claims c
          WHERE c.item_id = i.id AND c.assigned_to = v_user_id
        )
      )
      -- OR for random receiver assignment only: hide from assigned recipients
      OR (
        COALESCE(vl.random_assignment_enabled, false) = false
        AND vl.random_receiver_assignment_enabled = true
        AND i.assigned_recipient_id != v_user_id
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
'Returns claim counts for lists. In combined random assignment (collaborative mode), all members see total counts. In single random modes, counts filtered by visibility. Claim details remain private.';

COMMIT;
