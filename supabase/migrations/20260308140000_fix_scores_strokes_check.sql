-- Allow strokes = 0 for pick-up in stableford
ALTER TABLE scores DROP CONSTRAINT IF EXISTS scores_strokes_check;
ALTER TABLE scores ADD CONSTRAINT scores_strokes_check
  CHECK (strokes >= 0 AND strokes <= 20);
