-- Add match_play_enabled flag to rounds table
ALTER TABLE rounds ADD COLUMN match_play_enabled BOOLEAN NOT NULL DEFAULT false;
