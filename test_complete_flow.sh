#!/bin/bash
echo "=== COMPLETE API FLOW TEST ==="
echo ""

# Login
echo "1. Logging in..."
RESPONSE=$(curl -s -X POST 'https://vdfrewcuzzylordpvpai.supabase.co/auth/v1/token?grant_type=password' \
  -H 'apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZkZnJld2N1enp5bG9yZHB2cGFpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc5ODkxMDYsImV4cCI6MjA4MzU2NTEwNn0.p5TxuGVIV3s6jhVNr-8F_PW_CmeAMwyrs98derXNBWk' \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@fuldnyborg.dk","password":"TestPassword123!"}')
TOKEN=$(echo $RESPONSE | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
echo "✅ Logged in"
echo ""

ROUND_ID="439c45bb-cfdb-4269-8129-662f7b1a8786"
PLAYER1="5a88889f-5dc4-4e55-a594-2c202dbe9d2c"

echo "2. Saving score (Hole 1, 4 strokes)..."
curl -s -X POST 'https://vdfrewcuzzylordpvpai.supabase.co/functions/v1/save-score' \
  -H 'apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZkZnJld2N1enp5bG9yZHB2cGFpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc5ODkxMDYsImV4cCI6MjA4MzU2NTEwNn0.p5TxuGVIV3s6jhVNr-8F_PW_CmeAMwyrs98derXNBWk' \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"round_id\":\"$ROUND_ID\",\"player_id\":\"$PLAYER1\",\"hole_no\":1,\"strokes\":4}"
echo ""
echo ""

echo "3. Saving score (Hole 2, 5 strokes)..."
curl -s -X POST 'https://vdfrewcuzzylordpvpai.supabase.co/functions/v1/save-score' \
  -H 'apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZkZnJld2N1enp5bG9yZHB2cGFpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc5ODkxMDYsImV4cCI6MjA4MzU2NTEwNn0.p5TxuGVIV3s6jhVNr-8F_PW_CmeAMwyrs98derXNBWk' \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"round_id\":\"$ROUND_ID\",\"player_id\":\"$PLAYER1\",\"hole_no\":2,\"strokes\":5}"
echo ""
echo ""

echo "4. Getting snapshot..."
curl -s -X GET "https://vdfrewcuzzylordpvpai.supabase.co/functions/v1/get-snapshot?round_id=$ROUND_ID" \
  -H 'apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZkZnJld2N1enp5bG9yZHB2cGFpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc5ODkxMDYsImV4cCI6MjA4MzU2NTEwNn0.p5TxuGVIV3s6jhVNr-8F_PW_CmeAMwyrs98derXNBWk' \
  -H "Authorization: Bearer $TOKEN"
echo ""
echo ""
echo "=== TEST COMPLETE ==="
