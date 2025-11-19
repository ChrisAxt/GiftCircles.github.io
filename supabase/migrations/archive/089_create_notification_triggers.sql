-- Migration: Create notification triggers for digest activity logging
-- Created: 2025-11-12
-- Purpose: Enable notification triggers that were defined in schema but never created via migration
--          These triggers send instant notifications AND log activity for weekly digests

BEGIN;

-- ============================================================================
-- Create notification triggers
-- ============================================================================

-- Trigger: Notify when new list is created
-- Calls notify_new_list() which:
-- - Sends instant notification to eligible members
-- - Logs to daily_activity_log for digest (respecting privacy rules)
DROP TRIGGER IF EXISTS trigger_notify_new_list ON public.lists;
CREATE TRIGGER trigger_notify_new_list
  AFTER INSERT ON public.lists
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_new_list();

COMMENT ON TRIGGER trigger_notify_new_list ON public.lists IS 'Sends notifications and logs digest activity when new list is created';

-- Trigger: Notify when new item is added
-- Calls notify_new_item() which:
-- - Sends instant notification to eligible members
-- - Logs to daily_activity_log for digest (respecting privacy rules)
DROP TRIGGER IF EXISTS trigger_notify_new_item ON public.items;
CREATE TRIGGER trigger_notify_new_item
  AFTER INSERT ON public.items
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_new_item();

COMMENT ON TRIGGER trigger_notify_new_item ON public.items IS 'Sends notifications and logs digest activity when new item is added';

-- Trigger: Notify when item is claimed
-- Calls notify_new_claim() which:
-- - Sends instant notification to eligible members
-- - Logs to daily_activity_log for digest (respecting privacy rules, excluding recipients)
DROP TRIGGER IF EXISTS trigger_notify_new_claim ON public.claims;
CREATE TRIGGER trigger_notify_new_claim
  AFTER INSERT ON public.claims
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_new_claim();

COMMENT ON TRIGGER trigger_notify_new_claim ON public.claims IS 'Sends notifications and logs digest activity when item is claimed';

COMMIT;

-- Summary of Changes:
-- Created 3 triggers that enable both instant notifications and digest logging:
-- 1. trigger_notify_new_list (lists table)
-- 2. trigger_notify_new_item (items table)
-- 3. trigger_notify_new_claim (claims table)
--
-- These triggers were defined in schema_consolidated.sql but never created via migration.
-- They now populate daily_activity_log with privacy-filtered activity data.
--
-- After this migration:
-- ✓ Activity logging will start working
-- ✓ Digests will have data to send
-- ✓ Privacy rules will be enforced (from migration 088)
-- ✓ Weekly/daily digests will be sent by existing cron job
