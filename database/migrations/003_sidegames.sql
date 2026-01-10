-- ============================================
-- MIGRATION 003: Sidegames Framework
-- ============================================
-- Run this AFTER migration 002
-- This creates the sidegames tracking system

-- ============================================
-- STEP 1: SIDEGAME TYPES (global definitions)
-- ============================================
CREATE TABLE sidegame_types (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  scoring_mode TEXT NOT NULL CHECK (scoring_mode IN ('count','value')),
  default_value NUMERIC,
  rules_json JSONB,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE sidegame_types IS 'Global sidegame definitions (sandy, lay, etc.)';
COMMENT ON COLUMN sidegame_types.code IS 'Unique code identifier (e.g. "sandy", "lay")';
COMMENT ON COLUMN sidegame_types.scoring_mode IS 'count = fixed 1 per event, value = numeric amount';
COMMENT ON COLUMN sidegame_types.rules_json IS 'V2: Auto-detection rules (future)';

-- ============================================
-- STEP 2: Insert default sidegame types
-- ============================================
INSERT INTO sidegame_types (code, name, description, scoring_mode, default_value) VALUES
('sandy', 'Sandies', 'Par or better after being in bunker', 'count', 1),
('lay', 'Læg', 'Closest to pin on par 3 (tee shot)', 'count', 1),
('anti_lay', 'Anti-læg', 'Farthest from pin on par 3 (tee shot)', 'count', 1),
('birdie', 'Birdies', 'One under par (gross)', 'count', 1),
('eagle', 'Eagles', 'Two under par (gross)', 'count', 1),
('american', 'Amerikaner', 'Configurable points/money game', 'value', NULL);

COMMENT ON TABLE sidegame_types IS 'Pre-populated with common sidegames';

-- ============================================
-- STEP 3: ROUND SIDEGAMES (enabled per round)
-- ============================================
CREATE TABLE round_sidegames (
  round_id UUID NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
  sidegame_code TEXT NOT NULL REFERENCES sidegame_types(code) ON DELETE CASCADE,
  is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  custom_value NUMERIC,
  custom_rules_json JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (round_id, sidegame_code)
);

CREATE INDEX idx_round_sidegames_round ON round_sidegames(round_id) 
  WHERE is_enabled = TRUE;

COMMENT ON TABLE round_sidegames IS 'Which sidegames are active for each round';
COMMENT ON COLUMN round_sidegames.custom_value IS 'Override default_value for this round (e.g. 5 kr per sandy)';

-- ============================================
-- STEP 4: SIDEGAME EVENTS (occurrences)
-- ============================================
CREATE TABLE sidegame_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  round_id UUID NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
  sidegame_code TEXT NOT NULL REFERENCES sidegame_types(code) ON DELETE CASCADE,
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  
  hole_no INT CHECK (hole_no BETWEEN 1 AND 18),
  value NUMERIC NOT NULL DEFAULT 1,
  note TEXT,
  
  -- Audit trail
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID NOT NULL,
  is_auto_detected BOOLEAN NOT NULL DEFAULT FALSE,
  
  -- Ensure round has this sidegame enabled
  CONSTRAINT fk_round_sidegame FOREIGN KEY (round_id, sidegame_code) 
    REFERENCES round_sidegames(round_id, sidegame_code) ON DELETE CASCADE
);

CREATE INDEX idx_sidegame_events_round ON sidegame_events(round_id);
CREATE INDEX idx_sidegame_events_player ON sidegame_events(round_id, player_id);
CREATE INDEX idx_sidegame_events_sidegame ON sidegame_events(round_id, sidegame_code);
CREATE INDEX idx_sidegame_events_hole ON sidegame_events(round_id, hole_no) 
  WHERE hole_no IS NOT NULL;

COMMENT ON TABLE sidegame_events IS 'Individual sidegame occurrences (manual v1, auto v2)';
COMMENT ON COLUMN sidegame_events.hole_no IS 'Nullable for round-level events (e.g. Amerikaner)';
COMMENT ON COLUMN sidegame_events.is_auto_detected IS 'False = manual entry, True = auto-detected (v2)';
COMMENT ON COLUMN sidegame_events.created_by IS 'User who recorded the event';

-- ============================================
-- STEP 5: SIDEGAME TOTALS VIEW (aggregation)
-- ============================================
CREATE OR REPLACE VIEW sidegame_totals AS
SELECT
  e.round_id,
  e.sidegame_code,
  st.name AS sidegame_name,
  st.scoring_mode,
  e.player_id,
  p.display_name AS player_name,
  COUNT(*) AS event_count,
  SUM(e.value) AS total_value
FROM sidegame_events e
JOIN sidegame_types st ON st.code = e.sidegame_code
JOIN players p ON p.id = e.player_id
GROUP BY 
  e.round_id, 
  e.sidegame_code, 
  st.name, 
  st.scoring_mode,
  e.player_id, 
  p.display_name;

COMMENT ON VIEW sidegame_totals IS 
'Aggregated sidegame statistics per player per round';

-- ============================================
-- VERIFICATION QUERIES
-- ============================================
-- Uncomment to verify:

-- SELECT 'sidegame_types' as table_name, COUNT(*) as row_count FROM sidegame_types;
-- SELECT 'round_sidegames' as table_name, COUNT(*) as row_count FROM round_sidegames;
-- SELECT 'sidegame_events' as table_name, COUNT(*) as row_count FROM sidegame_events;

-- Show default sidegame types:
-- SELECT code, name, scoring_mode, default_value FROM sidegame_types ORDER BY code;

-- ============================================
-- END OF MIGRATION 003
-- ============================================