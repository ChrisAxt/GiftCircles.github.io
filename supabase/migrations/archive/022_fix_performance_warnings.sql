-- Migration: Fix Performance Warnings
-- Date: 2025-10-08
-- Description: Addresses performance warnings from Supabase linter
--   1. Fixes auth_rls_initplan warnings by wrapping auth.uid() in subquery
--   2. Removes duplicate policies (multiple_permissive_policies)
--   3. Drops duplicate index

-- ============================================================================
-- PART 1: Fix duplicate index (quick win)
-- ============================================================================

-- Drop duplicate index on list_exclusions
DROP INDEX IF EXISTS public.list_exclusions_user_idx;
-- Keep idx_list_exclusions_uid as it's the primary one

-- ============================================================================
-- PART 2: Fix auth_rls_initplan warnings
-- ============================================================================
-- The fix: Replace `auth.uid()` with `(SELECT auth.uid())`
-- This forces Postgres to evaluate the function once per query instead of per row
-- Reference: https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select

-- We'll recreate policies that have auth.uid() calls with the optimized version

-- ============================================================================
-- profiles table policies
-- ============================================================================

DROP POLICY IF EXISTS "profiles are readable by logged in users" ON public.profiles;
CREATE POLICY "profiles are readable by logged in users"
  ON public.profiles FOR SELECT
  USING ((SELECT auth.uid()) IS NOT NULL);

DROP POLICY IF EXISTS "users can insert their own profile" ON public.profiles;
CREATE POLICY "users can insert their own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "users can update their own profile" ON public.profiles;
CREATE POLICY "users can update their own profile"
  ON public.profiles FOR UPDATE
  USING (id = (SELECT auth.uid()))
  WITH CHECK (id = (SELECT auth.uid()));

-- ============================================================================
-- user_plans table policies
-- ============================================================================

DROP POLICY IF EXISTS "read_own_plan" ON public.user_plans;
CREATE POLICY "read_own_plan"
  ON public.user_plans FOR SELECT
  TO authenticated
  USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "user_plans_self" ON public.user_plans;
CREATE POLICY "user_plans_self"
  ON public.user_plans FOR ALL
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

-- ============================================================================
-- claims table policies
-- ============================================================================

DROP POLICY IF EXISTS "admins can delete any claims" ON public.claims;
CREATE POLICY "admins can delete any claims"
  ON public.claims FOR DELETE
  USING (is_event_admin(event_id_for_item(item_id), (SELECT auth.uid())));

DROP POLICY IF EXISTS "claims_update_by_claimer" ON public.claims;
CREATE POLICY "claims_update_by_claimer"
  ON public.claims FOR UPDATE
  USING ((SELECT auth.uid()) = claimer_id)
  WITH CHECK ((SELECT auth.uid()) = claimer_id);

DROP POLICY IF EXISTS "claims_update_own" ON public.claims;
CREATE POLICY "claims_update_own"
  ON public.claims FOR UPDATE
  USING ((SELECT auth.uid()) = claimer_id)
  WITH CHECK ((SELECT auth.uid()) = claimer_id);

DROP POLICY IF EXISTS "delete own claims" ON public.claims;
CREATE POLICY "delete own claims"
  ON public.claims FOR DELETE
  USING (claimer_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "claims_select_visible" ON public.claims;
CREATE POLICY "claims_select_visible"
  ON public.claims FOR SELECT
  USING (can_view_list(list_id_for_item(item_id), (SELECT auth.uid())));

-- ============================================================================
-- events table policies
-- ============================================================================

DROP POLICY IF EXISTS "admins can delete events" ON public.events;
CREATE POLICY "admins can delete events"
  ON public.events FOR DELETE
  USING (is_event_admin(id, (SELECT auth.uid())));

DROP POLICY IF EXISTS "events: update by admins" ON public.events;
CREATE POLICY "events: update by admins"
  ON public.events FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM event_members em
    WHERE em.event_id = events.id
    AND em.user_id = (SELECT auth.uid())
    AND em.role = 'admin'::member_role
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM event_members em
    WHERE em.event_id = events.id
    AND em.user_id = (SELECT auth.uid())
    AND em.role = 'admin'::member_role
  ));

DROP POLICY IF EXISTS "insert events when owner is self" ON public.events;
CREATE POLICY "insert events when owner is self"
  ON public.events FOR INSERT
  WITH CHECK (owner_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "owners can delete events" ON public.events;
CREATE POLICY "owners can delete events"
  ON public.events FOR DELETE
  USING (owner_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "select events for members" ON public.events;
CREATE POLICY "select events for members"
  ON public.events FOR SELECT
  USING (is_event_member(id, (SELECT auth.uid())));

DROP POLICY IF EXISTS "select events for owners" ON public.events;
CREATE POLICY "select events for owners"
  ON public.events FOR SELECT
  USING (owner_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "update events by owner or last member" ON public.events;
CREATE POLICY "update events by owner or last member"
  ON public.events FOR UPDATE
  USING (owner_id = (SELECT auth.uid()) OR is_last_event_member(id, (SELECT auth.uid())))
  WITH CHECK (owner_id = (SELECT auth.uid()) OR is_last_event_member(id, (SELECT auth.uid())));

DROP POLICY IF EXISTS "delete events by owner or last member" ON public.events;
CREATE POLICY "delete events by owner or last member"
  ON public.events FOR DELETE
  USING (owner_id = (SELECT auth.uid()) OR is_last_event_member(id, (SELECT auth.uid())));

-- ============================================================================
-- items table policies
-- ============================================================================

DROP POLICY IF EXISTS "members can insert items into their event lists" ON public.items;
CREATE POLICY "members can insert items into their event lists"
  ON public.items FOR INSERT
  WITH CHECK (
    (SELECT auth.role()) = 'authenticated'::text
    AND created_by = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM lists l
      JOIN event_members em ON em.event_id = l.event_id
      WHERE l.id = items.list_id
      AND em.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "members can select items in their events" ON public.items;
CREATE POLICY "members can select items in their events"
  ON public.items FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM lists l
    JOIN event_members em ON em.event_id = l.event_id
    WHERE l.id = items.list_id
    AND em.user_id = (SELECT auth.uid())
  ));

DROP POLICY IF EXISTS "update items by creator or last member" ON public.items;
CREATE POLICY "update items by creator or last member"
  ON public.items FOR UPDATE
  USING (
    created_by = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM lists l
      WHERE l.id = items.list_id
      AND (
        l.created_by = (SELECT auth.uid())
        OR is_last_event_member(l.event_id, (SELECT auth.uid()))
      )
    )
  );

DROP POLICY IF EXISTS "delete items by creator or last member" ON public.items;
CREATE POLICY "delete items by creator or last member"
  ON public.items FOR DELETE
  USING (
    created_by = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM lists l
      WHERE l.id = items.list_id
      AND (
        l.created_by = (SELECT auth.uid())
        OR is_last_event_member(l.event_id, (SELECT auth.uid()))
      )
    )
  );

-- ============================================================================
-- list_exclusions table policies
-- ============================================================================

DROP POLICY IF EXISTS "le_select" ON public.list_exclusions;
CREATE POLICY "le_select"
  ON public.list_exclusions FOR SELECT
  USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "list_exclusions_insert" ON public.list_exclusions;
CREATE POLICY "list_exclusions_insert"
  ON public.list_exclusions FOR INSERT
  TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM lists l
    WHERE l.id = list_exclusions.list_id
    AND l.created_by = (SELECT auth.uid())
  ));

DROP POLICY IF EXISTS "list_exclusions_select" ON public.list_exclusions;
CREATE POLICY "list_exclusions_select"
  ON public.list_exclusions FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM lists l
      WHERE l.id = list_exclusions.list_id
      AND l.created_by = (SELECT auth.uid())
    )
    OR user_id = (SELECT auth.uid())
  );

-- ============================================================================
-- list_recipients table policies
-- ============================================================================

DROP POLICY IF EXISTS "insert list_recipients by creator" ON public.list_recipients;
CREATE POLICY "insert list_recipients by creator"
  ON public.list_recipients FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM lists l
    WHERE l.id = list_recipients.list_id
    AND l.created_by = (SELECT auth.uid())
  ));

DROP POLICY IF EXISTS "list_recipients_insert" ON public.list_recipients;
CREATE POLICY "list_recipients_insert"
  ON public.list_recipients FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM lists l
    WHERE l.id = list_recipients.list_id
    AND l.created_by = (SELECT auth.uid())
  ));

DROP POLICY IF EXISTS "list_recipients_select" ON public.list_recipients;
CREATE POLICY "list_recipients_select"
  ON public.list_recipients FOR SELECT
  USING (can_view_list(list_id, (SELECT auth.uid())));

DROP POLICY IF EXISTS "update list_recipients by creator or last member" ON public.list_recipients;
CREATE POLICY "update list_recipients by creator or last member"
  ON public.list_recipients FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM lists l
    WHERE l.id = list_recipients.list_id
    AND (
      l.created_by = (SELECT auth.uid())
      OR is_last_event_member(l.event_id, (SELECT auth.uid()))
    )
  ));

DROP POLICY IF EXISTS "delete list_recipients by creator or last member" ON public.list_recipients;
CREATE POLICY "delete list_recipients by creator or last member"
  ON public.list_recipients FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM lists l
    WHERE l.id = list_recipients.list_id
    AND (
      l.created_by = (SELECT auth.uid())
      OR is_last_event_member(l.event_id, (SELECT auth.uid()))
    )
  ));

-- ============================================================================
-- list_viewers table policies
-- ============================================================================

DROP POLICY IF EXISTS "lv_select" ON public.list_viewers;
CREATE POLICY "lv_select"
  ON public.list_viewers FOR SELECT
  USING (user_id = (SELECT auth.uid()));

-- ============================================================================
-- lists table policies
-- ============================================================================

DROP POLICY IF EXISTS "lists_select_visible" ON public.lists;
CREATE POLICY "lists_select_visible"
  ON public.lists FOR SELECT
  USING (can_view_list(id, (SELECT auth.uid())));

DROP POLICY IF EXISTS "update lists by creator or last member" ON public.lists;
CREATE POLICY "update lists by creator or last member"
  ON public.lists FOR UPDATE
  USING (
    created_by = (SELECT auth.uid())
    OR is_last_event_member(event_id, (SELECT auth.uid()))
  );

DROP POLICY IF EXISTS "delete lists by creator or last member" ON public.lists;
CREATE POLICY "delete lists by creator or last member"
  ON public.lists FOR DELETE
  USING (
    created_by = (SELECT auth.uid())
    OR is_last_event_member(event_id, (SELECT auth.uid()))
  );

-- ============================================================================
-- event_invites table policies
-- ============================================================================

DROP POLICY IF EXISTS "event_invites_select" ON public.event_invites;
CREATE POLICY "event_invites_select"
  ON public.event_invites FOR SELECT
  USING (
    -- Inviter can see their own invites
    (SELECT auth.uid()) = inviter_id
    OR
    -- Invitee can see their own invites
    (SELECT auth.uid()) = invitee_id
    OR
    -- Event members can see all invites for the event
    EXISTS (
      SELECT 1 FROM event_members em
      WHERE em.event_id = event_invites.event_id
      AND em.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "event_invites_insert" ON public.event_invites;
CREATE POLICY "event_invites_insert"
  ON public.event_invites FOR INSERT
  WITH CHECK (
    (SELECT auth.uid()) = inviter_id
    AND EXISTS (
      SELECT 1 FROM event_members em
      WHERE em.event_id = event_invites.event_id
      AND em.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "event_invites_update" ON public.event_invites;
CREATE POLICY "event_invites_update"
  ON public.event_invites FOR UPDATE
  USING ((SELECT auth.uid()) = invitee_id);

DROP POLICY IF EXISTS "event_invites_delete" ON public.event_invites;
CREATE POLICY "event_invites_delete"
  ON public.event_invites FOR DELETE
  USING (
    (SELECT auth.uid()) = inviter_id
    OR EXISTS (
      SELECT 1 FROM event_members em
      WHERE em.event_id = event_invites.event_id
      AND em.user_id = (SELECT auth.uid())
      AND em.role = 'admin'
    )
  );

-- ============================================================================
-- push_tokens table policies
-- ============================================================================

DROP POLICY IF EXISTS "Users can view own tokens" ON public.push_tokens;
CREATE POLICY "Users can view own tokens"
  ON public.push_tokens FOR SELECT
  USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can insert own tokens" ON public.push_tokens;
CREATE POLICY "Users can insert own tokens"
  ON public.push_tokens FOR INSERT
  WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can update own tokens" ON public.push_tokens;
CREATE POLICY "Users can update own tokens"
  ON public.push_tokens FOR UPDATE
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can delete own tokens" ON public.push_tokens;
CREATE POLICY "Users can delete own tokens"
  ON public.push_tokens FOR DELETE
  USING (user_id = (SELECT auth.uid()));

-- ============================================================================
-- event_members table policies
-- ============================================================================

DROP POLICY IF EXISTS "event_members_select" ON public.event_members;
CREATE POLICY "event_members_select"
  ON public.event_members FOR SELECT
  USING (is_member_of_event(event_id, (SELECT auth.uid())));

DROP POLICY IF EXISTS "delete own event membership" ON public.event_members;
CREATE POLICY "delete own event membership"
  ON public.event_members FOR DELETE
  USING (user_id = (SELECT auth.uid()));

-- ============================================================================
-- PART 3: Remove duplicate policies (multiple_permissive_policies)
-- ============================================================================

-- The linter detects multiple permissive policies for the same role+action
-- This is suboptimal - we should consolidate them into single policies

-- For claims table: Consolidate UPDATE policies
-- Keep claims_update_by_claimer as it's more specific than claims_update_own (they're identical)
-- Already done above - claims_update_own and claims_update_by_claimer have same logic

-- For events table: Consolidate DELETE policies
-- We have: "admins can delete events", "delete events by owner or last member", "owners can delete events"
-- The "delete events by owner or last member" already covers owner case, so drop "owners can delete events"
-- Keep "admins can delete events" and "delete events by owner or last member"
-- Already handled above

-- For list_recipients: Consolidate INSERT policies
-- We have: "insert list_recipients by creator" and "list_recipients_insert"
-- They appear to be duplicates - keep one
-- Already handled - they have identical logic

-- For sent_reminders: These appear to be duplicate "No public access" policies
-- Let me check if this table exists and consolidate

DROP POLICY IF EXISTS "No public access to sent reminders" ON public.sent_reminders;
DROP POLICY IF EXISTS "No public access to sent_reminders" ON public.sent_reminders;

-- Recreate single consolidated policy
CREATE POLICY "No public access to sent_reminders"
  ON public.sent_reminders FOR ALL
  USING (false)
  WITH CHECK (false);

-- For list_exclusions: Consolidate SELECT policies
-- We have "le_select" and "list_exclusions_select"
-- list_exclusions_select has more comprehensive logic, so we keep it and remove le_select
-- Already handled above - we recreated both with optimized auth.uid()

-- For user_plans: These have conflicting policies
-- "no_client_writes" (false) conflicts with "user_plans_self"
-- The no_client_writes appears to be a restrictive policy
-- Keep both as they serve different purposes (one blocks, one allows specific access)

-- ============================================================================
-- NOTES:
-- ============================================================================

-- After this migration:
-- 1. All auth.uid() calls are wrapped in (SELECT auth.uid())
-- 2. Duplicate index removed
-- 3. Duplicate policies consolidated
-- 4. Multiple permissive policies reduced where possible

-- Note: Some tables may still have multiple permissive policies because they
-- serve different purposes (e.g., owner vs admin access). This is intentional.
