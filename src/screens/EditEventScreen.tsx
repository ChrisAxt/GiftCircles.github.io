// src/screens/EditEventScreen.tsx
// Requires (native): npx expo install @react-native-community/datetimepicker
import React, { useCallback, useEffect, useLayoutEffect, useState } from 'react';
import {
  View,
  Text,
  TextInput,
  Pressable,
  ActivityIndicator,
  Alert,
  Platform,
} from 'react-native';
import * as Clipboard from 'expo-clipboard';
import DateTimePicker from '@react-native-community/datetimepicker';
import { useTranslation } from 'react-i18next';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';
import { LabeledInput, LabeledPressableField } from '../components/LabeledInput';
import { Screen } from '../components/Screen';
import { useTheme } from '@react-navigation/native';
import TopBar from '../components/TopBar';
import { useSettings } from '../theme/SettingsProvider';

type EventRow = {
  id: string;
  title: string;
  event_date: string | null;
  join_code: string | null;
  owner_id: string | null;
};

function toYMD(date: Date): string {
  const y = date.getFullYear();
  const m = date.getMonth();
  const d = date.getDate();
  const utc = new Date(Date.UTC(y, m, d));
  return utc.toISOString().slice(0, 10); // YYYY-MM-DD
}

function safeParseDate(input?: string | null): Date | null {
  if (!input) return null;
  const parts = input.split('-').map(Number);
  if (parts.length === 3) {
    const [y, m, d] = parts;
    if (!isFinite(y) || !isFinite(m) || !isFinite(d)) return null;
    const dt = new Date(y, (m - 1), d, 12, 0, 0, 0);
    return isNaN(dt.getTime()) ? null : dt;
  }
  const dt = new Date(input);
  return isNaN(dt.getTime()) ? null : dt;
}

export default function EditEventScreen({ route, navigation }: any) {
  const { id } = route.params as { id: string };
  const { t, i18n } = useTranslation();
  const { colors } = useTheme();
  const { themePref } = useSettings();

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const [eventRow, setEventRow] = useState<EventRow | null>(null);
  const [title, setTitle] = useState('');
  const [dateValue, setDateValue] = useState<Date | null>(null);
  const [joinCode, setJoinCode] = useState('');

  const [isAdmin, setIsAdmin] = useState(false);
  const [showPicker, setShowPicker] = useState(false);

  useLayoutEffect(() => {
    navigation.setOptions({ title: t('editEvent.title') });
  }, [navigation, t, i18n.language]);

  const load = useCallback(async () => {
    setLoading(true);
    setErrorMsg(null);
    try {
      const { data: { session }, error: sessErr } = await supabase.auth.getSession();
      if (sessErr) throw sessErr;
      if (!session) { setErrorMsg(t('editEvent.messages.signInRequired')); return; }

      const { data: { user }, error: userErr } = await supabase.auth.getUser();
      if (userErr) throw userErr;
      if (!user) { setErrorMsg(t('editEvent.messages.signInRequired')); return; }

      const { data: row, error } = await supabase
        .from('events')
        .select('id,title,event_date,join_code,owner_id')
        .eq('id', id)
        .maybeSingle();
      if (error) throw error;
      if (!row) { setErrorMsg(t('editEvent.messages.notFound')); return; }

      const normalized: EventRow = {
        id: row.id,
        title: row.title ?? '',
        event_date: row.event_date ?? null,
        join_code: row.join_code ?? null,
        owner_id: row.owner_id ?? null,
      };
      setEventRow(normalized);
      setTitle(normalized.title);
      setDateValue(safeParseDate(normalized.event_date));
      setJoinCode(normalized.join_code ?? '');

      const { data: mem, error: mErr } = await supabase
        .from('event_members')
        .select('role')
        .eq('event_id', id)
        .eq('user_id', user.id)
        .maybeSingle();
      if (mErr) throw mErr;
      setIsAdmin(mem?.role === 'admin' || row.owner_id === user.id);
    } catch (e: any) {
      console.log('[EditEvent] load error', e);
      setErrorMsg(t('editEvent.messages.failedToLoad'));
    } finally {
      setLoading(false);
    }
  }, [id, t]);

  useEffect(() => { load(); }, [load]);

  const save = useCallback(async () => {
    if (!isAdmin) {
      return toast.error(t('editEvent.messages.notAllowed'), { text2: t('editEvent.messages.onlyAdmins') });
    }
    if (!title.trim()) {
      return Alert.alert(t('editEvent.messages.titleRequired'), t('editEvent.messages.enterTitle'));
    }

    setSaving(true);
    try {
      const patch: any = { title: title.trim() };
      patch.event_date = dateValue ? toYMD(dateValue) : null;

      const { data, error } = await supabase
        .from('events')
        .update(patch)
        .eq('id', id)
        .select('id,title,event_date')
        .single();

      if (error) throw error;
      if (!data) throw new Error('No row returned (RLS?)');

      toast.success(t('editEvent.messages.updated'));
      navigation.goBack();
    } catch (e: any) {
      console.log('[EditEvent] save error', e);
      toast.error(t('editEvent.messages.saveFailed'), { text2: e?.message ?? String(e) });
    } finally {
      setSaving(false);
    }
  }, [id, title, dateValue, isAdmin, navigation, t]);

  const copyJoinCode = useCallback(async () => {
    try {
      await Clipboard.setStringAsync(joinCode);
      toast.success(t('editEvent.messages.copied'));
    } catch {
      toast.error(t('editEvent.messages.copyFailed'));
    }
  }, [joinCode, t]);

  if (loading) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator />
      </View>
    );
  }

  if (errorMsg) {
    return (
      <View style={{ flex: 1, padding: 16, alignItems: 'center', justifyContent: 'center' }}>
        <Text style={{ fontSize: 16, textAlign: 'center', marginBottom: 16, color: colors.text }}>{errorMsg}</Text>
        <View style={{ flexDirection: 'row', gap: 12 }}>
          <Pressable
            onPress={load}
            style={{ paddingVertical: 10, paddingHorizontal: 16, backgroundColor: colors.card, borderRadius: 10, borderWidth: 1, borderColor: colors.border }}
          >
            <Text style={{ fontWeight: '700', color: '#2e95f1' }}>{t('editEvent.actions.retry')}</Text>
          </Pressable>
          <Pressable
            onPress={() => navigation.goBack()}
            style={{ paddingVertical: 10, paddingHorizontal: 16, borderRadius: 10, backgroundColor: colors.card, borderWidth: 1, borderColor: colors.border }}
          >
            <Text style={{ fontWeight: '700', color: colors.text }}>{t('editEvent.actions.back')}</Text>
          </Pressable>
        </View>
      </View>
    );
  }

  if (!eventRow) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <Text style={{ color: colors.text }}>{t('editEvent.messages.eventUnavailable')}</Text>
      </View>
    );
  }

  const webDateEditor = (
    <TextInput
      placeholder={t('editEvent.placeholders.date')}
      placeholderTextColor={colors.text + '99' /* muted */}
      value={dateValue ? toYMD(dateValue) : ''}
      onChangeText={(txt) => setDateValue(safeParseDate(txt))}
      editable={isAdmin}
      style={{
        borderWidth: 1,
        borderColor: colors.border,
        borderRadius: 8,
        padding: 10,
        backgroundColor: isAdmin ? colors.card : colors.card,
        opacity: isAdmin ? 1 : 0.6,
        color: colors.text,
      }}
    />
  );

  return (
    <Screen>
      <TopBar title={t('editEvent.screenTitle', 'Edit Event')} />
      <View style={{ padding: 16, gap: 12 }}>
        <Text style={{ fontSize: 16, fontWeight: '700', color: colors.text }}>{t('editEvent.title')}</Text>

        {/* Title */}
        <LabeledInput
          label={t('editEvent.labels.title')}
          placeholder={t('editEvent.placeholders.title')}
          value={title}
          onChangeText={setTitle}
          editable={isAdmin}
        />

        {/* Date */}
        {Platform.OS === 'web' ? (
          <View style={{ backgroundColor: colors.card, borderRadius: 12, padding: 12, borderWidth: 1, borderColor: colors.border }}>
            <Text style={{ fontWeight: '600', marginBottom: 6, color: colors.text }}>{t('editEvent.labels.date')}</Text>
            {webDateEditor}
          </View>
        ) : (
          <>
            <LabeledPressableField
              label={t('editEvent.labels.date')}
              placeholder={t('editEvent.placeholders.selectDate')}
              valueText={dateValue ? toYMD(dateValue) : undefined}
              onPress={() => isAdmin && setShowPicker(true)}
            />
            {showPicker && (
              <DateTimePicker
                value={dateValue ?? new Date()}
                mode="date"
                display={Platform.OS === 'ios' ? 'inline' : 'default'}
                themeVariant={themePref}
                onChange={(event: any, picked?: Date) => {
                  setShowPicker(false);
                  if (event?.type === 'dismissed') return;
                  if (picked) setDateValue(picked);
                }}
              />
            )}
          </>
        )}

        {/* Join code */}
        <View style={{ backgroundColor: colors.card, borderRadius: 12, padding: 12, borderWidth: 1, borderColor: colors.border }}>
          <Text style={{ fontWeight: '600', marginBottom: 6, color: colors.text }}>{t('editEvent.labels.joinCode')}</Text>
          <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
            <Text numberOfLines={1} style={{ flex: 1, marginRight: 12, opacity: 0.8, color: colors.text }}>
              {joinCode || '—'}
            </Text>
            <Pressable
              onPress={copyJoinCode}
              style={{ paddingVertical: 6, paddingHorizontal: 12, borderRadius: 999, backgroundColor: colors.card, borderWidth: 1, borderColor: colors.border }}
            >
              <Text style={{ fontWeight: '700', color: '#2e95f1' }}>{t('editEvent.actions.copy')}</Text>
            </Pressable>
          </View>
        </View>

        {/* Save */}
        <View style={{ marginTop: 12 }}>
          <Pressable
            onPress={save}
            disabled={!isAdmin || saving}
            style={{
              backgroundColor: !isAdmin ? colors.card : '#2e95f1',
              paddingVertical: 10,
              paddingHorizontal: 16,
              borderRadius: 10,
              alignItems: 'center',
              opacity: saving ? 0.7 : 1,
              borderWidth: !isAdmin ? 1 : 0,
              borderColor: !isAdmin ? colors.border : 'transparent',
            }}
          >
            {!isAdmin ? (
              <Text style={{ color: colors.text, fontWeight: '700' }}>{t('editEvent.states.viewOnly')}</Text>
            ) : saving ? (
              <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                <ActivityIndicator color="#fff" />
                <Text style={{ color: '#fff', fontWeight: '700', marginLeft: 8 }}>{t('editEvent.states.saving')}</Text>
              </View>
            ) : (
              <Text style={{ color: '#fff', fontWeight: '700' }}>{t('editEvent.actions.save')}</Text>
            )}
          </Pressable>
        </View>
      </View>
    </Screen>
  );
}
