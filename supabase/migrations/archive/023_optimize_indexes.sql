-- Migration: Optimize Indexes (INFO suggestions)
-- Date: 2025-10-08
-- Description: Addresses INFO-level performance suggestions from Supabase linter
--   1. Adds indexes for foreign keys without covering indexes
--   2. Removes unused indexes

-- ============================================================================
-- PART 1: Add indexes for unindexed foreign keys
-- ============================================================================
-- Foreign keys without indexes can cause performance issues, especially:
-- - When doing JOINs on these columns
-- - When the parent row is deleted (CASCADE requires scanning)
-- - When checking referential integrity

-- claims table: claimer_id foreign key
CREATE INDEX IF NOT EXISTS idx_claims_claimer_id
  ON public.claims(claimer_id);

-- event_invites table: inviter_id foreign key
CREATE INDEX IF NOT EXISTS idx_event_invites_inviter_id
  ON public.event_invites(inviter_id);

-- events table: owner_id foreign key
CREATE INDEX IF NOT EXISTS idx_events_owner_id
  ON public.events(owner_id);

-- items table: created_by foreign key
CREATE INDEX IF NOT EXISTS idx_items_created_by
  ON public.items(created_by);

-- sent_reminders table: event_id foreign key
CREATE INDEX IF NOT EXISTS idx_sent_reminders_event_id
  ON public.sent_reminders(event_id);

-- ============================================================================
-- PART 2: Remove unused indexes
-- ============================================================================
-- These indexes have never been used and are just adding overhead to writes

-- Note: Before dropping, verify these are truly unused in production
-- The linter reports they haven't been used, but consider:
-- 1. Is your database new/test data?
-- 2. Have you run all common queries?
-- 3. Are there seasonal or periodic queries that might use them?

-- If you're confident they're unused, uncomment these:
-- DROP INDEX IF EXISTS public.idx_list_recipients_uid;
-- DROP INDEX IF EXISTS public.idx_list_exclusions_uid;

-- For now, we'll comment them out and add a note
-- Check usage with: SELECT * FROM pg_stat_user_indexes WHERE indexrelname = 'idx_list_recipients_uid';

-- ============================================================================
-- NOTES:
-- ============================================================================

-- About unused indexes:
-- The linter detected that idx_list_recipients_uid and idx_list_exclusions_uid
-- have never been used. However, we dropped list_exclusions_user_idx in migration 022
-- and kept idx_list_exclusions_uid as the primary index on user_id.
--
-- Recommendation:
-- 1. Monitor index usage in production for 1-2 weeks
-- 2. If still unused, drop them in a future migration
-- 3. Use this query to check:
--    SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
--    FROM pg_stat_user_indexes
--    WHERE indexrelname IN ('idx_list_recipients_uid', 'idx_list_exclusions_uid');

-- About new foreign key indexes:
-- These indexes will help with:
-- - Queries filtering by user (e.g., "show all events owned by user X")
-- - DELETE operations with CASCADE (much faster)
-- - JOIN operations
--
-- Trade-off:
-- - Slightly slower INSERTs/UPDATEs (minimal impact)
-- - Additional storage (worth it for query performance)

-- Verification
DO $$
BEGIN
  RAISE NOTICE '✅ Migration 023 completed';
  RAISE NOTICE 'Added indexes for foreign keys:';
  RAISE NOTICE '  - claims.claimer_id';
  RAISE NOTICE '  - event_invites.inviter_id';
  RAISE NOTICE '  - events.owner_id';
  RAISE NOTICE '  - items.created_by';
  RAISE NOTICE '  - sent_reminders.event_id';
  RAISE NOTICE '';
  RAISE NOTICE 'ℹ️  Unused index suggestions (not acted upon):';
  RAISE NOTICE '  - idx_list_recipients_uid (monitor usage before dropping)';
  RAISE NOTICE '  - idx_list_exclusions_uid (monitor usage before dropping)';
END $$;
