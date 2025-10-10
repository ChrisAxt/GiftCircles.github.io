# GiftCircles - Pre-Production Checklist

## **Production Build Checklist**

### **1. App Store Configuration**

**iOS (App Store Connect)**
- [ ] Apple Developer account ($99/year)
- [x] Bundle identifier already set: `com.giftcircles.app`
- [x] Build number auto-incrementing (configured in eas.json:18)
- [x] App icon and splash screen ready (assets folder)
- [ ] Need to create App Store Connect app listing

**Android (Google Play Console)**
- [ ] Google Play Developer account ($25 one-time)
- [x] Package name already set: `com.giftcircles.app`
- [x] google-services.json already present
- [x] Version code auto-incrementing (configured in eas.json:18)

### **2. Environment & Secrets Management**

**Current State:**
- Supabase credentials are in `app.json` (lines 38-39) - **PUBLIC**
- No `.env` file exists (only `.env.test`)

**What to do:**
```bash
# Create production environment file
cat > .env << 'EOF'
SUPABASE_URL=https://bqgakovbbbiudmggduvu.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
EOF

# Add to .gitignore if not already
echo ".env" >> .gitignore
```

Then update app.json to use env vars instead of hardcoded values.

### **3. Build Configuration (EAS)**

Your `eas.json` needs production environment variables:

```json
{
  "build": {
    "production": {
      "autoIncrement": true,
      "env": {
        "NODE_ENV": "production"
      },
      "android": {
        "buildType": "apk"  // or "app-bundle" for Play Store
      },
      "ios": {
        "simulator": false
      }
    }
  }
}
```

### **4. Pre-Build Steps**

- [ ] **Remove test credentials from app.json** (move to EAS Secrets)
- [ ] **Update version in package.json** (currently 0.1.0)
- [ ] **Test all database migrations are applied** (see deployment_checklist.md)
- [ ] **Verify push notifications work** on physical devices
- [ ] **Test deep linking** with actual URLs
- [ ] **Review app permissions** in app.json

### **5. EAS Build Commands**

```bash
# Install EAS CLI if not already
npm install -g eas-cli

# Login to Expo account
eas login

# Configure project (first time only)
eas build:configure

# iOS production build
eas build --platform ios --profile production

# Android production build
eas build --platform android --profile production

# Both platforms
eas build --platform all --profile production
```

### **6. Submission**

```bash
# Submit to Apple App Store
eas submit --platform ios

# Submit to Google Play
eas submit --platform android
```

### **7. Critical Items to Address**

1. **Hardcoded Supabase keys in app.json** - Should use EAS Secrets
2. **No privacy policy URL** - Required for App Store
3. **No terms of service** - Required for App Store
4. **Missing app descriptions** - Need for store listings
5. **No screenshots** - Need for store listings
6. **Database migrations status** - Ensure all applied per deployment_checklist.md

### **8. Post-Build Verification**

- [ ] Test production build on physical iOS device
- [ ] Test production build on physical Android device
- [ ] Verify authentication works
- [ ] Verify push notifications work
- [ ] Verify deep links work
- [ ] Test offline behavior
- [ ] Check crash reporting is configured

---

*Created: 2025-10-09*
*For production testing release, see: production_testing_checklist.md*
