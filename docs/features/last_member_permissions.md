# Last Member Permissions

## Overview
When a user becomes the last remaining member of an event (all other members have left), they automatically gain full permissions to manage the event. This prevents orphaned events that nobody can delete or modify.

## Problem Solved
**Before:** If all event admins left an event, the remaining member couldn't:
- Delete lists created by others
- Delete items created by others
- Edit the event
- Delete the event

This created "orphaned" events that nobody could manage.

**After:** The last remaining member can:
- ✅ Delete any list in the event
- ✅ Delete any item in the event
- ✅ Edit the event
- ✅ Delete the event
- ✅ Manage all list recipients

## Implementation

### Database Function

```sql
CREATE OR REPLACE FUNCTION public.is_last_event_member(e_id uuid, u_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $
  SELECT
    EXISTS (
      SELECT 1 FROM public.event_members
      WHERE event_id = e_id AND user_id = u_id
    )
    AND
    (SELECT count(*) FROM public.event_members WHERE event_id = e_id) = 1
$;
```

**How it works:**
1. Checks if the user is a member of the event
2. Counts total members in the event
3. Returns `true` only if both conditions are met: user is a member AND count = 1

### Database Policies

#### Events Table
```sql
-- Allow last member to update event
CREATE POLICY "update events by admin or last member"
  ON public.events FOR UPDATE
  USING (
    (SELECT role FROM public.event_members WHERE event_id = id AND user_id = auth.uid()) = 'admin'
    OR public.is_last_event_member(id, auth.uid())
  );

-- Allow last member to delete event
CREATE POLICY "delete events by admin or last member"
  ON public.events FOR DELETE
  USING (
    (SELECT role FROM public.event_members WHERE event_id = id AND user_id = auth.uid()) = 'admin'
    OR public.is_last_event_member(id, auth.uid())
  );
```

#### Lists Table
```sql
-- Allow last member to update any list
CREATE POLICY "update lists by creator or last member"
  ON public.lists FOR UPDATE
  USING (
    created_by = auth.uid()
    OR public.is_last_event_member(event_id, auth.uid())
  );

-- Allow last member to delete any list
CREATE POLICY "delete lists by creator or last member"
  ON public.lists FOR DELETE
  USING (
    created_by = auth.uid()
    OR public.is_last_event_member(event_id, auth.uid())
  );
```

#### Items Table
```sql
-- Allow last member to update any item
CREATE POLICY "update items by creator or last member"
  ON public.items FOR UPDATE
  USING (
    created_by = auth.uid()
    OR public.is_last_event_member(
      (SELECT event_id FROM public.lists WHERE id = list_id),
      auth.uid()
    )
  );

-- Allow last member to delete any item
CREATE POLICY "delete items by creator or last member"
  ON public.items FOR DELETE
  USING (
    created_by = auth.uid()
    OR public.is_last_event_member(
      (SELECT event_id FROM public.lists WHERE id = list_id),
      auth.uid()
    )
  );
```

#### List Recipients Table
```sql
-- Allow last member to delete any recipient
CREATE POLICY "delete recipients by list creator or last member"
  ON public.list_recipients FOR DELETE
  USING (
    (SELECT created_by FROM public.lists WHERE id = list_id) = auth.uid()
    OR public.is_last_event_member(
      (SELECT event_id FROM public.lists WHERE id = list_id),
      auth.uid()
    )
  );
```

### UI Implementation

#### ListDetailScreen
```typescript
const [eventMemberCount, setEventMemberCount] = useState<number>(0);

// Fetch member count during load
const { count: memberCount } = await supabase
  .from('event_members')
  .select('*', { count: 'exact', head: true })
  .eq('event_id', listRow.event_id);

setEventMemberCount(memberCount ?? 0);

// Check if user can delete item
const canDeleteItem = useCallback((item: Item) => {
  if (!myUserId) return false;
  const isLastMember = eventMemberCount === 1;
  return item.created_by === myUserId || isOwner || isAdmin || isLastMember;
}, [myUserId, isOwner, isAdmin, eventMemberCount]);

// Check if user can delete list
const canDeleteList = isOwner || isAdmin || eventMemberCount === 1;
```

#### EventDetailScreen
```typescript
// Show edit/delete buttons if admin OR last member
right={
  (isAdmin || members.length === 1) ? (
    <View style={{ flexDirection: 'row' }}>
      <Pressable onPress={() => navigation.navigate('EditEvent', { id })}>
        <Text>{t('eventDetail.toolbar.edit')}</Text>
      </Pressable>
      <Pressable onPress={deleteEvent}>
        <Text>{t('eventDetail.toolbar.delete')}</Text>
      </Pressable>
    </View>
  ) : null
}

// Allow last member to delete event
const deleteEvent = useCallback(() => {
  const isLastMember = members.length === 1;
  if (!isAdmin && !isLastMember) {
    Alert.alert(
      t('eventDetail.alerts.notAllowedTitle'),
      t('eventDetail.alerts.onlyAdminDelete')
    );
    return;
  }
  // ... rest of delete logic
}, [isAdmin, members, event, navigation, t]);
```

## Migrations

### Migration 018: Add Policies
```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/018_add_update_delete_policies.sql
```

**What it does:**
- Creates `is_last_event_member()` function
- Adds UPDATE and DELETE policies for events, lists, items, list_recipients

### Migration 019: Remove Conflicting Policies
```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/019_fix_duplicate_policies.sql
```

**What it does:**
- Drops old restrictive policies that blocked last member access
- Policies like `"creators can delete own items"` evaluated before new policies
- Removing them allows new permissive policies to work

## Testing

### Test Scenario 1: List Deletion
```
1. User A creates event
2. User A invites User B
3. User B joins event
4. User B creates a list with items
5. User A leaves the event
6. User B (now last member) should be able to delete the list
```

**Expected:**
- ✅ User B sees delete button on list
- ✅ User B can delete list created by User A (before they left)
- ✅ User B can delete items created by User A

### Test Scenario 2: Event Deletion
```
1. User A creates event (admin)
2. User A invites User B (member)
3. User B joins event
4. User A leaves the event
5. User B (now last member) should be able to delete the event
```

**Expected:**
- ✅ User B sees edit/delete buttons in event toolbar
- ✅ User B can edit event details
- ✅ User B can delete entire event

### Test Scenario 3: Multiple Members
```
1. User A creates event
2. User B and User C join
3. User A leaves
4. User B should NOT have last member permissions (User C still there)
```

**Expected:**
- ❌ User B does NOT see delete button for User C's lists
- ❌ User B cannot delete event
- ✅ User B can still delete their own content

### Database Testing

```sql
-- Create test scenario
INSERT INTO events (id, title, date) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Test Event', '2025-12-25');

INSERT INTO event_members (event_id, user_id, role) VALUES
  ('00000000-0000-0000-0000-000000000001', auth.uid(), 'member');

-- Test: Is last member (should be true)
SELECT is_last_event_member(
  '00000000-0000-0000-0000-000000000001'::uuid,
  auth.uid()
);
-- Expected: true

-- Add second member
INSERT INTO event_members (event_id, user_id, role) VALUES
  ('00000000-0000-0000-0000-000000000001', 'some-other-user-id', 'member');

-- Test: Is last member (should be false now)
SELECT is_last_event_member(
  '00000000-0000-0000-0000-000000000001'::uuid,
  auth.uid()
);
-- Expected: false
```

## Edge Cases

### Case 1: User Leaves and Rejoins
**Scenario:** User is last member, someone else joins, then leaves again.

**Expected Behavior:**
- Permissions update dynamically based on current member count
- No special handling needed (function checks count in real-time)

### Case 2: Event with No Members
**Scenario:** All users leave event (shouldn't be possible, but just in case).

**Expected Behavior:**
- No user has access to the event
- Event becomes truly orphaned
- Manual database cleanup may be needed
- Consider adding a database trigger to delete events with zero members

### Case 3: Race Condition
**Scenario:** Two users both think they're the last member (leave at same time).

**Expected Behavior:**
- PostgreSQL transaction isolation handles this
- Function always returns accurate count
- No race condition possible (atomic operations)

## Troubleshooting

### Delete Button Not Showing

**Check UI state:**
```typescript
console.log('Event member count:', eventMemberCount);
console.log('Is last member:', eventMemberCount === 1);
console.log('Can delete list:', canDeleteList);
```

**Check database:**
```sql
-- Get member count for an event
SELECT COUNT(*) FROM event_members WHERE event_id = 'YOUR_EVENT_ID';

-- Test the function
SELECT is_last_event_member('YOUR_EVENT_ID'::uuid, auth.uid());
```

### Delete Fails with "Permission Denied"

**Check for conflicting policies:**
```sql
-- List all policies on the table
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'items'  -- or 'lists', 'events'
ORDER BY policyname;
```

**Look for old restrictive policies:**
- `"creators can delete own items"`
- `"creators can update own lists"`

These should have been removed by migration 019.

**Manually remove if needed:**
```sql
DROP POLICY IF EXISTS "creators can delete own items" ON public.items;
DROP POLICY IF EXISTS "creators can update own items" ON public.items;
-- Repeat for lists, events, etc.
```

### Function Returns Incorrect Value

**Verify member count:**
```sql
SELECT
  e.title,
  COUNT(em.user_id) as member_count
FROM events e
LEFT JOIN event_members em ON em.event_id = e.id
WHERE e.id = 'YOUR_EVENT_ID'
GROUP BY e.id, e.title;
```

**Test function with specific user:**
```sql
SELECT is_last_event_member(
  'YOUR_EVENT_ID'::uuid,
  'USER_ID'::uuid
);
```

## Performance Considerations

### Function Performance
- `STABLE` function - result won't change within a transaction
- Uses simple COUNT query (fast on indexed table)
- No significant performance impact

### Policy Performance
- Policies evaluated on every query
- Member count checked once per query
- Consider adding index if slow:
  ```sql
  CREATE INDEX IF NOT EXISTS idx_event_members_event_id
  ON event_members(event_id);
  ```

## Security Considerations

### Authorization
- Only members can become "last member"
- Non-members always get `false` from function
- RLS still enforces event membership

### Audit Trail
Consider adding audit logging:
```sql
-- Log deletions by last member
CREATE TABLE event_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid REFERENCES events(id),
  user_id uuid REFERENCES auth.users(id),
  action text,
  details jsonb,
  created_at timestamptz DEFAULT now()
);
```

## Future Enhancements

1. **Notification When Becoming Last Member:**
   ```
   "You're now the only member of 'Birthday Party 2025'.
    You can delete this event if you no longer need it."
   ```

2. **Confirmation Dialog:**
   ```
   "You're the last member. Deleting this event will permanently
    remove all lists and items. Continue?"
   ```

3. **Auto-Cleanup:**
   - Delete events with no members after 30 days
   - Send warning notification before deletion

4. **Transfer Ownership:**
   - Allow last member to transfer event to someone else
   - Invite new admin before leaving

## Related Documentation

- [Database Migrations](../MIGRATION_GUIDE.md)
- [Row Level Security](../testing/DATABASE_TESTS.md)
- [Event Member Roles](./event_member_roles.md)

## Files Modified

**Migrations:**
- `supabase/migrations/018_add_update_delete_policies.sql`
- `supabase/migrations/019_fix_duplicate_policies.sql`

**UI:**
- `src/screens/ListDetailScreen.tsx`
- `src/screens/EventDetailScreen.tsx`

**Documentation:**
- `docs/CHANGELOG.md`
- `docs/SESSION_SUMMARY_2025-10-08.md`
- `docs/features/last_member_permissions.md` (this file)

---

**Created:** 2025-10-08
**Status:** Implemented and tested
**Version:** 1.0.0
