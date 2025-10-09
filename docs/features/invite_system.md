# Event Invite System

## Overview

The invite system allows users to invite others to events via email. When inviting someone:

1. If the invitee is already registered, they receive a push notification
2. If they register later with that email, they automatically get linked to pending invites
3. Invitees can accept or decline invites from the app
4. When accepted, they become event members

## Database Schema

### `event_invites` Table

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| event_id | uuid | Event being invited to |
| inviter_id | uuid | User who sent the invite |
| invitee_email | text | Email address of invitee |
| invitee_id | uuid | User ID (if registered) |
| status | text | 'pending', 'accepted', or 'declined' |
| invited_at | timestamp | When invite was sent |
| responded_at | timestamp | When invite was accepted/declined |

### Functions

**`send_event_invite(p_event_id, p_invitee_email)`**
- Sends an invite to an email address
- Validates the inviter is an event member
- Checks if user is already a member
- Queues push notification if invitee is registered
- Returns invite_id

**`accept_event_invite(p_invite_id)`**
- Accepts an invite
- Adds user to event as 'giver'
- Updates invite status to 'accepted'

**`decline_event_invite(p_invite_id)`**
- Declines an invite
- Updates invite status to 'declined'

**`get_my_pending_invites()`**
- Returns all pending invites for current user
- Includes event details and inviter name

**`cleanup_old_invites()`**
- Deletes accepted/declined invites older than 30 days
- Can be scheduled as a cron job

### Triggers

**`update_invites_on_user_signup`**
- Runs when a new user signs up
- Links pending invites to the new user
- Sends push notifications for all pending invites

## Frontend Components

### `PendingInvitesCard.tsx`
Displays pending invites with accept/decline buttons.

**Usage:**
```tsx
import { PendingInvitesCard } from '../components/PendingInvitesCard';

// In your HomeScreen or similar
<PendingInvitesCard />
```

### `InviteUserModal.tsx`
Modal for sending invites by email.

**Usage:**
```tsx
import { InviteUserModal } from '../components/InviteUserModal';

const [showInviteModal, setShowInviteModal] = useState(false);

<InviteUserModal
  visible={showInviteModal}
  eventId={event.id}
  eventTitle={event.title}
  onClose={() => setShowInviteModal(false)}
  onInviteSent={() => {
    // Optional: refresh invite list
  }}
/>
```

## API Functions

### `src/lib/invites.ts`

```typescript
// Send invite
await sendEventInvite(eventId, 'user@example.com');

// Get pending invites
const invites = await getMyPendingInvites();

// Accept invite
await acceptEventInvite(inviteId);

// Decline invite
await declineEventInvite(inviteId);

// Get all invites for an event (organizers)
const eventInvites = await getEventInvites(eventId);

// Cancel an invite
await cancelEventInvite(inviteId);

// Subscribe to realtime invite updates
const subscription = subscribeToInvites(userId, (invite) => {
  console.log('New invite received:', invite);
});
```

## Push Notifications

When an invite is sent to a registered user, a push notification is queued with:

**Notification payload:**
```json
{
  "title": "Event Invitation",
  "body": "[Inviter Name] invited you to [Event Title]",
  "data": {
    "type": "event_invite",
    "invite_id": "uuid",
    "event_id": "uuid"
  }
}
```

## Integration Steps

### 1. Apply Migration
```bash
# Run the migration
npx supabase db push
```

Or execute `015_event_invites.sql` in your SQL editor.

### 2. Add to Event Detail Screen

```tsx
import { InviteUserModal } from '../components/InviteUserModal';

// Add button to invite users
<TouchableOpacity onPress={() => setShowInviteModal(true)}>
  <Text>Invite People</Text>
</TouchableOpacity>

<InviteUserModal
  visible={showInviteModal}
  eventId={event.id}
  eventTitle={event.title}
  onClose={() => setShowInviteModal(false)}
/>
```

### 3. Add to Home/Dashboard Screen

```tsx
import { PendingInvitesCard } from '../components/PendingInvitesCard';

// Display pending invites
<PendingInvitesCard />
```

### 4. Handle Push Notification Taps

When user taps a push notification with `type: 'event_invite'`:

```tsx
// Navigate to invites screen or directly accept/decline
if (notification.data.type === 'event_invite') {
  // Option 1: Navigate to invites list
  navigation.navigate('Invites');

  // Option 2: Show accept/decline dialog
  showInviteDialog(notification.data.invite_id);
}
```

## Security

- Only event members can send invites
- Only the invitee can accept/decline their own invites
- Inviter or event admins can cancel invites
- Email validation prevents invalid addresses
- Duplicate invites for same email/event are prevented
- RLS policies protect all operations

## Optional: Add Cleanup Cron Job

To automatically clean up old invites, add to your cron jobs:

```sql
select cron.schedule(
  'cleanup-old-invites',
  '0 4 * * *',  -- Daily at 4 AM
  $$SELECT public.cleanup_old_invites();$$
);
```

## Future Enhancements

- Bulk invites (multiple emails at once)
- Invite via SMS/phone number
- Email templates for non-registered users
- Invite expiration dates
- Resend invite functionality
- Track invite click/open rates
