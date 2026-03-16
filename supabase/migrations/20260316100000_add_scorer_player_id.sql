-- Add scorer_player_id to rounds for persistent scorekeeper assignment
ALTER TABLE rounds ADD COLUMN scorer_player_id UUID NULL REFERENCES players(id);
