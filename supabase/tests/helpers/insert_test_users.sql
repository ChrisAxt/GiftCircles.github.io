-- Insert test users with specific UUIDs (only works on local Supabase)
-- For hosted Supabase, use create_test_users.js instead

INSERT INTO auth.users (
  id,
  instance_id,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at,
  raw_app_meta_data,
  raw_user_meta_data,
  aud,
  role
) VALUES
  (
    '00000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-0000-0000-000000000000'::uuid,
    'alice@test.local',
    crypt('test-password-alice-123', gen_salt('bf')),
    now(),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    'authenticated',
    'authenticated'
  ),
  (
    '00000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-0000-0000-000000000000'::uuid,
    'bob@test.local',
    crypt('test-password-bob-123', gen_salt('bf')),
    now(),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    'authenticated',
    'authenticated'
  ),
  (
    '00000000-0000-4000-8000-000000000003'::uuid,
    '00000000-0000-0000-0000-000000000000'::uuid,
    'carl@test.local',
    crypt('test-password-carl-123', gen_salt('bf')),
    now(),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    'authenticated',
    'authenticated'
  )
ON CONFLICT (id) DO NOTHING;

-- Create corresponding profiles
INSERT INTO public.profiles (id, email)
VALUES
  ('00000000-0000-4000-8000-000000000001'::uuid, 'alice@test.local'),
  ('00000000-0000-4000-8000-000000000002'::uuid, 'bob@test.local'),
  ('00000000-0000-4000-8000-000000000003'::uuid, 'carl@test.local')
ON CONFLICT (id) DO NOTHING;

SELECT 'Created test users:' as message;
SELECT id, email FROM auth.users WHERE email LIKE '%@test.local';
