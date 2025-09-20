import { supabase } from './supabase';

export async function fetchClaimCountsByList(listIds: string[]): Promise<Record<string, number>> {
  if (!listIds.length) return {};

  // 👇 handle a mocked or failed call that returns undefined
  const rpc = await supabase.rpc('claim_counts_for_lists', { p_list_ids: listIds });
  const data = rpc?.data ?? [];
  const error = rpc?.error ?? null;
  if (error) throw error;

  const rows = (data ?? []) as Array<{ list_id: string; claims_count: number | string | null }>;
  const byId = new Map<string, number>();
  for (const r of rows) byId.set(r.list_id, Number(r?.claims_count ?? 0) || 0);

  const out: Record<string, number> = {};
  for (const id of listIds) out[id] = byId.get(id) ?? 0;
  return out;
}