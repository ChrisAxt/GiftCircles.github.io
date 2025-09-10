// src/screens/CreateListScreen.tsx
import React, { useEffect, useMemo, useState } from 'react';
import { View, TextInput, Button, Alert, Text, Switch, ScrollView, ActivityIndicator, Pressable } from 'react-native';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';
import { LabeledInput, LabeledPressableField } from '../components/LabeledInput';

type MemberRow = { event_id: string; user_id: string; role: 'giver' | 'recipient' | 'admin' };
type ProfileRow = { id: string; display_name: string | null };

function nameFor(id: string, profiles: Record<string, string | null>) {
  const n = (profiles[id] ?? '')?.trim();
  return n || `User ${id.slice(0, 4).toUpperCase()}`;
}

export default function CreateListScreen({ route, navigation }: any) {
  const { eventId } = route.params as { eventId: string };

  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  const [name, setName] = useState('');
  const [members, setMembers] = useState<MemberRow[]>([]);
  const [profilesMap, setProfilesMap] = useState<Record<string, string | null>>({});

  // selections
  const [recipientIds, setRecipientIds] = useState<Record<string, boolean>>({});
  const [recipientHidden, setRecipientHidden] = useState<Record<string, boolean>>({}); // true => hide from this recipient
  const [restrict, setRestrict] = useState(false); // false = event-wide, true = selected only
  const [viewerIds, setViewerIds] = useState<Record<string, boolean>>({});

  const toggleRecipient = (uid: string) => {
    setRecipientIds(prev => {
      const next = { ...prev, [uid]: !prev[uid] };
      // when newly selected, default to "can view" (hidden = false)
      if (!prev[uid]) {
        setRecipientHidden(h => ({ ...h, [uid]: false }));
      }
      return next;
    });
  };

  const toggleRecipientHidden = (uid: string) =>
    setRecipientHidden(prev => ({ ...prev, [uid]: !prev[uid] }));

  const toggleViewer = (uid: string) =>
    setViewerIds(prev => ({ ...prev, [uid]: !prev[uid] }));

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
        toast.error('Load error', err?.message ?? String(err));
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [eventId]);

  const membersWithNames = useMemo(() =>
    members
      .map(m => ({ ...m, displayName: nameFor(m.user_id, profilesMap) }))
      .sort((a, b) => a.displayName.localeCompare(b.displayName))
  , [members, profilesMap]);

  const create = async () => {
    if (submitting) return;

    try {
      const { data: { user }, error: userErr } = await supabase.auth.getUser();
      if (userErr) throw userErr;
      if (!user) { toast.error('Not signed in'); return; }

      if (!name.trim()) { toast.info('List name required'); return; }

      // Recipients (chips)
      const chosenRecipients = Object.entries(recipientIds)
        .filter(([, v]) => v)
        .map(([k]) => k);

      if (!chosenRecipients.length) {
        toast.error('Recipients required', 'Pick at least one recipient.');
        return;
      }

      setSubmitting(true);

      // --- NEW: exclusions ---
      // We reuse viewerIds as the EXCLUDED set based on the new UI.
      const excludedIds = new Set(
        Object.entries(viewerIds)
          .filter(([, v]) => v)
          .map(([k]) => k)
      );

      // Build the allow-list expected by the RPC when restricted:
      // allowed = (all event members) minus excluded, plus creator (deduped).
      // We can derive all member ids from membersWithNames (already loaded for this screen).
      const allMemberIds = (membersWithNames ?? []).map(m => m.user_id);
      const allowedViewers = Array.from(
        new Set(
          allMemberIds.filter(id => !excludedIds.has(id)).concat(user.id)
        )
      );

      // Visibility: keep using 'selected' only when restricting, otherwise 'event'
      const visibility = restrict ? 'selected' : 'event';

      const payload = {
        p_event_id: eventId,
        p_name: name.trim(),
        p_visibility: visibility as any,
        p_recipients: chosenRecipients,
        // Hidden recipients removed under the new model:
        p_hidden_recipients: [] as string[],
        // When not restricting, pass empty array so RPC won’t write list_viewers.
        p_viewers: restrict ? allowedViewers : [],
      };

      console.log('[CreateList] payload', payload);

      const { data: newListId, error } = await supabase.rpc('create_list_with_people', payload);

      if (error) {
        const msg = String(error.message || error);
        if (msg.includes('not_an_event_member')) {
          toast.error('You’re not a member of this event.');
        } else {
          toast.error('Create failed', msg);
        }
        return;
      }
      if (!newListId) {
        toast.error('Create failed', 'No list id returned.');
        return;
      }

      toast.success('List created', 'Your list was created successfully.');
      navigation.goBack();
    } catch (err: any) {
      toast.error('Create failed', err?.message ?? String(err));
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
    <View style={{ flex: 1, backgroundColor: '#f6f8fa' }}>
      <ScrollView contentContainerStyle={{ padding: 16, paddingBottom: 120 }}>
        {/* Card */}
        <View
          style={{
            backgroundColor: 'white',
            borderRadius: 16,
            padding: 16,
            borderWidth: 1,
            borderColor: '#e5e7eb',
            shadowColor: '#000',
            shadowOpacity: 0.05,
            shadowRadius: 10,
            elevation: 2,
            gap: 12,
          }}
        >
          <Text style={{ fontSize: 18, fontWeight: '800' }}>Create a list</Text>

          {/* Name */}
          <LabeledInput
            label="List name"
            placeholder="e.g. Gifts for Bob"
            value={name}
            onChangeText={setName}
          />

          {/* Divider */}
          <View style={{ height: 1, backgroundColor: '#eef2f7', marginVertical: 4 }} />

          {/* Recipients (chips, no Hidden/Show) */}
          <Text style={{ fontWeight: '700' }}>Recipients (who this list is for)</Text>
          <Text style={{ fontSize: 12, color: '#6b7280', marginTop: -4, marginBottom: 8 }}>
            Tap to select one or more recipients.
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
                    backgroundColor: selected ? '#2e95f1' : '#eef2f7',
                    borderWidth: 1,
                    borderColor: selected ? '#2e95f1' : '#e5e7eb',
                  }}
                >
                  <Text style={{ color: selected ? 'white' : '#1f2937', fontWeight: '700' }}>
                    {m.displayName}
                  </Text>
                </Pressable>
              );
            })}
          </View>

          {/* Divider */}
          <View style={{ height: 1, backgroundColor: '#eef2f7', marginVertical: 4 }} />

          {/* Visibility → Exclude people */}
          <Text style={{ fontWeight: '700' }}>Visibility</Text>
          <Text style={{ fontSize: 12, color: '#6b7280', marginTop: -4 }}>
            Choose who can see this list.
          </Text>

          {/* Segmented: Everyone vs Exclude people */}
          <View style={{ flexDirection: 'row', gap: 8, marginTop: 6, flexWrap: 'wrap' }}>
            <Pressable
              onPress={() => setRestrict(false)}
              style={{
                paddingVertical: 8,
                paddingHorizontal: 12,
                borderRadius: 999,
                backgroundColor: !restrict ? '#2e95f1' : '#eef2f7',
              }}
            >
              <Text style={{ color: !restrict ? 'white' : '#1f2937', fontWeight: '700' }}>
                Visible to everyone
              </Text>
            </Pressable>

            <Pressable
              onPress={() => setRestrict(true)}
              style={{
                paddingVertical: 8,
                paddingHorizontal: 12,
                borderRadius: 999,
                backgroundColor: restrict ? '#2e95f1' : '#eef2f7',
              }}
            >
              <Text style={{ color: restrict ? 'white' : '#1f2937', fontWeight: '700' }}>
                Exclude specific people
              </Text>
            </Pressable>
          </View>

          {/* Excluded viewers chips (shown only when restrict=true) */}
          {restrict && (
            <View style={{ marginTop: 8 }}>
              <Text style={{ fontWeight: '700', marginBottom: 8 }}>Who to exclude</Text>
              <Text style={{ fontSize: 12, color: '#6b7280', marginTop: -4, marginBottom: 8 }}>
                People you pick here won’t see this list (even if they’re recipients).
              </Text>

              <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
                {membersWithNames.map(m => {
                  const excluded = !!viewerIds[m.user_id]; // reusing viewerIds as "excludedIds"
                  return (
                    <Pressable
                      key={`exclude-${m.user_id}`}
                      onPress={() => toggleViewer(m.user_id)} // reusing toggleViewer to toggle exclusion
                      style={{
                        marginRight: 8,
                        marginBottom: 8,
                        paddingVertical: 8,
                        paddingHorizontal: 12,
                        borderRadius: 999,
                        backgroundColor: excluded ? '#c0392b' : '#eef2f7',
                        borderWidth: 1,
                        borderColor: excluded ? '#c0392b' : '#e5e7eb',
                      }}
                    >
                      <Text style={{ color: excluded ? 'white' : '#1f2937', fontWeight: '700' }}>
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
            <Button
              title={submitting ? 'Creating…' : 'Create List'}
              onPress={create}
              disabled={submitting}
            />
          </View>
        </View>
      </ScrollView>
    </View>
  );
}
