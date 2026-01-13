#!/bin/bash
echo "Creating new round as test user..."

# Login
RESPONSE=$(curl -s -X POST 'https://vdfrewcuzzylordpvpai.supabase.co/auth/v1/token?grant_type=password' \
  -H 'apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZkZnJld2N1enp5bG9yZHB2cGFpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc5ODkxMDYsImV4cCI6MjA4MzU2NTEwNn0.p5TxuGVIV3s6jhVNr-8F_PW_CmeAMwyrs98derXNBWk' \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@fuldnyborg.dk","password":"TestPassword123!"}')
TOKEN=$(echo $RESPONSE | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

# Create round
curl -X POST 'https://vdfrewcuzzylordpvpai.supabase.co/functions/v1/create-round' \
  -H 'apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZkZnJld2N1enp5bG9yZHB2cGFpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc5ODkxMDYsImV4cCI6MjA4MzU2NTEwNn0.p5TxuGVIV3s6jhVNr-8F_PW_CmeAMwyrs98derXNBWk' \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"course_id":"e948845c-d84d-4dfd-bef4-a294925477f8","tee_id":"e5d7d689-1263-4c0e-a7bd-1a6e807ae38e","players":[{"player_id":"5a88889f-5dc4-4e55-a594-2c202dbe9d2c","handicap_index":5.2}],"holes_played":18,"skins_enabled":true,"skins_type":"net"}'
