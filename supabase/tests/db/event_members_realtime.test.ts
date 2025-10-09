import { signInAs, ids, seedMinimal, cleanupTestData, supabaseService, createTestUsers } from './jest.setup.db';

beforeAll(async () => {
  await createTestUsers();
  await seedMinimal();
});

afterAll(async () => {
  await cleanupTestData();
});

test('new member can see existing members immediately', async () => {
  // Create a fresh event with just Alice
  const testEventId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb01';
  
  await supabaseService.from('events').insert({
    id: testEventId,
    title: 'Fresh Event',
    owner_id: ids.alice,
    recurrence: 'none',
    join_code: 'FRESH99'
  });
  
  await supabaseService.from('event_members').insert({
    event_id: testEventId,
    user_id: ids.alice,
    role: 'admin'
  });
  
  // Bob joins via RPC
  const bobClient = await signInAs('bob');
  const { error: joinError } = await bobClient.rpc('join_event', { p_code: 'FRESH99' });
  expect(joinError).toBeNull();
  
  // Bob should immediately see all members (including Alice)
  const { data: members, error } = await bobClient
    .from('event_members')
    .select('user_id')
    .eq('event_id', testEventId);
  
  expect(error).toBeNull();
  expect(members?.length).toBe(2); // Alice + Bob
  expect(members?.map(m => m.user_id)).toContain(ids.alice);
  expect(members?.map(m => m.user_id)).toContain(ids.bob);
  
  // Cleanup
  await supabaseService.from('event_members').delete().eq('event_id', testEventId);
  await supabaseService.from('events').delete().eq('id', testEventId);
});

test('no restrictive policies block member visibility', async () => {
  // Query pg_policy to ensure no restrictive policies on event_members
  // Note: We need to query by table name, not using ::regclass which isn't supported in TypeScript
  const { data, error } = await supabaseService
    .from('pg_policy')
    .select('polname, polpermissive')
    .eq('tablename', 'event_members');

  // This test verifies our fix: should have NO restrictive policies
  const restrictive = data?.filter((p: any) => p.polpermissive === false);

  expect(restrictive?.length).toBe(0);
});