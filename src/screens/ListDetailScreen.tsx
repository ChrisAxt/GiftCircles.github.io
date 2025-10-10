// src/screens/ListDetailScreen.tsx
import React, { useCallback, useEffect, useRef, useState } from 'react';
import { View, Text, FlatList, Button, ActivityIndicator, Alert, Pressable, Platform, Linking } from 'react-native';
import { useFocusEffect, useTheme } from '@react-navigation/native';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';
import ClaimButton from '../components/ClaimButton';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { Screen } from '../components/Screen';
import TopBar from '../components/TopBar';
import { formatPrice } from '../lib/currency';
import { useUserCurrency } from '../hooks/useUserCurrency';

type Item = {
  id: string;
  list_id: string;
  name: string;
  url?: string | null;
  price?: number | null;
  notes?: string | null;
  created_at?: string;
  created_by?: string | null;
};

type Claim = { id: string; item_id: string; claimer_id: string; created_at?: string };

export default function ListDetailScreen({ route, navigation }: any) {
  const { id } = route.params as { id: string };
  const { t } = useTranslation();
  const { colors } = useTheme();
  const currency = useUserCurrency();

  const [loading, setLoading] = useState(true);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [listName, setListName] = useState<string>(t('listDetail.title'));
  const [items, setItems] = useState<Item[]>([]);
  const [claimsByItem, setClaimsByItem] = useState<Record<string, Claim[]>>({});
  const [isRecipient, setIsRecipient] = useState(false);
  const [isOwner, setIsOwner] = useState(false);

  const [myUserId, setMyUserId] = useState<string | null>(null);
  const [isAdmin, setIsAdmin] = useState(false);
  const [listEventId, setListEventId] = useState<string | null>(null);
  const [eventMemberCount, setEventMemberCount] = useState<number>(0);

  const [claimedSummary, setClaimedSummary] = useState<{ claimed: number; unclaimed: number }>({ claimed: 0, unclaimed: 0 });
  const [claimedByName, setClaimedByName] = useState<Record<string, string>>({});
  const itemIdsRef = useRef<Set<string>>(new Set());
  const insets = useSafeAreaInsets();
  const [initialized, setInitialized] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    const firstLoad = !initialized;
    const wasRefreshing = !!refreshing;

    if (firstLoad) setLoading(true);
    setErrorMsg(null);

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
      if (!user) return;
      setMyUserId(user.id);

      // List
      const { data: listRow, error: listErr } = await supabase
        .from('lists')
        .select('id,name,created_by,event_id')
        .eq('id', id)
        .maybeSingle();
      if (listErr) throw listErr;
      if (!listRow) {
        setErrorMsg(t('listDetail.errors.notFound'));
        setItems([]); setClaimsByItem({}); setIsRecipient(false); setIsOwner(false);
        setClaimedByName({}); setClaimedSummary({ claimed: 0, unclaimed: 0 });
        itemIdsRef.current = new Set();
        return;
      }
      console.log('[ListDetail] List data:', {
        listId: listRow.id,
        created_by: listRow.created_by,
        currentUserId: user.id,
        isOwner: listRow.created_by === user.id
      });
      setListName(listRow.name || t('listDetail.title'));
      setIsOwner(listRow.created_by === user.id);
      setListEventId(listRow.event_id);

      if (listRow?.event_id) {
        const [{ data: mem }, { data: ev }, { count: memberCount }] = await Promise.all([
          supabase
            .from('event_members')
            .select('role')
            .eq('event_id', listRow.event_id)
            .eq('user_id', user.id)
            .maybeSingle(),
          supabase
            .from('events')
            .select('owner_id')
            .eq('id', listRow.event_id)
            .maybeSingle(),
          supabase
            .from('event_members')
            .select('*', { count: 'exact', head: true })
            .eq('event_id', listRow.event_id),
        ]);
        setIsAdmin(mem?.role === 'admin' || ev?.owner_id === user.id);
        setEventMemberCount(memberCount ?? 0);
      } else {
        setIsAdmin(false);
        setEventMemberCount(0);
      }

      // Items
      const { data: its, error: itemsErr } = await supabase
        .from('items')
        .select('id,list_id,name,url,price,notes,created_at,created_by')
        .eq('list_id', id)
        .order('created_at', { ascending: false });
      if (itemsErr) throw itemsErr;
      setItems(its ?? []);

      const itemIds = (its ?? []).map(i => i.id);
      itemIdsRef.current = new Set(itemIds);

      // Claims via RPC
      let claimsMap: Record<string, Claim[]> = {};
      if (itemIds.length) {
        const { data: claimRows, error: claimsErr } = await supabase
          .rpc('list_claims_for_user', { p_item_ids: itemIds });
        if (claimsErr) throw claimsErr;

        (claimRows ?? []).forEach((r: { item_id: string; claimer_id: string }) => {
          const arr = (claimsMap[r.item_id] ||= []);
          arr.push({
            id: `${r.item_id}:${r.claimer_id}`,
            item_id: r.item_id,
            claimer_id: r.claimer_id
          } as Claim);
        });
        setClaimsByItem(claimsMap);
      } else {
        setClaimsByItem({});
      }

      // Summary
      const totalItems = (its ?? []).length;
      const claimedCount = (its ?? []).reduce((acc, it) => acc + ((claimsMap[it.id]?.length ?? 0) > 0 ? 1 : 0), 0);
      setClaimedSummary({ claimed: claimedCount, unclaimed: Math.max(0, totalItems - claimedCount) });

      // Am I a recipient?
      const { data: r } = await supabase
        .from('list_recipients')
        .select('user_id')
        .eq('list_id', id)
        .eq('user_id', user.id)
        .maybeSingle();
      setIsRecipient(!!r);

      // Names for “Claimed by: Name”
      const claimerIds = Array.from(
        new Set(Object.values(claimsMap).flat().map(c => c.claimer_id).filter(Boolean))
      ) as string[];
      if (claimerIds.length) {
        const { data: profs, error: pErr } = await supabase
          .from('profiles')
          .select('id, display_name')
          .in('id', claimerIds);
        if (pErr) throw pErr;

        const nameById: Record<string, string> = {};
        (profs ?? []).forEach(p => { nameById[p.id] = (p.display_name ?? '').trim(); });

        const byItem: Record<string, string> = {};
        for (const [itemId, cl] of Object.entries(claimsMap)) {
          if (!cl?.length) continue;
          const first = cl[0];
          byItem[itemId] = nameById[first.claimer_id] || t('listDetail.item.someone');
        }
        setClaimedByName(byItem);
      } else {
        setClaimedByName({});
      }
    } catch (e: any) {
      if (e?.name === 'AuthSessionMissingError') {
        clearTimeout(failsafe);
        stopIndicators();
        return;
      }
      console.log('[ListDetail] load ERROR', e);
      setErrorMsg(t('listDetail.errors.load'));
      setIsOwner(false);
    } finally {
      clearTimeout(failsafe);
      stopIndicators();
    }
  }, [id, t, initialized, refreshing, setInitialized, setLoading, setRefreshing]);

  const canDeleteItem = useCallback((item: Item) => {
    if (!myUserId) return false;
    // Can delete if: item creator, list owner, event admin, OR last remaining member
    const isLastMember = eventMemberCount === 1;
    return item.created_by === myUserId || isOwner || isAdmin || isLastMember;
  }, [myUserId, isOwner, isAdmin, eventMemberCount]);

  const deleteItem = useCallback(async (item: Item) => {
    let confirmed = true;
    if (Platform.OS === 'web') {
      confirmed = typeof window !== 'undefined'
        ? window.confirm(`${t('listDetail.confirm.deleteItemTitle')}\n${t('listDetail.confirm.deleteItemBody', { name: item.name })}`)
        : true;
    } else {
      confirmed = await new Promise<boolean>((resolve) => {
        Alert.alert(
          t('listDetail.confirm.deleteItemTitle'),
          t('listDetail.confirm.deleteItemBody', { name: item.name }),
          [
            { text: 'Cancel', style: 'cancel', onPress: () => resolve(false) },
            { text: t('listDetail.actions.delete'), style: 'destructive', onPress: () => resolve(true) },
          ]
        );
      });
    }
    if (!confirmed) return;

    try {
      const { error: rpcErr } = await supabase.rpc('delete_item', { p_item_id: item.id });
      if (rpcErr) {
        const msg = String(rpcErr.message || rpcErr);
        if (msg.includes('not_authorized')) {
          toast.error(t('listDetail.errors.notAllowed'), t('listDetail.errors.cannotDeleteBody'));
        } else if (msg.includes('has_claims')) {
          toast.info(t('listDetail.errors.hasClaimsTitle'), t('listDetail.errors.hasClaimsBody'));
        } else if (msg.includes('not_found')) {
          toast.info(t('listDetail.errors.alreadyGoneTitle'), t('listDetail.errors.alreadyGoneBody'));
        } else {
          toast.error(t('listDetail.errors.deleteFailed'), msg);
        }
        await load();
        return;
      }

      toast.success(t('listDetail.success.itemDeleted'));
      await load();
    } catch (e: any) {
      toast.error(t('listDetail.errors.deleteFailed'), e?.message ?? String(e));
    }
  }, [load, t]);

  // realtime
  useEffect(() => {
    const ch = supabase
      .channel(`list-realtime-${id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'items', filter: `list_id=eq.${id}` }, () => load())
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'claims' }, () => load())
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'claims' }, () => load())
      .on('postgres_changes', { event: 'DELETE', schema: 'public', table: 'claims' }, () => load())
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [id, load]);

  // delete list
  const doDelete = useCallback(async () => {
    try {
      const { error } = await supabase.rpc('delete_list', { p_list_id: id });
      if (error) {
        const msg = String(error.message || error);
        if (msg.includes('not_authorized')) return toast.error(t('listDetail.errors.notAllowed'), { text2: t('listDetail.errors.cannotDeleteBody') });
        if (msg.includes('not_found')) return toast.error(t('listDetail.errors.notFound'));
        if (msg.includes('not_authenticated')) return toast.error(t('listDetail.errors.generic'), { text2: 'Please sign in and try again.' });
        return toast.error(t('listDetail.errors.deleteFailed'), { text2: msg });
      }
      toast.success(t('listDetail.success.listDeleted'));
      navigation.goBack();
    } catch (e: any) {
      toast.error(t('listDetail.errors.deleteFailed'), { text2: e?.message ?? String(e) });
    }
  }, [id, navigation, t]);

  const confirmDelete = useCallback(() => {
    if (Platform.OS === 'web') {
      const ok = typeof window !== 'undefined' && typeof window.confirm === 'function'
        ? window.confirm(`${t('listDetail.confirm.deleteListTitle')}\n${t('listDetail.confirm.deleteListBody')}`)
        : true;
      if (ok) doDelete();
      return;
    }
    Alert.alert(
      t('listDetail.confirm.deleteListTitle'),
      t('listDetail.confirm.deleteListBody'),
      [
        { text: 'Cancel', style: 'cancel' },
        { text: t('listDetail.actions.delete'), style: 'destructive', onPress: doDelete },
      ]
    );
  }, [doDelete, t]);

  // focus load
  useFocusEffect(useCallback(() => { load(); }, [load]));

  // ----------------- UI -----------------
  if (loading) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator />
      </View>
    );
  }

  if (errorMsg) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 16 }}>
        <Text style={{ fontSize: 16, textAlign: 'center' }}>{errorMsg}</Text>
        <View style={{ height: 12 }} />
        <Button title={t('listDetail.errors.goBack')} onPress={() => navigation.goBack()} />
      </View>
    );
  }

  const canDeleteList = isOwner || isAdmin || eventMemberCount === 1;

  return (
    <Screen>
      <TopBar
        title={listName || t('listDetail.screenTitle', 'List')}
        right={
          canDeleteList ? (
            <View style={{ flexDirection: 'row' }}>
              <Pressable onPress={() => navigation.navigate('EditList', { listId: id })} style={{ paddingHorizontal: 12, paddingVertical: 6 }}>
                <Text style={{ color: '#2e95f1', fontWeight: '700' }}>Edit</Text>
              </Pressable>
              <Pressable onPress={confirmDelete} style={{ paddingHorizontal: 12, paddingVertical: 6 }}>
                <Text style={{ color: '#d9534f', fontWeight: '700' }}>{t('listDetail.actions.delete')}</Text>
              </Pressable>
            </View>
          ) : null
        }
      />
      <View style={{ flex: 1, backgroundColor: colors.background, paddingTop: 16 }}>
        <View style={{ padding: 16 }}>
          <Pressable
            onPress={() => navigation.navigate('AddItem', { listId: id, listName })}
            style={{
              marginTop: -15,
              backgroundColor: '#2e95f1', // brand blue
              paddingVertical: 10,
              paddingHorizontal: 16,
              borderRadius: 10,
              alignItems: 'center',
            }}
          >
            <Text style={{ color: '#fff', fontWeight: '700' }}>{t('listDetail.actions.addItem')}</Text>
          </Pressable>
        </View>

        {/* Claimed/Unclaimed summary — hidden from recipients */}
        {!isRecipient && (
          <View style={{ paddingHorizontal: 16, paddingBottom: 8 }}>
            <Text style={{ fontWeight: '700', color: colors.text }}>
              {t('listDetail.summary.label', { claimed: claimedSummary.claimed, unclaimed: claimedSummary.unclaimed })}
            </Text>
          </View>
        )}

        <FlatList
          data={items}
          keyExtractor={(i) => String(i.id)}
          contentContainerStyle={{ paddingBottom: insets.bottom + 24 }}
          renderItem={({ item }) => {
            const claims = claimsByItem[item.id] ?? [];

            return (
              <Pressable
                onPress={(isOwner || isAdmin) ? () => navigation.navigate('EditItem', { itemId: item.id }) : undefined}
                style={{
                  marginHorizontal: 12,
                  marginVertical: 6,
                  backgroundColor: colors.card,
                  borderRadius: 12,
                  padding: 12,
                  borderWidth: 1,
                  borderColor: colors.border,
                  shadowColor: '#000',
                  shadowOpacity: 0.04,
                  shadowRadius: 6,
                  shadowOffset: { width: 0, height: 2 },
                }}
              >
                {/* Header: name + delete button */}
                <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
                  <Text style={{ fontSize: 16, fontWeight: '600', flex: 1, paddingRight: 8, color: colors.text }}>
                    {item.name}
                  </Text>

                  {canDeleteItem(item) && (
                    <Pressable
                      onPress={() => deleteItem(item)}
                      style={{ paddingVertical: 6, paddingHorizontal: 10, borderRadius: 999, backgroundColor: '#fdecef' }}
                    >
                      <Text style={{ color: '#c0392b', fontWeight: '700' }}>{t('listDetail.actions.delete')}</Text>
                    </Pressable>
                  )}
                </View>

                {/* URL / Price */}
                {item.url ? (
                  <Pressable
                    onPress={(e) => {
                      e.stopPropagation();
                      Linking.openURL(item.url!);
                    }}
                    style={{ maxWidth: '80%' }}
                  >
                    <Text numberOfLines={1} style={{ color: '#2e95f1', marginTop: 2, textDecorationLine: 'underline' }}>{item.url}</Text>
                  </Pressable>
                ) : null}
                {typeof item.price === 'number' ? (
                  <Text style={{ marginTop: 2, color: colors.text }}>{formatPrice(item.price, currency)}</Text>
                ) : null}
                {item.notes ? (
                  <Text style={{ marginTop: 4, color: colors.text, opacity: 0.8, fontStyle: 'italic' }}>{item.notes}</Text>
                ) : null}

                {/* Claim info & button (recipients can't see claimers) */}
                {!isRecipient ? (
                  <View style={{ marginTop: 10, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
                    <Text style={{ opacity: 0.7, color: colors.text }}>
                      {(() => {
                        const mine = myUserId ? claims.some(c => c.claimer_id === myUserId) : false;
                        if (!claims.length) return t('listDetail.item.notClaimed');
                        return mine
                          ? t('listDetail.item.claimedByYou')
                          : t('listDetail.item.claimedByName', { name: claimedByName[item.id] ?? t('listDetail.item.someone') });
                      })()}
                    </Text>

                    <ClaimButton
                      itemId={item.id}
                      claims={claimsByItem[item.id] ?? []}
                      meId={myUserId}
                      onChanged={load}
                    />
                  </View>
                ) : (
                  <Text style={{ marginTop: 8, fontStyle: 'italic', color: colors.text }}>
                    {t('listDetail.item.hiddenForRecipients')}
                  </Text>
                )}
              </Pressable>
            );
          }}
          ListEmptyComponent={
            <View style={{ alignItems: 'center', padding: 24 }}>
              <Text style={{ opacity: 0.6, color: colors.text }}>{t('listDetail.empty')}</Text>
            </View>
          }
        />
      </View>
    </Screen>
  );
}
