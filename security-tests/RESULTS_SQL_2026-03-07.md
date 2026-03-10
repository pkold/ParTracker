# ParTracker SQL Security Test Results — 2026-03-07

## Summary

| Metric   | Count |
|----------|-------|
| Passed   | 57    |
| Failed   | 0     |
| Warnings | 1     |

## Test Categories

### Table Existence (19/19 passed)
All 19 critical tables confirmed present: players, rounds, round_players, scores, course_tees, courses, friendships, friend_invite_codes, tournaments, tournament_players, tournament_rounds, tournament_standings, user_consents, skins_results, hole_results, round_results, user_hidden_items, home_courses, contact_messages.

### RLS Protection (16/16 passed)
All protected tables correctly block unauthenticated (anon key only) access — 0 rows returned for each.

### Public Tables (2/2 passed)
- `courses` — readable via anon (correct, public data)
- `course_tees` — readable via anon (correct, public data)

### Schema Correctness (15 passed, 1 warning)
- No `is_guest` column anywhere in schema
- `gender` column exists on `players`
- All 4 gendered tee rating columns present (`slope_rating_male/female`, `course_rating_male/female`)
- No deprecated `slope_rating` or `gender` columns on `course_tees`
- `visible_to_friends` and `scheduled_at` on `rounds`
- `tee_id` on `round_players` (per-player tee selection)
- `total_points` on `tournament_standings`
- `user_id` and `course_id` on `home_courses`

**Warning:** `tee_id` also found on `rounds` table. Per CLAUDE.md, tee should only be on `round_players`. The column on `rounds` may be a legacy column that should be removed via migration.

### Relationship Checks (4/4 passed)
- `round_players` -> `rounds` (FK verified)
- `scores` -> `rounds` (FK verified)
- `round_players` -> `course_tees` (FK verified)
- `tournament_rounds` -> `tournaments` (FK verified)

### Security Checks (2/2 passed)
- No `users` table exposed in public schema (auth.users stays in auth schema)
- Service role key has expected full access

## Action Items

1. **Consider removing `tee_id` from `rounds` table** — it's a legacy column. Tee selection is per-player on `round_players.tee_id`. A migration to drop this column would clean up the schema.
