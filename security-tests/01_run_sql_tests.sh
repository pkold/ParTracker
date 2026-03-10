#!/bin/bash
# ============================================================
# ParTracker Security Test Suite — SQL/Database Tests
# Tests RLS, schema, tables, constraints via Supabase REST API
# ============================================================

SUPABASE_URL="https://vdfrewcuzzylordpvpai.supabase.co"
SRK="${SUPABASE_SERVICE_ROLE_KEY:?Set SUPABASE_SERVICE_ROLE_KEY env var before running}"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZkZnJld2N1enp5bG9yZHB2cGFpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc5ODkxMDYsImV4cCI6MjA4MzU2NTEwNn0.p5TxuGVIV3s6jhVNr-8F_PW_CmeAMwyrs98derXNBWk"

PASS=0
FAIL=0
WARN=0

pass_f() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail_f() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }
warn_f() { echo "  ⚠️  WARN: $1"; WARN=$((WARN + 1)); }

# Helper: fetch from REST API with service role key
srk_get() {
  curl -s "$SUPABASE_URL/rest/v1/$1" \
    -H "apikey: $SRK" \
    -H "Authorization: Bearer $SRK"
}

# Helper: fetch from REST API with anon key (no auth)
anon_get() {
  curl -s "$SUPABASE_URL/rest/v1/$1" \
    -H "apikey: $ANON"
}

echo "=========================================="
echo "  ParTracker SQL / Database Security Tests"
echo "=========================================="
echo ""

# ─── TEST 1: Critical tables exist (via service role) ───
echo "--- Table Existence ---"

CRITICAL_TABLES="players rounds round_players scores course_tees courses friendships friend_invite_codes tournaments tournament_players tournament_rounds tournament_standings user_consents skins_results hole_results round_results user_hidden_items home_courses contact_messages"

for table in $CRITICAL_TABLES; do
  result=$(srk_get "$table?select=count&limit=0" 2>&1)
  if echo "$result" | grep -q '"code"'; then
    fail_f "Table '$table' not accessible or missing"
  else
    pass_f "Table '$table' exists"
  fi
done

echo ""

# ─── TEST 2: RLS blocks anon access to protected tables ───
echo "--- RLS Protection (anon key, no auth token) ---"

PROTECTED_TABLES="players rounds round_players scores friendships tournaments tournament_players tournament_rounds tournament_standings user_consents skins_results hole_results round_results user_hidden_items home_courses contact_messages"

for table in $PROTECTED_TABLES; do
  result=$(anon_get "$table?limit=1" 2>&1)
  row_count=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else -1)" 2>/dev/null)
  if [ "$row_count" = "0" ]; then
    pass_f "RLS blocks anon on '$table' (0 rows)"
  elif [ "$row_count" = "-1" ]; then
    # Could be an error response — check if it's a permission error
    if echo "$result" | grep -qi "permission\|denied\|policy\|42501"; then
      pass_f "RLS blocks anon on '$table' (permission denied)"
    else
      warn_f "Unexpected response from '$table': $(echo "$result" | head -c 100)"
    fi
  else
    fail_f "RLS allows anon to read '$table' ($row_count rows returned!)"
  fi
done

echo ""

# ─── TEST 3: Courses table should be readable (public data) ───
echo "--- Public Tables ---"

courses_result=$(anon_get "courses?select=id&limit=1" 2>&1)
courses_count=$(echo "$courses_result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else -1)" 2>/dev/null)
if [ "$courses_count" != "-1" ] && [ "$courses_count" != "" ]; then
  pass_f "Courses table readable via anon (public data)"
else
  warn_f "Courses table not readable via anon — may need RLS review"
fi

course_tees_result=$(anon_get "course_tees?select=id&limit=1" 2>&1)
tees_count=$(echo "$course_tees_result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else -1)" 2>/dev/null)
if [ "$tees_count" != "-1" ] && [ "$tees_count" != "" ]; then
  pass_f "Course_tees table readable via anon (public data)"
else
  warn_f "Course_tees not readable via anon — may need RLS review"
fi

echo ""

# ─── TEST 4: Schema checks via information_schema ───
echo "--- Schema Correctness ---"

# Check column existence using service role to query information_schema-like data
# We use the tables themselves to verify columns exist

# 4a: No is_guest column on players
players_cols=$(srk_get "players?select=is_guest&limit=1" 2>&1)
if echo "$players_cols" | grep -q '"code".*"42703"'; then
  pass_f "No is_guest column on players table"
elif echo "$players_cols" | grep -q "is_guest"; then
  fail_f "is_guest column found on players table!"
else
  pass_f "No is_guest column on players table"
fi

# 4b: Gender column on players
players_gender=$(srk_get "players?select=gender&limit=1" 2>&1)
if echo "$players_gender" | grep -q '"code".*"42703"'; then
  fail_f "No gender column on players table"
else
  pass_f "Gender column exists on players table"
fi

# 4c: Tee rating columns (male/female split)
for col in slope_rating_male slope_rating_female course_rating_male course_rating_female; do
  tee_col=$(srk_get "course_tees?select=$col&limit=1" 2>&1)
  if echo "$tee_col" | grep -q '"code".*"42703"'; then
    fail_f "Missing column '$col' on course_tees"
  else
    pass_f "Column '$col' exists on course_tees"
  fi
done

# 4d: No old slope_rating column
old_slope=$(srk_get "course_tees?select=slope_rating&limit=1" 2>&1)
if echo "$old_slope" | grep -q '"code".*"42703"'; then
  pass_f "No old slope_rating column on course_tees"
else
  fail_f "Old slope_rating column still exists on course_tees!"
fi

# 4e: No old gender column on tees
old_gender=$(srk_get "course_tees?select=gender&limit=1" 2>&1)
if echo "$old_gender" | grep -q '"code".*"42703"'; then
  pass_f "No old gender column on course_tees"
else
  fail_f "Old gender column still exists on course_tees!"
fi

# 4f: visible_to_friends on rounds
vtf=$(srk_get "rounds?select=visible_to_friends&limit=1" 2>&1)
if echo "$vtf" | grep -q '"code".*"42703"'; then
  fail_f "No visible_to_friends column on rounds"
else
  pass_f "visible_to_friends column exists on rounds"
fi

# 4g: scheduled_at on rounds
sched=$(srk_get "rounds?select=scheduled_at&limit=1" 2>&1)
if echo "$sched" | grep -q '"code".*"42703"'; then
  fail_f "No scheduled_at column on rounds"
else
  pass_f "scheduled_at column exists on rounds"
fi

# 4h: tee_id on round_players (not on rounds)
rp_tee=$(srk_get "round_players?select=tee_id&limit=1" 2>&1)
if echo "$rp_tee" | grep -q '"code".*"42703"'; then
  fail_f "No tee_id column on round_players"
else
  pass_f "tee_id column exists on round_players"
fi

rounds_tee=$(srk_get "rounds?select=tee_id&limit=1" 2>&1)
if echo "$rounds_tee" | grep -q '"code".*"42703"'; then
  pass_f "No tee_id on rounds table (correct — tee is per-player)"
else
  warn_f "tee_id found on rounds table — should only be on round_players"
fi

# 4i: tournament_standings has total_points
ts_tp=$(srk_get "tournament_standings?select=total_points&limit=1" 2>&1)
if echo "$ts_tp" | grep -q '"code".*"42703"'; then
  fail_f "No total_points column on tournament_standings"
else
  pass_f "total_points column exists on tournament_standings"
fi

# 4j: home_courses has user_id and course_id
for col in user_id course_id; do
  hc_col=$(srk_get "home_courses?select=$col&limit=1" 2>&1)
  if echo "$hc_col" | grep -q '"code".*"42703"'; then
    fail_f "Missing column '$col' on home_courses"
  else
    pass_f "Column '$col' exists on home_courses"
  fi
done

echo ""

# ─── TEST 5: Foreign key / relationship checks ───
echo "--- Relationship Checks ---"

# round_players references rounds (test via embedded select)
rp_fk=$(srk_get "round_players?select=round_id,rounds(id)&limit=1" 2>&1)
if echo "$rp_fk" | grep -q '"code"'; then
  warn_f "Could not verify FK: round_players -> rounds"
else
  pass_f "FK relationship: round_players -> rounds"
fi

# scores references rounds
sc_fk=$(srk_get "scores?select=round_id,rounds(id)&limit=1" 2>&1)
if echo "$sc_fk" | grep -q '"code"'; then
  warn_f "Could not verify FK: scores -> rounds"
else
  pass_f "FK relationship: scores -> rounds"
fi

# round_players references course_tees
rp_tee_fk=$(srk_get "round_players?select=tee_id,course_tees(id)&limit=1" 2>&1)
if echo "$rp_tee_fk" | grep -q '"code"'; then
  warn_f "Could not verify FK: round_players -> course_tees"
else
  pass_f "FK relationship: round_players -> course_tees"
fi

# tournament_rounds references tournaments
tr_fk=$(srk_get "tournament_rounds?select=tournament_id,tournaments(id)&limit=1" 2>&1)
if echo "$tr_fk" | grep -q '"code"'; then
  warn_f "Could not verify FK: tournament_rounds -> tournaments"
else
  pass_f "FK relationship: tournament_rounds -> tournaments"
fi

echo ""

# ─── TEST 6: auth.users not exposed in public ───
echo "--- Security Checks ---"

users_result=$(srk_get "users?select=id&limit=1" 2>&1)
if echo "$users_result" | grep -q '"code"'; then
  pass_f "No 'users' table exposed in public schema"
else
  fail_f "auth.users exposed in public schema!"
fi

# Service role should have full access to players
srk_players=$(srk_get "players?select=id&limit=1" 2>&1)
srk_count=$(echo "$srk_players" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else -1)" 2>/dev/null)
if [ "$srk_count" != "-1" ]; then
  pass_f "Service role can access players (as expected)"
else
  fail_f "Service role cannot access players!"
fi

echo ""

# ─── SUMMARY ───
echo "=========================================="
echo "  RESULTS: $PASS passed, $FAIL failed, $WARN warnings"
echo "=========================================="
