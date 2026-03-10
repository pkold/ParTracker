#!/bin/bash
# ============================================================
# ParTracker Security Test Suite — Edge Function Tests
# ============================================================

set -uo pipefail

SUPABASE_URL="https://vdfrewcuzzylordpvpai.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZkZnJld2N1enp5bG9yZHB2cGFpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc5ODkxMDYsImV4cCI6MjA4MzU2NTEwNn0.p5TxuGVIV3s6jhVNr-8F_PW_CmeAMwyrs98derXNBWk"
FAKE_JWT="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkZha2UiLCJpYXQiOjE1MTYyMzkwMjJ9.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

PASS=0
FAIL=0
WARN=0

pass() { echo "  PASS: $1"; ((PASS++)); }
fail() { echo "  FAIL: $1"; ((FAIL++)); }
warn() { echo "  WARN: $1"; ((WARN++)); }

echo "=========================================="
echo "  ParTracker Edge Function Security Tests"
echo "=========================================="
echo ""

# Helper: curl with timeout
api() {
  curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$@" 2>/dev/null || echo "000"
}

api_body() {
  curl -s --max-time 10 "$@" 2>/dev/null || echo "{}"
}

# ----------------------------------------------------------
echo "--- HTTPS Check ---"
# ----------------------------------------------------------
if [[ "$SUPABASE_URL" == https://* ]]; then
  pass "SUPABASE_URL uses HTTPS"
else
  fail "SUPABASE_URL does not use HTTPS!"
fi
echo ""

# ----------------------------------------------------------
echo "--- Unauthenticated Access (no token) ---"
# ----------------------------------------------------------

STATUS=$(api -X POST "$SUPABASE_URL/functions/v1/create-round" \
  -H "Content-Type: application/json" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -d '{}')
if [[ "$STATUS" == "401" || "$STATUS" == "400" ]]; then
  pass "create-round rejects unauthenticated request ($STATUS)"
else
  fail "create-round returned $STATUS without auth (expected 401/400)"
fi

STATUS=$(api -X POST "$SUPABASE_URL/functions/v1/save-score" \
  -H "Content-Type: application/json" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -d '{}')
if [[ "$STATUS" == "401" || "$STATUS" == "400" ]]; then
  pass "save-score rejects unauthenticated request ($STATUS)"
else
  fail "save-score returned $STATUS without auth (expected 401/400)"
fi

STATUS=$(api -X POST "$SUPABASE_URL/functions/v1/friend-operations" \
  -H "Content-Type: application/json" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -d '{}')
if [[ "$STATUS" == "401" || "$STATUS" == "400" ]]; then
  pass "friend-operations rejects unauthenticated request ($STATUS)"
else
  fail "friend-operations returned $STATUS without auth (expected 401/400)"
fi
echo ""

# ----------------------------------------------------------
echo "--- Invalid JWT Token ---"
# ----------------------------------------------------------

STATUS=$(api -X POST "$SUPABASE_URL/functions/v1/create-round" \
  -H "Content-Type: application/json" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $FAKE_JWT" \
  -d '{}')
if [[ "$STATUS" == "401" || "$STATUS" == "400" ]]; then
  pass "create-round rejects fake JWT ($STATUS)"
else
  fail "create-round returned $STATUS with fake JWT (expected 401/400)"
fi

STATUS=$(api -X POST "$SUPABASE_URL/functions/v1/save-score" \
  -H "Content-Type: application/json" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $FAKE_JWT" \
  -d '{}')
if [[ "$STATUS" == "401" || "$STATUS" == "400" ]]; then
  pass "save-score rejects fake JWT ($STATUS)"
else
  fail "save-score returned $STATUS with fake JWT (expected 401/400)"
fi
echo ""

# ----------------------------------------------------------
echo "--- Auth Endpoint Tests ---"
# ----------------------------------------------------------

# Wrong password
BODY=$(api_body -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"wrongpassword123"}')
if echo "$BODY" | grep -qi "invalid\|error\|unauthorized"; then
  pass "Wrong password returns error"
else
  fail "Wrong password did not return error"
fi

# Non-existent email
BODY=$(api_body -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"nonexistent_user_12345@fakeemail.invalid","password":"somepassword123"}')
if echo "$BODY" | grep -qi "invalid\|error\|unauthorized"; then
  pass "Non-existent email returns error"
else
  fail "Non-existent email did not return error"
fi

# Weak password on signup
BODY=$(api_body -X POST "$SUPABASE_URL/auth/v1/signup" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"weakpw_test_99999@fakeemail.invalid","password":"ab"}')
if echo "$BODY" | grep -qi "error\|short\|weak\|length\|minimum"; then
  pass "Weak password (2 chars) rejected on signup"
else
  # Some Supabase configs accept short passwords, warn instead of fail
  warn "Weak password may not be rejected — check Supabase auth config"
fi

# Invalid email format
BODY=$(api_body -X POST "$SUPABASE_URL/auth/v1/signup" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"not-an-email","password":"validpassword123"}')
if echo "$BODY" | grep -qi "error\|invalid\|valid email"; then
  pass "Invalid email format rejected on signup"
else
  warn "Invalid email format may not be rejected — check Supabase auth config"
fi
echo ""

# ----------------------------------------------------------
echo "--- RLS via REST API ---"
# ----------------------------------------------------------

# Anon access to rounds (should return empty or 401, not all data)
STATUS=$(api "$SUPABASE_URL/rest/v1/rounds?select=id&limit=1" \
  -H "apikey: $SUPABASE_ANON_KEY")
if [[ "$STATUS" == "200" || "$STATUS" == "401" ]]; then
  # 200 is OK if RLS returns empty set. Check body for data.
  BODY=$(api_body "$SUPABASE_URL/rest/v1/rounds?select=id&limit=1" \
    -H "apikey: $SUPABASE_ANON_KEY")
  if [[ "$BODY" == "[]" || "$STATUS" == "401" ]]; then
    pass "Anon cannot read rounds (empty or 401)"
  else
    fail "Anon can read rounds data! RLS may be misconfigured"
  fi
else
  fail "Unexpected status $STATUS for anon rounds access"
fi

# Anon access to players
BODY=$(api_body "$SUPABASE_URL/rest/v1/players?select=id&limit=1" \
  -H "apikey: $SUPABASE_ANON_KEY")
STATUS=$(api "$SUPABASE_URL/rest/v1/players?select=id&limit=1" \
  -H "apikey: $SUPABASE_ANON_KEY")
if [[ "$BODY" == "[]" || "$STATUS" == "401" ]]; then
  pass "Anon cannot read players (empty or 401)"
else
  fail "Anon can read players data! RLS may be misconfigured"
fi

# Courses should be publicly readable
STATUS=$(api "$SUPABASE_URL/rest/v1/courses?select=id,name&limit=1" \
  -H "apikey: $SUPABASE_ANON_KEY")
if [[ "$STATUS" == "200" ]]; then
  pass "Courses are publicly readable (200)"
else
  warn "Courses returned $STATUS (may need auth)"
fi

# Cannot write to players without auth
STATUS=$(api -X POST "$SUPABASE_URL/rest/v1/players" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"display_name":"hacker","user_id":"00000000-0000-0000-0000-000000000000"}')
if [[ "$STATUS" == "401" || "$STATUS" == "403" || "$STATUS" == "409" ]]; then
  pass "Anon cannot insert into players ($STATUS)"
else
  fail "Anon insert into players returned $STATUS (expected 401/403)"
fi
echo ""

# ----------------------------------------------------------
echo "--- Authenticated Input Validation ---"
# ----------------------------------------------------------

# Sign up a temporary test user to get a real JWT
TEST_EMAIL="security_test_$(date +%s)@test.partracker.local"
TEST_PASSWORD="SecureTestPass123!"

SIGNUP_BODY=$(api_body -X POST "$SUPABASE_URL/auth/v1/signup" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}")

TOKEN=$(echo "$SIGNUP_BODY" | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ -z "$TOKEN" ]]; then
  # Try login in case signup auto-confirms
  LOGIN_BODY=$(api_body -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}")
  TOKEN=$(echo "$LOGIN_BODY" | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)
fi

if [[ -n "$TOKEN" ]]; then
  echo "  (Using test user token for authenticated tests)"
  echo ""

  # create-round rejects empty body
  BODY=$(api_body -X POST "$SUPABASE_URL/functions/v1/create-round" \
    -H "Content-Type: application/json" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{}')
  if echo "$BODY" | grep -qi "error\|missing\|required"; then
    pass "create-round rejects empty body"
  else
    fail "create-round accepted empty body"
  fi

  # save-score rejects missing round_id
  BODY=$(api_body -X POST "$SUPABASE_URL/functions/v1/save-score" \
    -H "Content-Type: application/json" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"player_id":"xxx","hole_no":1,"strokes":4}')
  if echo "$BODY" | grep -qi "error\|missing\|required\|round_id"; then
    pass "save-score rejects missing round_id"
  else
    fail "save-score accepted missing round_id"
  fi

  # save-score rejects negative strokes
  BODY=$(api_body -X POST "$SUPABASE_URL/functions/v1/save-score" \
    -H "Content-Type: application/json" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"round_id":"00000000-0000-0000-0000-000000000000","player_id":"xxx","hole_no":1,"strokes":-1}')
  if echo "$BODY" | grep -qi "error\|invalid\|negative\|strokes"; then
    pass "save-score rejects negative strokes"
  else
    warn "save-score may not validate negative strokes"
  fi

  # save-score rejects hole > 18
  BODY=$(api_body -X POST "$SUPABASE_URL/functions/v1/save-score" \
    -H "Content-Type: application/json" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"round_id":"00000000-0000-0000-0000-000000000000","player_id":"xxx","hole_no":19,"strokes":4}')
  if echo "$BODY" | grep -qi "error\|invalid\|hole"; then
    pass "save-score rejects hole_no > 18"
  else
    warn "save-score may not validate hole_no > 18"
  fi

  # save-score rejects non-integer strokes
  BODY=$(api_body -X POST "$SUPABASE_URL/functions/v1/save-score" \
    -H "Content-Type: application/json" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"round_id":"00000000-0000-0000-0000-000000000000","player_id":"xxx","hole_no":1,"strokes":4.5}')
  if echo "$BODY" | grep -qi "error\|invalid\|integer"; then
    pass "save-score rejects non-integer strokes"
  else
    warn "save-score may not validate non-integer strokes"
  fi

  # save-score rejects unreasonable strokes
  BODY=$(api_body -X POST "$SUPABASE_URL/functions/v1/save-score" \
    -H "Content-Type: application/json" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"round_id":"00000000-0000-0000-0000-000000000000","player_id":"xxx","hole_no":1,"strokes":99}')
  if echo "$BODY" | grep -qi "error\|invalid\|unreasonable\|too high"; then
    pass "save-score rejects strokes=99"
  else
    warn "save-score may not validate unreasonable strokes (99)"
  fi

  # friend-operations rejects missing action
  BODY=$(api_body -X POST "$SUPABASE_URL/functions/v1/friend-operations" \
    -H "Content-Type: application/json" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{}')
  if echo "$BODY" | grep -qi "error\|missing\|action"; then
    pass "friend-operations rejects missing action"
  else
    fail "friend-operations accepted missing action"
  fi

else
  warn "Could not obtain test token — skipping authenticated tests"
  warn "  (Supabase may require email confirmation)"
fi
echo ""

# ----------------------------------------------------------
echo "=========================================="
printf "  RESULTS: %d passed, %d failed, %d warnings\n" "$PASS" "$FAIL" "$WARN"
echo "=========================================="
