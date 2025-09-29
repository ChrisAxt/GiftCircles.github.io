// src/lib/claimCounts.ts
import { supabase } from './supabase';

/**
 * Returns: { [list_id]: <number of items on that list that have at least 1 claim> }
 *
 * Strategy:
 *  1) Try an RPC (optional). Accepts various common shapes.
 *  2) Fallback: load items for these lists, load claims for those items,
 *     then count distinct claimed items per list.
 */
export async function fetchClaimCountsByList(listIds: string[]): Promise<Record<string, number>> {
  if (!listIds?.length) return {};

  // ---- (1) Optional RPC path (tolerant to different return shapes)
  try {
    // If you have an RPC like claimed_counts_by_list(p_list_ids uuid[])
    const { data, error } = await supabase.rpc('claimed_counts_by_list', { p_list_ids: listIds });
    if (!error && Array.isArray(data)) {
      const out: Record<string, number> = {};
      for (const row of data as any[]) {
        const listId = row.list_id || row.id || row.list || row.listId;
        const count =
          Number(row.claimed ?? row.claimed_count ?? row.count ?? row.cnt ?? 0);
        if (listId) out[listId] = count;
      }
      // If it looks like a real result, use it.
      if (Object.keys(out).length) return out;
    }
  } catch {
    // ignore and fall back
  }

  // ---- (2) Fallback: items -> claims
  // Load items for these lists
  const { data: items, error: itemsErr } = await supabase
    .from('items')
    .select('id,list_id')
    .in('list_id', listIds);

  if (itemsErr) throw itemsErr;
  if (!items?.length) return {};

  const allItemIds = items.map(i => i.id);

  // Load claims for those items (RLS should hide anything recipients shouldn't see)
  const { data: claims, error: claimsErr } = await supabase
    .from('claims')
    .select('item_id')
    .in('item_id', allItemIds);

  // If claims are fully locked down by RLS, just say 0s
  if (claimsErr) return Object.fromEntries(listIds.map(lid => [lid, 0]));

  const claimedSet = new Set((claims ?? []).map(c => c.item_id));
  const out: Record<string, number> = {};
  for (const it of items) {
    if (claimedSet.has(it.id)) {
      out[it.list_id] = (out[it.list_id] || 0) + 1;
    }
  }
  return out;
}
