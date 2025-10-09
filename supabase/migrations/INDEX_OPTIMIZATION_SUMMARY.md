# Index Optimization Summary

## Overview

This document covers the INFO-level suggestions from Supabase linter about index optimization.

---

## Migration 023: Add Foreign Key Indexes

### ✅ Issues Fixed

**Problem**: 5 foreign keys without covering indexes
**Impact**: Slower JOINs, slower CASCADE deletes, slower referential integrity checks

### Indexes Added

| Table | Column | Index Name | Purpose |
|-------|--------|------------|---------|
| claims | claimer_id | idx_claims_claimer_id | Filter claims by claimer, JOIN on users |
| event_invites | inviter_id | idx_event_invites_inviter_id | Filter invites by inviter, JOIN on users |
| events | owner_id | idx_events_owner_id | Filter events by owner, JOIN on users |
| items | created_by | idx_items_created_by | Filter items by creator, JOIN on users |
| sent_reminders | event_id | idx_sent_reminders_event_id | Filter reminders by event, JOIN on events |

### Performance Benefits

**Before**:
- Full table scan when filtering by these foreign keys
- Slow CASCADE deletes (must scan entire table)
- Slow referential integrity checks

**After**:
- O(log n) lookups using B-tree index
- Fast CASCADE deletes (direct index lookup)
- Fast referential integrity checks

**Expected Improvement**:
- 10-1000x faster for queries filtering by these columns
- Much faster DELETE operations on parent tables
- Minimal write overhead (indexes are cheap to maintain)

### Apply Migration 023

```bash
supabase db push
```

---

## Migration 024: Drop Unused Indexes (OPTIONAL)

### ⚠️ Decision Required

The linter reports 2 indexes as unused:
1. `idx_list_recipients_uid` on list_recipients(user_id)
2. `idx_list_exclusions_uid` on list_exclusions(user_id)

### Analysis

#### idx_list_recipients_uid
**Status**: Potentially unused
**Size**: Check with `pg_relation_size()`
**Used by**: Queries filtering `list_recipients` by user_id

**Recommendation**:
- ✅ Keep if you query "show all recipients where user_id = X"
- ❌ Drop if you never filter by user_id

#### idx_list_exclusions_uid
**Status**: KEEP THIS INDEX ⚠️
**Used by**: RLS policy "le_select" filters by user_id
**Recommendation**: **DO NOT DROP**

The linter may report this as "unused" if the table hasn't been queried yet, but the RLS policy will use this index every time you SELECT from the table.

### How to Decide

#### Step 1: Check Usage Statistics

```sql
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan as times_used,
    idx_tup_read as tuples_read,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
AND indexrelname IN ('idx_list_recipients_uid', 'idx_list_exclusions_uid')
ORDER BY indexrelname;
```

#### Step 2: Check Your Queries

Do you ever run queries like:
```sql
-- This would use idx_list_recipients_uid
SELECT * FROM list_recipients WHERE user_id = 'some-uuid';

-- This would use idx_list_exclusions_uid
SELECT * FROM list_exclusions WHERE user_id = 'some-uuid';
```

#### Step 3: Check RLS Policies

```sql
SELECT
    tablename,
    policyname,
    qual
FROM pg_policies
WHERE schemaname = 'public'
AND tablename IN ('list_recipients', 'list_exclusions')
AND qual::text LIKE '%user_id%';
```

If RLS policies filter by `user_id`, **keep the index**.

### Decision Matrix

| Criteria | Keep Index | Drop Index |
|----------|-----------|------------|
| idx_scan > 0 | ✅ | ❌ |
| Used in WHERE clause | ✅ | ❌ |
| Used by RLS policy | ✅ | ❌ |
| Table has < 1000 rows | ✅ (minimal overhead) | ⚠️ |
| Index size < 100KB | ✅ (negligible cost) | ⚠️ |
| Database is production | Wait 1-2 weeks | ⚠️ |
| Database is new/test | ✅ (need more data) | ❌ |

### Recommendation

**For idx_list_exclusions_uid**: **KEEP** (used by RLS)
**For idx_list_recipients_uid**: Monitor for 1-2 weeks, then decide

### Apply Migration 024 (When Ready)

```bash
# Only after verification!
# Edit the file to uncomment DROP statements
# Then:
supabase db push
```

---

## Summary

### Immediate Actions (Migration 023)
✅ Add 5 foreign key indexes → Apply immediately

### Future Actions (Migration 024)
⚠️ Review unused indexes → Apply after monitoring

### Expected Results

**After Migration 023**:
- All foreign keys have covering indexes
- Faster JOINs and CASCADE operations
- No more "unindexed_foreign_keys" warnings

**After Migration 024** (if applied):
- Removed truly unused indexes
- Slightly faster writes (less index maintenance)
- Freed up disk space

---

## Monitoring Queries

### Check Index Sizes
```sql
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;
```

### Check Index Usage Over Time
```sql
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch,
    pg_size_pretty(pg_relation_size(indexrelid)) as size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
AND idx_scan = 0  -- Never used
ORDER BY pg_relation_size(indexrelid) DESC;
```

### Check Missing Indexes
```sql
-- Lists tables with foreign keys but no index
SELECT
    tc.table_schema,
    tc.table_name,
    kcu.column_name,
    tc.constraint_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
LEFT JOIN pg_indexes i
    ON i.tablename = tc.table_name
    AND i.schemaname = tc.table_schema
    AND kcu.column_name = ANY(string_to_array(replace(i.indexdef, ' ', ''), ','))
WHERE tc.constraint_type = 'FOREIGN KEY'
AND tc.table_schema = 'public'
AND i.indexname IS NULL;
```

---

## Best Practices

1. **Always index foreign keys** (unless table is tiny)
2. **Monitor index usage** before dropping
3. **Consider RLS policies** when evaluating indexes
4. **Profile queries** to understand access patterns
5. **Index columns used in WHERE/JOIN** clauses

---

*Created: 2025-10-08*
