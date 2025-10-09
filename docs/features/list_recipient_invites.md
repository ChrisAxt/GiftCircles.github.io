# List Recipient Auto-Invite System

## Problem Solved

When creating a gift list for someone who is not yet a member of the event, they now get automatically invited. This replaces the need for the "Other" option when the recipient is a real person who just isn't in the event yet.

## How It Works

### Scenario 1: Recipient has the app (registered user)
1. You create a list for `john@example.com`
2. System checks if John is in the event → No
3. System automatically sends event invite to `john@example.com`
4. John receives **2 push notifications**:
   - "Event Invitation" - You've been invited to [Event Name]
   - "Gift List Created" - [Your Name] created a gift list for you
5. John opens app, accepts invite, joins event
6. John can now see his gift list

### Scenario 2: Recipient doesn't have the app (not registered)
1. You create a list for `mary@example.com`
2. System stores the email and creates pending invite
3. Later, Mary downloads the app and signs up with `mary@example.com`
4. System automatically:
   - Links her to the pending invite
   - Links her as the list recipient
   - Sends her the notifications
5. Mary sees the event invite and gift list immediately

### Scenario 3: Recipient is already in the event
1. You create a list for `sarah@example.com`
2. System checks if Sarah is in the event → Yes
3. No invite needed, just adds her as list recipient
4. Sarah can see the list (based on visibility settings)

## Database Changes

### `list_recipients` Table Updates
- **New column**: `recipient_email` (text)
- **Changed**: `user_id` is now nullable
- **Constraint**: Must have either `user_id` OR `recipient_email` (not both, not neither)

### New Functions

**`add_list_recipient(list_id, recipient_email)`**
- Adds recipient to list
- Auto-invites to event if not a member
- Sends notification if registered
- Returns `user_id` (if registered) or `null`

**`get_list_recipients(list_id)`**
- Returns all recipients with status info
- Shows registration status, event membership, etc.

**`link_list_recipients_on_signup()`**
- Trigger function
- Runs when new user signs up
- Auto-links pending recipients to new user

**Updated: `create_list_with_people()`**
- Now accepts `recipient_emails` parameter
- Automatically invites email recipients

## Frontend Usage

### Create list with email recipient:

```typescript
import { createListWithRecipients } from '../lib/listRecipients';

// Create list for someone not in the event
await createListWithRecipients(
  eventId,
  "John's Birthday Gifts",
  'shared',
  null,
  [], // No user IDs
  ['john@example.com'], // Email recipient (auto-invited)
  [], // No viewers
  [] // No exclusions
);
```

### Add recipient to existing list:

```typescript
import { addListRecipient } from '../lib/listRecipients';

await addListRecipient(listId, 'mary@example.com');
// Automatically sends event invite if Mary isn't a member
```

### Get recipient info:

```typescript
import { getListRecipients } from '../lib/listRecipients';

const recipients = await getListRecipients(listId);
// Returns array with:
// - user_id (null if not registered)
// - recipient_email
// - display_name
// - is_registered (boolean)
// - is_event_member (boolean)
```

## UI Recommendations

### When creating a list:

1. **Recipient Selection**:
   - Show event members first
   - Add option: "Invite someone by email"
   - Email input with validation
   - Show badge: "Will be invited to event"

2. **After adding email recipient**:
   - Show success message: "List created! [Email] will be invited to the event"
   - Show recipient status: "Invite pending" or "Not registered yet"

3. **Recipient list display**:
   ```
   Recipients:
   - John Doe (Member) ✓
   - mary@example.com (Invited) 📧
   - sarah@example.com (Pending signup) ⏳
   ```

## Notification Types

### Type 1: Event Invite
```json
{
  "title": "Event Invitation",
  "body": "[Name] invited you to [Event]",
  "data": {
    "type": "event_invite",
    "invite_id": "uuid",
    "event_id": "uuid"
  }
}
```

### Type 2: List for Recipient
```json
{
  "title": "Gift List Created",
  "body": "[Name] created a gift list for you in [Event]",
  "data": {
    "type": "list_for_recipient",
    "list_id": "uuid",
    "event_id": "uuid",
    "invite_id": "uuid"
  }
}
```

## Testing

Run the smoke test:
```sql
-- In Supabase SQL Editor
-- Run the QUICK SMOKE TEST section from test_list_recipient_invites.sql
```

This will:
1. Add an email recipient to your first list
2. Verify event invite was created
3. Clean up test data
4. Report SUCCESS or error

## Security

- Only list creators can add recipients
- Email validation prevents invalid addresses
- Duplicate invites are prevented
- RLS policies protect all data
- Recipients can see their own lists (when registered)

## Edge Cases Handled

✅ Duplicate recipients (same email added twice)
✅ User already in event (no duplicate invite)
✅ Invalid email format (error thrown)
✅ User signs up later (auto-linked)
✅ Multiple lists for same person (all get linked)
✅ Case-insensitive email matching

## Migration Steps

1. Apply migration 016:
   ```bash
   # Execute in Supabase SQL Editor
   # Or: npx supabase db push
   ```

2. Update your CreateListScreen to:
   - Accept email input for recipients
   - Show "invite" status for non-members
   - Use new `createListWithRecipients()` function

3. Handle new notification type:
   - `list_for_recipient` - navigate to list detail

## Example Flow

```typescript
// User creates list for non-member
const listId = await createListWithRecipients(
  eventId,
  "Sarah's Wedding Registry",
  'shared',
  null,
  [], // No member recipients
  ['sarah@example.com'], // Email recipient
  [],
  []
);

// System automatically:
// 1. Creates the list ✓
// 2. Adds sarah@example.com as recipient ✓
// 3. Sends event invite to sarah@example.com ✓
// 4. If Sarah is registered, sends notification ✓

// When Sarah signs up:
// 1. Auto-links her user_id to the recipient ✓
// 2. Sends her both notifications ✓
// 3. She can accept invite and see her list ✓
```

## Benefits

- ✅ No more "Other" option for real people
- ✅ Seamless onboarding for new users
- ✅ Automatic invite management
- ✅ Better user experience
- ✅ Handles registered and unregistered users
- ✅ Works with existing event invite system
