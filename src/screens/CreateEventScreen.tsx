// src/screens/CreateEventScreen.tsx
import React, { useState } from 'react';
import { View, TextInput, Button, Text, Pressable, Platform, Alert } from 'react-native';
import DateTimePicker, { DateTimePickerEvent } from '@react-native-community/datetimepicker';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';
import { LabeledInput, LabeledPressableField } from '../components/LabeledInput';

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
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState(''); // only sent if your schema has this column
  const [eventDate, setEventDate] = useState<Date | null>(null);
  const [showPicker, setShowPicker] = useState(false);
  const [loading, setLoading] = useState(false);

  // recurrence for the new feature
  const [recurrence, setRecurrence] = useState<'none'|'weekly'|'monthly'|'yearly'>('none');

  const onChangeDate = (_: DateTimePickerEvent, selected?: Date) => {
    if (Platform.OS === 'android') setShowPicker(false);
    if (selected) setEventDate(selected);
  };

  const create = async () => {
    if (!title.trim()) {
      return toast.info('Missing title', 'Please enter an event title.');
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
        p_recurrence: recurrence,                    // 'none' | 'weekly' | 'monthly' | 'yearly'
        p_description: description.trim() || null,   // optional
      });

      if (rpcErr) throw rpcErr;
      if (!newId) throw new Error('RPC returned no id');

      toast.success('Event created');
      navigation.replace('EventDetail', { id: newId as string });
    } catch (err: any) {
      console.log('[CreateEvent] ERROR', err);
      toast.error('Create failed', err?.message ?? String(err));
    } finally {
      setLoading(false);
    }
  };

  return (
    <View style={{ padding: 16 }}>
      <LabeledInput
        label="Title"
        placeholder="e.g. Bob’s Birthday"
        value={title}
        onChangeText={setTitle}
      />

      <LabeledInput
        label="Description (optional)"
        placeholder="e.g. Venue, theme, notes…"
        value={description}
        onChangeText={setDescription}
      />

      <LabeledPressableField
        label="Event date (optional)"
        placeholder="Select a date"
        valueText={eventDate ? pretty(eventDate) : undefined}
        onPress={() => setShowPicker(true)}
      />

      {/* Date picker */}
      {showPicker && (
        <>
          {Platform.OS === 'ios' && (
            <View style={{ alignItems: 'flex-end', marginBottom: 8 }}>
              <Pressable onPress={() => setShowPicker(false)}>
                <Text style={{ color: '#2e95f1', fontWeight: '600' }}>Done</Text>
              </Pressable>
            </View>
          )}
          <DateTimePicker
            value={eventDate ?? new Date()}
            mode="date"
            display={Platform.OS === 'ios' ? 'inline' : 'default'}
            onChange={onChangeDate}
          />
        </>
      )}

      {/* Recurrence selector */}
      <View style={{ backgroundColor: 'white', borderRadius: 12, padding: 12, marginTop: 12, borderWidth: 1, borderColor: '#e5e7eb' }}>
        <Text style={{ fontWeight: '600', marginBottom: 6 }}>Recurs</Text>
        <View style={{ flexDirection: 'row', gap: 8 }}>
          {(['none','weekly','monthly','yearly'] as const).map(opt => (
            <Pressable
              key={opt}
              onPress={() => setRecurrence(opt)}
              style={{
                paddingVertical: 8,
                paddingHorizontal: 12,
                borderRadius: 999,
                backgroundColor: recurrence === opt ? '#2e95f1' : '#eef2f7',
              }}
            >
              <Text style={{ color: recurrence === opt ? 'white' : '#1f2937', fontWeight: '700', textTransform: 'capitalize' }}>
                {opt}
              </Text>
            </Pressable>
          ))}
        </View>
      </View>

      <View style={{ marginTop: 12 }}>
        <Button title={loading ? 'Creating…' : 'Create'} onPress={create} disabled={loading} />
      </View>
    </View>
  );
}