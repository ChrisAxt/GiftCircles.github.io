-- Updated list_claims_for_user function to respect random assignments
-- For collaborative mode (combined random assignment), users see claims assigned to them even if they are recipients
-- For single random modes, recipients do not see claims
-- Admins and list owners see all claims regardless of assignment

CREATE OR REPLACE FUNCTION public.list_claims_for_user(p_item_ids uuid[])
RETURNS TABLE(item_id uuid, claimer_id uuid)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH me AS (SELECT auth.uid() AS uid),

  visible_items AS (
    SELECT i.id AS item_id, i.list_id
    FROM public.items i, me
    WHERE i.id = ANY(p_item_ids)
      AND public.can_view_list(i.list_id, (SELECT uid FROM me))
  ),

  -- Check if user is admin/owner of lists in question
  user_admin_lists AS (
    SELECT DISTINCT l.id AS list_id
    FROM visible_items vi
    CROSS JOIN me
    INNER JOIN public.lists l ON l.id = vi.list_id
    LEFT JOIN public.event_members em ON em.event_id = l.event_id AND em.user_id = me.uid
    LEFT JOIN public.events e ON e.id = l.event_id
    WHERE l.created_by = me.uid
       OR em.role = 'admin'
       OR e.owner_id = me.uid
  ),

  -- Check which lists have random assignment enabled and their mode
  list_assignment_modes AS (
    SELECT DISTINCT
      vi.list_id,
      l.random_assignment_enabled,
      l.random_receiver_assignment_enabled,
      -- Collaborative mode: both random features enabled
      (l.random_assignment_enabled = true AND l.random_receiver_assignment_enabled = true) as is_collaborative
    FROM visible_items vi
    INNER JOIN public.lists l ON l.id = vi.list_id
  ),

  -- Items where user is NOT a recipient (for non-collaborative lists)
  non_recipient_items AS (
    SELECT vi.item_id, vi.list_id
    FROM visible_items vi, me
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.list_recipients lr
      WHERE lr.list_id = vi.list_id
        AND lr.user_id = (SELECT uid FROM me)
    )
  ),

  -- For non-random lists OR admin users: show all claims
  claims_for_viewers AS (
    SELECT c.item_id, c.claimer_id
    FROM public.claims c
    JOIN non_recipient_items n ON n.item_id = c.item_id
    JOIN list_assignment_modes lam ON lam.list_id = n.list_id
    WHERE
      -- Not a random assignment list
      (COALESCE(lam.random_assignment_enabled, false) = false)
      -- OR user is admin/owner of the list
      OR EXISTS (SELECT 1 FROM user_admin_lists ual WHERE ual.list_id = n.list_id)
  ),

  -- For collaborative mode (combined random assignment): show claims assigned to user
  -- Even if user is also a recipient (which they always are in collaborative mode)
  collaborative_claims AS (
    SELECT c.item_id, c.claimer_id
    FROM public.claims c
    JOIN visible_items vi ON vi.item_id = c.item_id
    JOIN list_assignment_modes lam ON lam.list_id = vi.list_id
    WHERE lam.is_collaborative = true
      AND c.assigned_to = (SELECT uid FROM me)
      -- Don't show if user is admin (already shown in claims_for_viewers)
      AND NOT EXISTS (SELECT 1 FROM user_admin_lists ual WHERE ual.list_id = vi.list_id)
  ),

  -- For single random assignment mode (not collaborative): only show claims assigned to user
  -- AND user is not a recipient of the list
  single_random_claims AS (
    SELECT c.item_id, c.claimer_id
    FROM public.claims c
    JOIN non_recipient_items n ON n.item_id = c.item_id
    JOIN list_assignment_modes lam ON lam.list_id = n.list_id
    WHERE lam.random_assignment_enabled = true
      AND lam.is_collaborative = false
      AND c.assigned_to = (SELECT uid FROM me)
      -- Don't show if user is admin (already shown in claims_for_viewers)
      AND NOT EXISTS (SELECT 1 FROM user_admin_lists ual WHERE ual.list_id = n.list_id)
  ),

  -- Always show user's own claims
  my_claims AS (
    SELECT c.item_id, c.claimer_id
    FROM public.claims c, me
    WHERE c.item_id = ANY(p_item_ids)
      AND c.claimer_id = (SELECT uid FROM me)
  )

  SELECT * FROM claims_for_viewers
  UNION
  SELECT * FROM collaborative_claims
  UNION
  SELECT * FROM single_random_claims
  UNION
  SELECT * FROM my_claims;
$function$;

COMMENT ON FUNCTION public.list_claims_for_user(uuid[]) IS
'Returns claims visible to current user. For collaborative mode (combined random assignment), users see claims assigned to them even if they are recipients. For single random modes, recipients do not see claims. Admins always see all claims.';
