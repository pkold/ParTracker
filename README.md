# FuldNyborg Golf Scoring App - Backend

Supabase backend for FuldNyborg Golf Scoring Application.

## 🏗️ Architecture

- **Database:** PostgreSQL (Supabase)
- **Functions:** Supabase Edge Functions
- **Auth:** Supabase Auth (Email OTP)
- **Storage:** Supabase Storage (future)

## 📊 Database Schema

### Core Tables
- `players` - Golf players with handicap index
- `courses` - Golf courses
- `course_tees` - Tee-specific data (slope, rating, holes as JSONB)
- `rounds` - Game sessions
- `scores` - Raw stroke input per hole
- `round_players` - Player membership in rounds

### Results Tables (Calculated)
- `hole_results` - Per-hole calculations (net, stableford)
- `round_results` - Player totals
- `team_results` - Team totals (bestball/aggregate)
- `skins_results` - Skins winners with carryover

### Sidegames & Tournaments
- `sidegame_types` - Sidegame definitions
- `sidegame_events` - Sidegame occurrences
- `tournaments` - Multi-round competitions
- `tournament_standings` - Leaderboards

## 🚀 Setup Instructions

### 1. Create Supabase Project
```bash
# Go to https://supabase.com
# Create new project
# Note your project URL and API keys
```

### 2. Run Migrations (in order)
```sql
-- In Supabase SQL Editor, run these in order:
database/migrations/001_initial_schema.sql
database/migrations/002_rounds_scoring.sql
database/migrations/003_sidegames.sql
database/migrations/004_tournaments.sql
database/migrations/005_rls_policies.sql
database/migrations/006_test_data.sql
```

### 3. Deploy Functions
```sql
-- In Supabase SQL Editor:
database/functions/calculate_functions.sql
database/functions/recalculate_round.sql
database/functions/add_winner_team_id.sql
database/functions/fix_bestball_and_team_skins.sql
```

### 4. Verify Setup
```sql
-- Check tables exist
SELECT COUNT(*) FROM information_schema.tables 
WHERE table_schema = 'public';
-- Should return 19

-- Check test data
SELECT * FROM courses WHERE name = 'Nyborg Golf Club';
SELECT * FROM players;
```

## 🧪 Testing

Run test queries from `database/tests/`:
- `test_round_creation.sql` - Basic round creation and scoring
- `test_skins_carryover.sql` - Skins rollover logic
- `test_2v2_bestball.sql` - Team bestball scoring
- `test_team_skins.sql` - Team skins with carryover

## 📐 Key Functions

### `calculate_playing_hcp(handicap_index, slope, rating, par, allowance, holes)`
Converts WHS handicap index to playing handicap for specific tee.

### `calculate_strokes_received(playing_hcp, stroke_index, holes_played)`
Determines handicap strokes per hole based on stroke index.

### `calculate_stableford_points(net_strokes, par)`
Converts net score to stableford points.

### `recalculate_round(round_id)`
**Main scoring engine.** Recalculates all results for a round:
- Hole-by-hole results (net, stableford)
- Player totals
- Team results (bestball gross/net/points)
- Skins (individual or team, with carryover)

Returns JSONB summary of calculations performed.

## 🎯 Features

### ✅ Completed (E0: Foundations)
- [x] Database schema (19 tables)
- [x] Row Level Security (RLS) policies
- [x] Core calculation functions (WHS)
- [x] Scoring engine (individual + teams)
- [x] Skins (NET/GROSS, carryover, team support)
- [x] Bestball team scoring
- [x] Test data (Nyborg Golf Club + players)

### 🔄 In Progress (E1: Core API)
- [ ] Edge Function: create-round
- [ ] Edge Function: save-score
- [ ] Edge Function: get-snapshot

### 📋 Planned
- [ ] Offline sync (batch upload)
- [ ] Sidegames API
- [ ] Tournament API
- [ ] Frontend (PWA)

## 📚 Documentation

See `/docs` folder for:
- API specifications (coming soon)
- Architecture decisions
- Testing guides

## 🔄 Automatic Backups

This repository uses GitHub Actions to automatically backup the Supabase schema:
- **Schedule:** Daily at 3 AM UTC
- **Location:** `database/backups/schema_backup_YYYYMMDD.sql`
- **Retention:** Last 7 days

**Setup:** See [docs/GITHUB_ACTIONS_SETUP.md](docs/GITHUB_ACTIONS_SETUP.md) for configuration instructions.

## 🔐 Security

- All tables protected by RLS policies
- Users can only see rounds they created or are members of
- Service role required for Edge Functions
- Sensitive credentials stored in GitHub Secrets

## 🤝 Contributing

This is a private project. Contact @pkold for access.

## 📝 License

Private - All Rights Reserved

---

**Last Updated:** January 10, 2026  
**Status:** Backend Complete (E0), Ready for Edge Functions (E1)
