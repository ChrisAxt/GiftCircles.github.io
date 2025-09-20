jest.mock('../supabase', () => ({
  supabase: { rpc: jest.fn() },
}));

const { supabase } = require('../supabase');

describe('fetchClaimCountsByList', () => {
  beforeEach(() => {
    jest.resetModules();
    (supabase.rpc as jest.Mock).mockReset();
  });

  it('maps RPC rows into an id->count object', async () => {
    (supabase.rpc as jest.Mock).mockResolvedValueOnce({
      data: [
        { list_id: 'l1', claims_count: 2 },
        { list_id: 'l2', claims_count: 0 },
      ],
      error: null,
    });

    // require AFTER mocking so the module uses the mocked supabase
    const { fetchClaimCountsByList } = require('../claimCounts');
    const res = await fetchClaimCountsByList(['l1', 'l2']);

    expect(supabase.rpc).toHaveBeenCalledWith('claim_counts_for_lists', {
      p_list_ids: ['l1', 'l2'],
    });
    expect(res).toEqual({ l1: 2, l2: 0 });
  });

  it('returns empty object when listIds is empty', async () => {
    const { fetchClaimCountsByList } = require('../claimCounts');
    const res = await fetchClaimCountsByList([]);
    expect(res).toEqual({});
    expect(supabase.rpc).not.toHaveBeenCalled();
  });
});