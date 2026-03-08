-- Add first_name and last_name columns to players table
ALTER TABLE players ADD COLUMN IF NOT EXISTS first_name TEXT;
ALTER TABLE players ADD COLUMN IF NOT EXISTS last_name TEXT;
