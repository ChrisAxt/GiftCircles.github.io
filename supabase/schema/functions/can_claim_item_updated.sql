-- Updated can_claim_item function to respect random assignments
-- For lists with random assignment enabled, users can only claim items assigned to them (or if they're admins)

CREATE OR REPLACE FUNCTION public.can_claim_item(p_item_id uuid, p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  WITH i AS (
    SELECT i.id, i.list_id, l.event_id, l.random_assignment_enabled, l.created_by
    FROM public.items i
    JOIN public.lists l ON l.id = i.list_id
    WHERE i.id = p_item_id
  ),

  is_admin AS (
    SELECT EXISTS (
      SELECT 1
      FROM i
      LEFT JOIN public.event_members em ON em.event_id = i.event_id AND em.user_id = p_user
      LEFT JOIN public.events e ON e.id = i.event_id
      WHERE i.created_by = p_user
         OR em.role = 'admin'
         OR e.owner_id = p_user
    ) AS admin_check
  ),

  is_assigned AS (
    SELECT EXISTS (
      SELECT 1
      FROM public.claims c
      WHERE c.item_id = p_item_id
        AND c.assigned_to = p_user
    ) AS assigned_check
  )

  SELECT
    -- Must be event member
    EXISTS (
      SELECT 1 FROM i
      JOIN public.event_members em
        ON em.event_id = i.event_id AND em.user_id = p_user
    )
    -- Must not be a recipient of the list
    AND NOT EXISTS (
      SELECT 1 FROM public.list_recipients lr
      JOIN i ON i.list_id = lr.list_id
      WHERE lr.user_id = p_user
    )
    -- If random assignment enabled, must be assigned to user OR user is admin
    AND (
      NOT (SELECT random_assignment_enabled FROM i)
      OR (SELECT admin_check FROM is_admin)
      OR (SELECT assigned_check FROM is_assigned)
    )
$function$;

COMMENT ON FUNCTION public.can_claim_item(uuid, uuid) IS
'Checks if a user can claim an item. For random assignment lists, only assigned users or admins can claim.';
