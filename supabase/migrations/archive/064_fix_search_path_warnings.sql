-- Migration: Fix search_path warnings for all functions
-- Date: 2025-01-20
-- Description: Add SET search_path to functions that are missing it
--              This prevents search path injection attacks

BEGIN;

-- ============================================================================
-- Fix validation functions (from migration 061)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.validate_uuid(p_value text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $$
BEGIN
  -- Try to cast to UUID
  PERFORM p_value::uuid;
  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_email(p_email text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $$
BEGIN
  RETURN p_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';
END;
$$;

CREATE OR REPLACE FUNCTION public.sanitize_text(p_text text, p_max_length int DEFAULT 1000)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $$
BEGIN
  IF p_text IS NULL THEN
    RETURN NULL;
  END IF;

  -- Trim whitespace and limit length
  RETURN substring(trim(p_text) from 1 for p_max_length);
END;
$$;

-- ============================================================================
-- Fix notification trigger functions (if they exist)
-- ============================================================================

-- These functions might already have search_path set, but we'll ensure it
DO $$
DECLARE
  r record;
BEGIN
  -- Loop through all functions in public schema that need search_path set
  FOR r IN
    SELECT
      p.proname as func_name,
      pg_get_function_identity_arguments(p.oid) as func_args,
      p.oid::regprocedure::text as func_signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'notify_new_item',
        'notify_new_claim',
        'notify_new_list',
        'send_event_invite',
        'log_activity_for_digest',
        'trigger_daily_digest'
      )
  LOOP
    -- Add SET search_path using full function signature
    BEGIN
      EXECUTE format('ALTER FUNCTION %s SET search_path TO ''public''', r.func_signature);
      RAISE NOTICE 'Updated search_path for function: %', r.func_signature;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'Could not update search_path for %: %', r.func_signature, SQLERRM;
    END;
  END LOOP;
END;
$$;

-- ============================================================================
-- Fix orphaned lists functions (if they exist)
-- ============================================================================

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT
      p.proname as func_name,
      pg_get_function_identity_arguments(p.oid) as func_args,
      p.oid::regprocedure::text as func_signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'mark_orphaned_lists_for_deletion',
        'cleanup_orphaned_lists',
        'unmark_orphaned_lists_on_member_join',
        'is_sole_event_member'
      )
  LOOP
    BEGIN
      EXECUTE format('ALTER FUNCTION %s SET search_path TO ''public''', r.func_signature);
      RAISE NOTICE 'Updated search_path for function: %', r.func_signature;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'Could not update search_path for %: %', r.func_signature, SQLERRM;
    END;
  END LOOP;
END;
$$;

-- ============================================================================
-- Fix digest and cleanup functions (if they exist)
-- ============================================================================

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT
      p.proname as func_name,
      pg_get_function_identity_arguments(p.oid) as func_args,
      p.oid::regprocedure::text as func_signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'generate_and_send_daily_digests',
        'cleanup_old_activity_logs'
      )
  LOOP
    BEGIN
      EXECUTE format('ALTER FUNCTION %s SET search_path TO ''public''', r.func_signature);
      RAISE NOTICE 'Updated search_path for function: %', r.func_signature;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'Could not update search_path for %: %', r.func_signature, SQLERRM;
    END;
  END LOOP;
END;
$$;

-- Log completion
DO $$
BEGIN
  RAISE NOTICE 'Search path security hardening completed';
  RAISE NOTICE 'All functions now have SET search_path to prevent injection attacks';
END;
$$;

COMMIT;
