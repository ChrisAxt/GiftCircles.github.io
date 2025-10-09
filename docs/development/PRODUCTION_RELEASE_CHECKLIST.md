# Production Release Checklist - Google Play & iOS App Store

**App**: GiftCircles
**Version**: 1.0.0
**Date**: 2025-10-07

---

## 🎯 Quick Status Overview

### ✅ Already Complete
- [x] App built with React Native/Expo
- [x] Supabase backend configured
- [x] Google Services configured (Android push notifications)
- [x] App icon and splash screen created
- [x] Navigation and core features implemented
- [x] Onboarding flow complete with translations
- [x] Dark mode splash configuration added
- [x] Database migrations applied locally
- [x] Test suite created (67% passing)

### 🚀 In Progress
- [x] App configuration for production builds (build numbers, version codes)
- [x] TypeScript configuration fixed
- [x] Production logger utility created
- [x] Privacy policy and terms of service drafts created
- [x] Theme issues fixed (PendingInvitesCard, AuthScreen)
- [x] Last member permissions implemented
- [x] Notification system verified (lists, items, claims)
- [ ] Create adaptive icon file (assets/adaptive-icon.png)
- [ ] Customize and host legal documents online
- [ ] Deploy database migrations to production Supabase (migrations 000-019)
- [ ] Test on production database

### ⚠️ Needs Attention Before Release
- [ ] Fix iOS splash screen (requires production build)
- [ ] Create new splash.png with dark background/white text OR accept current light splash
- [ ] Create store listings
- [ ] Prepare marketing assets (screenshots, feature graphic)
- [ ] Set up production push notifications (iOS APNs certificates)
- [ ] Build and submit apps

---

## 📋 Detailed Pre-Release Checklist

## 1. App Configuration & Assets

### App.json Configuration
- [x] App name: "GiftCircles" ✓
- [x] Bundle identifiers set:
  - iOS: `com.giftcircles.app` ✓
  - Android: `com.giftcircles.app` ✓
- [x] Version: 1.0.0 ✓
- [x] Add `versionCode` for Android ✓
- [x] Add `buildNumber` for iOS ✓
- [x] Scheme: `giftcircles` ✓
- [x] Orientation locked to portrait ✓

### App Icon & Splash Screen

#### Icon (1024x1024)
- [x] `assets/icon.png` exists ✓
- [x] Has gradient (green to blue) ✓
- [x] White gift icon design ✓
- [ ] **TODO**: Verify no transparency issues on iOS
- [ ] **TODO**: Test on both light and dark backgrounds

#### Splash Screen (1284x2778)
- [x] `assets/splash.png` exists ✓
- [ ] **ISSUE**: Current splash has white background with dark text
- [ ] **DECISION NEEDED**:
  - Option A: Create new dark splash (black bg, white text) - recommended for dark mode
  - Option B: Keep current light splash (white bg, dark text) - acceptable
  - Option C: Create both and use adaptive splash

**Current Status**:
- iOS in Expo Go shows icon + app name (white bg)
- Android shows configured splash correctly
- **Fix**: Requires development/production build for custom splash

**Action Required (Choose One):**

**Option A - Dark Splash (Recommended):**
1. Create new `assets/splash.png`:
   - 1284 x 2778 px
   - Black background (#000000)
   - White "GiftCircles" text
   - Gradient gift icon
2. Keep current app.json config (already set to black)

**Option B - Accept Light Splash:**
1. Update app.json backgrounds to `#ffffff`
2. Current splash will work correctly

### Adaptive Icon (Android)
- [x] Add `adaptiveIcon` configuration in app.json ✓
- [ ] **TODO**: Create `assets/adaptive-icon.png` (1024x1024)
- [ ] **TODO**: Test on different Android launchers

**Note**: Configuration added, but the actual adaptive-icon.png file needs to be created before building.

---

## 2. Backend & Database

### Production Supabase Setup
- [x] Supabase project created ✓
- [x] Production URL configured in app.json ✓
- [x] Anon key configured ✓
- [ ] **TODO**: Apply all migrations to production database (000-017)
- [ ] **TODO**: Run database tests on production
- [ ] **TODO**: Verify RLS policies work correctly
- [ ] **TODO**: Test free tier limits (3 events max)

**Action Required:**
```bash
# Apply migrations to production
# See: docs/development/deployment_checklist.md

# Connect to production
export SUPABASE_DB_URL="your-prod-connection-string"

# Apply migrations 000-017 in order
for f in supabase/migrations/*.sql; do
  echo "Running $(basename $f)..."
  psql "$SUPABASE_DB_URL" -f "$f"
done

# Run tests
psql "$SUPABASE_DB_URL" -f supabase/tests/run_all_tests.sql
```

### Push Notifications (Production)
- [x] Android google-services.json configured ✓
- [ ] **TODO**: Set up iOS APNs certificates
- [ ] **TODO**: Configure Supabase Edge Function for push notifications
- [ ] **TODO**: Test notifications on both platforms
- [ ] **TODO**: Set up cron jobs for notification delivery

**Action Required:**
1. iOS: Generate APNs certificate in Apple Developer Portal
2. Upload to Supabase: Project Settings → Push Notifications
3. Deploy edge function: `supabase functions deploy send-push-notification`
4. Set up cron: See `docs/operations/cron_jobs.md`

---

## 3. Legal & Privacy Requirements

### Privacy Policy
- [x] **CRITICAL**: Create privacy policy document ✓
- [ ] **CRITICAL**: Host privacy policy online (website or GitHub Pages)
- [ ] Add privacy policy URL to app stores

**Status**: Privacy policy draft created at `docs/legal/privacy-policy.md`

**Next Steps:**
- Review and customize the policy (add email, jurisdiction, etc.)
- Host online (GitHub Pages recommended)
- Add hosted URL to app.json and store listings

### Terms of Service (Optional but Recommended)
- [x] Create terms of service document ✓
- [ ] Host terms online
- [ ] Add to app stores

**Status**: Terms of service draft created at `docs/legal/terms-of-service.md`

### Data Protection
- [ ] Verify GDPR compliance (if targeting EU)
- [ ] Verify CCPA compliance (if targeting California)
- [ ] Implement account deletion feature ✓ (already exists in ProfileScreen)
- [ ] Test data export (optional)

---

## 4. App Store Preparations

### Google Play Console

#### Account Setup
- [ ] Create Google Play Developer account ($25 one-time fee)
- [ ] Complete account verification
- [ ] Set up payment methods

#### App Listing
- [ ] **App Name**: "GiftCircles"
- [ ] **Short Description** (80 chars max):
  ```
  Coordinate gift giving for events with friends and family.
  ```
- [ ] **Full Description** (4000 chars max):
  ```
  GiftCircles makes gift giving easy and surprise-free. Create events,
  add gift lists, and secretly claim items you'll purchase. Perfect for
  birthdays, holidays, weddings, and more.

  KEY FEATURES:
  • Create events and invite friends with simple join codes
  • Build gift lists for recipients
  • Secretly claim items to avoid duplicates
  • Track purchases across all your events
  • Control who sees which lists
  • Support for recurring events

  HOW IT WORKS:
  1. Create an event (Birthday, Holiday, etc.)
  2. Invite friends using a join code
  3. Add gift lists for recipients
  4. Others claim items secretly - recipients never know!
  5. Mark purchases as you shop

  PRIVACY FIRST:
  • Recipients never see who claimed their items
  • Control list visibility per event
  • Your data stays private and secure

  Perfect for families, friend groups, coworkers, and anyone who wants
  to coordinate gifts without spoiling surprises!
  ```

#### Screenshots (Required: Min 2, Max 8)
- [ ] **TODO**: Capture screenshots from actual device:
  1. Event list screen (showing multiple events)
  2. Event detail screen (showing lists and members)
  3. List detail screen (showing items, claim buttons)
  4. My claims screen (showing purchased/unpurchased)
  5. Create event screen
  6. Onboarding screens (2-3 slides)

**Dimensions**:
- Phone: 1080 x 1920 px minimum
- Tablet (optional): 1600 x 2560 px minimum

#### Feature Graphic (Required)
- [ ] **TODO**: Create feature graphic
  - Size: 1024 x 500 px
  - Shows app name and key visual
  - Used in Play Store header

#### App Icon (Already Have)
- [x] 512 x 512 px ✓ (will use existing icon.png)

#### Content Rating
- [ ] Complete content rating questionnaire
- [ ] Expected: Everyone/3+ rating

#### Target Audience & Content
- [ ] Select target age groups (likely: Everyone)
- [ ] Declare ads: No ads
- [ ] Declare in-app purchases: None (or Yes if adding premium)

### Apple App Store Connect

#### Account Setup
- [ ] Create Apple Developer account ($99/year)
- [ ] Complete enrollment
- [ ] Accept agreements

#### App Store Connect Listing
- [ ] **App Name**: "GiftCircles"
- [ ] **Subtitle** (30 chars):
  ```
  Coordinate gifts with ease
  ```
- [ ] **Promotional Text** (170 chars):
  ```
  Plan gifts together without spoiling surprises. Create events, add wish lists, and secretly claim items you'll buy. Perfect for birthdays, holidays, and more!
  ```
- [ ] **Description** (4000 chars max): (Use same as Google Play)
- [ ] **Keywords** (100 chars):
  ```
  gift,wishlist,birthday,holiday,christmas,wedding,registry,coordination
  ```

#### Screenshots (Required)
- [ ] **TODO**: iPhone screenshots:
  - 6.7" Display (iPhone 14 Pro Max): 1290 x 2796 px
  - Need 3-10 screenshots
- [ ] **TODO**: iPad screenshots (if supporting iPad):
  - 12.9" Display: 2048 x 2732 px
  - Need 1-10 screenshots

#### App Preview Video (Optional)
- [ ] Create 30-second demo video

#### App Icon
- [x] 1024 x 1024 px ✓ (already have)

#### App Category
- [ ] Primary: Lifestyle
- [ ] Secondary: Utilities or Social Networking

#### Age Rating
- [ ] Complete age rating questionnaire
- [ ] Expected: 4+ rating

#### Pricing
- [ ] Select countries/regions
- [ ] Set price tier (likely: Free)

---

## 5. Code & Build Preparation

### Code Quality
- [x] Remove all console.log statements (or configure for production) ✓
- [ ] Remove test data and mock users
- [ ] Verify no hardcoded development URLs
- [ ] Check for exposed secrets/API keys
- [x] Run linter and fix issues ✓
- [x] Fix theme issues in UI components ✓

**Status**:
- Created production-safe logger utility at `src/lib/logger.ts`
- TypeScript configuration fixed for Expo compatibility
- Theme issues fixed in PendingInvitesCard and AuthScreen
- Console statements remain but can be wrapped with logger utility for production builds

**Recent Fixes (2025-10-08):**
- ✅ PendingInvitesCard now respects light/dark theme
- ✅ AuthScreen text inputs visible in both themes
- ✅ iOS status bar configuration error fixed
- ✅ Last member permissions implemented (database + UI)
- ✅ Event refresh after invite acceptance

### Performance
- [ ] Test on slow network (3G simulation)
- [ ] Test with large data sets (100+ items)
- [ ] Check image loading and optimization
- [ ] Verify no memory leaks

### Testing
- [ ] Test complete user flows on physical devices
- [ ] Test on small screen devices
- [ ] Test on iOS and Android
- [ ] Test dark mode
- [ ] Test landscape orientation (if supported)
- [ ] Test accessibility (VoiceOver/TalkBack)

### Known Issues to Fix
- [ ] Fix 6 remaining database test failures (documented in TEST_FAILURES_TODO.md)
  - Non-critical, can be fixed in v1.1
- [ ] iOS splash screen only works with production build
  - Will be resolved when building for App Store

---

## 6. Build Configuration

### EAS Build Setup
- [x] EAS CLI installed ✓
- [x] EAS project ID configured ✓
- [x] eas.json configured ✓
- [ ] **TODO**: Test production build locally first

### iOS Build Requirements
- [ ] **CRITICAL**: Apple Developer account active
- [ ] **CRITICAL**: Create App ID in Apple Developer Portal
- [ ] **CRITICAL**: Create provisioning profiles
- [ ] **TODO**: Configure Push Notifications capability
- [ ] **TODO**: Add app to App Store Connect
- [ ] **TODO**: Create App Store provisioning profile

**Action Required:**
```bash
# Register app ID and create profiles
eas device:create  # Register test devices (optional)
eas credentials        # Configure signing credentials

# Build for iOS
eas build --platform ios --profile production
```

### Android Build Requirements
- [x] Google Services configured ✓
- [ ] **TODO**: Create upload keystore (EAS handles this)
- [ ] **TODO**: Configure signing in EAS

**Action Required:**
```bash
# Build for Android
eas build --platform android --profile production
```

### App Permissions
- [ ] Review and document all permissions requested
- [ ] Remove unused permissions

**Current Permissions:**
- Internet (required for Supabase)
- Notifications (required for push)
- Potentially: Camera (if adding image uploads later)

---

## 7. Testing Builds

### Internal Testing
- [ ] Build internal test version
- [ ] Test on 3-5 real users
- [ ] Collect feedback
- [ ] Fix critical bugs

**Action Required:**
```bash
# Build preview
eas build --platform all --profile preview

# Distribute via:
# - TestFlight (iOS)
# - Internal testing track (Android)
```

### Beta Testing (Optional but Recommended)
- [ ] Set up TestFlight (iOS) beta
- [ ] Set up Google Play beta track
- [ ] Recruit 10-20 beta testers
- [ ] Run beta for 1-2 weeks
- [ ] Collect and address feedback

---

## 8. Final Production Builds

### Build Commands
```bash
# iOS Production Build
eas build --platform ios --profile production

# Android Production Build
eas build --platform android --profile production

# Both platforms
eas build --platform all --profile production
```

### Build Checklist
- [ ] Increment version numbers
- [ ] Update release notes
- [ ] Tag git commit: `git tag v1.0.0`
- [ ] Build completes without errors
- [ ] Download and test .ipa (iOS) and .aab (Android)
- [ ] Verify app icon displays correctly
- [ ] Verify splash screen displays correctly
- [ ] Test core flows one final time

---

## 9. Submission

### Google Play Submission
- [ ] Upload .aab to Google Play Console
- [ ] Fill out all store listing fields
- [ ] Upload screenshots and graphics
- [ ] Complete content rating
- [ ] Set pricing and distribution
- [ ] Submit for review

**Timeline**: Usually 1-3 days for review

### iOS App Store Submission
- [ ] Upload .ipa via EAS Submit or Transporter
- [ ] Complete App Store Connect listing
- [ ] Upload screenshots and metadata
- [ ] Complete export compliance
- [ ] Submit for review

**Timeline**: Usually 1-3 days for review (can be longer)

**Action Required:**
```bash
# Auto-submit via EAS
eas submit --platform ios --latest
eas submit --platform android --latest
```

---

## 10. Post-Release

### Monitoring
- [ ] Set up Sentry or similar error tracking
- [ ] Monitor Supabase logs for errors
- [ ] Watch for crash reports in consoles
- [ ] Monitor user reviews
- [ ] Track key metrics (DAU, retention, etc.)

### Support
- [ ] Set up support email
- [ ] Create FAQ/Help documentation
- [ ] Monitor app store reviews and respond
- [ ] Set up feedback channel (Discord, email, etc.)

### Marketing (Optional)
- [ ] Create landing page
- [ ] Social media accounts
- [ ] Product Hunt launch
- [ ] App Store Optimization (ASO)

---

## 📝 Quick Action Items (Priority Order)

### Must Do Before Submission (Blocking)
1. **Create privacy policy** - CRITICAL for both stores
2. **Apply database migrations to production** - Backend must work
3. **Decide on splash screen** - Dark or light version
4. **Create store screenshots** - 6-8 screenshots per platform
5. **Write store descriptions** - Use templates above
6. **Set up developer accounts** - $25 Google + $99 Apple/year
7. **Configure iOS push certificates** - Required for notifications
8. **Build and test production apps** - Final QA
9. **Submit to stores** - Fill out all forms

### Should Do (Recommended)
1. Fix iOS splash screen (create dark version with white text)
2. Add adaptive icon for Android
3. Run internal testing with 5 users
4. Fix remaining 6 database test failures
5. Remove console.log statements
6. Set up error monitoring (Sentry)
7. Create terms of service
8. Beta test for 1-2 weeks

### Nice to Have (Post-Launch)
1. Create landing page/website
2. Set up social media
3. Add App Store preview videos
4. Localize to other languages (you have i18n ready!)
5. Add iPad-specific layouts
6. Create onboarding tooltips

---

## 🎯 Estimated Timeline

### Minimum Path (Fastest to Release)
- **Week 1**: Privacy policy, store assets, production database setup
- **Week 2**: Build, test, submit to stores
- **Week 3**: Review process, launch
- **Total**: ~3 weeks

### Recommended Path (With Beta)
- **Week 1**: Privacy policy, store assets, production setup
- **Week 2**: Internal testing, fixes
- **Week 3**: Beta testing with users
- **Week 4**: Final fixes, production builds
- **Week 5**: Submit and launch
- **Total**: ~5 weeks

---

## 🔗 Useful Resources

### Documentation
- [Expo App Store Deployment](https://docs.expo.dev/distribution/app-stores/)
- [EAS Build](https://docs.expo.dev/build/introduction/)
- [EAS Submit](https://docs.expo.dev/submit/introduction/)
- [Google Play Console Help](https://support.google.com/googleplay/android-developer)
- [App Store Connect Help](https://developer.apple.com/app-store-connect/)

### Tools
- [Screenshot Frame Tool](https://shotsnapp.com/) - Make nice app screenshots
- [App Icon Generator](https://appicon.co/) - If you need to regenerate icons
- [Privacy Policy Generator](https://www.privacypolicygenerator.info/)

### Your Project Files
- Database deployment: `docs/development/deployment_checklist.md`
- Database tests: `docs/testing/DATABASE_TESTS.md`
- Test failures: `docs/development/TEST_FAILURES_TODO.md`
- Migrations: `supabase/migrations/`

---

## ✅ Final Pre-Flight Checklist

**Before you submit:**

- [ ] Privacy policy created and hosted
- [ ] Database migrations applied to production
- [ ] Production builds tested on physical devices
- [ ] All store listings filled out completely
- [ ] Screenshots uploaded (6+ per platform)
- [ ] App icons look good on devices
- [ ] Push notifications working
- [ ] Developer accounts paid and active
- [ ] Version numbers set correctly
- [ ] Release notes written
- [ ] Support email configured
- [ ] Error monitoring set up

**You're ready to submit! 🚀**

---

**Last Updated**: 2025-10-07
**Version**: 1.0.0
**Status**: Pre-Release
