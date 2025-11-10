-- Migration: Add foreign key constraints for referential integrity
-- Date: 2025-01-20
-- Description: CRITICAL - Adds proper foreign key constraints with CASCADE rules
--              to prevent orphaned records and maintain data integrity.
--              This migration first cleans up any existing orphaned data.

BEGIN;

-- ============================================================================
-- STEP 1: CLEAN UP ORPHANED DATA (if any exists)
-- ============================================================================

-- Delete orphaned claims (claims without valid items)
DELETE FROM public.claims
WHERE NOT EXISTS (
  SELECT 1 FROM public.items WHERE items.id = claims.item_id
);

-- Delete orphaned items (items without valid lists)
DELETE FROM public.items
WHERE NOT EXISTS (
  SELECT 1 FROM public.lists WHERE lists.id = items.list_id
);

-- Delete orphaned lists (lists without valid events)
DELETE FROM public.lists
WHERE NOT EXISTS (
  SELECT 1 FROM public.events WHERE events.id = lists.event_id
);

-- Delete orphaned event_members (members without valid events)
DELETE FROM public.event_members
WHERE NOT EXISTS (
  SELECT 1 FROM public.events WHERE events.id = event_members.event_id
);

-- Delete orphaned list_recipients (recipients without valid lists)
DELETE FROM public.list_recipients
WHERE NOT EXISTS (
  SELECT 1 FROM public.lists WHERE lists.id = list_recipients.list_id
);

-- Delete orphaned list_exclusions
DELETE FROM public.list_exclusions
WHERE NOT EXISTS (
  SELECT 1 FROM public.lists WHERE lists.id = list_exclusions.list_id
);

-- Delete orphaned list_viewers
DELETE FROM public.list_viewers
WHERE NOT EXISTS (
  SELECT 1 FROM public.lists WHERE lists.id = list_viewers.list_id
);

-- Delete orphaned event_invites
DELETE FROM public.event_invites
WHERE NOT EXISTS (
  SELECT 1 FROM public.events WHERE events.id = event_invites.event_id
);

-- Delete orphaned daily_activity_log
DELETE FROM public.daily_activity_log
WHERE NOT EXISTS (
  SELECT 1 FROM public.events WHERE events.id = daily_activity_log.event_id
);

-- Delete orphaned sent_reminders
DELETE FROM public.sent_reminders
WHERE NOT EXISTS (
  SELECT 1 FROM public.claims WHERE claims.id = sent_reminders.claim_id
);

-- Log completion of cleanup
DO $$
BEGIN
  RAISE NOTICE 'Orphaned data cleanup completed.';
END $$;

-- ============================================================================
-- STEP 2: ADD PRIMARY KEYS (if missing)
-- ============================================================================

-- Add primary keys where missing (PostgreSQL doesn't support IF NOT EXISTS for PK)
DO $$
BEGIN
  -- Check and add primary key for claims
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'claims_pkey'
  ) THEN
    ALTER TABLE public.claims ADD PRIMARY KEY (id);
  END IF;
END $$;

DO $$
BEGIN
  -- Add primary keys only if they don't exist
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'events_pkey') THEN
    ALTER TABLE public.events ADD PRIMARY KEY (id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'lists_pkey') THEN
    ALTER TABLE public.lists ADD PRIMARY KEY (id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'items_pkey') THEN
    ALTER TABLE public.items ADD PRIMARY KEY (id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_pkey') THEN
    ALTER TABLE public.profiles ADD PRIMARY KEY (id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'event_invites_pkey') THEN
    ALTER TABLE public.event_invites ADD PRIMARY KEY (id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'daily_activity_log_pkey') THEN
    ALTER TABLE public.daily_activity_log ADD PRIMARY KEY (id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'notification_queue_pkey') THEN
    ALTER TABLE public.notification_queue ADD PRIMARY KEY (id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orphaned_lists_pkey') THEN
    ALTER TABLE public.orphaned_lists ADD PRIMARY KEY (id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'push_tokens_pkey') THEN
    ALTER TABLE public.push_tokens ADD PRIMARY KEY (id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sent_reminders_pkey') THEN
    ALTER TABLE public.sent_reminders ADD PRIMARY KEY (id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'list_recipients_pkey') THEN
    ALTER TABLE public.list_recipients ADD PRIMARY KEY (id);
  END IF;

  RAISE NOTICE 'Primary keys verified/added';
END $$;

-- Composite primary keys
DO $$
BEGIN
  -- event_members
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'event_members_pkey') THEN
    ALTER TABLE public.event_members ADD PRIMARY KEY (event_id, user_id);
  ELSE
    -- Drop and recreate if exists with different columns
    ALTER TABLE public.event_members DROP CONSTRAINT event_members_pkey CASCADE;
    ALTER TABLE public.event_members ADD PRIMARY KEY (event_id, user_id);
  END IF;

  -- list_exclusions
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'list_exclusions_pkey') THEN
    ALTER TABLE public.list_exclusions ADD PRIMARY KEY (list_id, user_id);
  ELSE
    ALTER TABLE public.list_exclusions DROP CONSTRAINT list_exclusions_pkey CASCADE;
    ALTER TABLE public.list_exclusions ADD PRIMARY KEY (list_id, user_id);
  END IF;

  -- list_viewers
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'list_viewers_pkey') THEN
    ALTER TABLE public.list_viewers ADD PRIMARY KEY (list_id, user_id);
  ELSE
    ALTER TABLE public.list_viewers DROP CONSTRAINT list_viewers_pkey CASCADE;
    ALTER TABLE public.list_viewers ADD PRIMARY KEY (list_id, user_id);
  END IF;

  -- user_plans
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'user_plans_pkey') THEN
    ALTER TABLE public.user_plans ADD PRIMARY KEY (user_id);
  END IF;

  RAISE NOTICE 'Composite primary keys verified/added';
END $$;

-- ============================================================================
-- STEP 3: ADD FOREIGN KEY CONSTRAINTS
-- ============================================================================

-- Claims -> Items (CASCADE: when item is deleted, delete all its claims)
ALTER TABLE public.claims
  DROP CONSTRAINT IF EXISTS fk_claims_item_id,
  ADD CONSTRAINT fk_claims_item_id
    FOREIGN KEY (item_id)
    REFERENCES public.items(id)
    ON DELETE CASCADE;

-- Claims -> Users (SET NULL: preserve claim record even if user deleted)
ALTER TABLE public.claims
  DROP CONSTRAINT IF EXISTS fk_claims_claimer_id,
  ADD CONSTRAINT fk_claims_claimer_id
    FOREIGN KEY (claimer_id)
    REFERENCES auth.users(id)
    ON DELETE SET NULL;

-- Claims -> Users (assigned_to)
ALTER TABLE public.claims
  DROP CONSTRAINT IF EXISTS fk_claims_assigned_to,
  ADD CONSTRAINT fk_claims_assigned_to
    FOREIGN KEY (assigned_to)
    REFERENCES auth.users(id)
    ON DELETE SET NULL;

-- Items -> Lists (CASCADE: when list is deleted, delete all its items and their claims)
ALTER TABLE public.items
  DROP CONSTRAINT IF EXISTS fk_items_list_id,
  ADD CONSTRAINT fk_items_list_id
    FOREIGN KEY (list_id)
    REFERENCES public.lists(id)
    ON DELETE CASCADE;

-- Items -> Users (created_by)
ALTER TABLE public.items
  DROP CONSTRAINT IF EXISTS fk_items_created_by,
  ADD CONSTRAINT fk_items_created_by
    FOREIGN KEY (created_by)
    REFERENCES auth.users(id)
    ON DELETE SET NULL;

-- Items -> Users (assigned_recipient_id)
ALTER TABLE public.items
  DROP CONSTRAINT IF EXISTS fk_items_assigned_recipient_id,
  ADD CONSTRAINT fk_items_assigned_recipient_id
    FOREIGN KEY (assigned_recipient_id)
    REFERENCES auth.users(id)
    ON DELETE SET NULL;

-- Lists -> Events (CASCADE: when event is deleted, delete all its lists, items, and claims)
ALTER TABLE public.lists
  DROP CONSTRAINT IF EXISTS fk_lists_event_id,
  ADD CONSTRAINT fk_lists_event_id
    FOREIGN KEY (event_id)
    REFERENCES public.events(id)
    ON DELETE CASCADE;

-- Lists -> Users (created_by)
ALTER TABLE public.lists
  DROP CONSTRAINT IF EXISTS fk_lists_created_by,
  ADD CONSTRAINT fk_lists_created_by
    FOREIGN KEY (created_by)
    REFERENCES auth.users(id)
    ON DELETE SET NULL;

-- Events -> Users (owner_id)
ALTER TABLE public.events
  DROP CONSTRAINT IF EXISTS fk_events_owner_id,
  ADD CONSTRAINT fk_events_owner_id
    FOREIGN KEY (owner_id)
    REFERENCES auth.users(id)
    ON DELETE SET NULL;

-- Event Members -> Events (CASCADE: delete membership when event is deleted)
ALTER TABLE public.event_members
  DROP CONSTRAINT IF EXISTS fk_event_members_event_id,
  ADD CONSTRAINT fk_event_members_event_id
    FOREIGN KEY (event_id)
    REFERENCES public.events(id)
    ON DELETE CASCADE;

-- Event Members -> Users (CASCADE: delete membership when user is deleted)
ALTER TABLE public.event_members
  DROP CONSTRAINT IF EXISTS fk_event_members_user_id,
  ADD CONSTRAINT fk_event_members_user_id
    FOREIGN KEY (user_id)
    REFERENCES auth.users(id)
    ON DELETE CASCADE;

-- List Recipients -> Lists (CASCADE)
ALTER TABLE public.list_recipients
  DROP CONSTRAINT IF EXISTS fk_list_recipients_list_id,
  ADD CONSTRAINT fk_list_recipients_list_id
    FOREIGN KEY (list_id)
    REFERENCES public.lists(id)
    ON DELETE CASCADE;

-- List Recipients -> Users (CASCADE)
ALTER TABLE public.list_recipients
  DROP CONSTRAINT IF EXISTS fk_list_recipients_user_id,
  ADD CONSTRAINT fk_list_recipients_user_id
    FOREIGN KEY (user_id)
    REFERENCES auth.users(id)
    ON DELETE CASCADE;

-- List Exclusions -> Lists (CASCADE)
ALTER TABLE public.list_exclusions
  DROP CONSTRAINT IF EXISTS fk_list_exclusions_list_id,
  ADD CONSTRAINT fk_list_exclusions_list_id
    FOREIGN KEY (list_id)
    REFERENCES public.lists(id)
    ON DELETE CASCADE;

-- List Exclusions -> Users (CASCADE)
ALTER TABLE public.list_exclusions
  DROP CONSTRAINT IF EXISTS fk_list_exclusions_user_id,
  ADD CONSTRAINT fk_list_exclusions_user_id
    FOREIGN KEY (user_id)
    REFERENCES auth.users(id)
    ON DELETE CASCADE;

-- List Viewers -> Lists (CASCADE)
ALTER TABLE public.list_viewers
  DROP CONSTRAINT IF EXISTS fk_list_viewers_list_id,
  ADD CONSTRAINT fk_list_viewers_list_id
    FOREIGN KEY (list_id)
    REFERENCES public.lists(id)
    ON DELETE CASCADE;

-- List Viewers -> Users (CASCADE)
ALTER TABLE public.list_viewers
  DROP CONSTRAINT IF EXISTS fk_list_viewers_user_id,
  ADD CONSTRAINT fk_list_viewers_user_id
    FOREIGN KEY (user_id)
    REFERENCES auth.users(id)
    ON DELETE CASCADE;

-- Event Invites -> Events (CASCADE)
ALTER TABLE public.event_invites
  DROP CONSTRAINT IF EXISTS fk_event_invites_event_id,
  ADD CONSTRAINT fk_event_invites_event_id
    FOREIGN KEY (event_id)
    REFERENCES public.events(id)
    ON DELETE CASCADE;

-- Event Invites -> Users (inviter)
ALTER TABLE public.event_invites
  DROP CONSTRAINT IF EXISTS fk_event_invites_inviter_id,
  ADD CONSTRAINT fk_event_invites_inviter_id
    FOREIGN KEY (inviter_id)
    REFERENCES auth.users(id)
    ON DELETE CASCADE;

-- Event Invites -> Users (invitee)
ALTER TABLE public.event_invites
  DROP CONSTRAINT IF EXISTS fk_event_invites_invitee_id,
  ADD CONSTRAINT fk_event_invites_invitee_id
    FOREIGN KEY (invitee_id)
    REFERENCES auth.users(id)
    ON DELETE CASCADE;

-- Daily Activity Log -> Users (CASCADE)
ALTER TABLE public.daily_activity_log
  DROP CONSTRAINT IF EXISTS fk_daily_activity_log_user_id,
  ADD CONSTRAINT fk_daily_activity_log_user_id
    FOREIGN KEY (user_id)
    REFERENCES auth.users(id)
    ON DELETE CASCADE;

-- Daily Activity Log -> Events (CASCADE)
ALTER TABLE public.daily_activity_log
  DROP CONSTRAINT IF EXISTS fk_daily_activity_log_event_id,
  ADD CONSTRAINT fk_daily_activity_log_event_id
    FOREIGN KEY (event_id)
    REFERENCES public.events(id)
    ON DELETE CASCADE;

-- Notification Queue -> Users (CASCADE)
ALTER TABLE public.notification_queue
  DROP CONSTRAINT IF EXISTS fk_notification_queue_user_id,
  ADD CONSTRAINT fk_notification_queue_user_id
    FOREIGN KEY (user_id)
    REFERENCES auth.users(id)
    ON DELETE CASCADE;

-- Orphaned Lists -> Lists (CASCADE)
ALTER TABLE public.orphaned_lists
  DROP CONSTRAINT IF EXISTS fk_orphaned_lists_list_id,
  ADD CONSTRAINT fk_orphaned_lists_list_id
    FOREIGN KEY (list_id)
    REFERENCES public.lists(id)
    ON DELETE CASCADE;

-- Orphaned Lists -> Events (CASCADE)
ALTER TABLE public.orphaned_lists
  DROP CONSTRAINT IF EXISTS fk_orphaned_lists_event_id,
  ADD CONSTRAINT fk_orphaned_lists_event_id
    FOREIGN KEY (event_id)
    REFERENCES public.events(id)
    ON DELETE CASCADE;

-- Orphaned Lists -> Users (CASCADE)
ALTER TABLE public.orphaned_lists
  DROP CONSTRAINT IF EXISTS fk_orphaned_lists_excluded_user_id,
  ADD CONSTRAINT fk_orphaned_lists_excluded_user_id
    FOREIGN KEY (excluded_user_id)
    REFERENCES auth.users(id)
    ON DELETE CASCADE;

-- Push Tokens -> Users (CASCADE)
ALTER TABLE public.push_tokens
  DROP CONSTRAINT IF EXISTS fk_push_tokens_user_id,
  ADD CONSTRAINT fk_push_tokens_user_id
    FOREIGN KEY (user_id)
    REFERENCES auth.users(id)
    ON DELETE CASCADE;

-- Sent Reminders -> Users (CASCADE)
ALTER TABLE public.sent_reminders
  DROP CONSTRAINT IF EXISTS fk_sent_reminders_user_id,
  ADD CONSTRAINT fk_sent_reminders_user_id
    FOREIGN KEY (user_id)
    REFERENCES auth.users(id)
    ON DELETE CASCADE;

-- Sent Reminders -> Claims (CASCADE)
ALTER TABLE public.sent_reminders
  DROP CONSTRAINT IF EXISTS fk_sent_reminders_claim_id,
  ADD CONSTRAINT fk_sent_reminders_claim_id
    FOREIGN KEY (claim_id)
    REFERENCES public.claims(id)
    ON DELETE CASCADE;

-- Sent Reminders -> Events (CASCADE)
ALTER TABLE public.sent_reminders
  DROP CONSTRAINT IF EXISTS fk_sent_reminders_event_id,
  ADD CONSTRAINT fk_sent_reminders_event_id
    FOREIGN KEY (event_id)
    REFERENCES public.events(id)
    ON DELETE CASCADE;

-- User Plans -> Users (CASCADE)
ALTER TABLE public.user_plans
  DROP CONSTRAINT IF EXISTS fk_user_plans_user_id,
  ADD CONSTRAINT fk_user_plans_user_id
    FOREIGN KEY (user_id)
    REFERENCES auth.users(id)
    ON DELETE CASCADE;

-- ============================================================================
-- STEP 4: ADD NOT NULL CONSTRAINTS FOR REQUIRED FIELDS
-- ============================================================================

-- Ensure critical foreign keys are NOT NULL (data integrity)
ALTER TABLE public.claims ALTER COLUMN item_id SET NOT NULL;
ALTER TABLE public.items ALTER COLUMN list_id SET NOT NULL;
ALTER TABLE public.lists ALTER COLUMN event_id SET NOT NULL;
ALTER TABLE public.event_members ALTER COLUMN event_id SET NOT NULL;
ALTER TABLE public.event_members ALTER COLUMN user_id SET NOT NULL;

-- ============================================================================
-- STEP 5: ADD CHECK CONSTRAINTS FOR DATA VALIDATION
-- ============================================================================

-- Ensure positive quantities
ALTER TABLE public.claims
  DROP CONSTRAINT IF EXISTS chk_claims_quantity_positive,
  ADD CONSTRAINT chk_claims_quantity_positive
    CHECK (quantity > 0);

-- Ensure positive prices
ALTER TABLE public.items
  DROP CONSTRAINT IF EXISTS chk_items_price_positive,
  ADD CONSTRAINT chk_items_price_positive
    CHECK (price IS NULL OR price >= 0);

-- Ensure valid event dates (not too far in past)
ALTER TABLE public.events
  DROP CONSTRAINT IF EXISTS chk_events_date_reasonable,
  ADD CONSTRAINT chk_events_date_reasonable
    CHECK (event_date IS NULL OR event_date >= '2020-01-01'::date);

-- Ensure valid reminder days
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS chk_profiles_reminder_days_valid,
  ADD CONSTRAINT chk_profiles_reminder_days_valid
    CHECK (reminder_days >= 0 AND reminder_days <= 365);

-- Ensure valid digest hour
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS chk_profiles_digest_hour_valid,
  ADD CONSTRAINT chk_profiles_digest_hour_valid
    CHECK (digest_time_hour >= 0 AND digest_time_hour <= 23);

-- Ensure valid digest day of week
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS chk_profiles_digest_day_valid,
  ADD CONSTRAINT chk_profiles_digest_day_valid
    CHECK (digest_day_of_week >= 0 AND digest_day_of_week <= 6);

-- Log completion
DO $$
BEGIN
  RAISE NOTICE 'Foreign key constraints, NOT NULL constraints, and CHECK constraints added successfully.';
  RAISE NOTICE 'Database now has referential integrity. Orphaned records will be automatically cleaned up on DELETE.';
END;
$$;

COMMIT;
