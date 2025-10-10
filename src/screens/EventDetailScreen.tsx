// src/screens/EventDetailScreen.tsx
import React, { useCallback, useEffect, useMemo, useState, useLayoutEffect } from 'react';
import {
  View, Text, FlatList, Pressable, Alert, ActivityIndicator, Animated, Easing,
  ImageBackground, StyleSheet,
} from 'react-native';
import { useFocusEffect, useTheme } from '@react-navigation/native';
import { supabase } from '../lib/supabase';
import { Event } from '../types';
import ListCard from '../components/ListCard';
import { pickEventImage } from '../theme/eventImages';
import { fetchClaimCountsByList } from '../lib/claimCounts';
import { useTranslation } from 'react-i18next';
import { formatDateLocalized } from '../utils/date';
import { Screen } from '../components/Screen';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import TopBar from '../components/TopBar';
import { InviteUserModal } from '../components/InviteUserModal';

type MemberRow = { event_id: string; user_id: string; role: 'giver' | 'recipient' | 'admin' };
type ListRow = { id: string; event_id: string; name: string; custom_recipient_name?: string | null };
type EventTheme = { key: string; colors: string[]; textColor: string; };

const IMAGE_OPACITY = 0.2;
function getEventTheme(title?: string): EventTheme {
  const t = (title || '').toLowerCase();
  if (/(x-?mas|christmas|noel)/.test(t)) return { key: 'christmas', colors: [], textColor: '#ffffff' };
  if (/(birthday|b-?day|bday)/.test(t)) return { key: 'birthday', colors: [], textColor: '#ffffff' };
  if (/(wedding|marriage|anniversary)/.test(t)) return { key: 'wedding', colors: [], textColor: '#ffffff' };
  if (/(baby|shower)/.test(t)) return { key: 'baby', colors: [], textColor: '#ffffff' };
  return { key: 'default', colors: [], textColor: '#ffffff' };
}

export default function EventDetailScreen({ route, navigation }: any) {
  const { id } = route.params as { id: string };
  const { t, i18n } = useTranslation();
  const insets = useSafeAreaInsets();
  const { colors } = useTheme();

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

  // Invite modal state
  const [inviteOpen, setInviteOpen] = useState(false);
  const openInvitePopup = () => setInviteOpen(true);
  const closeInvitePopup = () => setInviteOpen(false);

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

  const goHome = () => {
    if (navigation.canGoBack()) navigation.goBack();
    else navigation.navigate('Events');
  };

  const load = async () => {
    setLoading(true);
    const failsafe = setTimeout(() => setLoading(false), 8000);

    try {
      const { data: { session }, error: sessErr } = await supabase.auth.getSession();
      if (sessErr) throw sessErr;
      if (!session) return;

      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      try {
        const { data: allowed, error: accErr } = await supabase.rpc('event_is_accessible', {
          p_event_id: id,
          p_user: user.id,
        });
        if (accErr) {
          console.log('[EventDetail] event_is_accessible error', accErr);
        } else if (allowed === false) {
          Alert.alert('Upgrade required', 'You can access up to 3 events on Free.');
          if (navigation.canGoBack()) navigation.goBack();
          else navigation.navigate('Events');
          return;
        }
      } catch (e) {
        console.log('[EventDetail] event_is_accessible exception', e);
      }

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

      setMyUserId(user?.id ?? null);
      const amAdminViaRole = !!ms?.find(m => m.user_id === user?.id && m.role === 'admin');
      const amOwner = !!(user && (e as any)?.owner_id && user.id === (e as any).owner_id);
      setIsAdmin(amAdminViaRole || amOwner);

      // Lists
      const { data: ls, error: lErr } = await supabase
        .from('lists')
        .select('id,event_id,name,custom_recipient_name')
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
      (lrs ?? []).forEach(r => {
        if (r.user_id) {
          (rb[r.list_id] ||= []).push(r.user_id);
        }
      });
      setRecipientsByList(rb);

      // Names (members + recipients)
      const memberIds = (ms ?? []).map(m => m.user_id);
      const recipientIds = (lrs ?? []).map(r => r.user_id).filter(uid => uid != null);
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
      try {
        const cc = await fetchClaimCountsByList(listIds);
        setClaimCountByList(cc);
      } catch (cErr: any) {
        console.log('[eventDetail] claim counts RPC error', cErr);
        setClaimCountByList({});
      }
    } catch (err: any) {
      console.error('eventDetail load()', err);
      if (err?.code === 'PGRST116') { navigation.goBack(); return; }
      Alert.alert(t('eventDetail.alerts.loadErrorTitle'), err?.message ?? String(err));
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
    const isLastMember = members.length === 1;
    if (!isAdmin && !isLastMember) {
      Alert.alert(t('eventDetail.alerts.notAllowedTitle'), t('eventDetail.alerts.onlyAdminDelete'));
      return;
    }
    if (!event) return;
    Alert.alert(
      t('eventDetail.alerts.deleteTitle'),
      t('eventDetail.alerts.deleteBody'),
      [
        { text: t('eventDetail.alerts.cancel'), style: 'cancel' },
        {
          text: t('eventDetail.alerts.confirmDelete'),
          style: 'destructive',
          onPress: async () => {
            const { error } = await supabase.from('events').delete().eq('id', event.id);
            if (error) return Alert.alert(t('eventDetail.alerts.deleteTitle'), error.message);
            goHome();
          },
        },
      ]
    );
  }, [isAdmin, event, navigation, t]);

  const goEdit = React.useCallback(() => {
    if (!id) return;
    navigation.push('EditEvent', { id });
  }, [id, navigation]);


  const removeMember = useCallback(async (targetUserId: string) => {
    try {
      if (!event?.id) return;
      if (targetUserId === myUserId) {
        Alert.alert(t('eventDetail.actions.leave'), t('eventDetail.alerts.leaveBody'));
        return;
      }
      const confirm = await new Promise<boolean>((resolve) => {
        Alert.alert(
          t('eventDetail.alerts.removeMemberTitle'),
          t('eventDetail.alerts.removeMemberBody'),
          [
            { text: t('eventDetail.alerts.cancel'), style: 'cancel', onPress: () => resolve(false) },
            { text: t('eventDetail.members.remove'), style: 'destructive', onPress: () => resolve(true) },
          ]
        );
      });
      if (!confirm) return;

      const { error } = await supabase.rpc('remove_member', { p_event_id: event.id, p_user_id: targetUserId });
      if (error) {
        const msg = error.message ?? String(error);
        if (msg.includes('not_authorized'))
          return Alert.alert(t('eventDetail.alerts.notAllowedTitle'), t('eventDetail.alerts.onlyAdminDelete'));
        if (msg.includes('target_not_member'))
          return Alert.alert(t('eventDetail.alerts.alreadyRemoved'), t('eventDetail.alerts.alreadyRemoved'));
        return Alert.alert(t('eventDetail.alerts.removeFailed'), msg);
      }
      Alert.alert(t('eventDetail.alerts.memberRemoved'), t('eventDetail.alerts.memberRemoved'));
      await load();
    } catch (e: any) {
      Alert.alert(t('eventDetail.alerts.removeFailed'), e?.message ?? String(e));
    }
  }, [event?.id, myUserId, load, t]);

  const leaveEvent = useCallback(async () => {
    try {
      if (!event?.id) return;
      const confirm = await new Promise<boolean>((resolve) => {
        Alert.alert(
          t('eventDetail.alerts.leaveTitle'),
          t('eventDetail.alerts.leaveBody'),
          [
            { text: t('eventDetail.alerts.cancel'), style: 'cancel', onPress: () => resolve(false) },
            { text: t('eventDetail.actions.leave'), style: 'destructive', onPress: () => resolve(true) },
          ]
        );
      });
      if (!confirm) return;

      const { error } = await supabase.rpc('leave_event', { p_event_id: event.id });
      if (error) {
        const msg = error.message ?? String(error);
        if (msg.includes('not_member')) return Alert.alert(t('eventDetail.alerts.notMember'), t('eventDetail.alerts.notMember'));
        return Alert.alert(t('eventDetail.alerts.leaveFailed'), msg);
      }
      Alert.alert(t('eventDetail.alerts.leftEvent'), t('eventDetail.alerts.leftEvent'));
      navigation.goBack();
    } catch (e: any) {
      Alert.alert(t('eventDetail.alerts.leaveFailed'), e?.message ?? String(e));
    }
  }, [event?.id, navigation, t]);

  if (loading && !event) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background }}>
        <ActivityIndicator />
      </View>
    );
  }

  return (
    <Screen>
      <TopBar
        title={t('eventDetail.title', 'Event')}
        right={
          (isAdmin || members.length === 1) ? (
            <View style={{ flexDirection: 'row' }}>
              <Pressable onPress={() => navigation.navigate('EditEvent', { id })} hitSlop={8} style={{ paddingHorizontal: 10 }}>
                <Text style={{ color: '#2e95f1', fontWeight: '700' }}>{t('eventDetail.toolbar.edit')}</Text>
              </Pressable>
              <Pressable onPress={deleteEvent} hitSlop={8} style={{ paddingHorizontal: 10 }}>
                <Text style={{ color: '#c0392b', fontWeight: '700' }}>{t('eventDetail.toolbar.delete')}</Text>
              </Pressable>
            </View>
          ) : null
        }
      />
      <View style={{ flex: 1, backgroundColor: colors.background }}>
        {/* Header card with image */}
        {(() => {
          const th = getEventTheme(event?.title);
          const img = pickEventImage(event?.title);

          const frameStyle = {
            margin: 16,
            borderRadius: 16,
            overflow: 'hidden' as const,
            backgroundColor: 'rgba(0,0,0,0.8)',
          };
          const styles = StyleSheet.create({
            button: {
              paddingVertical: 8,
              paddingHorizontal: 18,
              borderRadius: 18,
              alignItems: 'center',
              justifyContent: 'center',
            },
            text: {
              color: '#fff',
              fontWeight: 'bold',
              fontSize: 16,
            },
          });

          const textColor = th.textColor;
          const subTextColor = th.textColor;

          if (img) {
            return (
              <View style={frameStyle}>
                <ImageBackground
                  source={img}
                  resizeMode="cover"
                  style={{}}
                  imageStyle={{ margin: 0, borderRadius: 16, opacity: 0.5 }}
                >
                  <View style={{ padding: 16 }}>
                    {/* Title */}
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                      <Text style={{ color: textColor, fontSize: 22, fontWeight: '800' }}>{event?.title}</Text>
                    </View>

                    {/* Date (date-only) */}
                    {(event as any)?.event_date ? (
                      <Text style={{ color: subTextColor, fontSize: 16, fontWeight: '600' }}>
                        {formatDateLocalized((event as any).event_date, i18n.language)}
                      </Text>
                    ) : null}

                    {/* Actions */}
                    <View style={{ flexDirection: 'row', gap: 8, marginTop: 8, flexWrap: 'wrap' }}>
                      <Pressable style={[styles.button, { backgroundColor: '#32CD32' }]} onPress={openInvitePopup} hitSlop={12}>
                        <Text style={styles.text}>{t('eventDetail.actions.share')}</Text>
                      </Pressable>

                      <Pressable style={[styles.button, { backgroundColor: '#ff7373' }]} onPress={leaveEvent} hitSlop={12}>
                        <Text style={styles.text}>{t('eventDetail.actions.leave')}</Text>
                      </Pressable>
                    </View>

                    {/* Stats */}
                    <View style={{ flexDirection: 'row', gap: 20, marginTop: 12 }}>
                      <View>
                        <Text style={{ color: textColor, fontSize: 20, fontWeight: '800' }}>{memberCount}</Text>
                        <Text style={{ color: subTextColor, fontSize: 16, fontWeight: '600' }}>{t('eventDetail.stats.members')}</Text>
                      </View>
                      <View>
                        <Text style={{ color: textColor, fontSize: 20, fontWeight: '800' }}>{totalItems}</Text>
                        <Text style={{ color: subTextColor, fontSize: 16, fontWeight: '600' }}>{t('eventDetail.stats.items')}</Text>
                      </View>
                      <View>
                        <Text style={{ color: textColor, fontSize: 20, fontWeight: '800' }}>{totalClaimsVisible}</Text>
                        <Text style={{ color: subTextColor, fontSize: 16, fontWeight: '600' }}>{t('eventDetail.stats.claimed')}</Text>
                      </View>
                    </View>

                    <View style={{ marginTop: 8 }}>
                      <Text style={{ color: subTextColor, fontStyle: 'italic' }}>
                        {isAdmin ? t('eventDetail.header.adminNote') : t('eventDetail.header.memberNote')}
                      </Text>
                    </View>
                  </View>
                </ImageBackground>
              </View>
            );
          }
          return null;
        })()}

        {/* Members (collapsible, fade only) */}
        <View style={{ paddingHorizontal: 16, paddingBottom: 8 }}>
          <Pressable
            onPress={toggleMembers}
            style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}
          >
            <Text style={{ fontSize: 16, fontWeight: '700', color: colors.text }}>{t('eventDetail.members.title')}</Text>
            <View
              style={{
                flexDirection: 'row',
                alignItems: 'center',
                backgroundColor: membersOpen ? colors.card : 'rgba(46,149,241,0.15)',
                borderRadius: 999,
                paddingVertical: 4,
                paddingHorizontal: 10,
                borderWidth: membersOpen ? 1 : 0,
                borderColor: colors.border,
              }}
            >
              <Text
                style={{
                  fontSize: 13,
                  fontWeight: '700',
                  color: membersOpen ? colors.text : '#2e95f1',
                  marginRight: 6,
                }}
              >
                {membersOpen ? t('eventDetail.members.hide') : t('eventDetail.members.show')}
              </Text>
              <View
                style={{
                  paddingHorizontal: 6,
                  paddingVertical: 2,
                  borderRadius: 999,
                  backgroundColor: membersOpen ? colors.border : 'rgba(46,149,241,0.25)',
                }}
              >
                <Text
                  style={{
                    fontSize: 12,
                    fontWeight: '800',
                    color: membersOpen ? colors.text : '#2e95f1',
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
                backgroundColor: colors.card,
                borderRadius: 12,
                padding: 12,
                borderWidth: 1,
                borderColor: colors.border,
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
                      <Text style={{ fontWeight: '600', color: colors.text }}>{display}</Text>
                      <Text style={{ marginLeft: 8, opacity: 0.6, fontSize: 12, color: colors.text }}>
                        {t(`eventDetail.members.roles.${m.role}`)}
                      </Text>
                    </View>

                    {showRemove && (
                      <Pressable
                        onPress={() => removeMember(m.user_id)}
                        hitSlop={8}
                        accessibilityRole="button"
                        style={{ paddingVertical: 4 }}
                      >
                        <Text style={{ color: '#c0392b', fontWeight: '700' }}>{t('eventDetail.members.remove')}</Text>
                      </Pressable>
                    )}
                  </View>
                );
              })}
            </Animated.View>
          )}
        </View>

        {/* Actions */}
        <View style={{ paddingHorizontal: 16, marginBottom: insets.bottom, marginTop: 8 }}>
          <Pressable
            onPress={() => navigation.navigate('CreateList', { eventId: id })}
            style={{
              backgroundColor: '#2e95f1',
              paddingVertical: 10,
              paddingHorizontal: 16,
              borderRadius: 10,
              alignItems: 'center',
            }}
          >
            <Text style={{ color: '#fff', fontWeight: '700' }}>{t('eventDetail.actions.createList')}</Text>
          </Pressable>
        </View>

        {/* Lists section */}
        <View style={{ flex: 1, paddingHorizontal: 16, paddingBottom: insets.bottom + 24, paddingTop: 16 }}>
          <Text style={{ fontSize: 16, fontWeight: '700', marginBottom: 8, color: colors.text }}>
            {t('eventDetail.lists.title')}
          </Text>

          <FlatList
            style={{ flex: 1 }}
            data={lists}
            keyExtractor={(l) => l.id}
            contentContainerStyle={{ paddingBottom: insets.bottom + 16 }}
            keyboardShouldPersistTaps="handled"
            renderItem={({ item }) => {
              const recipientIds = recipientsByList[item.id] ?? [];
              const recipientNames = recipientIds
                .map(uid => (profileNames[uid] ?? '').trim())
                .filter(n => n.length > 0);

              // Add custom recipient name if it exists
              const allRecipientNames = item.custom_recipient_name
                ? [...recipientNames, item.custom_recipient_name.trim()]
                : recipientNames;

              // Hide claim counts if I am a recipient on THIS list
              const iAmRecipientOnThisList = myUserId ? recipientIds.includes(myUserId) : false;
              const visibleClaimCount = iAmRecipientOnThisList ? undefined : (claimCountByList[item.id] || 0);

              return (
                <ListCard
                  name={item.name}
                  recipients={allRecipientNames}
                  itemCount={itemCountByList[item.id] || 0}
                  claimedCount={visibleClaimCount}
                  onPress={() => navigation.navigate('ListDetail', { id: item.id })}
                />
              );
            }}
            ListEmptyComponent={
              <View style={{ backgroundColor: colors.card, padding: 16, borderRadius: 12, borderWidth: 1, borderColor: colors.border }}>
                <Text style={{ opacity: 0.8, fontWeight: '700', color: colors.text }}>{t('eventDetail.lists.emptyTitle')}</Text>
                <Text style={{ opacity: 0.6, marginTop: 6, color: colors.text }}>{t('eventDetail.lists.emptyBody')}</Text>
              </View>
            }
          />
        </View>

        {/* Invite modal */}
        <InviteUserModal
          visible={inviteOpen}
          eventId={id}
          eventTitle={event?.title || ''}
          joinCode={event?.join_code || ''}
          onClose={closeInvitePopup}
          onInviteSent={() => {
            load(); // Reload to show updated data
          }}
        />
      </View>
    </Screen>
  );
}
