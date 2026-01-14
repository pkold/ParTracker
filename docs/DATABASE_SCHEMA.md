# Database Schema Documentation

Complete reference for FuldNyborg Golf Scoring database schema.

## Overview

The database consists of 19 tables organized into 4 categories:
1. **Core Tables** - Courses, players, rounds
2. **Team Tables** - Team definitions and memberships
3. **Score Tables** - Raw score data
4. **Result Tables** - Calculated results (auto-updated)

---

## Entity Relationship Diagram

```
courses
  ├── course_tees
  │     └── rounds
  │           ├── round_players ──┐
  │           ├── scores          │
  │           ├── hole_results    ├── players
  │           ├── round_results ──┘
  │           ├── team_results ── teams
  │           ├── skins_results       └── team_members
  │           ├── round_sidegames
  │           └── sidegame_events
  └── tournaments
        └── tournament_rounds
```

---

## Core Tables

### courses

Golf courses in the system.

**Columns:**
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT uuid_generate_v4() | Unique course identifier |
| name | TEXT | NOT NULL | Course name |
| location | TEXT | NULL | City/region |
| holes | INTEGER | NOT NULL, DEFAULT 18 | Total holes (9 or 18) |
| created_at | TIMESTAMPTZ | DEFAULT NOW() | Creation timestamp |

**Indexes:**
- PRIMARY KEY on `id`

**Sample Data:**
```sql
INSERT INTO courses (id, name, location, holes) VALUES
('e948845c-d84d-4dfd-bef4-a294925477f8', 'Nyborg Golf Club', 'Nyborg, Denmark', 18);
```

---

### course_tees

Tee boxes for courses with WHS ratings.

**Columns:**
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT uuid_generate_v4() | Unique tee identifier |
| course_id | UUID | FK → courses.id, NOT NULL | Parent course |
| tee_name | TEXT | NOT NULL | Tee name (e.g., "Championship") |
| tee_color | TEXT | NOT NULL | Color code (e.g., "black", "yellow") |
| gender | TEXT | NOT NULL | "men", "women", "mixed" |
| slope_rating | NUMERIC(5,1) | NOT NULL | WHS slope rating (55-155) |
| course_rating | NUMERIC(4,1) | NOT NULL | WHS course rating |
| par | INTEGER | NOT NULL | Total par for the tee |
| holes | JSONB | NOT NULL | Array of hole details |
| created_at | TIMESTAMPTZ | DEFAULT NOW() | Creation timestamp |

**Indexes:**
- PRIMARY KEY on `id`
- FOREIGN KEY on `course_id`

**Holes JSONB Structure:**
```json
[
  {
    "hole_no": 1,
    "par": 4,
    "stroke_index": 11
  },
  ...
]
```

**Sample Data:**
```sql
INSERT INTO course_tees (course_id, tee_name, tee_color, gender, slope_rating, course_rating, par, holes) VALUES
('e948845c-...', 'Yellow', 'yellow', 'mixed', 113, 69.5, 72, '[...]');
```

---

### players

Player profiles.

**Columns:**
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT uuid_generate_v4() | Unique player identifier |
| display_name | TEXT | NOT NULL | Player name |
| user_id | UUID | FK → auth.users, NULL | Linked Supabase user |
| handicap_index | NUMERIC(4,1) | NULL | Current WHS handicap |
| email | TEXT | NULL | Contact email |
| phone | TEXT | NULL | Contact phone |
| created_at | TIMESTAMPTZ | DEFAULT NOW() | Creation timestamp |
| updated_at | TIMESTAMPTZ | DEFAULT NOW() | Last update timestamp |

**Indexes:**
- PRIMARY KEY on `id`
- UNIQUE on `user_id`
- INDEX on `email`

---

### rounds

Golf rounds/games.

**Columns:**
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT uuid_generate_v4() | Unique round identifier |
| course_id | UUID | FK → courses.id, NOT NULL | Course played |
| tee_id | UUID | FK → course_tees.id, NOT NULL | Tee used |
| created_by | UUID | FK → auth.users, NOT NULL | Round creator |
| created_at | TIMESTAMPTZ | DEFAULT NOW() | Creation timestamp |
| holes_played | INTEGER | NOT NULL, DEFAULT 18 | 9 or 18 |
| start_hole | INTEGER | NOT NULL, DEFAULT 1 | Starting hole (1-18) |
| handicap_allowance | NUMERIC(3,2) | NOT NULL, DEFAULT 1.0 | WHS allowance (0.0-1.0) |
| scoring_format | TEXT | NOT NULL, DEFAULT 'stableford' | Format type |
| team_mode | TEXT | NOT NULL, DEFAULT 'individual' | Team configuration |
| team_scoring_mode | TEXT | NOT NULL, DEFAULT 'aggregate' | Team scoring method |
| skins_enabled | BOOLEAN | NOT NULL, DEFAULT FALSE | Enable skins |
| skins_type | TEXT | NOT NULL, DEFAULT 'net' | 'net' or 'gross' |
| skins_rollover | BOOLEAN | NOT NULL, DEFAULT TRUE | Enable carryover |
| join_code | TEXT | NULL | Optional join code |
| visibility | TEXT | NOT NULL, DEFAULT 'private' | Access control |
| status | TEXT | NOT NULL, DEFAULT 'active' | Round status |
| started_at | TIMESTAMPTZ | NULL | Start time |
| finished_at | TIMESTAMPTZ | NULL | Finish time |

**Indexes:**
- PRIMARY KEY on `id`
- FOREIGN KEY on `course_id`, `tee_id`, `created_by`
- INDEX on `created_by`
- INDEX on `status`

**Scoring Formats:**
- `stableford` - Modified stableford scoring
- `stroke` - Stroke play
- `match` - Match play

**Team Modes:**
- `individual` - No teams
- `bestball` - Best ball team scoring (2v2, 3v3, 4v4)

---

### round_players

Players participating in a round.

**Columns:**
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| round_id | UUID | PK, FK → rounds.id | Parent round |
| player_id | UUID | PK, FK → players.id | Player |
| user_id | UUID | FK → auth.users, NULL | Linked user account |
| role | TEXT | NOT NULL, DEFAULT 'player' | Player role |
| playing_hcp | INTEGER | NOT NULL | Calculated playing handicap |
| team_id | UUID | FK → teams.id, NULL | Team assignment |
| created_at | TIMESTAMPTZ | DEFAULT NOW() | Join timestamp |

**Indexes:**
- PRIMARY KEY on `(round_id, player_id)`
- FOREIGN KEY on `round_id`, `player_id`, `user_id`, `team_id`

**Playing Handicap Calculation:**
```
Playing HCP = (Handicap Index × Slope / 113 + (Course Rating - Par)) × Allowance
For 9 holes: divide by 2
```

---

## Team Tables

### teams

Team definitions.

**Columns:**
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT uuid_generate_v4() | Team identifier |
| name | TEXT | NOT NULL | Team name |
| created_at | TIMESTAMPTZ | DEFAULT NOW() | Creation timestamp |

---

### team_members

Team membership.

**Columns:**
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| team_id | UUID | PK, FK → teams.id | Team |
| player_id | UUID | PK, FK → players.id | Player |
| joined_at | TIMESTAMPTZ | DEFAULT NOW() | Join timestamp |

**Indexes:**
- PRIMARY KEY on `(team_id, player_id)`

---

## Score Tables

### scores

Raw stroke data per hole.

**Columns:**
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| round_id | UUID | PK, FK → rounds.id | Parent round |
| player_id | UUID | PK, FK → players.id | Player |
| hole_no | INTEGER | PK, CHECK (1-18) | Hole number |
| strokes | INTEGER | NOT NULL, CHECK (≥ 1) | Number of strokes |
| client_event_id | UUID | NULL | Idempotency key |
| updated_at | TIMESTAMPTZ | DEFAULT NOW() | Last update |
| updated_by | UUID | FK → auth.users, NULL | Last updater |

**Indexes:**
- PRIMARY KEY on `(round_id, player_id, hole_no)`
- UNIQUE on `client_event_id` (if not null)

**Notes:**
- Uses UPSERT logic for updates
- `client_event_id` ensures offline sync idempotency

---

## Result Tables (Auto-calculated)

All result tables are automatically updated by the `recalculate_round()` function.

### hole_results

Per-hole calculated results.

**Columns:**
| Column | Type | Description |
|--------|------|-------------|
| round_id | UUID | Parent round |
| player_id | UUID | Player |
| hole_no | INTEGER | Hole number |
| strokes | INTEGER | Raw strokes |
| par | INTEGER | Hole par |
| stroke_index | INTEGER | Hole difficulty |
| strokes_received | INTEGER | Handicap strokes for this hole |
| net_strokes | INTEGER | Gross - strokes received |
| stableford_points | INTEGER | Points earned |
| updated_at | TIMESTAMPTZ | Last calculation |

**Stableford Points:**
| Score | Points |
|-------|--------|
| Double bogey+ | 0 |
| Bogey | 1 |
| Par | 2 |
| Birdie | 3 |
| Eagle | 4 |
| Albatross | 5 |

---

### round_results

Player totals for a round.

**Columns:**
| Column | Type | Description |
|--------|------|-------------|
| round_id | UUID | Parent round |
| player_id | UUID | Player |
| gross_total | INTEGER | Sum of gross strokes |
| net_total | INTEGER | Sum of net strokes |
| stableford_total | INTEGER | Sum of stableford points |
| updated_at | TIMESTAMPTZ | Last calculation |

---

### team_results

Team totals (for team modes).

**Columns:**
| Column | Type | Description |
|--------|------|-------------|
| round_id | UUID | Parent round |
| team_id | UUID | Team |
| gross_total | INTEGER | Team gross total |
| net_total | INTEGER | Team net total |
| stableford_total | INTEGER | Team stableford total |
| updated_at | TIMESTAMPTZ | Last calculation |

**Team Scoring Modes:**
- `aggregate` - Sum all players' scores
- `bestball` - Best score per hole

---

### skins_results

Skins winners per hole.

**Columns:**
| Column | Type | Description |
|--------|------|-------------|
| round_id | UUID | Parent round |
| hole_no | INTEGER | Hole number |
| winner_player_id | UUID | Winning player |
| winner_team_id | UUID | Winning team (if team skins) |
| winning_score | INTEGER | Net or gross score |
| carryover_value | INTEGER | Skins carried from ties |
| skin_awarded_value | INTEGER | Total skins awarded |
| updated_at | TIMESTAMPTZ | Last calculation |

**Skins Logic:**
- Ties result in carryover to next hole
- Final hole with tie: skins remain unawarded
- NET mode: uses net strokes
- GROSS mode: uses gross strokes

---

## Functions

### calculate_playing_hcp

Calculates WHS playing handicap.

**Parameters:**
- `p_handicap_index` NUMERIC - Player's handicap index
- `p_slope_rating` NUMERIC - Tee slope rating
- `p_course_rating` NUMERIC - Tee course rating
- `p_par` INTEGER - Tee par
- `p_handicap_allowance` NUMERIC - Allowance (0.0-1.0)
- `p_holes_played` INTEGER - 9 or 18

**Returns:** INTEGER (playing handicap)

---

### recalculate_round

Recalculates all results for a round.

**Parameters:**
- `p_round_id` UUID - Round to recalculate

**Returns:** JSONB snapshot
```json
{
  "round_id": "uuid",
  "holes_calculated": 5,
  "skins_calculated": 5,
  "teams_calculated": 0,
  "players_calculated": 4
}
```

**Side Effects:**
- Deletes and recreates hole_results
- Deletes and recreates round_results
- Deletes and recreates team_results (if applicable)
- Deletes and recreates skins_results (if applicable)

---

### is_round_member

Checks if a user has access to a round.

**Signatures:**
1. `is_round_member(p_round_id UUID)` - Uses auth.uid()
2. `is_round_member(p_round_id UUID, p_user_id UUID)` - Explicit user

**Returns:** BOOLEAN

**Logic:**
- Returns TRUE if user created the round
- Returns TRUE if user is in round_players
- Returns FALSE otherwise

---

## Row Level Security (RLS)

All tables have RLS enabled with policies:

**Read Access:**
- Users can read rounds they created or are members of
- Public read for courses and course_tees

**Write Access:**
- Only round creator can update round settings
- Only round members can update scores
- Admin (SERVICE_ROLE) has full access

---

## Migrations

Schema is managed through numbered SQL migrations:

1. `001_core_tables.sql` - Courses, players, rounds
2. `002_team_tables.sql` - Teams, team_members
3. `003_score_tables.sql` - Scores, results
4. `004_rls_policies.sql` - Row level security
5. `005_indexes.sql` - Performance indexes
6. `006_core_functions.sql` - PostgreSQL functions

Apply in order for correct dependencies.

---

**For more information, see:**
- [API Documentation](API.md)
- [Setup Guide](SETUP.md)
- [Architecture Overview](ARCHITECTURE.md)
