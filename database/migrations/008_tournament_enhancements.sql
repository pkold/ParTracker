-- ============================================
-- MIGRATION 008: Tournament Enhancements
-- ============================================
-- Run this AFTER migration 007
-- Adds season points system, bonus config, team standings

-- ============================================
-- STEP 1: ALTER tournaments — add season points columns
-- ============================================
ALTER TABLE tournaments
  ADD COLUMN scoring_mode TEXT NOT NULL DEFAULT 'individual'
    CHECK (scoring_mode IN ('individual','team','both')),
  ADD COLUMN points_table JSONB,
  ADD COLUMN bonus_config JSONB DEFAULT '{"round_winner":10,"skins_leader":5,"eagle":5,"hole_in_one":20,"hot_streak":10}',
  ADD COLUMN default_course_id UUID REFERENCES courses(id),
  ADD COLUMN default_game_types TEXT[] DEFAULT '{}';

COMMENT ON COLUMN tournaments.scoring_mode IS 'individual, team, or both leaderboards';
COMMENT ON COLUMN tournaments.points_table IS 'JSONB array mapping rank → points, auto-generated if null';
COMMENT ON COLUMN tournaments.bonus_config IS 'Bonus point awards for special achievements';
COMMENT ON COLUMN tournaments.default_course_id IS 'Default course for tournament rounds';
COMMENT ON COLUMN tournaments.default_game_types IS 'Default game types for tournament rounds';

-- ============================================
-- STEP 2: ALTER tournament_standings — add points columns
-- ============================================
ALTER TABLE tournament_standings
  ADD COLUMN season_points NUMERIC NOT NULL DEFAULT 0,
  ADD COLUMN bonus_points NUMERIC NOT NULL DEFAULT 0,
  ADD COLUMN total_points NUMERIC NOT NULL DEFAULT 0;

COMMENT ON COLUMN tournament_standings.season_points IS 'Points earned from round finishes';
COMMENT ON COLUMN tournament_standings.bonus_points IS 'Points earned from bonus achievements';
COMMENT ON COLUMN tournament_standings.total_points IS 'season_points + bonus_points';

-- ============================================
-- STEP 3: ALTER tournament_players — add team_name
-- ============================================
ALTER TABLE tournament_players
  ADD COLUMN team_name TEXT;

COMMENT ON COLUMN tournament_players.team_name IS 'Team assignment for team/both scoring modes';

-- ============================================
-- STEP 4: CREATE tournament_team_standings
-- ============================================
CREATE TABLE tournament_team_standings (
  tournament_id UUID NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  team_name TEXT NOT NULL,
  rounds_played INT NOT NULL DEFAULT 0,
  season_points NUMERIC NOT NULL DEFAULT 0,
  bonus_points NUMERIC NOT NULL DEFAULT 0,
  total_points NUMERIC NOT NULL DEFAULT 0,
  rank INT,
  last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (tournament_id, team_name)
);

CREATE INDEX idx_tournament_team_standings_rank
  ON tournament_team_standings(tournament_id, rank);

COMMENT ON TABLE tournament_team_standings IS 'Aggregated team standings for tournaments with team scoring';

-- ============================================
-- STEP 5: RLS on tournament_team_standings
-- ============================================
ALTER TABLE tournament_team_standings ENABLE ROW LEVEL SECURITY;

-- Select: tournament creator OR tournament player
CREATE POLICY "tournament_team_standings_select"
  ON tournament_team_standings FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM tournaments t
      WHERE t.id = tournament_team_standings.tournament_id
        AND t.created_by = auth.uid()
    )
    OR
    EXISTS (
      SELECT 1 FROM tournament_players tp
      JOIN players p ON p.id = tp.player_id
      WHERE tp.tournament_id = tournament_team_standings.tournament_id
        AND p.user_id = auth.uid()
    )
  );

-- Insert/Update/Delete: tournament creator only
CREATE POLICY "tournament_team_standings_modify"
  ON tournament_team_standings FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM tournaments t
      WHERE t.id = tournament_team_standings.tournament_id
        AND t.created_by = auth.uid()
    )
  );

-- ============================================
-- STEP 6: Helper function generate_points_table
-- ============================================
CREATE OR REPLACE FUNCTION generate_points_table(player_count INT)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  result JSONB := '[]'::JSONB;
  pts NUMERIC := 100;
  i INT;
BEGIN
  FOR i IN 1..player_count LOOP
    result := result || to_jsonb(jsonb_build_object('rank', i, 'points', GREATEST(ROUND(pts), 5)));
    pts := pts * 0.7;
  END LOOP;
  RETURN result;
END;
$$;

COMMENT ON FUNCTION generate_points_table IS 'Generates a FedEx-style points table: 1st=100, each next=70% of prev, min 5';

-- ============================================
-- VERIFICATION
-- ============================================
-- SELECT column_name, data_type FROM information_schema.columns
-- WHERE table_name = 'tournaments' AND column_name IN ('scoring_mode','points_table','bonus_config','default_course_id','default_game_types');

-- SELECT column_name, data_type FROM information_schema.columns
-- WHERE table_name = 'tournament_standings' AND column_name IN ('season_points','bonus_points','total_points');

-- SELECT generate_points_table(6);

-- ============================================
-- END OF MIGRATION 008
-- ============================================
