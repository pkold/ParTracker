# Setup Guide

Complete guide for setting up FuldNyborg Golf Scoring App.

## Prerequisites

Before starting, ensure you have:

- **Node.js 18+** - [Download](https://nodejs.org/)
- **Supabase Account** - [Sign up](https://supabase.com)
- **Git** - [Download](https://git-scm.com/)
- **Supabase CLI** - Install via Homebrew (Mac) or npm

---

## Quick Start

### 1. Install Supabase CLI

**macOS (Homebrew):**
```bash
brew install supabase/tap/supabase
```

**Windows/Linux (npm):**
```bash
npm install -g supabase
```

**Verify installation:**
```bash
supabase --version
```

---

### 2. Clone Repository

```bash
git clone https://github.com/pkold/fuldnyborg-app.git
cd fuldnyborg-app
```

---

### 3. Create Supabase Project

1. Go to [supabase.com/dashboard](https://supabase.com/dashboard)
2. Click "New Project"
3. Choose organization and region (EU recommended for Europe)
4. Set strong database password
5. Wait for project to provision (~2 minutes)
6. Note your project reference ID (e.g., `vdfrewcuzzylordpvpai`)

---

### 4. Link Local Project to Supabase

```bash
# Login to Supabase
supabase login

# Link to your project
supabase link --project-ref YOUR_PROJECT_REF

# Example:
# supabase link --project-ref vdfrewcuzzylordpvpai
```

---

### 5. Get Database Connection Info

From Supabase Dashboard:
1. Go to **Settings** → **Database**
2. Note your connection string
3. Format: `postgresql://postgres:[password]@db.[project-ref].supabase.co:5432/postgres`

---

### 6. Run Database Migrations

**Option A: Using psql (recommended)**

```bash
# Set environment variable for password
export PGPASSWORD='your-database-password'

# Run migrations in order
psql -h db.YOUR_PROJECT_REF.supabase.co -U postgres -d postgres \
  -f database/migrations/001_core_tables.sql

psql -h db.YOUR_PROJECT_REF.supabase.co -U postgres -d postgres \
  -f database/migrations/002_team_tables.sql

psql -h db.YOUR_PROJECT_REF.supabase.co -U postgres -d postgres \
  -f database/migrations/003_score_tables.sql

psql -h db.YOUR_PROJECT_REF.supabase.co -U postgres -d postgres \
  -f database/migrations/004_rls_policies.sql

psql -h db.YOUR_PROJECT_REF.supabase.co -U postgres -d postgres \
  -f database/migrations/005_indexes.sql

psql -h db.YOUR_PROJECT_REF.supabase.co -U postgres -d postgres \
  -f database/migrations/006_core_functions.sql
```

**Option B: Using Supabase SQL Editor**

1. Go to **SQL Editor** in Supabase Dashboard
2. Click **New Query**
3. Copy contents of each migration file (in order)
4. Click **Run** for each migration

---

### 7. Run Database Functions

Apply additional functions:

```bash
# Apply all functions
for file in database/functions/*.sql; do
  psql -h db.YOUR_PROJECT_REF.supabase.co -U postgres -d postgres -f "$file"
done
```

Or manually in SQL Editor:
1. `calculate_functions.sql`
2. `recalculate_round.sql`
3. `is_round_member.sql`
4. Other functions as needed

---

### 8. Load Test Data (Optional)

```bash
psql -h db.YOUR_PROJECT_REF.supabase.co -U postgres -d postgres \
  -f database/tests/test_data_setup.sql
```

This creates:
- Sample golf course (Nyborg Golf Club)
- Tee boxes (Black, Yellow, Red)
- Test players
- Sample teams

---

### 9. Get API Keys

From Supabase Dashboard:
1. Go to **Settings** → **API**
2. Note these keys:
   - **Project URL**: `https://YOUR_PROJECT_REF.supabase.co`
   - **anon public** key (starts with `eyJ...`)
   - **service_role** key (starts with `eyJ...`)

⚠️ **IMPORTANT**: 
- **anon key**: Safe to use in frontend (respects RLS)
- **service_role key**: NEVER expose in frontend (bypasses RLS)

---

### 10. Configure Edge Functions

Update `supabase/config.toml`:

```toml
[functions.create-round]
enabled = true
verify_jwt = false
import_map = "./functions/create-round/deno.json"
entrypoint = "./functions/create-round/index.ts"

[functions.save-score]
enabled = true
verify_jwt = false
import_map = "./functions/save-score/deno.json"
entrypoint = "./functions/save-score/index.ts"

[functions.get-snapshot]
enabled = true
verify_jwt = false
import_map = "./functions/get-snapshot/deno.json"
entrypoint = "./functions/get-snapshot/index.ts"
```

**Note:** `verify_jwt = false` disables platform-level JWT verification. Functions still verify JWT internally.

---

### 11. Set Edge Function Secrets

```bash
# Get your service_role key from Supabase Dashboard
supabase secrets set SERVICE_ROLE_KEY="your-service-role-key-here"

# Example:
# supabase secrets set SERVICE_ROLE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

---

### 12. Deploy Edge Functions

```bash
# Deploy all functions
supabase functions deploy create-round
supabase functions deploy save-score
supabase functions deploy get-snapshot

# Verify deployment
supabase functions list
```

You should see:
```
┌────────────────┬──────────┬─────────────────────────────────┐
│ NAME           │ STATUS   │ ENDPOINT                        │
├────────────────┼──────────┼─────────────────────────────────┤
│ create-round   │ ACTIVE   │ /functions/v1/create-round      │
│ save-score     │ ACTIVE   │ /functions/v1/save-score        │
│ get-snapshot   │ ACTIVE   │ /functions/v1/get-snapshot      │
└────────────────┴──────────┴─────────────────────────────────┘
```

---

### 13. Create Test User

1. Go to **Authentication** → **Users** in Supabase Dashboard
2. Click **Add User** → **Create new user**
3. Enter email and password
4. Enable "Auto Confirm User"
5. Click **Create user**

---

### 14. Test the API

```bash
# Make test scripts executable
chmod +x test_complete_flow.sh
chmod +x create_new_round.sh

# Create a test round
./create_new_round.sh

# Run complete flow test
./test_complete_flow.sh
```

Expected output:
```
=== COMPLETE API FLOW TEST ===
1. Logging in...
✅ Logged in

2. Saving score (Hole 1, 4 strokes)...
{"success":true,"round_id":"...","snapshot":{...}}

3. Saving score (Hole 2, 5 strokes)...
{"success":true,"round_id":"...","snapshot":{...}}

4. Getting snapshot...
{"success":true,"round":{...},"players":[...],"scores":[...],...}

=== TEST COMPLETE ===
```

---

### 15. Setup GitHub Actions (Optional)

Enable automated backups:

1. Go to your GitHub repository **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Add these secrets:
   - `SUPABASE_ACCESS_TOKEN`: Get from [supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens)
   - `SUPABASE_PROJECT_ID`: Your project reference (e.g., `vdfrewcuzzylordpvpai`)

The `.github/workflows/backup-schema.yml` workflow will run nightly at 03:00 UTC.

---

## Troubleshooting

### "psql: command not found"

Install PostgreSQL client:

**macOS:**
```bash
brew install postgresql
```

**Ubuntu/Debian:**
```bash
sudo apt-get install postgresql-client
```

**Windows:**
Download from [postgresql.org](https://www.postgresql.org/download/windows/)

---

### "relation does not exist"

Migrations not applied correctly. Re-run migrations in order:
```bash
psql -h db.YOUR_PROJECT_REF.supabase.co -U postgres -d postgres \
  -f database/migrations/001_core_tables.sql
# ... continue with all migrations
```

---

### "Invalid JWT"

Check:
1. JWT token not expired (1 hour validity)
2. Using correct anon key in `apikey` header
3. `verify_jwt = false` in config.toml
4. SERVICE_ROLE_KEY secret is set

---

### "Not authorized to update this round"

Check:
1. User is logged in correctly
2. User created the round OR is in round_players
3. `is_round_member` function exists (run functions/*.sql)

---

### Edge Function deploy fails

Check:
1. Supabase CLI is latest version: `supabase update`
2. Logged in: `supabase login`
3. Linked to project: `supabase link --project-ref YOUR_REF`
4. No syntax errors in function code

---

### Database connection timeout

Check:
1. Using correct database password
2. Project is not paused (free tier pauses after 1 week inactivity)
3. IP allowed (Supabase allows all IPs by default)

---

## Verification Checklist

After setup, verify:

- [ ] All 6 migrations applied successfully
- [ ] All database functions created
- [ ] Test data loaded (optional)
- [ ] All 3 Edge Functions deployed
- [ ] SERVICE_ROLE_KEY secret set
- [ ] Test user created
- [ ] Test scripts run successfully
- [ ] GitHub Actions workflow configured (optional)

---

## Next Steps

- Read [API Documentation](API.md) to understand endpoints
- Read [Database Schema](DATABASE_SCHEMA.md) to understand data model
- Read [Architecture Overview](ARCHITECTURE.md) to understand system design
- Start building frontend!

---

## Support

For issues or questions:
- Check [Troubleshooting](#troubleshooting) section above
- Review [Supabase Documentation](https://supabase.com/docs)
- Contact: peter@fuldnyborg.dk

---

**Setup complete! 🎉**
