import { supabaseAnon, signInAs, createTestUsers } from './jest.setup.db';

beforeAll(async () => {
  await createTestUsers();
});

test('create_event_and_admin rejects empty title', async () => {
  const client = await signInAs('alice');

  const { error } = await client.rpc('create_event_and_admin', {
    p_title: '  ',
    p_event_date: new Date().toISOString().slice(0, 10),
    p_recurrence: 'none',
    p_description: null
  });

  // Function should validate and reject empty/whitespace titles
  expect(error).toBeTruthy();
  expect(error?.message).toMatch(/invalid_parameter.*title_required/i);
});

test('create_event_and_admin rejects invalid recurrence', async () => {
  const client = await signInAs('alice');

  const { error } = await client.rpc('create_event_and_admin', {
    p_title: 'Valid Title',
    p_event_date: new Date().toISOString().slice(0, 10),
    p_recurrence: 'bananas', // invalid
    p_description: null
  });

  // Function should validate recurrence value
  expect(error).toBeTruthy();
  expect(error?.message).toMatch(/invalid_parameter.*invalid_recurrence/i);
});

test('create_list_with_people rejects bad visibility', async () => {
  const client = await signInAs('alice');
  
  const { error } = await client.rpc('create_list_with_people', {
    p_event_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    p_name: 'List',
    p_visibility: 'oops' as any, // invalid enum
    p_recipients: [],
    p_hidden_recipients: [],
    p_viewers: []
  });
  
  expect(error?.message).toMatch(/invalid|enum/i);
});

test('join_event requires a code', async () => {
  const client = await signInAs('carl');

  const { error } = await client.rpc('join_event', { p_code: '   ' });

  // Function should validate empty/whitespace codes
  expect(error).toBeTruthy();
  expect(error?.message).toMatch(/invalid_parameter.*code_required/i);
});

test('join_event rejects invalid code', async () => {
  const client = await signInAs('carl');
  
  const { error } = await client.rpc('join_event', { p_code: 'FAKE-CODE-999' });
  
  expect(error?.message).toContain('invalid_join_code');
});

test('unauthenticated user cannot create event', async () => {
  const { error } = await supabaseAnon.rpc('create_event_and_admin', {
    p_title: 'Test',
    p_event_date: new Date().toISOString().slice(0, 10),
    p_recurrence: 'none',
    p_description: null
  });

  // Function should reject unauthenticated requests
  expect(error).toBeTruthy();
  expect(error?.message).toMatch(/not_authenticated/i);
});