BEGIN;
SET LOCAL search_path = public;

-- 0) Remove test-only helpers (if present). These do not exist in your originals.
DROP FUNCTION IF EXISTS public._test_any_member_for_event_title(text);
DROP FUNCTION IF EXISTS public._test_admin_for_event_title(text);
DROP FUNCTION IF EXISTS public._test_create_list_for_event(uuid,text,list_visibility);

-- 1) Drop any RLS policies on key tables so the incoming policies.sql can recreate them cleanly.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT n.nspname, c.relname, pol.polname
    FROM pg_policy pol
    JOIN pg_class c ON c.oid = pol.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN ('events','event_members','lists','items','claims')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I;', r.polname, r.nspname, r.relname);
  END LOOP;
END$$;

-- 2) (Optional but recommended) Remove any stray overloads of create_list_with_people
--    that are not the canonical one defined by your files.
DO $$
DECLARE f regprocedure;
BEGIN
  IF to_regprocedure('public.create_list_with_people(uuid,text,list_visibility,uuid[],uuid[])') IS NOT NULL THEN
    FOR f IN
      SELECT p.oid::regprocedure
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname='public'
        AND p.proname='create_list_with_people'
        AND p.oid::regprocedure <> 'public.create_list_with_people(uuid,text,list_visibility,uuid[],uuid[])'::regprocedure
    LOOP
      EXECUTE format('DROP FUNCTION %s;', f);
    END LOOP;
  END IF;
END$$;

-- 3) Replay your schema exactly as defined in your files (paths below).
\i supabase/schema/tables.sql
\i supabase/schema/functions.sql
\i supabase/schema/policies.sql

COMMIT;
