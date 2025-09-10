// src/screens/ListDetailScreen.tsx
import React, { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { View, Text, FlatList, Button, ActivityIndicator, Alert, Pressable, Platform } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';
import ClaimButton from '../components/ClaimButton';

type Item = {
  id: string;
  list_id: string;
  name: string;
  url?: string | null;
  price?: number | null;
  created_at?: string;
  created_by?: string | null;
};

type Claim = { id: string; item_id: string; claimer_id: string; created_at?: string };

export default function ListDetailScreen({ route, navigation }: any) {
  const { id } = route.params as { id: string };

  const [loading, setLoading] = useState(true);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [listName, setListName] = useState<string>('List');
  const [items, setItems] = useState<Item[]>([]);
  const [claimsByItem, setClaimsByItem] = useState<Record<string, Claim[]>>({});
  const [isRecipient, setIsRecipient] = useState(false);
  const [isOwner, setIsOwner] = useState(false);

  const [myUserId, setMyUserId] = useState<string | null>(null);
  const [isAdmin, setIsAdmin] = useState(false);
  const [listEventId, setListEventId] = useState<string | null>(null);

  const [claimedSummary, setClaimedSummary] = useState<{ claimed: number; unclaimed: number }>({ claimed: 0, unclaimed: 0 });
  const [claimedByName, setClaimedByName] = useState<Record<string, string>>({}); // (not shown in UI yet)
  const itemIdsRef = useRef<Set<string>>(new Set());

  const load = useCallback(async () => {
    setLoading(true);
    setErrorMsg(null);

    try {
      const { data: { session }, error: sessErr } = await supabase.auth.getSession();
      if (sessErr) throw sessErr;
      if (!session) return;

      const { data: { user }, error: userErr } = await supabase.auth.getUser();
      if (userErr) throw userErr;
      if (!user) return;
      setMyUserId(user.id);

      // List (for title + owner + event)
      const { data: listRow, error: listErr } = await supabase
        .from('lists')
        .select('id,name,created_by,event_id')
        .eq('id', id)
        .maybeSingle();
      if (listErr) throw listErr;
      if (!listRow) {
        setErrorMsg("This list doesn't exist or you don’t have access.");
        setItems([]); setClaimsByItem({}); setIsRecipient(false); setIsOwner(false);
        setClaimedByName({}); setClaimedSummary({ claimed: 0, unclaimed: 0 });
        itemIdsRef.current = new Set();
        return;
      }
      setListName(listRow.name || 'List');
      setIsOwner(listRow.created_by === user.id);
      setListEventId(listRow.event_id);

      if (listRow?.event_id) {
        const { data: mem } = await supabase
          .from('event_members')
          .select('role')
          .eq('event_id', listRow.event_id)
          .eq('user_id', user.id)
          .maybeSingle();
        setIsAdmin(mem?.role === 'admin' || mem?.role === 'owner');
      } else {
        setIsAdmin(false);
      }

      // Items (include created_by for delete perms)
      const { data: its, error: itemsErr } = await supabase
        .from('items')
        .select('id,list_id,name,url,price,created_at,created_by')
        .eq('list_id', id)
        .order('created_at', { ascending: false });
      if (itemsErr) throw itemsErr;
      setItems(its ?? []);

      const itemIds = (its ?? []).map(i => i.id);
      itemIdsRef.current = new Set(itemIds);

      // Claims
      let claimsMap: Record<string, Claim[]> = {};
      if (itemIds.length) {
        const { data: cls, error: claimsErr } = await supabase
          .from('claims')
          .select('*')
          .in('item_id', itemIds);
        if (claimsErr) throw claimsErr;
        (cls ?? []).forEach((c) => { (claimsMap[c.item_id] ||= []).push(c as Claim); });
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
          byItem[itemId] = nameById[first.claimer_id] || 'Someone';
        }
        setClaimedByName(byItem);
      } else {
        setClaimedByName({});
      }
    } catch (e: any) {
      if (e?.name === 'AuthSessionMissingError') return;
      console.log('[ListDetail] load ERROR', e);
      setErrorMsg(e?.message ?? 'Something went wrong while loading this list.');
      setIsOwner(false);
    } finally {
      setLoading(false);
    }
  }, [id]);

  // ------ permissions & delete handlers (component scope) ------
  const canDeleteItem = useCallback((item: Item) => {
    if (!myUserId) return false;
    return item.created_by === myUserId || isOwner || isAdmin;
  }, [myUserId, isOwner, isAdmin]);

  const deleteItem = useCallback(async (item: Item) => {
    console.log('[DeleteItem] pressed', { itemId: item.id, name: item.name });

    // Simple confirm (works on mobile & web)
    let confirmed = true;
    if (Platform.OS === 'web') {
      confirmed = typeof window !== 'undefined' ? window.confirm(`Delete "${item.name}"?`) : true;
    } else {
      confirmed = await new Promise<boolean>((resolve) => {
        Alert.alert(
          'Delete item?',
          `This will remove "${item.name}" and its claims.`,
          [
            { text: 'Cancel', style: 'cancel', onPress: () => resolve(false) },
            { text: 'Delete', style: 'destructive', onPress: () => resolve(true) },
          ]
        );
      });
    }
    if (!confirmed) {
      console.log('[DeleteItem] cancelled');
      return;
    }

    try {
      console.log('[DeleteItem] calling RPC delete_item', { p_item_id: item.id });
      const { error: rpcErr } = await supabase.rpc('delete_item', { p_item_id: item.id });
      console.log('[DeleteItem] RPC result', { rpcErr });

      if (rpcErr) {
        const msg = String(rpcErr.message || rpcErr);
        // Give a clear reason
        if (msg.includes('not_authorized')) {
          toast.error('Not allowed', 'You cannot delete this item.');
          return;
        }
        if (msg.includes('has_claims')) {
          toast.info('Cannot delete', 'Unclaim first or ask an admin/list owner.');
          return;
        }
        if (msg.includes('not_found')) {
          toast.info('Already gone', 'This item no longer exists.');
        } else {
          toast.error('Delete failed', msg);
        }

        // 🔧 Fallback: try direct delete so we can see any RLS error text
        console.log('[DeleteItem] trying direct delete fallback…');
        const { error: directErr } = await supabase.from('items').delete().eq('id', item.id);
        console.log('[DeleteItem] direct delete result', { directErr });
        if (directErr) {
          toast.error('Direct delete blocked', directErr.message ?? String(directErr));
        }
        await load();
        return;
      }

      toast.success('Item deleted');
      await load();
    } catch (e: any) {
      console.log('[DeleteItem] EXCEPTION', e);
      toast.error('Delete failed', e?.message ?? String(e));
    }
  }, [load]);


  // ------ realtime subscriptions ------
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

  const doDelete = useCallback(async () => {
    try {
      const { error } = await supabase.rpc('delete_list', { p_list_id: id });
      if (error) {
        const msg = String(error.message || error);
        if (msg.includes('not_authorized')) return toast.error('Not allowed', { text2: 'Only the list creator can delete this list.' });
        if (msg.includes('not_found')) return toast.error('Not found', { text2: 'This list no longer exists.' });
        if (msg.includes('not_authenticated')) return toast.error('Sign in required', { text2: 'Please sign in and try again.' });
        return toast.error('Delete failed', { text2: msg });
      }
      toast.success('List deleted');
      navigation.goBack();
    } catch (e: any) {
      toast.error('Delete failed', { text2: e?.message ?? String(e) });
    }
  }, [id, navigation]);

  const confirmDelete = useCallback(() => {
    if (Platform.OS === 'web') {
      const ok = typeof window !== 'undefined' && typeof window.confirm === 'function'
        ? window.confirm('Delete this list?\nThis will remove the list and all its items and claims. This cannot be undone.')
        : true;
      if (ok) doDelete();
      return;
    }
    Alert.alert(
      'Delete this list?',
      'This will remove the list and all its items and claims. This cannot be undone.',
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Delete', style: 'destructive', onPress: doDelete },
      ]
    );
  }, [doDelete]);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  useLayoutEffect(() => {
    navigation.setOptions({
      title: listName || 'List',
      headerRight: () =>
        isOwner ? (
          <Pressable onPress={confirmDelete} style={{ paddingHorizontal: 12, paddingVertical: 6 }}>
            <Text style={{ color: '#d9534f', fontWeight: '700' }}>Delete</Text>
          </Pressable>
        ) : null,
    });
  }, [navigation, listName, isOwner, confirmDelete]);

  // (Optional) local claim toggle helpers not used when ClaimButton component handles it

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
        <Button title="Go back" onPress={() => navigation.goBack()} />
      </View>
    );
  }

  return (
    <View style={{ flex: 1, backgroundColor: '#f6f8fa' }}>
      <View style={{ padding: 16 }}>
        <Button title="Add Item" onPress={() => navigation.navigate('AddItem', { listId: id, listName })} />
      </View>

      {/* Claimed/Unclaimed summary — hidden from recipients */}
      {!isRecipient && (
        <View style={{ paddingHorizontal: 16, paddingBottom: 8 }}>
          <Text style={{ fontWeight: '700' }}>
            Claimed: {claimedSummary.claimed} · Unclaimed: {claimedSummary.unclaimed}
          </Text>
        </View>
      )}

      <FlatList
        data={items}
        keyExtractor={(i) => String(i.id)}
        contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: 100 }}
        renderItem={({ item }) => {
          const claims = claimsByItem[item.id] ?? [];
          const claimed = claims.length > 0;

          return (
            <View style={{
              marginHorizontal: 12,
              marginVertical: 6,
              backgroundColor: 'white',
              borderRadius: 12,
              padding: 12,
              borderWidth: 1, borderColor: '#eef2f7',
              shadowColor: '#000', shadowOpacity: 0.04, shadowRadius: 6, shadowOffset: { width: 0, height: 2 },
            }}>
              {/* Header: name + delete */}
              <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
                <Text style={{ fontSize: 16, fontWeight: '600', flex: 1, paddingRight: 8 }}>
                  {item.name}
                </Text>

                {canDeleteItem(item) && (
                  <Pressable
                    onPress={() => deleteItem(item)}
                    style={{ paddingVertical: 6, paddingHorizontal: 10, borderRadius: 999, backgroundColor: '#fdecef' }}
                  >
                    <Text style={{ color: '#c0392b', fontWeight: '700' }}>Delete</Text>
                  </Pressable>
                )}
              </View>

              {/* URL / Price */}
              {item.url ? <Text selectable style={{ color: '#2e95f1', marginTop: 2 }}>{item.url}</Text> : null}
              {typeof item.price === 'number' ? <Text style={{ marginTop: 2 }}>${Number(item.price).toFixed(2)}</Text> : null}

              {/* Claim info & button (recipients can’t see claimers) */}
              {!isRecipient ? (
                <View style={{ marginTop: 10, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
                  <Text style={{ opacity: 0.7 }}>
                    {(() => {
                      const claims = claimsByItem[item.id] ?? [];
                      const claimed = claims.length > 0;
                      const mine = myUserId ? claims.some(c => c.claimer_id === myUserId) : false;
                      if (!claimed) return 'Not claimed yet';
                      return mine ? 'Claimed by: You' : `Claimed by: ${claimedByName[item.id] ?? 'Someone'}`;
                    })()}
                  </Text>

                  <ClaimButton
                    itemId={item.id}
                    claims={claimsByItem[item.id] ?? []}
                    meId={myUserId}          // 👈 pass current user id to compute mine/disabled
                    onChanged={load}
                  />
                </View>
              ) : (
                <Text style={{ marginTop: 8, fontStyle: 'italic' }}>
                  Who’s buying remains hidden from recipients.
                </Text>
              )}
            </View>
          );
        }}
        ListEmptyComponent={
          <View style={{ alignItems: 'center', padding: 24 }}>
            <Text style={{ opacity: 0.6 }}>No items yet.</Text>
          </View>
        }
      />
    </View>
  );
}
