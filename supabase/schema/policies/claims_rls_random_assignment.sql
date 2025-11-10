-- RLS Policy updates for claims table to support random assignment
-- Members can only see claims assigned to them on random assignment lists (unless they're admins)

-- Drop existing claims SELECT policy and recreate with random assignment logic
DROP POLICY IF EXISTS "claims_select" ON public.claims;

CREATE POLICY "claims_select_with_random_assignment"
ON public.claims
AS PERMISSIVE
FOR SELECT
USING (
  -- User can see their own claims
  claimer_id = auth.uid()
  -- OR user can see claims for items they can view
  OR EXISTS (
    SELECT 1
    FROM public.items i
    JOIN public.lists l ON l.id = i.list_id
    WHERE i.id = claims.item_id
      AND public.can_view_list(l.id, auth.uid())
      AND (
        -- For non-random lists: show all claims if not recipient
        (
          l.random_assignment_enabled = false
          AND NOT EXISTS (
            SELECT 1 FROM public.list_recipients lr
            WHERE lr.list_id = l.id AND lr.user_id = auth.uid()
          )
        )
        -- For random lists: only show if assigned to user OR user is admin/owner
        OR (
          l.random_assignment_enabled = true
          AND (
            claims.assigned_to = auth.uid()
            OR l.created_by = auth.uid()
            OR EXISTS (
              SELECT 1 FROM public.event_members em
              WHERE em.event_id = l.event_id
                AND em.user_id = auth.uid()
                AND em.role = 'admin'
            )
            OR EXISTS (
              SELECT 1 FROM public.events e
              WHERE e.id = l.event_id AND e.owner_id = auth.uid()
            )
          )
        )
      )
  )
);

COMMENT ON POLICY "claims_select_with_random_assignment" ON public.claims IS
'Users can see their own claims, or claims on lists they can view. For random assignment lists, non-admin members only see claims assigned to them.';

-- Note: INSERT, UPDATE, and DELETE policies remain unchanged as they work through RPCs
