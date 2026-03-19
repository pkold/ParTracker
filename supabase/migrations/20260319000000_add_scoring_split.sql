-- Add scoring_split to tournaments for team tournament split scoring
-- When set, individual and team rankings use different scoring formats
-- Example: {"individual_format": "stableford", "team_format": "stroke_play", "team_points_max": 100}
ALTER TABLE tournaments ADD COLUMN scoring_split JSONB NULL;

NOTIFY pgrst, 'reload schema';
