# Changelog

All notable changes to FuldNyborg Golf Scoring App backend.

## [Unreleased]

### E1: Core API (In Progress)
- Edge Functions for create-round, save-score, get-snapshot

## [0.1.0] - 2026-01-10

### E0: Foundations - COMPLETE ✅

#### Added - Database Schema
- Initial schema with 19 tables (players, courses, rounds, scores, results)
- JSONB storage for course holes (par, stroke index per hole)
- Sidegames framework (types, events, round configuration)
- Tournament system (multi-round aggregation, standings)
- Row Level Security (RLS) policies for all tables

#### Added - Core Functions
- `calculate_playing_hcp()` - WHS playing handicap calculation
- `calculate_strokes_received()` - Handicap strokes per hole
- `calculate_stableford_points()` - Net score to points conversion
- `recalculate_round()` - Main scoring engine (deterministic recalculation)

#### Added - Scoring Features
- Individual stableford scoring with handicap
- NET vs GROSS skins with carryover/rollover
- Team bestball scoring (gross, net, stableford)
- Team skins with carryover support
- `winner_team_id` column for proper team skins storage

#### Added - Test Data
- Nyborg Golf Club (Yellow tee, 18 holes with realistic SI)
- 5 test players with varying handicaps (5.2 - 24.3)
- Test queries for individual and team modes

#### Fixed
- JSONB hole data extraction (replaced tee_holes table reference)
- Bestball gross/net totals (now use MIN per hole, not aggregate)
- Skins NET vs GROSS logic (respects skins_type setting)
- Team skins comparison (compares best team scores per hole)
- Carryover calculation (works for both individual and team modes)

#### Testing
- ✅ Individual scoring (3 players × 3 holes)
- ✅ Skins carryover (verified 2 ties → 3 skins awarded)
- ✅ Team bestball 2v2 (verified gross=13, net=12, points=6)
- ✅ Team skins (verified winner_team_id storage and carryover)

### Database Migrations Applied
1. `001_initial_schema.sql` - Players, courses, course_tees, app_logs
2. `002_rounds_scoring.sql` - Rounds, scores, results tables
3. `003_sidegames.sql` - Sidegame framework
4. `004_tournaments.sql` - Tournament system
5. `005_rls_policies.sql` - Security policies
6. `006_test_data.sql` - Nyborg GC + test players

### Functions Deployed
1. `calculate_functions.sql` - WHS calculation functions
2. `recalculate_round.sql` - Main scoring engine
3. `add_winner_team_id.sql` - Schema update for team skins
4. `fix_bestball_and_team_skins.sql` - Final bestball fixes

---

## Version History

- **0.1.0** (2026-01-10) - E0: Foundations Complete
- **0.2.0** (planned) - E1: Core API (Edge Functions)
- **0.3.0** (planned) - E2: Offline Sync
- **1.0.0** (planned) - E6: Frontend MVP + E7: Field Testing

---

**Note:** Version numbers follow [Semantic Versioning](https://semver.org/).
