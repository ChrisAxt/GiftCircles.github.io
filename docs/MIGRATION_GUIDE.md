# GiftCircles - Migration Guide

## Latest Migration (2025-10-08)
**Migrations 018-019: Last Member Permissions & Theme Fixes**

### Quick Apply

```bash
# Connect to your database
export SUPABASE_DB_URL="postgresql://..."

# Apply migrations 018 and 019
psql "$SUPABASE_DB_URL" -f supabase/migrations/018_add_update_delete_policies.sql
psql "$SUPABASE_DB_URL" -f supabase/migrations/019_fix_duplicate_policies.sql

# Verify policies were created
psql "$SUPABASE_DB_URL" -c "SELECT tablename, policyname FROM pg_policies WHERE policyname LIKE '%last member%' ORDER BY tablename;"
```

### What These Migrations Do

**Migration 018:**
- Creates `is_last_event_member(event_id, user_id)` function
- Adds UPDATE and DELETE policies for events, lists, items, list_recipients
- Allows last remaining member to manage all event content

**Migration 019:**
- Removes old conflicting policies that blocked last member access
- Ensures new permissive policies work correctly

**Impact:** Last remaining member can now edit/delete everything in the event, preventing orphaned events.

**Documentation:** See [last_member_permissions.md](./features/last_member_permissions.md)

### App Rebuild Required

Changes to `app.json` require a rebuild:
```bash
npm run android
# or
npm run ios
```

**Changes:**
- ✅ Build numbers added (iOS/Android)
- ✅ Adaptive icon config added (Android)
- ✅ iOS status bar config fixed
- ✅ Theme support added to PendingInvitesCard and AuthScreen

---

## Previous Migration (2025-10-06)
**Migration 017: Notification & Invite System Fixes**

## Quick Start

### 1. Run the Database Migration
```bash
# Option A: Via Supabase Dashboard
# 1. Go to SQL Editor
# 2. Open supabase/migrations/017_consolidated_fixes.sql
# 3. Run it

# Option B: Via Supabase CLI
supabase db push
```

### 2. Reload the Mobile App
```bash
# No rebuild needed! Just reload:
# - Shake device → Reload
# - Or press 'r' in Metro bundler
```

### 3. Test
- Create a list with yourself as recipient
- Receive and tap notification
- Should navigate to Events tab showing pending invite
- Accept invite (test free tier limit if you have 3 events)

## What Was Fixed

### 🔔 Notification Navigation
**Before:** Tapping notifications did nothing
**After:** Opens app and navigates to Events tab with pending invites visible

### 🎟️ Free Tier Invite Bug
**Before:** Could accept 4th invite creating inaccessible event
**After:** Shows "Upgrade required" when at limit

### 🚪 Join Button Validation
**Before:** Could navigate to Join screen even at limit
**After:** Shows alert immediately, consistent with Create button

### ✉️ List Recipient Auth
**Before:** Authorization errors when adding recipients
**After:** Proper auth checks for list creator OR event member

### 🔒 Notification Queue RLS
**Before:** Couldn't query own notifications
**After:** Users can view their notifications

## Migration Contents

The consolidated migration (`017_consolidated_fixes.sql`) includes:

1. **`add_list_recipient()` update**
   - Better authorization (list creator OR event member)
   - Email validation
   - Error handling with warnings
   - Notification queue integration

2. **`accept_event_invite()` update**
   - Free tier limit check via `can_join_event()`
   - Raises `free_limit_reached` exception
   - Prevents database inconsistency

3. **`notification_queue` RLS policies**
   - SELECT: Users can view their own notifications
   - INSERT: System functions can insert
   - UPDATE: System/edge functions can update

## Rollback Plan

If you need to rollback:

```sql
-- Restore original add_list_recipient (without notification integration)
-- Check supabase/migrations/016_list_recipient_invites_v2.sql for original

-- Restore original accept_event_invite (without limit check)
-- Check supabase/migrations/015_event_invites.sql for original

-- Note: RLS changes should be safe to keep
```

## Verification Queries

```sql
-- 1. Check if functions updated correctly
SELECT routine_name, last_altered
FROM information_schema.routines
WHERE routine_name IN ('add_list_recipient', 'accept_event_invite')
  AND routine_schema = 'public';

-- 2. Test free tier limit check
SELECT can_join_event(auth.uid()) as can_join;

-- 3. Check notification queue access
SELECT COUNT(*) FROM notification_queue WHERE user_id = auth.uid();

-- 4. Test add_list_recipient (replace with your IDs)
SELECT add_list_recipient(
  'YOUR_LIST_ID'::uuid,
  'test@example.com'
);
```

## Common Issues

### Issue: "free_limit_reached" error when accepting invite
**Expected behavior** - You have 3 events already (free tier limit)
**Solution:** Upgrade to pro or leave an existing event first

### Issue: Notification received but tap does nothing
**Check:**
1. App was reloaded after code changes
2. Console shows: `[Notification] Setting up notification response listener`
3. When tapping: `[Notification] ===== NOTIFICATION TAPPED =====`

### Issue: Can't see pending invites after accepting
**Expected behavior** - Invites disappear after accepting
**Check:** You're now a member of the event (should appear in events list)

## Files Modified

### Database:
- `supabase/migrations/017_consolidated_fixes.sql` ⭐ **NEW**

### Frontend:
- `src/lib/notifications.ts` (new file)
- `src/navigation/index.tsx`
- `src/screens/EventListScreen.tsx`
- `src/components/PendingInvitesCard.tsx`
- `src/i18n/locales/en.ts`

### Documentation:
- `CHANGELOG.md` (new)
- `MIGRATION_GUIDE.md` (this file)
- `NOTIFICATION_FIX.md` (detailed technical docs)
- `FREE_TIER_INVITE_BUG_FIX.md` (free tier fix details)
- `JOIN_BUTTON_LIMIT_CHECK.md` (join button validation)
- `test_notification_flow.md` (testing guide)

### Cleaned Up:
- ❌ All temporary `fix_*.sql` files (consolidated into migration)
- ❌ All test/debug `*.sql` files
- ❌ Redundant documentation files

## Support

If you encounter issues:

1. **Check console logs** for `[Notification]` and `[PendingInvitesCard]` messages
2. **Verify migration ran** with verification queries above
3. **Review detailed docs:**
   - Notification issues → `NOTIFICATION_FIX.md`
   - Free tier issues → `FREE_TIER_INVITE_BUG_FIX.md`
   - Testing → `test_notification_flow.md`

## Next Steps

After migration is verified:
1. ✅ Test notification flow end-to-end
2. ✅ Test free tier limits (create, join, accept at 3 events)
3. ✅ Monitor for any errors in production
4. 🔮 Consider future enhancements (see CHANGELOG.md)
