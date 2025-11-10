-- Migration: Test and verify list_claims_for_user is working
-- Date: 2025-01-20
-- Description: Add logging to help debug why claims aren't showing

BEGIN;

-- Create a simple test function to verify claims are visible
CREATE OR REPLACE FUNCTION public.test_list_claims_visibility(p_list_id uuid)
RETURNS TABLE(
  item_id uuid,
  item_name text,
  claimer_id uuid,
  assigned_to uuid,
  current_user uuid,
  is_visible boolean,
  reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();

  RETURN QUERY
  SELECT
    i.id as item_id,
    i.name as item_name,
    c.claimer_id,
    c.assigned_to,
    v_user_id as current_user,
    -- Check if user can see this claim
    (
      c.claimer_id = v_user_id
      OR EXISTS (
        SELECT 1 FROM lists l
        WHERE l.id = i.list_id
          AND (
            l.created_by = v_user_id
            OR EXISTS (SELECT 1 FROM event_members em WHERE em.event_id = l.event_id AND em.user_id = v_user_id AND em.role = 'admin')
            OR EXISTS (SELECT 1 FROM events e WHERE e.id = l.event_id AND e.owner_id = v_user_id)
            OR (l.random_assignment_enabled = true AND l.random_receiver_assignment_enabled = true AND c.assigned_to = v_user_id)
          )
      )
    ) as is_visible,
    CASE
      WHEN c.claimer_id = v_user_id THEN 'Own claim'
      WHEN EXISTS (SELECT 1 FROM lists l WHERE l.id = i.list_id AND l.created_by = v_user_id) THEN 'List creator'
      WHEN EXISTS (
        SELECT 1 FROM lists l
        WHERE l.id = i.list_id
          AND l.random_assignment_enabled = true
          AND l.random_receiver_assignment_enabled = true
          AND c.assigned_to = v_user_id
      ) THEN 'Collaborative assigned'
      ELSE 'Not visible'
    END as reason
  FROM items i
  JOIN claims c ON c.item_id = i.id
  WHERE i.list_id = p_list_id
  ORDER BY i.created_at;
END;
$$;

COMMENT ON FUNCTION public.test_list_claims_visibility(uuid) IS
'Debug function to test claim visibility for current user on a specific list';

COMMIT;
