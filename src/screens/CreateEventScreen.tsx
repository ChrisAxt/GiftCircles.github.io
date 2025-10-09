// src/screens/CreateEventScreen.tsx
import React, { useState } from 'react';
import { View, Text, Pressable, Platform, Alert } from 'react-native';
import DateTimePicker, { DateTimePickerEvent } from '@react-native-community/datetimepicker';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';
import { parseSupabaseError, isFreeLimitError } from '../lib/errorHandler';
import { LabeledInput, LabeledPressableField } from '../components/LabeledInput';
import { useTranslation } from 'react-i18next';
import { Screen } from '../components/Screen';
import { useTheme } from '@react-navigation/native';
import TopBar from '../components/TopBar';
import { useSettings } from '../theme/SettingsProvider';

const MAX_FREE_EVENTS = 3;

function toPgDate(d: Date) {
  const y = d.getFullYear();
  const m = `${d.getMonth() + 1}`.padStart(2, '0');
  const day = `${d.getDate()}`.padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function pretty(d: Date) {
  return d.toLocaleDateString(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

export default function CreateEventScreen({ navigation }: any) {
  const { t } = useTranslation();
  const { colors } = useTheme();
  const { themePref } = useSettings();

  const [title, setTitle] = useState('');
  const [description, setDescription] = useState(''); // optional
  const [eventDate, setEventDate] = useState<Date | null>(null);
  const [showPicker, setShowPicker] = useState(false);
  const [loading, setLoading] = useState(false);
  const [recurrence, setRecurrence] =
    useState<'none' | 'weekly' | 'monthly' | 'yearly'>('none');

  const onChangeDate = (_: DateTimePickerEvent, selected?: Date) => {
    if (Platform.OS === 'android') setShowPicker(false);
    if (selected) setEventDate(selected);
  };

  // Tries to read Pro status via RPC if present. Safe fallbacks if it doesn’t exist.
  const checkIsPro = async (userId: string): Promise<boolean> => {
    try {
      const r1 = await supabase.rpc('is_pro');
      if (!r1.error && typeof r1.data === 'boolean') return r1.data;
      const r2 = await supabase.rpc('is_pro', { p_user: userId });
      if (!r2.error && typeof r2.data === 'boolean') return r2.data;
    } catch { }
    return false; // default to Free if function is missing
  };

  const preflightCreationAllowed = async (userId: string): Promise<boolean> => {
    const isPro = await checkIsPro(userId);
    if (isPro) return true;

    const { count, error } = await supabase
      .from('events')
      .select('id', { count: 'exact', head: true })
      .eq('owner_id', userId);

    if (error) {
      Alert.alert(
        t('billing.upgradeRequiredTitle', 'Upgrade required'),
        t(
          'billing.upgradeRequiredCreateBody',
          'We could not verify your quota. You can create up to 3 events on Free. Subscribe to create more.'
        )
      );
      return false;
    }

    if ((count ?? 0) >= MAX_FREE_EVENTS) {
      Alert.alert(
        t('billing.upgradeRequiredTitle', 'Upgrade required'),
        t('billing.upgradeRequiredCreateBody', 'You can create up to 3 events on Free. Subscribe to create more.')
      );
      return false;
    }
    return true;
  };

  const create = async () => {
    if (!title.trim()) {
      return toast.info(
        t('createEvent.toastMissingTitleTitle'),
        { text2: t('createEvent.toastMissingTitleBody')}
      );
    }

    setLoading(true);
    try {
      const { data: { user }, error: userErr } = await supabase.auth.getUser();
      if (userErr) throw userErr;
      if (!user) throw new Error('Not signed in');

      const p_event_date = eventDate ? toPgDate(eventDate) : null;

      console.log('[CreateEvent] Calling create_event_and_admin RPC for user:', user.id);
      const { data: newId, error: rpcErr } = await supabase.rpc('create_event_and_admin', {
        p_title: title.trim(),
        p_event_date,
        p_recurrence: recurrence,
        p_description: description.trim() || null,
      });

      if (rpcErr) {
        console.log('[CreateEvent] RPC error:', JSON.stringify(rpcErr, null, 2));
        // Handle free limit error with Alert
        if (isFreeLimitError(rpcErr)) {
          console.log('[CreateEvent] Free limit error detected');
          const errorDetails = parseSupabaseError(rpcErr, t);
          Alert.alert(errorDetails.title, errorDetails.message);
          setLoading(false);
          return;
        }
        throw rpcErr;
      }
      if (!newId) throw new Error('RPC returned no id');

      console.log('[CreateEvent] Event created successfully:', newId);
      toast.success(t('createEvent.toastCreated'));
      navigation.replace('EventDetail', { id: newId as string });
    } catch (err: any) {
      console.log('[CreateEvent] ERROR', err);
      const errorDetails = parseSupabaseError(err, t);
      toast.error(errorDetails.title, errorDetails.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Screen>
      <TopBar title={t('createEvent.screenTitle', 'Create Event')} />
      <View style={{ padding: 16 }}>
        <LabeledInput
          label={t('createEvent.titleLabel')}
          placeholder={t('createEvent.titlePlaceholder')}
          value={title}
          onChangeText={setTitle}
        />

        <LabeledInput
          label={t('createEvent.descriptionLabel')}
          placeholder={t('createEvent.descriptionPlaceholder')}
          value={description}
          onChangeText={setDescription}
        />

        <LabeledPressableField
          label={t('createEvent.dateLabel')}
          placeholder={t('createEvent.datePlaceholder')}
          valueText={eventDate ? pretty(eventDate) : undefined}
          onPress={() => setShowPicker(true)}
        />

        {showPicker && (
          <>
            {Platform.OS === 'ios' && (
              <View style={{ alignItems: 'flex-end', marginBottom: 8 }}>
                <Pressable onPress={() => setShowPicker(false)}>
                  <Text style={{ color: '#2e95f1', fontWeight: '600' }}>{t('createEvent.done')}</Text>
                </Pressable>
              </View>
            )}
            <DateTimePicker
              value={eventDate ?? new Date()}
              mode="date"
              display={Platform.OS === 'ios' ? 'inline' : 'default'}
              themeVariant={themePref}
              onChange={onChangeDate}
            />
          </>
        )}

        {/* Recurrence selector */}
        <View
          style={{
            backgroundColor: colors.card,
            borderRadius: 12,
            padding: 12,
            borderWidth: 1,
            borderColor: colors.border,
          }}
        >
          <Text style={{ fontWeight: '600', marginBottom: 6, color: colors.text }}>
            {t('createEvent.recursLabel')}
          </Text>
          <View style={{ flexDirection: 'row', gap: 8, flexWrap: 'wrap' }}>
            {(['none', 'weekly', 'monthly', 'yearly'] as const).map(opt => (
              <Pressable
                key={opt}
                onPress={() => setRecurrence(opt)}
                style={{
                  paddingVertical: 8,
                  paddingHorizontal: 12,
                  borderRadius: 999,
                  backgroundColor: recurrence === opt ? '#2e95f1' : colors.card,
                  borderWidth: recurrence === opt ? 0 : 1,
                  borderColor: recurrence === opt ? 'transparent' : colors.border,
                }}
              >
                <Text style={{ color: recurrence === opt ? 'white' : colors.text, fontWeight: '700' }}>
                  {t(`createEvent.recurs.${opt}`)}
                </Text>
              </Pressable>
            ))}
          </View>
        </View>

        <View style={{ marginTop: 24 }}>
          <Pressable
            onPress={create}
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
            <Text style={{ color: '#fff', fontWeight: '700' }}>
              {loading ? t('createEvent.creating') : t('createEvent.create')}
            </Text>
          </Pressable>
        </View>
      </View>
    </Screen>
  );
}
