# Free Tier Invite Bug Fix

## Problem

**Critical Bug:** Free users with 3 events can accept invites and create a 4th event membership that becomes inaccessible.

### Scenario:
1. User has 3 events (free tier limit)
2. Someone creates a list with them as recipient
3. User receives invite notification
4. User accepts the invite
5. ❌ **User now has 4 event memberships** (violates limit!)
6. ❌ **Only 3 events are accessible**, 4th is locked
7. ❌ **Confusing experience** - accepted invite but can't see event

### Root Cause:
The `accept_event_invite()` function **does not check** `can_join_event()` before adding the user to `event_members`.

## Solution

### Database Fix (`fix_accept_invite_free_tier_limit.sql`)

Updated `accept_event_invite()` to:
1. ✅ Check `can_join_event()` before accepting
2. ✅ Raise `free_limit_reached` exception if limit exceeded
3. ✅ Provide helpful hint message

```sql
-- Check if user can join (free tier limit check)
IF NOT public.can_join_event(v_user_id) THEN
  RAISE EXCEPTION 'free_limit_reached'
    USING HINT = 'You can only be a member of 3 events on the free plan. Upgrade to join more events.';
END IF;
```

### Frontend Fix (`src/components/PendingInvitesCard.tsx`)

Updated `handleAccept()` to:
1. ✅ Catch `free_limit_reached` error
2. ✅ Show user-friendly upgrade message
3. ✅ Suggest leaving an existing event

```typescript
if (error?.message?.includes('free_limit_reached')) {
  Alert.alert(
    'Upgrade Required',
    'You can only be a member of 3 events on the free plan. Upgrade to join more events or leave an existing event first.',
    [{ text: 'OK' }]
  );
}
```

## Testing

### Test Case 1: Free user at limit
1. Create/join 3 events as free user
2. Have someone create a list with you as recipient
3. Receive notification
4. Try to accept invite
5. ✅ Should see "Upgrade Required" message
6. ✅ Invite should remain in `pending` status
7. ✅ Should NOT be added to `event_members`

### Test Case 2: Pro user at limit
1. Be a pro user with 3+ events
2. Receive invite
3. Try to accept invite
4. ✅ Should accept successfully (no limit for pro)

### Test Case 3: Free user under limit
1. Have only 2 events as free user
2. Receive invite
3. Try to accept invite
4. ✅ Should accept successfully
5. ✅ Now has 3 events

## SQL to Test

```sql
-- Check your current event count
SELECT COUNT(*) as event_count
FROM event_members
WHERE user_id = auth.uid();

-- Check if you can join more events
SELECT can_join_event(auth.uid()) as can_join;

-- Check if you're pro
SELECT is_pro(auth.uid(), now()) as is_pro;

-- Try to accept an invite (replace with your invite_id)
SELECT accept_event_invite('YOUR_INVITE_ID'::uuid);
-- Should fail with "free_limit_reached" if you have 3 events already
```

## Migration Instructions

1. **Run the SQL migration:**
   ```bash
   # Via Supabase dashboard SQL editor
   # Copy contents of fix_accept_invite_free_tier_limit.sql and run
   ```

2. **Reload the app** (no rebuild needed):
   ```bash
   # In Metro bundler or shake device → Reload
   ```

3. **Test the fix:**
   - Create scenario with 3 events
   - Try accepting invite
   - Should see upgrade message

## User Impact

### Before Fix:
- ❌ Users could exceed free tier limit
- ❌ Created inaccessible events
- ❌ Confusing "I accepted but can't see it" experience
- ❌ Database inconsistency

### After Fix:
- ✅ Users clearly told they're at limit
- ✅ Invitation remains pending (can accept later after leaving event)
- ✅ Option to upgrade or leave existing event
- ✅ Database stays consistent

## Related Functions

Other functions that already have limit checks:
- ✅ `join_event()` - checks `can_join_event()` (line 123 in 006_free_tier_membership_limit.sql)
- ✅ `can_create_event()` - checks total memberships (line 10-21)
- ✅ `can_join_event()` - checks total memberships (line 26-37)
- ❌ `accept_event_invite()` - **WAS MISSING** (now fixed!)

## Future Enhancements

Potential improvements:
1. Show "2/3 events" counter in UI
2. Allow user to choose which event to leave before accepting
3. Queue invites with message "Accept after leaving an event"
4. Send notification when user drops below limit (reminder about pending invites)

## Files Modified
- ✅ `fix_accept_invite_free_tier_limit.sql` (new migration)
- ✅ `src/components/PendingInvitesCard.tsx` (error handling)
