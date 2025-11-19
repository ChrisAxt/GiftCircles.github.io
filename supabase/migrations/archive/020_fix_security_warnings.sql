-- Migration: Fix Security Linter Warnings
-- Date: 2025-10-08
-- Description: Addresses security warnings from Supabase linter
--   1. Fixes function_search_path_mutable warnings by setting search_path
--   2. Enables RLS on notification_queue table

-- ============================================================================
-- 1. Enable RLS on notification_queue (fixes ERROR level issues)
-- ============================================================================

ALTER TABLE public.notification_queue ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 2. Fix function_search_path_mutable warnings
-- ============================================================================
-- Setting search_path prevents potential security issues from schema injection attacks
-- Reference: https://supabase.com/docs/guides/database/database-linter?lint=0011_function_search_path_mutable

-- Strategy: Use ALTER FUNCTION ... SET search_path for each function
-- We use a dynamic approach to handle all overloads of each function

DO $$
DECLARE
    func_record RECORD;
    function_names TEXT[] := ARRAY[
        'send_event_invite',
        'link_list_recipients_on_signup',
        'create_list_with_people',
        'cleanup_reminder_on_purchase',
        '_pick_new_admin',
        'add_list_recipient',
        'update_invites_on_user_signup',
        'accept_event_invite',
        'is_event_admin',
        'trigger_push_notifications',
        'autojoin_event_as_admin',
        'allowed_event_slots',
        '_next_occurrence',
        'get_my_pending_invites',
        'test_impersonate',
        'decline_event_invite',
        'check_and_queue_purchase_reminders',
        'get_list_recipients',
        'cleanup_old_notifications',
        'tg_set_timestamp',
        'cleanup_old_invites',
        'cleanup_old_reminders',
        'is_event_member',
        'is_last_event_member'
    ];
    func_name TEXT;
    updated_count INTEGER := 0;
BEGIN
    -- Loop through each function name
    FOREACH func_name IN ARRAY function_names LOOP
        -- Find all overloads of this function and set search_path
        FOR func_record IN
            SELECT
                p.oid::regprocedure::text as func_signature,
                p.proname as name
            FROM pg_proc p
            JOIN pg_namespace n ON p.pronamespace = n.oid
            WHERE n.nspname = 'public'
            AND p.proname = func_name
        LOOP
            BEGIN
                EXECUTE format('ALTER FUNCTION %s SET search_path = ''''', func_record.func_signature);
                updated_count := updated_count + 1;
                RAISE NOTICE 'Updated function: %', func_record.func_signature;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING 'Failed to update function %: %', func_record.func_signature, SQLERRM;
            END;
        END LOOP;
    END LOOP;

    RAISE NOTICE 'Successfully updated % functions with search_path', updated_count;
END $$;

-- ============================================================================
-- NOTES FOR MANUAL FIXES:
-- ============================================================================

-- 1. Extension migrations:
--    See: 021_move_extensions_elevated.sql
--
--    IMPORTANT: pg_net is a Supabase-managed extension that does NOT support
--    SET SCHEMA. The linter warning for pg_net can be safely ignored.
--    This is a known platform limitation, not a security issue.
--
--    pgtap CAN be moved with: ALTER EXTENSION pgtap SET SCHEMA extensions;
--    (See migration 021 for automated attempt with error handling)

-- 2. Leaked Password Protection:
--    This must be enabled in the Supabase Dashboard:
--    Authentication > Policies > Password Policy > Enable "Check for breached passwords"
--    URL: https://supabase.com/dashboard/project/_/auth/policies

-- 3. Postgres Version Upgrade:
--    This is a platform-level upgrade that should be done via Supabase dashboard
--    or scheduled during a maintenance window.
--    URL: https://supabase.com/dashboard/project/_/settings/infrastructure
