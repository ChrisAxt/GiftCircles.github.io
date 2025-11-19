-- Drop ALL duplicate foreign key constraints across all tables
--
-- Problem: PostgREST (Supabase JS client) can't handle nested selects when there are
-- multiple foreign keys between the same tables. This causes PGRST201 errors.
--
-- Solution: Drop all duplicate fk_* constraints and keep the standard *_fkey ones.

BEGIN;

-- Drop duplicate foreign keys on items table
ALTER TABLE public.items DROP CONSTRAINT IF EXISTS fk_items_list_id;
ALTER TABLE public.items DROP CONSTRAINT IF EXISTS fk_items_created_by;
ALTER TABLE public.items DROP CONSTRAINT IF EXISTS fk_items_assigned_recipient_id;

-- Drop duplicate foreign keys on lists table
ALTER TABLE public.lists DROP CONSTRAINT IF EXISTS fk_lists_event_id;
ALTER TABLE public.lists DROP CONSTRAINT IF EXISTS fk_lists_created_by;

-- Drop duplicate foreign keys on events table
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS fk_events_owner_id;

-- Drop duplicate foreign keys on list_recipients table
ALTER TABLE public.list_recipients DROP CONSTRAINT IF EXISTS fk_list_recipients_list_id;
ALTER TABLE public.list_recipients DROP CONSTRAINT IF EXISTS fk_list_recipients_user_id;

COMMIT;
