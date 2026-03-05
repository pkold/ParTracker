-- Fix: Ensure players UPDATE policy exists
-- The original 005_rls_policies.sql was applied manually and the UPDATE policy may be missing

DROP POLICY IF EXISTS "players_update_own" ON players;
CREATE POLICY "players_update_own"
ON players FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());
