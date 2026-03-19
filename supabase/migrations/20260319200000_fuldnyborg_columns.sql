-- FuldNyborg game mode: extra per-hole data, results, and settlement
ALTER TABLE rounds ADD COLUMN extra_hole_data JSONB NULL;
ALTER TABLE rounds ADD COLUMN amerikanere_results JSONB NULL;
ALTER TABLE rounds ADD COLUMN units_results JSONB NULL;
ALTER TABLE rounds ADD COLUMN settlement JSONB NULL;

NOTIFY pgrst, 'reload schema';
