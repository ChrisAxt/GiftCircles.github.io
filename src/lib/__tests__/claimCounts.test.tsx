import { fetchClaimCountsByList } from '../claimCounts';
import { supabase } from '../supabase';

jest.mock('../supabase', () => ({
  supabase: {
    rpc: jest.fn(),
    from: jest.fn(),
  },
}));

describe('fetchClaimCountsByList', () => {
  beforeEach(() => {
    (supabase.rpc as jest.Mock).mockReset();
    (supabase.from as jest.Mock).mockReset();
  });

  it('maps RPC rows into an id->count object', async () => {
    (supabase.rpc as jest.Mock).mockResolvedValueOnce({
      data: [
        { list_id: 'l1', claimed_count: 2 },
        { list_id: 'l2', claimed_count: 0 },
      ],
      error: null,
    });

    const res = await fetchClaimCountsByList(['l1', 'l2']);

    expect(supabase.rpc).toHaveBeenCalledWith('get_claim_counts_by_list', {
      p_list_ids: ['l1', 'l2'],
    });
    expect(res).toEqual({ l1: 2, l2: 0 });
  });

  it('falls back to direct query when RPC returns empty', async () => {
    // RPC returns empty array (no data)
    (supabase.rpc as jest.Mock).mockResolvedValueOnce({
      data: [],
      error: null,
    });

    // Mock the fallback path
    const mockSelectItems = jest.fn().mockReturnValue({
      in: jest.fn().mockResolvedValue({
        data: [
          { id: 'item1', list_id: 'l1' },
          { id: 'item2', list_id: 'l1' },
          { id: 'item3', list_id: 'l2' },
        ],
        error: null,
      }),
    });

    const mockSelectClaims = jest.fn().mockReturnValue({
      in: jest.fn().mockResolvedValue({
        data: [
          { item_id: 'item1' },
          { item_id: 'item3' },
        ],
        error: null,
      }),
    });

    (supabase.from as jest.Mock)
      .mockReturnValueOnce({ select: mockSelectItems })
      .mockReturnValueOnce({ select: mockSelectClaims });

    const res = await fetchClaimCountsByList(['l1', 'l2']);

    expect(res).toEqual({ l1: 1, l2: 1 });
  });

  it('returns empty object when listIds is empty', async () => {
    const res = await fetchClaimCountsByList([]);
    expect(res).toEqual({});
    expect(supabase.rpc).not.toHaveBeenCalled();
  });
});