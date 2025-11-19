-- Migration: Add random assignment feature to lists
-- Date: 2025-01-14
-- Description: Add columns to support random item assignment feature where items are automatically assigned to members

BEGIN;

-- Add random assignment columns to lists table
ALTER TABLE public.lists
ADD COLUMN IF NOT EXISTS random_assignment_enabled boolean NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS random_assignment_mode text CHECK (random_assignment_mode IN ('one_per_member', 'distribute_all')),
ADD COLUMN IF NOT EXISTS random_assignment_executed_at timestamp with time zone;

-- Add assigned_to column to claims table to distinguish random assignments from manual claims
ALTER TABLE public.claims
ADD COLUMN IF NOT EXISTS assigned_to uuid REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Add index on assigned_to for performance
CREATE INDEX IF NOT EXISTS idx_claims_assigned_to ON public.claims(assigned_to);

-- Add unique constraint to prevent duplicate claims
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'claims_item_claimer_unique'
  ) THEN
    ALTER TABLE public.claims
    ADD CONSTRAINT claims_item_claimer_unique
    UNIQUE (item_id, claimer_id);
  END IF;
END $$;

-- Add comment explaining the assigned_to column
COMMENT ON COLUMN public.claims.assigned_to IS 'For random assignment lists: the user this item was assigned to. NULL for manual claims.';
COMMENT ON COLUMN public.lists.random_assignment_enabled IS 'When true, items are randomly assigned and members can only see their assignments.';
COMMENT ON COLUMN public.lists.random_assignment_mode IS 'Assignment mode: one_per_member (1 item each) or distribute_all (all items distributed evenly).';
COMMENT ON COLUMN public.lists.random_assignment_executed_at IS 'Timestamp of the last random assignment execution.';

COMMIT;
