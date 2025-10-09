# Security Warnings Fixes

This document outlines all fixes for Supabase security linter warnings and errors.

## Overview

- **Migration 020**: Automated fixes for function search paths and RLS
- **Migration 021**: Extension schema migrations (may require elevated privileges)
- **Manual Steps**: Dashboard configurations that cannot be automated

---

## Automated Fixes

### ✅ Migration 020: Fix Security Warnings

Run this migration to fix:
- ✅ **RLS on notification_queue** (ERROR → Fixed)
- ✅ **Function search_path warnings** (25 functions) (WARN → Fixed)

```bash
# Apply the migration
supabase db push
```

---

## Semi-Automated Fixes (May Require Elevated Privileges)

### 🔧 Migration 021: Move Extensions

**Issue**: Extensions `pg_net` and `pgtap` are in the public schema.

**Important Note**: `pg_net` is a Supabase-managed extension that **does NOT support SET SCHEMA**. This is a platform limitation and the warning can be safely ignored.

**Fix**: Try running migration 021 to move `pgtap` only:

```bash
# Attempt to apply the migration
supabase db push
```

**Status after migration**:
- ❌ `pg_net` - **Cannot be moved** (Supabase platform limitation, warning can be ignored)
- 🔧 `pgtap` - **Can be moved** (if you have permissions)

**If you get permission errors for pgtap**:

#### Option A: Via Supabase SQL Editor
1. Go to your Supabase Dashboard
2. Navigate to **SQL Editor**
3. Run: `ALTER EXTENSION pgtap SET SCHEMA extensions;`

#### Option B: Leave it in public schema
Since pgtap is only used for testing, it's safe to leave in public schema. The warning is minor.

---

## Manual Fixes Required

### 🔐 1. Enable Leaked Password Protection

**Issue**: `auth_leaked_password_protection` warning

**Steps**:
1. Go to your Supabase Dashboard
2. Navigate to **Authentication** > **Policies**
3. Find **Password Policy** section
4. Enable "**Check for breached passwords**"
5. This integrates with HaveIBeenPwned.org to prevent compromised passwords

**Reference**: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

**Status**: ⏳ Awaiting manual configuration

---

### 🔄 2. Upgrade Postgres Version

**Issue**: `vulnerable_postgres_version` warning
**Current Version**: supabase-postgres-17.4.1.075
**Recommendation**: Upgrade to latest patch version

**Steps**:
1. Go to your Supabase Dashboard
2. Navigate to **Settings** > **Infrastructure**
3. Check for available Postgres upgrades
4. Schedule upgrade during maintenance window
5. Review breaking changes (if any)

**Important Notes**:
- ⚠️ Schedule during low-traffic period
- ⚠️ Backup your database before upgrading
- ⚠️ Test in staging environment first (if available)

**Reference**: https://supabase.com/docs/guides/platform/upgrading

**Status**: ⏳ Awaiting manual upgrade

---

## Summary of Changes

### Errors Fixed (2)
| Issue | Table/Entity | Status |
|-------|-------------|--------|
| RLS policies exist but RLS disabled | notification_queue | ✅ Fixed in Migration 020 |
| RLS disabled in public schema | notification_queue | ✅ Fixed in Migration 020 |

### Warnings Fixed (25+)
| Issue | Count | Status |
|-------|-------|--------|
| Function search_path mutable | 25 functions | ✅ Fixed in Migration 020 |
| Extensions in public schema | 2 (pg_net, pgtap) | ⚠️ pg_net cannot be moved (platform limitation), pgtap can be moved in Migration 021 |

### Warnings Requiring Manual Action (2)
| Issue | Status |
|-------|--------|
| Leaked password protection disabled | ⏳ Manual - Dashboard configuration |
| Postgres version upgrade | ⏳ Manual - Platform upgrade |

---

## Testing

After applying migrations, verify the fixes:

```sql
-- Check RLS is enabled on notification_queue
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
AND tablename = 'notification_queue';
-- Should show rowsecurity = true

-- Check function search_path settings
SELECT
    p.proname as function_name,
    pg_get_function_identity_arguments(p.oid) as arguments,
    COALESCE(array_to_string(p.proconfig, ', '), 'not set') as config
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
AND p.proname IN (
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
)
ORDER BY p.proname;
-- Should show search_path = '' for all functions

-- Check extension schemas
SELECT
    e.extname as extension_name,
    n.nspname as schema_name
FROM pg_extension e
JOIN pg_namespace n ON e.extnamespace = n.oid
WHERE e.extname IN ('pg_net', 'pgtap');
-- Should show schema_name = 'extensions' after migration 021
```

---

## Rollback Plan

If you need to rollback these changes:

### Rollback Migration 020 (Functions and RLS)
```sql
-- Disable RLS on notification_queue (if needed)
ALTER TABLE public.notification_queue DISABLE ROW LEVEL SECURITY;

-- To rollback function changes, you would need to remove the search_path setting
-- This is typically not necessary unless it causes issues
```

### Rollback Migration 021 (Extensions)
```sql
-- Move extensions back to public schema
ALTER EXTENSION pg_net SET SCHEMA public;
ALTER EXTENSION pgtap SET SCHEMA public;
```

---

## Additional Resources

- [Supabase Database Linter Docs](https://supabase.com/docs/guides/database/database-linter)
- [Row Level Security Guide](https://supabase.com/docs/guides/auth/row-level-security)
- [Function Security Best Practices](https://supabase.com/docs/guides/database/functions)
- [Password Security Configuration](https://supabase.com/docs/guides/auth/password-security)

---

## Next Steps

1. ✅ Apply migration 020
2. 🔧 Attempt migration 021 (may need elevated privileges)
3. ⏳ Enable leaked password protection in Dashboard
4. ⏳ Schedule Postgres upgrade
5. ✅ Run verification queries
6. ✅ Re-run Supabase linter to confirm all fixes

---

*Last Updated: 2025-10-08*
