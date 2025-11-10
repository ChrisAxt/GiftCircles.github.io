-- Migration: Add random receiver assignment feature
-- Date: 2025-01-16
-- Description: Add support for randomly assigning receivers (who gets the gift) in addition to givers (who buys it)

BEGIN;

-- ============================================================================
-- STEP 1: Add columns to support random receiver assignment
-- ============================================================================

-- Add column to items table to track assigned recipient
ALTER TABLE public.items
ADD COLUMN IF NOT EXISTS assigned_recipient_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

-- Add column to lists table to enable receiver assignment feature
ALTER TABLE public.lists
ADD COLUMN IF NOT EXISTS random_receiver_assignment_enabled boolean NOT NULL DEFAULT false;

-- Add index on assigned_recipient_id for performance
CREATE INDEX IF NOT EXISTS idx_items_assigned_recipient_id ON public.items(assigned_recipient_id);

-- Add comments explaining the columns
COMMENT ON COLUMN public.items.assigned_recipient_id IS 'For random receiver assignment lists: the user this item is intended for. NULL for regular lists. The giver (claimer) should not equal this recipient.';
COMMENT ON COLUMN public.lists.random_receiver_assignment_enabled IS 'When true, each item is randomly assigned to a specific recipient. Only the giver knows who will receive their item.';

-- ============================================================================
-- STEP 2: Create function to perform random receiver assignment
-- ============================================================================

CREATE OR REPLACE FUNCTION public.execute_random_receiver_assignment(
  p_list_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_list record;
  v_event_id uuid;
  v_items_count integer;
  v_members_count integer;
  v_item record;
  v_giver_id uuid;
  v_recipient_id uuid;
  v_eligible_recipients uuid[];
  v_random_index integer;
  v_retry_count integer;
  v_max_retries integer := 10;
BEGIN
  -- Validate user is authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get list details
  SELECT l.*, l.event_id INTO v_list
  FROM public.lists l
  WHERE l.id = p_list_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'List not found';
  END IF;

  -- Verify user has permission (list creator or event admin)
  IF v_list.created_by != auth.uid() THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.event_members
      WHERE event_id = v_list.event_id
        AND user_id = auth.uid()
        AND role = 'admin'
    ) THEN
      RAISE EXCEPTION 'Only list creator or event admin can execute assignment';
    END IF;
  END IF;

  -- Check if receiver assignment is enabled
  IF NOT v_list.random_receiver_assignment_enabled THEN
    RAISE EXCEPTION 'Random receiver assignment is not enabled for this list';
  END IF;

  -- Get eligible members (all event members who are givers, excluding recipients-only)
  v_event_id := v_list.event_id;

  SELECT COUNT(*) INTO v_members_count
  FROM public.event_members em
  WHERE em.event_id = v_event_id
    AND em.role IN ('giver', 'admin');

  -- Need at least 2 members to assign different givers and receivers
  IF v_members_count < 2 THEN
    RAISE EXCEPTION 'Need at least 2 members to use random receiver assignment';
  END IF;

  -- Get items count
  SELECT COUNT(*) INTO v_items_count
  FROM public.items
  WHERE list_id = p_list_id;

  IF v_items_count = 0 THEN
    RAISE EXCEPTION 'No items in list to assign';
  END IF;

  -- Loop through each item and assign a receiver
  FOR v_item IN
    SELECT i.id, i.list_id
    FROM public.items i
    WHERE i.list_id = p_list_id
  LOOP
    -- Get the giver (assigned_to from claims)
    SELECT c.claimer_id INTO v_giver_id
    FROM public.claims c
    WHERE c.item_id = v_item.id
      AND c.assigned_to IS NOT NULL
    LIMIT 1;

    -- If no giver assigned yet, skip this item
    IF v_giver_id IS NULL THEN
      CONTINUE;
    END IF;

    -- Get eligible recipients (all givers/admins except the giver themselves)
    SELECT ARRAY_AGG(em.user_id) INTO v_eligible_recipients
    FROM public.event_members em
    WHERE em.event_id = v_event_id
      AND em.role IN ('giver', 'admin')
      AND em.user_id != v_giver_id;

    -- If no eligible recipients, skip
    IF v_eligible_recipients IS NULL OR array_length(v_eligible_recipients, 1) = 0 THEN
      CONTINUE;
    END IF;

    -- Randomly select a recipient
    v_random_index := floor(random() * array_length(v_eligible_recipients, 1)) + 1;
    v_recipient_id := v_eligible_recipients[v_random_index];

    -- Update the item with assigned recipient
    UPDATE public.items
    SET assigned_recipient_id = v_recipient_id
    WHERE id = v_item.id;
  END LOOP;

  -- Update the list to mark when receiver assignment was executed
  UPDATE public.lists
  SET random_assignment_executed_at = now()
  WHERE id = p_list_id;

END;
$$;

-- ============================================================================
-- STEP 3: Grant permissions
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.execute_random_receiver_assignment(uuid) TO authenticated;

COMMENT ON FUNCTION public.execute_random_receiver_assignment(uuid) IS
'Randomly assigns a recipient to each item in a list where random receiver assignment is enabled. Only the giver (claimer) will know who their assigned recipient is.';

COMMIT;
