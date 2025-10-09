# Join Button Free Tier Limit Check

## Summary
Added free tier limit validation to the "Join" button on the Events list screen, matching the behavior of the "Create" button.

## Problem
Previously:
- ❌ "Create" button checks limit before navigation ✅
- ❌ "Join" button allowed navigation regardless of limit ❌
- Users could navigate to JoinEvent screen even at 3-event limit
- Would see error only after entering a join code
- Inconsistent UX between Create and Join buttons

## Solution
Added `onPressJoin()` function that:
1. ✅ Checks authentication
2. ✅ Calls `can_join_event()` RPC to validate limit
3. ✅ Shows upgrade alert if at limit
4. ✅ Only navigates to JoinEvent screen if allowed
5. ✅ Matches the pattern used by `onPressCreate()`

## Changes Made

### 1. EventListScreen.tsx
**Added `onPressJoin()` function:**
```typescript
const onPressJoin = async () => {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      navigation.navigate('Profile');
      return;
    }

    // Check free tier limit
    const { data: canJoin, error: checkError } = await supabase.rpc('can_join_event', {
      p_user: user.id
    });

    if (checkError) {
      // Show error, don't navigate
      Alert.alert('Something went wrong', 'Please try again.');
      return;
    }

    // Block if at limit
    if (canJoin === false) {
      Alert.alert(
        'Upgrade required',
        'You can only be a member of 3 events on the free plan. Upgrade to join more events or leave an existing event first.'
      );
      return;
    }

    // Only navigate if allowed
    navigation.navigate('JoinEvent');
  } catch (err) {
    Alert.alert('Something went wrong', 'Please try again.');
  }
};
```

**Updated Join button:**
```typescript
// Before:
<Pressable onPress={() => navigation.navigate('JoinEvent')}>

// After:
<Pressable onPress={onPressJoin}>
```

### 2. en.ts (translations)
**Added new translation key:**
```typescript
limits: {
  freeLimitTitle: 'Upgrade required',
  freeLimitMessage: 'You can create up to 3 events on the free plan. Upgrade to create more.',
  joinLimitMessage: 'You can only be a member of 3 events on the free plan. Upgrade to join more events or leave an existing event first.',
  eventAccessMessage: '...',
}
```

## User Experience

### Before Fix:
1. User has 3 events (at limit)
2. Taps "Join" button
3. ✅ Navigates to JoinEvent screen
4. Enters join code
5. ❌ Error: "free_limit_reached"
6. 😕 Confused - why could I get here if I can't join?

### After Fix:
1. User has 3 events (at limit)
2. Taps "Join" button
3. ⚠️ Alert: "Upgrade required. You can only be a member of 3 events..."
4. ✅ No navigation - stays on Events screen
5. 👍 Clear message about what to do (upgrade or leave event)

## Consistency

Now both buttons have the same behavior:
- ✅ **Create button**: Checks `can_create_event()` before navigation
- ✅ **Join button**: Checks `can_join_event()` before navigation
- ✅ Both show same upgrade alert style
- ✅ Both prevent navigation when at limit
- ✅ Consistent, predictable UX

## Testing

### Test Case 1: Free user at limit
```
Setup:
- Free user with 3 events

Steps:
1. Tap "Join" button

Expected:
- Alert: "Upgrade required..."
- No navigation
- Still on Events screen
```

### Test Case 2: Free user under limit
```
Setup:
- Free user with 2 events

Steps:
1. Tap "Join" button

Expected:
- Navigation to JoinEvent screen
- Can enter join code
```

### Test Case 3: Pro user at limit
```
Setup:
- Pro user with 3+ events

Steps:
1. Tap "Join" button

Expected:
- Navigation to JoinEvent screen (no limit for pro)
```

### Test Case 4: Not authenticated
```
Setup:
- User not logged in (edge case)

Steps:
1. Tap "Join" button

Expected:
- Navigation to Profile screen
```

## Related Functions

All event membership entry points now validate the limit:
- ✅ `join_event()` RPC - validates server-side (line 123 in 006_free_tier_membership_limit.sql)
- ✅ `accept_event_invite()` RPC - validates server-side (our recent fix)
- ✅ `onPressCreate()` UI - validates client-side before navigation
- ✅ `onPressJoin()` UI - validates client-side before navigation ⬅️ NEW

## Files Modified
- ✅ `src/screens/EventListScreen.tsx` (added onPressJoin function, updated button)
- ✅ `src/i18n/locales/en.ts` (added joinLimitMessage translation)

## Notes
- No database changes needed - `can_join_event()` already exists
- No rebuild needed - just reload the app
- Client-side check is UX optimization (server-side validation still happens in RPC)
- Error messages suggest actionable solutions (upgrade or leave event)
