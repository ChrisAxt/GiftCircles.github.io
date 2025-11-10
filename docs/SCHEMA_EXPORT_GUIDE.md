# Database Schema Export Guide

## Quick Reference

Use these scripts to export your database schema for review and verification.

---

## Method 1: Comprehensive Text Export (Recommended)

**Best for**: Human-readable review of all database objects

```bash
# Local database
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f scripts/export_database_schema.sql \
  > schema_export.txt

# Production database (via Supabase)
psql "postgresql://postgres:[YOUR-PASSWORD]@[YOUR-PROJECT-REF].supabase.co:5432/postgres" \
  -f scripts/export_database_schema.sql \
  > schema_export.txt
```

**Output**: `schema_export.txt` - Comprehensive text file with all database objects organized by category

---

## Method 2: JSON Export

**Best for**: Machine-readable format for parsing/comparison

```bash
# Local database
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f scripts/export_schema_json.sql \
  > schema.json

# Production database
psql "postgresql://postgres:[YOUR-PASSWORD]@[YOUR-PROJECT-REF].supabase.co:5432/postgres" \
  -f scripts/export_schema_json.sql \
  > schema.json
```

**Output**: `schema.json` - JSON formatted schema data

---

## Method 3: Quick One-Liners

### List All Tables
```bash
psql $DATABASE_URL -c "SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;"
```

### List All Policies
```bash
psql $DATABASE_URL -c "SELECT tablename, policyname, cmd FROM pg_policies WHERE schemaname = 'public' ORDER BY tablename, policyname;"
```

### List All Functions
```bash
psql $DATABASE_URL -c "SELECT proname, prosecdef FROM pg_proc WHERE pronamespace = 'public'::regnamespace ORDER BY proname;"
```

### List All Indexes
```bash
psql $DATABASE_URL -c "SELECT tablename, indexname FROM pg_indexes WHERE schemaname = 'public' ORDER BY tablename, indexname;"
```

### List All Constraints
```bash
psql $DATABASE_URL -c "SELECT conrelid::regclass AS table, conname, contype FROM pg_constraint WHERE connamespace = 'public'::regnamespace ORDER BY table, conname;"
```

---

## Method 4: Using Supabase CLI

If you're using Supabase CLI, you can also:

```bash
# Generate migration from current database state
supabase db dump -f schema_dump.sql

# Or get specific schema file
supabase db dump --schema public -f public_schema.sql
```

---

## Method 5: Copy Entire Output Here

For me to review, you can simply run:

```bash
# Export everything to a single file
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f scripts/export_database_schema.sql > full_schema.txt

# Then paste the contents here or use:
cat full_schema.txt
```

---

## What to Look For (Verification Checklist)

When reviewing the export, verify:

### Tables
- [ ] All expected tables exist
- [ ] RLS is enabled on all user-facing tables
- [ ] Columns match expected schema

### Constraints
- [ ] Primary keys exist on all tables
- [ ] Foreign keys with CASCADE rules present
- [ ] Unique constraints on appropriate columns

### Indexes
- [ ] Performance indexes from migration 058 exist
- [ ] Duplicate indexes removed (migration 065)
- [ ] Covering indexes present

### Policies
- [ ] All tables have appropriate RLS policies
- [ ] Policies use optimized `(SELECT auth.uid())` pattern
- [ ] Security tables block public access

### Functions
- [ ] All SECURITY DEFINER functions have `SET search_path`
- [ ] Rate limiting functions exist
- [ ] Audit logging functions exist
- [ ] Optimized RPC functions exist

### Security
- [ ] No tables without RLS (except system tables)
- [ ] No SECURITY DEFINER functions without search_path
- [ ] Rate limiting enabled on sensitive operations

---

## Example: Quick Table Check

```bash
# Run this to quickly check table status
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres << 'EOF'
SELECT
  t.tablename,
  t.rowsecurity AS rls_enabled,
  (SELECT COUNT(*) FROM pg_policies p WHERE p.tablename = t.tablename) AS policy_count,
  (SELECT COUNT(*) FROM pg_indexes i WHERE i.tablename = t.tablename) AS index_count,
  (SELECT COUNT(*) FROM pg_constraint c WHERE c.conrelid = ('public.' || t.tablename)::regclass) AS constraint_count
FROM pg_tables t
WHERE t.schemaname = 'public'
ORDER BY t.tablename;
EOF
```

---

## Comparing Schemas

To compare local vs production:

```bash
# Export local
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f scripts/export_database_schema.sql > local_schema.txt

# Export production
psql "$PRODUCTION_DATABASE_URL" \
  -f scripts/export_database_schema.sql > prod_schema.txt

# Compare
diff local_schema.txt prod_schema.txt
```

---

## For Claude Code Review

To have me review your database schema, run:

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f scripts/export_database_schema.sql
```

Then paste the output in our conversation. I'll verify:
1. All migration changes applied correctly
2. All security measures in place
3. All performance optimizations present
4. No issues or warnings

---

## Troubleshooting

### Connection Refused
```bash
# Make sure Supabase is running
supabase status

# If not, start it
supabase start
```

### Permission Denied
```bash
# Use postgres user for full access
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres
```

### Script Not Found
```bash
# Make sure you're in the project root
cd /home/chris/Documents/Repos/GiftCircles

# Then run the script
psql ... -f scripts/export_database_schema.sql
```

---

## Quick Export Command (Copy-Paste Ready)

```bash
# For local Supabase
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -f scripts/export_database_schema.sql

# Save to file
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -f scripts/export_database_schema.sql > schema_review.txt

# Then share the file contents with Claude Code
cat schema_review.txt
```

---

That's it! Run any of these commands and share the output for comprehensive schema verification.
