-- Drop legacy tee_id from rounds table.
-- Tee selection is per-player on round_players.tee_id.
ALTER TABLE rounds DROP COLUMN IF EXISTS tee_id;
