import React, { useCallback, useEffect, useState } from 'react';
import { View, Text, FlatList, Pressable, ActivityIndicator, RefreshControl } from 'react-native';
import { useFocusEffect, useTheme } from '@react-navigation/native';
import { supabase } from '../lib/supabase';
import ListCard from '../components/ListCard';
import { useTranslation } from 'react-i18next';
import { Screen } from '../components/Screen';

type ListRow = { id: string; name: string; event_id: string };
type EventRow = { id: string; title: string | null };

export default function AllListsScreen({ navigation }: any) {
  const { t } = useTranslation();
  const { colors } = useTheme();

  const [lists, setLists] = useState<ListRow[]>([]);
  const [eventTitles, setEventTitles] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [initialized, setInitialized] = useState(false);

  const load = useCallback(async () => {
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
      clearTimeout(failsafe);
      stopIndicators();
    }
  }, [initialized, refreshing]);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  useEffect(() => {
    const ch = supabase
      .channel('all-lists')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'lists' }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [load]);

  if (loading && !refreshing) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background }}>
        <ActivityIndicator />
      </View>
    );
  }

  return (
    <Screen withTopSafeArea>
      <View style={{ flex: 1, backgroundColor: colors.background }}>
        <View style={{ paddingHorizontal: 16, paddingVertical: 12 }}>
          <Text style={{ fontSize: 16, fontWeight: '700', color: colors.text }}>{t('allLists.title')}</Text>
        </View>
        <FlatList
          data={lists}
          keyExtractor={(l) => l.id}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={() => { setRefreshing(true); load(); }}
            />
          }
          contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: 100 }}
          renderItem={({ item }) => {
            const eventTitle = eventTitles[item.event_id] || t('allLists.event');
            return (
              <Pressable onPress={() => navigation.navigate('ListDetail', { id: item.id })}>
                <View
                  style={{
                    backgroundColor: colors.card,
                    padding: 14,
                    borderRadius: 14,
                    marginBottom: 12,
                    borderWidth: 1,
                    borderColor: colors.border,
                    shadowColor: '#000',
                    shadowOpacity: 0.04,
                    shadowRadius: 6,
                    shadowOffset: { width: 0, height: 2 },
                  }}
                >
                  <Text style={{ fontSize: 16, fontWeight: '700', color: colors.text }}>{item.name}</Text>
                  <Text style={{ marginTop: 4, opacity: 0.7, color: colors.text }}>
                    {t('allLists.eventLabel', { title: eventTitle })}
                  </Text>
                </View>
              </Pressable>
            );
          }}
          ListEmptyComponent={
            <View style={{ alignItems: 'center', marginTop: 48 }}>
              <Text style={{ opacity: 0.6, color: colors.text }}>{t('allLists.empty')}</Text>
            </View>
          }
        />
      </View>
    </Screen>
  );
}
