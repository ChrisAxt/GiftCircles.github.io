-- Create a test RPC to verify if the app can see claims at all
-- This will help us debug if the issue is with RLS or with the nested select syntax

CREATE OR REPLACE FUNCTION public.test_get_my_claims()
RETURNS TABLE (
  claim_id uuid,
  item_id uuid,
  purchased boolean,
  created_at timestamptz,
  auth_user_id uuid,
  can_see_claim boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.id as claim_id,
    c.item_id,
    c.purchased,
    c.created_at,
    auth.uid() as auth_user_id,
    (c.claimer_id = auth.uid()) as can_see_claim
  FROM claims c
  WHERE c.claimer_id = auth.uid();
END;
$$;
