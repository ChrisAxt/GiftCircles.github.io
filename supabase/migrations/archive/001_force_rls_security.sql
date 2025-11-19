-- Migration: Force RLS on all public tables
-- Purpose: Ensure SECURITY DEFINER functions cannot bypass RLS policies
-- Date: 2025-10-02

BEGIN;

-- Force RLS on all core tables to prevent SECURITY DEFINER bypass
ALTER TABLE public.events FORCE ROW LEVEL SECURITY;
ALTER TABLE public.event_members FORCE ROW LEVEL SECURITY;
ALTER TABLE public.lists FORCE ROW LEVEL SECURITY;
ALTER TABLE public.items FORCE ROW LEVEL SECURITY;
ALTER TABLE public.claims FORCE ROW LEVEL SECURITY;
ALTER TABLE public.list_recipients FORCE ROW LEVEL SECURITY;
ALTER TABLE public.list_viewers FORCE ROW LEVEL SECURITY;
ALTER TABLE public.list_exclusions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE public.user_plans FORCE ROW LEVEL SECURITY;

-- Verify RLS is forced
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename IN ('events', 'event_members', 'lists', 'items', 'claims',
                        'list_recipients', 'list_viewers', 'list_exclusions',
                        'profiles', 'user_plans')
  LOOP
    IF NOT (SELECT relforcerowsecurity
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relname = r.tablename) THEN
      RAISE EXCEPTION 'RLS not forced on table: %', r.tablename;
    END IF;
  END LOOP;

  RAISE NOTICE 'RLS successfully forced on all public tables';
END $$;

COMMIT;
