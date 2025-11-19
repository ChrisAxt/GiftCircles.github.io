# GiftCircles - Complete App Documentation

## Overview

GiftCircles is a collaborative gift planning app that helps groups coordinate gift-giving for events like birthdays, holidays, and special occasions. Users create events, build wish lists, and claim items to prevent duplicate gifts while maintaining the element of surprise.

## Core Concepts

### Events
Events are the foundation of GiftCircles. An event represents a gift-giving occasion (e.g., "Christmas 2025", "Mom's Birthday"). Events have:
- Title and description
- Event date
- Unique join code for inviting members
- Member management (admin, giver, recipient roles)

### Lists
Lists belong to events and represent a person's wish list. Features include:
- Multiple recipients per list
- Visibility controls (visible to all event members or selected viewers only)
- Member exclusions (hide list from specific members)
- Items with details, links, and prices

### Claims
Members can claim items from lists to indicate they will purchase them. Claims:
- Prevent duplicate gift purchases
- Are hidden from list recipients (maintains surprise)
- Can be split between multiple members
- Include purchase status tracking

## User Roles

### Event Roles
- **Admin**: Full control over event settings, can remove members, delete event
- **Giver**: Can view lists, claim items, create lists for others
- **Recipient**: Has lists created for them, cannot see who claimed their items

### List Roles
- **Creator**: Person who created the list
- **Recipient**: Person the list is for (cannot see claims on their list)
- **Viewer**: Can see the list and claim items

## Features

### Authentication
- Email and password authentication via Supabase Auth
- Session persistence across app restarts
- Password reset functionality
- Profile management (display name, preferences)

### Event Management
- Create events with title, description, and date
- Generate unique join codes for inviting members
- View all events you're a member of
- Edit event details (admin only)
- Delete events (admin only)
- Leave events
- Automatic rollover for recurring events

### Invitation System
- Share join codes via link or QR code
- Email invitations sent directly from app
- Accept or decline pending invitations
- Automatic member addition when joining via code
- Invite tracking and status management

### List Management
- Create lists for yourself or other event members
- Set list visibility (all members or selected viewers)
- Exclude specific members from seeing the list
- Add multiple recipients to a single list
- Edit list details and settings
- Delete lists (creator or admin only)
- Random recipient assignment (Secret Santa style)
  - Automatically assign list recipients from available members
  - Ensures no one is assigned to themselves
  - Creates private lists with correct visibility rules
- Random receiver assignment for items
  - Randomly assign who receives specific items
  - Useful for group gifts or surprise assignments

### Item Management
- Add items with name, description, URL, and price
- Support for multiple currencies (USD, EUR, GBP, SEK, etc.)
- Edit item details
- Delete items
- Priority ordering

### Claim System
- Claim items to indicate purchase intent
- View your claimed items across all events
- Mark items as purchased
- Unclaim items if plans change
- Request claim splits for expensive items
- Accept or decline split requests
- Claims hidden from list recipients (gift surprise protection)

### Notifications

#### Push Notifications
- New list created in your events
- New item added to lists you can view
- Items claimed (hidden from recipients)
- Items unclaimed
- Purchase reminders before event dates
- Event invitations

#### Digest Notifications
- Daily or weekly activity summaries
- Configurable delivery time
- Timezone-aware scheduling
- Detailed breakdown by event and list
- Privacy-respecting (only shows what user can see)

#### Instant Notifications
- Real-time notifications for activity
- Opt-in feature (Pro tier)
- Respects list visibility and exclusion rules

### Privacy and Security
- Row-Level Security (RLS) on all database tables
- List recipients cannot see who claimed their items
- List exclusions prevent specific members from viewing
- Selected visibility mode for private lists
- Claim activities hidden from gift recipients
- Secure authentication and session management

### Subscription Tiers

#### Free Tier
- Join up to 3 events
- Basic list and item management
- Standard notifications

#### Pro Tier
- Unlimited event memberships
- Instant notifications
- Daily/weekly activity digests
- Priority support
- Advanced notification preferences

### Internationalization
- Multiple language support:
  - English (en)
  - Swedish (sv)
  - German (de)
  - French (fr)
  - Spanish (es)
  - Italian (it)
- Automatic timezone detection
- Localized date and time formatting
- Currency localization

### User Preferences
- Push notification toggle
- Purchase reminder days configuration
- Currency preference
- Digest notification settings (frequency, time, day)
- Instant notification toggle
- Language selection

## Technical Architecture

### Frontend
- React Native with Expo
- React Navigation for routing
- TypeScript for type safety
- Async Storage for local persistence
- Expo Notifications for push notifications

### Backend
- Supabase (PostgreSQL database)
- Row-Level Security policies
- Database functions for complex operations
- Edge Functions for notification delivery
- pg_cron for scheduled tasks
- Real-time subscriptions

### Database Schema
- Users/Profiles: User accounts and preferences
- Events: Gift-giving occasions
- Event Members: User-event relationships
- Lists: Wish lists within events
- List Recipients: Who the list is for
- List Viewers: Who can see the list
- List Exclusions: Who cannot see the list
- Items: Individual gift items
- Claims: Item claim tracking
- Notification Queue: Pending notifications
- Push Tokens: Device tokens for push notifications
- Daily Activity Log: Activity tracking for digests

## Legal

- [Privacy Policy](./legal/privacy-policy.md)
- [Terms of Service](./legal/terms-of-service.md)

## Development

### Running the App
```bash
npm install
npm start
```

### Running Tests
```bash
npm test                    # Run all tests
npm run test:watch         # Watch mode
npm run test:cov           # Coverage report
npm run test:db            # Database tests
```

### Database Migrations
Located in `supabase/migrations/`. Apply via Supabase dashboard or CLI.

### Environment Setup
Requires:
- Node.js 18+
- Expo CLI
- Supabase project with proper configuration
- Push notification credentials (iOS/Android)

## Version History

### v1.0.0-beta.1 (Current)
- Core gift coordination functionality
- Event and list management
- Claim system with privacy protection
- Push notifications
- Multi-language support
- Free and Pro tier support
- Digest notifications with timezone support
