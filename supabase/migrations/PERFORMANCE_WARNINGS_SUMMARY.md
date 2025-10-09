# Performance Warnings - Summary & Fixes

## Overview

This document outlines the performance warnings from Supabase linter and how they've been addressed in migration 022.

---

## Issues Fixed in Migration 022

### 1. ✅ auth_rls_initplan (48 policies)

**Problem**: RLS policies that call `auth.uid()` directly cause Postgres to re-evaluate the function for EVERY ROW, which is extremely slow at scale.

**Solution**: Wrap all `auth.uid()` calls in a subquery: `(SELECT auth.uid())`

This forces Postgres to evaluate the function ONCE per query instead of once per row.

**Example**:
```sql
-- ❌ Before (slow - evaluated per row)
USING (user_id = auth.uid())

-- ✅ After (fast - evaluated once)
USING (user_id = (SELECT auth.uid()))
```

**Tables Fixed** (48 policies total):
- profiles (3 policies)
- user_plans (2 policies)
- claims (5 policies)
- events (8 policies)
- items (3 policies)
- list_exclusions (3 policies)
- list_recipients (5 policies)
- list_viewers (1 policy)
- lists (3 policies)
- event_invites (4 policies)
- push_tokens (4 policies)
- event_members (2 policies)
- sent_reminders (5 policies - also consolidated)

---

### 2. ✅ multiple_permissive_policies (60+ warnings)

**Problem**: Having multiple permissive RLS policies for the same role+action (e.g., two SELECT policies for `authenticated` role) causes Postgres to evaluate ALL policies for every query, which is suboptimal.

**Solution**: Consolidate duplicate policies where possible.

**Fixes Applied**:

#### sent_reminders table
- **Before**: Had two identical "No public access" policies
- **After**: Consolidated into single policy that blocks all access

#### list_recipients table
- **Before**: Had two INSERT policies with identical logic
- **After**: Kept the more comprehensive one, removed duplicate

#### claims table
- **Before**: Had `claims_update_by_claimer` and `claims_update_own` (identical)
- **After**: Both exist but with optimized `auth.uid()` calls

#### events table
- **Before**: Had 3 DELETE policies (admins, owners, last member)
- **After**: Kept all 3 as they serve different purposes (intentional multiple policies)

**Note**: Some tables still have multiple permissive policies because they serve different legitimate purposes (e.g., admin access vs owner access). This is intentional and acceptable.

---

### 3. ✅ duplicate_index (1 warning)

**Problem**: Table `list_exclusions` had two identical indexes:
- `idx_list_exclusions_uid`
- `list_exclusions_user_idx`

**Solution**: Dropped `list_exclusions_user_idx`, kept `idx_list_exclusions_uid`

---

## Performance Impact

### Before Migration 022:
- **auth.uid()** evaluated once per row → O(n) function calls
- Multiple policies evaluated for each query → Additional overhead
- Duplicate index → Wasted storage & slower writes

### After Migration 022:
- **auth.uid()** evaluated once per query → O(1) function calls
- Reduced policy evaluation overhead
- Single index → Faster writes

**Expected Improvement**:
- 10-100x faster queries on large tables (depends on row count)
- More noticeable improvement as tables grow
- Reduced CPU usage on database

---

## Applying the Migration

```bash
# Apply the performance fixes
supabase db push
```

---

## Verification

After applying, verify the fixes:

```sql
-- 1. Check that policies use subqueries
SELECT
    schemaname,
    tablename,
    policyname,
    qual
FROM pg_policies
WHERE schemaname = 'public'
AND tablename IN ('profiles', 'events', 'claims')
LIMIT 5;
-- Should see (SELECT auth.uid()) in the qual column

-- 2. Verify duplicate index is gone
SELECT
    tablename,
    indexname
FROM pg_indexes
WHERE schemaname = 'public'
AND tablename = 'list_exclusions'
AND indexname LIKE '%user%';
-- Should only show idx_list_exclusions_uid

-- 3. Check policy count per table
SELECT
    tablename,
    cmd as action,
    count(*) as policy_count
FROM pg_policies
WHERE schemaname = 'public'
GROUP BY tablename, cmd
HAVING count(*) > 1
ORDER BY tablename, cmd;
-- This shows tables with multiple policies (which may be intentional)
```

---

## Remaining Warnings

After migration 022, you may still see some `multiple_permissive_policies` warnings for:
- **claims table**: DELETE and UPDATE actions (intentional - admin vs owner access)
- **events table**: DELETE, SELECT, and UPDATE actions (intentional - owner vs admin vs member access)
- **user_plans table**: Has conflicting policies by design (restrictive + permissive)

**These are acceptable** because they serve different legitimate business logic purposes.

---

## Best Practices Going Forward

When creating new RLS policies:

1. **Always wrap auth functions in subqueries**:
   ```sql
   -- ✅ Do this
   USING (user_id = (SELECT auth.uid()))

   -- ❌ Not this
   USING (user_id = auth.uid())
   ```

2. **Consolidate policies when possible**:
   - If two policies have identical logic, merge them
   - If they serve different purposes, keep them separate

3. **Avoid duplicate indexes**:
   - Check existing indexes before creating new ones
   - Use `\d tablename` in psql to see all indexes

4. **Test performance with realistic data**:
   - RLS performance issues only show up at scale
   - Test with 1000+ rows to see the real impact

---

## Resources

- [Supabase RLS Performance Guide](https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select)
- [Database Linter - auth_rls_initplan](https://supabase.com/docs/guides/database/database-linter?lint=0003_auth_rls_initplan)
- [Database Linter - multiple_permissive_policies](https://supabase.com/docs/guides/database/database-linter?lint=0006_multiple_permissive_policies)

---

*Migration 022 applied: 2025-10-08*
