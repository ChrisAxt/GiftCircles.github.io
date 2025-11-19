# Archived Migrations

This folder contains all migrations from the initial development phase (migrations 000-099).

These migrations have been applied to the production database and are kept here for historical reference.

## Migration History

- **000-019**: Initial schema, RLS policies, free tier limits, join codes, push notifications
- **020-039**: Event invites, list recipients, policy fixes, statistics tracking
- **040-059**: Security hardening, foreign key constraints, performance optimizations
- **060-079**: Search path fixes, split claims, currency support, orphaned lists cleanup
- **080-099**: Event member stats, digest notifications, timezone support, instant notifications

## Important Notes

1. **Do not re-apply these migrations** - They have already been applied to the database
2. **Future migrations** should start from migration 100 or use a new numbering scheme
3. **Schema reference** - For the current database schema, export directly from Supabase
4. These files are kept for audit trail and understanding schema evolution

## Archive Date

2025-11-16
