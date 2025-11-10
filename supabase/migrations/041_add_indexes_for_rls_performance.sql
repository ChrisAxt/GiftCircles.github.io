-- Migration: Add indexes to improve RLS policy performance
-- Date: 2025-01-17
-- Description: The RLS policies for items and claims have complex nested queries.
--              Adding indexes on commonly queried columns will significantly improve performance.

BEGIN;

-- Index for claims.assigned_to - frequently checked in RLS policies
CREATE INDEX IF NOT EXISTS idx_claims_assigned_to
ON public.claims(assigned_to)
WHERE assigned_to IS NOT NULL;

-- Index for claims.item_id - used in JOINs and EXISTS checks
CREATE INDEX IF NOT EXISTS idx_claims_item_id
ON public.claims(item_id);

-- Index for items.assigned_recipient_id - checked in receiver assignment RLS
CREATE INDEX IF NOT EXISTS idx_items_assigned_recipient_id
ON public.items(assigned_recipient_id)
WHERE assigned_recipient_id IS NOT NULL;

-- Index for items.list_id - heavily used in JOINs
-- (May already exist, but ensure it's there)
CREATE INDEX IF NOT EXISTS idx_items_list_id
ON public.items(list_id);

-- Index for lists.random_assignment_enabled - checked in RLS policies
CREATE INDEX IF NOT EXISTS idx_lists_random_assignment_enabled
ON public.lists(random_assignment_enabled)
WHERE random_assignment_enabled = true;

-- Index for lists.random_receiver_assignment_enabled - checked in RLS policies
CREATE INDEX IF NOT EXISTS idx_lists_random_receiver_assignment_enabled
ON public.lists(random_receiver_assignment_enabled)
WHERE random_receiver_assignment_enabled = true;

-- Index for list_recipients(list_id, user_id) - checked in RLS policies
CREATE INDEX IF NOT EXISTS idx_list_recipients_list_user
ON public.list_recipients(list_id, user_id);

-- Index for event_members(event_id, user_id, role) - heavily used in RLS
CREATE INDEX IF NOT EXISTS idx_event_members_event_user_role
ON public.event_members(event_id, user_id, role);

-- Composite index for claims by claimer and item - speeds up claim lookups
CREATE INDEX IF NOT EXISTS idx_claims_claimer_item
ON public.claims(claimer_id, item_id);

-- Index for lists(id, event_id, created_by) - heavily used in RLS and RPCs
CREATE INDEX IF NOT EXISTS idx_lists_id_event_created
ON public.lists(id, event_id, created_by);

-- Index for events(id, owner_id) - checked in RLS policies
CREATE INDEX IF NOT EXISTS idx_events_id_owner
ON public.events(id, owner_id);

COMMIT;
