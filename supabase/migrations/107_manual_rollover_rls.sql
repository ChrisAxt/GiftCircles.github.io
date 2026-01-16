-- Migration: Manual Event Rollover - RLS Policies
-- Created: 2026-01-05
-- Purpose: Row Level Security for claimed_items_history table

BEGIN;

-- ============================================================================
-- RLS Policy for claimed_items_history
-- ============================================================================

-- Event members can view history for events they belong to
CREATE POLICY "Event members can view claimed items history"
  ON public.claimed_items_history FOR SELECT
  USING (public.is_event_member(event_id, auth.uid()));

COMMENT ON POLICY "Event members can view claimed items history" ON public.claimed_items_history IS
'Allows event members to view historical claimed items from previous event occurrences';

COMMIT;
