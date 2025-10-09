# Unused Index Warnings - Expected Behavior

## Current Status

After applying migrations 023, you'll see **7 unused index warnings**. This is **EXPECTED and NORMAL**.

---

## Why They Show as "Unused"

### Newly Created Indexes (Migration 023)
- idx_claims_claimer_id
- idx_event_invites_inviter_id
- idx_events_owner_id
- idx_items_created_by
- idx_sent_reminders_event_id

**Status**: ✅ **KEEP THESE** - They're new and haven't been used yet, but WILL be used

### Pre-existing Indexes
- idx_list_recipients_uid
- idx_list_exclusions_uid

**Status**: ⚠️ Monitor these (see details below)

---

## When Indexes WILL Be Used

### 1. Foreign Key Indexes (Keep All)

These indexes are critical for:

#### idx_claims_claimer_id
```sql
-- Will be used for:
SELECT * FROM claims WHERE claimer_id = 'user-uuid';
SELECT * FROM claims c JOIN users u ON c.claimer_id = u.id;
DELETE FROM users WHERE id = 'user-uuid';  -- CASCADE lookup
```

#### idx_event_invites_inviter_id
```sql
-- Will be used for:
SELECT * FROM event_invites WHERE inviter_id = 'user-uuid';
SELECT * FROM event_invites ei JOIN users u ON ei.inviter_id = u.id;
```

#### idx_events_owner_id
```sql
-- Will be used for:
SELECT * FROM events WHERE owner_id = 'user-uuid';
SELECT * FROM events e JOIN users u ON e.owner_id = u.id;
DELETE FROM users WHERE id = 'user-uuid';  -- CASCADE lookup
```

#### idx_items_created_by
```sql
-- Will be used for:
SELECT * FROM items WHERE created_by = 'user-uuid';
SELECT * FROM items i JOIN users u ON i.created_by = u.id;
```

#### idx_sent_reminders_event_id
```sql
-- Will be used for:
SELECT * FROM sent_reminders WHERE event_id = 'event-uuid';
SELECT * FROM sent_reminders sr JOIN events e ON sr.event_id = e.id;
DELETE FROM events WHERE id = 'event-uuid';  -- CASCADE lookup
```

**Recommendation**: ✅ **KEEP ALL FOREIGN KEY INDEXES**

---

## Pre-existing Index Review

### idx_list_recipients_uid

**Used by**: Queries filtering by user_id
**Check usage**:
```sql
SELECT
    idx_scan as times_used,
    idx_tup_read as rows_read,
    pg_size_pretty(pg_relation_size(indexrelid)) as size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
AND indexrelname = 'idx_list_recipients_uid';
```

**Decision**:
- If `times_used > 0` → Keep
- If your app queries `list_recipients` by `user_id` → Keep
- Otherwise → Monitor for 2 weeks, then consider dropping

### idx_list_exclusions_uid

**CRITICAL**: Used by RLS policy!

```sql
-- RLS policy "le_select" filters by user_id
CREATE POLICY "le_select"
  ON public.list_exclusions FOR SELECT
  USING (user_id = (SELECT auth.uid()));
```

**Recommendation**: ✅ **KEEP THIS INDEX** - Required for RLS performance

---

## Summary Table

| Index | Status | Action | Reason |
|-------|--------|--------|--------|
| idx_claims_claimer_id | New | ✅ Keep | Foreign key performance |
| idx_event_invites_inviter_id | New | ✅ Keep | Foreign key performance |
| idx_events_owner_id | New | ✅ Keep | Foreign key performance |
| idx_items_created_by | New | ✅ Keep | Foreign key performance |
| idx_sent_reminders_event_id | New | ✅ Keep | Foreign key performance |
| idx_list_recipients_uid | Existing | ⚠️ Monitor | May be useful |
| idx_list_exclusions_uid | Existing | ✅ Keep | Used by RLS policy |

---

## Action Plan

### Immediate (Now)
✅ **Keep all 7 indexes** - Do nothing

### Short Term (1-2 weeks)
⏳ Monitor `idx_list_recipients_uid` usage in production

### Long Term (After monitoring)
📊 Review and potentially drop `idx_list_recipients_uid` if truly unused

---

## Why "Unused" Doesn't Mean "Useless"

### Index Usage Stats Are Cumulative
- Stats reset on database restart
- New indexes always show as unused
- Need real workload to accumulate stats

### Foreign Key Indexes Are Critical
Even if direct queries don't use them, they're essential for:
1. **CASCADE operations** (e.g., deleting a user)
2. **Referential integrity checks**
3. **Implicit JOINs** in complex queries
4. **Future query optimization**

### Test/Dev Databases Show False Positives
- Limited query patterns
- Small data volumes
- Not representative of production

---

## Monitoring Query

Use this to track index usage over time:

```sql
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan as times_used,
    idx_tup_read as rows_read,
    idx_tup_fetch as rows_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) as size,
    pg_size_pretty(pg_table_size(relid)) as table_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
AND indexname IN (
    'idx_claims_claimer_id',
    'idx_event_invites_inviter_id',
    'idx_events_owner_id',
    'idx_items_created_by',
    'idx_sent_reminders_event_id',
    'idx_list_recipients_uid',
    'idx_list_exclusions_uid'
)
ORDER BY times_used DESC, indexname;
```

Run this weekly to track usage patterns.

---

## Final Recommendation

**Do NOT drop any of the 7 indexes showing as unused.**

- 5 are brand new and need time to accumulate usage stats
- 1 is used by RLS (idx_list_exclusions_uid)
- 1 may be useful (idx_list_recipients_uid - monitor)

The "unused index" warnings are **INFO level** for a reason - they require human judgment and monitoring, not immediate action.

---

*Last Updated: 2025-10-08*
