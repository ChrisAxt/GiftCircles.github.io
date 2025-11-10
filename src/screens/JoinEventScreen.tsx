import React, { useState } from 'react';
import { View, Text, Alert, Pressable, ActivityIndicator } from 'react-native';
import { supabase } from '../lib/supabase';
import { parseSupabaseError } from '../lib/errorHandler';
import { LabeledInput } from '../components/LabeledInput';
import { useTranslation } from 'react-i18next';
import { ScreenScroll } from '../components/Screen';
import { useTheme } from '@react-navigation/native';
import TopBar from '../components/TopBar';

export default function JoinEventScreen({ navigation }: any) {
  const { t } = useTranslation();
  const { colors } = useTheme();

  const [code, setCode] = useState('');
  const [loading, setLoading] = useState(false);

  const join = async () => {
    const trimmed = code.trim();
    if (!trimmed) {
      return Alert.alert(t('joinEvent.alertEnterTitle'), t('joinEvent.alertEnterBody'));
    }
    setLoading(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not signed in');

      // Check if user can join (free tier limit: 3 total events)
      const { data: canJoin, error: checkError } = await supabase.rpc('can_join_event', {
        p_user: user.id
      });

      if (checkError) {
        const errorDetails = parseSupabaseError(checkError, t);
        return Alert.alert(errorDetails.title, errorDetails.message);
      }

      if (canJoin === false) {
        return Alert.alert(
          t('errors.limits.freeLimitTitle', 'Upgrade required'),
          t('errors.limits.freeLimitMessage', 'You can create up to 3 events on the free plan. Upgrade to create more.')
        );
      }

      const { data: eventId, error } = await supabase.rpc('join_event', { p_code: trimmed });
      if (error) {
        const errorDetails = parseSupabaseError(error, t);
        return Alert.alert(errorDetails.title, errorDetails.message);
      }

      navigation.replace('EventDetail', { id: eventId });
    } catch (err: any) {
      const errorDetails = parseSupabaseError(err, t);
      Alert.alert(errorDetails.title, errorDetails.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <ScreenScroll contentContainerStyle={{ paddingBottom: 24 }}>
      <TopBar title={t('joinEvent.screenTitle', 'Join Event')} />
      {/* No extra padding here (avoids double 16px) */}
      <View style={{ flex: 1, justifyContent: 'center', gap: 12, paddingHorizontal: 16, paddingTop: 16 }}>
        <Text style={{ fontSize: 20, fontWeight: '700', marginBottom: 4, color: colors.text }}>
          {t('joinEvent.heading')}
        </Text>

        <LabeledInput
          label={t('joinEvent.codeLabel')}
          placeholder={t('joinEvent.codePlaceholder')}
          value={code}
          onChangeText={setCode}
          autoCapitalize="characters"
        />

        <Pressable
          onPress={join}
          disabled={loading}
          style={{
            backgroundColor: '#2e95f1',
            paddingVertical: 10,
            paddingHorizontal: 16,
            borderRadius: 10,
            alignItems: 'center',
            opacity: loading ? 0.6 : 1,
          }}
        >
          {loading ? (
            <View style={{ flexDirection: 'row', alignItems: 'center' }}>
              <ActivityIndicator color="#fff" />
              <Text style={{ color: '#fff', fontWeight: '700', marginLeft: 8 }}>
                {t('joinEvent.joining')}
              </Text>
            </View>
          ) : (
            <Text style={{ color: '#fff', fontWeight: '700' }}>
              {t('joinEvent.join')}
            </Text>
          )}
        </Pressable>
      </View>
    </ScreenScroll>
  );
}
