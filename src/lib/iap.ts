// src/lib/iap.ts
import Purchases, {
  CustomerInfo,
  PurchasesOffering,
  PurchasesPackage,
  LOG_LEVEL,
} from 'react-native-purchases';
import Constants from 'expo-constants';
import { supabase } from './supabase';

const REVENUECAT_API_KEY = Constants.expoConfig?.extra?.revenueCatApiKey;
const ENTITLEMENT_ID = 'pro';

let isConfigured = false;

/**
 * Initialize RevenueCat SDK with user ID
 * Call this after user authentication
 */
export async function initializeRevenueCat(userId: string): Promise<void> {
  if (isConfigured) {
    console.log('[RevenueCat] Already configured');
    return;
  }

  if (!REVENUECAT_API_KEY) {
    console.error('[RevenueCat] API key not configured in app.json');
    return;
  }

  try {
    // Configure RevenueCat
    Purchases.configure({
      apiKey: REVENUECAT_API_KEY,
      appUserID: userId,
    });

    // Enable debug logs in development
    if (__DEV__) {
      Purchases.setLogLevel(LOG_LEVEL.DEBUG);
    }

    isConfigured = true;
    console.log('[RevenueCat] Configured successfully for user:', userId);

    // Set up listener for customer info updates
    Purchases.addCustomerInfoUpdateListener(async (info) => {
      console.log('[RevenueCat] Customer info updated');
      await syncProStatusToSupabase(info);
    });

    // Sync initial status
    const customerInfo = await Purchases.getCustomerInfo();
    await syncProStatusToSupabase(customerInfo);
  } catch (e) {
    console.error('[RevenueCat] Configuration error:', e);
  }
}

/**
 * Sync pro status from RevenueCat to Supabase
 */
async function syncProStatusToSupabase(customerInfo: CustomerInfo): Promise<void> {
  try {
    const isPro = customerInfo.entitlements.active[ENTITLEMENT_ID] !== undefined;
    const entitlement = customerInfo.entitlements.active[ENTITLEMENT_ID];
    const proUntil = entitlement?.expirationDate || null;

    console.log('[RevenueCat] Syncing to Supabase:', { isPro, proUntil });

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      console.warn('[RevenueCat] No user found, skipping sync');
      return;
    }

    const { error } = await supabase
      .from('profiles')
      .update({
        plan: isPro ? 'pro' : 'free',
        pro_until: proUntil,
      })
      .eq('id', user.id);

    if (error) {
      console.error('[RevenueCat] Error syncing to Supabase:', error);
    } else {
      console.log('[RevenueCat] Successfully synced to Supabase');
    }
  } catch (e) {
    console.error('[RevenueCat] Sync error:', e);
  }
}

/**
 * Check if user has active pro subscription
 */
export async function checkIsProUser(): Promise<boolean> {
  try {
    const customerInfo = await Purchases.getCustomerInfo();
    const isPro = customerInfo.entitlements.active[ENTITLEMENT_ID] !== undefined;
    console.log('[RevenueCat] User pro status:', isPro);
    return isPro;
  } catch (e) {
    console.error('[RevenueCat] Error checking pro status:', e);
    return false;
  }
}

/**
 * Get current offerings (subscription packages)
 */
export async function getOfferings(): Promise<PurchasesOffering | null> {
  try {
    const offerings = await Purchases.getOfferings();
    if (offerings.current !== null) {
      console.log('[RevenueCat] Current offering:', offerings.current.identifier);
      console.log('[RevenueCat] Available packages:', offerings.current.availablePackages.length);
      return offerings.current;
    }
    console.warn('[RevenueCat] No current offering available');
    return null;
  } catch (e) {
    console.error('[RevenueCat] Error fetching offerings:', e);
    return null;
  }
}

/**
 * Purchase a subscription package
 * @returns true if purchase successful, false if cancelled
 * @throws Error if purchase fails
 */
export async function purchasePackage(pkg: PurchasesPackage): Promise<boolean> {
  try {
    console.log('[RevenueCat] Starting purchase for:', pkg.identifier);

    const { customerInfo } = await Purchases.purchasePackage(pkg);

    // Sync to Supabase
    await syncProStatusToSupabase(customerInfo);

    const isPro = customerInfo.entitlements.active[ENTITLEMENT_ID] !== undefined;
    console.log('[RevenueCat] Purchase completed, pro status:', isPro);

    return isPro;
  } catch (e: any) {
    if (e.userCancelled) {
      console.log('[RevenueCat] User cancelled purchase');
      return false;
    }
    console.error('[RevenueCat] Purchase error:', e);
    throw new Error(e.message || 'Purchase failed');
  }
}

/**
 * Restore previous purchases
 * Useful when user reinstalls app or logs in on new device
 */
export async function restorePurchases(): Promise<boolean> {
  try {
    console.log('[RevenueCat] Restoring purchases...');

    const customerInfo = await Purchases.restorePurchases();

    // Sync to Supabase
    await syncProStatusToSupabase(customerInfo);

    const isPro = customerInfo.entitlements.active[ENTITLEMENT_ID] !== undefined;
    console.log('[RevenueCat] Restore completed, pro status:', isPro);

    return isPro;
  } catch (e) {
    console.error('[RevenueCat] Restore error:', e);
    throw new Error('Failed to restore purchases');
  }
}

/**
 * Get customer info (subscription status, entitlements, etc.)
 */
export async function getCustomerInfo(): Promise<CustomerInfo | null> {
  try {
    const customerInfo = await Purchases.getCustomerInfo();
    return customerInfo;
  } catch (e) {
    console.error('[RevenueCat] Error getting customer info:', e);
    return null;
  }
}

/**
 * Log out current user from RevenueCat
 * Call this when user signs out of your app
 */
export async function logoutRevenueCat(): Promise<void> {
  if (!isConfigured) {
    console.log('[RevenueCat] Not configured, skipping logout');
    return;
  }

  try {
    await Purchases.logOut();
    isConfigured = false;
    console.log('[RevenueCat] User logged out');
  } catch (e) {
    console.error('[RevenueCat] Logout error:', e);
  }
}

/**
 * Get subscription status details
 */
export async function getSubscriptionStatus(): Promise<{
  isPro: boolean;
  expirationDate: string | null;
  willRenew: boolean;
  productIdentifier: string | null;
}> {
  try {
    const customerInfo = await Purchases.getCustomerInfo();
    const entitlement = customerInfo.entitlements.active[ENTITLEMENT_ID];

    if (!entitlement) {
      return {
        isPro: false,
        expirationDate: null,
        willRenew: false,
        productIdentifier: null,
      };
    }

    return {
      isPro: true,
      expirationDate: entitlement.expirationDate,
      willRenew: entitlement.willRenew,
      productIdentifier: entitlement.productIdentifier,
    };
  } catch (e) {
    console.error('[RevenueCat] Error getting subscription status:', e);
    return {
      isPro: false,
      expirationDate: null,
      willRenew: false,
      productIdentifier: null,
    };
  }
}
