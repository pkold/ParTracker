-- Seed peter@kolds.dk as super_admin
INSERT INTO admin_users (user_id, role)
SELECT id, 'super_admin' FROM auth.users
WHERE email = 'peter@kolds.dk'
ON CONFLICT (user_id) DO NOTHING;
