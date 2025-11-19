-- Migration: Move Extensions from Public Schema (Requires Elevated Privileges)
-- Date: 2025-10-08
-- Description: Moves pgtap extension from public schema to extensions schema
--
-- NOTE: pg_net is a Supabase-managed extension that does not support SET SCHEMA.
-- It must remain in the public schema. This is a known limitation and the linter
-- warning can be safely ignored for pg_net.
--
-- Reference: https://github.com/supabase/pg_net

-- Create extensions schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS extensions;

-- Attempt to move pgtap extension from public to extensions schema
-- pgtap is used for testing and CAN be moved
DO $$
BEGIN
  -- Check if pgtap exists and is in public schema
  IF EXISTS (
    SELECT 1
    FROM pg_extension e
    JOIN pg_namespace n ON e.extnamespace = n.oid
    WHERE e.extname = 'pgtap'
    AND n.nspname = 'public'
  ) THEN
    -- Move pgtap to extensions schema
    ALTER EXTENSION pgtap SET SCHEMA extensions;
    RAISE NOTICE 'Successfully moved pgtap extension to extensions schema';
  ELSE
    RAISE NOTICE 'pgtap extension not found in public schema, skipping';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Failed to move pgtap extension: %. This may require elevated privileges.', SQLERRM;
END $$;

-- ============================================================================
-- NOTES:
-- ============================================================================
--
-- 1. pg_net extension:
--    The pg_net extension is managed by Supabase and does NOT support SET SCHEMA.
--    The linter warning "extension_in_public" for pg_net can be safely ignored.
--    This is a platform limitation, not a security issue.
--
-- 2. pgtap extension:
--    If the above fails due to permissions, you can try running this via
--    the Supabase SQL Editor with elevated privileges, or simply leave pgtap
--    in the public schema (it's only used for testing).
