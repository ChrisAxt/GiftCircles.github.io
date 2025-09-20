// src/screens/AllListsScreen.tsx
import React, { useCallback, useEffect, useState } from 'react';
import { View, Text, FlatList, Pressable, ActivityIndicator, RefreshControl } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { supabase } from '../lib/supabase';
import ListCard from '../components/ListCard';

type ListRow = { id: string; name: string; event_id: string };
type EventRow = { id: string; title: string | null };

export default function AllListsScreen({ navigation }: any) {
  const [lists, setLists] = useState<ListRow[]>([]);
  const [eventTitles, setEventTitles] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return;

      // Lists visible via RLS
      const { data: ls, error: lErr } = await supabase
        .from('lists')
        .select('id,name,event_id')
        .order('created_at', { ascending: false });
      if (lErr) throw lErr;
      setLists(ls ?? []);

      // Fetch event titles for the lists
      const eids = Array.from(new Set((ls ?? []).map(l => l.event_id)));
      if (eids.length) {
        const { data: es, error: eErr } = await supabase
          .from('events')
          .select('id,title')
          .in('id', eids);
        if (eErr) throw eErr;
        const map: Record<string, string> = {};
        (es ?? []).forEach((e: EventRow) => { map[e.id] = (e.title ?? '').trim(); });
        setEventTitles(map);
      } else {
        setEventTitles({});
      }

    } catch (e) {
      console.log('[AllLists] load error', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  useEffect(() => {
    const ch = supabase
      .channel('all-lists')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'lists' }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [load]);

  if (loading && !refreshing) {
    return <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}><ActivityIndicator /></View>;
  }

  return (
    <View style={{ flex: 1, backgroundColor: '#f6f8fa', marginTop:40 }}>
      <View style={{ paddingHorizontal: 16, paddingVertical: 12 }}>
        <Text style={{ fontSize: 16, fontWeight: '700' }}>All Lists</Text>
      </View>
      <FlatList
        data={lists}
        keyExtractor={(l) => l.id}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); load(); }} />}
        contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: 100 }}
        renderItem={({ item }) => {
          // We don’t have recipients here; we just show name + event title.
          const eventTitle = eventTitles[item.event_id] || 'Event';
          return (
            <Pressable onPress={() => navigation.navigate('ListDetail', { id: item.id })}>
              <View style={{
                backgroundColor: 'white', padding: 14, borderRadius: 14, marginBottom: 12,
                borderWidth: 1, borderColor: '#eef2f7', shadowColor: '#000', shadowOpacity: 0.04, shadowRadius: 6, shadowOffset: { width: 0, height: 2 },
              }}>
                <Text style={{ fontSize: 16, fontWeight: '700' }}>{item.name}</Text>
                <Text style={{ marginTop: 4, opacity: 0.7 }}>Event: {eventTitle}</Text>
              </View>
            </Pressable>
          );
        }}
        ListEmptyComponent={
          <View style={{ alignItems: 'center', marginTop: 48 }}>
            <Text style={{ opacity: 0.6 }}>No lists you can view yet.</Text>
          </View>
        }
      />
    </View>
  );
}
