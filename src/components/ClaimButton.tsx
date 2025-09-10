import React, { useMemo, useState } from 'react';
import { Pressable, Text } from 'react-native';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';

type Claim = { id: string; item_id: string; claimer_id: string; created_at?: string };

export default function ClaimButton({
  itemId,
  claims,
  meId,           // 👈 new: pass current user id
  onChanged,
}: {
  itemId: string;
  claims: Claim[];
  meId?: string | null;
  onChanged?: () => void;
}) {
  const [busy, setBusy] = useState(false);

  const mine = useMemo(
    () => (meId ? claims.some(c => c.claimer_id === meId) : false),
    [claims, meId]
  );
  const claimedByOther = useMemo(
    () => claims.length > 0 && !mine,
    [claims, mine]
  );

  const label = mine ? 'Unclaim' : 'Claim';

  const onPress = async () => {
    if (busy) return;
    if (claimedByOther) {
      // Someone else already claimed; do nothing (button is disabled too)
      toast.info('Already claimed', 'Another member has claimed this.');
      return;
    }
    setBusy(true);
    try {
      const { data: { user }, error } = await supabase.auth.getUser();
      if (error) throw error;
      if (!user) {
        toast.info('Sign in required', 'Please sign in to claim.');
        return;
      }

      if (mine) {
        const { error: delErr } = await supabase
          .from('claims')
          .delete()
          .eq('item_id', itemId)
          .eq('claimer_id', user.id);
        if (delErr) throw delErr;
        toast.success('Unclaimed');
      } else {
        const { error: insErr } = await supabase
          .from('claims')
          .insert({ item_id: itemId, claimer_id: user.id });
        if (insErr) throw insErr;
        toast.success('Claimed');
      }

      onChanged?.();
    } catch (e: any) {
      toast.error('Claim action failed', e?.message ?? String(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Pressable
      onPress={onPress}
      disabled={busy || claimedByOther}
      style={{
        paddingVertical: 6,
        paddingHorizontal: 12,
        borderRadius: 999,
        backgroundColor: mine ? '#fde8e8' : '#e9f8ec',
        borderWidth: 1,
        borderColor: mine ? '#f8c7c7' : '#bce9cb',
        opacity: busy || claimedByOther ? 0.6 : 1,
      }}
    >
      <Text style={{ fontWeight: '800', fontSize: 12, color: mine ? '#c0392b' : '#1f9e4a' }}>
        {busy ? (mine ? 'Unclaiming…' : 'Claiming…') : label}
      </Text>
    </Pressable>
  );
}
