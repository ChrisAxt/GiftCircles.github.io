// src/screens/CustomerCenterScreen.tsx
import React, { useEffect, useState } from 'react';
import { View, ActivityIndicator, StyleSheet } from 'react-native';
import { useTheme } from '@react-navigation/native';
import { RevenueCatUI, CUSTOMER_CENTER_RESULT } from 'react-native-purchases-ui';
import { toast } from '../lib/toast';
import { useTranslation } from 'react-i18next';

interface CustomerCenterScreenProps {
  navigation: any;
}

export default function CustomerCenterScreen({ navigation }: CustomerCenterScreenProps) {
  const { colors } = useTheme();
  const { t } = useTranslation();
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    presentCustomerCenter();
  }, []);

  const presentCustomerCenter = async () => {
    try {
      console.log('[CustomerCenter] Presenting customer center');

      // Present the RevenueCat Customer Center
      const result = await RevenueCatUI.presentCustomerCenter();

      setLoading(false);

      // Handle customer center result
      switch (result) {
        case CUSTOMER_CENTER_RESULT.RESTORED:
          console.log('[CustomerCenter] Purchases restored');
          toast.success(
            t('premium.restoreSuccess.title', 'Purchases Restored'),
            { text2: t('premium.restoreSuccess.message', 'Your subscription has been restored!') }
          );
          break;

        case CUSTOMER_CENTER_RESULT.ERROR:
          console.error('[CustomerCenter] Error occurred');
          toast.error(
            t('errors.generic.title', 'Error'),
            { text2: t('errors.generic.message', 'Something went wrong. Please try again.') }
          );
          break;
      }

      // Navigate back
      if (navigation.canGoBack()) {
        navigation.goBack();
      } else {
        navigation.replace('Home');
      }
    } catch (error: any) {
      console.error('[CustomerCenter] Error presenting customer center:', error);
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

  // Show loading indicator while customer center is loading
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
