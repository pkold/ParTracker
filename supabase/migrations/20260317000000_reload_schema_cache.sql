-- Force PostgREST to reload schema cache after adding name and scorer_player_id columns
NOTIFY pgrst, 'reload schema';
