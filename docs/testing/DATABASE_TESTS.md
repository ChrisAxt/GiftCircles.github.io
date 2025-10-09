# Database Testing Guide

## Overview

GiftCircles has a comprehensive database test suite covering:
- **RPC Functions** - Validation, authorization, error handling
- **RLS Policies** - Row-level security enforcement
- **Integrity** - Foreign keys, cascades, data consistency
- **Security** - SECURITY DEFINER audit, auth checks

## Test Structure

```
supabase/tests/
├── helpers/           # Test utilities
│   ├── 00_enable_extensions.sql
│   ├── 01_impersonation.sql
│   └── 02_seed_minimal.sql
│
├── smoke/            # Quick validation tests
│   ├── run_all.sql
│   ├── integrity_smoke.sql
│   ├── policies_smoke.sql
│   └── rpc_smoke.sql
│
├── rpc/              # Function validation tests
│   ├── rpc_validation.sql
│   ├── claim_counts_visibility.sql
│   ├── secdef_audit.sql
│   ├── rpc_fuzz_validation.sql
│   └── migration_017_tests.sql    # NEW - Tests for latest fixes
│
├── policies/         # RLS policy tests
│   ├── rls_write_matrix.sql
│   ├── rls_write_denials.sql
│   ├── policies_select_can_view_list.sql
│   └── policies_admin_wrappers.sql
│
└── integrity/        # Data consistency tests
    ├── rls_and_fk_tests.sql
    └── cascade_runtime.sql
```

## Running Tests

### Option 1: Run All Tests (Recommended)

```bash
# From repository root
psql YOUR_DATABASE_URL -f supabase/tests/run_all_tests.sql
```

This runs all test suites in the correct order.

### Option 2: Run Individual Test Suites

**Smoke Tests (Fast - ~5 seconds)**
```bash
psql YOUR_DATABASE_URL -f supabase/tests/smoke/run_all.sql
```

**RPC Tests**
```bash
psql YOUR_DATABASE_URL -f supabase/tests/rpc/rpc_validation.sql
psql YOUR_DATABASE_URL -f supabase/tests/rpc/migration_017_tests.sql
```

**Policy Tests**
```bash
psql YOUR_DATABASE_URL -f supabase/tests/policies/rls_write_matrix.sql
```

**Integrity Tests**
```bash
psql YOUR_DATABASE_URL -f supabase/tests/integrity/rls_and_fk_tests.sql
```

### Option 3: Run via Supabase SQL Editor

1. Navigate to your Supabase project
2. Go to **SQL Editor**
3. Create a new query
4. Copy/paste the contents of `run_all_tests.sql`
5. Click **Run**

## Test Coverage

### Migration 017 Tests (`rpc/migration_017_tests.sql`)

Tests all fixes from the latest migration:

**Function: `add_list_recipient`**
- ✅ Email format validation
- ✅ Authorization checks (creator or member only)
- ✅ Creates list_recipient record
- ✅ Returns user_id for registered emails
- ✅ Sends event invite to non-members
- ✅ Queues notification for registered users

**Function: `accept_event_invite`**
- ✅ Rejects invalid invite_id
- ✅ Enforces free tier limit (3 events max)
- ✅ Adds user to event_members when < 3 events
- ✅ Updates invite status to 'accepted'

**RLS: `notification_queue`**
- ✅ Users can view their own notifications
- ✅ Users cannot view others' notifications

### Other Test Coverage

**RPC Validation** (`rpc/rpc_validation.sql`)
- Empty parameter validation
- Invalid parameter rejection
- Authorization checks

**SECURITY DEFINER Audit** (`rpc/secdef_audit.sql`)
- All SECDEF functions set search_path
- Auth guard recommendations

**Claim Visibility** (`rpc/claim_counts_visibility.sql`)
- Recipients cannot see claims on their lists
- Givers can see claim counts

**RLS Policies** (`policies/*.sql`)
- Write permissions matrix
- Denial cases
- Admin wrapper functions

**Data Integrity** (`integrity/*.sql`)
- Foreign key enforcement
- Cascade deletions
- RLS + FK interaction

## Understanding Test Output

### Successful Test Run

```
1..13
ok 1 - add_list_recipient rejects invalid email format
ok 2 - add_list_recipient rejects unauthorized users
ok 3 - add_list_recipient succeeds for list creator
ok 4 - add_list_recipient returns user_id for registered email
ok 5 - add_list_recipient creates list_recipients record
ok 6 - add_list_recipient sends event invite to non-member registered user
ok 7 - add_list_recipient queues notification for registered recipient
ok 8 - accept_event_invite rejects invalid invite_id
ok 9 - accept_event_invite enforces free tier limit
ok 10 - accept_event_invite adds user to event_members
ok 11 - accept_event_invite updates invite status to accepted
ok 12 - Users can SELECT their own notifications from notification_queue
ok 13 - Users cannot SELECT other users notifications (RLS enforcement)
```

### Failed Test

```
not ok 5 - add_list_recipient creates list_recipients record
#   Failed test 'add_list_recipient creates list_recipients record'
#   at line 115
```

If a test fails:
1. Check the error message for details
2. Review the test code to understand what's being tested
3. Check the relevant function/policy implementation
4. Run the test individually for debugging

## Writing New Tests

### Test Template

```sql
-- Load helpers
\ir ../helpers/00_enable_extensions.sql
\ir ../helpers/01_impersonation.sql

BEGIN;

-- Create test plan
SELECT plan(N);  -- N = number of tests

-- Setup test data
DO $$
BEGIN
  -- Insert test users, events, etc.
END$$;

-- Test 1: Description
SELECT public.test_impersonate('user_id'::uuid);
SET ROLE authenticated;

SELECT ok(
  -- condition to test,
  'Test description'
);

-- More tests...

SELECT * FROM finish();
ROLLBACK;
```

### Test Functions (pgTAP)

**Assertions:**
- `ok(condition, description)` - Assert true
- `is(actual, expected, description)` - Assert equality
- `isnt(actual, expected, description)` - Assert inequality
- `lives_ok(sql, description)` - Assert no error
- `throws_like(sql, pattern, description)` - Assert error matches pattern

**Helpers:**
- `test_impersonate(user_id)` - Set auth.uid() for testing
- `plan(N)` - Declare number of tests
- `finish()` - Complete test run

## Continuous Integration

### Pre-Deployment Checklist

Before deploying to production:

1. ✅ Run full test suite: `psql -f supabase/tests/run_all_tests.sql`
2. ✅ All tests pass
3. ✅ Review any warnings
4. ✅ Check new migrations have tests

### Post-Deployment Verification

After deploying to production:

1. Run smoke tests on production database
2. Verify critical functions work:
   - `can_create_event`
   - `can_join_event`
   - `accept_event_invite`
   - `add_list_recipient`

## Troubleshooting

### "No users in auth.users" Error

Some tests require at least one user in `auth.users`:

```sql
-- Create test user via Supabase Auth UI or:
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at)
VALUES (
  gen_random_uuid(),
  'test@example.com',
  crypt('password123', gen_salt('bf')),
  now()
);
```

### "Extension not found" Error

Install required extensions:

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pgtap;
```

### Tests Pass Locally But Fail in CI

Check:
- Extension availability in CI environment
- Database version differences
- Timing/race conditions in tests

## Best Practices

1. **Test Critical Functions First** - Focus on SECURITY DEFINER, RLS, and business logic
2. **Use Transactions** - Wrap tests in BEGIN/ROLLBACK to avoid polluting database
3. **Test Edge Cases** - Empty strings, nulls, boundary conditions
4. **Test Error Messages** - Verify user-friendly errors are returned
5. **Test Authorization** - Verify RLS policies work as expected
6. **Keep Tests Fast** - Use minimal test data, avoid unnecessary setup
7. **Document Test Intent** - Clear descriptions for each test
8. **Test Migrations** - Every migration should have corresponding tests

## Next Steps

- Add integration tests for notification flow
- Add performance tests for large datasets
- Add regression tests for fixed bugs
- Set up automated test runs on PR

---

**Last Updated:** 2025-10-06
