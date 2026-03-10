#!/bin/bash
# ============================================================
# ParTracker Security Test Suite — Codebase Scanner
# Scans frontend and backend for security issues
# ============================================================

set -uo pipefail

MOBILE_DIR="$HOME/projects/fuldnyborg-mobile"
BACKEND_DIR="$HOME/projects/fuldnyborg-app"

PASS=0
FAIL=0
WARN=0

pass() { echo "  PASS: $1"; ((PASS++)); }
fail() { echo "  FAIL: $1"; ((FAIL++)); }
warn() { echo "  WARN: $1"; ((WARN++)); }

echo "=========================================="
echo "  ParTracker Codebase Security Scanner"
echo "=========================================="
echo ""

# ----------------------------------------------------------
echo "--- Secret Exposure Checks ---"
# ----------------------------------------------------------

# 1. No SERVICE_ROLE_KEY in frontend source
if grep -rq "SERVICE_ROLE_KEY\|service_role" "$MOBILE_DIR/src/" "$MOBILE_DIR/app/" "$MOBILE_DIR/lib/" 2>/dev/null; then
  fail "SERVICE_ROLE_KEY found in frontend code!"
  grep -rn "SERVICE_ROLE_KEY\|service_role" "$MOBILE_DIR/src/" "$MOBILE_DIR/app/" "$MOBILE_DIR/lib/" 2>/dev/null | head -3
else
  pass "No SERVICE_ROLE_KEY in frontend source"
fi

# 2. No hardcoded JWT tokens in src/ (exclude the anon key in supabase.ts which is expected)
JWTS=$(grep -rn "eyJ[A-Za-z0-9_-]*\\.eyJ[A-Za-z0-9_-]*\\." "$MOBILE_DIR/src/" "$MOBILE_DIR/app/" 2>/dev/null | grep -v "node_modules" || true)
if [[ -z "$JWTS" ]]; then
  pass "No hardcoded JWT tokens in src/ or app/"
else
  warn "JWT-like strings found in source (verify these are expected):"
  echo "$JWTS" | head -3
fi

# Check lib/supabase.ts separately (anon key is expected there)
OTHER_JWTS=$(grep -rn "eyJ[A-Za-z0-9_-]*\\.eyJ[A-Za-z0-9_-]*\\." "$MOBILE_DIR/lib/" 2>/dev/null | grep -v "supabaseAnonKey" | grep -v "node_modules" || true)
if [[ -z "$OTHER_JWTS" ]]; then
  pass "No unexpected JWT tokens in lib/ (anon key in supabase.ts is expected)"
else
  warn "Unexpected JWT-like strings in lib/:"
  echo "$OTHER_JWTS" | head -3
fi

# 3. .env in .gitignore
if [[ -f "$MOBILE_DIR/.gitignore" ]] && grep -q "\.env" "$MOBILE_DIR/.gitignore"; then
  pass ".env is in frontend .gitignore"
else
  fail ".env NOT in frontend .gitignore!"
fi

if [[ -f "$BACKEND_DIR/.gitignore" ]] && grep -q "\.env" "$BACKEND_DIR/.gitignore"; then
  pass ".env is in backend .gitignore"
else
  warn ".env may not be in backend .gitignore (check manually)"
fi

# 4. No http:// URLs (except localhost)
HTTP_URLS=$(grep -rn "http://" "$MOBILE_DIR/src/" "$MOBILE_DIR/app/" "$MOBILE_DIR/lib/" 2>/dev/null \
  | grep -v "localhost\|127\.0\.0\.1\|node_modules\|\.map$" || true)
if [[ -z "$HTTP_URLS" ]]; then
  pass "No insecure http:// URLs in frontend (excluding localhost)"
else
  fail "Insecure http:// URLs found:"
  echo "$HTTP_URLS" | head -5
fi

# 8. No secrets in app.json or eas.json
if grep -qi "secret\|password\|service.role\|private.key" "$MOBILE_DIR/app.json" 2>/dev/null; then
  fail "Potential secrets in app.json!"
else
  pass "No secrets detected in app.json"
fi

if [[ -f "$MOBILE_DIR/eas.json" ]]; then
  if grep -qi "secret\|password\|service.role\|private.key" "$MOBILE_DIR/eas.json" 2>/dev/null; then
    fail "Potential secrets in eas.json!"
  else
    pass "No secrets detected in eas.json"
  fi
else
  pass "No eas.json file (nothing to check)"
fi
echo ""

# ----------------------------------------------------------
echo "--- Code Pattern Checks ---"
# ----------------------------------------------------------

# 5. No is_guest references
IS_GUEST=$(grep -rn "is_guest" "$MOBILE_DIR/src/" "$MOBILE_DIR/app/" "$MOBILE_DIR/lib/" \
  "$BACKEND_DIR/supabase/functions/" "$BACKEND_DIR/database/" 2>/dev/null \
  | grep -v "node_modules\|\.map$" || true)
if [[ -z "$IS_GUEST" ]]; then
  pass "No is_guest references in codebase"
else
  # Check if it's just in the Player interface type definition (which is acceptable)
  REAL_USAGE=$(echo "$IS_GUEST" | grep -v "is_guest\?:" | grep -v "interface\|type " || true)
  if [[ -z "$REAL_USAGE" ]]; then
    warn "is_guest found only in type definitions (acceptable but could be cleaned up)"
  else
    fail "is_guest references found in code logic:"
    echo "$REAL_USAGE" | head -5
  fi
fi

# 6. No tee_color in .eq() calls
TEE_COLOR=$(grep -rn "\.eq.*tee_color\|tee_color.*\.eq\|eq('tee_color\|eq(\"tee_color" \
  "$MOBILE_DIR/src/" "$MOBILE_DIR/app/" "$MOBILE_DIR/lib/" 2>/dev/null \
  | grep -v "node_modules" || true)
if [[ -z "$TEE_COLOR" ]]; then
  pass "No tee_color in .eq() calls"
else
  warn "tee_color used in .eq() calls (should use tee id instead):"
  echo "$TEE_COLOR" | head -3
fi

# 7. Check token storage approach
if grep -rq "expo-secure-store\|SecureStore" "$MOBILE_DIR/src/" "$MOBILE_DIR/app/" "$MOBILE_DIR/lib/" "$MOBILE_DIR/package.json" 2>/dev/null; then
  pass "expo-secure-store referenced in project"
else
  # Supabase JS SDK with AsyncStorage is standard for Expo — not a hard fail
  if grep -rq "AsyncStorage" "$MOBILE_DIR/lib/supabase.ts" 2>/dev/null; then
    warn "Using AsyncStorage for Supabase auth (standard for Expo, but SecureStore is more secure)"
  else
    warn "Could not determine token storage method"
  fi
fi
echo ""

# ----------------------------------------------------------
echo "--- Edge Function Security ---"
# ----------------------------------------------------------

FUNCTIONS_DIR="$BACKEND_DIR/supabase/functions"

if [[ -d "$FUNCTIONS_DIR" ]]; then
  for fn_dir in "$FUNCTIONS_DIR"/*/; do
    fn_name=$(basename "$fn_dir")
    fn_file="$fn_dir/index.ts"

    if [[ ! -f "$fn_file" ]]; then
      continue
    fi

    # 9. Auth verification
    if grep -q "getUser\|auth\.getUser\|auth\.getSession" "$fn_file"; then
      pass "$fn_name: verifies authentication"
    else
      fail "$fn_name: does NOT verify authentication!"
    fi

    # 10. CORS headers
    if grep -q "Access-Control" "$fn_file"; then
      pass "$fn_name: has CORS headers"
    else
      warn "$fn_name: no CORS headers found"
    fi
  done
else
  warn "Edge functions directory not found at $FUNCTIONS_DIR"
fi
echo ""

# ----------------------------------------------------------
echo "--- Additional Checks ---"
# ----------------------------------------------------------

# 11. SQL migrations in git
MIGRATION_COMMITS=$(cd "$BACKEND_DIR" && git log --oneline --all -- "database/migrations/" "supabase/migrations/" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$MIGRATION_COMMITS" -gt 0 ]]; then
  pass "SQL migrations committed to git ($MIGRATION_COMMITS commits)"
else
  warn "No migration commits found in git history"
fi

# 12. friend-operations verifies auth before trusting user IDs
FO_FILE="$FUNCTIONS_DIR/friend-operations/index.ts"
if [[ -f "$FO_FILE" ]]; then
  # Check that it gets user from auth, not from request body
  if grep -q "getUser" "$FO_FILE" && ! grep -q "body.user_id\|params.user_id" "$FO_FILE"; then
    pass "friend-operations derives user_id from auth (not request body)"
  else
    fail "friend-operations may trust user_id from request body!"
  fi
else
  warn "friend-operations/index.ts not found"
fi

# Check for SQL injection patterns in edge functions
SQL_INJECTION=$(grep -rn "\\$\{.*\}" "$FUNCTIONS_DIR"/*/index.ts 2>/dev/null \
  | grep -i "select\|insert\|update\|delete\|from\|where" \
  | grep -v "node_modules" || true)
if [[ -z "$SQL_INJECTION" ]]; then
  pass "No obvious SQL injection patterns in edge functions"
else
  warn "Template literals in SQL-like contexts found (verify parameterized):"
  echo "$SQL_INJECTION" | head -3
fi

# Check for console.log with sensitive data patterns
SENSITIVE_LOGS=$(grep -rn "console\.log.*password\|console\.log.*token\|console\.log.*secret" \
  "$MOBILE_DIR/src/" "$MOBILE_DIR/app/" "$MOBILE_DIR/lib/" \
  "$FUNCTIONS_DIR" 2>/dev/null \
  | grep -v "node_modules" || true)
if [[ -z "$SENSITIVE_LOGS" ]]; then
  pass "No sensitive data in console.log calls"
else
  warn "Potentially sensitive console.log found:"
  echo "$SENSITIVE_LOGS" | head -3
fi
echo ""

# ----------------------------------------------------------
echo "=========================================="
printf "  RESULTS: %d passed, %d failed, %d warnings\n" "$PASS" "$FAIL" "$WARN"
echo "=========================================="
