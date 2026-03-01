-- 013_user_accounts.sql
-- User accounts: consents, player profile columns, profile photo storage

-- ─── User Consents Table ───
CREATE TABLE IF NOT EXISTS user_consents (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  consent_type TEXT NOT NULL,  -- 'terms_of_service', 'privacy_policy'
  consented_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ip_address TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_user_consents_user_id ON user_consents(user_id);

-- RLS for user_consents
ALTER TABLE user_consents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own consents"
  ON user_consents FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own consents"
  ON user_consents FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- ─── Player Profile Columns ───
ALTER TABLE players ADD COLUMN IF NOT EXISTS settings JSONB DEFAULT '{}';
ALTER TABLE players ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE players ADD COLUMN IF NOT EXISTS first_name TEXT;
ALTER TABLE players ADD COLUMN IF NOT EXISTS last_name TEXT;

-- ─── Profile Photos Storage Bucket ───
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'profile-photos',
  'profile-photos',
  true,
  5242880,  -- 5MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
) ON CONFLICT (id) DO NOTHING;

-- Storage RLS: users can manage their own folder
CREATE POLICY "Users can upload own profile photos"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'profile-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users can update own profile photos"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'profile-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users can delete own profile photos"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'profile-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Profile photos are publicly readable"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'profile-photos');
