# Supabase Security Warnings

This document tracks security warnings from the Supabase Database Linter and their resolutions.

## Resolved Warnings

### ✅ Function Search Path Mutable (8 functions)

**Issue**: Functions without `SET search_path` are vulnerable to search path injection attacks.

**Fixed in**: Migration 100 (`100_fix_function_search_path_security.sql`)

Functions fixed:
- `public.is_pro`
- `public.log_activity_for_digest`
- `public.check_and_queue_purchase_reminders`
- `public.notify_new_list`
- `public.notify_new_item`
- `public.notify_new_claim`
- `public.notify_unclaim`
- `public.grant_manual_pro`

All functions now have `SET search_path = ''` and use fully schema-qualified table/function references (e.g., `public.profiles` instead of `profiles`).

---

## Outstanding Warnings (Manual Action Required)

### ⚠️ Extension in Public Schema

**Warning**: `pg_net` extension is installed in the public schema.

**Risk**: Extensions in public schema can expose additional attack surface.

**Action**: Move to a dedicated schema (e.g., `extensions`). This requires Supabase Dashboard access:
1. Go to Database → Extensions
2. Disable pg_net
3. Re-enable in `extensions` schema

**Note**: This may break existing functions that use `net.http_*` calls.

---

### ⚠️ Leaked Password Protection Disabled

**Warning**: Supabase Auth isn't checking passwords against HaveIBeenPwned.org.

**Risk**: Users may use compromised passwords.

**Action**: Enable in Supabase Dashboard:
1. Go to Authentication → Settings
2. Enable "Password Strength" checks
3. Enable "Leaked Password Protection"

**Reference**: https://supabase.com/docs/guides/auth/password-security

---

### ⚠️ Vulnerable Postgres Version

**Warning**: PostgreSQL 17.4.1.075 has security patches available.

**Risk**: Unpatched database vulnerabilities.

**Action**: Upgrade database in Supabase Dashboard:
1. Go to Settings → Database
2. Click "Upgrade Database"
3. Schedule maintenance window for upgrade

**Reference**: https://supabase.com/docs/guides/platform/upgrading

**Note**: This is a maintenance operation that may cause brief downtime.

---

---

## Performance Warnings (Fixed)

### ✅ Auth RLS Initialization Plan (4 policies)

**Issue**: Policies re-evaluate `auth.uid()` for each row instead of once per query.

**Fixed in**: Migration 101 (`101_fix_rls_performance.sql`)

Policies fixed:
- `claims_select_visible` - wraps `auth.uid()` in `(SELECT auth.uid())`
- `lists_select_visible` - wraps `auth.uid()` in `(SELECT auth.uid())`
- `items_select` - consolidated from 2 duplicate policies

### ✅ Multiple Permissive Policies (50+ duplicates)

**Issue**: Multiple policies for same role/action forces evaluation of all policies.

**Fixed in**: Migration 102 (`102_consolidate_duplicate_policies.sql`)

Tables consolidated:
- `claims` - UPDATE (2→1), DELETE policies **kept separate** (use RPC instead)
- `events` - SELECT (2→1), UPDATE (2→1), DELETE (3→1)
- `items` - SELECT (2→1) - done in migration 101
- `list_exclusions` - SELECT (2→1)
- `list_recipients` - INSERT (2→1)
- `profiles` - INSERT (2→1)
- `user_plans` - conflicting policies resolved (read-only for clients)

---

## ⚠️ PRODUCTION WARNING

**Migrations 101 and 102 modify RLS policies that control data access.**

Before applying to production:
1. **Backup your database**
2. **Test in staging environment first**
3. **Verify all user actions still work:**
   - Members can see their events
   - Users can claim/unclaim items
   - Admins can delete claims/events
   - Owners can update events
   - Users can see their own claims
   - Privacy rules still apply (recipients can't see claimers)

4. **Rollback plan**: Keep original policy definitions ready to restore

---

## Security Best Practices Applied

1. **SECURITY DEFINER functions** - Used only when necessary (trigger functions), with explicit `SET search_path = ''`
2. **Schema-qualified references** - All table/function calls use `public.` prefix
3. **RLS policies** - Row-Level Security enforced on all user-facing tables
4. **Input validation** - RPCs validate input before executing
5. **Privacy controls** - Recipients cannot see who claimed their items
6. **Pro tier enforcement** - Premium features require subscription check
7. **Performance optimized** - `(SELECT auth.uid())` pattern prevents row-by-row evaluation
