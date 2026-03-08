-- Fix playing_hcp constraint on round_players to allow plus handicaps (negative values)
ALTER TABLE round_players DROP CONSTRAINT IF EXISTS round_players_playing_hcp_check;
ALTER TABLE round_players ADD CONSTRAINT round_players_playing_hcp_check
  CHECK (playing_hcp >= -10 AND playing_hcp <= 56);
