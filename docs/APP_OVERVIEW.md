# GiftCircles - Complete Application Overview

## 🎁 What is GiftCircles?

GiftCircles is a collaborative gift list management app that solves the age-old problem: *"What do you want for your birthday/holiday/wedding?"*

Instead of creating wishlists on multiple platforms or sharing spreadsheets, GiftCircles lets groups create **events** where members can:
- Create gift lists for themselves or others
- Browse what people want
- Secretly claim items to purchase
- Keep surprises secret (recipients can't see who claimed what)

---

## 🏗️ Architecture

### Tech Stack

**Frontend:**
- **React Native** (Expo) - Cross-platform mobile app (iOS/Android)
- **TypeScript** - Type safety throughout
- **React Navigation** - Tab + Stack navigation
- **i18n** - Multi-language support (12 languages)

**Backend:**
- **Supabase** - Backend-as-a-Service
  - PostgreSQL database with Row Level Security (RLS)
  - Built-in authentication
  - Edge Functions (Deno)
  - Realtime subscriptions
- **Expo Push Notifications** - Push notification delivery

**Infrastructure:**
- **Expo EAS** - Build and deployment
- **Supabase Cloud** - Hosted database and functions

---

## 📱 App Flow

### 1. Authentication
```
User Flow:
1. Sign up with email/password
2. Create profile (display name)
3. Optional: Enable push notifications
4. Land on Events screen (home)
```

**Technical:**
- Uses Supabase Auth
- Password-based (no OAuth yet)
- Profile auto-created via database trigger
- Push tokens stored in `push_tokens` table

### 2. Events
```
User Flow:
1. Create Event (e.g., "Christmas 2025")
   - Title, date, optional location
   - Auto-generates join code (e.g., "ABC123")

2. Invite Members
   - Share join code directly
   - OR send email invite

3. Join Event
   - Enter join code
   - OR accept email invite
   - Become "giver" member

4. View Event
   - See all members
   - See all lists (except items on your own list)
   - Create lists for yourself or others
```

**Technical:**
- Events stored in `events` table
- Members in `event_members` table (role: admin/giver/recipient)
- Join code is 6-character uppercase string
- Free tier: max 3 event memberships
- RLS: members can view events they belong to

### 3. Gift Lists
```
User Flow:
1. Create List (within an event)
   - Name: "John's Birthday Wishlist"
   - Add recipients (event members or email addresses)

2. Add Items
   - Name, description, price, URL, image
   - Items appear on the list

3. View Lists
   - See all lists in the event
   - Browse items
   - Claim items you want to buy

4. Claim Items
   - Tap "Claim" on any item
   - Mark as purchased when bought
   - Optional: add notes for yourself
```

**Technical:**
- Lists in `lists` table
- Recipients in `list_recipients` table (user_id OR email)
- Items in `items` table
- Claims in `claims` table
- RLS: Recipients can't see claims on their own lists
- Realtime updates via Supabase subscriptions

### 4. Invitations System
```
User Flow:
1. Someone creates a list with you as recipient
   - If you're not an event member, you get invited

2. You receive push notification
   - "Gift List Created: John created a gift list for you in Christmas 2025"

3. Tap notification
   - Opens app to Events tab
   - See PendingInvitesCard at top

4. Accept or Decline
   - Accept: Join event as member, see list
   - Decline: Invitation removed

5. Free Tier Limits Apply
   - Can't accept if already in 3 events
   - Shows "Upgrade required" message
```

**Technical:**
- Invites in `event_invites` table
- Notifications in `notification_queue` table
- `add_list_recipient()` auto-creates invite if not member
- `accept_event_invite()` validates free tier limit
- Edge function sends push notifications
- Frontend handles notification navigation

---

## 🗄️ Database Schema

### Core Tables

**events**
```sql
- id (uuid, PK)
- title (text)
- event_date (date)
- join_code (text, unique)
- created_at (timestamp)
```

**event_members**
```sql
- event_id (uuid, FK → events)
- user_id (uuid, FK → auth.users)
- role (text: 'admin' | 'giver' | 'recipient')
- created_at (timestamp)
- UNIQUE(event_id, user_id)
```

**lists**
```sql
- id (uuid, PK)
- event_id (uuid, FK → events)
- name (text)
- created_by (uuid, FK → auth.users)
- custom_recipient_name (text, optional)
- created_at (timestamp)
```

**list_recipients**
```sql
- id (uuid, PK)
- list_id (uuid, FK → lists)
- user_id (uuid, FK → auth.users, nullable)
- recipient_email (text, nullable)
- created_at (timestamp)
```

**items**
```sql
- id (uuid, PK)
- list_id (uuid, FK → lists)
- name (text)
- description (text)
- price (numeric)
- url (text)
- image_url (text)
- created_at (timestamp)
```

**claims**
```sql
- id (uuid, PK)
- item_id (uuid, FK → items)
- user_id (uuid, FK → auth.users)
- purchased (boolean, default false)
- notes (text)
- created_at (timestamp)
- UNIQUE(item_id) -- one claim per item
```

**event_invites**
```sql
- id (uuid, PK)
- event_id (uuid, FK → events)
- inviter_id (uuid, FK → auth.users)
- invitee_email (text)
- invitee_id (uuid, FK → auth.users, nullable)
- status (text: 'pending' | 'accepted' | 'declined')
- invited_at (timestamp)
- responded_at (timestamp)
- UNIQUE(event_id, invitee_email)
```

**notification_queue**
```sql
- id (uuid, PK)
- user_id (uuid, FK → auth.users)
- title (text)
- body (text)
- data (jsonb) -- notification type, IDs, etc.
- sent (boolean, default false)
- created_at (timestamp)
```

**push_tokens**
```sql
- id (uuid, PK)
- user_id (uuid, FK → auth.users)
- token (text, unique)
- platform (text: 'ios' | 'android')
- created_at (timestamp)
```

**profiles**
```sql
- id (uuid, PK, FK → auth.users)
- display_name (text)
- onboarding_done (boolean)
- reminder_days (int, default 3)
- created_at (timestamp)
```

---

## 🔒 Security (Row Level Security)

### Key Principles
1. **Users can only see events they're members of**
2. **Recipients can't see claims on their own lists**
3. **Only event members can create lists/items**
4. **Only list creators/event members can add recipients**

### Example RLS Policies

**events** (SELECT):
```sql
-- User is a member
EXISTS (
  SELECT 1 FROM event_members
  WHERE event_id = events.id
    AND user_id = auth.uid()
)
```

**claims** (SELECT):
```sql
-- User made the claim OR user is NOT a recipient
user_id = auth.uid()
OR NOT EXISTS (
  SELECT 1 FROM list_recipients lr
  JOIN items i ON i.list_id = lr.list_id
  WHERE i.id = claims.item_id
    AND lr.user_id = auth.uid()
)
```

**lists** (INSERT):
```sql
-- User is an event member
EXISTS (
  SELECT 1 FROM event_members
  WHERE event_id = NEW.event_id
    AND user_id = auth.uid()
)
```

---

## 🔔 Notification System

### Flow

1. **Trigger** (various):
   - User creates list with recipient → notification queued
   - User invites to event → notification queued
   - User claims item → notification queued (future)

2. **Queue** (`notification_queue` table):
   ```json
   {
     "user_id": "...",
     "title": "Gift List Created",
     "body": "John created a gift list for you in Christmas 2025",
     "data": {
       "type": "list_for_recipient",
       "list_id": "...",
       "event_id": "...",
       "invite_id": "..."
     },
     "sent": false
   }
   ```

3. **Edge Function** (`send-push-notifications`):
   - Runs periodically (manual trigger or cron)
   - Fetches unsent notifications
   - Gets push tokens for each user
   - Sends via Expo Push API
   - Marks as sent

4. **Client Receives**:
   - Notification appears in system tray
   - User taps notification

5. **Navigation Handler** (`src/lib/notifications.ts`):
   - Listens for notification taps
   - Reads `data.type` from notification
   - Routes to appropriate screen:
     - `list_for_recipient` → Events tab (shows invite)
     - `event_invite` → Events tab
     - `item_claimed` → ListDetail screen
     - etc.

6. **UI Updates**:
   - `PendingInvitesCard` auto-reloads
   - Shows Accept/Decline buttons
   - User accepts → joins event

### Notification Types

| Type | Trigger | Navigation | Data |
|------|---------|------------|------|
| `list_for_recipient` | Add recipient to list | Events tab | list_id, event_id, invite_id |
| `event_invite` | Invite to event | Events tab | event_id, invite_id |
| `item_claimed` | Item claimed | ListDetail | list_id, item_id |
| `item_unclaimed` | Item unclaimed | ListDetail | list_id, item_id |
| `purchase_reminder` | Cron job before event | Claimed tab | event_id, items[] |

---

## 💎 Free Tier Limits

### Rules
- **Free users:** Max 3 event memberships
- **Pro users:** Unlimited events

### Enforcement Points

1. **Create Event** (client + server):
   - Client: `onPressCreate()` checks `can_create_event()`
   - Server: Event creation validated
   - Message: "You can create up to 3 events on the free plan"

2. **Join Event** (client + server):
   - Client: `onPressJoin()` checks `can_join_event()`
   - Server: `join_event()` validates
   - Message: "You can only be a member of 3 events on the free plan"

3. **Accept Invite** (server):
   - `accept_event_invite()` checks `can_join_event()`
   - Raises `free_limit_reached` exception
   - Message: "Upgrade to join more events or leave an existing event"

4. **Event Access** (server):
   - `events_for_current_user()` returns accessibility flag
   - Free users: Only 3 most recent events accessible
   - Locked events shown but can't be opened

### Database Functions

```sql
can_create_event(user_id) → boolean
  - Pro: always true
  - Free: true if < 3 memberships

can_join_event(user_id) → boolean
  - Same as can_create_event

events_for_current_user() → table
  - Returns all events with 'accessible' flag
  - Free users: only 3 most recent accessible
```

---

## 🎨 UI/UX Structure

### Navigation

**Material Top Tabs** (bottom-pinned):
```
Events | Lists | Claimed | Profile
  ↓       ↓        ↓         ↓
[Main]  [All]  [My     [Settings]
[Screen][Lists][Claims]
```

**Stack Navigation** (modal screens):
```
- EventDetail
- CreateEvent
- EditEvent
- JoinEvent
- ListDetail
- CreateList
- AddItem
- EditItem
- Onboarding
```

### Key Screens

**EventListScreen** (`Home → Events`):
- Welcome header with stats
- PendingInvitesCard (if any)
- List of user's events
- Create/Join buttons (with limit validation)

**EventDetailScreen**:
- Event header with image
- Members list (collapsible)
- Create List button
- FlatList of all lists in event

**ListDetailScreen**:
- List header
- Recipients display
- FlatList of items
- Claim/Unclaim buttons
- Add Item button (if owner)

**AllListsScreen** (`Home → Lists`):
- All lists from all events
- Grouped or flat view
- Quick access to any list

**MyClaimsScreen** (`Home → Claimed`):
- Items user has claimed
- Purchase status toggle
- "To Purchase" counter

**ProfileScreen**:
- Display name
- Settings (theme, language, notifications, reminders)
- Sign out

---

## 🌐 Internationalization

### Supported Languages (12)
- English (en)
- Swedish (sv)
- German (de)
- French (fr)
- Spanish (es)
- Italian (it)
- Norwegian Bokmål (nb)
- Danish (da)
- Finnish (fi)
- Dutch (nl)
- Polish (pl)
- Portuguese (pt)

### Implementation
- **i18next** library
- Translation files in `src/i18n/locales/`
- `useTranslation()` hook
- User preference stored in AsyncStorage
- "System" option uses device language

---

## 🔄 Realtime Updates

### Supabase Channels

**EventListScreen**:
```typescript
channel('events-dashboard')
  .on('events', '*', reload)
  .on('event_members', '*', reload)
  .on('lists', '*', reload)
  .on('items', '*', reload)
  .on('claims', '*', reload)
```

**EventDetailScreen**:
```typescript
channel('event-{id}-detail')
  .on('lists', '*', reload)
  .on('items', '*', reload)
  .on('claims', '*', reload)
  .on('event_members', '*', reload)
```

**ListDetailScreen**:
```typescript
channel('list-{id}')
  .on('items', '*', reload)
  .on('claims', '*', reload)
```

### Benefits
- Live updates without refreshing
- See when someone claims an item immediately
- New members appear instantly
- Collaborative experience

---

## 🎯 Key Features

### ✅ Implemented

1. **Event Management**
   - Create, edit, delete events
   - Join via code or invite
   - Member management
   - Admin controls

2. **List Management**
   - Create lists for anyone
   - Add multiple recipients
   - Custom recipient names (non-users)
   - Auto-invite non-members

3. **Item Management**
   - Add items with details (name, price, url, image)
   - Edit/delete items
   - Image upload support
   - Rich item details

4. **Claiming System**
   - One claim per item
   - Toggle purchased status
   - Private notes
   - Hidden from recipients

5. **Invitation System**
   - Email invites
   - Join code sharing
   - Pending invites UI
   - Auto-invite on list recipient add

6. **Push Notifications**
   - Invite notifications
   - List creation notifications
   - Navigation on tap
   - Badge/sound support

7. **Free Tier Limits**
   - 3 event membership limit
   - Accessibility enforcement
   - Clear upgrade messaging
   - Client + server validation

8. **Themes**
   - Light/Dark mode
   - System preference option
   - Persistent across app restarts

9. **Multi-language**
   - 12 languages supported
   - Dynamic language switching
   - System language detection

10. **Security**
    - Row Level Security on all tables
    - JWT-based authentication
    - Secure token handling
    - SECURITY DEFINER functions where needed

---

## 🔮 Future Enhancements

### Planned Features
1. **OAuth Login** - Google, Apple Sign-In
2. **Pro Tier** - Unlimited events, advanced features
3. **Item Categories** - Group items by category
4. **Price Tracking** - Alert on price drops
5. **Gift Recommendations** - AI-powered suggestions
6. **Split Gifts** - Multiple people claim one expensive item
7. **Photo Sharing** - Share photos of purchased gifts after event
8. **Event Templates** - Reuse lists year-over-year
9. **Budget Tracking** - Track spending per event
10. **Wish List Sync** - Import from Amazon, Etsy, etc.

### Technical Improvements
1. **Automated Notifications** - Database trigger or cron for edge function
2. **Error Monitoring** - Sentry integration
3. **Analytics** - User behavior tracking
4. **Performance** - Image optimization, caching
5. **Testing** - E2E tests, unit tests
6. **CI/CD** - Automated deployments
7. **Backup System** - Automated database backups
8. **Rate Limiting** - Prevent abuse

---

## 🐛 Recent Fixes (2025-10-06)

### Notification Navigation
- **Problem:** Tapping notifications did nothing
- **Fix:** Added notification response listener and navigation handler
- **Result:** Tapping notification now navigates to correct screen

### Free Tier Invite Bug
- **Problem:** Free users with 3 events could accept invites, creating inaccessible 4th event
- **Fix:** Added `can_join_event()` check to `accept_event_invite()`
- **Result:** Users can't exceed limit, see upgrade message

### Join Button Validation
- **Problem:** Join button allowed navigation even at limit
- **Fix:** Added client-side validation like Create button
- **Result:** Consistent UX, immediate feedback

### List Recipient Auth
- **Problem:** Authorization errors when adding recipients
- **Fix:** Better auth logic (list creator OR event member)
- **Result:** Proper permission handling

### Auto-Reload
- **Problem:** Invites only visible after manual reload
- **Fix:** AppState listener + notification listener in PendingInvitesCard
- **Result:** Invites appear immediately when app foregrounded

---

## 📊 Code Statistics

### Frontend (src/)
- **Components:** ~15 reusable components
- **Screens:** 13 main screens
- **Navigation:** 2 navigators (Stack, Tabs)
- **Hooks:** Custom hooks for session, etc.
- **Utilities:** Date formatting, toast, etc.
- **Language:** TypeScript throughout

### Backend (Supabase)
- **Tables:** 10 core tables
- **RLS Policies:** ~40+ security policies
- **Functions:** ~15 database functions
- **Edge Functions:** 1 (send-push-notifications)
- **Migrations:** 17 migration files

### Documentation
- **Total Docs:** 15 markdown files
- **Categories:** Features, Development, Operations, Testing
- **Lines:** ~2500 lines of documentation

---

## 🔧 Development Workflow

### Local Development
```bash
# Install dependencies
npm install

# Start Expo dev server
npm start

# Run on iOS simulator
npm run ios

# Run on Android emulator
npm run android
```

### Database Changes
```bash
# Create new migration
# Add SQL file to supabase/migrations/

# Test locally with Supabase CLI
supabase db reset

# Apply to production
# Run in Supabase SQL Editor
```

### Deployment
```bash
# Build for production
eas build --platform all

# Submit to stores
eas submit --platform ios
eas submit --platform android
```

---

## 📚 Documentation

Full documentation available in `docs/`:
- **README.md** - Documentation index
- **CHANGELOG.md** - Version history
- **MIGRATION_GUIDE.md** - Update instructions
- **features/** - Feature documentation
- **development/** - Developer guides
- **operations/** - Infrastructure docs
- **testing/** - Test procedures

---

## ✨ Summary

GiftCircles is a **production-ready** React Native app that makes gift-giving easier by:
- Organizing wishlists around events
- Letting groups collaborate secretly
- Preventing duplicate purchases
- Keeping surprises surprising

Built with modern tech (React Native, Supabase), well-documented, properly secured (RLS), and ready to scale with a freemium model.

**Current Status:** MVP complete, bug fixes applied, ready for user testing and iterative improvements.
