-- 014_friendships.sql
-- Friend system: friendships table, invite codes, and RLS policies

-- ============================================================
-- friendships table
-- ============================================================
CREATE TABLE IF NOT EXISTS friendships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  addressee_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT no_self_friendship CHECK (requester_id != addressee_id),
  CONSTRAINT unique_friendship UNIQUE (requester_id, addressee_id)
);

CREATE INDEX IF NOT EXISTS idx_friendships_requester ON friendships(requester_id);
CREATE INDEX IF NOT EXISTS idx_friendships_addressee ON friendships(addressee_id);
CREATE INDEX IF NOT EXISTS idx_friendships_status ON friendships(status);

-- Trigger to prevent reverse duplicates (A→B exists, block B→A)
CREATE OR REPLACE FUNCTION prevent_reverse_friendship()
RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM friendships
    WHERE requester_id = NEW.addressee_id AND addressee_id = NEW.requester_id
  ) THEN
    RAISE EXCEPTION 'A friendship between these users already exists';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_reverse_friendship ON friendships;
CREATE TRIGGER trg_prevent_reverse_friendship
  BEFORE INSERT ON friendships
  FOR EACH ROW EXECUTE FUNCTION prevent_reverse_friendship();

-- ============================================================
-- friend_invite_codes table
-- ============================================================
CREATE TABLE IF NOT EXISTS friend_invite_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '7 days'),
  used_by UUID REFERENCES auth.users(id),
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invite_codes_code ON friend_invite_codes(code);
CREATE INDEX IF NOT EXISTS idx_invite_codes_user ON friend_invite_codes(user_id);

-- ============================================================
-- generate_friend_invite_code() function
-- ============================================================
CREATE OR REPLACE FUNCTION generate_friend_invite_code()
RETURNS TEXT AS $$
DECLARE
  new_code TEXT;
  code_exists BOOLEAN;
BEGIN
  LOOP
    new_code := upper(substr(md5(gen_random_uuid()::text), 1, 8));
    SELECT EXISTS(SELECT 1 FROM friend_invite_codes WHERE code = new_code) INTO code_exists;
    EXIT WHEN NOT code_exists;
  END LOOP;
  RETURN new_code;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- RLS policies
-- ============================================================
ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE friend_invite_codes ENABLE ROW LEVEL SECURITY;

-- Friendships: users can see their own friendships
DO $$ BEGIN
  CREATE POLICY "friendships_select_own" ON friendships FOR SELECT
    USING (requester_id = auth.uid() OR addressee_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Invite codes: users can see their own codes
DO $$ BEGIN
  CREATE POLICY "invite_codes_select_own" ON friend_invite_codes FOR SELECT
    USING (user_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
