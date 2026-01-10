-- ============================================
-- MIGRATION 004: Tournaments
-- ============================================
-- Run this AFTER migration 003
-- This creates the multi-round tournament system

-- ============================================
-- STEP 1: TOURNAMENTS
-- ============================================
CREATE TABLE tournaments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  description TEXT,
  created_by UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Tournament rules
  rounds_to_count INT NOT NULL DEFAULT 6,
  aggregation_rule TEXT NOT NULL DEFAULT 'sum' 
    CHECK (aggregation_rule IN ('sum','best_n','average')),
  best_n INT CHECK (best_n IS NULL OR best_n > 0),
  
  -- Dates
  start_date DATE,
  end_date DATE,
  
  -- Status
  status TEXT NOT NULL DEFAULT 'setup' 
    CHECK (status IN ('setup','active','completed','cancelled'))
);

CREATE INDEX idx_tournaments_created_by ON tournaments(created_by);
CREATE INDEX idx_tournaments_status ON tournaments(status);
CREATE INDEX idx_tournaments_dates ON tournaments(start_date, end_date);

COMMENT ON TABLE tournaments IS 'Multi-round tournament definitions';
COMMENT ON COLUMN tournaments.rounds_to_count IS 'How many rounds count toward final standings (e.g. 6)';
COMMENT ON COLUMN tournaments.aggregation_rule IS 'sum = total all rounds, best_n = best N of M rounds';
COMMENT ON COLUMN tournaments.best_n IS 'Used when aggregation_rule = best_n (e.g. best 4 of 6)';

-- ============================================
-- STEP 2: TOURNAMENT ROUNDS (link rounds)
-- ============================================
CREATE TABLE tournament_rounds (
  tournament_id UUID NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  round_id UUID NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
  round_no INT NOT NULL,
  weight NUMERIC NOT NULL DEFAULT 1.0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (tournament_id, round_id)
);

CREATE INDEX idx_tournament_rounds_tournament ON tournament_rounds(tournament_id, round_no);
CREATE UNIQUE INDEX idx_tournament_rounds_unique_no ON tournament_rounds(tournament_id, round_no);

COMMENT ON TABLE tournament_rounds IS 'Links rounds to tournaments with ordering';
COMMENT ON COLUMN tournament_rounds.round_no IS 'Sequential number (1, 2, 3...) for sorting';
COMMENT ON COLUMN tournament_rounds.weight IS 'Multiplier for scoring (e.g. 1.5 for final round)';

-- ============================================
-- STEP 3: TOURNAMENT PLAYERS (registrations)
-- ============================================
CREATE TABLE tournament_players (
  tournament_id UUID NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (tournament_id, player_id)
);

CREATE INDEX idx_tournament_players_tournament ON tournament_players(tournament_id);

COMMENT ON TABLE tournament_players IS 'Player registrations for tournaments';

-- ============================================
-- STEP 4: TOURNAMENT STANDINGS (materialized)
-- ============================================
CREATE TABLE tournament_standings (
  tournament_id UUID NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  
  -- Aggregate statistics
  rounds_played INT NOT NULL DEFAULT 0,
  rounds_won INT NOT NULL DEFAULT 0,
  stableford_total INT NOT NULL DEFAULT 0,
  skins_total_value NUMERIC NOT NULL DEFAULT 0,
  
  -- Rankings
  rank INT,
  
  -- Metadata
  last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  PRIMARY KEY (tournament_id, player_id)
);

CREATE INDEX idx_tournament_standings_rank ON tournament_standings(tournament_id, rank);

COMMENT ON TABLE tournament_standings IS 'Materialized leaderboard for performance (updated after each round)';
COMMENT ON COLUMN tournament_standings.rank IS 'Current position in tournament (1 = leader)';

-- ============================================
-- STEP 5: VIEWS FOR AGGREGATIONS
-- ============================================

-- View 1: Stableford totals per tournament
CREATE OR REPLACE VIEW tournament_stableford_totals AS
SELECT
  tr.tournament_id,
  rr.player_id,
  p.display_name AS player_name,
  COUNT(DISTINCT tr.round_id) AS rounds_played,
  SUM(rr.stableford_total * tr.weight) AS weighted_stableford_total,
  SUM(rr.stableford_total) AS stableford_total
FROM tournament_rounds tr
JOIN round_results rr ON rr.round_id = tr.round_id
JOIN players p ON p.id = rr.player_id
GROUP BY tr.tournament_id, rr.player_id, p.display_name;

COMMENT ON VIEW tournament_stableford_totals IS 
'Aggregate stableford scores across tournament rounds';

-- View 2: Round wins per tournament
CREATE OR REPLACE VIEW tournament_round_wins AS
WITH round_rankings AS (
  SELECT
    tr.tournament_id,
    tr.round_id,
    rr.player_id,
    rr.stableford_total,
    RANK() OVER (
      PARTITION BY tr.tournament_id, tr.round_id 
      ORDER BY rr.stableford_total DESC
    ) AS rank
  FROM tournament_rounds tr
  JOIN round_results rr ON rr.round_id = tr.round_id
)
SELECT
  tournament_id,
  player_id,
  COUNT(*) FILTER (WHERE rank = 1) AS rounds_won,
  COUNT(*) AS rounds_played
FROM round_rankings
GROUP BY tournament_id, player_id;

COMMENT ON VIEW tournament_round_wins IS 
'Count of rounds won per player in tournaments';

-- View 3: Skins totals per tournament
CREATE OR REPLACE VIEW tournament_skins_totals AS
SELECT
  tr.tournament_id,
  sr.winner_player_id AS player_id,
  p.display_name AS player_name,
  SUM(sr.skin_awarded_value) AS skins_total_value,
  COUNT(*) AS skins_won
FROM tournament_rounds tr
JOIN skins_results sr ON sr.round_id = tr.round_id
JOIN players p ON p.id = sr.winner_player_id
WHERE sr.winner_player_id IS NOT NULL
GROUP BY tr.tournament_id, sr.winner_player_id, p.display_name;

COMMENT ON VIEW tournament_skins_totals IS 
'Total skins value won per player in tournaments';

-- View 4: Sidegames totals per tournament
CREATE OR REPLACE VIEW tournament_sidegame_totals AS
SELECT
  tr.tournament_id,
  e.sidegame_code,
  st.name AS sidegame_name,
  e.player_id,
  p.display_name AS player_name,
  COUNT(*) AS event_count,
  SUM(e.value) AS total_value
FROM tournament_rounds tr
JOIN sidegame_events e ON e.round_id = tr.round_id
JOIN sidegame_types st ON st.code = e.sidegame_code
JOIN players p ON p.id = e.player_id
GROUP BY 
  tr.tournament_id, 
  e.sidegame_code, 
  st.name,
  e.player_id, 
  p.display_name;

COMMENT ON VIEW tournament_sidegame_totals IS 
'Sidegame event totals per player in tournaments';

-- ============================================
-- VERIFICATION QUERIES
-- ============================================
-- Uncomment to verify:

-- SELECT 'tournaments' as table_name, COUNT(*) as row_count FROM tournaments;
-- SELECT 'tournament_rounds' as table_name, COUNT(*) as row_count FROM tournament_rounds;
-- SELECT 'tournament_players' as table_name, COUNT(*) as row_count FROM tournament_players;
-- SELECT 'tournament_standings' as table_name, COUNT(*) as row_count FROM tournament_standings;

-- Check views exist:
-- SELECT table_name FROM information_schema.views 
-- WHERE table_schema = 'public' AND table_name LIKE 'tournament%'
-- ORDER BY table_name;

-- ============================================
-- END OF MIGRATION 004
-- ============================================