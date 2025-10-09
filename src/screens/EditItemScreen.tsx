// src/screens/EditItemScreen.tsx
import React, { useEffect, useState } from 'react';
import { View, TextInput, ActivityIndicator, Pressable, Text, ScrollView } from 'react-native';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';
import { parseSupabaseError } from '../lib/errorHandler';
import { LabeledInput } from '../components/LabeledInput';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { Screen } from '../components/Screen';
import { useTheme } from '@react-navigation/native';
import TopBar from '../components/TopBar';

export default function EditItemScreen({ route, navigation }: any) {
  const { itemId } = route.params as { itemId: string };
  const { t } = useTranslation();
  const insets = useSafeAreaInsets();
  const { colors } = useTheme();

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const [name, setName] = useState('');
  const [url, setUrl] = useState('');
  const [price, setPrice] = useState('');
  const [notes, setNotes] = useState('');

  useEffect(() => {
    (async () => {
      try {
        const { data, error } = await supabase
          .from('items')
          .select('*')
          .eq('id', itemId)
          .maybeSingle();

        if (error) throw error;
        if (!data) {
          toast.error(t('listDetail.errors.notFound'));
          navigation.goBack();
          return;
        }

        setName(data.name || '');
        setUrl(data.url || '');
        setPrice(data.price?.toString() || '');
        setNotes(data.notes || '');
      } catch (err: any) {
        const errorDetails = parseSupabaseError(err, t);
        toast.error(errorDetails.title, errorDetails.message);
        navigation.goBack();
      } finally {
        setLoading(false);
      }
    })();
  }, [itemId, navigation, t]);

  const save = async () => {
    if (saving) return;

    try {
      if (!name.trim()) {
        toast.info(t('addItem.toasts.itemNameRequired.title'), { text2: t('addItem.toasts.itemNameRequired.body') });
        return;
      }

      const priceNum = price.trim() ? parseFloat(price.trim()) : null;
      if (price.trim() && (isNaN(priceNum!) || priceNum! < 0)) {
        toast.info(t('addItem.toasts.invalidPrice.title'), { text2: t('addItem.toasts.invalidPrice.body') });
        return;
      }

      setSaving(true);

      const { error } = await supabase
        .from('items')
        .update({
          name: name.trim(),
          url: url.trim() || null,
          price: priceNum,
          notes: notes.trim() || null,
        })
        .eq('id', itemId);

      if (error) throw error;

      toast.success(t('listDetail.toasts.itemUpdated', 'Item updated'));
      navigation.goBack();
    } catch (err: any) {
      const errorDetails = parseSupabaseError(err, t);
      toast.error(errorDetails.title, errorDetails.message);
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

  return (
    <Screen>
      <TopBar title={t('editItem.title', 'Edit Item')} />
      <View style={{ flex: 1, backgroundColor: colors.background, paddingTop: 16 }}>
        <ScrollView contentContainerStyle={{ padding: 16, paddingBottom: insets.bottom + 40 }}>
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
            <Text style={{ fontSize: 18, fontWeight: '800', color: colors.text }}>
              {t('editItem.heading', 'Edit item details')}
            </Text>

            <LabeledInput
              label={t('addItem.labels.name')}
              placeholder={t('addItem.placeholders.name')}
              value={name}
              onChangeText={setName}
            />

            <LabeledInput
              label={t('addItem.labels.urlOpt')}
              placeholder={t('addItem.placeholders.url')}
              value={url}
              onChangeText={setUrl}
            />

            <LabeledInput
              label={t('addItem.labels.priceOpt')}
              placeholder={t('addItem.placeholders.price')}
              value={price}
              onChangeText={setPrice}
              keyboardType="decimal-pad"
            />

            <View>
              <Text style={{ fontWeight: '700', marginBottom: 4, color: colors.text }}>
                {t('addItem.labels.notesOpt')}
              </Text>
              <TextInput
                value={notes}
                onChangeText={setNotes}
                placeholder={t('addItem.placeholders.notes')}
                placeholderTextColor={colors.text + '80'}
                multiline
                numberOfLines={4}
                style={{
                  borderWidth: 1,
                  borderColor: colors.border,
                  borderRadius: 8,
                  padding: 10,
                  color: colors.text,
                  backgroundColor: colors.background,
                  minHeight: 80,
                  textAlignVertical: 'top',
                }}
              />
            </View>

            <View style={{ marginTop: 8 }}>
              <Pressable
                onPress={save}
                disabled={saving}
                style={{
                  backgroundColor: '#2e95f1',
                  paddingVertical: 10,
                  paddingHorizontal: 16,
                  borderRadius: 10,
                  alignItems: 'center',
                  opacity: saving ? 0.7 : 1,
                }}
              >
                {saving ? (
                  <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                    <ActivityIndicator color="#fff" />
                    <Text style={{ color: '#fff', fontWeight: '700', marginLeft: 8 }}>
                      {t('editItem.saving', 'Saving…')}
                    </Text>
                  </View>
                ) : (
                  <Text style={{ color: '#fff', fontWeight: '700' }}>
                    {t('editItem.save', 'Save Changes')}
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
