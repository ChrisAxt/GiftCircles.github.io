// src/screens/EditListScreen.tsx
import React, { useCallback, useEffect, useState } from 'react';
import { View, Text, ActivityIndicator, Pressable } from 'react-native';
import { useFocusEffect, useTheme } from '@react-navigation/native';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';
import { LabeledInput } from '../components/LabeledInput';
import { Screen } from '../components/Screen';
import { useTranslation } from 'react-i18next';
import TopBar from '../components/TopBar';

type ListRow = {
  id: string;
  name: string;
  event_id: string;
  created_by: string;
};

export default function EditListScreen({ route, navigation }: any) {
  const { listId } = route.params as { listId: string };
  const { t } = useTranslation();
  const { colors } = useTheme();

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const [list, setList] = useState<ListRow | null>(null);
  const [name, setName] = useState('');
  const [canEdit, setCanEdit] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setErrorMsg(null);
    try {
      const { data: { user }, error: userErr } = await supabase.auth.getUser();
      if (userErr) throw userErr;
      if (!user) {
        setErrorMsg('Please sign in');
        return;
      }

      // Get list
      const { data: listData, error: listErr } = await supabase
        .from('lists')
        .select('id, name, event_id, created_by')
        .eq('id', listId)
        .maybeSingle();

      if (listErr) throw listErr;
      if (!listData) {
        setErrorMsg('List not found');
        return;
      }

      setList(listData);
      setName(listData.name);

      // Check if user can edit (is creator or admin)
      const isCreator = listData.created_by === user.id;

      const { data: memberData, error: memberErr } = await supabase
        .from('event_members')
        .select('role')
        .eq('event_id', listData.event_id)
        .eq('user_id', user.id)
        .maybeSingle();

      if (memberErr) throw memberErr;

      const isAdmin = memberData?.role === 'admin';
      setCanEdit(isCreator || isAdmin);
    } catch (e: any) {
      console.error('[EditList] load error', e);
      setErrorMsg(e?.message ?? 'Failed to load list');
    } finally {
      setLoading(false);
    }
  }, [listId]);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  const save = async () => {
    if (!canEdit) {
      toast.error('Not allowed', { text2: 'Only the list creator or event admin can edit' });
      return;
    }

    if (!name.trim()) {
      toast.error('Name required', { text2: 'Please enter a list name' });
      return;
    }

    setSaving(true);
    try {
      const { error } = await supabase
        .from('lists')
        .update({ name: name.trim() })
        .eq('id', listId);

      if (error) throw error;

      toast.success('List updated');
      navigation.goBack();
    } catch (e: any) {
      console.error('[EditList] save error', e);
      toast.error('Save failed', { text2: e?.message ?? String(e) });
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator />
      </View>
    );
  }

  if (errorMsg) {
    return (
      <Screen>
        <TopBar title="Edit List" />
        <View style={{ flex: 1, padding: 16, alignItems: 'center', justifyContent: 'center' }}>
          <Text style={{ fontSize: 16, textAlign: 'center', marginBottom: 16, color: colors.text }}>
            {errorMsg}
          </Text>
          <Pressable
            onPress={() => navigation.goBack()}
            style={{
              paddingVertical: 10,
              paddingHorizontal: 16,
              borderRadius: 10,
              backgroundColor: colors.card,
              borderWidth: 1,
              borderColor: colors.border,
            }}
          >
            <Text style={{ fontWeight: '700', color: colors.text }}>Go Back</Text>
          </Pressable>
        </View>
      </Screen>
    );
  }

  return (
    <Screen>
      <TopBar title="Edit List" />
      <View style={{ padding: 16, gap: 12 }}>
        <LabeledInput
          label="List Name"
          placeholder="e.g. Christmas Wishlist"
          value={name}
          onChangeText={setName}
          editable={canEdit}
        />

        <View style={{ marginTop: 12 }}>
          <Pressable
            onPress={save}
            disabled={!canEdit || saving}
            style={{
              backgroundColor: !canEdit ? colors.card : '#2e95f1',
              paddingVertical: 10,
              paddingHorizontal: 16,
              borderRadius: 10,
              alignItems: 'center',
              opacity: saving ? 0.7 : 1,
              borderWidth: !canEdit ? 1 : 0,
              borderColor: !canEdit ? colors.border : 'transparent',
            }}
          >
            {!canEdit ? (
              <Text style={{ color: colors.text, fontWeight: '700' }}>View Only</Text>
            ) : saving ? (
              <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                <ActivityIndicator color="#fff" />
                <Text style={{ color: '#fff', fontWeight: '700', marginLeft: 8 }}>Saving...</Text>
              </View>
            ) : (
              <Text style={{ color: '#fff', fontWeight: '700' }}>Save Changes</Text>
            )}
          </Pressable>
        </View>
      </View>
    </Screen>
  );
}
