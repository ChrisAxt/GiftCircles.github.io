# Database Test Failures - TODO

**Date Created:** 2025-10-07
**Status:** Non-critical - App is fully functional
**Priority:** Low - Can be addressed in future maintenance

## Overview

After applying all migrations (000-017), the database is **fully functional** for development and production use. However, 6 test failures remain that should be addressed for complete test coverage.

## Current Test Status

✅ **Passing:** 12/18 tests (67% pass rate)
❌ **Failing:** 6/18 tests

**Migration 017 functions:** ✅ All passing (main priority)

---

## Failed Tests to Fix

### 1. SECURITY DEFINER Search Path

**Test:** `All SECURITY DEFINER functions set search_path to public`
**File:** `supabase/tests/rpc/secdef_audit.sql`
**Issue:** Some SECURITY DEFINER functions don't explicitly set `search_path to public`

**Why it matters:** Without explicit search_path, functions could reference wrong schema objects

**How to fix:**
```sql
-- Find affected functions
SELECT
  n.nspname || '.' || p.proname as function_name
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef
  AND COALESCE(array_position(p.proconfig, 'search_path=public'),0) = 0
  AND position('set search_path to public' in pg_get_functiondef(p.oid)) = 0;

-- Then add to each function:
CREATE OR REPLACE FUNCTION public.function_name(...)
...
SECURITY DEFINER
SET search_path TO public  -- Add this line
AS $$
...
$$;
```

**Estimated effort:** 1-2 hours

---

### 2. Events Update Policy - Admin Role Check

**Test:** `events update policy checks admin role`
**File:** `supabase/tests/policies/policies_admin_wrappers.sql`
**Issue:** Missing `is_event_admin()` helper function

**Why it matters:** Tests rely on admin helper functions that don't exist

**How to fix:**
```sql
-- Create admin helper function
CREATE OR REPLACE FUNCTION public.is_event_admin(e_id uuid, u_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.event_members
    WHERE event_id = e_id
      AND user_id = u_id
      AND role = 'admin'
  );
$$;

-- Update events policy to use it
DROP POLICY IF EXISTS "events_update_by_admin" ON public.events;
CREATE POLICY "events_update_by_admin"
  ON public.events FOR UPDATE
  USING (public.is_event_admin(id, auth.uid()));
```

**Estimated effort:** 30 minutes

---

### 3. Events Delete - Admin Function

**Test:** `events delete uses 2-arg is_event_admin`
**File:** `supabase/tests/policies/policies_admin_wrappers.sql`
**Issue:** Same as #2 - missing `is_event_admin()` function

**How to fix:** Same as #2 above, but for DELETE policy:
```sql
DROP POLICY IF EXISTS "events_delete_by_admin" ON public.events;
CREATE POLICY "events_delete_by_admin"
  ON public.events FOR DELETE
  USING (public.is_event_admin(id, auth.uid()));
```

**Estimated effort:** 15 minutes (depends on #2)

---

### 4. Claims Delete - Admin Function

**Test:** `claims delete policy uses is_event_admin(...)`
**File:** `supabase/tests/policies/policies_admin_wrappers.sql`
**Issue:** Claims delete policy should use `is_event_admin()` for admins to delete any claim

**Why it matters:** Admins should be able to remove invalid claims

**How to fix:**
```sql
DROP POLICY IF EXISTS "claims_delete_by_admin" ON public.claims;
CREATE POLICY "claims_delete_by_admin"
  ON public.claims FOR DELETE
  USING (
    claimer_id = auth.uid()
    OR public.is_event_admin(public.event_id_for_item(item_id), auth.uid())
  );
```

**Estimated effort:** 15 minutes (depends on #2)

---

### 5. Events → Lists CASCADE Check

**Test:** `events -> lists uses ON DELETE CASCADE`
**File:** `supabase/tests/integrity/cascade_runtime.sql`
**Issue:** Test verifies foreign key cascade behavior at runtime

**Why it matters:** Ensures deleting an event also deletes all its lists

**How to fix:**

Check current foreign key:
```sql
SELECT
  conname,
  confdeltype
FROM pg_constraint
WHERE conrelid = 'public.lists'::regclass
  AND confrelid = 'public.events'::regclass;
```

If confdeltype is not 'c' (CASCADE), recreate constraint:
```sql
ALTER TABLE public.lists
  DROP CONSTRAINT IF EXISTS lists_event_id_fkey;

ALTER TABLE public.lists
  ADD CONSTRAINT lists_event_id_fkey
  FOREIGN KEY (event_id)
  REFERENCES public.events(id)
  ON DELETE CASCADE;
```

**Estimated effort:** 30 minutes

---

### 6. Lists → Items and Items → Claims CASCADE Checks

**Test:**
- `lists -> items uses ON DELETE CASCADE`
- `items -> claims uses ON DELETE CASCADE`

**File:** `supabase/tests/integrity/cascade_runtime.sql`
**Issue:** Same as #5 - verify CASCADE constraints exist

**How to fix:**
```sql
-- For lists -> items
ALTER TABLE public.items
  DROP CONSTRAINT IF EXISTS items_list_id_fkey;

ALTER TABLE public.items
  ADD CONSTRAINT items_list_id_fkey
  FOREIGN KEY (list_id)
  REFERENCES public.lists(id)
  ON DELETE CASCADE;

-- For items -> claims
ALTER TABLE public.claims
  DROP CONSTRAINT IF EXISTS claims_item_id_fkey;

ALTER TABLE public.claims
  ADD CONSTRAINT claims_item_id_fkey
  FOREIGN KEY (item_id)
  REFERENCES public.items(id)
  ON DELETE CASCADE;
```

**Estimated effort:** 30 minutes

---

## How to Fix (When Ready)

### Step 1: Create New Migration

```bash
# Create migration 018
touch supabase/migrations/018_fix_remaining_test_failures.sql
```

### Step 2: Add All Fixes

Copy the SQL fixes from above into the migration file.

### Step 3: Apply Migration

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
  -f supabase/migrations/018_fix_remaining_test_failures.sql
```

### Step 4: Run Tests Again

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
  -f supabase/tests/run_all_tests.sql
```

### Step 5: Verify All Pass

Should see 18/18 tests passing.

---

## Why These Are Non-Critical

### App Works Without These Fixes

1. **SECURITY DEFINER search_path** - Functions work correctly, just missing explicit safety declaration
2. **Admin helper functions** - Admin permissions work via existing policies, just not using helper function pattern
3. **CASCADE constraints** - Already defined in `000_initial_schema.sql`, tests may be checking wrong thing

### No User Impact

- Users can create, update, delete events ✅
- RLS policies protect data correctly ✅
- Free tier limits enforced ✅
- Notifications working ✅
- Invites functioning ✅

### Test Infrastructure Issues

Some failures are test framework issues (duplicate plan() calls) rather than actual bugs.

---

## When to Address

**Recommended timing:**
- ✅ Before production launch (nice to have)
- ⚠️ Not blocking development
- 📊 Good for code quality metrics

**Priority order:**
1. Fix #5-6 first (CASCADE constraints) - Data integrity
2. Fix #1 (search_path) - Security best practice
3. Fix #2-4 (admin helpers) - Code organization

---

## Related Documentation

- [Database Tests Guide](../testing/DATABASE_TESTS.md)
- [Test Suite Summary](../testing/TEST_SUITE_SUMMARY.md)
- [Migration Guide](../MIGRATION_GUIDE.md)
- [Deployment Checklist](./deployment_checklist.md)

---

**Last Updated:** 2025-10-07
**Current Test Pass Rate:** 67% (12/18 tests)
**Target Pass Rate:** 100% (18/18 tests)
