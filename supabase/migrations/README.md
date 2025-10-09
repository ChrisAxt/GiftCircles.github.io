# Database Migrations

This directory contains all database migrations for the GiftCircles application.

## Migration List

### Security & Core Functionality

**001_force_rls_security.sql**
- Force Row Level Security on all public tables
- Prevents SECURITY DEFINER functions from bypassing RLS policies

**002_add_rpc_validation.sql**
- Add comprehensive input validation to RPC functions
- Validates parameters for create_event_and_admin, create_list_with_people, join_event

**003_fix_authorization_logic.sql**
- Fix authorization bugs and improve visibility
- Fixes free tier event counting bug
- Improves member and claim visibility

**004_rollback_event_members_policy.sql**
- Rollback event_members policy changes

**005_fix_event_members_visibility_correct.sql**
- Correct fix for event_members visibility

**006_free_tier_membership_limit.sql**
- Implement free tier membership limits
- Adds event ownership limits

**007_fix_visibility_validation.sql**
- Fix visibility enum validation

### Features

**008_add_join_code_generation.sql**
- Add automatic join code generation for events
- Creates unique join codes on event creation

**009_fix_join_code_case_insensitive.sql**
- Make join codes case-insensitive

**010_add_custom_recipient_name.sql**
- Add custom recipient name field to lists

**011_fix_function_overload.sql**
- Fix function overload issues

### Notifications System

**012_push_notifications.sql**
- Creates push_tokens table for storing device tokens
- Creates notification_queue table for queuing notifications
- Creates triggers for new lists, items, and claims
- Creates notification processing functions

**013_purchase_reminders.sql**
- Adds reminder_days column to profiles
- Creates sent_reminders table
- Creates check_and_queue_purchase_reminders function
- Creates cleanup_old_reminders function
- Creates trigger for cleaning reminders on purchase

**014_setup_cron_jobs.sql**
- Creates trigger_push_notifications function
- Schedules cron jobs for:
  - Processing push notifications (every minute)
  - Checking purchase reminders (daily at 9 AM)
  - Cleaning up old notifications (daily at 3 AM)
  - Cleaning up old reminders (daily at 3 AM)

## Applying Migrations

### Via Supabase CLI
```bash
npx supabase db push
```

### Via SQL Editor (Manual)
1. Go to SQL Editor in your Supabase dashboard
2. Run each migration file in order (001, 002, 003, etc.)
3. Verify success messages in the output

### Via psql
```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/001_force_rls_security.sql
psql "$SUPABASE_DB_URL" -f supabase/migrations/002_add_rpc_validation.sql
# ... continue for each migration
```

## Verification

Check that migrations were applied successfully:

```sql
-- Check RLS is forced
SELECT tablename, relforcerowsecurity
FROM pg_tables t
JOIN pg_class c ON c.relname = t.tablename
WHERE schemaname = 'public';

-- Check notification tables exist
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('push_tokens', 'notification_queue', 'sent_reminders');

-- Check cron jobs are scheduled
SELECT jobid, jobname, schedule, active
FROM cron.job
WHERE jobname IN (
  'process-push-notifications',
  'check-purchase-reminders',
  'cleanup-old-notifications',
  'cleanup-old-reminders'
);
```

## Testing

### SQL Tests
```bash
# Run all tests
psql "$SUPABASE_DB_URL" -f supabase/tests/smoke/run_all.sql

# Run specific test suites
pg_prove -d "$SUPABASE_DB_URL" supabase/tests/integrity/*.sql
pg_prove -d "$SUPABASE_DB_URL" supabase/tests/rpc/*.sql
```

### TypeScript Tests
```bash
npm test -- supabase/tests/db
```

## Notes

- Migrations are applied in numerical order
- Each migration should be idempotent (safe to run multiple times)
- Notification system requires pg_cron and pg_net extensions
- Cron jobs use $$ delimiters to avoid quote escaping issues
