# GitHub Actions Setup Guide

This guide explains how to configure automatic Supabase schema backups.

## 🔐 Required GitHub Secrets

You need to add 3 secrets to your GitHub repository:

### 1. SUPABASE_ACCESS_TOKEN

**Get it from:**
1. Go to https://supabase.com/dashboard/account/tokens
2. Click "Generate New Token"
3. Name it: "GitHub Actions Backup"
4. Copy the token

**Add to GitHub:**
1. Go to https://github.com/pkold/fuldnyborg-app/settings/secrets/actions
2. Click "New repository secret"
3. Name: `SUPABASE_ACCESS_TOKEN`
4. Value: Paste the token
5. Click "Add secret"

---

### 2. SUPABASE_DB_PASSWORD

**Get it from:**
1. Go to https://supabase.com/dashboard/project/YOUR_PROJECT/settings/database
2. Under "Database Password"
3. Copy your database password (the one you set when creating the project)

**Add to GitHub:**
1. Go to https://github.com/pkold/fuldnyborg-app/settings/secrets/actions
2. Click "New repository secret"
3. Name: `SUPABASE_DB_PASSWORD`
4. Value: Paste your database password
5. Click "Add secret"

---

### 3. SUPABASE_PROJECT_ID

**Get it from:**
1. Go to https://supabase.com/dashboard/project/YOUR_PROJECT/settings/general
2. Under "Project Settings" → "Reference ID"
3. Copy the reference ID (e.g., `abcdefghijklmnop`)

**Add to GitHub:**
1. Go to https://github.com/pkold/fuldnyborg-app/settings/secrets/actions
2. Click "New repository secret"
3. Name: `SUPABASE_PROJECT_ID`
4. Value: Paste the project reference ID
5. Click "Add secret"

---

## ✅ Verify Setup

After adding all 3 secrets:

1. Go to https://github.com/pkold/fuldnyborg-app/actions
2. Click on "Backup Supabase Schema" workflow
3. Click "Run workflow" → "Run workflow"
4. Wait ~1 minute
5. Check if a new backup file appears in `database/backups/`

---

## 🕐 Automatic Schedule

The workflow runs:
- **Daily at 3 AM UTC** (4 AM Danish time)
- **On every push** to main branch (only the workflow file)
- **Manually** via GitHub Actions UI

---

## 📁 Backup Files

- Location: `database/backups/schema_backup_YYYYMMDD.sql`
- Retention: Last 7 days (older backups auto-deleted)
- Format: PostgreSQL dump (schema only, no data)

---

## 🔍 What Gets Backed Up

The workflow backs up:
- ✅ All table schemas
- ✅ All functions
- ✅ All views
- ✅ Indexes, constraints, triggers
- ❌ Data (rows) - only schema structure

If you want to backup data too, modify the workflow:
```yaml
supabase db dump --data-only > database/backups/data_backup_$(date +%Y%m%d).sql
```

---

## 🐛 Troubleshooting

### "Authentication failed"
- Check that `SUPABASE_ACCESS_TOKEN` is correct
- Generate a new token if needed

### "Connection failed"
- Check that `SUPABASE_DB_PASSWORD` is correct
- Verify your database is running

### "Project not found"
- Check that `SUPABASE_PROJECT_ID` is correct
- Make sure it's the Reference ID, not the project name

---

## 📊 Monitoring

View workflow runs:
https://github.com/pkold/fuldnyborg-app/actions

Each run shows:
- ✅ Success/failure status
- 📝 Commit created (if changes detected)
- ⏱️ Execution time (~30-60 seconds)

---

**Last Updated:** January 10, 2026
