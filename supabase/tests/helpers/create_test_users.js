#!/usr/bin/env node
/**
 * Create test users for database tests
 * Run: node supabase/tests/helpers/create_test_users.js
 */

require('dotenv').config({ path: '.env.test' });
const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseServiceKey) {
  console.error('ERROR: Missing environment variables');
  console.error('Required: EXPO_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY');
  console.error('Make sure .env.test has your service role key (not anon key)');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseServiceKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
});

const testUsers = [
  {
    id: '00000000-0000-4000-8000-000000000001',
    email: 'alice@test.local',
    password: 'test-password-alice-123'
  },
  {
    id: '00000000-0000-4000-8000-000000000002',
    email: 'bob@test.local',
    password: 'test-password-bob-123'
  },
  {
    id: '00000000-0000-4000-8000-000000000003',
    email: 'carl@test.local',
    password: 'test-password-carl-123'
  }
];

async function createTestUsers() {
  console.log('Creating test users...\n');

  for (const user of testUsers) {
    try {
      const { data, error } = await supabase.auth.admin.createUser({
        email: user.email,
        password: user.password,
        email_confirm: true,
        user_metadata: {
          test_user: true
        }
      });

      if (error) {
        if (error.message.includes('already registered')) {
          console.log(`✓ ${user.email} already exists`);
        } else {
          console.error(`✗ ${user.email}: ${error.message}`);
        }
      } else {
        console.log(`✓ Created ${user.email} (id: ${data.user.id})`);

        // Check if ID matches expected
        if (data.user.id !== user.id) {
          console.warn(`  WARNING: ID mismatch! Expected ${user.id}, got ${data.user.id}`);
          console.warn(`  You'll need to update jest.setup.db.ts with the actual ID`);
        }
      }
    } catch (e) {
      console.error(`✗ ${user.email}: ${e.message}`);
    }
  }

  console.log('\nDone! Run: npm test -- supabase/tests/db');
}

createTestUsers().catch(console.error);
