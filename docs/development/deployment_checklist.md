# GiftCircles Security Fixes - Deployment Checklist

## Pre-Deployment

### 1. Database Backup ✅
- [ ] Create Supabase backup via dashboard (Database → Backups)
- [ ] Or run: `pg_dump "$SUPABASE_DB_URL" > backup_$(date +%Y%m%d).sql`
- [ ] Verify backup file exists and is not empty

### 2. Review Changes ✅
- [ ] Read `SECURITY_ANALYSIS.md` to understand issues
- [ ] Read `MIGRATION_SUMMARY.md` to understand fixes
- [ ] Review migration files in `supabase/migrations/`

### 3. Test Environment (if available) ✅
- [ ] Apply migrations to test database first
- [ ] Run test suite: `npm test -- supabase/tests/db`
- [ ] Verify client app still works
- [ ] Check error messages are user-friendly

## Deployment Steps

### Step 1: Apply Migrations ⚙️

**⚠️ IMPORTANT**: Migration 003 has a critical bug. Use the corrected approach below:

**Option A: Via Supabase Dashboard (Recommended)**
1. [ ] Go to Supabase Dashboard → SQL Editor
2. [ ] Run migration 001: `supabase/migrations/001_force_rls_security.sql`
3. [ ] Run migration 002: `supabase/migrations/002_add_rpc_validation.sql`
4. [ ] **SKIP migration 003** (has infinite recursion bug)
5. [ ] Run migration 004: `supabase/migrations/004_rollback_event_members_policy.sql`
6. [ ] Run migration 005: `supabase/migrations/005_fix_event_members_visibility_correct.sql`

**Option B: Via psql**
```bash
# Set your database URL
export SUPABASE_DB_URL="your-connection-string"

# Apply migrations (SKIP 003)
psql "$SUPABASE_DB_URL" -f supabase/migrations/001_force_rls_security.sql
psql "$SUPABASE_DB_URL" -f supabase/migrations/002_add_rpc_validation.sql
# DO NOT RUN: 003_fix_authorization_logic.sql (has recursion bug)
psql "$SUPABASE_DB_URL" -f supabase/migrations/004_rollback_event_members_policy.sql
psql "$SUPABASE_DB_URL" -f supabase/migrations/005_fix_event_members_visibility_correct.sql
```

**Option C: If You Already Ran Migration 003 (EMERGENCY FIX)**
```bash
# Your app is currently broken - run these immediately:
psql "$SUPABASE_DB_URL" -f supabase/migrations/004_rollback_event_members_policy.sql
psql "$SUPABASE_DB_URL" -f supabase/migrations/005_fix_event_members_visibility_correct.sql
# App should work again after 004
```

### Step 2: Verify Migrations ✅

Run these SQL queries in Supabase SQL Editor:

```sql
-- ✅ Check RLS is forced
SELECT
  tablename,
  c.relforcerowsecurity as rls_forced
FROM pg_tables t
JOIN pg_class c ON c.relname = t.tablename
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND tablename IN ('events', 'lists', 'items', 'claims', 'event_members')
ORDER BY tablename;
-- Expected: All rows show rls_forced = true

-- ✅ Check SECURITY DEFINER helper function exists (prevents recursion)
SELECT proname, prosecdef
FROM pg_proc
WHERE proname = 'is_member_of_event_secure'
  AND pronamespace = 'public'::regnamespace;
-- Expected: 1 row with prosecdef = true

-- ✅ Check correct policies exist (NOT the broken ones)
SELECT tablename, policyname
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('event_members', 'claims')
ORDER BY tablename, policyname;
-- Expected: event_members_select, claims_select_visible
-- NOT EXPECTED: event_members_select_all (this one causes recursion)

-- ✅ Check function validation works
SELECT public.create_event_and_admin('', current_date, 'none', null);
-- Expected: ERROR containing "invalid_parameter"

-- 🚨 CRITICAL: Test for recursion bug
-- This should NOT error with "infinite recursion"
SELECT * FROM event_members LIMIT 1;
-- Expected: Returns data OR empty result (but NO recursion error)
```

### Step 3: Test Critical Paths 🧪

- [ ] **User Registration**: Create new user
- [ ] **Event Creation**: Create event with valid data
- [ ] **Event Creation Error**: Try creating event with empty title (should error)
- [ ] **Join Event**: Join event with valid code
- [ ] **Join Event Error**: Try joining with empty code (should error)
- [ ] **List Creation**: Create list in event
- [ ] **Item Creation**: Add item to list
- [ ] **Claim Item**: Claim an item
- [ ] **View Claims**: Verify list creator can see who claimed

### Step 4: Monitor for Issues 📊

- [ ] Check Supabase logs for errors (Dashboard → Logs)
- [ ] Monitor client error reports
- [ ] Watch for performance issues
- [ ] Check user feedback channels

## Post-Deployment

### Immediate (First Hour)
- [ ] Verify no critical errors in logs
- [ ] Test one complete user flow end-to-end
- [ ] Confirm RLS is working (users can't see other users' data)

### First Day
- [ ] Monitor error rates
- [ ] Check for unexpected `invalid_parameter` errors
- [ ] Verify free tier limits working correctly
- [ ] Confirm member visibility works properly

### First Week
- [ ] Review all error logs
- [ ] Gather user feedback
- [ ] Check for performance issues
- [ ] Plan remaining improvements from SECURITY_ANALYSIS.md

## Rollback Procedure (Emergency Only)

If critical issues occur:

### Option 1: Supabase Time Travel
1. Go to Database → Backups
2. Select backup from before migration
3. Click "Restore"
4. Wait for restore to complete

### Option 2: Manual Restore
```bash
psql "$SUPABASE_DB_URL" < backup_YYYYMMDD.sql
```

### Option 3: Contact Support
- Supabase support: support@supabase.io
- Include: project ID, timestamp of deployment, error details

## Success Criteria

✅ All migrations applied without errors
✅ Verification queries return expected results
✅ Critical user paths work
✅ No spike in error rates
✅ Tests passing (once test users created)
✅ No rollback needed within 24 hours

## Known Limitations & Next Steps

### For Test Suite to Pass:
Create test users with these SQL commands:
```sql
-- See SECURITY_ANALYSIS.md for full SQL
-- Creates alice, bob, carl with specific UUIDs
```

### Future Improvements (Not Blocking):
1. Add rate limiting on join_event
2. Add XSS sanitization
3. Add audit timestamps
4. Simplify list visibility modes
5. Add soft deletes

## Support Contacts

- **Database Issues**: Supabase Dashboard → Support
- **Migration Questions**: Review `supabase/migrations/README.md`
- **Security Concerns**: Review `SECURITY_ANALYSIS.md`

---

## Final Checklist Before "Go"

- [ ] Backup created and verified
- [ ] Migrations reviewed and understood
- [ ] Test environment validated (if available)
- [ ] Deployment time scheduled (off-peak hours)
- [ ] Rollback plan understood
- [ ] Monitoring tools ready
- [ ] Team notified of deployment

**Ready to Deploy?** ✅

**Deployed By**: ________________

**Deployment Date**: ________________

**Deployment Time**: ________________

**Status After 1 Hour**: ________________

**Status After 24 Hours**: ________________

---

*Version: 1.0.0*
*Last Updated: 2025-10-02*
