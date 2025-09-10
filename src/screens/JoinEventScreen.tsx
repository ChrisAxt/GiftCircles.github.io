// src/screens/JoinEventScreen.tsx
import React, { useState } from 'react';
import { View, Text, TextInput, Button, Alert } from 'react-native';
import { supabase } from '../lib/supabase';
import { LabeledInput, LabeledPressableField } from '../components/LabeledInput';

export default function JoinEventScreen({ navigation }: any) {
  const [code, setCode] = useState('');
  const [loading, setLoading] = useState(false);

  const join = async () => {
    const trimmed = code.trim();
    if (!trimmed) return Alert.alert('Enter a code', 'Paste the event join code.');
    setLoading(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not signed in');

      const { data: eventId, error } = await supabase.rpc('join_event', { p_code: trimmed });
      if (error) {
        if (String(error.message).toLowerCase().includes('invalid_join_code')) {
          return Alert.alert('Invalid code', 'That join code was not found.');
        }
        throw error;
      }

      // Go straight to the event you just joined
      navigation.replace('EventDetail', { id: eventId });
    } catch (err: any) {
      Alert.alert('Join failed', err?.message ?? String(err));
    } finally {
      setLoading(false);
    }
  };

  return (
    <View style={{ flex: 1, padding: 16, justifyContent: 'center', gap: 12 }}>
      <Text style={{ fontSize: 20, fontWeight: '700', marginBottom: 4 }}>Join an event</Text>

      <LabeledInput
        label="Enter join code"
        placeholder="e.g. 7G4K-MQ"
        value={code}
        onChangeText={setCode}
        autoCapitalize="characters"
      />

      <Button title={loading ? 'Joining…' : 'Join'} onPress={join} />
    </View>
  );
}
