// src/screens/EditEventScreen.tsx
// Requires (native): npx expo install @react-native-community/datetimepicker
import React, { useCallback, useEffect, useState } from 'react';
import {
  View,
  Text,
  TextInput,
  Pressable,
  ActivityIndicator,
  Alert,
  Platform,
  Button
} from 'react-native';
import * as Clipboard from 'expo-clipboard';
import DateTimePicker from '@react-native-community/datetimepicker';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';
import { LabeledInput, LabeledPressableField } from '../components/LabeledInput';

type EventRow = {
  id: string;
  title: string;
  event_date: string | null; // stored as YYYY-MM-DD in DB
  join_code: string | null;
};

function toYMD(date: Date): string {
  // Avoid timezone shifting: build UTC date from Y/M/D
  const y = date.getFullYear();
  const m = date.getMonth();
  const d = date.getDate();
  const utc = new Date(Date.UTC(y, m, d));
  return utc.toISOString().slice(0, 10); // YYYY-MM-DD
}

function safeParseDate(input?: string | null): Date | null {
  if (!input) return null;
  // input is likely "YYYY-MM-DD"
  const parts = input.split('-').map(Number);
  if (parts.length === 3) {
    const [y, m, d] = parts;
    if (!isFinite(y) || !isFinite(m) || !isFinite(d)) return null;
    // Construct in local, but we later convert with toYMD
    const dt = new Date(y, (m - 1), d, 12, 0, 0, 0); // 12:00 to reduce DST edge cases
    return isNaN(dt.getTime()) ? null : dt;
  }
  // fallback generic parse
  const dt = new Date(input);
  return isNaN(dt.getTime()) ? null : dt;
}

export default function EditEventScreen({ route, navigation }: any) {
  const { id } = route.params as { id: string };

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const [eventRow, setEventRow] = useState<EventRow | null>(null);
  const [title, setTitle] = useState('');
  const [dateValue, setDateValue] = useState<Date | null>(null);
  const [joinCode, setJoinCode] = useState('');

  const [isAdmin, setIsAdmin] = useState(false);
  const [showPicker, setShowPicker] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setErrorMsg(null);
    try {
      const { data: { session }, error: sessErr } = await supabase.auth.getSession();
      if (sessErr) throw sessErr;
      if (!session) { setErrorMsg('Sign in required.'); return; }

      const { data: { user }, error: userErr } = await supabase.auth.getUser();
      if (userErr) throw userErr;
      if (!user) { setErrorMsg('Sign in required.'); return; }

      // Load event (no created_by column in your schema)
      const { data: row, error } = await supabase
        .from('events')
        .select('id,title,event_date,join_code')
        .eq('id', id)
        .maybeSingle();
      if (error) throw error;
      if (!row) { setErrorMsg("Event not found or you don't have access."); return; }

      const normalized: EventRow = {
        id: row.id,
        title: row.title ?? '',
        event_date: row.event_date ?? null,
        join_code: row.join_code ?? null,
      };
      setEventRow(normalized);
      setTitle(normalized.title);
      setDateValue(safeParseDate(normalized.event_date));
      setJoinCode(normalized.join_code ?? '');

      // Admin = role 'admin' on event_members
      const { data: mem, error: mErr } = await supabase
        .from('event_members')
        .select('role')
        .eq('event_id', id)
        .eq('user_id', user.id)
        .maybeSingle();
      if (mErr) throw mErr;
      setIsAdmin(mem?.role === 'admin');
    } catch (e: any) {
      console.log('[EditEvent] load error', e);
      setErrorMsg(e?.message ?? 'Failed to load event.');
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => { load(); }, [load]);

  const save = useCallback(async () => {
    if (!isAdmin) {
      return toast.error('Not allowed', { text2: 'Only event admins can edit.' });
    }
    if (!title.trim()) {
      return Alert.alert('Title required', 'Please enter a title.');
    }

    setSaving(true);
    try {
      const patch: any = { title: title.trim() };
      patch.event_date = dateValue ? toYMD(dateValue) : null;

      console.log('[EditEvent] saving patch', patch);

      const { data, error, status } = await supabase
        .from('events')
        .update(patch)
        .eq('id', id)
        .select('id,title,event_date')
        .single(); // force error if 0 rows

      console.log('[EditEvent] save result', { status, data, error });

      if (error) throw error;
      if (!data) throw new Error('No row returned (RLS?)');

      toast.success('Event updated');
      navigation.goBack();
    } catch (e: any) {
      console.log('[EditEvent] save error', e);
      toast.error('Save failed', { text2: e?.message ?? String(e) });
    } finally {
      setSaving(false);
    }
  }, [id, title, dateValue, isAdmin, navigation]);

  const copyJoinCode = useCallback(async () => {
    try {
      await Clipboard.setStringAsync(joinCode);
      toast.success('Join code copied');
    } catch {
      toast.error('Copy failed');
    }
  }, [joinCode]);

  // ---------- UI ----------

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
        <Text style={{ fontSize: 16, textAlign: 'center', marginBottom: 16 }}>{errorMsg}</Text>
        <View style={{ flexDirection: 'row', gap: 12 }}>
          <Pressable onPress={load} style={{ paddingVertical: 10, paddingHorizontal: 16, backgroundColor: '#eef2f7', borderRadius: 10 }}>
            <Text style={{ fontWeight: '700', color: '#2e95f1' }}>Retry</Text>
          </Pressable>
          <Pressable onPress={() => navigation.goBack()} style={{ paddingVertical: 10, paddingHorizontal: 16, borderRadius: 10, backgroundColor: '#f3f4f6' }}>
            <Text style={{ fontWeight: '700' }}>Back</Text>
          </Pressable>
        </View>
      </View>
    );
  }

  if (!eventRow) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <Text>Event unavailable.</Text>
      </View>
    );
  }

  // Web fallback editor for date (no native picker)
  const webDateEditor = (
    <TextInput
      placeholder="YYYY-MM-DD"
      value={dateValue ? toYMD(dateValue) : ''}
      onChangeText={(txt) => setDateValue(safeParseDate(txt))}
      editable={isAdmin}
      style={{
        borderWidth: 1,
        borderColor: '#e5e7eb',
        borderRadius: 8,
        padding: 10,
        backgroundColor: isAdmin ? 'white' : '#f3f4f6',
      }}
    />
  );

  return (
    <View style={{ flex: 1, backgroundColor: '#f6f8fa' }}>
      <View style={{ padding: 16, gap: 12 }}>
        <Text style={{ fontSize: 16, fontWeight: '700' }}>Edit Event</Text>

        {/* Title (labeled) */}
        <LabeledInput
          label="Title"
          placeholder="e.g. Bob’s Birthday"
          value={title}
          onChangeText={setTitle}
          editable={isAdmin}
        />

        {/* Date (labeled; native uses picker, web keeps your editor) */}
        {Platform.OS === 'web' ? (
          <View style={{ backgroundColor: 'white', borderRadius: 12, padding: 12, borderWidth: 1, borderColor: '#e5e7eb' }}>
            <Text style={{ fontWeight: '600', marginBottom: 6 }}>Date</Text>
            {webDateEditor}
          </View>
        ) : (
          <>
            <LabeledPressableField
              label="Date"
              placeholder="Select a date"
              valueText={dateValue ? toYMD(dateValue) : undefined}
              onPress={() => isAdmin && setShowPicker(true)}
            />
            {showPicker && (
              <DateTimePicker
                value={dateValue ?? new Date()}
                mode="date"
                display={Platform.OS === 'ios' ? 'inline' : 'default'}
                onChange={(event: any, picked?: Date) => {
                  setShowPicker(false);
                  if (event?.type === 'dismissed') return;
                  if (picked) setDateValue(picked);
                }}
              />
            )}
          </>
        )}

        {/* Join code (unchanged layout) */}
        <View style={{ backgroundColor: 'white', borderRadius: 12, padding: 12, borderWidth: 1, borderColor: '#e5e7eb' }}>
          <Text style={{ fontWeight: '600', marginBottom: 6 }}>Join code</Text>
          <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
            <Text numberOfLines={1} style={{ flex: 1, marginRight: 12, opacity: 0.8 }}>
              {joinCode || '—'}
            </Text>
            <Pressable
              onPress={copyJoinCode}
              style={{ paddingVertical: 6, paddingHorizontal: 12, borderRadius: 999, backgroundColor: '#eef2f7' }}
            >
              <Text style={{ fontWeight: '700', color: '#2e95f1' }}>Copy</Text>
            </Pressable>
          </View>
        </View>

        {/* Save */}
        <View style={{ marginTop: 12 }}>
          <Pressable
            onPress={save}
            disabled={!isAdmin || saving}
            style={{
              backgroundColor: !isAdmin ? '#eef2f7' : '#2e95f1',
              paddingVertical: 10,
              paddingHorizontal: 16,
              borderRadius: 10,
              alignItems: 'center',
              opacity: saving ? 0.7 : 1,
            }}
          >
            {!isAdmin ? (
              <Text style={{ color: '#1f2937', fontWeight: '700' }}>View only (not admin)</Text>
            ) : saving ? (
              <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                <ActivityIndicator color="#fff" />
                <Text style={{ color: '#fff', fontWeight: '700', marginLeft: 8 }}>Saving…</Text>
              </View>
            ) : (
              <Text style={{ color: '#fff', fontWeight: '700' }}>Save changes</Text>
            )}
          </Pressable>
        </View>

      </View>
    </View>
  );
}
