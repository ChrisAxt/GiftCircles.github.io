// src/screens/CreateEventScreen.tsx
import React, { useState } from 'react';
import { View, Text, Pressable, Platform, Alert, TextInput, ScrollView } from 'react-native';
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
import { useSafeAreaInsets } from 'react-native-safe-area-context';

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
  const insets = useSafeAreaInsets();

  const [title, setTitle] = useState('');
  const [description, setDescription] = useState(''); // optional
  const [eventDate, setEventDate] = useState<Date | null>(null);
  const [showPicker, setShowPicker] = useState(false);
  const [loading, setLoading] = useState(false);
  const [recurrence, setRecurrence] =
    useState<'none' | 'weekly' | 'monthly' | 'yearly'>('none');
  const [adminOnlyInvites, setAdminOnlyInvites] = useState(false);
  const [adminEmails, setAdminEmails] = useState<string[]>([]);
  const [adminEmailInput, setAdminEmailInput] = useState('');

  const onChangeDate = (_: DateTimePickerEvent, selected?: Date) => {
    if (Platform.OS === 'android') setShowPicker(false);
    if (selected) setEventDate(selected);
  };

  const addAdminEmail = () => {
    const email = adminEmailInput.trim().toLowerCase();
    if (!email) return;

    // Basic email validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return toast.error(
        t('createEvent.invalidEmailTitle', 'Invalid Email'),
        { text2: t('createEvent.invalidEmailBody', 'Please enter a valid email address') }
      );
    }

    // Check for duplicates
    if (adminEmails.includes(email)) {
      return toast.info(
        t('createEvent.duplicateEmailTitle', 'Already Added'),
        { text2: t('createEvent.duplicateEmailBody', 'This email is already in the list') }
      );
    }

    setAdminEmails([...adminEmails, email]);
    setAdminEmailInput('');
  };

  const removeAdminEmail = (email: string) => {
    setAdminEmails(adminEmails.filter(e => e !== email));
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

      const { data: newId, error: rpcErr } = await supabase.rpc('create_event_and_admin', {
        p_title: title.trim(),
        p_event_date,
        p_recurrence: recurrence,
        p_description: description.trim() || null,
        p_admin_only_invites: adminOnlyInvites,
        p_admin_emails: adminEmails,
      });

      if (rpcErr) {
        // Handle free limit error with Alert
        if (isFreeLimitError(rpcErr)) {
          const errorDetails = parseSupabaseError(rpcErr, t);
          Alert.alert(errorDetails.title, errorDetails.message);
          setLoading(false);
          return;
        }
        throw rpcErr;
      }
      if (!newId) throw new Error('RPC returned no id');

      toast.success(t('createEvent.toastCreated'), {});
      navigation.replace('EventDetail', { id: newId as string });
    } catch (err: any) {
      const errorDetails = parseSupabaseError(err, t);
      toast.error(errorDetails.title, { text2: errorDetails.message });
    } finally {
      setLoading(false);
    }
  };

  return (
    <Screen>
      <TopBar title={t('createEvent.screenTitle', 'Create Event')} />
      <ScrollView contentContainerStyle={{ padding: 16, paddingBottom: insets.bottom + 40 }}>
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
              <View style={{ marginBottom: 12 }}>
                <Pressable
                  onPress={() => setShowPicker(false)}
                  style={{
                    backgroundColor: '#2e95f1',
                    paddingVertical: 10,
                    paddingHorizontal: 16,
                    borderRadius: 10,
                    alignItems: 'center',
                  }}
                  hitSlop={{ top: 12, bottom: 12, left: 12, right: 12 }}
                >
                  <Text style={{ color: '#fff', fontWeight: '700' }}>{t('createEvent.done')}</Text>
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

        {/* Admin-only invites toggle */}
        <View
          style={{
            backgroundColor: colors.card,
            borderRadius: 12,
            padding: 12,
            borderWidth: 1,
            borderColor: colors.border,
            marginTop: 12,
          }}
        >
          <Pressable
            onPress={() => setAdminOnlyInvites(!adminOnlyInvites)}
            style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}
          >
            <View style={{ flex: 1, marginRight: 12 }}>
              <Text style={{ fontWeight: '600', marginBottom: 4, color: colors.text }}>
                {t('createEvent.adminOnlyInvitesLabel', 'Restrict Invites to Admins')}
              </Text>
              <Text style={{ fontSize: 12, opacity: 0.7, color: colors.text }}>
                {t('createEvent.adminOnlyInvitesDesc', 'Only admins can invite new members to this event')}
              </Text>
            </View>
            <View
              style={{
                width: 24,
                height: 24,
                borderRadius: 4,
                borderWidth: 2,
                borderColor: adminOnlyInvites ? '#2e95f1' : colors.border,
                backgroundColor: adminOnlyInvites ? '#2e95f1' : 'transparent',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              {adminOnlyInvites && (
                <Text style={{ color: 'white', fontWeight: '900', fontSize: 16 }}>✓</Text>
              )}
            </View>
          </Pressable>
        </View>

        {/* Additional Admins */}
        <View
          style={{
            backgroundColor: colors.card,
            borderRadius: 12,
            padding: 12,
            borderWidth: 1,
            borderColor: colors.border,
            marginTop: 12,
          }}
        >
          <Text style={{ fontWeight: '600', marginBottom: 4, color: colors.text }}>
            {t('createEvent.adminEmailsLabel', 'Additional Admins (optional)')}
          </Text>
          <Text style={{ fontSize: 12, opacity: 0.7, marginBottom: 8, color: colors.text }}>
            {t('createEvent.adminEmailsDesc', 'Add email addresses of people who should be admins')}
          </Text>

          <View style={{ flexDirection: 'row', gap: 8, marginBottom: 8 }}>
            <TextInput
              style={{
                flex: 1,
                borderWidth: 1,
                borderColor: colors.border,
                borderRadius: 8,
                padding: 8,
                backgroundColor: colors.background,
                color: colors.text,
                fontSize: 14,
              }}
              placeholder={t('createEvent.adminEmailPlaceholder', 'admin@example.com')}
              placeholderTextColor={colors.text + '80'}
              value={adminEmailInput}
              onChangeText={setAdminEmailInput}
              keyboardType="email-address"
              autoCapitalize="none"
              autoCorrect={false}
              onSubmitEditing={addAdminEmail}
            />
            <Pressable
              onPress={addAdminEmail}
              style={{
                backgroundColor: '#2e95f1',
                paddingVertical: 8,
                paddingHorizontal: 16,
                borderRadius: 8,
                justifyContent: 'center',
              }}
            >
              <Text style={{ color: '#fff', fontWeight: '700' }}>
                {t('createEvent.addAdmin', 'Add')}
              </Text>
            </Pressable>
          </View>

          {adminEmails.length > 0 && (
            <View style={{ gap: 6 }}>
              {adminEmails.map((email) => (
                <View
                  key={email}
                  style={{
                    flexDirection: 'row',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    backgroundColor: colors.background,
                    padding: 8,
                    borderRadius: 6,
                  }}
                >
                  <Text style={{ color: colors.text, fontSize: 13 }}>{email}</Text>
                  <Pressable onPress={() => removeAdminEmail(email)} hitSlop={8}>
                    <Text style={{ color: '#c0392b', fontWeight: '700', fontSize: 18 }}>×</Text>
                  </Pressable>
                </View>
              ))}
            </View>
          )}
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
      </ScrollView>
    </Screen>
  );
}
