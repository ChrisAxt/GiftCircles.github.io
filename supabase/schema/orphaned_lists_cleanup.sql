-- Orphaned Lists Cleanup System
-- This system handles automatic deletion of lists where the only remaining event member
-- is excluded from the list (orphaned exclusion scenario)

-- Table to track lists marked for deletion
CREATE TABLE IF NOT EXISTS public.orphaned_lists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  list_id UUID NOT NULL REFERENCES public.lists(id) ON DELETE CASCADE,
  event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  excluded_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  marked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  delete_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 days'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(list_id, excluded_user_id)
);

-- Index for efficient querying
CREATE INDEX IF NOT EXISTS idx_orphaned_lists_delete_at ON public.orphaned_lists(delete_at);
CREATE INDEX IF NOT EXISTS idx_orphaned_lists_list_id ON public.orphaned_lists(list_id);

-- Enable RLS
ALTER TABLE public.orphaned_lists ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Only system/admins can view (users don't need to see this)
CREATE POLICY orphaned_lists_select ON public.orphaned_lists
  FOR SELECT
  USING (false);

-- Function to check if a user is the sole member of an event
CREATE OR REPLACE FUNCTION is_sole_event_member(p_event_id UUID, p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COUNT(*) = 1
    FROM public.event_members
    WHERE event_id = p_event_id
  ) AND (
    SELECT EXISTS(
      SELECT 1
      FROM public.event_members
      WHERE event_id = p_event_id
        AND user_id = p_user_id
    )
  );
END;
$$;

-- Function to mark orphaned lists for deletion
CREATE OR REPLACE FUNCTION mark_orphaned_lists_for_deletion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_event_id UUID;
  v_remaining_user_id UUID;
  v_list RECORD;
BEGIN
  -- Get the event_id from the deleted member
  v_event_id := OLD.event_id;

  -- Check if there's exactly one member left in the event
  SELECT user_id INTO v_remaining_user_id
  FROM public.event_members
  WHERE event_id = v_event_id
  LIMIT 1;

  -- If no members left or more than one member, nothing to do
  IF v_remaining_user_id IS NULL THEN
    RETURN OLD;
  END IF;

  IF NOT is_sole_event_member(v_event_id, v_remaining_user_id) THEN
    RETURN OLD;
  END IF;

  -- Find all lists in this event where the remaining user is excluded
  FOR v_list IN
    SELECT l.id as list_id
    FROM public.lists l
    INNER JOIN public.list_exclusions le ON le.list_id = l.id
    WHERE l.event_id = v_event_id
      AND le.user_id = v_remaining_user_id
  LOOP
    -- Mark this list for deletion (insert or update)
    INSERT INTO public.orphaned_lists (list_id, event_id, excluded_user_id, marked_at, delete_at)
    VALUES (v_list.list_id, v_event_id, v_remaining_user_id, NOW(), NOW() + INTERVAL '30 days')
    ON CONFLICT (list_id, excluded_user_id)
    DO UPDATE SET
      marked_at = NOW(),
      delete_at = NOW() + INTERVAL '30 days';
  END LOOP;

  RETURN OLD;
END;
$$;

-- Trigger to mark orphaned lists when a member leaves an event
DROP TRIGGER IF EXISTS trigger_mark_orphaned_lists ON public.event_members;
CREATE TRIGGER trigger_mark_orphaned_lists
  AFTER DELETE ON public.event_members
  FOR EACH ROW
  EXECUTE FUNCTION mark_orphaned_lists_for_deletion();

-- Function to clean up orphaned lists that have passed their deletion date
CREATE OR REPLACE FUNCTION cleanup_orphaned_lists()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_deleted_count INTEGER := 0;
  v_orphaned RECORD;
BEGIN
  -- Find all orphaned lists ready for deletion
  FOR v_orphaned IN
    SELECT ol.id, ol.list_id, ol.event_id, ol.excluded_user_id
    FROM public.orphaned_lists ol
    WHERE ol.delete_at <= NOW()
  LOOP
    -- Verify the user is still the sole member before deleting
    IF is_sole_event_member(v_orphaned.event_id, v_orphaned.excluded_user_id) THEN
      -- Verify the user is still excluded from this list
      IF EXISTS(
        SELECT 1 FROM public.list_exclusions
        WHERE list_id = v_orphaned.list_id
          AND user_id = v_orphaned.excluded_user_id
      ) THEN
        -- Delete the list (cascade will handle items, claims, etc.)
        DELETE FROM public.lists WHERE id = v_orphaned.list_id;
        v_deleted_count := v_deleted_count + 1;
      END IF;
    END IF;

    -- Remove from orphaned_lists tracking table
    DELETE FROM public.orphaned_lists WHERE id = v_orphaned.id;
  END LOOP;

  RETURN v_deleted_count;
END;
$$;

-- Function to unmark lists if a new member joins the event
CREATE OR REPLACE FUNCTION unmark_orphaned_lists_on_member_join()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- When a new member joins an event, remove any orphaned list markers for that event
  DELETE FROM public.orphaned_lists
  WHERE event_id = NEW.event_id;

  RETURN NEW;
END;
$$;

-- Trigger to unmark orphaned lists when a new member joins
DROP TRIGGER IF EXISTS trigger_unmark_orphaned_lists ON public.event_members;
CREATE TRIGGER trigger_unmark_orphaned_lists
  AFTER INSERT ON public.event_members
  FOR EACH ROW
  EXECUTE FUNCTION unmark_orphaned_lists_on_member_join();

-- Create a cron job to run cleanup daily at 3 AM UTC
-- Note: This requires the pg_cron extension to be enabled
-- You can enable it in Supabase Dashboard under Database > Extensions
SELECT cron.schedule(
  'cleanup-orphaned-lists',
  '0 3 * * *',
  $$SELECT cleanup_orphaned_lists();$$
);
