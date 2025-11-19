-- Migration: Set reminder_days default to NULL (off by default)
-- Created: 2025-11-10
-- Purpose: Make purchase reminders opt-in instead of enabled by default

-- Change the default value for new users to NULL (off)
ALTER TABLE profiles
ALTER COLUMN reminder_days SET DEFAULT NULL;

-- Optionally, you can also update existing users to NULL if desired
-- Uncomment the line below if you want to turn off reminders for all existing free users
-- UPDATE profiles SET reminder_days = NULL WHERE (plan != 'pro' AND (pro_until IS NULL OR pro_until < NOW()));

-- Comment for documentation
COMMENT ON COLUMN profiles.reminder_days IS 'Days before event to send purchase reminder (NULL = disabled). Premium feature.';
