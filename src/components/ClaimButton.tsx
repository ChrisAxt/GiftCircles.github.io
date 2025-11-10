// src/components/ClaimButton.tsx
import React, { useMemo, useState } from 'react';
import { Pressable, Text, ActivityIndicator, View } from 'react-native';
import { useTranslation } from 'react-i18next';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';

type Claim = { id: string; item_id: string; claimer_id: string; created_at?: string };

type Props = {
  itemId: string;
  claims: Claim[];
  meId: string | null | undefined;
  onChanged?: () => void; // call to refresh list after action
  isRandomAssignment?: boolean; // true if this list has random assignment enabled
  isAssignedToMe?: boolean; // true if this item is assigned to current user
  onRequestSplit?: () => void; // callback to open split request modal
};

export default function ClaimButton({ itemId, claims, meId, onChanged, isRandomAssignment = false, isAssignedToMe = false, onRequestSplit }: Props) {
  const { t } = useTranslation();
  const [busy, setBusy] = useState(false);

  const mine = useMemo(() => !!meId && claims.some(c => c.claimer_id === meId), [claims, meId]);
  const isClaimed = claims.length > 0;

  // For random assignment: determine label and disabled state
  let label: string;
  let disabled: boolean;
  let isRequestSplit = false; // New flag for "Request to Split" button

  if (isRandomAssignment) {
    if (isAssignedToMe && mine) {
      // Assigned to me and I claimed it: show "Unclaim" (enabled)
      label = t('claimButton.unclaim');
      disabled = false;
    } else if (isClaimed) {
      // Claimed/assigned to someone else: show "Assigned" (disabled)
      label = t('claimButton.assigned', 'Assigned');
      disabled = true;
    } else {
      // Not assigned to anyone: show "Not assigned" (disabled)
      label = t('claimButton.notAssigned', 'Not assigned');
      disabled = true;
    }
  } else {
    // Normal (non-random) assignment behavior
    if (isClaimed && !mine) {
      // Someone else claimed it: show "Request to Split" (enabled)
      label = t('claimButton.requestToSplit', 'Request to Split');
      disabled = false;
      isRequestSplit = true;
    } else {
      // Either unclaimed or mine
      disabled = false;
      label = mine ? t('claimButton.unclaim') : t('claimButton.claim');
    }
  }

  const bg = disabled ? '#e5e7eb' : isRequestSplit ? '#e9f0fc' : mine ? '#fde8e8' : '#e9f8ec';
  const border = disabled ? '#e5e7eb' : isRequestSplit ? '#bcd4f5' : mine ? '#f8c7c7' : '#bce9cb';
  const fg = disabled ? '#9aa3af' : isRequestSplit ? '#2e95f1' : mine ? '#c0392b' : '#1f9e4a';

  const press = async () => {
    if (busy || disabled) return;

    // If this is a "Request to Split" button, open the modal
    if (isRequestSplit) {
      onRequestSplit?.();
      return;
    }

    try {
      setBusy(true);

      // Use SECURITY DEFINER RPCs so RLS/visibility can't block legit actions
      const fn = mine ? 'unclaim_item' : 'claim_item';
      const { error } = await supabase.rpc(fn, { p_item_id: itemId });

      if (error) {
        const msg = String(error.message || error);
        if (msg.includes('not_authenticated')) {
          toast.error(t('claimButton.errors.signInRequiredTitle'), { text2: t('claimButton.errors.signInRequiredBody') });
        } else if (msg.includes('not_authorized')) {
          toast.error(t('claimButton.errors.notAllowedTitle'), { text2: t('claimButton.errors.notAllowedBody') });
        } else {
          toast.error(t('claimButton.errors.actionFailedTitle'), { text2: msg });
        }
        return;
      }

      toast.success(mine ? t('claimButton.unclaimed') : t('claimButton.claimed'));
      onChanged?.(); // realtime should also update, this just makes it snappy
    } catch (e: any) {
      toast.error(t('claimButton.errors.actionFailedTitle'), e?.message ?? String(e));
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
