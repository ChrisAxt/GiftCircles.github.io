# GiftCircles - Changelog

## 2025-10-08 - Theme Fixes, Last Member Permissions & Production Prep

### New Features

#### Last Member Permissions
**Feature:** When a user becomes the last remaining member of an event (everyone else has left), they gain full permissions to edit and delete everything related to that event.

**Implementation:**
- Added `is_last_event_member(event_id, user_id)` database function
- Created UPDATE and DELETE policies for events, lists, items, and list_recipients
- Updated UI in `ListDetailScreen` and `EventDetailScreen` to show delete buttons for last member
- Prevents orphaned events that nobody can manage

**Files:**
- `supabase/migrations/018_add_update_delete_policies.sql` (new)
- `supabase/migrations/019_fix_duplicate_policies.sql` (new - removed conflicting old policies)
- `src/screens/ListDetailScreen.tsx`
- `src/screens/EventDetailScreen.tsx`

**Testing:**
```sql
-- Test: Create event, add second member, second member creates list, first member leaves
-- Result: Second member (now last member) can delete the list they didn't create
```

#### Event Refresh After Invite Acceptance
**Feature:** Events list automatically refreshes when you accept an invitation, showing the new event immediately.

**Implementation:**
- Added `onInviteAccepted` callback prop to `PendingInvitesCard`
- Callback triggers `EventListScreen.load()` after successful invite acceptance
- No manual refresh needed

**Files:**
- `src/components/PendingInvitesCard.tsx`
- `src/screens/EventListScreen.tsx`

### Bug Fixes

#### 1. Theme Support in PendingInvitesCard
**Problem:** Invite card used hardcoded colors (white text on white background in light mode).

**Solution:**
- Added `useTheme` hook from `@react-navigation/native`
- Replaced all hardcoded colors with theme-aware colors:
  - `colors.card` for card background
  - `colors.text` for text
  - `colors.primary` for accent colors
  - `colors.border` for borders

**Files:**
- `src/components/PendingInvitesCard.tsx`

#### 2. Invite Card Flash on Navigation
**Problem:** Card briefly showed "Loading invites..." every time user navigated to Events tab, even with no invites.

**Solution:**
- Changed initial `loading` state from `true` to `false`
- Removed loading UI completely
- Card only renders when `invites.length > 0`

**Files:**
- `src/components/PendingInvitesCard.tsx`

#### 3. Theme Support in AuthScreen
**Problem:** Text inputs had white text on white background in light mode (invisible).

**Solution:**
- Added `useTheme` hook
- Added color properties to all `TextInput` components:
  - `color`: text color
  - `placeholderTextColor`: placeholder with opacity
  - `borderColor`: border color
  - `backgroundColor`: input background

**Files:**
- `src/screens/AuthScreen.tsx`

#### 4. iOS Status Bar Configuration Error
**Problem:** Error on iOS: "RCTStatusBarManager module requires UIViewControllerBasedStatusBarAppearance key to be NO"

**Solution:**
- Changed `app.json` iOS configuration:
  ```json
  "ios": {
    "infoPlist": {
      "UIViewControllerBasedStatusBarAppearance": false
    }
  }
  ```

**Files:**
- `app.json`

### Production Preparation

#### App Configuration
**Updates to app.json:**
- Added `buildNumber: "1"` for iOS (required for App Store)
- Added `versionCode: 1` for Android (required for Play Store)
- Added adaptive icon configuration for Android:
  ```json
  "adaptiveIcon": {
    "foregroundImage": "./assets/adaptive-icon.png",
    "backgroundColor": "#21c36b"
  }
  ```
- Fixed iOS status bar configuration

**Files:**
- `app.json`

#### TypeScript Configuration Fix
**Problem:** Syntax error with Expo's TypeScript config.

**Solution:**
- Simplified `tsconfig.json` to only override necessary settings
- Extended `expo/tsconfig.base` to avoid conflicts
- Removed conflicting module resolution settings

**Files:**
- `tsconfig.json`

#### Production-Safe Logger
**Created:** Utility for production-safe logging that disables console.log in production but keeps error logging.

**Usage:**
```typescript
import { logger } from '@/lib/logger';

logger.log('Debug info');  // Only in development
logger.error('Error!');    // Always logged
logger.warn('Warning');    // Only in development
```

**Files:**
- `src/lib/logger.ts` (new)

#### Legal Documents
**Created:** Draft privacy policy and terms of service for app store submissions.

**Files:**
- `docs/legal/privacy-policy.md` (new)
- `docs/legal/terms-of-service.md` (new)

**Next Steps:**
1. Customize with your information (email, jurisdiction, etc.)
2. Host online (GitHub Pages recommended)
3. Add URLs to app.json and store listings

### Verification & Testing

#### Notification System Verification
**Created:** Scripts to verify and test push notification triggers for lists, items, and claims.

**Scripts:**
- `scripts/check_notification_triggers.sql` - Verify triggers are active
- `scripts/test_notifications.sql` - Manually test notification flow

**Verification Results:**
- ✅ All notification triggers exist in migration 012
- ✅ `notify_new_list()` - Triggers on list INSERT
- ✅ `notify_new_item()` - Triggers on item INSERT
- ✅ `notify_new_claim()` - Triggers on claim INSERT
- ✅ Notifications queue in database
- ✅ Edge function sends push notifications via cron (every minute)

**Files:**
- `scripts/check_notification_triggers.sql` (new)
- `scripts/test_notifications.sql` (new)

**Usage:**
```bash
# Check if triggers are active
psql "$SUPABASE_DB_URL" -f scripts/check_notification_triggers.sql

# Test notification flow
psql "$SUPABASE_DB_URL" -f scripts/test_notifications.sql
```

#### Purchase Reminder Testing
**Added:** Documentation and commands for manually triggering purchase reminder notifications.

**Commands:**
```sql
-- Trigger reminders for all events
SELECT public.trigger_purchase_reminders();

-- Check queued reminders
SELECT * FROM public.notification_queue
WHERE data->>'type' = 'purchase_reminder'
ORDER BY created_at DESC;
```

### Migration Instructions

1. **Apply new database migrations:**
   ```bash
   # Migration 018: Last member permissions
   psql "$SUPABASE_DB_URL" -f supabase/migrations/018_add_update_delete_policies.sql

   # Migration 019: Remove conflicting policies
   psql "$SUPABASE_DB_URL" -f supabase/migrations/019_fix_duplicate_policies.sql
   ```

2. **Update app.json and rebuild:**
   ```bash
   # Changes to app.json require a rebuild
   npm run android
   # or
   npm run ios
   ```

3. **Test the fixes:**
   - Theme: Toggle between light/dark mode, verify all screens
   - Last member: Leave event, verify remaining member can delete lists/items
   - Invite refresh: Accept invite, verify event appears immediately
   - Notifications: Run verification scripts

### Breaking Changes
None - all changes are backward compatible.

### Known Issues
- iOS splash screen requires production build to display custom splash
- 6 database tests still failing (non-critical, documented in TEST_FAILURES_TODO.md)

### Files Changed Summary

**New Files:**
- `supabase/migrations/018_add_update_delete_policies.sql`
- `supabase/migrations/019_fix_duplicate_policies.sql`
- `src/lib/logger.ts`
- `docs/legal/privacy-policy.md`
- `docs/legal/terms-of-service.md`
- `scripts/check_notification_triggers.sql`
- `scripts/test_notifications.sql`

**Modified Files:**
- `app.json` - Build numbers, adaptive icon, iOS status bar
- `tsconfig.json` - Simplified configuration
- `src/components/PendingInvitesCard.tsx` - Theme support, flash fix, refresh callback
- `src/screens/AuthScreen.tsx` - Theme support
- `src/screens/ListDetailScreen.tsx` - Last member permissions
- `src/screens/EventDetailScreen.tsx` - Last member permissions
- `src/screens/EventListScreen.tsx` - Invite refresh callback
- `docs/development/PRODUCTION_RELEASE_CHECKLIST.md` - Updated with completed items

---

## 2025-10-06 - Notification & Invite System Fixes

### Bug Fixes

#### 1. Notification Navigation
**Problem:** Tapping push notifications opened the app but didn't navigate to the correct screen or show pending invites.

**Solution:**
- Added notification response listener (`src/lib/notifications.ts`)
- Added navigation handling for all notification types
- Moved `PendingInvitesCard` to Events tab (home screen) where it makes sense
- Added automatic reload when app comes to foreground or screen focuses

**Files:**
- `src/lib/notifications.ts` (new)
- `src/navigation/index.tsx`
- `src/screens/EventListScreen.tsx`
- `src/components/PendingInvitesCard.tsx`

#### 2. Free Tier Invite Limit Bug
**Problem:** Free users with 3 events could accept invites, creating an inaccessible 4th event.

**Solution:**
- Added `can_join_event()` check to `accept_event_invite()` function
- Shows clear error message when limit is reached
- Prevents database inconsistency

**Files:**
- `supabase/migrations/017_consolidated_fixes.sql`
- `src/components/PendingInvitesCard.tsx`

#### 3. Join Button Limit Check
**Problem:** Join button allowed navigation to JoinEvent screen even at free tier limit.

**Solution:**
- Added `onPressJoin()` function with limit validation
- Shows upgrade alert before navigation (consistent with Create button)
- Better UX - users know immediately they're at limit

**Files:**
- `src/screens/EventListScreen.tsx`
- `src/i18n/locales/en.ts`

#### 4. List Recipient Authorization
**Problem:** `add_list_recipient` function had authorization issues and silent failures.

**Solution:**
- Better auth checks (list creator OR event member)
- Proper error handling with warnings
- Integration with notification queue
- Validates email format

**Files:**
- `supabase/migrations/017_consolidated_fixes.sql`

#### 5. Notification Queue RLS
**Problem:** Overly restrictive RLS policies on notification_queue table.

**Solution:**
- Users can view their own notifications
- System functions can insert/update notifications
- Edge functions can mark notifications as sent

**Files:**
- `supabase/migrations/017_consolidated_fixes.sql`

### Migration Instructions

1. **Run the consolidated migration:**
   ```sql
   -- In Supabase SQL Editor, run:
   supabase/migrations/017_consolidated_fixes.sql
   ```

2. **Reload the mobile app** (no rebuild needed):
   ```bash
   # Shake device → Reload
   # Or press 'r' in Metro bundler
   ```

3. **Test the fixes:**
   - Create a list with yourself as recipient
   - Receive notification
   - Tap notification → should navigate to Events tab
   - See PendingInvitesCard with Accept/Decline buttons
   - Test free tier limits (Create, Join, Accept invite at 3 events)

### Breaking Changes
None - all changes are backward compatible.

### Known Issues
None currently.

### Technical Details

#### Database Functions Updated:
- `add_list_recipient()` - Better auth, error handling, notifications
- `accept_event_invite()` - Added free tier limit check

#### New Features:
- Notification tap handling with deep linking
- AppState listener for automatic reload
- Consistent free tier limit checks across all entry points

#### Entry Points with Limit Validation:
- ✅ `join_event()` RPC (server-side)
- ✅ `accept_event_invite()` RPC (server-side) - NEW
- ✅ Create button (client-side UX)
- ✅ Join button (client-side UX) - NEW

### Files Cleaned Up
Removed temporary fix/test files:
- All `check_*.sql`, `debug_*.sql`, `fix_*.sql`, `test_*.sql` files
- Consolidated into single migration: `017_consolidated_fixes.sql`

### Documentation
- `CHANGELOG.md` - This file (consolidated overview)
- `NOTIFICATION_FIX.md` - Detailed notification system docs
- `FREE_TIER_INVITE_BUG_FIX.md` - Free tier limit fix details
- `JOIN_BUTTON_LIMIT_CHECK.md` - Join button validation docs
- `test_notification_flow.md` - Testing guide

---

## Future Enhancements
- Show event count indicator (e.g., "2/3 events") in UI
- Queue invites with reminder when user drops below limit
- Allow choosing which event to leave before accepting invite
- Auto-trigger edge function via database trigger or cron
