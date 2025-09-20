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
  const [deleting, setDeleting] = useState(false);

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
  const [signingOut, setSigningOut] = useState(false);
  const handleSignOut = async () => {
    setSigningOut(true);
    try {
      await signOut();
    } finally {
      setSigningOut(false);
    }
  };

  if (loading) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator />
      </View>
    );
  }

  const handleDeleteAccount = async () => {
    // Step 1: Confirm
    const confirm = await new Promise<boolean>((resolve) => {
      Alert.alert(
        "Delete your account?",
        "This will permanently delete your profile, memberships, and sign you out.",
        [
          { text: "Cancel", style: "cancel", onPress: () => resolve(false) },
          { text: "Delete", style: "destructive", onPress: () => resolve(true) },
        ]
      );
    });
    if (!confirm) return;

    setDeleting(true);
    try {
      // Step 2: Call Edge Function (JWT is sent automatically by supabase client)
      const { data, error } = await supabase.functions.invoke("delete-account", { body: {} });

      if (error || !data?.ok) {
        // Try to read server's message if present
        const ctx: any = (error as any)?.context;
        let msg = (data && data.error) || (error && (error as any).message) || "Delete failed";
        if (ctx && typeof ctx.text === "function") {
          try { msg = (await ctx.text()) || msg; } catch {}
        }
        Alert.alert("Delete failed", msg);
        return;
      }

      // Step 3: Sign out locally
      await supabase.auth.signOut();
      Alert.alert("Account deleted", "Your account has been removed.");

    } catch (e: any) {
      Alert.alert("Delete failed", e?.message ?? String(e));
    } finally {
      setDeleting(false);
    }
  };


  return (
    <View style={{ flex: 1, backgroundColor: '#f6f8fa' }}>
      {/* Header card */}
      <View style={{ margin: 16, marginTop: 40, backgroundColor: 'white', borderRadius: 16, padding: 18, shadowColor: '#000', shadowOpacity: 0.05, shadowRadius: 10, elevation: 2 }}>
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
        <Pressable
          onPress={saveName}
          disabled={saving}
          style={{
            backgroundColor: '#2e95f1',
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
            <Text style={{ color: '#fff', fontWeight: '700' }}>Save name</Text>
          )}
        </Pressable>

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
      <View style={{ margin: 16, backgroundColor: 'white', borderRadius: 16, padding: 16, borderWidth: 1, borderColor: '#f1f5f9' }}>
        <Text style={{ fontSize: 16, fontWeight: '700', color: '#111827', marginBottom: 12 }}>Account</Text>

        <Pressable
          onPress={handleSignOut}
          disabled={signingOut}
          style={{
            backgroundColor: '#ef4444',
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
            <Text style={{ color: '#fff', fontWeight: '700' }}>Sign out</Text>
          )}
        </Pressable>
      </View>
      <View style={{ marginTop: 24, paddingHorizontal: 16 }}>
        <View style={{ backgroundColor: "white", borderRadius: 12, padding: 16, borderWidth: 1, borderColor: "#f1f5f9" }}>
          <Text style={{ fontSize: 16, fontWeight: "700", color: "#111827", marginBottom: 8 }}>Danger zone</Text>
          <Text style={{ color: "#6b7280", marginBottom: 12 }}>
            This will permanently delete your profile and remove you from events.
          </Text>

          <Pressable
            onPress={handleDeleteAccount}
            disabled={deleting}
            style={{
              backgroundColor: "#ef4444",
              paddingVertical: 10,
              paddingHorizontal: 16,
              borderRadius: 10,
              alignItems: "center",
              opacity: deleting ? 0.7 : 1,
            }}
          >
            {deleting ? (
              <ActivityIndicator color="#fff" />
            ) : (
              <Text style={{ color: "#fff", fontWeight: "700" }}>Delete account</Text>
            )}
          </Pressable>
        </View>
      </View>

    </View>
  );
}
