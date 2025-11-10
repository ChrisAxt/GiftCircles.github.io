// src/screens/CreateListScreen.tsx
import React, { useEffect, useMemo, useState } from 'react';
import { View, TextInput, Alert, Text, Switch, ScrollView, ActivityIndicator, Pressable } from 'react-native';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';
import { parseSupabaseError } from '../lib/errorHandler';
import { LabeledInput } from '../components/LabeledInput';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { Screen } from '../components/Screen';
import { useTheme } from '@react-navigation/native';
import TopBar from '../components/TopBar';

type MemberRow = { event_id: string; user_id: string; role: 'giver' | 'recipient' | 'admin' };
type ProfileRow = { id: string; display_name: string | null };

export default function CreateListScreen({ route, navigation }: any) {
  const { eventId } = route.params as { eventId: string };
  const { t } = useTranslation();
  const insets = useSafeAreaInsets();
  const { colors } = useTheme();

  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  const [name, setName] = useState('');
  const [members, setMembers] = useState<MemberRow[]>([]);
  const [profilesMap, setProfilesMap] = useState<Record<string, string | null>>({});

  // selections
  const [recipientIds, setRecipientIds] = useState<Record<string, boolean>>({});
  const [restrict, setRestrict] = useState(false); // false = visible to event, true = exclude specific people
  const [viewerIds, setViewerIds] = useState<Record<string, boolean>>({}); // reused as "excluded" set in UI
  const [inviteByEmailSelected, setInviteByEmailSelected] = useState(false);
  const [otherRecipientSelected, setOtherRecipientSelected] = useState(false);
  const [otherRecipientName, setOtherRecipientName] = useState('');
  const [recipientEmails, setRecipientEmails] = useState<string[]>([]);
  const [emailInput, setEmailInput] = useState('');
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);
  const [randomAssignment, setRandomAssignment] = useState(false);
  const [randomAssignmentMode, setRandomAssignmentMode] = useState<'one_per_member' | 'distribute_all'>('one_per_member');
  const [randomReceiverAssignment, setRandomReceiverAssignment] = useState(false);

  const toggleRecipient = (uid: string) => setRecipientIds(prev => ({ ...prev, [uid]: !prev[uid] }));
  const toggleViewer = (uid: string) => setViewerIds(prev => ({ ...prev, [uid]: !prev[uid] }));

  // Load event members + profile names
  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        // Get current user
        const { data: { user } } = await supabase.auth.getUser();
        if (user && !cancelled) {
          setCurrentUserId(user.id);
        }

        const { data: ms, error: mErr } = await supabase
          .from('event_members')
          .select('event_id,user_id,role')
          .eq('event_id', eventId);
        if (mErr) throw mErr;
        if (cancelled) return;
        setMembers(ms ?? []);

        const ids = (ms ?? []).map(m => m.user_id);
        const profiles: Record<string, string | null> = {};
        if (ids.length) {
          const { data: ps, error: pErr } = await supabase
            .from('profiles')
            .select('id,display_name')
            .in('id', ids);
          if (pErr) throw pErr;
          (ps as ProfileRow[] | null ?? []).forEach(p => { profiles[p.id] = p.display_name; });
        }
        if (cancelled) return;
        setProfilesMap(profiles);
      } catch (err: any) {
        const errorDetails = parseSupabaseError(err, t);
        toast.error(errorDetails.title, { text2: errorDetails.message });
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [eventId, t]);

  const membersWithNames = useMemo(
    () =>
      members
        .map(m => {
          const raw = (profilesMap[m.user_id] ?? '').trim();
          const fallback = t('createList.user', { id: m.user_id.slice(0, 4).toUpperCase() });
          return { ...m, displayName: raw || fallback };
        })
        .sort((a, b) => a.displayName.localeCompare(b.displayName)),
    [members, profilesMap, t]
  );

  // Check if all members are selected
  const allMembersSelected = useMemo(() => {
    if (!membersWithNames || membersWithNames.length === 0) return false;
    return membersWithNames.every(m => recipientIds[m.user_id]);
  }, [recipientIds, membersWithNames]);

  // Toggle "Everyone" - select/deselect all members
  const toggleEveryone = () => {
    if (allMembersSelected) {
      // Deselect all
      setRecipientIds({});
    } else {
      // Select all
      const all: Record<string, boolean> = {};
      membersWithNames.forEach(m => { all[m.user_id] = true; });
      setRecipientIds(all);
    }
  };

  const create = async () => {
    if (submitting) return;

    try {
      const { data: { user }, error: userErr } = await supabase.auth.getUser();
      if (userErr) throw userErr;
      if (!user) {
        toast.error(t('createList.toasts.notSignedIn'), {});
        return;
      }

      if (!name.trim()) {
        toast.info(t('createList.toasts.listNameRequired'), {});
        return;
      }

      // Recipients
      const chosenRecipients = Object.keys(recipientIds).filter(uid => !!recipientIds[uid]);

      // Validation: At least one recipient source required
      if (!chosenRecipients.length && !otherRecipientSelected && !inviteByEmailSelected) {
        toast.error(t('createList.toasts.recipientsRequired.title'),
        { text2: t('createList.toasts.recipientsRequired.body')});
        return;
      }

      // If "Other" is selected, name is required
      if (otherRecipientSelected && !otherRecipientName.trim()) {
        toast.info(t('createList.toasts.otherRecipientNameRequired', 'Please enter a name for the other recipient'), {});
        return;
      }

      // If "Invite by Email" is selected, at least one email is required
      if (inviteByEmailSelected && recipientEmails.length === 0) {
        toast.info(t('createList.toasts.emailRecipientRequired', 'Please add at least one email address'), {});
        return;
      }

      setSubmitting(true);

      // Determine if "for_everyone" flag should be set
      // When all members are selected, this becomes a list "for everyone"
      const forEveryone = allMembersSelected && chosenRecipients.length > 0;

      const { data: newListId, error: rpcErr } = await supabase.rpc('create_list_with_people', {
        p_event_id: eventId,
        p_name: name.trim(),
        p_visibility: 'event' as any,
        p_recipients: chosenRecipients,
        p_hidden_recipients: [] as string[],
        p_viewers: [] as string[],
        p_custom_recipient_name: otherRecipientSelected ? otherRecipientName.trim() : null,
        p_random_assignment_enabled: randomAssignment,
        p_random_assignment_mode: randomAssignment ? randomAssignmentMode : null,
        p_random_receiver_assignment_enabled: randomReceiverAssignment,
        p_for_everyone: forEveryone,
      });

      if (rpcErr) {
        const errorDetails = parseSupabaseError(rpcErr, t);
        toast.error(errorDetails.title, { text2: errorDetails.message });
        setSubmitting(false); // Important: reset state before returning
        return;
      }

      if (!newListId) {
        toast.error(t('createList.toasts.createFailed.title'),
        { text2: t('createList.toasts.createFailed.noId')});
        setSubmitting(false); // Important: reset state before returning
        return;
      }

      // Exclusions: reuse viewerIds as "excluded"
      const excludedUserIds = Object.keys(viewerIds).filter(uid => !!viewerIds[uid]);
      if (excludedUserIds.length) {
        const rows = excludedUserIds.map(uid => ({ list_id: newListId, user_id: uid }));
        const { error: exclErr } = await supabase.from('list_exclusions').insert(rows);
        if (exclErr) throw exclErr;
      }

      // Add email recipients (auto-invites to event)
      if (recipientEmails.length > 0) {
        for (const email of recipientEmails) {
          const { error: emailErr } = await supabase.rpc('add_list_recipient', {
            p_list_id: newListId,
            p_recipient_email: email,
          });
          if (emailErr) {
            toast.error(t('createList.toasts.inviteFailedTitle', { email }), { text2: emailErr.message });
          }
        }
      }

      toast.success(t('createList.toasts.created.title'),
      { text2: t('createList.toasts.created.body')});
      navigation.goBack();
    } catch (err: any) {
      const errorDetails = parseSupabaseError(err, t);
      toast.error(errorDetails.title, { text2: errorDetails.message });
    } finally {
      setSubmitting(false);
    }
  };

  if (loading) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator />
      </View>
    );
  }

  return (
    <Screen >
      <TopBar title={t('createList.screenTitle', 'Create List')} />
      <View style={{ flex: 1, backgroundColor: colors.background, paddingTop: 16 }}>
        <ScrollView contentContainerStyle={{ padding: 16, paddingBottom: insets.bottom + 40 }}>
          {/* Card */}
          <View
            style={{
              marginTop: -15,
              backgroundColor: colors.card,
              borderRadius: 16,
              padding: 16,
              borderWidth: 1,
              borderColor: colors.border,
              shadowColor: '#000',
              shadowOpacity: 0.05,
              shadowRadius: 10,
              elevation: 2,
              gap: 12,
            }}
          >
            <Text style={{ fontSize: 18, fontWeight: '800', color: colors.text }}>{t('createList.title')}</Text>

            {/* Name */}
            <LabeledInput
              label={t('createList.labels.listName')}
              placeholder={t('createList.placeholders.listName')}
              value={name}
              onChangeText={setName}
            />

            {/* Divider */}
            <View style={{ height: 1, backgroundColor: colors.border, opacity: 0.6, marginVertical: 4 }} />

            {/* Recipients (chips) */}
            <Text style={{ fontWeight: '700', color: colors.text }}>{t('createList.sections.recipients.title')}</Text>
            <Text style={{ fontSize: 12, color: colors.text, opacity: 0.7, marginTop: -4, marginBottom: 8 }}>
              {t('createList.sections.recipients.help')}
            </Text>

            <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
              {membersWithNames.map(m => {
                const selected = !!recipientIds[m.user_id];
                return (
                  <Pressable
                    key={m.user_id}
                    onPress={() => toggleRecipient(m.user_id)}
                    style={{
                      marginRight: 8,
                      marginBottom: 8,
                      paddingVertical: 8,
                      paddingHorizontal: 12,
                      borderRadius: 999,
                      backgroundColor: selected ? '#2e95f1' : colors.card,
                      borderWidth: 1,
                      borderColor: selected ? '#2e95f1' : colors.border,
                    }}
                  >
                    <Text style={{ color: selected ? 'white' : colors.text, fontWeight: '700' }}>
                      {m.displayName}
                    </Text>
                  </Pressable>
                );
              })}

              {/* Everyone option */}
              <Pressable
                onPress={toggleEveryone}
                style={{
                  marginRight: 8,
                  marginBottom: 8,
                  paddingVertical: 8,
                  paddingHorizontal: 12,
                  borderRadius: 999,
                  backgroundColor: allMembersSelected ? '#2e95f1' : colors.card,
                  borderWidth: 1,
                  borderColor: allMembersSelected ? '#2e95f1' : colors.border,
                }}
              >
                <Text style={{ color: allMembersSelected ? 'white' : colors.text, fontWeight: '700' }}>
                  {t('createList.recipients.everyone', 'Everyone')}
                </Text>
              </Pressable>

              {/* Invite by Email option */}
              <Pressable
                onPress={() => {
                  setInviteByEmailSelected(!inviteByEmailSelected);
                  if (!inviteByEmailSelected) {
                    // If selecting Invite by Email, deselect Other
                    setOtherRecipientSelected(false);
                  }
                }}
                style={{
                  marginRight: 8,
                  marginBottom: 8,
                  paddingVertical: 8,
                  paddingHorizontal: 12,
                  borderRadius: 999,
                  backgroundColor: inviteByEmailSelected ? '#10b981' : colors.card,
                  borderWidth: 1,
                  borderColor: inviteByEmailSelected ? '#10b981' : colors.border,
                }}
              >
                <Text style={{ color: inviteByEmailSelected ? 'white' : colors.text, fontWeight: '700' }}>
                  {t('createList.recipients.inviteByEmail', 'Invite by Email')}
                </Text>
              </Pressable>

              {/* Other option */}
              <Pressable
                onPress={() => {
                  setOtherRecipientSelected(!otherRecipientSelected);
                  if (!otherRecipientSelected) {
                    // If selecting Other, deselect Invite by Email
                    setInviteByEmailSelected(false);
                  }
                }}
                style={{
                  marginRight: 8,
                  marginBottom: 8,
                  paddingVertical: 8,
                  paddingHorizontal: 12,
                  borderRadius: 999,
                  backgroundColor: otherRecipientSelected ? '#2e95f1' : colors.card,
                  borderWidth: 1,
                  borderColor: otherRecipientSelected ? '#2e95f1' : colors.border,
                }}
              >
                <Text style={{ color: otherRecipientSelected ? 'white' : colors.text, fontWeight: '700' }}>
                  {t('createList.recipients.other', 'Other')}
                </Text>
              </Pressable>
            </View>

            {/* Other recipient name input */}
            {otherRecipientSelected && (
              <View style={{ marginTop: 8 }}>
                <LabeledInput
                  label={t('createList.labels.otherRecipientName', 'Recipient Name')}
                  placeholder={t('createList.placeholders.otherRecipientName', 'Enter recipient name')}
                  value={otherRecipientName}
                  onChangeText={setOtherRecipientName}
                />
              </View>
            )}

            {/* Email recipients section - only show when Invite by Email is selected */}
            {inviteByEmailSelected && (
              <View style={{ marginTop: 12 }}>
                <Text style={{ fontWeight: '700', color: colors.text, marginBottom: 4 }}>
                  {t('createList.sections.emailRecipients.title')}
                </Text>
                <Text style={{ fontSize: 12, color: colors.text, opacity: 0.7, marginBottom: 8 }}>
                  {t('createList.sections.emailRecipients.help')}
                </Text>

                {/* Email chips */}
                {recipientEmails.length > 0 && (
                  <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginBottom: 8 }}>
                    {recipientEmails.map((email, idx) => (
                      <View
                        key={idx}
                        style={{
                          marginRight: 8,
                          marginBottom: 8,
                          paddingVertical: 6,
                          paddingHorizontal: 10,
                          borderRadius: 999,
                          backgroundColor: '#10b981',
                          flexDirection: 'row',
                          alignItems: 'center',
                        }}
                      >
                        <Text style={{ color: 'white', fontWeight: '600', fontSize: 13 }}>
                          {email}
                        </Text>
                        <Pressable
                          onPress={() => setRecipientEmails(prev => prev.filter((_, i) => i !== idx))}
                          hitSlop={8}
                          style={{ marginLeft: 6 }}
                        >
                          <Text style={{ color: 'white', fontWeight: 'bold', fontSize: 16 }}>×</Text>
                        </Pressable>
                      </View>
                    ))}
                  </View>
                )}

                {/* Email input */}
                <View style={{ flexDirection: 'row', gap: 8 }}>
                  <View style={{ flex: 1 }}>
                    <TextInput
                      style={{
                        borderWidth: 1,
                        borderColor: colors.border,
                        borderRadius: 8,
                        padding: 12,
                        color: colors.text,
                        backgroundColor: colors.card,
                      }}
                      placeholder={t('createList.sections.emailRecipients.placeholder')}
                      placeholderTextColor={colors.text + '80'}
                      value={emailInput}
                      onChangeText={setEmailInput}
                      keyboardType="email-address"
                      autoCapitalize="none"
                      autoCorrect={false}
                    />
                  </View>
                  <Pressable
                    onPress={() => {
                      const email = emailInput.trim().toLowerCase();
                      if (!email) return;

                      // Basic email validation
                      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
                        toast.error(t('createList.toasts.invalidEmailTitle'), { text2: t('createList.toasts.invalidEmailBody') });
                        return;
                      }

                      // Check for duplicates
                      if (recipientEmails.includes(email)) {
                        toast.info(t('createList.toasts.duplicateEmailTitle'), { text2: t('createList.toasts.duplicateEmailBody') });
                        return;
                      }

                      setRecipientEmails(prev => [...prev, email]);
                      setEmailInput('');
                    }}
                    style={{
                      backgroundColor: '#2e95f1',
                      paddingHorizontal: 16,
                      paddingVertical: 12,
                      borderRadius: 8,
                      justifyContent: 'center',
                    }}
                  >
                    <Text style={{ color: 'white', fontWeight: '700' }}>
                      {t('createList.sections.emailRecipients.addButton')}
                    </Text>
                  </Pressable>
                </View>
              </View>
            )}

            {/* Divider */}
            <View style={{ height: 1, backgroundColor: colors.border, opacity: 0.6, marginVertical: 4 }} />

            {/* Visibility → Exclude people */}
            <Text style={{ fontWeight: '700', color: colors.text }}>{t('createList.sections.visibility.title')}</Text>
            <Text style={{ fontSize: 12, color: colors.text, opacity: 0.7, marginTop: -4 }}>
              {t('createList.sections.visibility.help')}
            </Text>

            {/* Segmented: Everyone vs Exclude people */}
            <View style={{ flexDirection: 'row', gap: 8, marginTop: 6, flexWrap: 'wrap' }}>
              <Pressable
                onPress={() => setRestrict(false)}
                style={{
                  paddingVertical: 8,
                  paddingHorizontal: 12,
                  borderRadius: 999,
                  backgroundColor: !restrict ? '#2e95f1' : colors.card,
                  borderWidth: !restrict ? 0 : 1,
                  borderColor: !restrict ? 'transparent' : colors.border,
                }}
              >
                <Text style={{ color: !restrict ? 'white' : colors.text, fontWeight: '700' }}>
                  {t('createList.visibility.public')}
                </Text>
              </Pressable>

              <Pressable
                onPress={() => setRestrict(true)}
                style={{
                  paddingVertical: 8,
                  paddingHorizontal: 12,
                  borderRadius: 999,
                  backgroundColor: restrict ? '#2e95f1' : colors.card,
                  borderWidth: restrict ? 0 : 1,
                  borderColor: restrict ? 'transparent' : colors.border,
                }}
              >
                <Text style={{ color: restrict ? 'white' : colors.text, fontWeight: '700' }}>
                  {t('createList.visibility.exclude')}
                </Text>
              </Pressable>
            </View>

            {/* Excluded viewers chips (shown only when restrict=true) */}
            {restrict && (
              <View style={{ marginTop: 8 }}>
                <Text style={{ fontWeight: '700', marginBottom: 8, color: colors.text }}>
                  {t('createList.sections.exclusions.title')}
                </Text>
                <Text style={{ fontSize: 12, color: colors.text, opacity: 0.7, marginTop: -4, marginBottom: 8 }}>
                  {t('createList.sections.exclusions.help')}
                </Text>

                <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
                  {membersWithNames
                    .filter(m => m.user_id !== currentUserId)
                    .map(m => {
                    const excluded = !!viewerIds[m.user_id]; // reusing viewerIds as "excluded" set
                    return (
                      <Pressable
                        key={`exclude-${m.user_id}`}
                        onPress={() => toggleViewer(m.user_id)}
                        style={{
                          marginRight: 8,
                          marginBottom: 8,
                          paddingVertical: 8,
                          paddingHorizontal: 12,
                          borderRadius: 999,
                          backgroundColor: excluded ? '#c0392b' : colors.card,
                          borderWidth: 1,
                          borderColor: excluded ? '#c0392b' : colors.border,
                        }}
                      >
                        <Text style={{ color: excluded ? 'white' : colors.text, fontWeight: '700' }}>
                          {m.displayName}
                        </Text>
                      </Pressable>
                    );
                  })}
                </View>
              </View>
            )}

            {/* Divider */}
            <View style={{ height: 1, backgroundColor: colors.border, opacity: 0.6, marginVertical: 4 }} />

            {/* Random Assignment */}
            <View
              style={{
                backgroundColor: colors.card,
                borderRadius: 12,
                padding: 12,
                borderWidth: 1,
                borderColor: colors.border,
                marginTop: 12,
              }}
            >
              <Pressable
                onPress={() => setRandomAssignment(!randomAssignment)}
                style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}
              >
                <View style={{ flex: 1, marginRight: 12 }}>
                  <Text style={{ fontWeight: '600', marginBottom: 4, color: colors.text }}>
                    {t('createList.randomAssignment.label', 'Random Assignment')}
                  </Text>
                  <Text style={{ fontSize: 12, opacity: 0.7, color: colors.text }}>
                    {t('createList.randomAssignment.desc', 'Automatically assign items to members. Each person only sees their assignment.')}
                  </Text>
                </View>
                <View
                  style={{
                    width: 24,
                    height: 24,
                    borderRadius: 4,
                    borderWidth: 2,
                    borderColor: randomAssignment ? '#2e95f1' : colors.border,
                    backgroundColor: randomAssignment ? '#2e95f1' : 'transparent',
                    alignItems: 'center',
                    justifyContent: 'center',
                  }}
                >
                  {randomAssignment && (
                    <Text style={{ color: 'white', fontWeight: '900', fontSize: 16 }}>✓</Text>
                  )}
                </View>
              </Pressable>

              {/* Assignment mode options */}
              {randomAssignment && (
                <View style={{ marginTop: 12 }}>
                  <Text style={{ fontWeight: '600', marginBottom: 8, color: colors.text }}>
                    {t('createList.randomAssignment.modeLabel', 'Assignment Mode')}
                  </Text>

                  <Pressable
                    onPress={() => setRandomAssignmentMode('one_per_member')}
                    style={{
                      flexDirection: 'row',
                      alignItems: 'center',
                      paddingVertical: 8,
                      paddingHorizontal: 12,
                      borderRadius: 8,
                      backgroundColor: randomAssignmentMode === 'one_per_member' ? 'rgba(171, 217, 255, 0.2)' : 'transparent',
                      marginBottom: 8,
                    }}
                  >
                    <View
                      style={{
                        width: 20,
                        height: 20,
                        borderRadius: 10,
                        borderWidth: 2,
                        borderColor: randomAssignmentMode === 'one_per_member' ? '#2e95f1' : colors.border,
                        backgroundColor: randomAssignmentMode === 'one_per_member' ? '#2e95f1' : 'transparent',
                        alignItems: 'center',
                        justifyContent: 'center',
                        marginRight: 10,
                      }}
                    >
                      {randomAssignmentMode === 'one_per_member' && (
                        <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: 'white' }} />
                      )}
                    </View>
                    <Text style={{ flex: 1, color: colors.text, fontWeight: randomAssignmentMode === 'one_per_member' ? '600' : '400' }}>
                      {t('createList.randomAssignment.onePerMember', 'One item per member')}
                    </Text>
                  </Pressable>

                  <Pressable
                    onPress={() => setRandomAssignmentMode('distribute_all')}
                    style={{
                      flexDirection: 'row',
                      alignItems: 'center',
                      paddingVertical: 8,
                      paddingHorizontal: 12,
                      borderRadius: 8,
                      backgroundColor: randomAssignmentMode === 'distribute_all' ? 'rgba(171, 217, 255, 0.2)' : 'transparent',
                    }}
                  >
                    <View
                      style={{
                        width: 20,
                        height: 20,
                        borderRadius: 10,
                        borderWidth: 2,
                        borderColor: randomAssignmentMode === 'distribute_all' ? '#2e95f1' : colors.border,
                        backgroundColor: randomAssignmentMode === 'distribute_all' ? '#2e95f1' : 'transparent',
                        alignItems: 'center',
                        justifyContent: 'center',
                        marginRight: 10,
                      }}
                    >
                      {randomAssignmentMode === 'distribute_all' && (
                        <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: 'white' }} />
                      )}
                    </View>
                    <View style={{ flex: 1 }}>
                      <Text style={{ color: colors.text, fontWeight: randomAssignmentMode === 'distribute_all' ? '600' : '400' }}>
                        {t('createList.randomAssignment.distributeAll', 'Distribute all items')}
                      </Text>
                      <Text style={{ fontSize: 11, opacity: 0.6, color: colors.text, marginTop: 2 }}>
                        {t('createList.randomAssignment.distributeAllWarning', 'Some members may receive more items than others')}
                      </Text>
                    </View>
                  </Pressable>
                </View>
              )}
            </View>

            {/* Random Receiver Assignment */}
            {randomAssignment && (
              <View
                style={{
                  backgroundColor: colors.card,
                  borderRadius: 12,
                  padding: 12,
                  borderWidth: 1,
                  borderColor: colors.border,
                  marginTop: 12,
                }}
              >
                <Pressable
                  onPress={() => setRandomReceiverAssignment(!randomReceiverAssignment)}
                  style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}
                >
                  <View style={{ flex: 1, marginRight: 12 }}>
                    <Text style={{ fontWeight: '600', marginBottom: 4, color: colors.text }}>
                      {t('createList.randomReceiverAssignment.label', 'Random Receiver Assignment')}
                    </Text>
                    <Text style={{ fontSize: 12, opacity: 0.7, color: colors.text }}>
                      {t('createList.randomReceiverAssignment.desc', 'Each item is randomly assigned to a specific recipient. Only the giver knows who will receive their item.')}
                    </Text>
                  </View>
                  <View
                    style={{
                      width: 24,
                      height: 24,
                      borderRadius: 4,
                      borderWidth: 2,
                      borderColor: randomReceiverAssignment ? '#2e95f1' : colors.border,
                      backgroundColor: randomReceiverAssignment ? '#2e95f1' : 'transparent',
                      alignItems: 'center',
                      justifyContent: 'center',
                    }}
                  >
                    {randomReceiverAssignment && (
                      <Text style={{ color: 'white', fontWeight: '900', fontSize: 16 }}>✓</Text>
                    )}
                  </View>
                </Pressable>

                {randomReceiverAssignment && (
                  <View style={{ marginTop: 12, padding: 12, backgroundColor: 'rgba(255, 193, 7, 0.1)', borderRadius: 8 }}>
                    <Text style={{ fontSize: 12, color: colors.text, fontWeight: '600', marginBottom: 4 }}>
                      {t('createList.randomReceiverAssignment.noteTitle', 'Important:')}
                    </Text>
                    <Text style={{ fontSize: 11, color: colors.text, opacity: 0.8 }}>
                      {t('createList.randomReceiverAssignment.note', 'Recipients will not see items assigned to them. Each giver will see their assigned recipient\'s name. Requires at least 2 members.')}
                    </Text>
                  </View>
                )}
              </View>
            )}

            {/* Create button */}
            <View style={{ marginTop: 8 }}>
              <Pressable
                onPress={create}
                disabled={submitting}
                style={{
                  backgroundColor: '#2e95f1',
                  paddingVertical: 10,
                  paddingHorizontal: 16,
                  borderRadius: 10,
                  alignItems: 'center',
                  opacity: submitting ? 0.7 : 1,
                }}
              >
                {submitting ? (
                  <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                    <ActivityIndicator color="#fff" />
                    <Text style={{ color: '#fff', fontWeight: '700', marginLeft: 8 }}>
                      {t('createList.states.creating')}
                    </Text>
                  </View>
                ) : (
                  <Text style={{ color: '#fff', fontWeight: '700' }}>
                    {t('createList.actions.create')}
                  </Text>
                )}
              </Pressable>
            </View>
          </View>
        </ScrollView>
      </View>
    </Screen>
  );
}
