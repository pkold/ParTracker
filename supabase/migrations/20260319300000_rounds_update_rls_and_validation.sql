-- Fix critical security issue: add RLS UPDATE policy on rounds table
-- Only the round creator can update their own rounds

-- Ensure RLS is enabled
ALTER TABLE rounds ENABLE ROW LEVEL SECURITY;

-- UPDATE policy: only creator can update
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'rounds' AND policyname = 'rounds_update_own'
  ) THEN
    CREATE POLICY rounds_update_own ON rounds
      FOR UPDATE
      USING (created_by = auth.uid())
      WITH CHECK (created_by = auth.uid());
  END IF;
END
$$;

-- Also ensure extra_hole_data, settlement columns are protected by same policy
-- (they're on the rounds table, so the policy above covers them)

NOTIFY pgrst, 'reload schema';
