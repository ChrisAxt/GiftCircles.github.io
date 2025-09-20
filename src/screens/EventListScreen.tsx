// src/screens/EventListScreen.tsx
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { View, Text, FlatList, Pressable, ActivityIndicator, RefreshControl, Alert } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { LinearGradient } from 'expo-linear-gradient';
import { supabase } from '../lib/supabase';
import { Event } from '../types';
import AsyncStorage from '@react-native-async-storage/async-storage';
import EventCard from '../components/EventCard';
import { toast } from '../lib/toast';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { fetchClaimCountsByList } from '../lib/claimCounts';

// simple stat tile
function StatCard({ title, value }: { title: string; value: number | string }) {
  return (
    <View style={{ flex: 1, backgroundColor: 'white', paddingVertical: 14, borderRadius: 14, alignItems: 'center', justifyContent: 'center' }}>
      <Text style={{ fontSize: 20, fontWeight: '800' }}>{String(value)}</Text>
      <Text style={{ marginTop: 4, opacity: 0.7 }}>{title}</Text>
    </View>
  );
}

type MemberRow = { event_id: string; user_id: string };

export default function EventListScreen({ navigation }: any) {
  const [meName, setMeName] = useState<string>('there');
  const [events, setEvents] = useState<Event[]>([]);
  const [memberMap, setMemberMap] = useState<Record<string, MemberRow[]>>({});
  const [profileNames, setProfileNames] = useState<Record<string, string>>({});
  const [itemCountByEvent, setItemCountByEvent] = useState<Record<string, number>>({});
  const [claimsByEvent, setClaimsByEvent] = useState<Record<string, number>>({});
  const [loading, setLoading] = useState(true);
  const [initialized, setInitialized] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const insets = useSafeAreaInsets();

  const ensureProfileName = async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    // Fetch current display_name
    const { data: prof } = await supabase
      .from('profiles')
      .select('display_name')
      .eq('id', user.id)
      .maybeSingle();

    const emailPrefix = (user.email?.split('@')[0] ?? '').trim();
    const metaName = (user.user_metadata?.name ?? '').trim();

    // If display_name is missing or equals the email prefix, and we have a better name in metadata → set it
    if (metaName && (!prof?.display_name || prof.display_name === emailPrefix)) {
      await supabase.rpc('set_profile_name', { p_name: metaName });
    }
  };

  const load = async () => {
    setLoading(true);
    const failsafe = setTimeout(() => setLoading(false), 8000);

    try {
      // ✅ Guard: don’t fetch anything if there’s no session
      const { data: { session }, error: sessErr } = await supabase.auth.getSession();
      if (sessErr) throw sessErr;
      if (!session) {
        // RootNavigator will switch to Auth; just stop this load.
        return;
      }

      // who am I (for greeting)? -> prefer metadata.name immediately, then profile, then email
      const { data: { user }, error: userErr } = await supabase.auth.getUser();
      if (userErr) throw userErr;
      const myId = user?.id ?? null;
      console.log('user meta name:', user?.user_metadata?.name);

      if (user) {
        const metaName = (user.user_metadata?.name ?? '').trim();
        const emailPrefix = (user.email?.split('@')[0] ?? 'there').trim();

        // Show something right away
        setMeName(metaName || emailPrefix);

        // If profile missing or equals email prefix and we have a better name, set it
        if (metaName) {
          const { data: profMaybe } = await supabase
            .from('profiles')
            .select('display_name')
            .eq('id', user.id)
            .maybeSingle();

          const needsUpdate =
            !profMaybe?.display_name ||
            profMaybe.display_name.trim() === '' ||
            profMaybe.display_name.trim() === emailPrefix;

          if (needsUpdate) {
            // ok if this RPC doesn’t exist; you already have RLS update fallback elsewhere
            await supabase.rpc('set_profile_name', { p_name: metaName }).catch(() => {});
          }
        }

        // Re-read profile and prefer that going forward
        const { data: prof } = await supabase
          .from('profiles')
          .select('display_name')
          .eq('id', user.id)
          .maybeSingle();

        setMeName(
          (prof?.display_name ?? '').trim() ||
          (user.user_metadata?.name ?? '').trim() ||
          (user.email?.split('@')[0] ?? 'there').trim()
        );
      }

      // events visible via RLS
      const { data: es, error: eErr } = await supabase
        .from('events')
        .select('*')
        .order('created_at', { ascending: false });
      if (eErr) throw eErr;

      setEvents(es ?? []);
      const eventIds = (es ?? []).map(e => e.id);

      // members
      const { data: members, error: mErr } = await supabase
        .from('event_members')
        .select('event_id,user_id')
        .in('event_id', eventIds);
      if (mErr) throw mErr;
      const mm: Record<string, MemberRow[]> = {};
      (members ?? []).forEach(m => { (mm[m.event_id] ||= []).push(m); });
      setMemberMap(mm);

      // ---- NEW: fetch display names for these member user_ids
      const allUserIds = Array.from(new Set((members ?? []).map(m => m.user_id)));
      if (allUserIds.length) {
        const { data: ps, error: pErr } = await supabase
          .from('profiles')
          .select('id,display_name')
          .in('id', allUserIds);
        if (pErr) throw pErr;
        const map: Record<string, string> = {};
        (ps ?? []).forEach(p => { map[p.id] = (p.display_name ?? '').trim(); });
        setProfileNames(map);
      } else {
        setProfileNames({});
      }

      // lists → items
      const { data: lists, error: lErr } = await supabase
        .from('lists')
        .select('id,event_id')
        .in('event_id', eventIds);
      if (lErr) throw lErr;

      const listIds = (lists ?? []).map(l => l.id);
      const eventIdByList: Record<string, string> = {};
      (lists ?? []).forEach(l => { eventIdByList[l.id] = l.event_id; });

      const { data: items, error: iErr } = listIds.length
        ? await supabase.from('items').select('id,list_id').in('list_id', listIds)
        : { data: [], error: null as any };
      if (iErr) throw iErr;

      const itemIdsByEvent: Record<string, string[]> = {};
      (items ?? []).forEach((it) => {
        const evId = eventIdByList[it.list_id];
        if (!evId) return;
        (itemIdsByEvent[evId] ||= []).push(it.id);
      });
      const itemCount: Record<string, number> = {};
      Object.keys(itemIdsByEvent).forEach(evId => (itemCount[evId] = itemIdsByEvent[evId].length));
      setItemCountByEvent(itemCount);

      // ===== FIXED: claims per event =====
      // 1) Per-list claim counts
      const listClaimCounts = listIds.length ? await fetchClaimCountsByList(listIds) : {};

      // 2) If I’m a recipient on a list, hide its claim count from my totals (match EventDetail behavior)
      let iAmRecipientOnList = new Set<string>();
      if (myId && listIds.length) {
        const { data: myRecips, error: recipErr } = await supabase
          .from('list_recipients')
          .select('list_id')
          .in('list_id', listIds)
          .eq('user_id', myId);
        if (recipErr) throw recipErr;
        iAmRecipientOnList = new Set((myRecips ?? []).map(r => r.list_id));
      }

      // 3) Aggregate per-event
      const claimsPerEvent: Record<string, number> = {};
      for (const listId of listIds) {
        if (!eventIdByList[listId]) continue;
        const count = listClaimCounts[listId] ?? 0;
        // Skip lists where I'm a recipient
        if (iAmRecipientOnList.has(listId)) continue;
        claimsPerEvent[eventIdByList[listId]] = (claimsPerEvent[eventIdByList[listId]] || 0) + count;
      }
      setClaimsByEvent(claimsPerEvent);

    } catch (err: any) {
      console.error('EventList load()', err);
      // show details as text2
      toast.error('Load error', { text2: err?.message ?? String(err) });
    } finally {
      clearTimeout(failsafe);
      setLoading(false);
      setRefreshing?.(false);
      setInitialized?.(true);
    }
  };

  useFocusEffect(useCallback(() => { load(); }, []));
  useEffect(() => {
    const ch = supabase
      .channel('events-dashboard')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'events' }, load)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'event_members' }, load)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'lists' }, load)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'items' }, load)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'claims' }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, []);

  const totalClaimsVisible = useMemo(
    () => Object.values(claimsByEvent).reduce((a, b) => a + b, 0),
    [claimsByEvent]
  );

  if (!initialized) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator />
      </View>
    );
  }

  // Get the initial letter for a user id based on profiles.display_name
  const initialFor = (uid: string) => {
    const n = (profileNames[uid] ?? '').trim();
    if (!n) return 'U';               // fallback if no name yet
    const first = Array.from(n)[0];   // unicode-safe
    return first.toUpperCase();
  };

  // Small circular avatar with an initial
  const Avatar = ({ ch }: { ch: string }) => (
    <View
      style={{
        width: 24, height: 24, borderRadius: 12,
        backgroundColor: '#eef2f7',
        alignItems: 'center', justifyContent: 'center'
      }}
    >
      <Text style={{ fontWeight: '700', fontSize: 12 }}>{ch}</Text>
    </View>
  );

  return (
    <View style={{ flex: 1, backgroundColor: '#f6f8fa' }}>
      {/* Pretty gradient header */}
      <LinearGradient
        colors={['#21c36b', '#2e95f1']}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 0 }}
        style={{ paddingTop: 48, paddingBottom: 16, paddingHorizontal: 16, borderBottomLeftRadius: 16, borderBottomRightRadius: 16 }}
      >
        <Text style={{ color: 'white', fontSize: 22, fontWeight: '700', marginBottom: 4 }}>
          Welcome back, {meName}!
        </Text>
        <Text style={{ color: 'white', opacity: 0.9 }}>Coordinate gifts with ease</Text>

        <View style={{ flexDirection: 'row', gap: 12, marginTop: 16 }}>
          <StatCard title="Active Events" value={events.length} />
          <StatCard title="Items Claimed" value={totalClaimsVisible} />
        </View>
      </LinearGradient>

      <View style={{ paddingHorizontal: 16, paddingVertical: 12, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
        <Text style={{ fontSize: 16, fontWeight: '700' }}>Your Events</Text>
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <Pressable onPress={() => navigation.navigate('JoinEvent')} style={{ marginRight: 16 }}>
            <Text style={{ color: '#2e95f1', fontWeight: '600' }}>Join</Text>
          </Pressable>
          <Pressable onPress={() => navigation.navigate('CreateEvent')} style={{ marginRight: 16 }}>
            <Text style={{ color: '#2e95f1', fontWeight: '600' }}>Create</Text>
          </Pressable>
        </View>
      </View>
      <FlatList
        data={events}
        keyExtractor={(e) => e.id}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); load(); }} />}
        contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: insets.bottom + 24 }}
        renderItem={({ item }) => {
          const members = memberMap[item.id] ?? [];
          const totalItems = itemCountByEvent[item.id] || 0;
          const claimCount = claimsByEvent[item.id] || 0;
          const memberDisplayTokens = members.map(m => {
            const uid = m.user_id;
            const initial = initialFor(uid); // uses profileNames map you already populated
            return `${initial}:${uid}`;
          });
          return (
            <EventCard
              title={item.title}
              date={item.event_date || undefined}
              createdAt={item.created_at || undefined}
              members={memberDisplayTokens}
              memberCount={members.length}
              claimed={claimCount}
              total={totalItems}
              onPress={() => navigation.navigate('EventDetail', { id: item.id })}
            />
          );
        }}
        ListEmptyComponent={
          <View style={{ alignItems: 'center', marginTop: 48 }}>
            <Text style={{ opacity: 0.6 }}>No events yet. Create your first one!</Text>
          </View>
        }
      />
    </View>
  );
}
