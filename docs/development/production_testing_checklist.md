# GiftCircles - Production Testing Release Checklist

This checklist covers building and distributing a **production-ready test build** to your family for testing before App Store/Play Store submission.

## **Quick Overview**

You'll create production builds that can be distributed via:
- **iOS**: TestFlight (recommended) or direct .ipa installation
- **Android**: Google Play Internal Testing or direct .apk installation

---

## **1. Pre-Build Preparation**

### App Version
- [ ] Update version in `package.json` (e.g., `0.1.0` → `1.0.0-beta.1`)
- [ ] Verify `app.json` version matches (line 6: currently `1.0.0`)

### Database
- [ ] Verify all migrations are applied to production database
- [ ] Run through deployment_checklist.md verification queries
- [ ] Ensure test data is clean (no junk data)

### Code Quality
- [ ] Run tests: `npm test`
- [ ] Fix any failing tests
- [ ] Test app locally on both iOS and Android simulators
- [ ] Verify all new features work (invite modal, share code, theme switching)

### Expo/EAS Setup
- [ ] Install EAS CLI: `npm install -g eas-cli`
- [ ] Login to Expo: `eas login`
- [ ] Verify EAS project is configured: Check `app.json` line 41 has projectId

---

## **2. Configure Test Build Profile**

Update `eas.json` to add a `preview-production` profile:

```json
{
  "cli": {
    "version": ">= 16.19.3",
    "appVersionSource": "remote"
  },
  "build": {
    "development": {
      "developmentClient": true,
      "distribution": "internal",
      "env": {
        "NODE_ENV": "development"
      }
    },
    "preview-production": {
      "distribution": "internal",
      "env": {
        "NODE_ENV": "production"
      },
      "android": {
        "buildType": "apk"
      },
      "ios": {
        "simulator": false,
        "resourceClass": "default"
      }
    },
    "production": {
      "autoIncrement": true,
      "env": {
        "NODE_ENV": "production"
      }
    }
  },
  "submit": {
    "production": {}
  }
}
```

---

## **3. Build for Family Testing**

### iOS Build (TestFlight or Direct)

```bash
# Build for iOS
eas build --platform ios --profile preview-production

# This will:
# - Build your app with production settings
# - Create a .ipa file
# - Upload to EAS servers
# - Provide download link
```

**Expected output:**
- Build URL (e.g., `https://expo.dev/accounts/.../builds/...`)
- Download link for .ipa file
- Build time: ~10-15 minutes

### Android Build (APK)

```bash
# Build for Android
eas build --platform android --profile preview-production

# This will:
# - Build your app with production settings
# - Create an .apk file
# - Upload to EAS servers
# - Provide download link
```

**Expected output:**
- Build URL
- Download link for .apk file
- Build time: ~10-15 minutes

### Build Both Platforms

```bash
# Build both at once
eas build --platform all --profile preview-production
```

---

## **4. Distribution Options**

### **Option A: TestFlight (iOS) - Recommended**

1. **Submit to TestFlight:**
   ```bash
   eas submit --platform ios --latest
   ```

2. **Configure in App Store Connect:**
   - Go to https://appstoreconnect.apple.com
   - Select your app
   - Go to TestFlight tab
   - Add external testers (your family's emails)
   - Testers will receive email invitation

3. **Testers Install:**
   - Install TestFlight app from App Store
   - Click link in email
   - Install GiftCircles

**Pros:** Easy for testers, automatic updates, crash reports
**Cons:** Requires Apple Developer account ($99/year), 24-48hr review for first build

### **Option B: Direct Installation (iOS)**

1. **Get device UDIDs:**
   - Have each family member open Settings → General → About
   - Tap on "Serial Number" to reveal UDID
   - Copy UDID (format: `00008030-XXXXXXXXXXXX`)

2. **Register devices in Apple Developer:**
   - Go to https://developer.apple.com/account/resources/devices
   - Add each device with name and UDID

3. **Update provisioning profile and rebuild:**
   ```bash
   eas device:create
   eas build --platform ios --profile preview-production
   ```

4. **Share .ipa file:**
   - Send download link from EAS build
   - Testers install via link on their device

**Pros:** No review delay
**Cons:** Manual UDID registration, limited to 100 devices

### **Option C: Google Play Internal Testing (Android)**

1. **Upload to Play Console:**
   - Go to https://play.google.com/console
   - Create app if not exists
   - Go to Testing → Internal Testing
   - Upload .apk from EAS build

2. **Add testers:**
   - Create email list of testers
   - Share opt-in link with family

3. **Testers install:**
   - Click opt-in link
   - Download from Play Store

**Pros:** Easy distribution, automatic updates
**Cons:** Requires Play Developer account ($25 one-time)

### **Option D: Direct APK Installation (Android) - Easiest**

1. **Share APK link:**
   - Copy download link from EAS build output
   - Send to family via text/email

2. **Testers install:**
   - Download .apk on Android device
   - Enable "Install from Unknown Sources" if prompted
   - Open .apk file to install

**Pros:** No accounts needed, instant
**Cons:** Manual updates, security warning on install

---

## **5. Testing Instructions for Family**

Create a testing guide for your family:

### **Installation**
- [Platform-specific steps from above]

### **What to Test**

1. **Sign Up/Login**
   - [ ] Create account with email
   - [ ] Verify email works
   - [ ] Log out and log back in

2. **Onboarding**
   - [ ] Complete onboarding flow
   - [ ] Set display name

3. **Events**
   - [ ] Create new event
   - [ ] Edit event details
   - [ ] Delete event (if owner)
   - [ ] Join event with code
   - [ ] Invite others via email
   - [ ] Invite others via share code

4. **Lists**
   - [ ] Create list for yourself
   - [ ] Create list for someone else
   - [ ] Edit list
   - [ ] Delete list

5. **Items**
   - [ ] Add item with all fields (name, price, URL, notes)
   - [ ] Add item with just name
   - [ ] Edit item
   - [ ] Delete item

6. **Claims**
   - [ ] Claim someone else's item
   - [ ] Unclaim item
   - [ ] View claimed items in "Claimed" tab
   - [ ] Verify list owner sees claims

7. **Notifications**
   - [ ] Receive invite notification
   - [ ] Tap notification to open app
   - [ ] Verify notification settings in Profile

8. **Theme**
   - [ ] Toggle light/dark mode in Profile
   - [ ] Verify entire app switches theme
   - [ ] Verify toast messages match theme
   - [ ] Verify invite modal matches theme

9. **Edge Cases**
   - [ ] Test with poor internet connection
   - [ ] Test with airplane mode (should show error)
   - [ ] Try to create event with empty title (should error)
   - [ ] Try to join with invalid code (should error)

### **What to Report**

- **Crashes**: When and what you were doing
- **Bugs**: Describe steps to reproduce
- **Confusing UI**: What was unclear
- **Feature requests**: What's missing
- **Performance issues**: Slow screens or actions

---

## **6. Monitoring During Testing**

### Supabase Dashboard
- [ ] Monitor Supabase Logs (Database → Logs)
- [ ] Watch for errors or unusual queries
- [ ] Check Auth logs for sign-up issues

### EAS Dashboard
- [ ] Monitor crash reports: https://expo.dev
- [ ] Check build analytics
- [ ] Review device/OS distribution

### User Feedback
- [ ] Create shared document or chat for feedback
- [ ] Ask for daily updates during testing period
- [ ] Schedule debrief call after 3-5 days

---

## **7. Common Issues & Solutions**

### iOS Install Issues
**Problem:** "Unable to install"
**Solution:**
- Verify device UDID is registered
- Check provisioning profile includes device
- Rebuild after adding device

### Android Install Warning
**Problem:** "Install blocked"
**Solution:**
- Settings → Security → Enable "Install from Unknown Sources"
- Or use Play Store internal testing

### App Crashes on Launch
**Problem:** Immediate crash
**Check:**
- Supabase credentials correct
- Database migrations applied
- Check EAS crash logs

### Push Notifications Not Working
**Problem:** No notifications received
**Check:**
- Permissions granted in device settings
- Expo push token registered (check profile table)
- Test sending push from Expo dashboard

### Login Fails
**Problem:** Can't sign in
**Check:**
- Internet connection
- Supabase Auth enabled
- Check Supabase Auth logs

---

## **8. Iteration Process**

After receiving feedback:

1. **Fix issues in code**
2. **Increment version** (e.g., `1.0.0-beta.1` → `1.0.0-beta.2`)
3. **Rebuild:**
   ```bash
   eas build --platform all --profile preview-production
   ```
4. **Distribute new build** via same method
5. **Notify testers** of new version and changes

---

## **9. When Ready for Production**

After testing is successful:

- [ ] All critical bugs fixed
- [ ] Family can complete full user journey
- [ ] No crashes reported in past 48 hours
- [ ] All edge cases handled gracefully
- [ ] Ready to proceed with App Store/Play Store submission

→ **Next step:** Follow `pre_production_checklist.md` for store submission

---

## **Quick Start Commands**

```bash
# 1. Update version
# Edit package.json: "version": "1.0.0-beta.1"

# 2. Verify EAS login
eas whoami

# 3. Build for testing
eas build --platform all --profile preview-production

# 4. Wait for builds to complete (~15 minutes)

# 5. Share download links with family
# (Links will be in build output)

# 6. Monitor and iterate
# Check EAS dashboard and Supabase logs regularly
```

---

## **Support Resources**

- **EAS Build Docs:** https://docs.expo.dev/build/introduction/
- **TestFlight Guide:** https://developer.apple.com/testflight/
- **Play Internal Testing:** https://support.google.com/googleplay/android-developer/answer/9845334
- **Expo Forums:** https://forums.expo.dev/

---

**Testing Period Recommended:** 3-7 days minimum

**Tester Count Recommended:** 3-5 family members (different devices/OS versions)

**Build Profile:** `preview-production` (production code, internal distribution)

---

*Created: 2025-10-09*
*Last Updated: 2025-10-09*
