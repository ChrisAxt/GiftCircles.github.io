// src/screens/PaywallScreen.tsx
import React, { useEffect, useState } from 'react';
import { View, ActivityIndicator, StyleSheet } from 'react-native';
import { useTheme } from '@react-navigation/native';
import { RevenueCatUI, PAYWALL_RESULT } from 'react-native-purchases-ui';
import { toast } from '../lib/toast';
import { useTranslation } from 'react-i18next';

interface PaywallScreenProps {
  navigation: any;
  route?: {
    params?: {
      onSuccess?: () => void;
    };
  };
}

export default function PaywallScreen({ navigation, route }: PaywallScreenProps) {
  const { colors } = useTheme();
  const { t } = useTranslation();
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    presentPaywall();
  }, []);

  const presentPaywall = async () => {
    try {
      // Present the RevenueCat Paywall
      const result = await RevenueCatUI.presentPaywall({
        // Optional: customize paywall appearance
        // offering: 'default', // Use specific offering
      });

      setLoading(false);

      // Handle paywall result
      switch (result) {
        case PAYWALL_RESULT.PURCHASED:
        case PAYWALL_RESULT.RESTORED:
          console.log('[Paywall] Purchase/Restore successful');

          // Show success message
          toast.success(
            t('premium.purchaseSuccess.title', 'Welcome to Premium!'),
            { text2: t('premium.purchaseSuccess.message', 'All premium features unlocked!') }
          );

          // Call success callback if provided
          if (route?.params?.onSuccess) {
            route.params.onSuccess();
          }

          // Navigate back
          if (navigation.canGoBack()) {
            navigation.goBack();
          } else {
            navigation.replace('Home');
          }
          break;

        case PAYWALL_RESULT.CANCELLED:
          console.log('[Paywall] User cancelled');
          // Navigate back without showing error
          if (navigation.canGoBack()) {
            navigation.goBack();
          } else {
            navigation.replace('Home');
          }
          break;

        case PAYWALL_RESULT.ERROR:
          console.error('[Paywall] Error occurred');
          toast.error(
            t('premium.purchaseError.title', 'Purchase Failed'),
            { text2: t('premium.purchaseError.message', 'Something went wrong. Please try again.') }
          );
          if (navigation.canGoBack()) {
            navigation.goBack();
          } else {
            navigation.replace('Home');
          }
          break;

        case PAYWALL_RESULT.NOT_PRESENTED:
          console.warn('[Paywall] Paywall not presented');
          toast.error(
            t('premium.paywallError.title', 'Unable to Load'),
            { text2: t('premium.paywallError.message', 'Could not load subscription options.') }
          );
          if (navigation.canGoBack()) {
            navigation.goBack();
          } else {
            navigation.replace('Home');
          }
          break;
      }
    } catch (error: any) {
      console.error('[Paywall] Error presenting paywall:', error);
      setLoading(false);

      toast.error(
        t('errors.generic.title', 'Error'),
        { text2: error.message || t('errors.generic.message', 'An unexpected error occurred') }
      );

      if (navigation.canGoBack()) {
        navigation.goBack();
      } else {
        navigation.replace('Home');
      }
    }
  };

  // Show loading indicator while paywall is loading
  if (loading) {
    return (
      <View style={[styles.container, { backgroundColor: colors.background }]}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  // Paywall is presented as a modal, so we just show loading state
  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <ActivityIndicator size="large" color={colors.primary} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
});
