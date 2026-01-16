-- Migration: Manual Event Rollover - Schema
-- Created: 2026-01-05
-- Purpose: Add tracking columns for manual rollover and claimed items history

BEGIN;

-- ============================================================================
-- 1. Add rollover tracking columns to events table
-- ============================================================================

ALTER TABLE public.events
ADD COLUMN IF NOT EXISTS needs_rollover boolean DEFAULT false NOT NULL;

ALTER TABLE public.events
ADD COLUMN IF NOT EXISTS rollover_notification_sent boolean DEFAULT false NOT NULL;

ALTER TABLE public.events
ADD COLUMN IF NOT EXISTS last_rolled_at timestamp with time zone;

COMMENT ON COLUMN public.events.needs_rollover IS
'True when event_date has passed and recurrence != none. Set by daily cron job. Reset to false after manual rollover.';

COMMENT ON COLUMN public.events.rollover_notification_sent IS
'Whether rollover notification was sent after event_date passed. Prevents duplicate notifications. Reset to false after manual rollover.';

COMMENT ON COLUMN public.events.last_rolled_at IS
'Timestamp of last manual rollover. NULL if event has never been rolled over.';

-- ============================================================================
-- 2. Create claimed items history table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.claimed_items_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  rollover_date timestamp with time zone NOT NULL DEFAULT now(),
  items_snapshot jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE public.claimed_items_history ENABLE ROW LEVEL SECURITY;

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_claimed_items_history_event_id
  ON public.claimed_items_history(event_id);

CREATE INDEX IF NOT EXISTS idx_claimed_items_history_rollover_date
  ON public.claimed_items_history(rollover_date DESC);

COMMENT ON TABLE public.claimed_items_history IS
'Historical archive of claimed items from previous event occurrences. Created when event owner chooses "Keep as history" during manual rollover.';

COMMENT ON COLUMN public.claimed_items_history.items_snapshot IS
'JSONB array of claimed items: [{item_id, item_name, item_url, item_price, item_notes, list_id, list_name, claimer_id, claimer_name, quantity, purchased, claim_note, claimed_at}]';

COMMIT;
