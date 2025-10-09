# GiftCircles (Expo + Supabase)

A collaborative gift list app for events where members can create lists, add items, and secretly claim gifts for each other.

## 🚀 Quick Start

1. **Create a Supabase project** and copy the API URL + anon key
2. **Configure the app** - In `app.json` under `expo.extra`, set `supabaseUrl` and `supabaseAnonKey`
3. **Run migrations** - Execute all files in `supabase/migrations/` in order
4. **Install and run:**
   ```bash
   npm install
   npm start
   ```
5. **Try it out** - Sign up, create an event, share the join code, create lists & items, claim items

## 📖 Documentation

**For complete documentation, see [docs/README.md](./docs/README.md)**

### Quick Links
- **[App Overview](./docs/APP_OVERVIEW.md)** ⭐ **NEW** - Complete application guide
- **[Migration Guide](./docs/MIGRATION_GUIDE.md)** - Apply latest updates
- **[Changelog](./docs/CHANGELOG.md)** - What's new
- **[Notification Testing](./docs/testing/notification_flow.md)** - Test push notifications
- **[Deployment Checklist](./docs/development/deployment_checklist.md)** - Pre-production steps

## 🎁 Features

- **Events** - Create events for birthdays, holidays, weddings, etc.
- **Gift Lists** - Create lists for yourself or others
- **Secret Claims** - Claim items without the recipient seeing
- **Invitations** - Invite members via email or join code
- **Push Notifications** - Get notified about invites, claims, etc.
- **Free Tier** - Use up to 3 events for free

## 🏗️ Tech Stack

- **Frontend:** React Native (Expo)
- **Backend:** Supabase (PostgreSQL + Auth + Edge Functions)
- **Notifications:** Expo Push Notifications
- **Languages:** TypeScript, SQL

## 📱 App Structure

See the in-app screens for flows. RLS policies ensure users only see appropriate data (e.g., claims are hidden from list recipients).
