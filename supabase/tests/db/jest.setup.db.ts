/**
 * Database Test Setup
 *
 * IMPORTANT: These tests require:
 * 1. EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_ANON_KEY in .env.test
 * 2. SUPABASE_SERVICE_ROLE_KEY with admin permissions in .env.test
 * 3. Test users (alice, bob, carl) to exist in auth.users with specific UUIDs
 * 4. Database schema deployed (tables, functions, policies)
 *
 * If user creation fails, some tests will fail with FK constraint errors.
 */
import { createClient, SupabaseClient } from '@supabase/supabase-js';

export const supabaseAnon = createClient(
  process.env.EXPO_PUBLIC_SUPABASE_URL!,
  process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY!
);

export const supabaseService = createClient(
  process.env.EXPO_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
  { auth: { persistSession: false } }
);

// Fixed IDs to match SQL tests
export const ids = {
  alice: '00000000-0000-4000-8000-000000000001',
  bob:   '00000000-0000-4000-8000-000000000002',
  carl:  '00000000-0000-4000-8000-000000000003',
  event: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  L1:    '11111111-1111-4111-8111-111111111111',
  L2:    '22222222-2222-4222-8222-222222222222',
  I1:    '33333333-3333-4333-8333-333333333333',
  I2:    '44444444-4444-4444-8444-444444444444',
};

// Test user credentials
export const testUsers = {
  alice: { email: 'alice@test.local', password: 'test-password-alice-123' },
  bob: { email: 'bob@test.local', password: 'test-password-bob-456' },
  carl: { email: 'carl@test.local', password: 'test-password-carl-789' },
};

/**
 * Create test users in Supabase Auth (run once during setup)
 */
export async function createTestUsers() {
  const users = [
    { id: ids.alice, ...testUsers.alice },
    { id: ids.bob, ...testUsers.bob },
    { id: ids.carl, ...testUsers.carl },
  ];

  for (const user of users) {
    try {
      // Try to create user directly using service role
      const { error } = await supabaseService.auth.admin.createUser({
        email: user.email,
        password: user.password,
        email_confirm: true,
        user_metadata: { name: user.email.split('@')[0] }
      });

      if (error) {
        if (
          error.message.includes('already registered') ||
          error.message.includes('User already registered') ||
          error.message.includes('already been registered')
        ) {
          // User already exists, that's fine
          continue;
        } else {
          console.warn(`Could not create user ${user.email}:`, error.message);
        }
      }
    } catch (e: any) {
      console.warn(`Error creating user ${user.email}:`, e?.message || e);
    }
  }

  // Ensure profiles exist (in case trigger didn't run)
  for (const user of users) {
    try {
      const { error: profileError } = await supabaseService.from('profiles').upsert({
        id: user.id,
        display_name: user.email.split('@')[0]
      }, { onConflict: 'id' });

      if (profileError) {
        console.warn(`Could not create profile for ${user.email}:`, profileError.message);
      }
    } catch (e: any) {
      console.warn(`Error creating profile for ${user.email}:`, e?.message || e);
    }
  }
}

// Cache authenticated clients to avoid rate limiting
const clientCache: Record<string, SupabaseClient> = {};

/**
 * Sign in as a specific test user and return authenticated client
 */
export async function signInAs(userKey: 'alice' | 'bob' | 'carl'): Promise<SupabaseClient> {
  // Return cached client if available
  if (clientCache[userKey]) {
    return clientCache[userKey];
  }

  const credentials = testUsers[userKey];

  const { data, error } = await supabaseAnon.auth.signInWithPassword({
    email: credentials.email,
    password: credentials.password
  });

  if (error) {
    throw new Error(`Failed to sign in as ${userKey}: ${error.message}`);
  }

  // Create new client with this session and cache it
  const client = createClient(
    process.env.EXPO_PUBLIC_SUPABASE_URL!,
    process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY!,
    {
      global: {
        headers: {
          Authorization: `Bearer ${data.session.access_token}`
        }
      }
    }
  );

  clientCache[userKey] = client;
  return client;
}

/**
 * Seed minimal test data using service role
 */
export async function seedMinimal() {
  // Clean up first (in case of previous test runs)
  await supabaseService.from('claims').delete().in('item_id', [ids.I1, ids.I2]);
  await supabaseService.from('items').delete().in('id', [ids.I1, ids.I2]);
  await supabaseService.from('list_viewers').delete().eq('list_id', ids.L2);
  await supabaseService.from('list_recipients').delete().in('list_id', [ids.L1, ids.L2]);
  await supabaseService.from('lists').delete().in('id', [ids.L1, ids.L2]);
  await supabaseService.from('event_members').delete().eq('event_id', ids.event);
  await supabaseService.from('events').delete().eq('id', ids.event);

  // Create event
  const { error: eventError } = await supabaseService.from('events').insert({
    id: ids.event,
    title: 'Test Event',
    event_date: new Date(Date.now() + 7 * 864e5).toISOString().slice(0, 10),
    owner_id: ids.alice,
    recurrence: 'none',
    join_code: 'TEST123'
  });
  if (eventError) console.error('Event seed error:', eventError);

  // Create members
  const { error: membersError } = await supabaseService.from('event_members').insert([
    { event_id: ids.event, user_id: ids.alice, role: 'admin' },
    { event_id: ids.event, user_id: ids.bob, role: 'giver' },
  ]);
  if (membersError) console.error('Members seed error:', membersError);

  // Create lists
  const { error: listsError } = await supabaseService.from('lists').insert([
    { id: ids.L1, event_id: ids.event, name: 'List L1', visibility: 'event', created_by: ids.alice },
    { id: ids.L2, event_id: ids.event, name: 'List L2', visibility: 'selected', created_by: ids.alice },
  ]);
  if (listsError) console.error('Lists seed error:', listsError);

  // Create list recipients
  const { error: recipientsError } = await supabaseService.from('list_recipients').insert([
    { list_id: ids.L1, user_id: ids.bob },
    { list_id: ids.L2, user_id: ids.alice },
  ]);
  if (recipientsError) console.error('Recipients seed error:', recipientsError);

  // Create list viewers (for selected visibility)
  const { error: viewersError } = await supabaseService.from('list_viewers').insert([
    { list_id: ids.L2, user_id: ids.alice }
  ]);
  if (viewersError) console.error('Viewers seed error:', viewersError);

  // Create items (FIXED: using 'name' not 'title')
  const { error: itemsError } = await supabaseService.from('items').insert([
    { id: ids.I1, list_id: ids.L1, name: 'Item A1', created_by: ids.alice },
    { id: ids.I2, list_id: ids.L2, name: 'Item A2', created_by: ids.alice },
  ]);
  if (itemsError) console.error('Items seed error:', itemsError);

  // Create claims (FIXED: using 'claimer_id' not 'created_by')
  // Skip if users don't exist in auth.users (FK constraint will fail)
  const { error: claimsError } = await supabaseService.from('claims').insert([
    { id: '55555555-5555-4555-8555-555555555555', item_id: ids.I1, claimer_id: ids.bob }
  ]);
  if (claimsError && !claimsError.message.includes('foreign key')) {
    console.error('Claims seed error:', claimsError);
  }
}

/**
 * Clean up test data
 */
export async function cleanupTestData() {
  await supabaseService.from('claims').delete().in('item_id', [ids.I1, ids.I2]);
  await supabaseService.from('items').delete().in('id', [ids.I1, ids.I2]);
  await supabaseService.from('list_viewers').delete().eq('list_id', ids.L2);
  await supabaseService.from('list_recipients').delete().in('list_id', [ids.L1, ids.L2]);
  await supabaseService.from('lists').delete().in('id', [ids.L1, ids.L2]);
  await supabaseService.from('event_members').delete().eq('event_id', ids.event);
  await supabaseService.from('events').delete().eq('id', ids.event);
}
