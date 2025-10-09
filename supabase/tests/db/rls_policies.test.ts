import { signInAs, ids, seedMinimal, cleanupTestData, createTestUsers } from './jest.setup.db';

beforeAll(async () => {
  await createTestUsers();
  await seedMinimal();
});

afterAll(async () => {
  await cleanupTestData();
});

test('outsider cannot update someone else item (RLS)', async () => {
  const carlClient = await signInAs('carl'); // Carl is not in the event

  const { error } = await carlClient
    .from('items')
    .update({ name: 'hacked' }) // FIXED: using 'name' not 'title'
    .eq('id', ids.I1);

  expect(error).toBeTruthy();
  // RLS should block the update (could be PGRST301 or other error codes)
  expect(error?.code).toMatch(/PGRST|42501/);
});

test('member can update their own item', async () => {
  const aliceClient = await signInAs('alice');
  
  const { error } = await aliceClient
    .from('items')
    .update({ name: 'Updated by Alice' })
    .eq('id', ids.I1);
  
  expect(error).toBeNull();
});

test('outsider cannot see event members', async () => {
  const carlClient = await signInAs('carl');
  
  const { data, error } = await carlClient
    .from('event_members')
    .select('*')
    .eq('event_id', ids.event);
  
  expect(error).toBeNull();
  expect(data).toEqual([]); // RLS hides rows from non-members
});

test('member can see all event members', async () => {
  const aliceClient = await signInAs('alice');
  
  const { data, error } = await aliceClient
    .from('event_members')
    .select('*')
    .eq('event_id', ids.event);
  
  expect(error).toBeNull();
  expect(data?.length).toBeGreaterThanOrEqual(2); // Alice and Bob at minimum
});

test('member can see other members after joining', async () => {
  // This tests the bug we just fixed
  const aliceClient = await signInAs('alice');
  const bobClient = await signInAs('bob');
  
  // Alice queries members
  const { data: aliceView } = await aliceClient
    .from('event_members')
    .select('user_id')
    .eq('event_id', ids.event);
  
  // Bob queries members
  const { data: bobView } = await bobClient
    .from('event_members')
    .select('user_id')
    .eq('event_id', ids.event);
  
  // Both should see the same member count
  expect(aliceView?.length).toBe(bobView?.length);
  expect(aliceView?.length).toBeGreaterThanOrEqual(2);
});

test('recipient cannot claim their own item', async () => {
  const bobClient = await signInAs('bob'); // Bob is recipient of L1
  
  const { error } = await bobClient.rpc('claim_item', { p_item_id: ids.I1 });
  
  expect(error?.message).toContain('not_authorized');
});

test('non-recipient can attempt to claim item', async () => {
  const aliceClient = await signInAs('alice'); // Alice is NOT recipient of L1

  const { error } = await aliceClient.rpc('claim_item', { p_item_id: ids.I1 });

  // I1 may already be claimed, but Alice is authorized to try
  // The error (if any) should not be about authorization
  if (error && error.message === 'not_authorized') {
    throw new Error('Alice should be authorized to claim items on L1 (she is not a recipient)');
  }
  // Otherwise pass - either succeeds or fails for other reasons (already claimed, etc)
});