# Architecture Overview

Technical architecture and design decisions for FuldNyborg Golf Scoring App.

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    CLIENT LAYER                         │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │  Web App     │  │  Mobile App  │  │  Admin Panel │ │
│  │  (Future)    │  │  (Future)    │  │  (Future)    │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
│                                                         │
│  Authentication: JWT Tokens via Supabase Auth          │
└─────────────────────┬───────────────────────────────────┘
                      │
                      │ HTTPS + JWT
                      │
┌─────────────────────▼───────────────────────────────────┐
│                  API LAYER (Edge Functions)             │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  create-round                                    │  │
│  │  • Validates input                               │  │
│  │  • Calculates WHS handicaps                      │  │
│  │  • Creates round + players                       │  │
│  │  • Returns initial snapshot                      │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  save-score                                      │  │
│  │  • Authorizes user                               │  │
│  │  • Upserts score                                 │  │
│  │  • Triggers recalculation                        │  │
│  │  • Returns updated snapshot                      │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  get-snapshot                                    │  │
│  │  • Authorizes user                               │  │
│  │  • Fetches complete round state                  │  │
│  │  • Returns all results + calculations            │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  Runtime: Deno (TypeScript)                            │
│  Security: JWT auth + is_round_member() check          │
└─────────────────────┬───────────────────────────────────┘
                      │
                      │ PostgreSQL Protocol
                      │
┌─────────────────────▼───────────────────────────────────┐
│              DATABASE LAYER (Supabase)                  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Core Tables                                     │  │
│  │  • courses, course_tees                          │  │
│  │  • players, rounds, round_players                │  │
│  │  • teams, team_members                           │  │
│  │  • scores                                        │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Result Tables (Auto-calculated)                 │  │
│  │  • hole_results                                  │  │
│  │  • round_results                                 │  │
│  │  • team_results                                  │  │
│  │  • skins_results                                 │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  PostgreSQL Functions                            │  │
│  │  • calculate_playing_hcp()                       │  │
│  │  • recalculate_round()                           │  │
│  │  • is_round_member()                             │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  Security: Row Level Security (RLS) policies           │
└─────────────────────────────────────────────────────────┘
```

---

## Design Principles

### 1. Separation of Concerns

**Data Storage vs Calculations:**
- Raw scores stored in `scores` table
- Calculated results in separate tables (`hole_results`, `round_results`)
- Calculations triggered automatically via `recalculate_round()`

**Benefits:**
- Clear data lineage
- Easy to recalculate if formulas change
- Simplified queries (pre-calculated results)

---

### 2. Idempotency

**Problem:** Mobile apps may retry requests (network issues, offline sync)

**Solution:** `client_event_id` field in scores table
```sql
UNIQUE (client_event_id) WHERE client_event_id IS NOT NULL
```

**Flow:**
```
Client generates UUID: abc-123
→ POST /save-score with client_event_id: abc-123
→ Network fails, retry
→ POST /save-score with same client_event_id: abc-123
→ Database: UPSERT prevents duplicate
→ Result: Score saved exactly once
```

---

### 3. Authorization Model

**Two-Level Security:**

**Level 1: Edge Functions (Application)**
```typescript
// Verify user has access
const { data: hasAccess } = await supabaseAdmin.rpc('is_round_member', {
  p_round_id: round_id,
  p_user_id: user.id
})

if (!hasAccess) {
  throw new Error('Not authorized')
}
```

**Level 2: Database (RLS Policies)**
```sql
CREATE POLICY "scores_select_members" ON scores
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM rounds
    WHERE rounds.id = scores.round_id
    AND is_round_member(rounds.id)
  )
);
```

**Benefits:**
- Defense in depth
- Direct database access still protected
- Edge Functions can use admin client safely

---

### 4. Dual Client Pattern

**Problem:** SERVICE_ROLE_KEY bypasses RLS, but we need JWT verification

**Solution:** Two Supabase clients in Edge Functions

```typescript
// Admin client: bypasses RLS for database operations
const supabaseAdmin = createClient(
  Deno.env.get('SUPABASE_URL'),
  Deno.env.get('SERVICE_ROLE_KEY')
)

// User client: verifies JWT
const supabaseUser = createClient(
  Deno.env.get('SUPABASE_URL'),
  Deno.env.get('SUPABASE_ANON_KEY'),
  {
    global: {
      headers: { Authorization: req.headers.get('Authorization') }
    }
  }
)

// Verify auth with user client
const { data: { user } } = await supabaseUser.auth.getUser()

// Do database ops with admin client
await supabaseAdmin.from('scores').insert(...)
```

**Why:**
- Edge Functions need admin access for recalculation
- Still verify user identity via JWT
- Can pass user.id to authorization functions

---

### 5. Real-time Calculation

**Trigger:** Every score update

**Flow:**
```
User saves score (Hole 5, Player 1)
  ↓
save-score Edge Function
  ↓
UPSERT into scores table
  ↓
Call recalculate_round(round_id)
  ↓
PostgreSQL function:
  1. Delete old hole_results for this round
  2. Recalculate all hole results (net, stableford)
  3. Delete old round_results
  4. Sum up player totals
  5. Delete old skins_results
  6. Determine skins winners
  7. Return snapshot
  ↓
Return to client
```

**Why not triggers?**
- Explicit calculation control
- Easier to debug
- Can skip recalc for bulk imports
- Snapshot return useful for UX

---

## Data Flow Examples

### Creating a Round

```
┌──────────┐
│  Client  │
└────┬─────┘
     │
     │ POST /create-round
     │ { course_id, tee_id, players: [...] }
     ▼
┌─────────────────┐
│  Edge Function  │
│  create-round   │
└────┬────────────┘
     │
     │ 1. Verify JWT
     ▼
┌─────────────────┐
│ supabaseUser    │
│ .auth.getUser() │
└────┬────────────┘
     │
     │ 2. Get tee ratings
     ▼
┌──────────────────┐
│ SELECT * FROM    │
│ course_tees      │
└────┬─────────────┘
     │
     │ 3. Create round
     ▼
┌──────────────────┐
│ INSERT INTO      │
│ rounds           │
└────┬─────────────┘
     │
     │ 4. For each player:
     │    Calculate playing HCP
     ▼
┌──────────────────────────┐
│ SELECT                   │
│ calculate_playing_hcp()  │
└────┬─────────────────────┘
     │
     │ 5. Insert players
     ▼
┌──────────────────┐
│ INSERT INTO      │
│ round_players    │
└────┬─────────────┘
     │
     │ 6. Get initial snapshot
     ▼
┌──────────────────────┐
│ SELECT               │
│ recalculate_round()  │
└────┬─────────────────┘
     │
     │ 7. Return result
     ▼
┌──────────┐
│  Client  │
│ { round_id, players, snapshot }
└──────────┘
```

---

### Saving a Score

```
┌──────────┐
│  Client  │
└────┬─────┘
     │
     │ POST /save-score
     │ { round_id, player_id, hole_no: 5, strokes: 4 }
     ▼
┌─────────────────┐
│  Edge Function  │
│  save-score     │
└────┬────────────┘
     │
     │ 1. Verify JWT
     │ 2. Check authorization
     ▼
┌────────────────────┐
│ SELECT             │
│ is_round_member()  │
└────┬───────────────┘
     │
     │ 3. Upsert score
     ▼
┌──────────────────────────┐
│ INSERT INTO scores       │
│ ON CONFLICT (round_id,   │
│   player_id, hole_no)    │
│ DO UPDATE ...            │
└────┬─────────────────────┘
     │
     │ 4. Recalculate
     ▼
┌──────────────────────┐
│ SELECT               │
│ recalculate_round()  │
└────┬─────────────────┘
     │
     │ Inside recalculate_round():
     │
     │ a) Calculate hole results
     ▼
┌──────────────────────────────────┐
│ DELETE FROM hole_results         │
│ WHERE round_id = ...             │
│                                  │
│ INSERT INTO hole_results         │
│ SELECT                           │
│   round_id,                      │
│   player_id,                     │
│   hole_no,                       │
│   strokes,                       │
│   -- Calculate strokes_received  │
│   -- Calculate net_strokes       │
│   -- Calculate stableford_points │
│ FROM scores                      │
│ JOIN ...                         │
└────┬─────────────────────────────┘
     │
     │ b) Calculate round results
     ▼
┌──────────────────────────────────┐
│ DELETE FROM round_results        │
│ WHERE round_id = ...             │
│                                  │
│ INSERT INTO round_results        │
│ SELECT                           │
│   round_id,                      │
│   player_id,                     │
│   SUM(strokes) as gross_total,   │
│   SUM(net_strokes) as net_total, │
│   SUM(stableford_points) as ...  │
│ FROM hole_results                │
│ GROUP BY round_id, player_id     │
└────┬─────────────────────────────┘
     │
     │ c) Calculate skins (if enabled)
     ▼
┌──────────────────────────────────┐
│ DELETE FROM skins_results        │
│ WHERE round_id = ...             │
│                                  │
│ INSERT INTO skins_results        │
│ -- Find winner per hole          │
│ -- Handle ties (carryover)       │
│ -- Award skins values            │
└────┬─────────────────────────────┘
     │
     │ 5. Return snapshot
     ▼
┌──────────┐
│  Client  │
│ { success: true, snapshot: {...} }
└──────────┘
```

---

## Key Technical Decisions

### Why Supabase?

**Pros:**
- PostgreSQL (powerful, reliable)
- Built-in auth (JWT, RLS)
- Edge Functions (serverless)
- Real-time subscriptions (future)
- Generous free tier

**Cons:**
- Vendor lock-in (mitigated by open source + backup)
- Learning curve for RLS

---

### Why Edge Functions over Direct Database?

**Pros:**
- Business logic in one place
- Can call external APIs (future: weather, handicap services)
- Rate limiting / validation
- Complex calculations (WHS)
- Easier to test

**Cons:**
- Extra network hop
- Cold starts (~100-500ms)

**Decision:** Benefits outweigh costs for this use case

---

### Why Separate Result Tables?

**Alternative:** Calculate on read (views, CTEs)

**Why separate tables:**
- Pre-calculated = faster reads
- Explicit calculation timing
- Historical results preserved
- Simpler queries for frontend

**Trade-off:** Extra storage (minimal for this scale)

---

### Why PostgreSQL Functions?

**Alternative:** All calculations in Edge Functions

**Why PostgreSQL:**
- WHS calculations complex (50+ lines)
- Database has data context
- Reusable across functions
- Atomic operations
- Can be called from any tool (SQL Editor, pgAdmin)

**Decision:** Use PostgreSQL for data-heavy calculations

---

## Performance Considerations

### Database Indexes

```sql
-- High-traffic lookups
CREATE INDEX idx_rounds_created_by ON rounds(created_by);
CREATE INDEX idx_scores_round_player ON scores(round_id, player_id);
CREATE INDEX idx_hole_results_round ON hole_results(round_id);
```

### Query Optimization

**get-snapshot:** Uses JOINs with explicit SELECT
```sql
SELECT 
  rounds.*,
  courses.id, courses.name,
  course_tees.id, course_tees.tee_name, ...
FROM rounds
JOIN courses ON rounds.course_id = courses.id
JOIN course_tees ON rounds.tee_id = course_tees.id
```

**Why:** Explicit columns = no SELECT *, faster

---

### Cold Start Mitigation

**Problem:** Edge Functions ~500ms cold start

**Solutions:**
1. Keep functions warm (ping every 5 min)
2. Optimize imports (minimal deps)
3. Use connection pooling (Supabase handles)

**Current:** Acceptable for non-real-time use

---

## Security Architecture

### Defense in Depth

**Layer 1: Network**
- HTTPS only
- CORS headers

**Layer 2: Authentication**
- JWT tokens (1 hour expiry)
- Supabase Auth

**Layer 3: Authorization**
- Edge Function checks (`is_round_member`)
- RLS policies

**Layer 4: Validation**
- Input validation in functions
- Database constraints (CHECK, FK)

---

### Secrets Management

**Stored in Supabase Secrets:**
- `SERVICE_ROLE_KEY` - Never exposed to client

**Safe for client:**
- `ANON_KEY` - Respects RLS

**Rotation:** Manual via Supabase Dashboard

---

## Scalability

### Current Architecture Limits

**Free Tier:**
- 500MB database
- 2GB bandwidth/month
- Pauses after 1 week inactivity

**Estimated Capacity:**
- ~10,000 rounds
- ~100,000 scores
- ~1,000 concurrent users (with Pro)

**Bottlenecks:**
1. Database size (mitigated: archive old rounds)
2. Edge Function compute (scale: Pro plan)
3. Recalculate performance (optimize: partial recalc)

---

### Future Optimizations

**If needed:**
1. Partial recalculation (only changed holes)
2. Caching layer (Redis)
3. Read replicas (leaderboards)
4. CDN for static assets
5. WebSocket real-time (Supabase Realtime)

---

## Deployment

### Current: Manual

```bash
supabase functions deploy create-round
supabase functions deploy save-score
supabase functions deploy get-snapshot
```

### Future: CI/CD

```yaml
# .github/workflows/deploy.yml
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: supabase/setup-cli@v1
      - run: supabase functions deploy --all
```

---

## Monitoring

### Current Tools

**Supabase Dashboard:**
- Edge Function logs
- Database metrics
- API usage

**GitHub Actions:**
- Nightly schema backups
- Migration success/failure

### Future Additions

**Recommended:**
- Sentry (error tracking)
- LogDNA (log aggregation)
- Datadog (APM)

---

## Testing Strategy

### Current

**Manual Tests:**
- `test_complete_flow.sh` - End-to-end
- `create_new_round.sh` - Round creation

**Database Tests:**
- SQL test files in `database/tests/`

### Future

**Unit Tests:**
- Jest for Edge Functions
- pgTAP for PostgreSQL functions

**Integration Tests:**
- Automated API tests
- Load testing (k6)

---

## Backup & Recovery

### Automated Backups

**GitHub Actions Workflow:**
- Runs nightly at 03:00 UTC
- Exports schema via `pg_dump`
- Commits to `database/backups/`
- Retention: Git history

### Manual Backup

```bash
pg_dump -h db.PROJECT.supabase.co \
  -U postgres \
  -d postgres \
  --schema-only \
  > backup_$(date +%Y%m%d).sql
```

### Recovery

```bash
psql -h db.PROJECT.supabase.co \
  -U postgres \
  -d postgres \
  < backup_20260113.sql
```

---

## Future Architecture

### Planned Additions

**Frontend:**
- React web app
- React Native mobile app
- Admin dashboard

**Backend:**
- Tournament management
- Handicap index tracking
- Weather integration
- Push notifications

**Infrastructure:**
- CDN (Cloudflare)
- CI/CD pipeline
- Staging environment

---

**For more information, see:**
- [API Documentation](API.md)
- [Database Schema](DATABASE_SCHEMA.md)
- [Setup Guide](SETUP.md)
