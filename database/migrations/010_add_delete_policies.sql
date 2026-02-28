-- ============================================
-- MIGRATION 010: Add DELETE policies
-- ============================================
-- Missing DELETE policies caused rounds to reappear after deletion.

CREATE POLICY "rounds_delete_owner"
ON rounds FOR DELETE
TO authenticated
USING (created_by = auth.uid());

CREATE POLICY "scores_delete_owner"
ON scores FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM rounds r WHERE r.id = scores.round_id AND r.created_by = auth.uid()
  )
);

CREATE POLICY "round_players_delete_owner"
ON round_players FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM rounds r WHERE r.id = round_players.round_id AND r.created_by = auth.uid()
  )
);

CREATE POLICY "round_results_delete_owner"
ON round_results FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM rounds r WHERE r.id = round_results.round_id AND r.created_by = auth.uid()
  )
);

CREATE POLICY "hole_results_delete_owner"
ON hole_results FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM rounds r WHERE r.id = hole_results.round_id AND r.created_by = auth.uid()
  )
);

CREATE POLICY "skins_results_delete_owner"
ON skins_results FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM rounds r WHERE r.id = skins_results.round_id AND r.created_by = auth.uid()
  )
);

CREATE POLICY "tournament_rounds_delete_creator"
ON tournament_rounds FOR DELETE
TO authenticated
USING (
  public.is_tournament_creator(tournament_id)
);

-- ============================================
-- END OF MIGRATION 010
-- ============================================
