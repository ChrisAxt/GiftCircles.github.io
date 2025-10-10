# Orphaned Lists Cleanup Feature

## Overview

This feature automatically handles the scenario where a user becomes the sole remaining member of an event but is excluded from certain lists. These lists become "orphaned" because there's no one else to view or manage them.

## How It Works

### Scenario
1. Multiple users are in an event
2. User A creates a list and excludes User B from seeing it
3. User A (and any other members) leave the event
4. User B is now the only member left in the event
5. User B is still excluded from the list, but there's no one else to see or manage it

### Solution
The system provides **two ways** to handle orphaned lists:

#### 1. Automatic Deletion (30-day grace period)
The system implements a **30-day grace period** before automatically deleting orphaned lists:

1. **Detection**: When a member leaves an event, a trigger checks if:
   - Only one member remains in the event
   - That remaining member is excluded from any lists

2. **Marking**: Orphaned lists are marked for deletion in the `orphaned_lists` table with:
   - `marked_at`: Timestamp when the list was marked
   - `delete_at`: Scheduled deletion time (30 days from marked_at)

3. **Cleanup**: A daily cron job runs at 3 AM UTC to:
   - Find all lists past their deletion date
   - Verify the conditions are still met (user is still sole member and still excluded)
   - Delete the lists and all associated data (items, claims, etc.)

4. **Unmarking**: If a new member joins the event before the 30-day period:
   - All orphaned list markers for that event are removed
   - Lists are preserved and continue to function normally

#### 2. Manual Deletion (Immediate)
If a new member joins the event and finds unwanted orphaned lists, they can delete them immediately:

1. **Permission Check**: Any event member can delete lists if the original creator is no longer in the event
2. **Applies to Lists and Items**: Both `delete_list` and `delete_item` functions support this
3. **No Waiting**: Users don't need to wait for the 30-day period or be an admin

**Example**:
- User A creates a list and leaves the event
- User B joins and finds the orphaned list
- User B can immediately delete the list, even if they're not an admin
- This prevents abandoned lists from cluttering the event

## Database Schema

### Table: `public.orphaned_lists`

```sql
CREATE TABLE public.orphaned_lists (
  id UUID PRIMARY KEY,
  list_id UUID REFERENCES lists(id) ON DELETE CASCADE,
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  excluded_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  marked_at TIMESTAMPTZ DEFAULT NOW(),
  delete_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '30 days'),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(list_id, excluded_user_id)
);
```

## Functions

### `is_sole_event_member(event_id, user_id)`
Checks if a user is the only remaining member of an event.

**Returns**: `BOOLEAN`

### `mark_orphaned_lists_for_deletion()`
Trigger function that runs when a member leaves an event. Marks lists for deletion if orphaned scenario is detected.

**Trigger**: `AFTER DELETE ON event_members`

### `cleanup_orphaned_lists()`
Deletes lists that have passed their 30-day grace period.

**Returns**: `INTEGER` (count of deleted lists)
**Schedule**: Daily at 3 AM UTC via pg_cron

### `unmark_orphaned_lists_on_member_join()`
Removes orphaned list markers when a new member joins an event.

**Trigger**: `AFTER INSERT ON event_members`

## Setup Instructions

### 1. Enable pg_cron Extension
In Supabase Dashboard:
1. Go to Database > Extensions
2. Search for "pg_cron"
3. Enable the extension

### 2. Apply SQL Migrations
Run these SQL files in Supabase SQL Editor (in order):

**Step 1: Create orphaned lists tracking system**
```bash
supabase/schema/orphaned_lists_cleanup.sql
```

**Step 2: Update delete functions for manual cleanup**
```bash
supabase/schema/allow_orphaned_list_deletion.sql
```

Or apply via Supabase Dashboard:
1. Go to SQL Editor
2. Paste the contents of each file
3. Run the queries in order

### 3. Verify Cron Job
Check that the cron job was created:
```sql
SELECT * FROM cron.job WHERE jobname = 'cleanup-orphaned-lists';
```

## Manual Cleanup

To manually trigger the cleanup process:
```sql
SELECT cleanup_orphaned_lists();
```

This will return the number of lists deleted.

## Monitoring

### Check Orphaned Lists
View all lists currently marked for deletion:
```sql
SELECT
  ol.*,
  l.name as list_name,
  e.title as event_title,
  p.display_name as excluded_user_name
FROM public.orphaned_lists ol
JOIN public.lists l ON l.id = ol.list_id
JOIN public.events e ON e.id = ol.event_id
JOIN public.profiles p ON p.id = ol.excluded_user_id
ORDER BY ol.delete_at ASC;
```

### Check Next Scheduled Cleanup
```sql
SELECT * FROM cron.job_run_details
WHERE jobid IN (SELECT jobid FROM cron.job WHERE jobname = 'cleanup-orphaned-lists')
ORDER BY start_time DESC
LIMIT 10;
```

## Edge Cases Handled

1. **User rejoins before deletion**: Lists are unmarked and preserved
2. **New member joins event**: All orphaned markers removed
3. **List is deleted manually**: Cascade delete removes orphaned_lists entry
4. **Event is deleted**: Cascade delete removes orphaned_lists entry
5. **User deletes account**: Cascade delete removes orphaned_lists entry
6. **Creator leaves event**: Any remaining member can delete the orphaned list immediately
7. **New member wants to clean up**: Can delete orphaned lists without admin privileges

## Safety Features

- **Grace period**: 30 days allows time for recovery
- **Re-verification**: Conditions are checked again at deletion time
- **Cascade protection**: Related data is cleaned up automatically
- **Atomic operations**: All checks and deletions happen in transactions

## Future Enhancements

Possible improvements:
- Notification to user when lists are marked for deletion
- UI to view and manage orphaned lists before deletion
- Configurable grace period per event or organization
- Option to transfer list ownership instead of deletion
