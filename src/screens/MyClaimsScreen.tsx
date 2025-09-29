import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { View, Text, FlatList, Pressable, ActivityIndicator, Alert, RefreshControl } from 'react-native';
import { useFocusEffect, useTheme } from '@react-navigation/native';
import { supabase } from '../lib/supabase';
import { useTranslation } from 'react-i18next';
import { Screen } from '../components/Screen';

type ClaimRow = {
  id: string;
  item_id: string;
  purchased?: boolean | null;
  created_at?: string;
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
  const { t } = useTranslation();
  const { colors } = useTheme();

  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [claims, setClaims] = useState<ClaimRow[]>([]);
  const [myUserId, setMyUserId] = useState<string | null>(null);
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
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        setClaims([]);
        clearTimeout(failsafe);
        stopIndicators();
        return;
      }

      setMyUserId(user.id);

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
      clearTimeout(failsafe);
      stopIndicators();
    }
  }, [initialized, refreshing]);

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
        itemName: (it?.name ?? t('myClaims.fallbackItem')),
        listName: (ls?.name ?? t('myClaims.fallbackList')),
        eventTitle: (ev?.title ?? t('myClaims.fallbackEvent')),
      };
    });
  }, [claims, t]);

  const togglePurchased = async (claimId: string, current: boolean) => {
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
    } catch (e: any) {
      setClaims(prev =>
        prev.map(c => (c.id === claimId ? { ...c, purchased: current } : c))
      );
      Alert.alert(t('myClaims.updateFailed'), e?.message ?? String(e));
    }
  };

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
          <Text style={{ fontSize: 16, fontWeight: '700', color: colors.text }}>{t('myClaims.title')}</Text>
        </View>

        <FlatList
          data={rows}
          keyExtractor={(r) => r.claimId}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={() => { setRefreshing(true); load(); }}
            />
          }
          contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: 100 }}
          renderItem={({ item }) => (
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
              <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                <View style={{ flex: 1, paddingRight: 8 }}>
                  <Text style={{ fontSize: 16, fontWeight: '700', color: colors.text }}>{item.itemName}</Text>
                  <Text style={{ marginTop: 4, opacity: 0.75, color: colors.text }}>
                    {t('myClaims.line', { event: item.eventTitle, list: item.listName })}
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
                    {item.purchased ? t('myClaims.markNotPurchased') : t('myClaims.markPurchased')}
                  </Text>
                </Pressable>
              </View>
            </View>
          )}
          ListEmptyComponent={
            <View style={{ alignItems: 'center', marginTop: 48 }}>
              <Text style={{ opacity: 0.6, color: colors.text }}>{t('myClaims.empty')}</Text>
            </View>
          }
        />
      </View>
    </Screen>
  );
}
