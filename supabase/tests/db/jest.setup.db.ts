/**
 * Database Integration Test Setup
 *
 * IMPORTANT: These tests run against your REAL Supabase database.
 *
 * Requirements:
 * 1. .env.test file with:
 *    - EXPO_PUBLIC_SUPABASE_URL
 *    - EXPO_PUBLIC_SUPABASE_ANON_KEY
 *    - SUPABASE_SERVICE_ROLE_KEY (for admin operations)
 * 2. Database schema deployed (tables, functions, policies)
 *
 * Test users are created dynamically with unique emails per test run.
 */
import { createClient, SupabaseClient, User } from '@supabase/supabase-js';
import * as dotenv from 'dotenv';

// Load environment variables
dotenv.config({ path: '.env.test' });

if (!process.env.EXPO_PUBLIC_SUPABASE_URL) {
  throw new Error('EXPO_PUBLIC_SUPABASE_URL not set in .env.test');
}
if (!process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY) {
  throw new Error('EXPO_PUBLIC_SUPABASE_ANON_KEY not set in .env.test');
}
if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('SUPABASE_SERVICE_ROLE_KEY not set in .env.test');
}

// Anonymous client (respects RLS)
export const supabaseAnon = createClient(
  process.env.EXPO_PUBLIC_SUPABASE_URL,
  process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY
);

// Service role client (bypasses RLS)
export const supabaseService = createClient(
  process.env.EXPO_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { persistSession: false } }
);

// Dynamic IDs - populated after user creation
export const ids: {
  alice: string;
  bob: string;
  carl: string;
  event: string;
  L1: string;
  L2: string;
  I1: string;
  I2: string;
  claim1: string;
} = {
  alice: '',
  bob: '',
  carl: '',
  event: '',
  L1: '',
  L2: '',
  I1: '',
  I2: '',
  claim1: '',
};

// Generate unique test run ID to avoid conflicts
const testRunId = Date.now().toString(36);

// Test user credentials with unique emails per test run
export const testUsers = {
  alice: {
    email: `alice-${testRunId}@test.local`,
    password: 'TestPassword123!',
    name: 'Alice Test'
  },
  bob: {
    email: `bob-${testRunId}@test.local`,
    password: 'TestPassword123!',
    name: 'Bob Test'
  },
  carl: {
    email: `carl-${testRunId}@test.local`,
    password: 'TestPassword123!',
    name: 'Carl Test'
  },
};

// Cache authenticated clients
const clientCache: Record<string, SupabaseClient> = {};

// Track created users for cleanup
const createdUserIds: string[] = [];

/**
 * Create test users in Supabase Auth
 * Returns the actual UUIDs assigned by Supabase
 */
export async function createTestUsers(): Promise<void> {
  console.log('Creating test users...');

  for (const [key, userData] of Object.entries(testUsers)) {
    const { data, error } = await supabaseService.auth.admin.createUser({
      email: userData.email,
      password: userData.password,
      email_confirm: true,
      user_metadata: { display_name: userData.name }
    });

    if (error) {
      throw new Error(`Failed to create user ${key}: ${error.message}`);
    }

    if (!data.user) {
      throw new Error(`No user returned for ${key}`);
    }

    // Store the actual UUID
    ids[key as keyof typeof testUsers] = data.user.id;
    createdUserIds.push(data.user.id);

    // Ensure profile exists with display name
    const { error: profileError } = await supabaseService.from('profiles').upsert({
      id: data.user.id,
      display_name: userData.name
    }, { onConflict: 'id' });

    if (profileError) {
      console.warn(`Profile creation warning for ${key}:`, profileError.message);
    }

    console.log(`  Created ${key}: ${data.user.id}`);
  }
}

/**
 * Delete test users (cleanup)
 */
export async function deleteTestUsers(): Promise<void> {
  console.log('Cleaning up test users...');

  for (const userId of createdUserIds) {
    try {
      await supabaseService.auth.admin.deleteUser(userId);
      console.log(`  Deleted user: ${userId}`);
    } catch (e: any) {
      console.warn(`  Failed to delete user ${userId}:`, e?.message);
    }
  }

  // Clear caches
  Object.keys(clientCache).forEach(key => delete clientCache[key]);
  createdUserIds.length = 0;
}

/**
 * Sign in as a specific test user and return authenticated client
 */
export async function signInAs(userKey: 'alice' | 'bob' | 'carl'): Promise<SupabaseClient> {
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

  if (!data.session) {
    throw new Error(`No session returned for ${userKey}`);
  }

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
 * Seed minimal test data
 *
 * Creates:
 * - Event owned by Alice with join_code 'TESTJOIN'
 * - Alice (admin) and Bob (giver) as members
 * - Carl is NOT a member (outsider for testing)
 * - L1: visibility='event', Bob is recipient
 * - L2: visibility='selected', Alice is recipient and viewer
 * - I1: item on L1, claimed by Bob
 * - I2: item on L2 (unclaimed)
 */
export async function seedMinimal(): Promise<void> {
  console.log('Seeding test data...');

  if (!ids.alice || !ids.bob) {
    throw new Error('Users must be created before seeding data');
  }

  // Generate unique IDs for this test run
  const eventId = crypto.randomUUID();
  const l1Id = crypto.randomUUID();
  const l2Id = crypto.randomUUID();
  const i1Id = crypto.randomUUID();
  const i2Id = crypto.randomUUID();
  const claim1Id = crypto.randomUUID();

  // Create event
  const { error: eventError } = await supabaseService.from('events').insert({
    id: eventId,
    title: 'Integration Test Event',
    event_date: new Date(Date.now() + 7 * 864e5).toISOString().slice(0, 10),
    owner_id: ids.alice,
    recurrence: 'none',
    join_code: `TEST${testRunId.toUpperCase()}`
  });
  if (eventError) throw new Error(`Event seed failed: ${eventError.message}`);
  ids.event = eventId;
  console.log(`  Created event: ${eventId}`);

  // Create members (Alice is already admin from event creation trigger, add Bob as giver)
  // Use upsert to handle case where Alice is already a member
  const { error: membersError } = await supabaseService.from('event_members').upsert([
    { event_id: eventId, user_id: ids.alice, role: 'admin' },
    { event_id: eventId, user_id: ids.bob, role: 'giver' },
  ], { onConflict: 'event_id,user_id' });
  if (membersError) throw new Error(`Members seed failed: ${membersError.message}`);
  console.log('  Created event members');

  // Create lists
  const { error: listsError } = await supabaseService.from('lists').insert([
    { id: l1Id, event_id: eventId, name: 'Test List L1', visibility: 'event', created_by: ids.alice },
    { id: l2Id, event_id: eventId, name: 'Test List L2', visibility: 'selected', created_by: ids.alice },
  ]);
  if (listsError) throw new Error(`Lists seed failed: ${listsError.message}`);
  ids.L1 = l1Id;
  ids.L2 = l2Id;
  console.log('  Created lists');

  // Create list recipients (Bob is recipient of L1, Alice is recipient of L2)
  const { error: recipientsError } = await supabaseService.from('list_recipients').insert([
    { list_id: l1Id, user_id: ids.bob },
    { list_id: l2Id, user_id: ids.alice },
  ]);
  if (recipientsError) throw new Error(`Recipients seed failed: ${recipientsError.message}`);
  console.log('  Created list recipients');

  // Create list viewers (Alice can view L2 which has selected visibility)
  const { error: viewersError } = await supabaseService.from('list_viewers').insert([
    { list_id: l2Id, user_id: ids.alice }
  ]);
  if (viewersError) throw new Error(`Viewers seed failed: ${viewersError.message}`);
  console.log('  Created list viewers');

  // Create items
  const { error: itemsError } = await supabaseService.from('items').insert([
    { id: i1Id, list_id: l1Id, name: 'Test Item 1', created_by: ids.alice },
    { id: i2Id, list_id: l2Id, name: 'Test Item 2', created_by: ids.alice },
  ]);
  if (itemsError) throw new Error(`Items seed failed: ${itemsError.message}`);
  ids.I1 = i1Id;
  ids.I2 = i2Id;
  console.log('  Created items');

  // Create claim (Bob claims item on L1)
  const { error: claimsError } = await supabaseService.from('claims').insert([
    { id: claim1Id, item_id: i1Id, claimer_id: ids.bob }
  ]);
  if (claimsError) throw new Error(`Claims seed failed: ${claimsError.message}`);
  ids.claim1 = claim1Id;
  console.log('  Created claims');
}

/**
 * Clean up all test data
 */
export async function cleanupTestData(): Promise<void> {
  console.log('Cleaning up test data...');

  if (ids.event) {
    // Delete in correct order (respecting FK constraints)
    if (ids.I1 || ids.I2) {
      await supabaseService.from('claims').delete().in('item_id', [ids.I1, ids.I2].filter(Boolean));
      await supabaseService.from('items').delete().in('id', [ids.I1, ids.I2].filter(Boolean));
    }

    if (ids.L1 || ids.L2) {
      await supabaseService.from('list_viewers').delete().in('list_id', [ids.L1, ids.L2].filter(Boolean));
      await supabaseService.from('list_recipients').delete().in('list_id', [ids.L1, ids.L2].filter(Boolean));
      await supabaseService.from('lists').delete().in('id', [ids.L1, ids.L2].filter(Boolean));
    }

    await supabaseService.from('event_members').delete().eq('event_id', ids.event);
    await supabaseService.from('events').delete().eq('id', ids.event);
  }

  // Reset IDs
  ids.event = '';
  ids.L1 = '';
  ids.L2 = '';
  ids.I1 = '';
  ids.I2 = '';
  ids.claim1 = '';

  console.log('  Cleanup complete');
}

/**
 * Global setup - runs once before all tests
 */
beforeAll(async () => {
  console.log('\n=== Database Integration Tests Setup ===\n');
  await createTestUsers();
  await seedMinimal();
  console.log('\n=== Setup Complete ===\n');
}, 120000); // 2 minute timeout for setup

/**
 * Global cleanup - runs once after all tests
 */
afterAll(async () => {
  console.log('\n=== Database Integration Tests Cleanup ===\n');
  await cleanupTestData();
  await deleteTestUsers();
  console.log('\n=== Cleanup Complete ===\n');
}, 120000); // 2 minute timeout for cleanup
