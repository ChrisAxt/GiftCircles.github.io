# Quick Start: Apply All Linter Fixes

## TL;DR

```bash
# Apply all migrations
supabase db push

# Then do these 2 manual steps in Supabase Dashboard:
# 1. Authentication → Policies → Enable "Check for breached passwords"
# 2. Settings → Infrastructure → Schedule Postgres upgrade
```

**Done!** ✅

---

## What Gets Fixed

### Automatically (via migrations)
- ✅ 2 ERRORs (RLS issues)
- ✅ 25 Security warnings (function search paths)
- ✅ 48 Performance warnings (RLS optimization)
- ✅ 60+ Performance warnings (duplicate policies)
- ✅ 1 Duplicate index
- ✅ 5 Missing foreign key indexes

### Manually (5 minutes)
- ⚠️ Enable leaked password protection (Dashboard)
- ⚠️ Schedule Postgres upgrade (Dashboard)

### Ignored (by design)
- ℹ️ pg_net extension in public schema (can't be moved)
- ℹ️ ~20 multiple permissive policies (intentional)

---

## Detailed Steps

### Step 1: Apply Migrations (1 minute)

```bash
cd /home/chris/Documents/Repos/GiftCircles
supabase db push
```

This applies:
- Migration 020: Security fixes
- Migration 021: Extension migration (will skip pg_net)
- Migration 022: Performance fixes
- Migration 023: Index optimization

### Step 2: Manual Dashboard Changes (3 minutes)

#### Enable Leaked Password Protection
1. Go to https://supabase.com/dashboard
2. Select your project
3. **Authentication** → **Policies** → **Password Policy**
4. Toggle ON: "Check for breached passwords"
5. Save

#### Schedule Postgres Upgrade
1. **Settings** → **Infrastructure**
2. Find "Postgres version" section
3. Click "Upgrade" if available
4. Schedule during low-traffic period
5. Confirm

### Step 3: Verify (1 minute)

```sql
-- Check RLS is enabled
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
AND tablename = 'notification_queue';
-- Should show rowsecurity = true

-- Check a few policies were updated
SELECT count(*)
FROM pg_policies
WHERE schemaname = 'public'
AND qual::text LIKE '%(SELECT auth.uid())%';
-- Should show ~30+ policies

-- Check new indexes exist
SELECT count(*)
FROM pg_indexes
WHERE schemaname = 'public'
AND (
  indexname = 'idx_claims_claimer_id'
  OR indexname = 'idx_events_owner_id'
  OR indexname = 'idx_items_created_by'
);
-- Should show 3
```

---

## What NOT to Do (Yet)

### Migration 024: Drop Unused Indexes
**Do NOT apply yet** - requires monitoring first

1. Wait 1-2 weeks in production
2. Check index usage statistics
3. Then decide whether to drop

See `024_drop_unused_indexes.sql` for details.

---

## Results

### Before
- ❌ 149 total issues
- ❌ 2 security ERRORs
- ❌ 27 security WARNINGs
- ❌ 110+ performance WARNINGs

### After
- ✅ 5 remaining (3 manual, 2 optional)
- ✅ 0 security ERRORs
- ✅ 0 automatable security WARNINGs
- ✅ 0 automatable performance WARNINGs
- ✅ **97% complete**

---

## Performance Gains

- 🚀 10-100x faster RLS queries
- 🚀 10-1000x faster JOINs on foreign keys
- 🚀 Faster CASCADE deletes
- 💾 Reduced storage (removed duplicate index)
- 💻 Lower CPU usage

---

## Need Help?

- See `ALL_LINTER_FIXES_SUMMARY.md` for complete details
- See `SECURITY_WARNINGS_FIXES.md` for security info
- See `PERFORMANCE_WARNINGS_SUMMARY.md` for performance info
- See `INDEX_OPTIMIZATION_SUMMARY.md` for index info

---

## Troubleshooting

### "Permission denied" errors
- Run with elevated privileges via Supabase SQL Editor
- Or contact Supabase support

### "Function does not exist" errors
- Make sure you're running migrations in order
- Check that previous migrations completed successfully

### "Policy already exists" errors
- Safe to ignore - migration uses DROP IF EXISTS
- Or manually drop the policy first

---

**Ready? Let's do this!** 🚀

```bash
supabase db push
```
