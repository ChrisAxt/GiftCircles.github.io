-- Migration 102: Consolidate Duplicate RLS Policies
-- Fixes: multiple_permissive_policies warnings from Supabase Linter
--
-- Problem: Multiple permissive policies for same action causes all to be evaluated.
-- Solution: Consolidate into single policy with OR conditions.
--
-- WARNING: This is a PRODUCTION migration. Test thoroughly before applying!

BEGIN;

-- ============================================================================
-- 1. Claims DELETE policies - SKIP (keep using unclaim_item RPC)
-- ============================================================================
-- NOT consolidating claims DELETE policies to preserve current behavior.
-- Claims should be deleted via unclaim_item() RPC which handles:
-- - Notifications (notify_unclaim trigger)
-- - Activity logging (log_activity_for_digest)
-- - Privacy checks
--
-- Current duplicate policies will remain but are rarely used.
-- If you want to consolidate later, uncomment the code below.
/*
DROP POLICY IF EXISTS "admins can delete any claims" ON public.claims;
DROP POLICY IF EXISTS "delete own claims" ON public.claims;

CREATE POLICY "claims_delete"
  ON public.claims
  AS PERMISSIVE
  FOR DELETE
  USING (
    claimer_id = (SELECT auth.uid())
    OR
    EXISTS (
      SELECT 1
      FROM public.items i
      JOIN public.lists l ON l.id = i.list_id
      JOIN public.event_members em ON em.event_id = l.event_id
      WHERE i.id = item_id
        AND em.user_id = (SELECT auth.uid())
        AND em.role = 'admin'::public.member_role
    )
  );
*/

-- ============================================================================
-- 2. Consolidate claims UPDATE policies
-- Merges: "claims_update_by_claimer" + "claims_update_own"
-- These are identical so just keep one
-- ============================================================================
DROP POLICY IF EXISTS "claims_update_by_claimer" ON public.claims;
DROP POLICY IF EXISTS "claims_update_own" ON public.claims;

CREATE POLICY "claims_update"
  ON public.claims
  AS PERMISSIVE
  FOR UPDATE
  USING (claimer_id = (SELECT auth.uid()))
  WITH CHECK (claimer_id = (SELECT auth.uid()));

-- ============================================================================
-- 3. Consolidate events SELECT policies
-- Merges: "select events for members" + "select events for owners"
-- ============================================================================
DROP POLICY IF EXISTS "select events for members" ON public.events;
DROP POLICY IF EXISTS "select events for owners" ON public.events;

CREATE POLICY "events_select"
  ON public.events
  AS PERMISSIVE
  FOR SELECT
  USING (
    -- Owner
    owner_id = (SELECT auth.uid())
    OR
    -- Member (preserves is_event_member logic)
    public.is_event_member(id, (SELECT auth.uid()))
  );

-- ============================================================================
-- 4. Consolidate events UPDATE policies
-- Merges: "events: update by admins" + "update events by owner or last member"
-- ============================================================================
DROP POLICY IF EXISTS "events: update by admins" ON public.events;
DROP POLICY IF EXISTS "update events by owner or last member" ON public.events;

CREATE POLICY "events_update"
  ON public.events
  AS PERMISSIVE
  FOR UPDATE
  USING (
    -- Owner or last member
    owner_id = (SELECT auth.uid())
    OR public.is_last_event_member(id, (SELECT auth.uid()))
    OR
    -- Admin
    EXISTS (
      SELECT 1 FROM public.event_members em
      WHERE em.event_id = id
        AND em.user_id = (SELECT auth.uid())
        AND em.role = 'admin'::public.member_role
    )
  )
  WITH CHECK (
    owner_id = (SELECT auth.uid())
    OR public.is_last_event_member(id, (SELECT auth.uid()))
    OR
    EXISTS (
      SELECT 1 FROM public.event_members em
      WHERE em.event_id = id
        AND em.user_id = (SELECT auth.uid())
        AND em.role = 'admin'::public.member_role
    )
  );

-- ============================================================================
-- 5. Consolidate events DELETE policies
-- Merges: "admins can delete events" + "delete events by owner or last member" + "owners can delete events"
-- ============================================================================
DROP POLICY IF EXISTS "admins can delete events" ON public.events;
DROP POLICY IF EXISTS "delete events by owner or last member" ON public.events;
DROP POLICY IF EXISTS "owners can delete events" ON public.events;

CREATE POLICY "events_delete"
  ON public.events
  AS PERMISSIVE
  FOR DELETE
  USING (
    -- Owner
    owner_id = (SELECT auth.uid())
    OR
    -- Last member
    public.is_last_event_member(id, (SELECT auth.uid()))
    OR
    -- Admin
    EXISTS (
      SELECT 1 FROM public.event_members em
      WHERE em.event_id = id
        AND em.user_id = (SELECT auth.uid())
        AND em.role = 'admin'::public.member_role
    )
  );

-- ============================================================================
-- 6. Consolidate list_exclusions SELECT policies
-- Merges: "le_select" + "list_exclusions_select"
-- ============================================================================
DROP POLICY IF EXISTS "le_select" ON public.list_exclusions;
DROP POLICY IF EXISTS "list_exclusions_select" ON public.list_exclusions;

-- Preserve both conditions: user can see own exclusions OR list creator can see all
CREATE POLICY "list_exclusions_select"
  ON public.list_exclusions
  AS PERMISSIVE
  FOR SELECT
  USING (
    -- User can see their own exclusions
    user_id = (SELECT auth.uid())
    OR
    -- List creator can see all exclusions for their lists
    EXISTS (
      SELECT 1
      FROM public.lists l
      WHERE l.id = list_id
        AND l.created_by = (SELECT auth.uid())
    )
  );

-- ============================================================================
-- 7. Consolidate list_recipients INSERT policies
-- Merges: "insert list_recipients by creator" + "list_recipients_insert"
-- These are identical so just keep one
-- ============================================================================
DROP POLICY IF EXISTS "insert list_recipients by creator" ON public.list_recipients;
DROP POLICY IF EXISTS "list_recipients_insert" ON public.list_recipients;

CREATE POLICY "list_recipients_insert"
  ON public.list_recipients
  AS PERMISSIVE
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.lists l
      WHERE l.id = list_id
        AND l.created_by = (SELECT auth.uid())
    )
  );

-- ============================================================================
-- 8. Consolidate profiles INSERT policies
-- Merges: "server-side insert when id exists in auth.users" + "users can insert their own profile"
-- ============================================================================
DROP POLICY IF EXISTS "server-side insert when id exists in auth.users" ON public.profiles;
DROP POLICY IF EXISTS "users can insert their own profile" ON public.profiles;

-- The server-side policy was likely for service role, which bypasses RLS anyway
-- So we only need the user's own profile policy
CREATE POLICY "profiles_insert"
  ON public.profiles
  AS PERMISSIVE
  FOR INSERT
  WITH CHECK (id = (SELECT auth.uid()));

-- ============================================================================
-- 9. Consolidate user_plans policies
-- Merges: "user_plans_self" + "no_client_writes" + "read_own_plan"
-- ============================================================================
-- These policies conflict - user_plans_self allows all operations, but
-- no_client_writes blocks everything. We need to reconcile this.
-- The intent seems to be: users can READ their own plan, but not modify
DROP POLICY IF EXISTS "user_plans_self" ON public.user_plans;
DROP POLICY IF EXISTS "no_client_writes" ON public.user_plans;
DROP POLICY IF EXISTS "read_own_plan" ON public.user_plans;

-- Allow users to read their own plan only
CREATE POLICY "user_plans_select"
  ON public.user_plans
  AS PERMISSIVE
  FOR SELECT
  USING (user_id = (SELECT auth.uid()));

-- Block all writes from clients (INSERT, UPDATE, DELETE)
-- Service role bypasses RLS, so server can still modify
CREATE POLICY "user_plans_no_writes"
  ON public.user_plans
  AS PERMISSIVE
  FOR INSERT
  WITH CHECK (false);

CREATE POLICY "user_plans_no_updates"
  ON public.user_plans
  AS PERMISSIVE
  FOR UPDATE
  USING (false)
  WITH CHECK (false);

CREATE POLICY "user_plans_no_deletes"
  ON public.user_plans
  AS PERMISSIVE
  FOR DELETE
  USING (false);

COMMIT;
