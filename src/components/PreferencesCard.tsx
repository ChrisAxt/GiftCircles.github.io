// src/components/PreferencesCard.tsx
import React, { useMemo, useState } from 'react';
import {
  View, Text, Pressable, Alert, Platform, Modal, ScrollView,
} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Notifications from 'expo-notifications';
import Constants from 'expo-constants';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';
import { useSettings } from '../theme/SettingsProvider';
import { useTranslation } from 'react-i18next';
import { useTheme } from '@react-navigation/native';
import { getAllCurrencies, CURRENCIES, detectUserCurrency, type Currency } from '../lib/currency';

const inExpoGo = Constants.appOwnership === 'expo';

export default function PreferencesCard() {
  const { colors } = useTheme();
  const { themePref, setThemePref, langPref, setLangPref } = useSettings();
  const [pushEnabled, setPushEnabled] = useState<boolean | null>(null);
  const [working, setWorking] = useState(false);
  const [langOpen, setLangOpen] = useState(false);
  const [reminderDays, setReminderDays] = useState<number | null>(null);
  const [loadingReminder, setLoadingReminder] = useState(false);
  const [currencyCode, setCurrencyCode] = useState<string>('USD');
  const [currencyOpen, setCurrencyOpen] = useState(false);
  const [loadingCurrency, setLoadingCurrency] = useState(false);
  const [digestEnabled, setDigestEnabled] = useState<boolean>(false);
  const [digestHour, setDigestHour] = useState<number>(9);
  const [digestFrequency, setDigestFrequency] = useState<'daily' | 'weekly'>('daily');
  const [digestDayOfWeek, setDigestDayOfWeek] = useState<number>(1);
  const [loadingDigest, setLoadingDigest] = useState(false);
  const { t, i18n } = useTranslation();

  // Load cached push state, reminder preference, currency, and digest
  React.useEffect(() => {
    (async () => {
      const pushValue = await AsyncStorage.getItem('pref.pushEnabled');
      setPushEnabled(pushValue === '1');
      await loadReminderDays();
      await loadCurrency();
      await loadDigestPreferences();
    })();
  }, []);

  const loadReminderDays = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      const { data } = await supabase
        .from('profiles')
        .select('reminder_days')
        .eq('id', user.id)
        .maybeSingle();

      if (data?.reminder_days !== undefined) {
        setReminderDays(data.reminder_days);
      }
    } catch (e) {
      // Error loading reminder days
    }
  };

  const loadCurrency = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      const { data } = await supabase
        .from('profiles')
        .select('currency')
        .eq('id', user.id)
        .maybeSingle();

      if (data?.currency) {
        setCurrencyCode(data.currency);
      } else {
        // Auto-detect and save currency on first load
        const detected = detectUserCurrency();
        setCurrencyCode(detected);
        await updateCurrency(detected);
      }
    } catch (e) {
      // Error loading currency
    }
  };

  const loadDigestPreferences = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      const { data } = await supabase
        .from('profiles')
        .select('notification_digest_enabled, digest_time_hour, digest_frequency, digest_day_of_week')
        .eq('id', user.id)
        .maybeSingle();

      if (data) {
        setDigestEnabled(data.notification_digest_enabled ?? false);
        setDigestHour(data.digest_time_hour ?? 9);
        setDigestFrequency(data.digest_frequency ?? 'daily');
        setDigestDayOfWeek(data.digest_day_of_week ?? 1);
      }
    } catch (e) {
      // Error loading digest preferences
    }
  };
  const setPushLocal = async (b: boolean) => {
    setPushEnabled(b);
    await AsyncStorage.setItem('pref.pushEnabled', b ? '1' : '0');
  };

  const Chip = ({ active, label, onPress }: { active: boolean; label: string; onPress: () => void }) => (
    <Pressable
      onPress={onPress}
      style={{
        backgroundColor: active ? '#2e95f1' : colors.card,
        paddingVertical: 8,
        paddingHorizontal: 12,
        borderRadius: 999,
        marginRight: 8,
        marginTop: 8,
        borderWidth: active ? 0 : 1,
        borderColor: active ? 'transparent' : colors.border,
      }}
    >
      <Text style={{ color: active ? '#fff' : colors.text, fontWeight: '700' }}>{label}</Text>
    </Pressable>
  );

  const onTogglePush = async () => {
    if (working) return;
    if (inExpoGo) {
      Alert.alert(t('profile.settings.pushNotAvailableTitle'), t('profile.settings.pushNotAvailableBody'));
      return;
    }
    setWorking(true);
    try {
      if (!pushEnabled) {
        const token = await ensurePushRegistered();
        if (!token) {
          Alert.alert(t('profile.settings.pushPermissionTitle'), t('profile.settings.pushPermissionBody'));
          setWorking(false);
          return;
        }
        await AsyncStorage.setItem('pref.pushToken', token);
        await savePushTokenToDb(token);
        await setPushLocal(true);
        toast.success(t('profile.settings.pushEnabled'));
      } else {
        await removePushTokenFromDb();
        await AsyncStorage.removeItem('pref.pushToken');
        await setPushLocal(false);
        toast.info(t('profile.settings.pushDisabled'));
      }
    } catch (error) {
      Alert.alert(t('profile.settings.pushError'), String(error));
    } finally {
      setWorking(false);
    }
  };

  // ---- Dynamic language list pulled from i18n resources ----
  const availableLangs = useMemo<string[]>(() => {
    const store = (i18n.services?.resourceStore as any)?.data || {};
    return Object.keys(store).filter(k => k !== 'dev');
  }, [i18n]);

  // Localized language names (fallbacks if Intl.DisplayNames missing)
  const dn = useMemo(() => {
    // @ts-ignore
    const DisplayNames = (Intl as any)?.DisplayNames;
    let intl: any = null;
    if (DisplayNames) {
      try { intl = new DisplayNames([i18n.language], { type: 'language' }); } catch {}
    }
    const fallback: Record<string, string> = {
      en: 'English',
      sv: 'Svenska',
      de: 'Deutsch',
      fr: 'Français',
      es: 'Español',
      it: 'Italiano',
      nb: 'Norsk bokmål',
      da: 'Dansk',
      fi: 'Suomi',
      nl: 'Nederlands',
      pl: 'Polski',
      pt: 'Português',
    };
    const nameOf = (code: string) => (intl?.of?.(code) || fallback[code] || code.toUpperCase());
    return { nameOf };
  }, [i18n.language]);

  const langOptions = useMemo(
    () => availableLangs
      .map(code => ({ code, label: dn.nameOf(code) }))
      .sort((a, b) => a.label.localeCompare(b.label)),
    [availableLangs, dn]
  );

  const currentLangLabel = langPref === 'system'
    ? t('profile.common.system')
    : (dn.nameOf(langPref) || langPref.toUpperCase());

  const pickLanguage = (code: string) => {
    setLangPref(code);
    setLangOpen(false);
  };

  const updateReminderDays = async (days: number) => {
    if (loadingReminder) return;
    setLoadingReminder(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      const { error } = await supabase
        .from('profiles')
        .update({ reminder_days: days })
        .eq('id', user.id);

      if (error) throw error;

      setReminderDays(days);
      toast.success(t('profile.settings.reminderUpdated'));
    } catch (e: any) {
      toast.error(t('profile.settings.updateFailed'), e?.message ?? String(e));
    } finally {
      setLoadingReminder(false);
    }
  };

  const updateCurrency = async (code: string) => {
    if (loadingCurrency) return;
    setLoadingCurrency(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      const { error } = await supabase
        .from('profiles')
        .update({ currency: code })
        .eq('id', user.id);

      if (error) throw error;

      setCurrencyCode(code);
      setCurrencyOpen(false);
      toast.success(t('profile.settings.currencyUpdated', 'Currency preference updated'));
    } catch (e: any) {
      toast.error(t('profile.alerts.updateFailed', 'Update failed'), { text2: e?.message ?? String(e) });
    } finally {
      setLoadingCurrency(false);
    }
  };

  const toggleDigest = async () => {
    if (loadingDigest) return;
    setLoadingDigest(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      const newValue = !digestEnabled;
      const { error } = await supabase
        .from('profiles')
        .update({ notification_digest_enabled: newValue })
        .eq('id', user.id);

      if (error) throw error;

      setDigestEnabled(newValue);
      toast.success(t('profile.settings.digestUpdated', 'Daily digest preference updated'));
    } catch (e: any) {
      toast.error(t('profile.alerts.updateFailed', 'Update failed'), { text2: e?.message ?? String(e) });
    } finally {
      setLoadingDigest(false);
    }
  };

  const updateDigestHour = async (hour: number) => {
    if (loadingDigest) return;
    setLoadingDigest(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      const { error } = await supabase
        .from('profiles')
        .update({ digest_time_hour: hour })
        .eq('id', user.id);

      if (error) throw error;

      setDigestHour(hour);
      toast.success(t('profile.settings.digestTimeUpdated', 'Digest time updated'));
    } catch (e: any) {
      toast.error(t('profile.alerts.updateFailed', 'Update failed'), { text2: e?.message ?? String(e) });
    } finally {
      setLoadingDigest(false);
    }
  };

  const updateDigestFrequency = async (frequency: 'daily' | 'weekly') => {
    if (loadingDigest) return;
    setLoadingDigest(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      const { error } = await supabase
        .from('profiles')
        .update({ digest_frequency: frequency })
        .eq('id', user.id);

      if (error) throw error;

      setDigestFrequency(frequency);
      toast.success(t('profile.settings.digestFrequencyUpdated', 'Digest frequency updated'));
    } catch (e: any) {
      toast.error(t('profile.alerts.updateFailed', 'Update failed'), { text2: e?.message ?? String(e) });
    } finally {
      setLoadingDigest(false);
    }
  };

  const updateDigestDayOfWeek = async (day: number) => {
    if (loadingDigest) return;
    setLoadingDigest(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      const { error } = await supabase
        .from('profiles')
        .update({ digest_day_of_week: day })
        .eq('id', user.id);

      if (error) throw error;

      setDigestDayOfWeek(day);
      toast.success(t('profile.settings.digestDayUpdated', 'Digest day updated'));
    } catch (e: any) {
      toast.error(t('profile.alerts.updateFailed', 'Update failed'), { text2: e?.message ?? String(e) });
    } finally {
      setLoadingDigest(false);
    }
  };

  return (
    <View
      style={{
        margin: 16,
        marginTop: 10,
        backgroundColor: colors.card,
        borderRadius: 16,
        padding: 16,
        borderWidth: 1,
        borderColor: colors.border,
      }}
    >
      <Text style={{ fontSize: 18, fontWeight: '800', color: colors.text }}>
        {t('profile.settings.title')}
      </Text>

      {/* Push notifications */}
      {pushEnabled !== null && (
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: 8 }}>
          <Text style={{ fontWeight: '600', color: colors.text }}>{t('profile.settings.push')}</Text>
          <Pressable
            onPress={onTogglePush}
            style={{
              backgroundColor: pushEnabled ? '#2e95f1' : colors.card,
              paddingVertical: 8,
              paddingHorizontal: 12,
              borderRadius: 999,
              minWidth: 110,
              alignItems: 'center',
              opacity: working ? 0.7 : 1,
              borderWidth: pushEnabled ? 0 : 1,
              borderColor: pushEnabled ? 'transparent' : colors.border,
            }}
          >
            <Text style={{ color: pushEnabled ? '#fff' : colors.text, fontWeight: '700' }}>
              {inExpoGo ? t('profile.settings.pushUseDevBuild') : pushEnabled ? t('profile.common.on') : t('profile.common.off')}
            </Text>
          </Pressable>
        </View>
      )}

      {/* Purchase Reminders */}
      {reminderDays !== null && (
        <View style={{ marginTop: 12 }}>
          <Text style={{ fontWeight: '600', marginBottom: 6, color: colors.text }}>
            {t('profile.settings.purchaseReminders', 'Purchase Reminders')}
          </Text>
          <Text style={{ fontSize: 12, color: colors.text, opacity: 0.7, marginBottom: 8 }}>
            {t('profile.settings.purchaseRemindersDesc', 'Get notified to purchase claimed items before events')}
          </Text>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
            <Chip active={reminderDays === 0} label={t('profile.common.off')} onPress={() => updateReminderDays(0)} />
            <Chip active={reminderDays === 1} label={t('profile.common.1day')} onPress={() => updateReminderDays(1)} />
            <Chip active={reminderDays === 3} label={t('profile.common.3days')} onPress={() => updateReminderDays(3)} />
            <Chip active={reminderDays === 7} label={t('profile.common.7days')} onPress={() => updateReminderDays(7)} />
            <Chip active={reminderDays === 14} label={t('profile.common.14days')} onPress={() => updateReminderDays(14)} />
          </View>
        </View>
      )}

      {/* Activity Digest */}
      <View style={{ marginTop: 12 }}>
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 }}>
          <Text style={{ fontWeight: '600', color: colors.text }}>
            {t('profile.settings.activityDigest', 'Activity Digest')}
          </Text>
          <Pressable
            onPress={toggleDigest}
            disabled={loadingDigest}
            style={{
              backgroundColor: digestEnabled ? '#2e95f1' : colors.card,
              paddingVertical: 6,
              paddingHorizontal: 12,
              borderRadius: 999,
              minWidth: 70,
              alignItems: 'center',
              opacity: loadingDigest ? 0.7 : 1,
              borderWidth: digestEnabled ? 0 : 1,
              borderColor: digestEnabled ? 'transparent' : colors.border,
            }}
          >
            <Text style={{ color: digestEnabled ? '#fff' : colors.text, fontWeight: '700' }}>
              {digestEnabled ? t('profile.common.on') : t('profile.common.off')}
            </Text>
          </Pressable>
        </View>
        <Text style={{ fontSize: 12, color: colors.text, opacity: 0.7, marginBottom: 8 }}>
          {t('profile.settings.activityDigestDesc', 'Receive a summary of activity in your events')}
        </Text>
        {digestEnabled && (
          <>
            {/* Frequency selector */}
            <Text style={{ fontSize: 12, fontWeight: '600', marginBottom: 6, color: colors.text }}>
              {t('profile.settings.digestFrequency', 'Frequency')}
            </Text>
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginBottom: 12 }}>
              <Chip active={digestFrequency === 'daily'} label={t('profile.settings.daily', 'Daily')} onPress={() => updateDigestFrequency('daily')} />
              <Chip active={digestFrequency === 'weekly'} label={t('profile.settings.weekly', 'Weekly')} onPress={() => updateDigestFrequency('weekly')} />
            </View>

            {/* Day of week selector (only for weekly) */}
            {digestFrequency === 'weekly' && (
              <>
                <Text style={{ fontSize: 12, fontWeight: '600', marginBottom: 6, color: colors.text }}>
                  {t('profile.settings.digestDay', 'Day')}
                </Text>
                <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginBottom: 12 }}>
                  <Chip active={digestDayOfWeek === 1} label={t('profile.common.monday', 'Mon')} onPress={() => updateDigestDayOfWeek(1)} />
                  <Chip active={digestDayOfWeek === 2} label={t('profile.common.tuesday', 'Tue')} onPress={() => updateDigestDayOfWeek(2)} />
                  <Chip active={digestDayOfWeek === 3} label={t('profile.common.wednesday', 'Wed')} onPress={() => updateDigestDayOfWeek(3)} />
                  <Chip active={digestDayOfWeek === 4} label={t('profile.common.thursday', 'Thu')} onPress={() => updateDigestDayOfWeek(4)} />
                  <Chip active={digestDayOfWeek === 5} label={t('profile.common.friday', 'Fri')} onPress={() => updateDigestDayOfWeek(5)} />
                  <Chip active={digestDayOfWeek === 6} label={t('profile.common.saturday', 'Sat')} onPress={() => updateDigestDayOfWeek(6)} />
                  <Chip active={digestDayOfWeek === 0} label={t('profile.common.sunday', 'Sun')} onPress={() => updateDigestDayOfWeek(0)} />
                </View>
              </>
            )}

            {/* Time selector */}
            <Text style={{ fontSize: 12, fontWeight: '600', marginBottom: 6, color: colors.text }}>
              {t('profile.settings.digestTime', 'Delivery Time')}
            </Text>
            <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
              <Chip active={digestHour === 7} label="7:00" onPress={() => updateDigestHour(7)} />
              <Chip active={digestHour === 9} label="9:00" onPress={() => updateDigestHour(9)} />
              <Chip active={digestHour === 12} label="12:00" onPress={() => updateDigestHour(12)} />
              <Chip active={digestHour === 18} label="18:00" onPress={() => updateDigestHour(18)} />
              <Chip active={digestHour === 20} label="20:00" onPress={() => updateDigestHour(20)} />
            </View>
          </>
        )}
      </View>

      {/* Appearance */}
      <View style={{ marginTop: 12 }}>
        <Text style={{ fontWeight: '600', marginBottom: 6, color: colors.text }}>
          {t('profile.settings.appearance')}
        </Text>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
          <Chip active={themePref === 'light'}  label={t('profile.common.light')}  onPress={() => setThemePref('light')} />
          <Chip active={themePref === 'dark'}   label={t('profile.common.dark')}   onPress={() => setThemePref('dark')} />
        </View>
      </View>

      {/* Language — modal dropdown populated from i18n */}
      <View style={{ marginTop: 12 }}>
        <Text style={{ fontWeight: '600', marginBottom: 6, color: colors.text }}>
          {t('profile.settings.language')}
        </Text>

        {/* Field-like button */}
        <Pressable
          onPress={() => setLangOpen(true)}
          style={{
            borderWidth: 1,
            borderColor: colors.border,
            borderRadius: 10,
            paddingVertical: 12,
            paddingHorizontal: 12,
            backgroundColor: colors.card,
          }}
        >
          <Text style={{ fontWeight: '700', color: colors.text }}>{currentLangLabel}</Text>
        </Pressable>

        {/* Modal selector */}
        <Modal visible={langOpen} transparent animationType="fade" onRequestClose={() => setLangOpen(false)}>
          <Pressable
            onPress={() => setLangOpen(false)}
            style={{ flex: 1, backgroundColor: 'rgba(0,0,0,0.4)', justifyContent: 'center', padding: 20 }}
          >
            <Pressable
              onPress={() => {}}
              style={{ backgroundColor: colors.card, borderRadius: 12, maxHeight: '70%', overflow: 'hidden', borderWidth: 1, borderColor: colors.border }}
            >
              <View style={{ padding: 14, borderBottomWidth: 1, borderColor: colors.border }}>
                <Text style={{ fontSize: 16, fontWeight: '800', color: colors.text }}>
                  {t('profile.settings.language')}
                </Text>
              </View>

              <ScrollView>
                <LangRow
                  label={t('profile.common.system')}
                  selected={langPref === 'system'}
                  onPress={() => pickLanguage('system')}
                />
                {langOptions.map(({ code, label }) => (
                  <LangRow
                    key={code}
                    label={label}
                    selected={langPref === code}
                    onPress={() => pickLanguage(code)}
                  />
                ))}
              </ScrollView>

              <Pressable
                onPress={() => setLangOpen(false)}
                style={{ padding: 14, alignItems: 'center', borderTopWidth: 1, borderColor: colors.border }}
              >
                <Text style={{ fontWeight: '700', color: '#2e95f1' }}>{t('profile.common.ok')}</Text>
              </Pressable>
            </Pressable>
          </Pressable>
        </Modal>
      </View>

      {/* Currency — modal dropdown */}
      <View style={{ marginTop: 12 }}>
        <Text style={{ fontWeight: '600', marginBottom: 6, color: colors.text }}>
          {t('profile.settings.currency', 'Currency')}
        </Text>

        {/* Field-like button */}
        <Pressable
          onPress={() => setCurrencyOpen(true)}
          style={{
            borderWidth: 1,
            borderColor: colors.border,
            borderRadius: 10,
            paddingVertical: 12,
            paddingHorizontal: 12,
            backgroundColor: colors.card,
          }}
        >
          <Text style={{ fontWeight: '700', color: colors.text }}>
            {CURRENCIES[currencyCode]?.symbol} {CURRENCIES[currencyCode]?.name}
          </Text>
        </Pressable>

        {/* Modal selector */}
        <Modal visible={currencyOpen} transparent animationType="fade" onRequestClose={() => setCurrencyOpen(false)}>
          <Pressable
            onPress={() => setCurrencyOpen(false)}
            style={{ flex: 1, backgroundColor: 'rgba(0,0,0,0.4)', justifyContent: 'center', padding: 20 }}
          >
            <Pressable
              onPress={() => {}}
              style={{ backgroundColor: colors.card, borderRadius: 12, maxHeight: '70%', overflow: 'hidden', borderWidth: 1, borderColor: colors.border }}
            >
              <View style={{ padding: 14, borderBottomWidth: 1, borderColor: colors.border }}>
                <Text style={{ fontSize: 16, fontWeight: '800', color: colors.text }}>
                  {t('profile.settings.currency', 'Currency')}
                </Text>
              </View>

              <ScrollView>
                {getAllCurrencies().map((currency) => (
                  <CurrencyRow
                    key={currency.code}
                    currency={currency}
                    selected={currencyCode === currency.code}
                    onPress={() => updateCurrency(currency.code)}
                  />
                ))}
              </ScrollView>

              <Pressable
                onPress={() => setCurrencyOpen(false)}
                style={{ padding: 14, alignItems: 'center', borderTopWidth: 1, borderColor: colors.border }}
              >
                <Text style={{ fontWeight: '700', color: '#2e95f1' }}>{t('profile.common.ok')}</Text>
              </Pressable>
            </Pressable>
          </Pressable>
        </Modal>
      </View>
    </View>
  );
}

function LangRow({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) {
  const { colors } = useTheme();
  return (
    <Pressable
      onPress={onPress}
      style={{
        paddingVertical: 12,
        paddingHorizontal: 16,
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        borderBottomWidth: 1,
        borderColor: colors.border,
      }}
    >
      <Text style={{ fontSize: 15, color: colors.text }}>{label}</Text>
      {selected ? <Text style={{ fontWeight: '800', color: '#2e95f1' }}>✓</Text> : null}
    </Pressable>
  );
}

function CurrencyRow({ currency, selected, onPress }: { currency: Currency; selected: boolean; onPress: () => void }) {
  const { colors } = useTheme();
  return (
    <Pressable
      onPress={onPress}
      style={{
        paddingVertical: 12,
        paddingHorizontal: 16,
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        borderBottomWidth: 1,
        borderColor: colors.border,
      }}
    >
      <View>
        <Text style={{ fontSize: 15, color: colors.text, fontWeight: '600' }}>
          {currency.symbol} {currency.name}
        </Text>
        <Text style={{ fontSize: 12, color: colors.text, opacity: 0.6 }}>
          {currency.code}
        </Text>
      </View>
      {selected ? <Text style={{ fontWeight: '800', color: '#2e95f1' }}>✓</Text> : null}
    </Pressable>
  );
}

/* helpers */
async function ensurePushRegistered(): Promise<string | null> {
  let { status } = await Notifications.getPermissionsAsync();
  if (status !== 'granted') status = (await Notifications.requestPermissionsAsync()).status;
  if (status !== 'granted') return null;

  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('default', {
      name: 'Default',
      importance: Notifications.AndroidImportance.DEFAULT,
    });
  }

  const projectId =
    (Constants as any)?.expoConfig?.extra?.eas?.projectId ||
    (Constants as any)?.easConfig?.projectId;

  try {
    const token = await Notifications.getExpoPushTokenAsync({ projectId });
    return token.data || null;
  } catch (error) {
    // Fallback: try to get device push token (FCM token for Android)
    const deviceToken = (await Notifications.getDevicePushTokenAsync()).data;
    return deviceToken || null;
  }
}

async function savePushTokenToDb(token: string) {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;
    await supabase.from('push_tokens').upsert(
      { token, user_id: user.id, platform: Platform.OS },
      { onConflict: 'token' }
    );
  } catch {}
}
async function removePushTokenFromDb() {
  try {
    const token = await AsyncStorage.getItem('pref.pushToken');
    if (token) await supabase.from('push_tokens').delete().eq('token', token);
  } catch {}
}
