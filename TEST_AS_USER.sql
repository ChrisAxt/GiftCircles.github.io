-- Test list_claims_for_user as a specific user
-- This bypasses auth.uid() by testing the logic directly

-- First, verify claims exist
SELECT
  c.id as claim_id,
  c.item_id,
  c.claimer_id,
  c.assigned_to,
  i.name as item_name,
  l.name as list_name
FROM claims c
JOIN items i ON i.id = c.item_id
JOIN lists l ON l.id = i.list_id
WHERE l.id = '4ed8df20-1eac-4a6a-ad34-282483043e43';

-- Test if the function WOULD work for user 962f043b-340e-4f3f-9d45-2f3816580648
-- (This simulates what happens when that user calls the function)
SELECT DISTINCT c.item_id, c.claimer_id, i.name as item_name
FROM public.claims c
INNER JOIN public.items i ON i.id = c.item_id
INNER JOIN public.lists l ON l.id = i.list_id
WHERE
  c.item_id = ANY(ARRAY(SELECT id FROM items WHERE list_id = '4ed8df20-1eac-4a6a-ad34-282483043e43'))
  AND EXISTS (
    SELECT 1 FROM public.event_members em
    WHERE em.event_id = l.event_id AND em.user_id = '962f043b-340e-4f3f-9d45-2f3816580648'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.list_exclusions le
    WHERE le.list_id = l.id AND le.user_id = '962f043b-340e-4f3f-9d45-2f3816580648'
  )
  AND (
    c.claimer_id = '962f043b-340e-4f3f-9d45-2f3816580648'
    OR l.created_by = '962f043b-340e-4f3f-9d45-2f3816580648'
    OR EXISTS (
      SELECT 1 FROM public.event_members em
      WHERE em.event_id = l.event_id
        AND em.user_id = '962f043b-340e-4f3f-9d45-2f3816580648'
        AND em.role = 'admin'
    )
    OR EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = l.event_id AND e.owner_id = '962f043b-340e-4f3f-9d45-2f3816580648'
    )
    OR (
      COALESCE(l.random_assignment_enabled, false) = true
      AND COALESCE(l.random_receiver_assignment_enabled, false) = true
      AND c.assigned_to = '962f043b-340e-4f3f-9d45-2f3816580648'
    )
  );

-- Test for the OTHER user (0881f0e0-4254-4f76-b487-99b40dd08f10)
SELECT DISTINCT c.item_id, c.claimer_id, i.name as item_name
FROM public.claims c
INNER JOIN public.items i ON i.id = c.item_id
INNER JOIN public.lists l ON l.id = i.list_id
WHERE
  c.item_id = ANY(ARRAY(SELECT id FROM items WHERE list_id = '4ed8df20-1eac-4a6a-ad34-282483043e43'))
  AND EXISTS (
    SELECT 1 FROM public.event_members em
    WHERE em.event_id = l.event_id AND em.user_id = '0881f0e0-4254-4f76-b487-99b40dd08f10'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.list_exclusions le
    WHERE le.list_id = l.id AND le.user_id = '0881f0e0-4254-4f76-b487-99b40dd08f10'
  )
  AND (
    c.claimer_id = '0881f0e0-4254-4f76-b487-99b40dd08f10'
    OR l.created_by = '0881f0e0-4254-4f76-b487-99b40dd08f10'
    OR EXISTS (
      SELECT 1 FROM public.event_members em
      WHERE em.event_id = l.event_id
        AND em.user_id = '0881f0e0-4254-4f76-b487-99b40dd08f10'
        AND em.role = 'admin'
    )
    OR EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = l.event_id AND e.owner_id = '0881f0e0-4254-4f76-b487-99b40dd08f10'
    )
    OR (
      COALESCE(l.random_assignment_enabled, false) = true
      AND COALESCE(l.random_receiver_assignment_enabled, false) = true
      AND c.assigned_to = '0881f0e0-4254-4f76-b487-99b40dd08f10'
    )
  );
