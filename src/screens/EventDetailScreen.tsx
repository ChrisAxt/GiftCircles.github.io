// src/screens/EventDetailScreen.tsx
import React, { useCallback, useEffect, useMemo, useState, useLayoutEffect } from 'react';
import { View, Text, FlatList, Button, Pressable, Alert, ActivityIndicator, Share, Animated, Easing, ImageBackground } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { supabase } from '../lib/supabase';
import { Event } from '../types';
import ListCard from '../components/ListCard';
import { pickEventImage } from '../theme/eventImages';

type MemberRow = { event_id: string; user_id: string; role: 'giver' | 'recipient' | 'admin' };
type ListRow = { id: string; event_id: string; name: string };
type EventTheme = { key: string; colors: string[]; textColor: string; emoji?: string };
const IMAGE_OPACITY = 0.2;
function getEventTheme(title?: string): EventTheme {
  const t = (title || '').toLowerCase();
  if (/(x-?mas|christmas|noel)/.test(t)) return { key: 'christmas', colors: [], textColor: '#ffffff', emoji: '🎄' };
  if (/(birthday|b-?day|bday)/.test(t))  return { key: 'birthday',  colors: [], textColor: '#ffffff', emoji: '🎂' };
  if (/(wedding|marriage|anniversary)/.test(t)) return { key: 'wedding', colors: [], textColor: '#1f2937', emoji: '💍' };
  if (/(baby|shower)/.test(t))          return { key: 'baby',      colors: [], textColor: '#1f2937', emoji: '👶' };
  if (/(valentine|valentines)/.test(t)) return { key: 'valentine', colors: [], textColor: '#ffffff', emoji: '❤️' };
  if (/(easter)/.test(t))               return { key: 'easter',    colors: [], textColor: '#1f2937', emoji: '🐣' };
  if (/(new[-\s]?year)/.test(t))        return { key: 'newyear',   colors: [], textColor: '#ffffff', emoji: '🥂' };
  return { key: 'default', colors: [], textColor: '#111111' };
}

export default function EventDetailScreen({ route, navigation }: any) {
  const { id } = route.params as { id: string }; // event id
  const [event, setEvent] = useState<Event | null>(null);
  const [members, setMembers] = useState<MemberRow[]>([]);
  const [lists, setLists] = useState<ListRow[]>([]);
  const [profileNames, setProfileNames] = useState<Record<string, string>>({});
  const [recipientsByList, setRecipientsByList] = useState<Record<string, string[]>>({});
  const [itemCountByList, setItemCountByList] = useState<Record<string, number>>({});
  const [claimCountByList, setClaimCountByList] = useState<Record<string, number>>({});
  const [isAdmin, setIsAdmin] = useState(false);
  const [loading, setLoading] = useState(true);
  const [myUserId, setMyUserId] = useState<string | null>(null);
  const [membersOpen, setMembersOpen] = useState(false);
  const membersOpacity = React.useRef(new Animated.Value(0)).current;

  const toggleMembers = () => {
    const opening = !membersOpen;
    setMembersOpen(opening);
    Animated.timing(membersOpacity, {
      toValue: opening ? 1 : 0,
      duration: 160,
      easing: Easing.out(Easing.quad),
      useNativeDriver: true,
    }).start();
  };

  const load = async () => {
    setLoading(true);
    const failsafe = setTimeout(() => setLoading(false), 8000);

    try {
      const { data: { session }, error: sessErr } = await supabase.auth.getSession();
      if (sessErr) throw sessErr;
      if (!session) return;

      // Event
      const { data: e, error: eErr } = await supabase
        .from('events')
        .select('*')
        .eq('id', id)
        .maybeSingle();
      if (eErr) throw eErr;
      if (!e) { navigation.goBack(); return; }
      setEvent(e);

      // Members
      const { data: ms, error: mErr } = await supabase
        .from('event_members')
        .select('event_id,user_id,role')
        .eq('event_id', id);
      if (mErr) throw mErr;
      setMembers(ms ?? []);

      // Me + admin check (admin role OR event owner)
      const { data: { user } } = await supabase.auth.getUser();
      setMyUserId(user?.id ?? null);
      const amAdminViaRole = !!ms?.find(m => m.user_id === user?.id && m.role === 'admin');
      const amOwner = !!(user && (e as any)?.owner_id && user.id === (e as any).owner_id);
      setIsAdmin(amAdminViaRole || amOwner);

      // Lists
      const { data: ls, error: lErr } = await supabase
        .from('lists')
        .select('id,event_id,name')
        .eq('event_id', id)
        .order('created_at', { ascending: false });
      if (lErr) throw lErr;
      setLists(ls ?? []);
      const listIds = (ls ?? []).map(l => l.id);

      // Recipients per list
      const { data: lrs, error: rErr } = listIds.length
        ? await supabase.from('list_recipients').select('list_id,user_id').in('list_id', listIds)
        : { data: [], error: null as any };
      if (rErr) throw rErr;
      const rb: Record<string, string[]> = {};
      (lrs ?? []).forEach(r => { (rb[r.list_id] ||= []).push(r.user_id); });
      setRecipientsByList(rb);

      // Names (members + recipients)
      const memberIds = (ms ?? []).map(m => m.user_id);
      const recipientIds = (lrs ?? []).map(r => r.user_id);
      const allUserIds = Array.from(new Set([...memberIds, ...recipientIds]));
      if (allUserIds.length) {
        const { data: ps, error: pErr } = await supabase
          .from('profiles')
          .select('id,display_name')
          .in('id', allUserIds);
        if (pErr) throw pErr;
        const nameMap: Record<string, string> = {};
        (ps ?? []).forEach(p => { nameMap[p.id] = (p.display_name ?? '').trim(); });
        setProfileNames(nameMap);
      } else {
        setProfileNames({});
      }

      // Items
      const { data: items, error: iErr } = listIds.length
        ? await supabase.from('items').select('id,list_id').in('list_id', listIds)
        : { data: [], error: null as any };
      if (iErr) throw iErr;

      const ic: Record<string, number> = {};
      const itemIdsByList: Record<string, string[]> = {};
      (items ?? []).forEach(i => {
        ic[i.list_id] = (ic[i.list_id] || 0) + 1;
        (itemIdsByList[i.list_id] ||= []).push(i.id);
      });
      setItemCountByList(ic);

      // Claims
      const flatItemIds = Object.values(itemIdsByList).flat();
      const { data: claims, error: cErr } = flatItemIds.length
        ? await supabase.from('claims').select('id,item_id').in('item_id', flatItemIds)
        : { data: [], error: null as any };
      if (cErr) throw cErr;

      const listIdByItem: Record<string, string> = {};
      (items ?? []).forEach(i => { listIdByItem[i.id] = i.list_id; });
      const cc: Record<string, number> = {};
      (claims ?? []).forEach(c => {
        const lid = listIdByItem[c.item_id];
        cc[lid] = (cc[lid] || 0) + 1;
      });
      setClaimCountByList(cc);
    } catch (err: any) {
      console.error('EventDetail load()', err);
      if (err?.code === 'PGRST116') { navigation.goBack(); return; }
      Alert.alert('Load error', err?.message ?? String(err));
    } finally {
      clearTimeout(failsafe);
      setLoading(false);
    }
  };

  useFocusEffect(useCallback(() => { load(); }, [id]));

  useEffect(() => {
    const ch = supabase
      .channel(`event-${id}-detail`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'lists' }, load)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'items' }, load)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'claims' }, load)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'event_members' }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [id]);

  const memberCount = members.length;
  const totalItems = useMemo(
    () => Object.values(itemCountByList).reduce((a, b) => a + b, 0),
    [itemCountByList]
  );
  const totalClaimsVisible = useMemo(() => {
    if (!lists?.length) return 0;
    let sum = 0;
    for (const l of lists) {
      const recips = recipientsByList[l.id] ?? [];
      const iAmRecipient = myUserId ? recips.includes(myUserId) : false;
      if (iAmRecipient) continue;
      sum += (claimCountByList[l.id] || 0);
    }
    return sum;
  }, [lists, recipientsByList, claimCountByList, myUserId]);

  // ----- Actions that header depends on
  const deleteEvent = useCallback(() => {
    if (!isAdmin) {
      Alert.alert('Not allowed', 'Only an admin can delete this event.');
      return;
    }
    if (!event) return;
    Alert.alert(
      'Delete event?',
      'This will remove all lists, items, and claims for this event for everyone.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            const { error } = await supabase.from('events').delete().eq('id', event.id);
            if (error) return Alert.alert('Delete failed', error.message);
            navigation.goBack();
          },
        },
      ]
    );
  }, [isAdmin, event, navigation]);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () =>
        isAdmin ? (
          <View style={{ flexDirection: 'row' }}>
            <Pressable
              onPress={() => navigation.navigate('EditEvent', { id })}
              style={{ paddingHorizontal: 12, paddingVertical: 6 }}
            >
              <Text style={{ color: '#2e95f1', fontWeight: '700' }}>Edit</Text>
            </Pressable>
            <Pressable
              onPress={deleteEvent}
              style={{ paddingHorizontal: 12, paddingVertical: 6 }}
            >
              <Text style={{ color: '#c0392b', fontWeight: '700' }}>Delete</Text>
            </Pressable>
          </View>
        ) : null,
    });
  }, [navigation, isAdmin, id, deleteEvent]);

  const goEdit = React.useCallback(() => {
    if (!id) return;
    navigation.push('EditEvent', { id });
  }, [id, navigation]);

  const shareCode = async () => {
    if (!event?.join_code) return;
    Share.share({ message: `Join my event "${event.title}": code ${event.join_code}` });
  };

  // Remove member (admin/owner)
  const removeMember = useCallback(async (targetUserId: string) => {
    try {
      if (!event?.id) return;
      if (targetUserId === myUserId) {
        Alert.alert('Use “Leave event”', 'To remove yourself, tap the Leave event button.');
        return;
      }
      const confirm = await new Promise<boolean>((resolve) => {
        Alert.alert('Remove member?', 'They will be removed from this event and their claims cleared.', [
          { text: 'Cancel', style: 'cancel', onPress: () => resolve(false) },
          { text: 'Remove', style: 'destructive', onPress: () => resolve(true) },
        ]);
      });
      if (!confirm) return;

      const { error } = await supabase.rpc('remove_member', { p_event_id: event.id, p_user_id: targetUserId });
      if (error) {
        const msg = error.message ?? String(error);
        if (msg.includes('not_authorized')) return Alert.alert('Not allowed', 'Only admins can remove members.');
        if (msg.includes('target_not_member')) return Alert.alert('Already removed', 'This user is no longer a member.');
        return Alert.alert('Remove failed', msg);
      }
      Alert.alert('Member removed', 'They have been removed from the event.');
      await load();
    } catch (e: any) {
      Alert.alert('Remove failed', e?.message ?? String(e));
    }
  }, [event?.id, myUserId, load]);

  // Leave event (anyone)
  const leaveEvent = useCallback(async () => {
    try {
      if (!event?.id) return;
      const confirm = await new Promise<boolean>((resolve) => {
        Alert.alert('Leave event?', 'You will be removed from this event and your claims cleared.', [
          { text: 'Cancel', style: 'cancel', onPress: () => resolve(false) },
          { text: 'Leave', style: 'destructive', onPress: () => resolve(true) },
        ]);
      });
      if (!confirm) return;

      const { error } = await supabase.rpc('leave_event', { p_event_id: event.id });
      if (error) {
        const msg = error.message ?? String(error);
        if (msg.includes('not_member')) return Alert.alert('Not a member', 'You are not in this event.');
        return Alert.alert('Leave failed', msg);
      }
      Alert.alert('Left event', 'You have left the event.');
      navigation.goBack();
    } catch (e: any) {
      Alert.alert('Leave failed', e?.message ?? String(e));
    }
  }, [event?.id, navigation]);

  if (loading && !event) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator />
      </View>
    );
  }

  return (
    <View style={{ flex: 1, backgroundColor: '#f6f8fa'}}>
      {/* Header card with image (no gradients) */}
      {(() => {
        const th = getEventTheme(event?.title);
        const img = pickEventImage(event?.title); // may be undefined

        const frameStyle = {
          margin: 16,
          borderRadius: 16,
          overflow: 'hidden' as const, // clip corners
          elevation: 2,
        };

        const textColor = th.key !== 'default' ? th.textColor : '#111111';
        const subTextColor = th.key !== 'default' ? th.textColor : '#5b6b7b';

        if (img) {
          return (
            <View style={frameStyle}>
              <ImageBackground
                source={img}
                resizeMode="cover"
                style={{}} // no background, no padding here
                imageStyle={{ borderRadius: 16, opacity:0.8}} // no opacity; no overlay
              >
                {/* Content wrapper only adds padding; no background color */}
                <View style={{ padding: 16 }}>
                  {/* Title + optional emoji */}
                  <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                    {th.emoji ? <Text style={{ color: textColor, fontSize: 20 }}>{th.emoji}</Text> : null}
                    <Text style={{ color: textColor, fontSize: 20, fontWeight: '800' }}>{event?.title}</Text>
                  </View>

                  {/* Date */}
                  {event?.event_date ? (
                    <Text style={{ color: subTextColor }}>
                      {new Date(event.event_date).toLocaleDateString(undefined, {
                        weekday: 'short', month: 'short', day: 'numeric', year: 'numeric',
                      })}
                    </Text>
                  ) : null}

                  {/* Actions */}
                  <View style={{ flexDirection: 'row', gap: 8, marginTop: 8, flexWrap: 'wrap' }}>
                    <Button color="#32CD32" title="Share" onPress={shareCode} />
                    <Button color="#9a6700" title="Leave" onPress={leaveEvent} />
                  </View>

                  {/* Stats */}
                  <View style={{ flexDirection: 'row', gap: 20, marginTop: 12 }}>
                    <View>
                      <Text style={{ color: textColor, fontSize: 18, fontWeight: '800' }}>{memberCount}</Text>
                      <Text style={{ color: subTextColor }}>Members</Text>
                    </View>
                    <View>
                      <Text style={{ color: textColor, fontSize: 18, fontWeight: '800' }}>{totalItems}</Text>
                      <Text style={{ color: subTextColor }}>Items</Text>
                    </View>
                    <View>
                      <Text style={{ color: textColor, fontSize: 18, fontWeight: '800' }}>{totalClaimsVisible}</Text>
                      <Text style={{ color: subTextColor }}>Claimed</Text>
                    </View>
                  </View>

                  <View style={{ marginTop: 8 }}>
                    <Text style={{ color: subTextColor }}>
                      {isAdmin ? 'You are an admin of this event.' : 'Member access'}
                    </Text>
                  </View>
                </View>
              </ImageBackground>
            </View>
          );
        }

        // Fallback: no image → plain white card
        return (
          <View style={{ backgroundColor: 'white', padding: 16, margin: 16, borderRadius: 16, gap: 8, elevation: 2 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
              {th.emoji ? <Text style={{ color: '#111', fontSize: 20 }}>{th.emoji}</Text> : null}
              <Text style={{ color: '#111', fontSize: 20, fontWeight: '800' }}>{event?.title}</Text>
            </View>
            {event?.event_date ? (
              <Text style={{ color: '#5b6b7b' }}>
                {new Date(event.event_date).toLocaleDateString(undefined, {
                  weekday: 'short', month: 'short', day: 'numeric', year: 'numeric',
                })}
              </Text>
            ) : null}
            <View style={{ flexDirection: 'row', gap: 8, marginTop: 8, flexWrap: 'wrap' }}>
              <Button color="#32CD32" title="Share" onPress={shareCode} />
              <Button color="#9a6700" title="Leave" onPress={leaveEvent} />
            </View>
            <View style={{ flexDirection: 'row', gap: 20, marginTop: 12 }}>
              <View>
                <Text style={{ fontSize: 18, fontWeight: '800' }}>{memberCount}</Text>
                <Text style={{ color: '#5b6b7b' }}>Members</Text>
              </View>
              <View>
                <Text style={{ fontSize: 18, fontWeight: '800' }}>{totalItems}</Text>
                <Text style={{ color: '#5b6b7b' }}>Items</Text>
              </View>
              <View>
                <Text style={{ fontSize: 18, fontWeight: '800' }}>{totalClaimsVisible}</Text>
                <Text style={{ color: '#5b6b7b' }}>Claimed</Text>
              </View>
            </View>
            <View style={{ marginTop: 8 }}>
              <Text style={{ color: '#5b6b7b' }}>
                {isAdmin ? 'You are an admin of this event.' : 'Member access'}
              </Text>
            </View>
          </View>
        );
      })()}

      {/* Members (collapsible, fade only) */}
      <View style={{ paddingHorizontal: 16, paddingBottom: 8 }}>
        <Pressable
          onPress={toggleMembers}
          style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}
        >
          <Text style={{ fontSize: 16, fontWeight: '700' }}>Members</Text>
          <View
            style={{
              flexDirection: 'row',
              alignItems: 'center',
              backgroundColor: membersOpen ? '#f3f4f6' : '#eaf2ff',
              borderRadius: 999,
              paddingVertical: 4,
              paddingHorizontal: 10,
            }}
          >
            <Text
              style={{
                fontSize: 13,
                fontWeight: '700',
                color: membersOpen ? '#374151' : '#2e95f1',
                marginRight: 6,
              }}
            >
              {membersOpen ? 'Hide' : 'Show'}
            </Text>
            <View
              style={{
                paddingHorizontal: 6,
                paddingVertical: 2,
                borderRadius: 999,
                backgroundColor: membersOpen ? '#e5e7eb' : '#d6e7ff',
              }}
            >
              <Text
                style={{
                  fontSize: 12,
                  fontWeight: '800',
                  color: membersOpen ? '#374151' : '#2e95f1',
                }}
              >
                {members.length}
              </Text>
            </View>
          </View>
        </Pressable>

        {membersOpen && (
          <Animated.View
            style={{
              opacity: membersOpacity,
              backgroundColor: 'white',
              borderRadius: 12,
              padding: 12,
              borderWidth: 1,
              borderColor: '#eef2f7',
            }}
          >
            {(members ?? []).map((m) => {
              const display = (profileNames[m.user_id] ?? '').trim() || (m.user_id ?? '').slice(0, 6);
              const isMe = myUserId === m.user_id;
              const showRemove = isAdmin && !isMe;
              return (
                <View
                  key={m.user_id}
                  style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: 8 }}
                >
                  <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                    <Text style={{ fontWeight: '600' }}>{display}</Text>
                    <Text style={{ marginLeft: 8, opacity: 0.6, fontSize: 12 }}>{m.role}</Text>
                  </View>

                  {showRemove && (
                    <Pressable
                      onPress={() => removeMember(m.user_id)}
                      hitSlop={8}
                      accessibilityRole="button"
                      style={{ paddingVertical: 4 }}
                    >
                      <Text style={{ color: '#c0392b', fontWeight: '700' }}>Remove</Text>
                    </Pressable>
                  )}
                </View>
              );
            })}
          </Animated.View>
        )}
      </View>

      {/* Actions */}
      <View style={{ paddingHorizontal: 16, marginBottom: 8, marginTop: 8 }}>
        <Button title="Create List" onPress={() => navigation.navigate('CreateList', { eventId: id })} />
      </View>

      {/* Lists section */}
      <View style={{ paddingHorizontal: 16, paddingBottom: 24 }}>
        <Text style={{ fontSize: 16, fontWeight: '700', marginBottom: 8 }}>Lists</Text>
        <FlatList
          data={lists}
          keyExtractor={(l) => l.id}
          renderItem={({ item }) => {
            const recipientIds = recipientsByList[item.id] ?? [];
            const recipientNames = recipientIds
              .map(uid => (profileNames[uid] ?? '').trim())
              .filter(n => n.length > 0);

            // Hide claim counts if I am a recipient on THIS list
            const iAmRecipientOnThisList = myUserId ? recipientIds.includes(myUserId) : false;
            const visibleClaimCount = iAmRecipientOnThisList ? undefined : (claimCountByList[item.id] || 0);

            return (
              <ListCard
                name={item.name}
                recipients={recipientNames}
                itemCount={itemCountByList[item.id] || 0}
                claimedCount={visibleClaimCount}
                onPress={() => navigation.navigate('ListDetail', { id: item.id })}
              />
            );
          }}
          ListEmptyComponent={
            <View style={{ backgroundColor: 'white', padding: 16, borderRadius: 12 }}>
              <Text style={{ opacity: 0.7 }}>No lists yet. Create one to get started.</Text>
            </View>
          }
        />
      </View>
    </View>
  );
}
