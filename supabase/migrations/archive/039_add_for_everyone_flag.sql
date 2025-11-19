-- Migration: Add for_everyone flag to lists
-- Date: 2025-01-17
-- Description: Add flag to indicate when a list is for all event members, allowing everyone to claim items

BEGIN;

-- Add for_everyone column to lists table
ALTER TABLE public.lists
ADD COLUMN IF NOT EXISTS for_everyone boolean NOT NULL DEFAULT false;

-- Add comment explaining the column
COMMENT ON COLUMN public.lists.for_everyone IS 'When true, this list is for all event members. All members can claim items (but cannot see who claimed them).';

COMMIT;
