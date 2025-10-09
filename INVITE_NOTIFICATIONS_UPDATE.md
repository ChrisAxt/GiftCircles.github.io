# Event Invite System Update

## Summary

Updated the event invite system to send **both email and push notifications** when inviting users to events.

## Changes Made

### 1. Database Migration (`025_event_invites_send_emails.sql`)

Updated the `send_event_invite` function to:
- **Always send an email invitation** to the invitee (whether they have an account or not)
- **If the user has an account AND push tokens registered**: Also send a push notification
- This provides redundancy - email as the primary/backup, push notification for instant delivery

Updated the `update_invites_on_user_signup` trigger to:
- Send emails to new users who have pending invites
- Queue push notifications for new users with push tokens

### 2. Frontend Update (`EventDetailScreen.tsx`)

Replaced the old inline invite modal with the `InviteUserModal` component:
- Removed old email-only invite code
- Uses the new `sendEventInvite` function that triggers both email and push notifications
- Cleaner code with reusable component

### 3. Configuration (`026_configure_app_settings.sql`)

Set up database configuration for the edge function URLs and API keys.

## How It Works

When a user invites someone to an event:

1. **User clicks "Share" button** in EventDetailScreen
2. **InviteUserModal opens** where they enter an email address
3. **sendEventInvite() is called** which:
   - Creates/updates the invite in the database
   - **Sends an email** to the invitee with the event details and join link
   - **If the invitee has an account**: Also queues a push notification
4. **Within 1 minute**, the cron job processes the push notification queue
5. **Invitee receives**:
   - Email (always)
   - Push notification (if they have the app installed and notifications enabled)

## Benefits

- **Redundancy**: Email serves as a reliable fallback if push notifications fail
- **Better UX**: Registered users get instant notifications via push
- **Works for everyone**: Unregistered users still get the email invitation
- **No missed invites**: Even if push notifications don't work, email ensures delivery

## Testing

To test the full flow:

1. **Invite a registered user** (someone who has the app installed):
   - They should receive an email
   - They should receive a push notification
   - Tapping the notification should navigate to the Events tab

2. **Invite an unregistered user** (someone without an account):
   - They should receive an email
   - No push notification (they don't have the app)

3. **Invite someone who signed up before** but was invited:
   - The signup trigger sends them both email and push notification

## Database Functions Modified

- `send_event_invite()` - Now sends both email and push notifications
- `update_invites_on_user_signup()` - Now sends both email and push notifications for pending invites

## Files Changed

- `supabase/migrations/025_event_invites_send_emails.sql` - Updated database functions
- `supabase/migrations/026_configure_app_settings.sql` - Database configuration
- `src/screens/EventDetailScreen.tsx` - Use new invite modal component
