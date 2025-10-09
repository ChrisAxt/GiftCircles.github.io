# GiftCircles Documentation

## 📖 Quick Reference

### Getting Started
- **[Main README](../README.md)** - Project overview and setup
- **[App Overview](./APP_OVERVIEW.md)** ⭐ **NEW** - Complete application guide
- **[Migration Guide](./MIGRATION_GUIDE.md)** - How to apply latest updates
- **[Changelog](./CHANGELOG.md)** - What changed and when

### Latest Updates (2025-10-08)
- **[Session Summary](./SESSION_SUMMARY_2025-10-08.md)** - Theme fixes, last member permissions, production prep
- **[Migration Guide](./MIGRATION_GUIDE.md)** - Apply migrations 018-019
- **[Changelog](./CHANGELOG.md)** - Complete list of changes
- **[Testing Guide](./testing/notification_flow.md)** - How to test notifications

### Feature Documentation

#### Invitation System
- **[Event Invite System](./features/invite_system.md)** - How event invitations work
- **[List Recipient Invites](./features/list_recipient_invites.md)** - Auto-invite when adding list recipients

#### Notifications
- **[Notification System](./features/notification_fix.md)** - Push notification navigation and handling

#### Free Tier Limits
- **[Free Tier Overview](./features/free_tier_limits.md)** - 3-event membership limit
- **[Invite Limit Fix](./features/free_tier_invite_fix.md)** - Fix for invite acceptance at limit
- **[Join Button Validation](./features/join_button_limit.md)** - Client-side limit check

#### Permissions
- **[Last Member Permissions](./features/last_member_permissions.md)** - Full access for last remaining member

### Development Guides
- **[Error Handling](./development/error_handling.md)** - User-friendly error messages
- **[Security Analysis](./development/security_analysis.md)** - RLS policies and security review
- **[Deployment Checklist](./development/deployment_checklist.md)** - Pre-deployment steps
- **[Production Release Checklist](./development/PRODUCTION_RELEASE_CHECKLIST.md)** ⭐ - Complete app store submission guide

### Legal Documents
- **[Privacy Policy](./legal/privacy-policy.md)** - Draft privacy policy for app stores
- **[Terms of Service](./legal/terms-of-service.md)** - Draft terms of service

### Operations
- **[Cron Jobs Setup](./operations/cron_jobs.md)** - Automated tasks configuration

### Testing
- **[Notification Flow Testing](./testing/notification_flow.md)** - Step-by-step testing guide
- **[Database Tests](./testing/DATABASE_TESTS.md)** - Database test suite and running instructions

---

## 📂 Documentation Structure

```
docs/
├── README.md (this file)
├── CHANGELOG.md
├── MIGRATION_GUIDE.md
├── SESSION_SUMMARY_2025-10-08.md
│
├── features/
│   ├── invite_system.md
│   ├── list_recipient_invites.md
│   ├── notification_fix.md
│   ├── free_tier_limits.md
│   ├── free_tier_invite_fix.md
│   ├── join_button_limit.md
│   └── last_member_permissions.md ⭐ NEW
│
├── development/
│   ├── error_handling.md
│   ├── security_analysis.md
│   ├── deployment_checklist.md
│   └── PRODUCTION_RELEASE_CHECKLIST.md ⭐
│
├── legal/
│   ├── privacy-policy.md ⭐ NEW
│   └── terms-of-service.md ⭐ NEW
│
├── operations/
│   └── cron_jobs.md
│
└── testing/
    ├── notification_flow.md
    └── DATABASE_TESTS.md
```

---

## 🎯 Common Tasks

### "How does the whole app work?"
→ [APP_OVERVIEW.md](./APP_OVERVIEW.md) ⭐

### "I want to update my app with the latest fixes"
→ [MIGRATION_GUIDE.md](./MIGRATION_GUIDE.md)

### "What changed recently?"
→ [CHANGELOG.md](./CHANGELOG.md)

### "How do invitations work?"
→ [invite_system.md](./features/invite_system.md)

### "Why can't I join more than 3 events?"
→ [free_tier_limits.md](./features/free_tier_limits.md)

### "Notifications aren't working"
→ [notification_flow.md](./testing/notification_flow.md)

### "I'm deploying to production"
→ [deployment_checklist.md](./development/deployment_checklist.md)

### "How do I run database tests?"
→ [DATABASE_TESTS.md](./testing/DATABASE_TESTS.md)

### "Last member can't delete content in event"
→ [last_member_permissions.md](./features/last_member_permissions.md)

### "Preparing for app store release"
→ [PRODUCTION_RELEASE_CHECKLIST.md](./development/PRODUCTION_RELEASE_CHECKLIST.md)

---

## 📝 Document Purposes

### Primary (Read These)
- **CHANGELOG.md** - History of changes
- **MIGRATION_GUIDE.md** - How to update

### Features (How Things Work)
- **invite_system.md** - Event invitation flow
- **list_recipient_invites.md** - List recipient auto-invite
- **notification_fix.md** - Notification navigation
- **free_tier_limits.md** - Membership limits overview
- **free_tier_invite_fix.md** - Specific bug fix details
- **join_button_limit.md** - UI validation details
- **last_member_permissions.md** - Last member full access ⭐ NEW

### Development (For Developers)
- **error_handling.md** - Error message patterns
- **security_analysis.md** - Security review
- **deployment_checklist.md** - Deployment steps
- **PRODUCTION_RELEASE_CHECKLIST.md** - App store submission guide ⭐

### Legal (App Store Requirements)
- **privacy-policy.md** - Privacy policy template ⭐ NEW
- **terms-of-service.md** - Terms of service template ⭐ NEW

### Operations (Infrastructure)
- **cron_jobs.md** - Scheduled tasks

### Testing (QA)
- **notification_flow.md** - Test procedures
- **DATABASE_TESTS.md** - Database test suite guide
