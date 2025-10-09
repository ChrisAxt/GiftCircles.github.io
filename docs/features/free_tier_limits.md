# Free Tier Membership Limit - Complete Implementation

## Overview

The free tier limit has been updated to work based on **total event memberships** instead of just owned events.

## New Behavior

### Free Plan (Non-Pro Users)
- **Maximum 3 total events** (owned + joined combined)
- Can only **access the 3 most recent events** (by join date)
- Older events are **locked** but still visible in the list
- Cannot create new events if already at 3 memberships
- Cannot join new events if already at 3 memberships

### Pro Plan Users
- **Unlimited events** (create and join)
- Can **access all events**
- No restrictions

### Downgrade Scenario
When a Pro user downgrades to Free:
- They keep all their event memberships
- But can only **access the 3 most recent** (by join date)
- Older events show as "locked" in the event list
- Cannot create or join new events until they leave some events

## Changes Made

### Migration 006 (`supabase/migrations/006_free_tier_membership_limit.sql`)

#### 1. Updated `can_create_event(p_user uuid)` function
**Before**: Counted events where `owner_id = p_user`
**After**: Counts rows in `event_members` where `user_id = p_user`

```sql
-- Old logic (migration 003)
else (select count(*) < 3 from public.events where owner_id = p_user)

-- New logic (migration 006)
else (select count(*) < 3 from public.event_members where user_id = p_user)
```

#### 2. Created `can_join_event(p_user uuid)` function
Same logic as `can_create_event` - checks total memberships.

#### 3. Updated `events_for_current_user()` RPC
**New behavior**:
- Ranks event memberships by `created_at DESC` (most recent first)
- Pro users: returns all events with `accessible = true`
- Free users: returns all events, but only first 3 have `accessible = true`
- Locked events (rank > 3) have `accessible = false`

#### 4. Updated `join_event(p_code text)` function
**Added check**: Calls `can_join_event()` before allowing user to join
**Raises exception**: `'free_limit_reached'` if user already has 3 memberships

### Client-Side Changes

#### EventListScreen.tsx (`src/screens/EventListScreen.tsx:385-394`)
- Already handles `accessible` field from `events_for_current_user()` RPC
- Shows "Upgrade required" alert when user taps locked event
- Updated to use translated error message

#### JoinEventScreen.tsx (`src/screens/JoinEventScreen.tsx:18-65`)
- **Added preflight check**: Calls `can_join_event()` RPC before attempting join
- Shows "Upgrade required" alert if limit reached
- Prevents navigation if limit reached
- Added console logging for debugging

#### CreateEventScreen.tsx (`src/screens/CreateEventScreen.tsx:90-138`)
- Already has validation via `create_event_and_admin()` RPC
- Added console logging for debugging

#### Translations (`src/i18n/locales/en.ts`)
- Added `errors.limits.eventAccessMessage` for locked events

## Testing Steps

### Setup: Apply Migration
```bash
# Push migration to database
npx supabase db push
```

Or via SQL Editor in Supabase Dashboard:
1. Copy contents of `supabase/migrations/006_free_tier_membership_limit.sql`
2. Paste and run in SQL Editor

### Test 1: Create Event Limit (3 Total Memberships)

**Initial state**: User has 2 owned events + 1 joined event = 3 total

1. Go to Event List screen
2. Press "Create" button

**Expected**:
- Alert: "Upgrade required - You can create up to 3 events on the free plan..."
- Should NOT navigate to CreateEvent screen
- Console log: `[Events] Free tier limit reached - blocking creation`

### Test 2: Join Event Limit (3 Total Memberships)

**Initial state**: User has 3 total memberships

1. Get a join code from another event
2. Go to Join Event screen
3. Enter the code
4. Press "Join"

**Expected**:
- Alert: "Upgrade required - You can create up to 3 events on the free plan..."
- Should NOT join the event
- Console log: `[JoinEvent] Free tier limit reached - blocking join`

### Test 3: Can Create When Under Limit

**Initial state**: User has 2 total memberships

1. Go to Event List screen
2. Press "Create" button
3. Fill in event details
4. Press "Create"

**Expected**:
- Successfully creates event
- Navigates to EventDetail screen
- Console log: `[CreateEvent] Event created successfully: <event_id>`

### Test 4: Locked Events (Downgrade Scenario)

**Setup**:
1. Set user as pro temporarily:
   ```sql
   UPDATE public.profiles
   SET plan = 'pro'
   WHERE id = '<your_user_id>';
   ```
2. Create or join 5 events
3. Downgrade user:
   ```sql
   UPDATE public.profiles
   SET plan = NULL
   WHERE id = '<your_user_id>';
   ```

**Test**:
1. Restart app (to refresh event list)
2. Go to Event List screen

**Expected**:
- All 5 events visible in list
- First 3 events (most recent by join date) are accessible
- Last 2 events show as locked (visual indication needed in EventCard component)
- Tapping a locked event shows: "You can access up to 3 events on the free plan. This event is locked. Upgrade to access all your events."

### Test 5: Leave Event to Free Up Slot

**Initial state**: User has 3 total memberships, all accessible

1. Go to one of the 3 events
2. Leave the event (need to implement leave functionality)
3. Go back to Event List

**Expected**:
- User now has 2 memberships
- Can create or join a new event
- If they had >3 events, the 4th event becomes accessible

## Verification Queries

```sql
-- Check user's membership count
SELECT count(*) as membership_count
FROM public.event_members
WHERE user_id = '<your_user_id>';

-- Check if user can create/join
SELECT
  public.can_create_event('<your_user_id>') as can_create,
  public.can_join_event('<your_user_id>') as can_join;

-- See which events are accessible
SELECT
  id,
  title,
  accessible
FROM public.events_for_current_user();

-- Check user's memberships ranked by recency
SELECT
  e.title,
  em.created_at as joined_at,
  row_number() over (order by em.created_at desc) as recency_rank
FROM public.event_members em
JOIN public.events e ON e.id = em.event_id
WHERE em.user_id = '<your_user_id>'
ORDER BY em.created_at DESC;
```

## Known Issues / Future Work

### 1. Visual Indication for Locked Events
The `EventCard` component should show a visual indicator (lock icon, opacity, badge) when `accessible = false`.

**Suggested**: Update `EventCard.tsx` to accept an `accessible` prop and show a lock overlay.

### 2. Leave Event Functionality
Currently there's no UI to leave an event. This is needed so free users can free up slots.

**Suggested**: Add "Leave Event" button in EventDetailScreen for non-owners.

### 3. Better Messaging
The error message says "You can create up to 3 events" but should say "You can be a member of up to 3 events".

**Suggested**: Update translation keys:
- `freeLimitMessage` → "You can be a member of up to 3 events on the free plan. Upgrade for unlimited events."

### 4. Edge Case: Admin/Owner Leaving
What happens if a user owns an event that's locked? They can't access it to manage it.

**Suggested**: Always make owned events accessible, even beyond the 3-event limit. Only restrict joined events.

## Summary

✅ Free tier now limits **total memberships** (owned + joined)
✅ Free users can only **access 3 most recent events**
✅ Create button checks limit before navigation
✅ Join screen checks limit before joining
✅ Server-side validation prevents creation/joining beyond limit
✅ Locked events show in list but can't be accessed
✅ All error messages translated via i18n

---

**Created**: 2025-10-02
**Migration**: `006_free_tier_membership_limit.sql`
**Status**: ✅ Ready for testing
