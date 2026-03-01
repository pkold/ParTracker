-- 012_admin_website.sql
-- Admin dashboard and website support tables

-- ============================================================
-- 1. admin_users — Controls access to the admin dashboard
-- ============================================================
CREATE TABLE admin_users (
  user_id    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role       TEXT NOT NULL CHECK (role IN ('admin', 'super_admin')) DEFAULT 'admin',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

-- Admins can see who else is an admin
CREATE POLICY "admin_users_select" ON admin_users
  FOR SELECT USING (
    auth.uid() IN (SELECT user_id FROM admin_users)
  );

-- ============================================================
-- 2. contact_messages — Landing page contact form submissions
-- ============================================================
CREATE TABLE contact_messages (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  email      TEXT NOT NULL,
  message    TEXT NOT NULL,
  read       BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE contact_messages ENABLE ROW LEVEL SECURITY;

-- Anyone can submit a contact message (anon insert)
CREATE POLICY "contact_messages_insert" ON contact_messages
  FOR INSERT WITH CHECK (TRUE);

-- Only admins can read messages
CREATE POLICY "contact_messages_select" ON contact_messages
  FOR SELECT USING (
    auth.uid() IN (SELECT user_id FROM admin_users)
  );

-- Only admins can update messages (mark as read)
CREATE POLICY "contact_messages_update" ON contact_messages
  FOR UPDATE USING (
    auth.uid() IN (SELECT user_id FROM admin_users)
  );

-- ============================================================
-- 3. Admin views (for dashboard stats)
--    Accessed via service role client — no RLS needed on views
-- ============================================================

-- Usage overview: total users, guests, rounds, active users
CREATE OR REPLACE VIEW admin_usage_overview AS
SELECT
  (SELECT COUNT(*) FROM players WHERE user_id IS NOT NULL AND email IS NOT NULL) AS total_users,
  (SELECT COUNT(*) FROM players WHERE email IS NULL) AS total_guests,
  (SELECT COUNT(*) FROM rounds) AS total_rounds,
  (SELECT COUNT(DISTINCT created_by) FROM rounds WHERE created_at > NOW() - INTERVAL '7 days') AS active_users_7d,
  (SELECT COUNT(DISTINCT created_by) FROM rounds WHERE created_at > NOW() - INTERVAL '30 days') AS active_users_30d;

-- Rounds per day (last 90 days)
CREATE OR REPLACE VIEW admin_rounds_per_day AS
SELECT
  DATE(created_at) AS day,
  COUNT(*) AS round_count
FROM rounds
WHERE created_at > NOW() - INTERVAL '90 days'
GROUP BY DATE(created_at)
ORDER BY day;

-- Popular courses
CREATE OR REPLACE VIEW admin_popular_courses AS
SELECT
  c.id,
  c.name,
  c.club,
  c.city,
  COUNT(r.id) AS round_count
FROM courses c
LEFT JOIN rounds r ON r.course_id = c.id
GROUP BY c.id, c.name, c.club, c.city
ORDER BY round_count DESC;

-- Format breakdown
CREATE OR REPLACE VIEW admin_format_stats AS
SELECT
  scoring_format,
  team_mode,
  COUNT(*) AS round_count
FROM rounds
GROUP BY scoring_format, team_mode
ORDER BY round_count DESC;

-- ============================================================
-- REMINDER: After running this migration, manually seed admin:
--
--   INSERT INTO admin_users (user_id, role)
--   SELECT id, 'super_admin' FROM auth.users
--   WHERE email = 'peter@kolds.dk';
-- ============================================================
