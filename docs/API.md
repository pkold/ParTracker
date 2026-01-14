# API Documentation

Complete reference for FuldNyborg Golf Scoring API.

## Base URL

```
https://vdfrewcuzzylordpvpai.supabase.co/functions/v1
```

## Authentication

All endpoints require JWT authentication via Supabase Auth.

**Headers required:**
```
Authorization: Bearer YOUR_JWT_TOKEN
apikey: YOUR_SUPABASE_ANON_KEY
Content-Type: application/json
```

**Getting a JWT token:**
```bash
curl -X POST 'https://vdfrewcuzzylordpvpai.supabase.co/auth/v1/token?grant_type=password' \
  -H 'apikey: YOUR_ANON_KEY' \
  -H 'Content-Type: application/json' \
  -d '{"email":"user@example.com","password":"password"}'
```

---

## Endpoints

### POST /create-round

Creates a new golf round with players and calculates playing handicaps.

**Request Body:**
```json
{
  "course_id": "uuid",           // Required: Golf course ID
  "tee_id": "uuid",              // Required: Tee box ID
  "players": [                   // Required: Array of players (1-4)
    {
      "player_id": "uuid",       // Required: Player ID
      "handicap_index": 5.2,     // Required: Current handicap index
      "team_id": "uuid"          // Optional: Team ID for team modes
    }
  ],
  "holes_played": 18,            // Optional: 9 or 18 (default: 18)
  "start_hole": 1,               // Optional: 1-18 (default: 1)
  "handicap_allowance": 1.0,     // Optional: 0.0-1.0 (default: 1.0)
  "scoring_format": "stableford",// Optional: stableford, stroke, match (default: stableford)
  "team_mode": "individual",     // Optional: individual, bestball (default: individual)
  "team_scoring_mode": "aggregate", // Optional: aggregate, bestball (default: aggregate)
  "skins_enabled": true,         // Optional: Enable skins (default: false)
  "skins_type": "net",           // Optional: net, gross (default: net)
  "skins_rollover": true         // Optional: Enable carryover (default: true)
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "round_id": "uuid",
  "round": {
    "id": "uuid",
    "course_id": "uuid",
    "tee_id": "uuid",
    "created_by": "uuid",
    "created_at": "2026-01-13T16:00:00Z",
    "holes_played": 18,
    "scoring_format": "stableford",
    "team_mode": "individual",
    "skins_enabled": true,
    "status": "active"
  },
  "players": [
    {
      "round_id": "uuid",
      "player_id": "uuid",
      "playing_hcp": 3,          // Calculated playing handicap
      "team_id": null,
      "role": "player"
    }
  ],
  "snapshot": {
    "round_id": "uuid",
    "holes_calculated": 0,
    "skins_calculated": 0,
    "players_calculated": 0
  }
}
```

**Error Response (400 Bad Request):**
```json
{
  "success": false,
  "error": "Missing required fields: course_id, tee_id, players"
}
```

**WHS Playing Handicap Calculation:**
```
Playing HCP = (Handicap Index × Slope / 113 + (Course Rating - Par)) × Allowance
For 9 holes: divide by 2
```

---

### POST /save-score

Saves a score for a player on a specific hole and triggers automatic recalculation.

**Request Body:**
```json
{
  "round_id": "uuid",            // Required: Round ID
  "player_id": "uuid",           // Required: Player ID
  "hole_no": 1,                  // Required: 1-18
  "strokes": 4,                  // Required: Number of strokes
  "client_event_id": "uuid"      // Optional: For offline sync idempotency
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "round_id": "uuid",
  "snapshot": {
    "round_id": "uuid",
    "holes_calculated": 5,       // Holes with complete scores
    "skins_calculated": 5,       // Holes with skins calculated
    "teams_calculated": 0,       // Teams with results
    "players_calculated": 4      // Players with results
  }
}
```

**Error Response (400 Bad Request):**
```json
{
  "success": false,
  "error": "Missing required fields: round_id, player_id, hole_no, strokes"
}
```

**Error Response (401 Unauthorized):**
```json
{
  "success": false,
  "error": "Not authorized to update this round"
}
```

**Notes:**
- Uses UPSERT logic: creates new score or updates existing
- Automatically triggers `recalculate_round()` function
- `client_event_id` ensures idempotency for offline sync
- Authorization check via `is_round_member()`

---

### GET /get-snapshot

Retrieves complete round status including all scores, results, and calculations.

**Query Parameters:**
```
round_id=uuid    // Required: Round ID
```

**Response (200 OK):**
```json
{
  "success": true,
  "round": {
    "id": "uuid",
    "course_id": "uuid",
    "tee_id": "uuid",
    "created_by": "uuid",
    "created_at": "2026-01-13T16:00:00Z",
    "holes_played": 18,
    "scoring_format": "stableford",
    "team_mode": "individual",
    "skins_enabled": true,
    "status": "active",
    "course": {
      "id": "uuid",
      "name": "Nyborg Golf Club"
    },
    "tee": {
      "id": "uuid",
      "tee_name": "Yellow",
      "tee_color": "yellow",
      "par": 72,
      "slope_rating": 113,
      "course_rating": 69.5,
      "holes": [
        {
          "hole_no": 1,
          "par": 4,
          "stroke_index": 11
        }
        // ... all holes
      ]
    }
  },
  "players": [
    {
      "round_id": "uuid",
      "player_id": "uuid",
      "playing_hcp": 3,
      "team_id": null,
      "role": "player",
      "player": {
        "id": "uuid",
        "display_name": "Peter Hansen",
        "email": "peter@example.com"
      }
    }
  ],
  "scores": [
    {
      "round_id": "uuid",
      "player_id": "uuid",
      "hole_no": 1,
      "strokes": 4,
      "updated_at": "2026-01-13T16:05:00Z",
      "updated_by": "uuid"
    }
  ],
  "hole_results": [
    {
      "round_id": "uuid",
      "player_id": "uuid",
      "hole_no": 1,
      "strokes": 4,
      "par": 4,
      "stroke_index": 11,
      "strokes_received": 0,
      "net_strokes": 4,
      "stableford_points": 2
    }
  ],
  "round_results": [
    {
      "round_id": "uuid",
      "player_id": "uuid",
      "gross_total": 72,
      "net_total": 69,
      "stableford_total": 36
    }
  ],
  "team_results": null,  // or array if team mode
  "skins_results": [
    {
      "round_id": "uuid",
      "hole_no": 1,
      "winner_player_id": "uuid",
      "winning_score": 3,
      "carryover_value": 0,
      "skin_awarded_value": 1,
      "winner_player": {
        "id": "uuid",
        "display_name": "Peter Hansen"
      }
    }
  ]
}
```

**Error Response (401 Unauthorized):**
```json
{
  "success": false,
  "error": "Not authorized to view this round"
}
```

**Notes:**
- Returns complete round state in single call
- Optimized for "follower mode" (live leaderboard updates)
- Authorization check via `is_round_member()`
- Includes nested course/tee/player information

---

## Common Patterns

### Creating and Playing a Round

```javascript
// 1. Create round
const createResponse = await fetch('/functions/v1/create-round', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${jwt}`,
    'apikey': anonKey,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    course_id: courseId,
    tee_id: teeId,
    players: [{ player_id: playerId, handicap_index: 5.2 }],
    skins_enabled: true
  })
});

const { round_id } = await createResponse.json();

// 2. Save scores
for (let hole = 1; hole <= 18; hole++) {
  await fetch('/functions/v1/save-score', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${jwt}`,
      'apikey': anonKey,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      round_id,
      player_id: playerId,
      hole_no: hole,
      strokes: strokes[hole]
    })
  });
}

// 3. Get final results
const snapshotResponse = await fetch(
  `/functions/v1/get-snapshot?round_id=${round_id}`,
  {
    headers: {
      'Authorization': `Bearer ${jwt}`,
      'apikey': anonKey
    }
  }
);

const results = await snapshotResponse.json();
```

### Live Leaderboard Updates

```javascript
// Poll every 10 seconds for updates
setInterval(async () => {
  const response = await fetch(
    `/functions/v1/get-snapshot?round_id=${round_id}`,
    {
      headers: {
        'Authorization': `Bearer ${jwt}`,
        'apikey': anonKey
      }
    }
  );
  
  const snapshot = await response.json();
  updateLeaderboard(snapshot.round_results);
  updateSkins(snapshot.skins_results);
}, 10000);
```

### Offline Sync with Idempotency

```javascript
// Generate unique event ID for each score
const clientEventId = crypto.randomUUID();

// Save to local storage first
localStorage.setItem(`score_${hole}`, JSON.stringify({
  round_id,
  player_id,
  hole_no: hole,
  strokes,
  client_event_id: clientEventId
}));

// Sync when online
if (navigator.onLine) {
  await fetch('/functions/v1/save-score', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${jwt}`,
      'apikey': anonKey,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      round_id,
      player_id,
      hole_no: hole,
      strokes,
      client_event_id: clientEventId  // Ensures no duplicates
    })
  });
}
```

---

## Rate Limits

- Standard Supabase Edge Function rate limits apply
- Recommend max 10 requests/second per user
- Use debouncing for rapid score input

## Error Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 400 | Bad Request - Invalid parameters |
| 401 | Unauthorized - Invalid JWT or not authorized |
| 404 | Not Found - Round/player not found |
| 500 | Internal Server Error |

## Testing

Use the provided test scripts:

```bash
# End-to-end test
./test_complete_flow.sh

# Create test round
./create_new_round.sh
```

---

**For more information, see:**
- [Database Schema](DATABASE_SCHEMA.md)
- [Setup Guide](SETUP.md)
- [Architecture Overview](ARCHITECTURE.md)
