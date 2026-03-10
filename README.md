# ParTracker — Backend (Supabase)

Supabase backend for ParTracker, a commercial golf scoring app for iOS and Android. Handles scoring, handicap calculations, tournaments, and social features.

## Tech Stack

- **Database**: PostgreSQL (Supabase)
- **Edge Functions**: Deno/TypeScript (8 functions)
- **Auth**: Supabase Auth with Row Level Security
- **Realtime**: Supabase Realtime for live score updates

## Edge Functions

| Function | Description |
|---|---|
| `create-round` | Creates round with players, tees, teams. Supports `scheduled_at`. |
| `save-score` | Saves hole scores and triggers recalculation. |
| `get-snapshot` | Real-time round snapshot. Authorises members + friends. |
| `calculate-standings` | Recalculates tournament standings after round completion. |
| `create-tournament` | Creates tournament with settings, players, teams. |
| `friend-operations` | Friend requests, invite codes, list/search/unfriend/block. |
| `delete-account` | GDPR-compliant account deletion. |
| `export-user-data` | User data export for GDPR compliance. |

## Database

- **18 SQL migrations** defining the complete schema
- **40+ Row Level Security policies**
- Key tables: `players`, `courses`, `course_tees`, `rounds`, `round_players`, `scores`, `hole_results`, `round_results`, `skins_results`, `teams`, `tournaments`, `friendships`

## Scoring Systems

- **Stableford** — WHS-compliant points-based scoring
- **Stroke Play** — Gross/net totals
- **Match Play** — Hole-by-hole competition
- **Skins** — Match play with carryover on tied holes
- **Team Best Ball** — Best stableford score per team (2v2, 4 players)

## Setup

```bash
# Install Supabase CLI
brew install supabase/tap/supabase

# Login and link
supabase login
supabase link --project-ref YOUR_PROJECT_REF

# Deploy Edge Functions
supabase functions deploy create-round
supabase functions deploy save-score
supabase functions deploy get-snapshot
supabase functions deploy calculate-standings
supabase functions deploy create-tournament
supabase functions deploy friend-operations
supabase functions deploy delete-account
supabase functions deploy export-user-data

# Set secrets
supabase secrets set SUPABASE_SERVICE_ROLE_KEY="your-service-role-key"
```

## Project Structure

```
fuldnyborg-app/
├── supabase/
│   ├── functions/           # 8 Edge Functions
│   │   ├── create-round/
│   │   ├── save-score/
│   │   ├── get-snapshot/
│   │   ├── calculate-standings/
│   │   ├── create-tournament/
│   │   ├── friend-operations/
│   │   ├── delete-account/
│   │   └── export-user-data/
│   └── migrations/          # 18 SQL migration files
├── config.toml
└── README.md
```

## Security

- All tables have Row Level Security enabled
- `is_round_member(round_id)` helper function for RLS policies
- All Edge Functions verify `auth.getUser()` before processing
- No service role keys in frontend code
- GDPR compliance: data export and account deletion

## License

Private — All Rights Reserved
