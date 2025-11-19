-- Migration: Add support screen tracking to profiles
-- Created: 2025-11-10
-- Purpose: Track when support screen was last shown to user
-- Note: Uses existing profiles.plan and profiles.pro_until columns to check subscription status

-- Add column to profiles table for tracking support screen display
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS last_support_screen_shown TIMESTAMPTZ;

-- Add index for efficient querying
CREATE INDEX IF NOT EXISTS idx_profiles_last_support_screen ON profiles(last_support_screen_shown);

-- Add comment for documentation
COMMENT ON COLUMN profiles.last_support_screen_shown IS 'Timestamp when support screen was last shown to user. Support screen shows every 30 days for free users (checked via profiles.plan and profiles.pro_until)';
