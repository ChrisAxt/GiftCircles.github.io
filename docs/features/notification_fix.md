# Notification Navigation Fix

## Problem Summary
After running `fix_add_list_recipient_error_handling.sql`, you received a push notification when creating a list with a recipient, but:
1. ✅ First notification worked and opened the app
2. ❌ Couldn't see accept/decline buttons
3. ❌ Could only see the list, not the event
4. ❌ Subsequent list creations didn't send notifications

## Root Causes Identified

### 1. Missing Notification Response Listener
The app had push notification registration (`PreferencesCard.tsx`) but **no listener** to handle when users tap notifications. This meant tapping a notification would open the app but do nothing.

### 2. No Navigation Logic
There was no code to navigate to the correct screen based on the notification type and data.

### 3. Missing PendingInvitesCard on EventDetailScreen
The `PendingInvitesCard` component exists and works correctly, but it was never added to the `EventDetailScreen`, so users couldn't see or interact with their pending invites.

## Changes Made

### 1. Created Notification Handler (`src/lib/notifications.ts`)
**New file** that provides:
- `configureNotificationHandler()` - Sets how notifications appear when app is foregrounded
- `setupNotificationResponseListener(navigationRef)` - Listens for notification taps
- `handleNotificationNavigation(navigationRef, data)` - Routes to correct screen based on notification type

Supported notification types:
- `list_for_recipient` → Navigate to Events tab (shows PendingInvitesCard)
- `event_invite` → Navigate to Events tab (shows PendingInvitesCard)
- `item_claimed` → Navigate to ListDetail
- `item_unclaimed` → Navigate to ListDetail
- `event_update` → Navigate to EventDetail
- `list_created` → Navigate to ListDetail
- `purchase_reminder` → Navigate to Claimed tab

### 2. Updated Navigation (`src/navigation/index.tsx`)
Added:
- Import of notification handlers
- `navigationRef` using `useRef<NavigationContainerRef<any>>(null)`
- `useEffect` to configure notification handler on mount
- `useEffect` to set up notification response listener
- Passed `ref={navigationRef}` to `NavigationContainer`

### 3. Added PendingInvitesCard to EventListScreen
The card now appears on the Events tab (home screen) right after the header stats and before the events list, showing:
- Event title
- Inviter name
- Event date
- Accept/Decline buttons

This makes more sense because users need to accept the invite *before* they can access the event.

## How It Works Now

### When a user creates a list with a recipient:

1. **Database Trigger** (`add_list_recipient` function):
   - Adds recipient to `list_recipients` table
   - If recipient is not an event member, calls `send_event_invite()`
   - Creates notification in `notification_queue`:
     ```json
     {
       "type": "list_for_recipient",
       "list_id": "...",
       "event_id": "...",
       "invite_id": "..."
     }
     ```

2. **Edge Function** (`send-push-notifications`):
   - Polls `notification_queue` for unsent notifications
   - Gets user's push tokens from `push_tokens` table
   - Sends via Expo Push API
   - Marks as sent

3. **Mobile App Receives Notification**:
   - Shows banner with title and body
   - User taps notification

4. **Navigation Handler** (`src/lib/notifications.ts`):
   - Reads notification data
   - Sees `type: "list_for_recipient"`
   - Navigates to `Home` screen, `Events` tab

5. **EventListScreen** (Events tab):
   - Loads user's events
   - Renders `PendingInvitesCard` at the top
   - Card fetches pending invites for current user
   - Shows Accept/Decline buttons for each invite

## Testing Instructions

### 1. Verify Notification Queue
```sql
-- Run check_notifications.sql to see recent notifications
SELECT
  id,
  user_id,
  title,
  body,
  data,
  sent,
  created_at
FROM notification_queue
ORDER BY created_at DESC
LIMIT 10;
```

### 2. Manually Trigger Edge Function
```bash
# If using Supabase CLI
supabase functions invoke send-push-notifications

# Or via curl
curl -X POST \
  'https://YOUR_PROJECT.supabase.co/functions/v1/send-push-notifications' \
  -H 'Authorization: Bearer YOUR_ANON_KEY'
```

### 3. Test the Full Flow
1. **Enable notifications** in Profile → Settings → Push notifications: On
2. **Create a test event** (or use existing)
3. **Create a list** and add yourself as recipient (use your own email)
4. **Check notification queue** - should see new entry with `sent: false`
5. **Trigger edge function** manually or wait for cron/trigger
6. **Check notification queue again** - should see `sent: true`
7. **Receive notification** on device
8. **Tap notification** - should navigate to Events tab (home screen)
9. **See PendingInvitesCard** at the top with Accept/Decline buttons
10. **Accept invite** - should add you to event members
11. **Card disappears** and event appears in your events list

### 4. Test Different Notification Types
You can test other notification types by manually inserting into `notification_queue`:

```sql
-- Test event invite notification
INSERT INTO notification_queue (user_id, title, body, data)
VALUES (
  'YOUR_USER_ID',
  'Event Invitation',
  'You were invited to Birthday Party',
  jsonb_build_object(
    'type', 'event_invite',
    'event_id', 'YOUR_EVENT_ID',
    'invite_id', 'YOUR_INVITE_ID'
  )
);
```

## Why Notifications Might Not Send

### Issue: Only first notification worked
**Possible causes:**

1. **Edge function not running** - Check if you have a cron job or database trigger to invoke it
2. **Notifications marked as sent** - Check `notification_queue.sent` column
3. **No push token** - Verify `push_tokens` table has your device token
4. **Expo push service** - Check Expo dashboard for push receipt errors

### Solution: Set up automated edge function invocation

**Option A: Database Trigger (recommended)**
```sql
-- Create a trigger to invoke edge function after insert
CREATE OR REPLACE FUNCTION notify_new_notification()
RETURNS TRIGGER AS $$
BEGIN
  -- Invoke edge function asynchronously
  PERFORM net.http_post(
    url := 'https://YOUR_PROJECT.supabase.co/functions/v1/send-push-notifications',
    headers := jsonb_build_object('Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_send_push_notification
AFTER INSERT ON notification_queue
FOR EACH ROW
EXECUTE FUNCTION notify_new_notification();
```

**Option B: Cron Job**
```sql
-- Run edge function every minute
SELECT cron.schedule(
  'send-push-notifications',
  '* * * * *', -- Every minute
  $$
  SELECT net.http_post(
    url := 'https://YOUR_PROJECT.supabase.co/functions/v1/send-push-notifications',
    headers := jsonb_build_object('Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY')
  ) AS request_id;
  $$
);
```

## Files Modified
- ✅ `src/lib/notifications.ts` (new file - handles notification taps and navigation)
- ✅ `src/navigation/index.tsx` (added notification response listener)
- ✅ `src/screens/EventListScreen.tsx` (added PendingInvitesCard to Events tab)

## Files Already Working
- ✅ `src/components/PendingInvitesCard.tsx` (already existed, works correctly)
- ✅ `src/lib/invites.ts` (accept/decline logic already works)
- ✅ `fix_add_list_recipient_error_handling.sql` (creates notifications correctly)
- ✅ `supabase/functions/send-push-notifications/index.ts` (sends notifications correctly)

## Next Steps
1. Rebuild your app with `npm run android` or `npm run ios`
2. Test the notification flow end-to-end
3. Set up automated edge function invocation (cron or trigger)
4. Monitor `notification_queue` table for any errors
