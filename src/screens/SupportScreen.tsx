// src/screens/SupportScreen.tsx
import React, { useState } from 'react';
import { View, Text, Pressable, ScrollView, Linking, ActivityIndicator } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';

interface SupportScreenProps {
  navigation: any;
  route?: {
    params?: {
      fromOnboarding?: boolean;
    };
  };
}

export default function SupportScreen({ navigation, route }: SupportScreenProps) {
  const { t } = useTranslation();
  const insets = useSafeAreaInsets();
  const [loading, setLoading] = useState(false);
  const [checkingOnboarding, setCheckingOnboarding] = useState(true);
  const [needsOnboarding, setNeedsOnboarding] = useState(false);

  // Check if user still needs onboarding
  React.useEffect(() => {
    async function checkOnboarding() {
      try {
        const { data: { user } } = await supabase.auth.getUser();
        if (!user) {
          setNeedsOnboarding(false);
          return;
        }

        const { data: prof } = await supabase
          .from('profiles')
          .select('onboarding_done')
          .eq('id', user.id)
          .maybeSingle();

        setNeedsOnboarding(!prof?.onboarding_done);
      } catch (error) {
        console.error('Failed to check onboarding status:', error);
        setNeedsOnboarding(false);
      } finally {
        setCheckingOnboarding(false);
      }
    }
    checkOnboarding();
  }, []);

  const updateSupportScreenShown = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      await supabase
        .from('profiles')
        .update({ last_support_screen_shown: new Date().toISOString() })
        .eq('id', user.id);
    } catch (error) {
      console.error('Failed to update support screen timestamp:', error);
    }
  };

  const handleGetPremium = async () => {
    setLoading(true);
    // TODO: Implement premium subscription flow (Apple/Google IAP)
    // For now, just show a toast
    toast.info(t('support.comingSoon.title'), { text2: t('support.comingSoon.body') });
    await updateSupportScreenShown();
    setLoading(false);

    // Navigate to next screen
    if (needsOnboarding) {
      navigation.replace('Onboarding');
    } else {
      navigation.replace('Home');
    }
  };

  const handleMaybeLater = async () => {
    await updateSupportScreenShown();

    if (needsOnboarding) {
      navigation.replace('Onboarding');
    } else {
      navigation.replace('Home');
    }
  };

  // Show loading while checking onboarding status
  if (checkingOnboarding) {
    return (
      <SafeAreaView style={{ flex: 1, backgroundColor: '#0ea5e9', justifyContent: 'center', alignItems: 'center' }} edges={['top', 'left', 'right']}>
        <ActivityIndicator size="large" color="white" />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: '#0ea5e9' }} edges={['top', 'left', 'right']}>
      <ScrollView
        contentContainerStyle={{
          paddingHorizontal: 20,
          paddingTop: 40,
          paddingBottom: Math.max(insets.bottom + 20, 40),
        }}
      >
        {/* Header */}
        <View style={{ alignItems: 'center', marginBottom: 32 }}>
          <Text style={{ fontSize: 32, fontWeight: '800', color: 'white', textAlign: 'center' }}>
            {t('support.title')}
          </Text>
          <Text style={{ fontSize: 16, color: 'white', opacity: 0.9, textAlign: 'center', marginTop: 8, marginBottom: 12 }}>
            {t('support.subtitle')}
          </Text>
          <Text style={{ fontSize: 14, color: 'white', opacity: 0.85, textAlign: 'center', fontStyle: 'italic' }}>
            {t('support.freeForever', 'GiftCircles is free forever. We never show ads or sell your data.')}
          </Text>
        </View>

        {/* Premium Features Card */}
        <View
          style={{
            backgroundColor: 'white',
            borderRadius: 20,
            padding: 24,
            marginBottom: 24,
            shadowColor: '#000',
            shadowOpacity: 0.1,
            shadowRadius: 12,
            shadowOffset: { width: 0, height: 4 },
            elevation: 4,
          }}
        >
          <LinearGradient
            colors={['#21c36b', '#2e95f1']}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 0 }}
            style={{
              position: 'absolute',
              top: -1,
              left: 0,
              right: 0,
              height: 274,
              borderTopLeftRadius: 20,
              borderTopRightRadius: 20,
              borderBottomLeftRadius: 20,
              borderBottomRightRadius: 20
            }}
          />

          <Text style={{ fontSize: 20, fontWeight: '800', marginBottom: 16, marginTop: 8 }}>
            {t('support.premiumFeatures.title')}
          </Text>

          {[
            { key: 'unlimitedEvents', icon: '∞' },
            { key: 'purchaseReminders', icon: '🔔' },
            { key: 'digest', icon: '📊' },
            { key: 'randomAssignment', icon: '🎲' },
          ].map((feature) => (
            <View
              key={feature.key}
              style={{
                flexDirection: 'row',
                alignItems: 'center',
                marginBottom: 12,
              }}
            >
              <View
                style={{
                  width: 32,
                  height: 32,
                  borderRadius: 16,
                  backgroundColor: '#e9f8ec',
                  alignItems: 'center',
                  justifyContent: 'center',
                  marginRight: 12,
                }}
              >
                <Text style={{ fontSize: 16 }}>{feature.icon}</Text>
              </View>
              <Text style={{ fontSize: 16, fontWeight: '600', flex: 1 }}>
                {t(`support.premiumFeatures.${feature.key}`)}
              </Text>
            </View>
          ))}

          {/* Pricing (optional - uncomment when pricing is set) */}
          {/* <Text style={{ fontSize: 14, opacity: 0.7, marginTop: 12, textAlign: 'center' }}>
            {t('support.pricing')}
          </Text> */}
        </View>

        {/* Support Options */}
        <View style={{ marginBottom: 24 }}>
          <Pressable
            onPress={handleGetPremium}
            disabled={loading}
            style={({ pressed }) => ({
              backgroundColor: 'white',
              paddingVertical: 16,
              paddingHorizontal: 24,
              borderRadius: 999,
              opacity: pressed || loading ? 0.8 : 1,
              shadowColor: '#000',
              shadowOpacity: 0.1,
              shadowRadius: 8,
              shadowOffset: { width: 0, height: 2 },
              elevation: 2,
            })}
          >
            <Text style={{ color: '#0ea5e9', fontWeight: '800', fontSize: 18, textAlign: 'center' }}>
              {t('support.actions.getPremium')}
            </Text>
          </Pressable>
        </View>

        {/* Maybe Later */}
        <Pressable
          onPress={handleMaybeLater}
          disabled={loading}
          style={({ pressed }) => ({
            paddingVertical: 12,
            opacity: pressed || loading ? 0.6 : 1,
          })}
        >
          <Text style={{ color: 'white', fontWeight: '600', fontSize: 16, textAlign: 'center' }}>
            {t('support.actions.maybeLater')}
          </Text>
        </Pressable>
      </ScrollView>
    </SafeAreaView>
  );
}
