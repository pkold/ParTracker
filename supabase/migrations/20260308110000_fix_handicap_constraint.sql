-- Fix handicap_index constraint to allow plus handicaps (stored as negative values)
-- WHS range: -10.0 (plus handicap) to 56.0
ALTER TABLE players DROP CONSTRAINT IF EXISTS players_handicap_index_check;
ALTER TABLE players ADD CONSTRAINT players_handicap_index_check
  CHECK (handicap_index >= -10.0 AND handicap_index <= 56.0);

COMMENT ON COLUMN players.handicap_index IS 'WHS handicap index (-10.0 to 56.0, negative = plus handicap)';
