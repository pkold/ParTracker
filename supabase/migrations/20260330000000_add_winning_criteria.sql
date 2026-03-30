-- Add winning criteria columns to tournaments
ALTER TABLE tournaments
  ADD COLUMN primary_win_criterion TEXT NOT NULL DEFAULT 'stableford_individual'
    CHECK (primary_win_criterion IN (
      'stableford_individual',
      'stroke_play_individual',
      'team_stableford',
      'team_skins',
      'skins_individual'
    )),
  ADD COLUMN secondary_win_criteria TEXT[] DEFAULT '{}';

-- Reload PostgREST schema cache so new columns are available immediately
NOTIFY pgrst, 'reload schema';
