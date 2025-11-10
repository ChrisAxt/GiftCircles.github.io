-- Migration: Fix Claim Split Unique Constraint
-- Description: Change unique constraint to only apply to pending requests
--              This allows users to request again after a request has been accepted/denied

-- Drop the old unique constraint
ALTER TABLE public.claim_split_requests
  DROP CONSTRAINT IF EXISTS claim_split_requests_item_id_requester_id_original_claimer__key;

-- Create a partial unique index that only applies to pending requests
-- This allows multiple non-pending requests but ensures only one pending request per combination
CREATE UNIQUE INDEX IF NOT EXISTS claim_split_requests_pending_unique
  ON public.claim_split_requests(item_id, requester_id, original_claimer_id)
  WHERE status = 'pending';
