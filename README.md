# FuldNyborg Golf Scoring App

A comprehensive golf scoring system built on Supabase with support for WHS handicapping, stableford scoring, team modes, and skins games.

## 🎯 Features

### Core Functionality
- **WHS Handicap System** - Automatic playing handicap calculation using World Handicap System formulas
- **Multiple Scoring Formats** - Stableford, stroke play, match play
- **Team Modes** - Individual, 2v2, 3v3, 4v4 best ball
- **Skins Games** - NET/GROSS scoring with carryover support
- **Real-time Calculation** - Automatic score recalculation on every update
- **Multi-round Tournaments** - Track results across multiple rounds

### Technical Features
- **RESTful API** - Edge Functions for all operations
- **Row Level Security** - Database-level access control
- **Offline Support** - Client-event-id based idempotency
- **Type Safety** - PostgreSQL functions with proper types
- **Automated Backups** - Nightly schema backups via GitHub Actions

## 🏗️ Architecture

```
┌─────────────────────────────────────────────┐
│           Frontend (Future)                 │
│  React/Vue/Mobile App                       │
└─────────────────┬───────────────────────────┘
                  │
                  │ HTTPS/JWT
                  ▼
┌─────────────────────────────────────────────┐
│         Supabase Edge Functions             │
│  • create-round                             │
│  • save-score                               │
│  • get-snapshot                             │
└─────────────────┬───────────────────────────┘
                  │
                  │ PostgreSQL
                  ▼
┌─────────────────────────────────────────────┐
│           Supabase Database                 │
│  • 19 tables                                │
│  • RLS policies                             │
│  • PostgreSQL functions                     │
│  • Automated calculations                   │
└─────────────────────────────────────────────┘
```

## 📊 Database Schema

### Core Tables
- **courses** - Golf courses
- **course_tees** - Tee boxes with ratings
- **players** - Player profiles
- **rounds** - Golf rounds/games
- **round_players** - Players in a round
- **teams** - Team definitions
- **scores** - Raw stroke data

### Result Tables (Auto-calculated)
- **hole_results** - Per-hole calculated results
- **round_results** - Player totals
- **team_results** - Team totals
- **skins_results** - Skins winners per hole

See [docs/DATABASE_SCHEMA.md](docs/DATABASE_SCHEMA.md) for complete schema documentation.

## 🚀 API Endpoints

All Edge Functions require JWT authentication via Supabase Auth.

### POST /functions/v1/create-round
Creates a new golf round with players.

**Request:**
```json
{
  "course_id": "uuid",
  "tee_id": "uuid",
  "players": [
    {
      "player_id": "uuid",
      "handicap_index": 5.2
    }
  ],
  "holes_played": 18,
  "skins_enabled": true,
  "skins_type": "net"
}
```

**Response:**
```json
{
  "success": true,
  "round_id": "uuid",
  "round": {...},
  "players": [...],
  "snapshot": {...}
}
```

### POST /functions/v1/save-score
Saves a score and triggers recalculation.

**Request:**
```json
{
  "round_id": "uuid",
  "player_id": "uuid",
  "hole_no": 1,
  "strokes": 4,
  "client_event_id": "uuid" // Optional, for offline sync
}
```

**Response:**
```json
{
  "success": true,
  "round_id": "uuid",
  "snapshot": {
    "holes_calculated": 1,
    "skins_calculated": 1,
    "players_calculated": 4
  }
}
```

### GET /functions/v1/get-snapshot?round_id=uuid
Retrieves complete round status.

**Response:**
```json
{
  "success": true,
  "round": {...},
  "players": [...],
  "scores": [...],
  "hole_results": [...],
  "round_results": [...],
  "team_results": [...],
  "skins_results": [...]
}
```

See [docs/API.md](docs/API.md) for complete API documentation.

## 🛠️ Setup

### Prerequisites
- Node.js 18+
- Supabase account
- Supabase CLI

### Installation

1. **Clone repository:**
```bash
git clone https://github.com/pkold/fuldnyborg-app.git
cd fuldnyborg-app
```

2. **Install Supabase CLI:**
```bash
brew install supabase/tap/supabase
```

3. **Login to Supabase:**
```bash
supabase login
```

4. **Link to your project:**
```bash
supabase link --project-ref YOUR_PROJECT_REF
```

5. **Run migrations:**
```bash
# Apply all migrations in order
psql -h db.YOUR_PROJECT_REF.supabase.co -U postgres -d postgres -f database/migrations/001_core_tables.sql
psql -h db.YOUR_PROJECT_REF.supabase.co -U postgres -d postgres -f database/migrations/002_team_tables.sql
# ... (run all migrations in order)
```

6. **Deploy Edge Functions:**
```bash
supabase functions deploy create-round
supabase functions deploy save-score
supabase functions deploy get-snapshot
```

7. **Set secrets:**
```bash
supabase secrets set SERVICE_ROLE_KEY="your-service-role-key"
```

See [docs/SETUP.md](docs/SETUP.md) for detailed setup instructions.

## 🧪 Testing

### Run end-to-end test:
```bash
./test_complete_flow.sh
```

### Create test round:
```bash
./create_new_round.sh
```

## 📁 Project Structure

```
fuldnyborg-app/
├── .github/
│   └── workflows/
│       └── backup-schema.yml        # Automated nightly backups
├── database/
│   ├── migrations/                  # SQL migrations (001-006)
│   ├── functions/                   # PostgreSQL functions
│   ├── tests/                       # Database tests
│   └── backups/                     # Nightly schema backups
├── supabase/
│   ├── config.toml                  # Supabase configuration
│   └── functions/                   # Edge Functions
│       ├── create-round/
│       ├── save-score/
│       └── get-snapshot/
├── docs/                            # Documentation
├── test_complete_flow.sh            # E2E test script
└── README.md
```

## 🔐 Security

- **JWT Authentication** - All Edge Functions require valid JWT
- **Row Level Security** - Database policies enforce access control
- **Authorization Checks** - `is_round_member()` verifies access
- **Service Role Protection** - Admin operations use SERVICE_ROLE_KEY
- **Secrets Management** - Sensitive keys stored in Supabase secrets

## 🎓 Key Concepts

### WHS Handicap Calculation
Playing handicap = (Handicap Index × Slope Rating / 113 + (Course Rating - Par)) × Handicap Allowance

For 9 holes, divide by 2.

### Stableford Scoring
- Double bogey or worse: 0 points
- Bogey: 1 point
- Par: 2 points
- Birdie: 3 points
- Eagle: 4 points
- Albatross: 5 points

### Skins Games
- **NET mode**: Uses net strokes (gross - handicap strokes)
- **GROSS mode**: Uses gross strokes
- **Carryover**: Ties result in carry to next hole

## 📝 Development Status

- ✅ E0: Foundations (100%)
- ✅ E1: Core API (100%)
- ⬜ E6: Frontend (0%)
- ⬜ Documentation (In Progress)

## 🤝 Contributing

This is a private project. Contact the owner for access.

## 📄 License

Private - All Rights Reserved

## 🙋 Support

For questions or issues, contact: peter@fuldnyborg.dk

---

**Built with ❤️ using Supabase**
