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
import { requestClaimSplit } from '../lib/splitClaims';

type Item = {
  id: string;
  list_id: string;
  name: string;
  url?: string | null;
  price?: number | null;
  notes?: string | null;
  created_at?: string;
  created_by?: string | null;
  assigned_recipient_id?: string | null;
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
  const [randomAssignmentEnabled, setRandomAssignmentEnabled] = useState(false);
  const [randomAssignmentMode, setRandomAssignmentMode] = useState<string | null>(null);
  const [randomAssignmentExecutedAt, setRandomAssignmentExecutedAt] = useState<string | null>(null);
  const [isAssigning, setIsAssigning] = useState(false);
  const [randomReceiverAssignmentEnabled, setRandomReceiverAssignmentEnabled] = useState(false);
  const [isAssigningReceivers, setIsAssigningReceivers] = useState(false);
  const [recipientNames, setRecipientNames] = useState<Record<string, string>>({});

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
        .select('id,name,created_by,event_id,random_assignment_enabled,random_assignment_mode,random_assignment_executed_at,random_receiver_assignment_enabled')
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
      setListName(listRow.name || t('listDetail.title'));
      setIsOwner(listRow.created_by === user.id);
      setListEventId(listRow.event_id);
      setRandomAssignmentEnabled(listRow.random_assignment_enabled || false);
      setRandomAssignmentMode(listRow.random_assignment_mode || null);
      setRandomAssignmentExecutedAt(listRow.random_assignment_executed_at || null);
      setRandomReceiverAssignmentEnabled(listRow.random_receiver_assignment_enabled || false);

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
        .select('id,list_id,name,url,price,notes,created_at,created_by,assigned_recipient_id')
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

      // Names for "Claimed by: Name" (support multiple claimers)
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

          // Separate current user from others
          const youString = t('listDetail.item.you', 'You');
          const otherNames: string[] = [];
          let hasCurrentUser = false;

          cl.forEach(c => {
            if (c.claimer_id === user.id) {
              hasCurrentUser = true;
            } else {
              otherNames.push(nameById[c.claimer_id] || t('listDetail.item.someone'));
            }
          });

          // Build final name string with "You" always last
          const allNames = hasCurrentUser ? [...otherNames, youString] : otherNames;

          // Format names with "and" for multiple claimers
          if (allNames.length === 1) {
            byItem[itemId] = allNames[0];
          } else if (allNames.length === 2) {
            byItem[itemId] = allNames.join(` ${t('listDetail.item.and', 'and')} `);
          } else {
            const lastName = allNames[allNames.length - 1];
            const restNames = allNames.slice(0, -1);
            byItem[itemId] = `${restNames.join(', ')} ${t('listDetail.item.and', 'and')} ${lastName}`;
          }
        }
        setClaimedByName(byItem);
      } else {
        setClaimedByName({});
      }

      // Fetch recipient names for items with assigned recipients
      if (randomReceiverAssignmentEnabled) {
        const recipientIds = Array.from(
          new Set((its ?? []).map(i => i.assigned_recipient_id).filter(Boolean))
        ) as string[];

        if (recipientIds.length) {
          const { data: recipientProfs, error: recipientErr } = await supabase
            .from('profiles')
            .select('id, display_name')
            .in('id', recipientIds);
          if (recipientErr) throw recipientErr;

          const recipientNameById: Record<string, string> = {};
          (recipientProfs ?? []).forEach(p => {
            recipientNameById[p.id] = (p.display_name ?? '').trim() || 'Unknown';
          });
          setRecipientNames(recipientNameById);
        } else {
          setRecipientNames({});
        }
      } else {
        setRecipientNames({});
      }
    } catch (e: any) {
      if (e?.name === 'AuthSessionMissingError') {
        clearTimeout(failsafe);
        stopIndicators();
        return;
      }
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
          toast.error(t('listDetail.errors.notAllowed'), { text2: t('listDetail.errors.cannotDeleteBody') });
        } else if (msg.includes('has_claims')) {
          toast.info(t('listDetail.errors.hasClaimsTitle'), { text2: t('listDetail.errors.hasClaimsBody') });
        } else if (msg.includes('not_found')) {
          toast.info(t('listDetail.errors.alreadyGoneTitle'), { text2: t('listDetail.errors.alreadyGoneBody') });
        } else {
          toast.error(t('listDetail.errors.deleteFailed'), { text2: msg });
        }
        await load();
        return;
      }

      toast.success(t('listDetail.success.itemDeleted'), {});
      await load();
    } catch (e: any) {
      toast.error(t('listDetail.errors.deleteFailed'), { text2: e?.message ?? String(e) });
    }
  }, [load, t]);

  // Split request handler
  const handleRequestSplit = useCallback((item: Item) => {
    Alert.alert(
      t('splitRequest.confirmTitle', 'Request to Split Claim?'),
      t('splitRequest.confirmBody', { itemName: item.name }),
      [
        {
          text: t('splitRequest.cancel', 'Cancel'),
          style: 'cancel'
        },
        {
          text: t('splitRequest.send', 'Send Request'),
          onPress: async () => {
            try {
              await requestClaimSplit(item.id);
              toast.success(
                t('splitRequest.successTitle', 'Request Sent'),
                { text2: t('splitRequest.successBody', 'Your split request has been sent!') }
              );
              load(); // Refresh to show updated claims
            } catch (error: any) {
              const msg = String(error.message || error);

              if (msg.includes('Item is not claimed')) {
                Alert.alert(
                  t('splitRequest.errorTitle', 'Error'),
                  t('splitRequest.notClaimedError', 'This item is not claimed yet')
                );
              } else if (msg.includes('Cannot request to split your own claim')) {
                Alert.alert(
                  t('splitRequest.errorTitle', 'Error'),
                  t('splitRequest.ownClaimError', 'You cannot request to split your own claim')
                );
              } else if (msg.includes('You have already claimed this item')) {
                Alert.alert(
                  t('splitRequest.errorTitle', 'Error'),
                  t('splitRequest.alreadyClaimedError', 'You have already claimed this item')
                );
              } else if (msg.includes('already have a pending split request')) {
                Alert.alert(
                  t('splitRequest.errorTitle', 'Error'),
                  t('splitRequest.alreadyRequestedError', 'You already have a pending request for this item')
                );
              } else {
                Alert.alert(t('splitRequest.errorTitle', 'Error'), msg);
              }
            }
          }
        }
      ]
    );
  }, [t, load]);

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
        if (msg.includes('not_found')) return toast.error(t('listDetail.errors.notFound'), {});
        if (msg.includes('not_authenticated')) return toast.error(t('listDetail.errors.generic'), { text2: 'Please sign in and try again.' });
        return toast.error(t('listDetail.errors.deleteFailed'), { text2: msg });
      }
      toast.success(t('listDetail.success.listDeleted'), {});
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

  // Random receiver assignment handler
  const handleRandomReceiverAssignment = useCallback(async () => {
    if (!randomReceiverAssignmentEnabled) return;

    const confirmed = await new Promise<boolean>((resolve) => {
      if (Platform.OS === 'web') {
        const ok = typeof window !== 'undefined'
          ? window.confirm(`${t('listDetail.randomReceiverAssignment.confirmTitle')}\n${t('listDetail.randomReceiverAssignment.confirmBody')}`)
          : true;
        resolve(ok);
      } else {
        Alert.alert(
          t('listDetail.randomReceiverAssignment.confirmTitle', 'Assign Recipients Randomly?'),
          t('listDetail.randomReceiverAssignment.confirmBody', 'This will randomly assign a recipient to each item. Only givers will see who their item is for.'),
          [
            { text: t('eventList.alerts.cancel', 'Cancel'), style: 'cancel', onPress: () => resolve(false) },
            { text: t('listDetail.randomReceiverAssignment.assignButton', 'Assign'), onPress: () => resolve(true) },
          ]
        );
      }
    });

    if (!confirmed) return;

    setIsAssigningReceivers(true);
    try {
      const { error } = await supabase.rpc('execute_random_receiver_assignment', { p_list_id: id });

      if (error) {
        const msg = String(error.message || error);
        if (msg.includes('Need at least 2 members')) {
          toast.error(
            t('listDetail.randomReceiverAssignment.errorTitle', 'Assignment Failed'),
            { text2: t('listDetail.randomReceiverAssignment.needTwoMembers', 'Need at least 2 members to use random receiver assignment') }
          );
        } else if (msg.includes('not_authorized') || msg.includes('Only list creator or event admin')) {
          toast.error(
            t('listDetail.randomReceiverAssignment.errorTitle', 'Assignment Failed'),
            { text2: t('listDetail.errors.notAllowed', 'Not allowed') }
          );
        } else if (msg.includes('No items in list')) {
          toast.info(
            t('listDetail.randomReceiverAssignment.noItems', 'No Items'),
            { text2: t('listDetail.randomReceiverAssignment.noItemsBody', 'Add items to the list first') }
          );
        } else {
          toast.error(t('listDetail.randomReceiverAssignment.errorTitle', 'Assignment Failed'), { text2: msg });
        }
        return;
      }

      toast.success(
        t('listDetail.randomReceiverAssignment.successTitle', 'Recipients Assigned'),
        { text2: t('listDetail.randomReceiverAssignment.successBody', 'Each item has been assigned to a random recipient') }
      );

      await load();
    } catch (e: any) {
      toast.error(t('listDetail.randomReceiverAssignment.errorTitle', 'Assignment Failed'), { text2: e?.message ?? String(e) });
    } finally {
      setIsAssigningReceivers(false);
    }
  }, [id, randomReceiverAssignmentEnabled, t, load]);

  // Random assignment handler
  const handleRandomAssignment = useCallback(async () => {
    if (!randomAssignmentEnabled || !randomAssignmentMode) return;

    const modeText = randomAssignmentMode === 'one_per_member'
      ? t('listDetail.randomAssignment.modeOnePerMember', 'assign one item per member')
      : t('listDetail.randomAssignment.modeDistributeAll', 'distribute all items evenly');

    const confirmed = await new Promise<boolean>((resolve) => {
      if (Platform.OS === 'web') {
        const ok = typeof window !== 'undefined'
          ? window.confirm(`${t('listDetail.randomAssignment.confirmTitle')}\n${t('listDetail.randomAssignment.confirmBody', { mode: modeText })}`)
          : true;
        resolve(ok);
      } else {
        Alert.alert(
          t('listDetail.randomAssignment.confirmTitle', 'Assign Items Randomly?'),
          t('listDetail.randomAssignment.confirmBody', { mode: modeText }),
          [
            { text: t('eventList.alerts.cancel', 'Cancel'), style: 'cancel', onPress: () => resolve(false) },
            { text: t('listDetail.randomAssignment.assignButton', 'Assign'), onPress: () => resolve(true) },
          ]
        );
      }
    });

    if (!confirmed) return;

    setIsAssigning(true);
    try {
      const { data, error } = await supabase.rpc('assign_items_randomly', { p_list_id: id });

      if (error) {
        const msg = String(error.message || error);
        if (msg.includes('no_available_members')) {
          toast.error(
            t('listDetail.randomAssignment.errorTitle', 'Assignment Failed'),
            { text2: t('listDetail.randomAssignment.noMembers', 'No available members to assign items to') }
          );
        } else if (msg.includes('not_authorized')) {
          toast.error(
            t('listDetail.randomAssignment.errorTitle', 'Assignment Failed'),
            { text2: t('listDetail.errors.notAllowed', 'Not allowed') }
          );
        } else {
          toast.error(t('listDetail.randomAssignment.errorTitle', 'Assignment Failed'), { text2: msg });
        }
        return;
      }

      const result = data as any;
      if (result.assignments_made === 0) {
        toast.info(
          t('listDetail.randomAssignment.noNewItems', 'No New Items'),
          { text2: t('listDetail.randomAssignment.noItemsToAssign', 'All items have already been assigned') }
        );
      } else {
        toast.success(
          t('listDetail.randomAssignment.successTitle', 'Items Assigned'),
          { text2: t('listDetail.randomAssignment.successBody', { count: result.assignments_made, memberCount: result.member_count }) }
        );
      }

      await load();
    } catch (e: any) {
      toast.error(t('listDetail.randomAssignment.errorTitle', 'Assignment Failed'), { text2: e?.message ?? String(e) });
    } finally {
      setIsAssigning(false);
    }
  }, [id, randomAssignmentEnabled, randomAssignmentMode, t, load]);

  // Combined assignment handler (when both features are enabled)
  const handleCombinedAssignment = useCallback(async () => {
    if (!randomAssignmentEnabled || !randomReceiverAssignmentEnabled || !randomAssignmentMode) return;

    const modeText = randomAssignmentMode === 'one_per_member'
      ? t('listDetail.randomAssignment.modeOnePerMember', 'assign one item per member')
      : t('listDetail.randomAssignment.modeDistributeAll', 'distribute all items evenly');

    const message = t('listDetail.combinedAssignment.confirmBody', {
      defaultValue: 'This will:\n\n1. Randomly assign items to members ({{mode}})\n2. Randomly assign a recipient to each item\n\nOnly givers will see their assigned items and who they\'re for.',
      mode: modeText
    });

    const confirmed = await new Promise<boolean>((resolve) => {
      if (Platform.OS === 'web') {
        const ok = typeof window !== 'undefined'
          ? window.confirm(`${t('listDetail.combinedAssignment.confirmTitle', 'Assign Items & Recipients?')}\n${message}`)
          : true;
        resolve(ok);
      } else {
        Alert.alert(
          t('listDetail.combinedAssignment.confirmTitle', 'Assign Items & Recipients?'),
          message,
          [
            { text: t('eventList.alerts.cancel', 'Cancel'), style: 'cancel', onPress: () => resolve(false) },
            { text: t('listDetail.combinedAssignment.assignButton', 'Assign Both'), onPress: () => resolve(true) },
          ]
        );
      }
    });

    if (!confirmed) return;

    setIsAssigning(true);
    setIsAssigningReceivers(true);
    try {
      // First assign items to givers
      const { data: itemData, error: itemError } = await supabase.rpc('assign_items_randomly', { p_list_id: id });
      if (itemError) {
        throw itemError;
      }

      // Then assign recipients to items
      const { error: receiverError } = await supabase.rpc('execute_random_receiver_assignment', { p_list_id: id });
      if (receiverError) {
        throw receiverError;
      }

      const result = itemData as any;
      toast.success(
        t('listDetail.combinedAssignment.successTitle', 'Assignment Complete'),
        { text2: t('listDetail.combinedAssignment.successBody', {
          defaultValue: 'Assigned {{count}} items to {{memberCount}} members and assigned recipients to all items',
          count: result.assignments_made,
          memberCount: result.member_count
        }) }
      );

      await load();
    } catch (e: any) {
      const msg = String(e.message || e);
      if (msg.includes('no_available_members')) {
        toast.error(
          t('listDetail.combinedAssignment.errorTitle', 'Assignment Failed'),
          { text2: t('listDetail.randomAssignment.noMembers', 'No available members to assign items to') }
        );
      } else if (msg.includes('Need at least 2 members')) {
        toast.error(
          t('listDetail.combinedAssignment.errorTitle', 'Assignment Failed'),
          { text2: t('listDetail.randomReceiverAssignment.needTwoMembers', 'Need at least 2 members to use random receiver assignment') }
        );
      } else if (msg.includes('not_authorized')) {
        toast.error(
          t('listDetail.combinedAssignment.errorTitle', 'Assignment Failed'),
          { text2: t('listDetail.errors.notAllowed', 'Not allowed') }
        );
      } else {
        toast.error(t('listDetail.combinedAssignment.errorTitle', 'Assignment Failed'), { text2: msg });
      }
    } finally{
      setIsAssigning(false);
      setIsAssigningReceivers(false);
    }
  }, [id, randomAssignmentEnabled, randomReceiverAssignmentEnabled, randomAssignmentMode, t, load]);

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
  const canAssign = randomAssignmentEnabled && (isOwner || isAdmin);
  const canAssignReceivers = randomReceiverAssignmentEnabled && (isOwner || isAdmin);
  const hasBothAssignments = canAssign && canAssignReceivers;

  return (
    <Screen noPaddingBottom>
      <TopBar
        title={listName || t('listDetail.screenTitle', 'List')}
        right={
          canDeleteList || canAssign || canAssignReceivers ? (
            <View style={{ flexDirection: 'row' }}>
              {hasBothAssignments ? (
                // Show one combined button when both features are enabled
                <Pressable
                  onPress={handleCombinedAssignment}
                  disabled={isAssigning || isAssigningReceivers}
                  style={{ paddingHorizontal: 12, paddingVertical: 6 }}
                >
                  <Text style={{ color: (isAssigning || isAssigningReceivers) ? '#999' : '#9333ea', fontWeight: '700' }}>
                    {(isAssigning || isAssigningReceivers)
                      ? t('listDetail.combinedAssignment.assigning', 'Assigning...')
                      : t('listDetail.combinedAssignment.assignButton', 'Assign')}
                  </Text>
                </Pressable>
              ) : (
                <>
                  {canAssign && (
                    <Pressable
                      onPress={handleRandomAssignment}
                      disabled={isAssigning}
                      style={{ paddingHorizontal: 12, paddingVertical: 6 }}
                    >
                      <Text style={{ color: isAssigning ? '#999' : '#10b981', fontWeight: '700' }}>
                        {isAssigning ? t('listDetail.randomAssignment.assigning', 'Assigning...') : t('listDetail.randomAssignment.assignButton', 'Assign')}
                      </Text>
                    </Pressable>
                  )}
                  {canAssignReceivers && (
                    <Pressable
                      onPress={handleRandomReceiverAssignment}
                      disabled={isAssigningReceivers}
                      style={{ paddingHorizontal: 12, paddingVertical: 6 }}
                    >
                      <Text style={{ color: isAssigningReceivers ? '#999' : '#f59e0b', fontWeight: '700' }}>
                        {isAssigningReceivers ? t('listDetail.randomReceiverAssignment.assigning', 'Assigning...') : t('listDetail.randomReceiverAssignment.assignButton', 'Assign Recipients')}
                      </Text>
                    </Pressable>
                  )}
                </>
              )}
              {canDeleteList && (
                <>
                  <Pressable onPress={() => navigation.navigate('EditList', { listId: id })} style={{ paddingHorizontal: 12, paddingVertical: 6 }}>
                    <Text style={{ color: '#2e95f1', fontWeight: '700' }}>Edit</Text>
                  </Pressable>
                  <Pressable onPress={confirmDelete} style={{ paddingHorizontal: 12, paddingVertical: 6 }}>
                    <Text style={{ color: '#d9534f', fontWeight: '700' }}>{t('listDetail.actions.delete')}</Text>
                  </Pressable>
                </>
              )}
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

                {/* Recipient assignment info (only show to givers) */}
                {randomReceiverAssignmentEnabled && item.assigned_recipient_id && claims.some(c => c.claimer_id === myUserId) && (
                  <View style={{ marginTop: 8, padding: 8, backgroundColor: 'rgba(245, 158, 11, 0.1)', borderRadius: 8, borderLeftWidth: 3, borderLeftColor: '#f59e0b' }}>
                    <Text style={{ fontSize: 13, fontWeight: '600', color: colors.text }}>
                      {t('listDetail.item.forRecipient', 'This gift is for: ')}
                      <Text style={{ fontWeight: '700', color: '#f59e0b' }}>
                        {recipientNames[item.assigned_recipient_id] || 'Unknown'}
                      </Text>
                    </Text>
                  </View>
                )}

                {/* Claim info & button */}
                {/* In collaborative mode (both random features), everyone can see claims */}
                {/* In other modes, recipients can't see claimers */}
                {(!isRecipient || (randomAssignmentEnabled && randomReceiverAssignmentEnabled)) ? (
                  <View style={{ marginTop: 10, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
                    <Text style={{ opacity: 0.7, color: colors.text }}>
                      {(() => {
                        if (!claims.length) return t('listDetail.item.notClaimed');

                        // For random assignment: show "You" if you claimed it, otherwise "hidden"
                        if (randomAssignmentEnabled) {
                          const iClaimedIt = claims.some(c => c.claimer_id === myUserId);
                          if (iClaimedIt) {
                            return t('listDetail.item.claimedByYou', 'Claimed by: You');
                          }
                          return t('listDetail.item.claimedByHidden', 'Claimed by: hidden');
                        }

                        const claimerNames = claimedByName[item.id];
                        if (!claimerNames) return t('listDetail.item.notClaimed');

                        // Check if "You" is in the names (single or multiple)
                        const hasYou = claimerNames.includes(t('listDetail.item.you', 'You'));

                        // If single claim
                        if (claims.length === 1) {
                          return hasYou
                            ? t('listDetail.item.claimedByYou')
                            : t('listDetail.item.claimedByName', { name: claimerNames });
                        }

                        // If multiple claims (split claim), show full formatted names
                        return t('listDetail.item.claimedByName', { name: claimerNames });
                      })()}
                    </Text>

                    <ClaimButton
                      itemId={item.id}
                      claims={claimsByItem[item.id] ?? []}
                      meId={myUserId}
                      onChanged={load}
                      isRandomAssignment={randomAssignmentEnabled}
                      isAssignedToMe={randomAssignmentEnabled && claims.some(c => c.claimer_id === myUserId)}
                      onRequestSplit={() => handleRequestSplit(item)}
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
