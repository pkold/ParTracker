-- Add playing_format and format_config to rounds table
-- playing_format replaces the old game_types approach with a single explicit format
-- format_config stores format-specific settings as JSONB

ALTER TABLE rounds ADD COLUMN playing_format TEXT NOT NULL DEFAULT 'stableford';
ALTER TABLE rounds ADD COLUMN format_config JSONB NULL;

-- Valid formats:
-- Individual: stroke_play, stableford (existing)
-- Combined (individual scores + team derivation): fourball, irish_rumble
-- Team (one score per team): foursome, greensome, scramble, texas_scramble

COMMENT ON COLUMN rounds.playing_format IS 'Playing format: stroke_play, stableford, fourball, irish_rumble, foursome, greensome, scramble, texas_scramble';
COMMENT ON COLUMN rounds.format_config IS 'Format-specific config JSON. E.g. fourball: {scoring: "stableford"}, irish_rumble: {best_scores: 2}, scramble: {hcp_formula: "10_low"}';

NOTIFY pgrst, 'reload schema';
