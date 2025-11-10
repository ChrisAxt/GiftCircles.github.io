# GiftCircles Database Schema

## Overview

This directory contains the consolidated database schema for the GiftCircles application.

## Files

- **schema_consolidated.sql** - Complete database schema (single source of truth)
- **config.toml** - Supabase edge function configuration
- **functions/** - Supabase edge functions (Deno)
- **tests/** - Database tests

## Schema Structure

The consolidated schema file contains:

### 1. Extensions
- `pgcrypto` - For UUID generation
- `pg_cron` - For scheduled jobs

### 2. Types (Enums)
- `member_role` - Event member roles: giver, recipient, admin
- `list_visibility` - List visibility levels

### 3. Tables (16 total)
- **claims** - Item claims by users
- **daily_activity_log** - Activity tracking for digest notifications
- **event_invites** - Event invitations
- **event_members** - Event membership
- **events** - Events (Christmas, birthdays, etc.)
- **items** - Gift list items
- **list_exclusions** - Users excluded from seeing lists
- **list_recipients** - List recipients
- **list_viewers** - Users with custom view access
- **lists** - Gift lists
- **notification_queue** - Push notification queue
- **orphaned_lists** - Lists marked for cleanup
- **profiles** - User profiles
- **push_tokens** - Push notification tokens
- **sent_reminders** - Purchase reminder tracking
- **user_plans** - User subscription plans

### 4. Functions (81 total)
All RPC functions and helper functions for:
- Event management
- List operations
- Claims and purchases
- Notifications
- Invites
- Access control
- Daily digest system
- Orphaned list cleanup

### 5. Triggers (8 total)
- Auto-join event as admin on creation
- Notify on new list/item/claim
- Cleanup reminders on purchase
- Update invites on user signup
- Link list recipients on signup
- Timestamp updates

### 6. RLS Policies (54 total)
Row Level Security policies for all tables enforcing:
- User authentication
- Event membership
- Admin permissions
- List visibility
- Recipient privacy

### 7. Indexes (20+ total)
Optimized indexes for:
- Foreign key relationships
- Frequently queried columns
- Composite queries
- Digest notification lookups

## Deployment

To deploy this schema to a fresh database:

```bash
psql "$DATABASE_URL" < schema_consolidated.sql
```

Or via Supabase CLI:

```bash
supabase db reset
psql "$DATABASE_URL" < schema_consolidated.sql
```

## Key Features

### Free Tier Limits
- 3 events maximum for free users
- Access limited to 3 most recent events
- Enforced via `can_create_event()` and `can_join_event()`

### Notification System
- Push notifications for new lists, items, claims
- Purchase reminders based on event dates
- Daily/weekly activity digest emails
- Configurable per user

### Invite System
- Email invites for events
- Auto-link invites when users sign up
- List recipient invites (auto-invite to event)

### Orphaned List Cleanup
- Automatic detection of orphaned lists
- 30-day grace period before deletion
- Triggered when list creator leaves event

### Event Recurrence
- Weekly, monthly, yearly recurring events
- Automatic rollover of event dates
- Preserves lists and items across recurrences

## Schema Changes

All future schema changes should be made by:
1. Updating `schema_consolidated.sql`
2. Creating a timestamped migration file if needed
3. Applying changes to production database

Previous migration history (000-032) has been consolidated into this file.

## Notes

- All tables have RLS enabled and FORCE RLS for security
- Functions use SECURITY DEFINER to bypass RLS where needed
- Timestamps are in UTC (timestamp with time zone)
- UUIDs are used for all primary keys
