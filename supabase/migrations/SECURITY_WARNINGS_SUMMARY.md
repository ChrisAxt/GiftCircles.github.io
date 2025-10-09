# Security Warnings - Quick Summary

## ✅ Fully Fixed (27 issues)

### Errors (2)
- ✅ `policy_exists_rls_disabled` - notification_queue
- ✅ `rls_disabled_in_public` - notification_queue

### Warnings (25)
- ✅ All 25 `function_search_path_mutable` warnings

**Action**: Apply migration 020
```bash
supabase db push
```

---

## ⚠️ Cannot Be Fixed (1 warning)

### `extension_in_public` - pg_net

**Why**: `pg_net` is a Supabase-managed extension that does NOT support `SET SCHEMA`. This is a known platform limitation.

**Reference**: https://github.com/supabase/pg_net

**Action**: **Accept this warning** - it's safe to ignore. This is not a security issue, just a linter preference.

---

## 🔧 Optionally Fixable (1 warning)

### `extension_in_public` - pgtap

**Fix**: Apply migration 021 (may require elevated privileges)
```bash
supabase db push
```

**Or**: Since pgtap is only for testing, you can safely ignore this warning too.

---

## 📋 Manual Actions Required (2 warnings)

### 1. `auth_leaked_password_protection`

**Where**: Supabase Dashboard → Authentication → Policies
**Action**: Enable "Check for breached passwords"
**Importance**: ⭐⭐⭐ Recommended for production

### 2. `vulnerable_postgres_version`

**Where**: Supabase Dashboard → Settings → Infrastructure
**Action**: Schedule Postgres upgrade
**Importance**: ⭐⭐⭐ Recommended for security patches

---

## Final Score

After applying migration 020:
- ✅ **27 out of 30 issues fixed** (90%)
- ⚠️ **1 cannot be fixed** (pg_net - platform limitation)
- 📋 **2 require manual action** (dashboard settings)

---

## Quick Commands

```bash
# Apply automated fixes
supabase db push

# Verify RLS is enabled
psql $DATABASE_URL -c "SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' AND tablename = 'notification_queue';"

# Verify functions have search_path set
psql $DATABASE_URL -c "SELECT proname, array_to_string(proconfig, ', ') as config FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname = 'public' AND proname IN ('send_event_invite', 'is_event_admin', 'trigger_push_notifications') LIMIT 3;"

# Check extension locations
psql $DATABASE_URL -c "SELECT e.extname, n.nspname FROM pg_extension e JOIN pg_namespace n ON e.extnamespace = n.oid WHERE e.extname IN ('pg_net', 'pgtap');"
```

---

*Generated: 2025-10-08*
