-- Migration: Add 'unclaim' to daily_activity_log activity_type check constraint
-- Created: 2025-11-16
-- Purpose: Fix check constraint violation when unclaiming items
-- The notify_unclaim trigger tries to log 'unclaim' activity, but the check constraint
-- only allows 'new_list', 'new_item', and 'new_claim'

BEGIN;

-- Drop the existing check constraint
ALTER TABLE public.daily_activity_log
  DROP CONSTRAINT IF EXISTS daily_activity_log_activity_type_check;

-- Add the updated check constraint that includes 'unclaim'
ALTER TABLE public.daily_activity_log
  ADD CONSTRAINT daily_activity_log_activity_type_check
  CHECK (activity_type = ANY (ARRAY['new_list'::text, 'new_item'::text, 'new_claim'::text, 'unclaim'::text]));

COMMIT;
