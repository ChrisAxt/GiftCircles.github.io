-- Migration: Claim Split Feature
-- Description: Add support for users to request splitting claims on items

-- ============================================================================
-- TABLE: claim_split_requests
-- ============================================================================
-- Tracks requests from users to split claim an item with the original claimer

CREATE TABLE IF NOT EXISTS public.claim_split_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id uuid NOT NULL REFERENCES public.items(id) ON DELETE CASCADE,
  requester_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  original_claimer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'denied')),
  created_at timestamptz DEFAULT now(),
  responded_at timestamptz,
  -- Ensure a user can only have one pending request per item/claimer combination
  UNIQUE(item_id, requester_id, original_claimer_id)
);

-- Add indexes for common queries
CREATE INDEX IF NOT EXISTS idx_claim_split_requests_original_claimer
  ON public.claim_split_requests(original_claimer_id)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_claim_split_requests_item
  ON public.claim_split_requests(item_id);

-- ============================================================================
-- RLS POLICIES: claim_split_requests
-- ============================================================================

ALTER TABLE public.claim_split_requests ENABLE ROW LEVEL SECURITY;

-- Users can insert their own split requests
CREATE POLICY "Users can create split requests"
  ON public.claim_split_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = requester_id);

-- Users can view split requests they're involved in (as requester or original claimer)
CREATE POLICY "Users can view their split requests"
  ON public.claim_split_requests
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = requester_id OR
    auth.uid() = original_claimer_id
  );

-- Original claimers can update the status of their split requests
CREATE POLICY "Original claimers can update split requests"
  ON public.claim_split_requests
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = original_claimer_id)
  WITH CHECK (auth.uid() = original_claimer_id);

-- Users can delete their own pending requests
CREATE POLICY "Requesters can delete their pending requests"
  ON public.claim_split_requests
  FOR DELETE
  TO authenticated
  USING (auth.uid() = requester_id AND status = 'pending');

-- ============================================================================
-- FUNCTION: request_claim_split
-- ============================================================================
-- Allows a user to request splitting a claim on an item

CREATE OR REPLACE FUNCTION public.request_claim_split(
  p_item_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_original_claimer_id uuid;
  v_request_id uuid;
  v_list_id uuid;
  v_event_id uuid;
BEGIN
  -- Validate user is authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get the original claimer (first claimer based on created_at)
  SELECT c.claimer_id INTO v_original_claimer_id
  FROM public.claims c
  WHERE c.item_id = p_item_id
  ORDER BY c.created_at ASC
  LIMIT 1;

  -- Validate item is claimed
  IF v_original_claimer_id IS NULL THEN
    RAISE EXCEPTION 'Item is not claimed';
  END IF;

  -- Validate user is not the original claimer
  IF v_original_claimer_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot request to split your own claim';
  END IF;

  -- Validate user is not already a claimer
  IF EXISTS (
    SELECT 1 FROM public.claims
    WHERE item_id = p_item_id AND claimer_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'You have already claimed this item';
  END IF;

  -- Validate user is a member of the event
  SELECT i.list_id, l.event_id INTO v_list_id, v_event_id
  FROM public.items i
  JOIN public.lists l ON i.list_id = l.id
  WHERE i.id = p_item_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.event_members
    WHERE event_id = v_event_id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'You are not a member of this event';
  END IF;

  -- Check if there's already a pending request
  IF EXISTS (
    SELECT 1 FROM public.claim_split_requests
    WHERE item_id = p_item_id
      AND requester_id = auth.uid()
      AND original_claimer_id = v_original_claimer_id
      AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'You already have a pending split request for this item';
  END IF;

  -- Create the split request
  INSERT INTO public.claim_split_requests (
    item_id,
    requester_id,
    original_claimer_id,
    status
  ) VALUES (
    p_item_id,
    auth.uid(),
    v_original_claimer_id,
    'pending'
  )
  RETURNING id INTO v_request_id;

  RETURN v_request_id;
END;
$$;

-- ============================================================================
-- FUNCTION: accept_claim_split
-- ============================================================================
-- Allows the original claimer to accept a split request

CREATE OR REPLACE FUNCTION public.accept_claim_split(
  p_request_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request record;
BEGIN
  -- Validate user is authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get the request details
  SELECT * INTO v_request
  FROM public.claim_split_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Split request not found';
  END IF;

  -- Validate user is the original claimer
  IF v_request.original_claimer_id != auth.uid() THEN
    RAISE EXCEPTION 'Only the original claimer can accept this request';
  END IF;

  -- Validate request is still pending
  IF v_request.status != 'pending' THEN
    RAISE EXCEPTION 'Request has already been responded to';
  END IF;

  -- Validate requester hasn't already claimed the item
  IF EXISTS (
    SELECT 1 FROM public.claims
    WHERE item_id = v_request.item_id AND claimer_id = v_request.requester_id
  ) THEN
    RAISE EXCEPTION 'Requester has already claimed this item';
  END IF;

  -- Create a claim for the requester
  INSERT INTO public.claims (
    item_id,
    claimer_id,
    quantity,
    note
  ) VALUES (
    v_request.item_id,
    v_request.requester_id,
    1,
    'Split claim'
  );

  -- Update the request status
  UPDATE public.claim_split_requests
  SET
    status = 'accepted',
    responded_at = now()
  WHERE id = p_request_id;
END;
$$;

-- ============================================================================
-- FUNCTION: deny_claim_split
-- ============================================================================
-- Allows the original claimer to deny a split request

CREATE OR REPLACE FUNCTION public.deny_claim_split(
  p_request_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request record;
BEGIN
  -- Validate user is authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get the request details
  SELECT * INTO v_request
  FROM public.claim_split_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Split request not found';
  END IF;

  -- Validate user is the original claimer
  IF v_request.original_claimer_id != auth.uid() THEN
    RAISE EXCEPTION 'Only the original claimer can deny this request';
  END IF;

  -- Validate request is still pending
  IF v_request.status != 'pending' THEN
    RAISE EXCEPTION 'Request has already been responded to';
  END IF;

  -- Update the request status
  UPDATE public.claim_split_requests
  SET
    status = 'denied',
    responded_at = now()
  WHERE id = p_request_id;
END;
$$;

-- ============================================================================
-- FUNCTION: get_my_split_requests
-- ============================================================================
-- Returns pending split requests for the current user (as original claimer)

CREATE OR REPLACE FUNCTION public.get_my_split_requests()
RETURNS TABLE (
  request_id uuid,
  item_id uuid,
  item_name text,
  event_id uuid,
  event_title text,
  list_name text,
  requester_id uuid,
  requester_name text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Validate user is authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  RETURN QUERY
  SELECT
    csr.id as request_id,
    csr.item_id,
    i.name as item_name,
    l.event_id,
    e.title as event_title,
    l.name as list_name,
    csr.requester_id,
    COALESCE(p.display_name, 'Unknown User') as requester_name,
    csr.created_at
  FROM public.claim_split_requests csr
  JOIN public.items i ON csr.item_id = i.id
  JOIN public.lists l ON i.list_id = l.id
  JOIN public.events e ON l.event_id = e.id
  LEFT JOIN public.profiles p ON csr.requester_id = p.id
  WHERE csr.original_claimer_id = auth.uid()
    AND csr.status = 'pending'
  ORDER BY csr.created_at DESC;
END;
$$;

-- Grant necessary permissions
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON public.claim_split_requests TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_claim_split(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_claim_split(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deny_claim_split(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_split_requests() TO authenticated;
