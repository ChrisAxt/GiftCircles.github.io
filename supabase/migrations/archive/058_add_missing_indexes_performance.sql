-- Migration: Add missing composite indexes for RLS and query performance
-- Date: 2025-01-20
-- Description: Critical indexes to prevent full table scans in RLS policies and queries
--              These indexes target the most expensive queries identified in the codebase.

BEGIN;

-- ============================================================================
-- COMPOSITE INDEXES FOR RLS POLICY OPTIMIZATION
-- ============================================================================

-- Index for event_members RLS checks (event_id, user_id, role)
-- Used in almost every RLS policy to check admin status
CREATE INDEX IF NOT EXISTS idx_event_members_composite_rls
ON public.event_members(event_id, user_id, role)
WHERE role IS NOT NULL;

COMMENT ON INDEX idx_event_members_composite_rls IS
'Composite index for RLS policies checking admin/member status. Covers most common RLS pattern.';

-- Index for list_recipients composite lookups (list_id, user_id)
-- Used heavily in RLS to determine if user is a recipient
CREATE INDEX IF NOT EXISTS idx_list_recipients_composite
ON public.list_recipients(list_id, user_id)
WHERE user_id IS NOT NULL;

COMMENT ON INDEX idx_list_recipients_composite IS
'Composite index for checking recipient status in RLS policies and queries.';

-- Index for claims with assigned_to (for random assignment queries)
-- Existing partial index is good, but add composite with item_id
CREATE INDEX IF NOT EXISTS idx_claims_assigned_to_item
ON public.claims(assigned_to, item_id)
WHERE assigned_to IS NOT NULL;

COMMENT ON INDEX idx_claims_assigned_to_item IS
'Composite index for random assignment queries checking who is assigned to items.';

-- Index for items(list_id, assigned_recipient_id) for receiver assignment
CREATE INDEX IF NOT EXISTS idx_items_list_recipient_composite
ON public.items(list_id, assigned_recipient_id)
WHERE assigned_recipient_id IS NOT NULL;

COMMENT ON INDEX idx_items_list_recipient_composite IS
'Composite index for random receiver assignment queries.';

-- Index for lists with random assignment flags
CREATE INDEX IF NOT EXISTS idx_lists_random_modes
ON public.lists(event_id, random_assignment_enabled, random_receiver_assignment_enabled);

COMMENT ON INDEX idx_lists_random_modes IS
'Composite index for queries filtering by random assignment modes.';

-- Index for lists(id, event_id, created_by) - frequently joined
-- This may already exist from migration 041, ensuring it's here
CREATE INDEX IF NOT EXISTS idx_lists_composite_joins
ON public.lists(id, event_id, created_by);

COMMENT ON INDEX idx_lists_composite_joins IS
'Composite index covering most common list JOIN patterns and WHERE clauses.';

-- ============================================================================
-- INDEXES FOR SPECIFIC QUERY PATTERNS
-- ============================================================================

-- Index for events(owner_id) - checked in many RLS policies
CREATE INDEX IF NOT EXISTS idx_events_owner_id
ON public.events(owner_id);

COMMENT ON INDEX idx_events_owner_id IS
'Index for checking event ownership in RLS policies.';

-- Index for list_exclusions(list_id, user_id) - checked in claim visibility
CREATE INDEX IF NOT EXISTS idx_list_exclusions_composite
ON public.list_exclusions(list_id, user_id);

COMMENT ON INDEX idx_list_exclusions_composite IS
'Composite index for checking if user is excluded from a list.';

-- Index for items(created_by) - used to determine item ownership
CREATE INDEX IF NOT EXISTS idx_items_created_by
ON public.items(created_by);

COMMENT ON INDEX idx_items_created_by IS
'Index for checking item ownership and creator.';

-- Index for claims(claimer_id, purchased) - used in stats calculations
CREATE INDEX IF NOT EXISTS idx_claims_claimer_purchased
ON public.claims(claimer_id, purchased);

COMMENT ON INDEX idx_claims_claimer_purchased IS
'Composite index for calculating unpurchased claims per user.';

-- Index for event_invites(invitee_email, status) - for checking pending invites
CREATE INDEX IF NOT EXISTS idx_event_invites_email_status
ON public.event_invites(invitee_email, status)
WHERE status = 'pending';

COMMENT ON INDEX idx_event_invites_email_status IS
'Partial index for finding pending invites by email.';

-- ============================================================================
-- COVERING INDEXES FOR HOT QUERIES
-- ============================================================================

-- Covering index for event_member_stats queries
-- This table is already indexed but ensure optimal coverage
CREATE INDEX IF NOT EXISTS idx_event_member_stats_covering
ON public.event_member_stats(user_id, event_id)
INCLUDE (total_claims, unpurchased_claims);

COMMENT ON INDEX idx_event_member_stats_covering IS
'Covering index allowing index-only scans for user claim stats.';

-- ============================================================================
-- VACUUM ANALYZE TO UPDATE STATISTICS
-- ============================================================================

-- Update query planner statistics for all modified tables
ANALYZE public.event_members;
ANALYZE public.list_recipients;
ANALYZE public.claims;
ANALYZE public.items;
ANALYZE public.lists;
ANALYZE public.events;
ANALYZE public.list_exclusions;
ANALYZE public.event_invites;
ANALYZE public.event_member_stats;

-- Log completion
DO $$
BEGIN
  RAISE NOTICE 'Performance indexes created successfully. Run EXPLAIN ANALYZE on slow queries to verify usage.';
END;
$$;

COMMIT;
