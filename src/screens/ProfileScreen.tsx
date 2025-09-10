// src/screens/ProfileScreen.tsx
import React, { useCallback, useState } from 'react';
import { View, Text, TextInput, Button, ActivityIndicator, Alert, Pressable, Platform } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';
import { LabeledInput, LabeledPressableField } from '../components/LabeledInput';

export default function ProfileScreen({ navigation }: any) {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const [userId, setUserId] = useState<string>('');
  const [email, setEmail] = useState<string>('');
  const [createdAt, setCreatedAt] = useState<string>('');
  const [displayName, setDisplayName] = useState<string>('');

  const [eventsCount, setEventsCount] = useState<number>(0);
  const [listsCreated, setListsCreated] = useState<number>(0);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      // ✅ Guard: only proceed if there’s an auth session
      const { data: { session }, error: sessErr } = await supabase.auth.getSession();
      if (sessErr) throw sessErr;
      if (!session) {
        // RootNavigator will show Auth; don’t fetch or toast here.
        return;
      }

      // Who am I
      const { data: { user }, error } = await supabase.auth.getUser();
      if (error) throw error;
      if (!user) return;

      setUserId(user.id);
      setEmail(user.email ?? '');
      setCreatedAt(new Date(user.created_at ?? Date.now()).toLocaleDateString());

      // Profile
      const { data: prof } = await supabase
        .from('profiles')
        .select('display_name')
        .eq('id', user.id)
        .maybeSingle();
      setDisplayName((prof?.display_name ?? '').trim());

      // Counts
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
      if (e?.name === 'AuthSessionMissingError') return; // session vanished mid-load
      console.log('[Profile] load error', e);
      toast.error('Load failed', { text2: e?.message ?? String(e) });
    } finally {
      setLoading(false);
    }
  }, []);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  const saveName = async () => {
    if (!displayName.trim()) {
      toast.error('Name required', 'Please enter a display name.');
      return;
    }
    setSaving(true);
    try {
      // Prefer RPC if you have it; fall back to direct update
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
      toast.success('Saved', 'Your display name was updated.');
      await load();
    } catch (e: any) {
      console.log('[Profile] saveName error', e);
      toast.error('Save failed', e?.message ?? String(e));
    } finally {
      setSaving(false);
    }
  };

  const signOut = async () => {
    try {
      await supabase.auth.signOut();
      // If your navigator has an Auth route, reset to it:
      if (navigation.reset) {
        navigation.reset({ index: 0, routes: [{ name: 'Auth' }] });
      }
    } catch (e: any) {
      toast.error('Sign out failed', e?.message ?? String(e));
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
    <View style={{ flex: 1, backgroundColor: '#f6f8fa' }}>
      {/* Header card */}
      <View style={{ margin: 16, backgroundColor: 'white', borderRadius: 16, padding: 16, shadowColor: '#000', shadowOpacity: 0.05, shadowRadius: 10, elevation: 2 }}>
        <Text style={{ fontSize: 18, fontWeight: '800' }}>Profile</Text>

        <Text style={{ marginTop: 8, color: '#5b6b7b' }}>Email</Text>
        <Text style={{ fontSize: 16 }}>{email || '—'}</Text>

        <View style={{ marginTop: 12 }}>
          <LabeledInput
            label="Display name"
            placeholder="e.g. Alice Johnson"
            value={displayName}
            onChangeText={setDisplayName}
          />
        </View>

        <View style={{ height: 8 }} />
        <Button title={saving ? 'Saving…' : 'Save name'} onPress={saveName} disabled={saving} />

        <View style={{ marginTop: 12, flexDirection: 'row', justifyContent: 'space-between' }}>
          <View>
            <Text style={{ color: '#5b6b7b' }}>Member since</Text>
            <Text style={{ fontWeight: '700' }}>{createdAt}</Text>
          </View>
        </View>
      </View>

      {/* Stats cards */}
      <View style={{ marginHorizontal: 16, flexDirection: 'row' }}>
        <View style={{ flex: 1, backgroundColor: 'white', borderRadius: 16, padding: 16, marginRight: 6 }}>
          <Text style={{ color: '#5b6b7b' }}>Events</Text>
          <Text style={{ fontSize: 22, fontWeight: '800' }}>{eventsCount}</Text>
        </View>
        <View style={{ flex: 1, backgroundColor: 'white', borderRadius: 16, padding: 16, marginLeft: 6 }}>
          <Text style={{ color: '#5b6b7b' }}>Lists created</Text>
          <Text style={{ fontSize: 22, fontWeight: '800' }}>{listsCreated}</Text>
        </View>
      </View>

      {/* Danger zone */}
      <View style={{ margin: 16, backgroundColor: 'white', borderRadius: 16, padding: 16 }}>
        <Text style={{ fontWeight: '800', marginBottom: 8 }}>Account</Text>
        <Button color="#d9534f" title="Sign out" onPress={signOut} />
      </View>
    </View>
  );
}
