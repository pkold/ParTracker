-- ============================================
-- MIGRATION 002: Rounds & Scoring Tables
-- ============================================
-- Run this AFTER migration 001
-- This creates the core scoring engine tables

-- ============================================
-- STEP 1: ROUNDS (game sessions)
-- ============================================
CREATE TABLE rounds (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  course_id UUID NOT NULL REFERENCES courses(id),
  tee_id UUID NOT NULL REFERENCES course_tees(id),
  created_by UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Round configuration
  holes_played INT NOT NULL CHECK (holes_played IN (9,18)),
  start_hole INT NOT NULL CHECK (start_hole IN (1,10)),
  handicap_allowance NUMERIC(4,2) NOT NULL DEFAULT 1.00 
    CHECK (handicap_allowance BETWEEN 0 AND 1.00),
  
  -- Scoring format
  scoring_format TEXT NOT NULL DEFAULT 'stableford' 
    CHECK (scoring_format IN ('stableford','strokeplay')),
  
  -- Team settings
  team_mode TEXT NOT NULL DEFAULT 'individual' 
    CHECK (team_mode IN ('individual','teams')),
  team_scoring_mode TEXT NOT NULL DEFAULT 'bestball' 
    CHECK (team_scoring_mode IN ('bestball','aggregate')),
  
  -- Skins settings
  skins_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  skins_type TEXT NOT NULL DEFAULT 'net' 
    CHECK (skins_type IN ('gross','net')),
  skins_rollover BOOLEAN NOT NULL DEFAULT TRUE,
  
  -- Membership & access
  join_code TEXT,
  visibility TEXT NOT NULL DEFAULT 'private' 
    CHECK (visibility IN ('private','group','public')),
  
  -- Status tracking
  status TEXT NOT NULL DEFAULT 'setup' 
    CHECK (status IN ('setup','active','completed','cancelled')),
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ
);

-- Indexes for performance
CREATE INDEX idx_rounds_created_by ON rounds(created_by);
CREATE INDEX idx_rounds_course ON rounds(course_id);
CREATE INDEX idx_rounds_tee ON rounds(tee_id);
CREATE INDEX idx_rounds_join_code ON rounds(join_code) WHERE join_code IS NOT NULL;
CREATE UNIQUE INDEX idx_rounds_join_code_unique ON rounds(join_code) WHERE join_code IS NOT NULL;

COMMENT ON TABLE rounds IS 'Game sessions with scoring rules and settings';
COMMENT ON COLUMN rounds.holes_played IS '9 or 18 holes';
COMMENT ON COLUMN rounds.start_hole IS '1 (front nine) or 10 (back nine)';
COMMENT ON COLUMN rounds.handicap_allowance IS 'Percentage of handicap to use (0.85 = 85%, 1.0 = 100%)';
COMMENT ON COLUMN rounds.join_code IS 'Code for players to join round (nullable)';

-- ============================================
-- STEP 2: TEAMS
-- ============================================
CREATE TABLE teams (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  round_id UUID NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_teams_round ON teams(round_id);

COMMENT ON TABLE teams IS 'Team groupings within a round';

-- ============================================
-- STEP 3: ROUND PLAYERS (membership + roles)
-- ============================================
CREATE TABLE round_players (
  round_id UUID NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  
  -- Role in this specific round
  role TEXT NOT NULL DEFAULT 'player' 
    CHECK (role IN ('owner','scorekeeper','player','viewer')),
  
  -- Calculated handicap for THIS round
  playing_hcp INT NOT NULL CHECK (playing_hcp BETWEEN 0 AND 54),
  
  -- Team membership (nullable if individual mode)
  team_id UUID REFERENCES teams(id) ON DELETE SET NULL,
  
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (round_id, player_id)
);

CREATE INDEX idx_round_players_user ON round_players(user_id);
CREATE INDEX idx_round_players_role ON round_players(round_id, role);

COMMENT ON TABLE round_players IS 'Links players to rounds with role and playing handicap';
COMMENT ON COLUMN round_players.playing_hcp IS 'Calculated WHS playing handicap for this round/tee';
COMMENT ON COLUMN round_players.role IS 'owner = creator, scorekeeper = can write all scores, player = participant, viewer = read-only';

-- ============================================
-- STEP 4: SCORES (raw stroke input)
-- ============================================
CREATE TABLE scores (
  round_id UUID NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  hole_no INT NOT NULL CHECK (hole_no BETWEEN 1 AND 18),
  strokes INT NOT NULL CHECK (strokes BETWEEN 1 AND 20),
  
  -- Offline sync support (idempotency)
  client_event_id UUID,
  
  -- Audit trail
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by UUID,
  
  PRIMARY KEY (round_id, player_id, hole_no)
);

CREATE INDEX idx_scores_round ON scores(round_id);
CREATE UNIQUE INDEX idx_scores_client_event ON scores(client_event_id) 
  WHERE client_event_id IS NOT NULL;

COMMENT ON TABLE scores IS 'Raw stroke input per hole (source of truth)';
COMMENT ON COLUMN scores.client_event_id IS 'UUID for idempotent offline sync (nullable)';
COMMENT ON COLUMN scores.strokes IS 'Gross strokes taken on hole';

-- ============================================
-- STEP 5: HOLE RESULTS (calculated per hole)
-- ============================================
CREATE TABLE hole_results (
  round_id UUID NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  hole_no INT NOT NULL CHECK (hole_no BETWEEN 1 AND 18),
  
  -- Source data
  strokes INT NOT NULL,
  par INT NOT NULL,
  stroke_index INT NOT NULL,
  
  -- Calculated values
  strokes_received INT NOT NULL,
  net_strokes INT NOT NULL,
  stableford_points INT NOT NULL,
  
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (round_id, player_id, hole_no)
);

CREATE INDEX idx_hole_results_round ON hole_results(round_id);

COMMENT ON TABLE hole_results IS 'Calculated results per hole (derived from scores)';
COMMENT ON COLUMN hole_results.strokes_received IS 'Handicap strokes allocated to this hole';
COMMENT ON COLUMN hole_results.net_strokes IS 'strokes - strokes_received';
COMMENT ON COLUMN hole_results.stableford_points IS 'Points earned (max(0, 2 + (par - net_strokes)))';

-- ============================================
-- STEP 6: ROUND RESULTS (player totals)
-- ============================================
CREATE TABLE round_results (
  round_id UUID NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  
  gross_total INT NOT NULL,
  net_total INT NOT NULL,
  stableford_total INT NOT NULL,
  
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (round_id, player_id)
);

CREATE INDEX idx_round_results_round ON round_results(round_id);
CREATE INDEX idx_round_results_stableford ON round_results(round_id, stableford_total DESC);

COMMENT ON TABLE round_results IS 'Aggregated totals per player (derived from hole_results)';
COMMENT ON COLUMN round_results.gross_total IS 'Sum of gross strokes';
COMMENT ON COLUMN round_results.net_total IS 'Sum of net strokes';
COMMENT ON COLUMN round_results.stableford_total IS 'Sum of stableford points';

-- ============================================
-- STEP 7: TEAM RESULTS
-- ============================================
CREATE TABLE team_results (
  round_id UUID NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
  team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  
  gross_total INT NOT NULL,
  net_total INT NOT NULL,
  stableford_total INT NOT NULL,
  
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (round_id, team_id)
);

CREATE INDEX idx_team_results_round ON team_results(round_id);

COMMENT ON TABLE team_results IS 'Aggregated team totals (bestball or aggregate mode)';

-- ============================================
-- STEP 8: SKINS RESULTS
-- ============================================
CREATE TABLE skins_results (
  round_id UUID NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
  hole_no INT NOT NULL CHECK (hole_no BETWEEN 1 AND 18),
  
  winner_player_id UUID REFERENCES players(id) ON DELETE SET NULL,
  winning_score INT,
  
  carryover_value NUMERIC NOT NULL DEFAULT 0,
  skin_awarded_value NUMERIC NOT NULL DEFAULT 0,
  
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (round_id, hole_no)
);

CREATE INDEX idx_skins_results_round ON skins_results(round_id);
CREATE INDEX idx_skins_results_winner ON skins_results(round_id, winner_player_id) 
  WHERE winner_player_id IS NOT NULL;

COMMENT ON TABLE skins_results IS 'Skin winners per hole with rollover tracking';
COMMENT ON COLUMN skins_results.winner_player_id IS 'NULL if tie (no winner)';
COMMENT ON COLUMN skins_results.carryover_value IS 'Accumulated carryover from previous ties';
COMMENT ON COLUMN skins_results.skin_awarded_value IS 'Total value awarded (carryover + 1)';

-- ============================================
-- VERIFICATION QUERIES
-- ============================================
-- Uncomment to verify migration:

-- SELECT 'rounds table exists' as check, COUNT(*) as count FROM rounds;
-- SELECT 'teams table exists' as check, COUNT(*) as count FROM teams;
-- SELECT 'round_players table exists' as check, COUNT(*) as count FROM round_players;
-- SELECT 'scores table exists' as check, COUNT(*) as count FROM scores;
-- SELECT 'hole_results table exists' as check, COUNT(*) as count FROM hole_results;
-- SELECT 'round_results table exists' as check, COUNT(*) as count FROM round_results;
-- SELECT 'team_results table exists' as check, COUNT(*) as count FROM team_results;
-- SELECT 'skins_results table exists' as check, COUNT(*) as count FROM skins_results;

-- ============================================
-- END OF MIGRATION 002
-- ============================================