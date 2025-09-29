// src/screens/AddItemScreen.tsx
import { useState } from 'react';
import { View, Alert, Pressable, ActivityIndicator, Text } from 'react-native';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';
import { LabeledInput } from '../components/LabeledInput';
import { useTranslation } from 'react-i18next';
import { ScreenScroll } from '../components/Screen';
import TopBar from '../components/TopBar';

export default function AddItemScreen({ route, navigation }: any) {
  const { listId } = route.params as { listId: string };
  const { t } = useTranslation();

  const [name, setName] = useState('');
  const [url, setUrl] = useState('');
  const [price, setPrice] = useState('');
  const [notes, setNotes] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const parsePrice = (raw: string): number | null => {
    const trimmed = (raw ?? '').trim();
    if (!trimmed) return null;
    // keep digits and a single dot/comma
    const normalized = trimmed.replace(',', '.').replace(/[^\d.]/g, '');
    const n = Number(normalized);
    return Number.isFinite(n) ? n : null;
  };

  const add = async () => {
    if (submitting) return;
    if (!name.trim()) {
      toast.info(t('addItem.toasts.itemNameRequired.title'), t('addItem.toasts.itemNameRequired.body'));
      return;
    }

    setSubmitting(true);
    try {
      const { data: { user }, error: userErr } = await supabase.auth.getUser();
      if (userErr) throw userErr;
      if (!user) throw new Error(t('addItem.toasts.notSignedIn'));

      const parsedPrice = parsePrice(price);
      if (price.trim() && parsedPrice === null) {
        toast.info(t('addItem.toasts.invalidPrice.title'), t('addItem.toasts.invalidPrice.body'));
        setSubmitting(false);
        return;
      }

      const payload: any = {
        list_id: listId,
        name: name.trim(),
        url: url.trim() ? url.trim() : null,
        price: parsedPrice,
        created_by: user.id,
      };
      if (notes.trim()) payload.notes = notes.trim();

      const { error } = await supabase
        .from('items')
        .insert(payload)
        .select('id')
        .single();

      if (error) throw error;

      toast.success(t('addItem.toasts.added'));
      navigation.goBack();
    } catch (e: any) {
      const msg = e?.message ?? String(e);
      toast.error(t('addItem.toasts.addFailed.title'), msg);
      Alert.alert(t('addItem.errors.generic'), msg);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <ScreenScroll >
    <TopBar title={t('addItem.screenTitle', 'Add Item')} />
      <View style={{ paddingTop: 16, paddingHorizontal: 16 }}>
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
          keyboardType="url"
          autoCapitalize="none"
        />

        <LabeledInput
          label={t('addItem.labels.priceOpt')}
          placeholder={t('addItem.placeholders.price')}
          value={price}
          onChangeText={setPrice}
          keyboardType="decimal-pad"
        />

        <LabeledInput
          label={t('addItem.labels.notesOpt')}
          placeholder={t('addItem.placeholders.notes')}
          value={notes}
          onChangeText={setNotes}
          multiline
        />

        <View>
          <Pressable
            onPress={add}
            disabled={submitting}
            style={{
              backgroundColor: '#2e95f1', // keep your brand color
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
                  {t('addItem.states.adding')}
                </Text>
              </View>
            ) : (
              <Text style={{ color: '#fff', fontWeight: '700' }}>{t('addItem.actions.add')}</Text>
            )}
          </Pressable>
        </View>
      </View>
    </ScreenScroll>
  );
}
