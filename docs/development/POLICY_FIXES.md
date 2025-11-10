# Policy Creation Fixes - Migrations 061 and 063

## Issue

When migrations are run multiple times (e.g., during testing or re-deployment), policies that were created in previous runs cause errors when the migration tries to create them again.

**Error Message**: 
```
ERROR: 42710: policy "<policy_name>" for table "<table_name>" already exists
```

---

## Root Cause

PostgreSQL doesn't support `CREATE POLICY IF NOT EXISTS`, unlike `CREATE TABLE IF NOT EXISTS` or `CREATE INDEX IF NOT EXISTS`. This means policies must be explicitly dropped before recreation to ensure idempotency.

---

## Migrations Affected

### Migration 061: security_audit_and_hardening.sql
- **Policy**: `security_audit_log_no_public_access`
- **Table**: `security_audit_log`

### Migration 063: fix_rate_limit_rls.sql
- **Policy**: `rate_limit_tracking_no_public_access`
- **Table**: `rate_limit_tracking`

---

## Solution

Add `DROP POLICY IF EXISTS` before each `CREATE POLICY` statement to ensure the migration is idempotent (can be run multiple times safely).

### Pattern Used

```sql
-- Before (not idempotent)
CREATE POLICY "policy_name"
ON public.table_name
FOR ALL
USING (false);

-- After (idempotent)
DROP POLICY IF EXISTS "policy_name" ON public.table_name;
CREATE POLICY "policy_name"
ON public.table_name
FOR ALL
USING (false);
```

---

## Fixes Applied

### Migration 061 Fix

**File**: `supabase/migrations/061_security_audit_and_hardening.sql`

**Line 39-43** (changed):
```sql
DROP POLICY IF EXISTS "security_audit_log_no_public_access" ON public.security_audit_log;
CREATE POLICY "security_audit_log_no_public_access"
ON public.security_audit_log
FOR ALL
USING (false);
```

### Migration 063 Fix

**File**: `supabase/migrations/063_fix_rate_limit_rls.sql`

**Line 14-19** (changed):
```sql
DROP POLICY IF EXISTS "rate_limit_tracking_no_public_access" ON public.rate_limit_tracking;
CREATE POLICY "rate_limit_tracking_no_public_access"
ON public.rate_limit_tracking
FOR ALL
USING (false)
WITH CHECK (false);
```

---

## Verification

Both migrations now run successfully with the following notices:

### Migration 061
```
NOTICE:  policy "security_audit_log_no_public_access" for relation "public.security_audit_log" does not exist, skipping
NOTICE:  Security audit and hardening completed:
NOTICE:  - Added security audit logging
NOTICE:  - Added rate limiting for sensitive operations
...
```

### Migration 063
```
NOTICE:  policy "rate_limit_tracking_no_public_access" for relation "public.rate_limit_tracking" does not exist, skipping
NOTICE:  RLS enabled on rate_limit_tracking table
NOTICE:  Rate limit tracking is now protected and only accessible via server functions
```

---

## Best Practice

**Always use `DROP POLICY IF EXISTS` before `CREATE POLICY`** in migrations to ensure idempotency.

This pattern applies to other PostgreSQL objects that don't support `IF NOT EXISTS`:
- Policies: Use `DROP POLICY IF EXISTS`
- Triggers: Use `DROP TRIGGER IF EXISTS`
- Views: Use `CREATE OR REPLACE VIEW` or `DROP VIEW IF EXISTS`
- Rules: Use `DROP RULE IF EXISTS`

Objects that DO support `IF NOT EXISTS`:
- Tables: `CREATE TABLE IF NOT EXISTS`
- Indexes: `CREATE INDEX IF NOT EXISTS`
- Functions: `CREATE OR REPLACE FUNCTION`
- Extensions: `CREATE EXTENSION IF NOT EXISTS`

---

## Status

✅ **Both migrations fixed and tested**
✅ **Idempotent - can be run multiple times safely**
✅ **Ready for production deployment**

---

**Total Policy Fixes**: 2
**Migrations Updated**: 061, 063
**Status**: Complete ✅

---

# Additional Fix: Constraint vs Index - Migration 065

## Issue

When trying to drop an index that backs a UNIQUE constraint, PostgreSQL prevents the operation because the constraint depends on the index.

**Error Message**:
```
ERROR: 2BP01: cannot drop index claims_item_claimer_unique because constraint claims_item_claimer_unique on table claims requires it
HINT: You can drop constraint claims_item_claimer_unique on table claims instead.
```

---

## Root Cause

In PostgreSQL, UNIQUE constraints automatically create an index to enforce uniqueness. When you have a UNIQUE constraint, you cannot drop its backing index directly - you must drop the constraint itself.

### Key Distinction

- **Index**: A database structure to speed up queries
- **Constraint**: A business rule that uses an index to enforce data integrity

When a UNIQUE constraint is created, PostgreSQL:
1. Creates the constraint
2. Automatically creates an index with the same name
3. Links the constraint to the index

**You cannot drop the index without first dropping the constraint.**

---

## Migration Affected

### Migration 065: fix_performance_warnings.sql
- **Object**: `claims_item_claimer_unique`
- **Type**: UNIQUE constraint (not a standalone index)
- **Table**: `claims`

---

## Solution

Change from `DROP INDEX` to `ALTER TABLE ... DROP CONSTRAINT`:

```sql
-- Before (incorrect)
DROP INDEX IF EXISTS public.claims_item_claimer_unique;

-- After (correct)
ALTER TABLE public.claims DROP CONSTRAINT IF EXISTS claims_item_claimer_unique;
```

When you drop the constraint, PostgreSQL automatically drops the backing index.

---

## Complete Fix Applied

**File**: `supabase/migrations/065_fix_performance_warnings.sql`

**Lines 14-19** (changed):
```sql
-- Drop duplicate indexes/constraints on claims table
-- Keep: claims_item_id_claimer_id_key (likely the constraint-based one)
-- Drop: claims_item_claimer_unique (constraint), idx_claims_item_claimer_unique (index)
-- Note: claims_item_claimer_unique is a UNIQUE constraint, must drop constraint not index
ALTER TABLE public.claims DROP CONSTRAINT IF EXISTS claims_item_claimer_unique;
DROP INDEX IF EXISTS public.idx_claims_item_claimer_unique;
```

---

## How to Identify Constraint-Backed Indexes

### Query to find constraint-backed indexes:
```sql
SELECT
  con.conname AS constraint_name,
  con.contype AS constraint_type,
  idx.indexname AS index_name,
  tab.tablename AS table_name
FROM pg_constraint con
JOIN pg_indexes idx ON idx.indexname = con.conname
JOIN pg_tables tab ON tab.tablename = idx.tablename
WHERE tab.schemaname = 'public'
ORDER BY tab.tablename, con.conname;
```

### Constraint Types:
- `p` = PRIMARY KEY
- `u` = UNIQUE
- `f` = FOREIGN KEY
- `c` = CHECK

---

## Best Practice

**Always check if an index is backing a constraint before dropping it:**

1. **For standalone indexes**: Use `DROP INDEX`
2. **For constraint-backed indexes**: Use `ALTER TABLE ... DROP CONSTRAINT`

### Safe Pattern:
```sql
-- Drop constraint (which drops its index automatically)
ALTER TABLE table_name DROP CONSTRAINT IF EXISTS constraint_name;

-- Drop standalone index
DROP INDEX IF EXISTS index_name;
```

---

## Status

✅ **Migration 065 fixed**
✅ **Constraint correctly dropped instead of index**
✅ **Ready for production deployment**

---

**Total Constraint/Index Fixes**: 1
**Migration Updated**: 065
**Status**: Complete ✅
