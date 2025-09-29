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

const inExpoGo = Constants.appOwnership === 'expo';

export default function PreferencesCard() {
  const { colors } = useTheme();
  const { themePref, setThemePref, langPref, setLangPref } = useSettings();
  const [pushEnabled, setPushEnabled] = useState<boolean>(false);
  const [working, setWorking] = useState(false);
  const [langOpen, setLangOpen] = useState(false);
  const { t, i18n } = useTranslation();

  // Load cached push state
  React.useEffect(() => {
    AsyncStorage.getItem('pref.pushEnabled').then(v => setPushEnabled(v === '1'));
  }, []);
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
      Alert.alert('Not available in Expo Go', 'Install a development build to enable remote push notifications.');
      return;
    }
    setWorking(true);
    try {
      if (!pushEnabled) {
        const token = await ensurePushRegistered();
        if (!token) {
          Alert.alert('Permission needed', 'Enable notifications in system settings to receive alerts.');
          return;
        }
        await AsyncStorage.setItem('pref.pushToken', token);
        await savePushTokenToDb(token);
        await setPushLocal(true);
        toast.success('Notifications enabled');
      } else {
        await removePushTokenFromDb();
        await AsyncStorage.removeItem('pref.pushToken');
        await setPushLocal(false);
        toast.info('Notifications disabled');
      }
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
            {inExpoGo ? 'Use dev build' : pushEnabled ? 'On' : 'Off'}
          </Text>
        </Pressable>
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
                <Text style={{ fontWeight: '700', color: '#2e95f1' }}>OK</Text>
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

  const token = await Notifications.getExpoPushTokenAsync({ projectId });
  return token.data || null;
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
