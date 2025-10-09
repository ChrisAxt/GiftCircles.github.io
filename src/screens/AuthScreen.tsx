// src/screens/AuthScreen.tsx
import React, { useState } from 'react';
import { View, Text, TextInput, Button, Alert, Pressable } from 'react-native';
import { useTheme } from '@react-navigation/native';
import { supabase } from '../lib/supabase';

export default function AuthScreen() {
  const { colors } = useTheme();
  const [mode, setMode] = useState<'signin' | 'signup'>('signin');
  const [name, setName] = useState('');       // NEW
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);

  const signIn = async () => {
    setLoading(true);
    try {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) throw error;
      await ensureProfileNameFromMetadata();
    } catch (err: any) {
      Alert.alert('Sign-in error', err?.message ?? String(err));
    } finally {
      setLoading(false);
    }
  };

  const signUp = async () => {
    if (!name.trim()) {
      return Alert.alert('Missing name', 'Please enter your name.');
    }
    setLoading(true);
    try {
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: { name: name.trim() }, // stored as user metadata; our DB trigger will use this
        },
      });
      if (error) throw error;

      if (data.session?.user) {
        await supabase.rpc('set_profile_name', { p_name: name.trim() });
      }

      // If email confirmation is ON, there won't be a session yet — the DB trigger will create the profile row
      if (!data.session) {
        Alert.alert('Verify your email', 'We sent a confirmation link to your inbox.');
      }
      setMode('signin');
    } catch (err: any) {
      Alert.alert('Sign-up error', err?.message ?? String(err));
    } finally {
      setLoading(false);
    }
  };

  async function ensureProfileNameFromMetadata() {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;
    const metaName = (user.user_metadata?.name || '').trim();
    if (!metaName) return;
    await supabase.rpc('set_profile_name', { p_name: metaName });
  }




  return (
    <View style={{ flex: 1, justifyContent: 'center', padding: 16, gap: 12, backgroundColor: colors.background }}>
      <Text style={{ fontSize: 24, fontWeight: '600', marginBottom: 8, color: colors.text }}>GiftCircles</Text>

      {mode === 'signup' && (
        <TextInput
          placeholder="Full name"
          placeholderTextColor={colors.text + '80'}
          value={name}
          onChangeText={setName}
          autoCapitalize="words"
          style={{
            borderWidth: 1,
            borderColor: colors.border,
            padding: 10,
            borderRadius: 8,
            color: colors.text,
            backgroundColor: colors.card
          }}
        />
      )}

      <TextInput
        placeholder="Email"
        placeholderTextColor={colors.text + '80'}
        autoCapitalize="none"
        keyboardType="email-address"
        value={email}
        onChangeText={setEmail}
        style={{
          borderWidth: 1,
          borderColor: colors.border,
          padding: 10,
          borderRadius: 8,
          color: colors.text,
          backgroundColor: colors.card
        }}
      />
      <TextInput
        placeholder="Password"
        placeholderTextColor={colors.text + '80'}
        secureTextEntry
        value={password}
        onChangeText={setPassword}
        style={{
          borderWidth: 1,
          borderColor: colors.border,
          padding: 10,
          borderRadius: 8,
          color: colors.text,
          backgroundColor: colors.card
        }}
      />

      {mode === 'signin' ? (
        <>
          <Button title={loading ? '…' : 'Sign in'} onPress={signIn} />
          <Pressable onPress={() => setMode('signup')} style={{ padding: 8, alignItems: 'center' }}>
            <Text style={{ color: colors.primary }}>Create an account</Text>
          </Pressable>
        </>
      ) : (
        <>
          <Button title={loading ? '…' : 'Create account'} onPress={signUp} />
          <Pressable onPress={() => setMode('signin')} style={{ padding: 8, alignItems: 'center' }}>
            <Text style={{ color: colors.primary }}>Have an account? Sign in</Text>
          </Pressable>
        </>
      )}
    </View>
  );
}
