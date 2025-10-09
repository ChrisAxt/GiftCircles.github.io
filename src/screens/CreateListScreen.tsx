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
  const [otherRecipientSelected, setOtherRecipientSelected] = useState(false);
  const [otherRecipientName, setOtherRecipientName] = useState('');
  const [recipientEmails, setRecipientEmails] = useState<string[]>([]);
  const [emailInput, setEmailInput] = useState('');

  const toggleRecipient = (uid: string) => setRecipientIds(prev => ({ ...prev, [uid]: !prev[uid] }));
  const toggleViewer = (uid: string) => setViewerIds(prev => ({ ...prev, [uid]: !prev[uid] }));

  // Load event members + profile names
  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
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
        toast.error(errorDetails.title, errorDetails.message);
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

  const create = async () => {
    console.log('[CreateList] create() called, submitting:', submitting);
    if (submitting) return;

    try {
      const { data: { user }, error: userErr } = await supabase.auth.getUser();
      if (userErr) throw userErr;
      if (!user) {
        console.log('[CreateList] User not signed in');
        toast.error(t('createList.toasts.notSignedIn'));
        return;
      }

      if (!name.trim()) {
        console.log('[CreateList] List name required');
        toast.info(t('createList.toasts.listNameRequired'));
        return;
      }

      // Recipients
      const chosenRecipients = Object.keys(recipientIds).filter(uid => !!recipientIds[uid]);
      console.log('[CreateList] Validation - chosenRecipients:', chosenRecipients, 'otherSelected:', otherRecipientSelected, 'otherName:', otherRecipientName, 'emails:', recipientEmails);

      if (!chosenRecipients.length && !otherRecipientSelected && recipientEmails.length === 0) {
        console.log('[CreateList] No recipients selected');
        toast.error(t('createList.toasts.recipientsRequired.title'),
        { text2: t('createList.toasts.recipientsRequired.body')});
        return;
      }

      if (otherRecipientSelected && !otherRecipientName.trim()) {
        console.log('[CreateList] Other recipient name required');
        toast.info(t('createList.toasts.otherRecipientNameRequired', 'Please enter a name for the other recipient'));
        return;
      }

      setSubmitting(true);

      // Using EXCLUSIONS model RPC
      console.log('[CreateList] Calling create_list_with_people RPC', { eventId, name: name.trim(), recipients: chosenRecipients, customRecipient: otherRecipientSelected ? otherRecipientName.trim() : null });
      const { data: newListId, error: rpcErr } = await supabase.rpc('create_list_with_people', {
        p_event_id: eventId,
        p_name: name.trim(),
        p_visibility: 'event' as any,
        p_recipients: chosenRecipients,
        p_hidden_recipients: [] as string[],
        p_viewers: [] as string[],
        p_custom_recipient_name: otherRecipientSelected ? otherRecipientName.trim() : null,
      });

      if (rpcErr) {
        console.log('[CreateList] RPC error:', JSON.stringify(rpcErr, null, 2));
        const errorDetails = parseSupabaseError(rpcErr, t);
        toast.error(errorDetails.title, errorDetails.message);
        setSubmitting(false); // Important: reset state before returning
        return;
      }

      if (!newListId) {
        console.log('[CreateList] No list ID returned');
        toast.error(t('createList.toasts.createFailed.title'),
        { text2: t('createList.toasts.createFailed.noId')});
        setSubmitting(false); // Important: reset state before returning
        return;
      }

      console.log('[CreateList] List created successfully:', newListId);

      // Exclusions: reuse viewerIds as "excluded"
      const excludedUserIds = Object.keys(viewerIds).filter(uid => !!viewerIds[uid]);
      if (excludedUserIds.length) {
        const rows = excludedUserIds.map(uid => ({ list_id: newListId, user_id: uid }));
        const { error: exclErr } = await supabase.from('list_exclusions').insert(rows);
        if (exclErr) throw exclErr;
      }

      // Add email recipients (auto-invites to event)
      if (recipientEmails.length > 0) {
        console.log('[CreateList] Adding email recipients:', recipientEmails);
        for (const email of recipientEmails) {
          const { error: emailErr } = await supabase.rpc('add_list_recipient', {
            p_list_id: newListId,
            p_recipient_email: email,
          });
          if (emailErr) {
            console.log('[CreateList] Error adding email recipient:', email, emailErr);
            toast.error('Failed to invite ' + email, { text2: emailErr.message });
          } else {
            console.log('[CreateList] Successfully added email recipient:', email);
          }
        }
      }

      toast.success(t('createList.toasts.created.title'),
      { text2: t('createList.toasts.created.body')});
      navigation.goBack();
    } catch (err: any) {
      const errorDetails = parseSupabaseError(err, t);
      toast.error(errorDetails.title, errorDetails.message);
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

              {/* Other option */}
              <Pressable
                onPress={() => setOtherRecipientSelected(!otherRecipientSelected)}
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

            {/* Email recipients section */}
            <View style={{ marginTop: 12 }}>
              <Text style={{ fontWeight: '700', color: colors.text, marginBottom: 4 }}>
                Invite by Email
              </Text>
              <Text style={{ fontSize: 12, color: colors.text, opacity: 0.7, marginBottom: 8 }}>
                Add recipients who aren't in the event yet. They'll be invited automatically.
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
                    placeholder="email@example.com"
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
                      toast.error('Invalid Email', { text2: 'Please enter a valid email address' });
                      return;
                    }

                    // Check for duplicates
                    if (recipientEmails.includes(email)) {
                      toast.info('Already Added', { text2: 'This email is already in the list' });
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
                  <Text style={{ color: 'white', fontWeight: '700' }}>Add</Text>
                </Pressable>
              </View>
            </View>

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
                  {membersWithNames.map(m => {
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
