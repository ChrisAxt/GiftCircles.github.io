# Apply All Backend Hardening Migrations

## Current Status

Your database currently only has:
- ✅ Security audit log (from migration 061)
- ✅ Rate limit tracking (from migration 061/063)

**Missing**: The main application schema (events, lists, items, etc.) and other hardening migrations.

---

## Option 1: Apply ALL Migrations (Recommended if starting fresh)

This will apply all migrations from the beginning, including the hardening ones:

```bash
# Reset and apply all migrations
supabase db reset
```

This will:
1. Drop the current database
2. Recreate it from scratch
3. Apply ALL migrations in `/supabase/migrations/` in order
4. Give you a fully hardened database

---

## Option 2: Apply Only the Hardening Migrations (If you already have data)

If you already have a production database with data, apply only the 8 hardening migrations:

```bash
cd /home/chris/Documents/Repos/GiftCircles

# Apply migrations 058-065 in order
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f supabase/migrations/058_add_missing_indexes_performance.sql

psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f supabase/migrations/059_add_foreign_key_constraints.sql

psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f supabase/migrations/060_add_transaction_safety.sql

psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f supabase/migrations/061_security_audit_and_hardening.sql

psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f supabase/migrations/062_optimize_events_for_current_user.sql

psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f supabase/migrations/063_fix_rate_limit_rls.sql

psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f supabase/migrations/064_fix_search_path_warnings.sql

psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f supabase/migrations/065_fix_performance_warnings.sql
```

---

## Option 3: One-Command Apply (All hardening migrations)

```bash
cd /home/chris/Documents/Repos/GiftCircles

# Apply all 8 hardening migrations at once
for migration in 058 059 060 061 062 063 064 065; do
  echo "Applying migration ${migration}..."
  psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
    -f supabase/migrations/${migration}_*.sql
done
```

---

## Verification After Applying

After applying all migrations, verify success:

```bash
# Run verification script
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f scripts/verify_backend_hardening.sql
```

**Expected Results**:
- ✅ Foreign keys: ~30
- ✅ Indexes: 15+
- ✅ Security tables: present
- ✅ RLS enabled: all tables
- ✅ SECURITY DEFINER functions: with SET search_path
- ✅ Optimized RPCs: present

---

## What Each Migration Does

| Migration | What It Does | Required Base |
|-----------|--------------|---------------|
| 058 | Adds 15+ performance indexes | Needs base schema (events, lists, items, etc.) |
| 059 | Adds 30+ foreign key constraints | Needs base schema |
| 060 | Transaction safety for RPCs | Needs existing functions |
| 061 | Security audit + rate limiting | Creates new tables ✅ (already applied) |
| 062 | N+1 query optimization | Needs base schema |
| 063 | RLS on rate_limit_tracking | Needs migration 061 ✅ (already applied) |
| 064 | SET search_path for functions | Needs existing functions |
| 065 | Performance warning fixes | Needs base schema + policies |

---

## Recommendation

Since your database is mostly empty, I recommend **Option 1: Full Reset**

```bash
supabase db reset
```

This will give you the complete, hardened schema with all tables, functions, policies, and optimizations in one go.

Then verify:

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f scripts/verify_backend_hardening.sql
```

---

## If You Get Errors

The migrations are designed to be idempotent (safe to run multiple times), so if any migration fails:

1. Check the error message
2. The migration will rollback automatically (we use BEGIN/COMMIT)
3. Fix the issue or share the error with me
4. Re-run the migration

---

## Next Steps After Applying

1. ✅ Run verification script
2. ✅ Export schema for review (if you want me to verify)
3. ✅ Test your application
4. ✅ Deploy to production

---

**Ready to proceed!** Choose your option and let me know if you encounter any errors.
