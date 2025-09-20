// src/components/ClaimButton.tsx
import React, { useMemo, useState } from 'react';
import { Pressable, Text, ActivityIndicator, View } from 'react-native';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';

type Claim = { id: string; item_id: string; claimer_id: string; created_at?: string };

type Props = {
  itemId: string;
  claims: Claim[];
  meId: string | null | undefined;
  onChanged?: () => void; // call to refresh list after action
};

export default function ClaimButton({ itemId, claims, meId, onChanged }: Props) {
  const [busy, setBusy] = useState(false);

  const mine = useMemo(() => !!meId && claims.some(c => c.claimer_id === meId), [claims, meId]);
  const isClaimed = claims.length > 0;
  const disabled = isClaimed && !mine; // only claimer can unclaim; others blocked

  const label = mine ? 'Unclaim' : 'Claim';
  const bg = disabled ? '#e5e7eb' : mine ? '#fde8e8' : '#e9f8ec';
  const border = disabled ? '#e5e7eb' : mine ? '#f8c7c7' : '#bce9cb';
  const fg = disabled ? '#9aa3af' : mine ? '#c0392b' : '#1f9e4a';

  const press = async () => {
    if (busy || disabled) return;
    try {
      setBusy(true);

      // Use SECURITY DEFINER RPCs so RLS/visibility can’t block legit actions
      const fn = mine ? 'unclaim_item' : 'claim_item';
      const { error } = await supabase.rpc(fn, { p_item_id: itemId });

      if (error) {
        const msg = String(error.message || error);
        if (msg.includes('not_authenticated')) {
          toast.error('Sign in required', 'Please sign in and try again.');
        } else if (msg.includes('not_authorized')) {
          toast.error('Not allowed', 'Recipients cannot claim items on their own lists.');
        } else {
          toast.error('Action failed', msg);
        }
        return;
      }

      toast.success(mine ? 'Unclaimed' : 'Claimed');
      onChanged?.(); // realtime should also update, this just makes it snappy
    } catch (e: any) {
      toast.error('Action failed', e?.message ?? String(e));
    } finally {
      setBusy(false);
    }
  };

return (
  <Pressable
    onPress={press}
    disabled={disabled || busy}
    accessibilityRole="button"
    accessibilityLabel={label}
    accessibilityState={{ disabled: disabled || busy }}
    style={{
      paddingVertical: 6,
      paddingHorizontal: 12,
      borderRadius: 999,
      backgroundColor: bg,
      borderWidth: 1,
      borderColor: border,
      minWidth: 92,
      alignItems: 'center',
      justifyContent: 'center',
    }}
  >
    {busy ? (
      <View style={{ height: 16 }}>
        <ActivityIndicator size="small" />
      </View>
    ) : (
      <Text style={{ fontWeight: '800', fontSize: 12, color: fg }}>{label}</Text>
    )}
  </Pressable>
);

}
