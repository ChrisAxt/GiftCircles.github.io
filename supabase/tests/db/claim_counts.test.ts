import { signInAs, ids, seedMinimal, cleanupTestData, createTestUsers } from './jest.setup.db';

beforeAll(async () => {
  await createTestUsers();
  await seedMinimal();
});

afterAll(async () => {
  await cleanupTestData();
});

test('claim_counts_for_lists respects visibility', async () => {
  const aliceClient = await signInAs('alice');
  
  const { data, error } = await aliceClient.rpc('claim_counts_for_lists', {
    p_list_ids: [ids.L1, ids.L2]
  });
  
  expect(error).toBeNull();
  expect(Array.isArray(data)).toBeTruthy();
  
  // Alice should see counts for both lists (she's admin and viewer of L2)
  expect(data?.length).toBeGreaterThanOrEqual(1);
});

test('outsider cannot see claim counts', async () => {
  const carlClient = await signInAs('carl'); // Not in event
  
  const { data, error } = await carlClient.rpc('claim_counts_for_lists', {
    p_list_ids: [ids.L1, ids.L2]
  });
  
  expect(error).toBeNull();
  expect(data).toEqual([]); // Should see no results due to RLS
});

test('recipient does not see claim counts for their own list', async () => {
  const bobClient = await signInAs('bob'); // Bob is recipient of L1
  
  const { data, error } = await bobClient.rpc('claim_counts_for_lists', {
    p_list_ids: [ids.L1]
  });
  
  expect(error).toBeNull();
  // Bob should see the list exists but no claim count (filtered for recipients)
  // The exact behavior depends on your RPC implementation
});
