// src/screens/AddItemScreen.tsx
import { useState } from 'react';
import { View, Alert, Pressable, ActivityIndicator, Text } from 'react-native';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';
import { LabeledInput, LabeledPressableField } from '../components/LabeledInput';

export default function AddItemScreen({ route, navigation }: any) {
  const { listId } = route.params as { listId: string };

  const [name, setName] = useState('');
  const [url, setUrl] = useState('');
  const [price, setPrice] = useState('');
  const [notes, setNotes] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const parsePrice = (raw: string): number | null => {
    const trimmed = (raw ?? '').trim();
    if (!trimmed) return null;
    // keep digits and a single dot/comma
    const normalized = trimmed.replace(',', '.').replace(/[^\d.]/g, '');
    const n = Number(normalized);
    return Number.isFinite(n) ? n : null;
  };

  const add = async () => {
    if (submitting) return;
    if (!name.trim()) {
      toast.info('Item name required', 'Please enter a name.');
      return;
    }

    setSubmitting(true);
    try {
      const { data: { user }, error: userErr } = await supabase.auth.getUser();
      if (userErr) throw userErr;
      if (!user) throw new Error('Not signed in');

      const parsedPrice = parsePrice(price);
      if (price.trim() && parsedPrice === null) {
        toast.info('Invalid price', 'Enter a number like 19.99');
        setSubmitting(false);
        return;
      }

      // Build payload, only include fields your schema supports
      const payload: any = {
        list_id: listId,
        name: name.trim(),
        url: url.trim() ? url.trim() : null,
        price: parsedPrice,
        created_by: user.id, // helps with delete permissions
      };
      if (notes.trim()) payload.notes = notes.trim(); // include only if you have items.notes

      console.log('[AddItem] inserting', payload);
      const { data, error } = await supabase
        .from('items')
        .insert(payload)
        .select('id')     // force returning row
        .single();

      if (error) throw error;

      toast.success('Item added');
      navigation.goBack();
    } catch (e: any) {
      console.log('[AddItem] ERROR', e);
      const msg = e?.message ?? String(e);
      toast.error('Add failed', msg);
      Alert.alert('Error', msg);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <View style={{ padding: 16 }}>
      <LabeledInput
        label="Item name"
        placeholder="e.g. Noise-canceling headphones"
        value={name}
        onChangeText={setName}
      />

      <LabeledInput
        label="URL (optional)"
        placeholder="e.g. https://example.com/product"
        value={url}
        onChangeText={setUrl}
        keyboardType="url"
        autoCapitalize="none"
      />

      <LabeledInput
        label="Price (optional)"
        placeholder="e.g. 149.99"
        value={price}
        onChangeText={setPrice}
        keyboardType="decimal-pad"
      />

      <LabeledInput
        label="Notes (optional)"
        placeholder="e.g. Prefers over-ear style"
        value={notes}
        onChangeText={setNotes}
        multiline
      />
      <View >
        <Pressable
          onPress={add}
          disabled={submitting}
          style={{
            backgroundColor: '#2e95f1',
            paddingVertical: 10,
            paddingHorizontal: 16,
            borderRadius: 10,
            alignItems: 'center',
            opacity: submitting ? 0.7 : 1,
          }}
        >
          {submitting ? (
            <View style={{ flexDirection: 'row', alignItems: 'center' }}>
              <ActivityIndicator color="#fff" />
              <Text style={{ color: '#fff', fontWeight: '700', marginLeft: 8 }}>Adding…</Text>
            </View>
          ) : (
            <Text style={{ color: '#fff', fontWeight: '700' }}>Add</Text>
          )}
        </Pressable>
      </View>
    </View>
  );
}
