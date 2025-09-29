// src/screens/EventListScreen.tsx
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { View, Text, FlatList, Pressable, ActivityIndicator, RefreshControl, Alert } from 'react-native';
import { useFocusEffect, useTheme } from '@react-navigation/native';
import { LinearGradient } from 'expo-linear-gradient';
import { supabase } from '../lib/supabase';
import { Event } from '../types';
import AsyncStorage from '@react-native-async-storage/async-storage';
import EventCard from '../components/EventCard';
import { toast } from '../lib/toast';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';

type MemberRow = { event_id: string; user_id: string };

// Shape returned by public.events_for_current_user()
type EventsRPCRow = {
  id: string;
  title: string | null;
  event_date: string | null;
  join_code: string | null;
  created_at: string | null;
  member_count: number | null;
  total_items: number | null;
  claimed_count: number | null;
  accessible: boolean | null;
};

export default function EventListScreen({ navigation }: any) {
  const { colors } = useTheme();
  const [meName, setMeName] = useState<string>('there');
  const [events, setEvents] = useState<Event[]>([]);
  const [memberMap, setMemberMap] = useState<Record<string, MemberRow[]>>({});
  const [profileNames, setProfileNames] = useState<Record<string, string>>({});
  const [itemCountByEvent, setItemCountByEvent] = useState<Record<string, number>>({});
  const [claimsByEvent, setClaimsByEvent] = useState<Record<string, number>>({});
  const [unpurchasedByEvent, setUnpurchasedByEvent] = useState<Record<string, number>>({});
  const [accessibleByEvent, setAccessibleByEvent] = useState<Record<string, boolean>>({});
  const [loading, setLoading] = useState(true);
  const [initialized, setInitialized] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const insets = useSafeAreaInsets();
  const { t } = useTranslation();
  const HIT = { top: 12, bottom: 12, left: 12, right: 12 };

  const load = async () => {
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

      const { data: { user }, error: userErr } = await supabase.auth.getUser();
      if (userErr) throw userErr;
      const myId = user?.id ?? null;

      if (user) {
        const metaName = (user.user_metadata?.name ?? '').trim();
        const emailPrefix = (user.email?.split('@')[0] ?? 'there').trim();

        setMeName(metaName || emailPrefix);

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
            await supabase.rpc('set_profile_name', { p_name: metaName }).catch(() => {});
          }
        }

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

      // ---- Pull events + counts from RPC ----
      const { data: es, error: eErr } = await supabase.rpc('events_for_current_user');
      if (eErr) throw eErr;

      const rows = (es ?? []) as EventsRPCRow[];

      const minimalEvents: Event[] = rows.map(r => ({
        id: r.id,
        title: r.title ?? '',
        event_date: r.event_date as any,
        join_code: r.join_code ?? null,
        created_at: (r.created_at as any) ?? null,
      })) as Event[];
      setEvents(minimalEvents);

      const itemMap: Record<string, number> = {};
      const claimMap: Record<string, number> = {};
      const accessMap: Record<string, boolean> = {};
      rows.forEach(r => {
        itemMap[r.id] = Number(r.total_items ?? 0);
        claimMap[r.id] = Number(r.claimed_count ?? 0);
        accessMap[r.id] = !!r.accessible;
      });
      setItemCountByEvent(itemMap);
      setClaimsByEvent(claimMap);
      setAccessibleByEvent(accessMap);

      const eventIds = rows.map(r => r.id);

      // Members for avatars/counts
      if (eventIds.length) {
        const { data: members, error: mErr } = await supabase
          .from('event_members')
          .select('event_id,user_id')
          .in('event_id', eventIds);
        if (mErr) throw mErr;
        const mm: Record<string, MemberRow[]> = {};
        (members ?? []).forEach(m => { (mm[m.event_id] ||= []).push(m); });
        setMemberMap(mm);

        // display names for initials
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
      } else {
        setMemberMap({});
        setProfileNames({});
      }

      // ----- Unpurchased claims (for the third stat tile) -----
      if (eventIds.length) {
        const { data: lists, error: lErr } = await supabase
          .from('lists')
          .select('id,event_id')
          .in('event_id', eventIds);
        if (lErr) throw lErr;

        const listIds = (lists ?? []).map(l => l.id);
        const eventIdByList: Record<string, string> = {};
        (lists ?? []).forEach(l => { eventIdByList[l.id] = l.event_id; });

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

        const { data: unpurchasedClaims, error: upErr } = listIds.length
          ? await supabase
              .from('claims')
              .select('id,item_id,purchased,items!inner(list_id)')
              .eq('purchased', false)
              .in('items.list_id', listIds)
          : { data: [], error: null as any };
        if (upErr) throw upErr;

        const unpurchasedPerEvent: Record<string, number> = {};
        (unpurchasedClaims ?? []).forEach((cl: any) => {
          const listId = cl.items?.list_id as string | undefined;
          if (!listId) return;
          if (iAmRecipientOnList.has(listId)) return; // hide recipient lists
          const evId = eventIdByList[listId];
          if (!evId) return;
          unpurchasedPerEvent[evId] = (unpurchasedPerEvent[evId] || 0) + 1;
        });
        setUnpurchasedByEvent(unpurchasedPerEvent);
      } else {
        setUnpurchasedByEvent({});
      }

    } catch (err: any) {
      console.error('EventList load()', err);
      toast.error('Load error', { text2: err?.message ?? String(err) });
    } finally {
      clearTimeout(failsafe);
      stopIndicators();
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

  const toPurchaseCount = useMemo(
    () => Object.values(unpurchasedByEvent).reduce((a, b) => a + b, 0),
    [unpurchasedByEvent]
  );

  if (!initialized) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background }}>
        <ActivityIndicator />
      </View>
    );
  }

  const initialFor = (uid: string) => {
    const n = (profileNames[uid] ?? '').trim();
    if (!n) return 'U';
    const first = Array.from(n)[0];
    return first.toUpperCase();
  };

  const Avatar = ({ ch }: { ch: string }) => (
    <View
      style={{
        width: 24, height: 24, borderRadius: 12,
        backgroundColor: colors.card,
        borderWidth: 1,
        borderColor: colors.border,
        alignItems: 'center', justifyContent: 'center'
      }}
    >
      <Text style={{ fontWeight: '700', fontSize: 12, color: colors.text }}>{ch}</Text>
    </View>
  );

  // Simple stat tile that flips with theme
  function StatCard({ title, value }: { title: string; value: number | string }) {
    return (
      <View style={{ flex: 1, backgroundColor: 'white', paddingVertical: 14, borderRadius: 14, alignItems: 'center', justifyContent: 'center' }}>
        <Text style={{ fontSize: 20, fontWeight: '800' }}>{String(value)}</Text>
        <Text style={{ marginTop: 4, opacity: 0.7 }}>{title}</Text>
      </View>
    );
  }

  const onPressCreate = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) { navigation.navigate('Profile'); return; }

      const { data: allowed, error } = await supabase.rpc('can_create_event', { p_user: user.id });
      if (error) console.log('[Events] can_create_event error', error);

      if (allowed === false) {
        Alert.alert('Upgrade required', 'You can create up to 3 events on Free.');
        return;
      }
      navigation.navigate('CreateEvent');
    } catch {
      navigation.navigate('CreateEvent');
    }
  };

  return (
    <SafeAreaView edges={['bottom']} style={{ flex: 1, backgroundColor: colors.background }}>
      <View style={{ flex: 1, backgroundColor: colors.background }}>
        <LinearGradient
          colors={['#21c36b', '#2e95f1']}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 0 }}
          style={{ paddingTop: 48, paddingBottom: 16, paddingHorizontal: 16, borderBottomLeftRadius: 16, borderBottomRightRadius: 16 }}
        >
          <Text style={{ color: 'white', fontSize: 22, fontWeight: '700', marginBottom: 4 }}>
            {t('eventList.header.welcome')} {meName}!
          </Text>
          <Text style={{ color: 'white', opacity: 0.9 }}>{t('eventList.header.tagline')}</Text>

          <View style={{ flexDirection: 'row', gap: 12, marginTop: 16 }}>
            {/* make stat cards theme-aware but keep inside gradient, so use a light-ish surface */}
            <View style={{ flex: 1, backgroundColor: colors.card, paddingVertical: 14, borderRadius: 14, alignItems: 'center', justifyContent: 'center' }}>
              <Text style={{ fontSize: 20, fontWeight: '800', color: colors.text }}>{String(events.length)}</Text>
              <Text style={{ marginTop: 4, color: colors.text, opacity: 0.7 }}>{t('eventList.stats.activeEvents')}</Text>
            </View>
            <View style={{ flex: 1, backgroundColor: colors.card, paddingVertical: 14, borderRadius: 14, alignItems: 'center', justifyContent: 'center' }}>
              <Text style={{ fontSize: 20, fontWeight: '800', color: colors.text }}>{String(totalClaimsVisible)}</Text>
              <Text style={{ marginTop: 4, color: colors.text, opacity: 0.7 }}>{t('eventList.stats.itemsClaimed')}</Text>
            </View>
            <View style={{ flex: 1, backgroundColor: colors.card, paddingVertical: 14, borderRadius: 14, alignItems: 'center', justifyContent: 'center' }}>
              <Text style={{ fontSize: 20, fontWeight: '800', color: colors.text }}>{String(toPurchaseCount)}</Text>
              <Text style={{ marginTop: 4, color: colors.text, opacity: 0.7 }}>{t('eventList.stats.toPurchase')}</Text>
            </View>
          </View>
        </LinearGradient>

        <View style={{ paddingHorizontal: 16, paddingVertical: 12, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
          <Text style={{ fontSize: 16, fontWeight: '700', color: colors.text }}>{t('eventList.title')}</Text>
          <View style={{ flexDirection: 'row', alignItems: 'center' }}>
            <Pressable hitSlop={HIT} onPress={() => navigation.navigate('JoinEvent')} style={{ marginRight: 16 }}>
              <Text style={{ color: '#2e95f1', fontWeight: '600' }}>{t('eventList.toolbar.join')}</Text>
            </Pressable>
            <Pressable hitSlop={HIT} onPress={onPressCreate} style={{ marginRight: 16 }}>
              <Text style={{ color: '#2e95f1', fontWeight: '600' }}>{t('eventList.toolbar.create')}</Text>
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
            const isAccessible = accessibleByEvent[item.id] ?? true;

            const memberDisplayTokens = members.map(m => {
              const uid = m.user_id;
              const initial = initialFor(uid);
              return `${initial}:${uid}`;
            });

            const onPress = () => {
              if (!isAccessible) {
                Alert.alert('Upgrade required', 'You can access up to 3 events on Free.');
                return;
              }
              navigation.navigate('EventDetail', { id: item.id });
            };

            return (
              <EventCard
                title={item.title}
                date={item.event_date || undefined}
                createdAt={item.created_at || undefined}
                members={memberDisplayTokens}
                memberCount={members.length}
                claimed={claimCount}
                total={totalItems}
                onPress={onPress}
              />
            );
          }}
          ListEmptyComponent={
            <View style={{ alignItems: 'center', marginTop: 48 }}>
              <Text style={{ opacity: 0.6, color: colors.text }}>
                {t('eventList.empty.title')}{t('eventList.empty.body')}
              </Text>
            </View>
          }
        />
      </View>
    </SafeAreaView>
  );
}
