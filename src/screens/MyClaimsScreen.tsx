// src/screens/MyClaimsScreen.tsx
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { View, Text, FlatList, Pressable, ActivityIndicator, Alert, RefreshControl } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { supabase } from '../lib/supabase';

type ClaimRow = {
  id: string;
  item_id: string;
  purchased?: boolean | null;
  created_at?: string;
  // nested (via select)
  item?: {
    id: string;
    name: string | null;
    list_id: string;
    list?: {
      id: string;
      name: string | null;
      event_id: string;
      event?: {
        id: string;
        title: string | null;
        event_date?: string | null;
      } | null;
    } | null;
  } | null;
};

type ClaimCard = {
  claimId: string;
  itemId: string;
  purchased: boolean;
  itemName: string;
  listName: string;
  eventTitle: string;
};

export default function MyClaimsScreen({ navigation }: any) {
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [claims, setClaims] = useState<ClaimRow[]>([]);
  const [myUserId, setMyUserId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) { setClaims([]); return; }
      setMyUserId(user.id);

      // Pull everything we need in one go (claims → items → lists → events)
      const { data: cs, error: cErr } = await supabase
        .from('claims')
        .select(`
          id, item_id, purchased, created_at,
          item:items (
            id, name, list_id,
            list:lists (
              id, name, event_id,
              event:events ( id, title, event_date )
            )
          )
        `)
        .eq('claimer_id', user.id)
        .order('created_at', { ascending: false });

      if (cErr) throw cErr;
      setClaims((cs ?? []) as unknown as ClaimRow[]);
    } catch (e) {
      console.log('[MyClaims] load error', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  useEffect(() => {
    const ch = supabase
      .channel('my-claims')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'claims' }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [load]);

  const rows: ClaimCard[] = useMemo(() => {
    return (claims ?? []).map(c => {
      const it = c.item;
      const ls = it?.list;
      const ev = ls?.event;

      return {
        claimId: c.id,
        itemId: c.item_id,
        purchased: !!c.purchased,
        itemName: (it?.name ?? 'Item'),
        listName: (ls?.name ?? 'List'),
        eventTitle: (ev?.title ?? 'Event'),
      };
    });
  }, [claims]);

  const togglePurchased = async (claimId: string, current: boolean) => {
    // optimistic update
    setClaims(prev =>
      prev.map(c => (c.id === claimId ? { ...c, purchased: !current } : c))
    );
    try {
      const { error } = await supabase
        .from('claims')
        .update({ purchased: !current })
        .eq('id', claimId)
        .eq('claimer_id', myUserId || '');
      if (error) throw error;
      // server will fan out realtime; load() keeps us consistent
    } catch (e: any) {
      // revert on error
      setClaims(prev =>
        prev.map(c => (c.id === claimId ? { ...c, purchased: current } : c))
      );
      Alert.alert('Update failed', e?.message ?? String(e));
    }
  };

  if (loading && !refreshing) {
    return <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}><ActivityIndicator /></View>;
  }

  return (
    <View style={{ flex: 1, backgroundColor: '#f6f8fa', marginTop: 40 }}>
      <View style={{ paddingHorizontal: 16, paddingVertical: 12 }}>
        <Text style={{ fontSize: 16, fontWeight: '700' }}>My claimed items</Text>
      </View>
      <FlatList
        data={rows}
        keyExtractor={(r) => r.claimId}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); load(); }} />}
        contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: 100 }}
        renderItem={({ item }) => (
          <View
            style={{
              backgroundColor: 'white',
              padding: 14,
              borderRadius: 14,
              marginBottom: 12,
              borderWidth: 1,
              borderColor: '#eef2f7',
              shadowColor: '#000',
              shadowOpacity: 0.04,
              shadowRadius: 6,
              shadowOffset: { width: 0, height: 2 },
            }}
          >
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start' }}>
              <View style={{ flex: 1, paddingRight: 8 }}>
                <Text style={{ fontSize: 16, fontWeight: '700' }}>{item.itemName}</Text>
                <Text style={{ marginTop: 4, opacity: 0.75 }}>
                  {item.eventTitle} · {item.listName}
                </Text>
              </View>
              <Pressable
                onPress={() => togglePurchased(item.claimId, item.purchased)}
                style={{
                  paddingVertical: 6,
                  paddingHorizontal: 12,
                  borderRadius: 999,
                  backgroundColor: item.purchased ? '#fde8e8' : '#e9f8ec',
                  borderWidth: 1,
                  borderColor: item.purchased ? '#f8c7c7' : '#bce9cb',
                  alignSelf: 'flex-start',
                }}
              >
                <Text style={{ fontWeight: '800', fontSize: 12, color: item.purchased ? '#c0392b' : '#1f9e4a' }}>
                  {item.purchased ? 'Mark not purchased' : 'Mark purchased'}
                </Text>
              </Pressable>
            </View>
          </View>
        )}
        ListEmptyComponent={
          <View style={{ alignItems: 'center', marginTop: 48 }}>
            <Text style={{ opacity: 0.6 }}>You haven’t claimed anything yet.</Text>
          </View>
        }
      />
    </View>
  );
}
