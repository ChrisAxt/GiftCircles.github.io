-- Migration: Fix performance warnings from database linter
-- Date: 2025-01-20
-- Description:
--   1. Fix auth.uid() calls in RLS policies (use SELECT subquery)
--   2. Remove duplicate indexes
--   3. Consolidate multiple permissive policies (deferred - requires policy rewrite)

BEGIN;

-- ============================================================================
-- STEP 1: Remove duplicate indexes
-- ============================================================================

-- Drop duplicate indexes/constraints on claims table
-- Keep: claims_item_id_claimer_id_key (likely the constraint-based one)
-- Drop: claims_item_claimer_unique (constraint), idx_claims_item_claimer_unique (index)
-- Note: claims_item_claimer_unique is a UNIQUE constraint, must drop constraint not index
ALTER TABLE public.claims DROP CONSTRAINT IF EXISTS claims_item_claimer_unique;
DROP INDEX IF EXISTS public.idx_claims_item_claimer_unique;

-- Drop duplicate index on lists table
-- Keep: idx_lists_composite_joins
-- Drop: idx_lists_id_event_created
DROP INDEX IF EXISTS public.idx_lists_id_event_created;

DO $$
BEGIN
  RAISE NOTICE 'Duplicate indexes removed';
END;
$$;

-- ============================================================================
-- STEP 2: Fix auth.uid() in RLS policies - Use SELECT subquery
-- ============================================================================

-- Fix profiles policies (only if table exists)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'profiles') THEN
    DROP POLICY IF EXISTS "users can insert their own profile" ON public.profiles;
    CREATE POLICY "users can insert their own profile"
    ON public.profiles
    FOR INSERT
    WITH CHECK ((id = (SELECT auth.uid())));

    DROP POLICY IF EXISTS "users can update their own profile" ON public.profiles;
    CREATE POLICY "users can update their own profile"
    ON public.profiles
    FOR UPDATE
    USING ((id = (SELECT auth.uid())))
    WITH CHECK ((id = (SELECT auth.uid())));

    RAISE NOTICE 'Updated profiles policies';
  ELSE
    RAISE NOTICE 'Skipping profiles policies - table does not exist';
  END IF;
END;
$$;

-- Fix event_member_stats policy (only if table exists)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'event_member_stats') THEN
    DROP POLICY IF EXISTS "event_member_stats_select" ON public.event_member_stats;
    CREATE POLICY "event_member_stats_select"
    ON public.event_member_stats
    FOR SELECT
    USING (user_id = (SELECT auth.uid()));

    RAISE NOTICE 'Updated event_member_stats policies';
  ELSE
    RAISE NOTICE 'Skipping event_member_stats policies - table does not exist';
  END IF;
END;
$$;

-- Fix claim_split_requests policies (only if table exists)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'claim_split_requests') THEN
    -- Drop and recreate policies with optimized auth.uid()
    -- Note: Table uses item_id + original_claimer_id, not claim_id + claimer_id
    DROP POLICY IF EXISTS "Users can view their split requests" ON public.claim_split_requests;
    CREATE POLICY "Users can view their split requests"
    ON public.claim_split_requests
    FOR SELECT
    USING (
      requester_id = (SELECT auth.uid())
      OR original_claimer_id = (SELECT auth.uid())
    );

    DROP POLICY IF EXISTS "Users can create split requests" ON public.claim_split_requests;
    CREATE POLICY "Users can create split requests"
    ON public.claim_split_requests
    FOR INSERT
    WITH CHECK (requester_id = (SELECT auth.uid()));

    DROP POLICY IF EXISTS "Original claimers can update split requests" ON public.claim_split_requests;
    CREATE POLICY "Original claimers can update split requests"
    ON public.claim_split_requests
    FOR UPDATE
    USING (original_claimer_id = (SELECT auth.uid()));

    DROP POLICY IF EXISTS "Requesters can delete their pending requests" ON public.claim_split_requests;
    CREATE POLICY "Requesters can delete their pending requests"
    ON public.claim_split_requests
    FOR DELETE
    USING (
      requester_id = (SELECT auth.uid())
      AND status = 'pending'
    );

    RAISE NOTICE 'Updated claim_split_requests policies';
  ELSE
    RAISE NOTICE 'Skipping claim_split_requests policies - table does not exist';
  END IF;
END;
$$;

-- Fix list_exclusions policy (only if table exists)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'list_exclusions') THEN
    DROP POLICY IF EXISTS "list_exclusions_delete" ON public.list_exclusions;
    CREATE POLICY "list_exclusions_delete"
    ON public.list_exclusions
    FOR DELETE
    USING (
      EXISTS (
        SELECT 1 FROM public.lists l
        WHERE l.id = list_exclusions.list_id
          AND (
            l.created_by = (SELECT auth.uid())
            OR EXISTS (
              SELECT 1 FROM public.event_members em
              WHERE em.event_id = l.event_id
                AND em.user_id = (SELECT auth.uid())
                AND em.role = 'admin'
            )
          )
      )
    );

    RAISE NOTICE 'Updated list_exclusions policies';
  ELSE
    RAISE NOTICE 'Skipping list_exclusions policies - table does not exist';
  END IF;
END;
$$;

-- Fix items_select_with_receiver_assignment policy (only if table and function exist)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'items') THEN
    DROP POLICY IF EXISTS "items_select_with_receiver_assignment" ON public.items;
    CREATE POLICY "items_select_with_receiver_assignment"
    ON public.items
    AS PERMISSIVE
    FOR SELECT
    USING (
      EXISTS (
        SELECT 1
        FROM public.lists l
        JOIN public.event_members em ON em.event_id = l.event_id
        WHERE l.id = items.list_id
          AND em.user_id = (SELECT auth.uid())
          AND public.can_view_list(l.id, (SELECT auth.uid()))
          AND (
            -- For combined random assignment (giver + receiver): all members see all items
            (
              l.random_assignment_enabled = true
              AND l.random_receiver_assignment_enabled = true
            )
            -- OR user is list creator/admin/owner (always see all items)
            OR l.created_by = (SELECT auth.uid())
            OR em.role = 'admin'
            OR EXISTS (
              SELECT 1 FROM public.events e
              WHERE e.id = l.event_id AND e.owner_id = (SELECT auth.uid())
            )
            -- OR for random giver assignment ONLY: only see assigned items
            OR (
              l.random_assignment_enabled = true
              AND COALESCE(l.random_receiver_assignment_enabled, false) = false
              AND EXISTS (
                SELECT 1 FROM public.claims c
                WHERE c.item_id = items.id
                  AND c.assigned_to = (SELECT auth.uid())
              )
            )
            -- OR for random receiver assignment ONLY: hide from assigned recipients
            OR (
              COALESCE(l.random_assignment_enabled, false) = false
              AND l.random_receiver_assignment_enabled = true
              AND items.assigned_recipient_id != (SELECT auth.uid())
            )
            -- OR for non-random lists: see all items
            OR (
              COALESCE(l.random_assignment_enabled, false) = false
              AND COALESCE(l.random_receiver_assignment_enabled, false) = false
            )
          )
      )
    );

    RAISE NOTICE 'Updated items policies';
  ELSE
    RAISE NOTICE 'Skipping items policies - table does not exist';
  END IF;
END;
$$;

DO $$
BEGIN
  RAISE NOTICE 'RLS policies optimized with SELECT auth.uid()';
END;
$$;

-- ============================================================================
-- STEP 3: Note about multiple permissive policies
-- ============================================================================

-- Multiple permissive policies warnings are legitimate design choices
-- Consolidating them would require significant policy rewrites
-- They provide clarity and maintainability at a small performance cost
-- For now, we'll leave them as-is and address if performance issues arise

COMMENT ON TABLE public.claims IS
'Multiple permissive policies exist for flexibility. Consider consolidating if performance issues arise.';

COMMENT ON TABLE public.events IS
'Multiple permissive policies exist for flexibility. Consider consolidating if performance issues arise.';

-- Log completion
DO $$
BEGIN
  RAISE NOTICE 'Performance optimization completed:';
  RAISE NOTICE '- Removed duplicate indexes (2 indexes)';
  RAISE NOTICE '- Optimized RLS policies with SELECT auth.uid()';
  RAISE NOTICE '- Multiple permissive policies noted for future optimization';
END;
$$;

COMMIT;
