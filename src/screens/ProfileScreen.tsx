// src/screens/ProfileScreen.tsx
import React, { useCallback, useState } from 'react';
import { View, Text, ActivityIndicator, Alert, Pressable, ScrollView } from 'react-native';
import { useFocusEffect, useTheme } from '@react-navigation/native';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';
import { LabeledInput } from '../components/LabeledInput';
import PreferencesCard from '../components/PreferencesCard';
import { useTranslation } from 'react-i18next';
import { Screen } from '../components/Screen';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

export default function ProfileScreen({ navigation }: any) {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const [userId, setUserId] = useState<string>('');
  const [email, setEmail] = useState<string>('');
  const [createdAt, setCreatedAt] = useState<string>('');
  const [displayName, setDisplayName] = useState<string>('');

  const [eventsCount, setEventsCount] = useState<number>(0);
  const [listsCreated, setListsCreated] = useState<number>(0);
  const [deleting, setDeleting] = useState(false);
  const [signingOut, setSigningOut] = useState(false);

  const { colors } = useTheme();
  const { t } = useTranslation();
  const [initialized, setInitialized] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const insets = useSafeAreaInsets();
  const TAB_BAR_HEIGHT = 64; // adjust if your FancyTabBar height differs
  const bottomPad = insets.bottom + TAB_BAR_HEIGHT + 16;

  const load = useCallback(async () => {
    const firstLoad = !initialized;
    const wasRefreshing = !!refreshing;

    if (firstLoad) setLoading(true);

    const stopIndicators = () => {
      if (firstLoad) setLoading(false);
      if (wasRefreshing) setRefreshing(false);
      setInitialized(true);
    };

    const failsafe = setTimeout(stopIndicators, 8000);

    try {
      const { data: { session }, error: sessErr } = await supabase.auth.getSession();
      if (sessErr) throw sessErr;
      if (!session) return;

      const { data: { user }, error } = await supabase.auth.getUser();
      if (error) throw error;
      if (!user) return;

      setUserId(user.id);
      setEmail(user.email ?? '');
      setCreatedAt(new Date(user.created_at ?? Date.now()).toLocaleDateString());

      const { data: prof } = await supabase
        .from('profiles')
        .select('display_name')
        .eq('id', user.id)
        .maybeSingle();
      setDisplayName((prof?.display_name ?? '').trim());

      const { count: evCount } = await supabase
        .from('event_members')
        .select('*', { count: 'exact', head: true })
        .eq('user_id', user.id);
      setEventsCount(evCount ?? 0);

      const { count: lcCount } = await supabase
        .from('lists')
        .select('*', { count: 'exact', head: true })
        .eq('created_by', user.id);
      setListsCreated(lcCount ?? 0);
    } catch (e: any) {
      if (e?.name === 'AuthSessionMissingError') {
        clearTimeout(failsafe);
        stopIndicators();
        return;
      }
      console.log('[Profile] load error', e);
      toast.error(t('profile.alerts.loadFailedTitle', 'Load failed'), { text2: e?.message ?? String(e) });
    } finally {
      clearTimeout(failsafe);
      stopIndicators();
    }
  }, [initialized, refreshing, setInitialized, setLoading, setRefreshing]);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  const saveName = async () => {
    if (!displayName.trim()) {
      toast.error(t('profile.alerts.nameRequiredTitle'), { text2: t('profile.alerts.nameRequiredBody') });
      return;
    }
    setSaving(true);
    try {
      const { error: rpcErr } = await supabase.rpc('set_profile_name', { p_name: displayName.trim() });
      if (rpcErr && !String(rpcErr.message || '').toLowerCase().includes('function set_profile_name')) {
        throw rpcErr;
      }
      if (rpcErr) {
        const { error } = await supabase
          .from('profiles')
          .update({ display_name: displayName.trim() })
          .eq('id', userId);
        if (error) throw error;
      }
      toast.success(t('profile.alerts.saveOkTitle'), { text2: t('profile.alerts.saveOkBody') });
      await load();
    } catch (e: any) {
      console.log('[Profile] saveName error', e);
      toast.error(t('profile.alerts.saveErrTitle'), { text2: e?.message ?? String(e) });
    } finally {
      setSaving(false);
    }
  };

  const signOut = async () => {
    try {
      await supabase.auth.signOut();
      if (navigation.reset) {
        navigation.reset({ index: 0, routes: [{ name: 'Auth' }] });
      }
    } catch (e: any) {
      toast.error(t('profile.alerts.signOutErrTitle'), { text2: e?.message ?? String(e) });
    }
  };
  const handleSignOut = async () => {
    setSigningOut(true);
    try { await signOut(); } finally { setSigningOut(false); }
  };

  const handleDeleteAccount = async () => {
    const confirm = await new Promise<boolean>((resolve) => {
      Alert.alert(
        t('profile.alerts.deleteConfirmTitle'),
        t('profile.alerts.deleteConfirmBody'),
        [
          { text: t('profile.alerts.cancel'), style: 'cancel', onPress: () => resolve(false) },
          { text: t('profile.alerts.confirmDelete'), style: 'destructive', onPress: () => resolve(true) },
        ]
      );
    });
    if (!confirm) return;

    setDeleting(true);
    try {
      const { data, error } = await supabase.functions.invoke('delete-account', { body: {} });
      if (error || !data?.ok) {
        const ctx: any = (error as any)?.context;
        let msg = (data && data.error) || (error && (error as any).message) || 'Delete failed';
        if (ctx && typeof ctx.text === 'function') { try { msg = (await ctx.text()) || msg; } catch { } }
        Alert.alert(t('profile.alerts.deleteErrTitle'), msg);
        return;
      }
      await supabase.auth.signOut();
      Alert.alert(t('profile.alerts.deleteOkTitle'), t('profile.alerts.deleteOkBody'));
    } catch (e: any) {
      Alert.alert(t('profile.alerts.deleteErrTitle'), e?.message ?? String(e));
    } finally {
      setDeleting(false);
    }
  };

  if (loading) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator />
      </View>
    );
  }

  return (
    <Screen withTopSafeArea>
      <ScrollView style={{ flex: 1, backgroundColor: colors.background }} contentContainerStyle={{ paddingBottom: bottomPad }}>
        {/* Header card */}
        <View
          style={{
            margin: 16,
            backgroundColor: colors.card,
            borderRadius: 16,
            padding: 18,
            // keep your existing subtle shadow/elevation
            shadowColor: '#000',
            shadowOpacity: 0.05,
            shadowRadius: 10,
            elevation: 2,
            borderWidth: 1,
            borderColor: colors.border,
          }}
        >
          <Text style={{ fontSize: 18, fontWeight: '800', color: colors.text }}>{t('profile.title')}</Text>

          <Text style={{ marginTop: 8, color: colors.text, opacity: 0.7 }}>{t('profile.email')}</Text>
          <Text style={{ fontSize: 16, color: colors.text }}>{email || '—'}</Text>

          <View style={{ marginTop: 12 }}>
            <LabeledInput
              label={t('profile.displayName')}
              placeholder="e.g. Alice Johnson"
              value={displayName}
              onChangeText={setDisplayName}
            />
          </View>

          <View style={{ height: 8 }} />
          <Pressable
            onPress={saveName}
            disabled={saving}
            style={{
              backgroundColor: '#2e95f1', // keep brand blue
              paddingVertical: 10,
              paddingHorizontal: 16,
              borderRadius: 10,
              alignItems: 'center',
              opacity: saving ? 0.7 : 1,
            }}
          >
            {saving ? (
              <ActivityIndicator color="#fff" />
            ) : (
              <Text style={{ color: '#fff', fontWeight: '700' }}>{t('profile.saveName')}</Text>
            )}
          </Pressable>

          <View style={{ marginTop: 12, flexDirection: 'row', justifyContent: 'space-between' }}>
            <View>
              <Text style={{ color: colors.text, opacity: 0.7 }}>{t('profile.memberSince')}</Text>
              <Text style={{ fontWeight: '700', color: colors.text }}>{createdAt}</Text>
            </View>
          </View>
        </View>

        {/* Preferences / Settings */}
        <PreferencesCard />

        {/* Account / sign out */}
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
          <Text style={{ fontSize: 18, fontWeight: '800', color: colors.text }}>{t('profile.account')}</Text>
          <Pressable
            onPress={handleSignOut}
            disabled={signingOut}
            style={{
              backgroundColor: '#ef4444', // keep brand red
              marginTop: 20,
              paddingVertical: 10,
              paddingHorizontal: 16,
              borderRadius: 10,
              alignItems: 'center',
              opacity: signingOut ? 0.7 : 1,
            }}
          >
            {signingOut ? (
              <ActivityIndicator color="#fff" />
            ) : (
              <Text style={{ color: '#fff', fontWeight: '700' }}>{t('profile.signOut')}</Text>
            )}
          </Pressable>
        </View>

        {/* Danger zone */}
        <View style={{ marginTop: 10, paddingHorizontal: 16 }}>
          <View
            style={{
              backgroundColor: colors.card,
              borderRadius: 12,
              padding: 16,
              borderWidth: 1,
              borderColor: colors.border,
            }}
          >
            <Text style={{ fontSize: 18, fontWeight: '800', color: colors.text }}>{t('profile.dangerTitle')}</Text>
            <Text style={{ color: colors.text, opacity: 0.7, marginBottom: 12, marginTop: 20 }}>
              {t('profile.dangerDesc')}
            </Text>

            <Pressable
              onPress={handleDeleteAccount}
              disabled={deleting}
              style={{
                backgroundColor: '#ef4444', // keep brand red
                paddingVertical: 10,
                paddingHorizontal: 16,
                borderRadius: 10,
                alignItems: 'center',
                opacity: deleting ? 0.7 : 1,
              }}
            >
              {deleting ? (
                <ActivityIndicator color="#fff" />
              ) : (
                <Text style={{ color: '#fff', fontWeight: '700' }}>{t('profile.delete')}</Text>
              )}
            </Pressable>
          </View>
        </View>
      </ScrollView>
    </Screen>
  );
}
