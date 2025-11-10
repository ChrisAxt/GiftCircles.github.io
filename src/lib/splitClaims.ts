// Split Claim Functions
import { supabase } from './supabase';
import { PendingSplitRequest } from '../types/splitClaims';

/**
 * Request to split claim an item with the original claimer
 */
export async function requestClaimSplit(itemId: string): Promise<string> {
  const { data, error } = await supabase.rpc('request_claim_split', {
    p_item_id: itemId,
  });

  if (error) throw error;
  return data as string; // Returns request_id
}

/**
 * Get all pending split requests for the current user (as original claimer)
 */
export async function getMySplitRequests(): Promise<PendingSplitRequest[]> {
  const { data, error } = await supabase.rpc('get_my_split_requests');

  if (error) throw error;
  return data as PendingSplitRequest[];
}

/**
 * Accept a split claim request
 */
export async function acceptClaimSplit(requestId: string): Promise<void> {
  const { error } = await supabase.rpc('accept_claim_split', {
    p_request_id: requestId,
  });

  if (error) throw error;
}

/**
 * Deny a split claim request
 */
export async function denyClaimSplit(requestId: string): Promise<void> {
  const { error } = await supabase.rpc('deny_claim_split', {
    p_request_id: requestId,
  });

  if (error) throw error;
}

/**
 * Subscribe to split claim request changes for realtime updates
 */
export function subscribeToSplitRequests(
  userId: string,
  onRequestReceived: (request: any) => void
) {
  return supabase
    .channel('claim_split_requests')
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'claim_split_requests',
        filter: `original_claimer_id=eq.${userId}`,
      },
      (payload) => {
        onRequestReceived(payload.new);
      }
    )
    .subscribe();
}
