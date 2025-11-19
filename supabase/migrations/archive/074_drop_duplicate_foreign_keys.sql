-- Drop duplicate foreign key constraints on claims table
--
-- Problem: PostgREST (Supabase JS client) can't handle nested selects when there are
-- multiple foreign keys between the same tables. This causes PGRST201 error.
--
-- Solution: Drop the duplicate fk_* constraints and keep the standard *_fkey ones.

BEGIN;

-- Drop duplicate foreign keys (keep the *_fkey versions which are standard PostgreSQL naming)
ALTER TABLE public.claims DROP CONSTRAINT IF EXISTS fk_claims_item_id;
ALTER TABLE public.claims DROP CONSTRAINT IF EXISTS fk_claims_claimer_id;
ALTER TABLE public.claims DROP CONSTRAINT IF EXISTS fk_claims_assigned_to;

-- Verify the standard foreign keys are still in place
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'claims_item_id_fkey'
      AND conrelid = 'claims'::regclass
  ) THEN
    RAISE EXCEPTION 'Standard foreign key claims_item_id_fkey is missing!';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'claims_claimer_id_fkey'
      AND conrelid = 'claims'::regclass
  ) THEN
    RAISE EXCEPTION 'Standard foreign key claims_claimer_id_fkey is missing!';
  END IF;

  RAISE NOTICE 'Successfully dropped duplicate foreign keys. Standard foreign keys remain in place.';
END $$;

COMMIT;
