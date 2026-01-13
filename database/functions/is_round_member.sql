-- Function to check if a user is a member of a round
-- Used for authorization in Edge Functions

CREATE OR REPLACE FUNCTION is_round_member(p_round_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
BEGIN
  -- Get the authenticated user ID
  v_user_id := auth.uid();
  
  -- If no user is authenticated, return false
  IF v_user_id IS NULL THEN
    RETURN FALSE;
  END IF;
  
  -- Check if user created the round
  SELECT EXISTS(
    SELECT 1
    FROM rounds
    WHERE id = p_round_id
    AND created_by = v_user_id
  ) INTO v_is_member;
  
  IF v_is_member THEN
    RETURN TRUE;
  END IF;
  
  -- Check if user is a player in the round
  SELECT EXISTS(
    SELECT 1
    FROM round_players
    WHERE round_id = p_round_id
    AND user_id = v_user_id
  ) INTO v_is_member;
  
  RETURN v_is_member;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION is_round_member TO authenticated;
GRANT EXECUTE ON FUNCTION is_round_member TO service_role;
