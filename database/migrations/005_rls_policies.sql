-- ============================================
-- MIGRATION 005: Row Level Security Policies
-- ============================================
-- Run this AFTER migration 004
-- This adds security so users only see their own data

-- ============================================
-- STEP 1: Helper Function - Check Round Membership
-- ============================================
CREATE OR REPLACE FUNCTION is_round_member(p_round_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM rounds r
    WHERE r.id = p_round_id
      AND (
        r.created_by = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM round_players rp
          WHERE rp.round_id = r.id
            AND rp.user_id = auth.uid()
        )
      )
  );
$$;

COMMENT ON FUNCTION is_round_member IS 
'Returns true if current user is owner or member of round';

-- ============================================
-- STEP 2: Enable RLS on All Tables
-- ============================================
ALTER TABLE players ENABLE ROW LEVEL SECURITY;
ALTER TABLE courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE course_tees ENABLE ROW LEVEL SECURITY;
ALTER TABLE rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE round_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE hole_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE round_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE skins_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE sidegame_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE round_sidegames ENABLE ROW LEVEL SECURITY;
ALTER TABLE sidegame_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE tournaments ENABLE ROW LEVEL SECURITY;
ALTER TABLE tournament_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE tournament_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE tournament_standings ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_logs ENABLE ROW LEVEL SECURITY;

-- ============================================
-- STEP 3: PLAYERS POLICIES
-- ============================================
CREATE POLICY "players_select_all"
ON players FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "players_insert_own"
ON players FOR INSERT
TO authenticated
WITH CHECK (
  user_id IS NULL OR user_id = auth.uid()
);

CREATE POLICY "players_update_own"
ON players FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

COMMENT ON POLICY "players_select_all" ON players IS 
'All authenticated users can see all players (names are public)';

-- ============================================
-- STEP 4: COURSES & TEES POLICIES (public read)
-- ============================================
CREATE POLICY "courses_select_all"
ON courses FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "course_tees_select_all"
ON course_tees FOR SELECT
TO authenticated
USING (true);

COMMENT ON POLICY "courses_select_all" ON courses IS 
'Course data is public (read-only for all)';

-- ============================================
-- STEP 5: ROUNDS POLICIES
-- ============================================
CREATE POLICY "rounds_select_members"
ON rounds FOR SELECT
TO authenticated
USING (is_round_member(id));

CREATE POLICY "rounds_insert_owner"
ON rounds FOR INSERT
TO authenticated
WITH CHECK (created_by = auth.uid());

CREATE POLICY "rounds_update_owner"
ON rounds FOR UPDATE
TO authenticated
USING (created_by = auth.uid())
WITH CHECK (created_by = auth.uid());

COMMENT ON POLICY "rounds_select_members" ON rounds IS 
'Users can only see rounds they created or are members of';

-- ============================================
-- STEP 6: TEAMS POLICIES
-- ============================================
CREATE POLICY "teams_select_members"
ON teams FOR SELECT
TO authenticated
USING (is_round_member(round_id));

CREATE POLICY "teams_modify_owner"
ON teams FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM rounds r 
    WHERE r.id = round_id AND r.created_by = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM rounds r 
    WHERE r.id = round_id AND r.created_by = auth.uid()
  )
);

-- ============================================
-- STEP 7: ROUND_PLAYERS POLICIES
-- ============================================
CREATE POLICY "round_players_select_members"
ON round_players FOR SELECT
TO authenticated
USING (is_round_member(round_id));

CREATE POLICY "round_players_modify_owner"
ON round_players FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM rounds r 
    WHERE r.id = round_id AND r.created_by = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM rounds r 
    WHERE r.id = round_id AND r.created_by = auth.uid()
  )
);

-- ============================================
-- STEP 8: SCORES POLICIES
-- ============================================
CREATE POLICY "scores_select_members"
ON scores FOR SELECT
TO authenticated
USING (is_round_member(round_id));

-- Owner or scorekeeper can write scores for all
CREATE POLICY "scores_insert_authorized"
ON scores FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM rounds r WHERE r.id = round_id AND r.created_by = auth.uid()
  )
  OR EXISTS (
    SELECT 1 FROM round_players rp
    WHERE rp.round_id = scores.round_id 
      AND rp.user_id = auth.uid()
      AND rp.role IN ('owner','scorekeeper')
  )
);

CREATE POLICY "scores_update_authorized"
ON scores FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM rounds r WHERE r.id = round_id AND r.created_by = auth.uid()
  )
  OR EXISTS (
    SELECT 1 FROM round_players rp
    WHERE rp.round_id = scores.round_id 
      AND rp.user_id = auth.uid()
      AND rp.role IN ('owner','scorekeeper')
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM rounds r WHERE r.id = round_id AND r.created_by = auth.uid()
  )
  OR EXISTS (
    SELECT 1 FROM round_players rp
    WHERE rp.round_id = scores.round_id 
      AND rp.user_id = auth.uid()
      AND rp.role IN ('owner','scorekeeper')
  )
);

COMMENT ON POLICY "scores_insert_authorized" ON scores IS 
'Only owner or scorekeeper can write scores';

-- ============================================
-- STEP 9: RESULTS TABLES POLICIES (read only)
-- ============================================
CREATE POLICY "hole_results_select_members"
ON hole_results FOR SELECT
TO authenticated
USING (is_round_member(round_id));

CREATE POLICY "round_results_select_members"
ON round_results FOR SELECT
TO authenticated
USING (is_round_member(round_id));

CREATE POLICY "team_results_select_members"
ON team_results FOR SELECT
TO authenticated
USING (is_round_member(round_id));

CREATE POLICY "skins_results_select_members"
ON skins_results FOR SELECT
TO authenticated
USING (is_round_member(round_id));

-- Note: Write policies for results are handled by Edge Functions using service role

-- ============================================
-- STEP 10: SIDEGAMES POLICIES
-- ============================================
CREATE POLICY "sidegame_types_select_all"
ON sidegame_types FOR SELECT
TO authenticated
USING (is_active = true);

CREATE POLICY "round_sidegames_select_members"
ON round_sidegames FOR SELECT
TO authenticated
USING (is_round_member(round_id));

CREATE POLICY "sidegame_events_select_members"
ON sidegame_events FOR SELECT
TO authenticated
USING (is_round_member(round_id));

CREATE POLICY "sidegame_events_insert_members"
ON sidegame_events FOR INSERT
TO authenticated
WITH CHECK (
  is_round_member(round_id)
  AND created_by = auth.uid()
);

CREATE POLICY "sidegame_events_delete_creator_or_owner"
ON sidegame_events FOR DELETE
TO authenticated
USING (
  created_by = auth.uid()
  OR EXISTS (
    SELECT 1 FROM rounds r 
    WHERE r.id = round_id AND r.created_by = auth.uid()
  )
);

-- ============================================
-- STEP 11: TOURNAMENTS POLICIES
-- ============================================
CREATE POLICY "tournaments_select_members"
ON tournaments FOR SELECT
TO authenticated
USING (
  created_by = auth.uid()
  OR EXISTS (
    SELECT 1 FROM tournament_players tp
    WHERE tp.tournament_id = tournaments.id
      AND tp.player_id IN (
        SELECT id FROM players WHERE user_id = auth.uid()
      )
  )
);

CREATE POLICY "tournaments_insert_own"
ON tournaments FOR INSERT
TO authenticated
WITH CHECK (created_by = auth.uid());

CREATE POLICY "tournaments_update_own"
ON tournaments FOR UPDATE
TO authenticated
USING (created_by = auth.uid())
WITH CHECK (created_by = auth.uid());

-- ============================================
-- STEP 12: TOURNAMENT TABLES POLICIES
-- ============================================
CREATE POLICY "tournament_rounds_select_members"
ON tournament_rounds FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM tournaments t
    WHERE t.id = tournament_id
      AND (
        t.created_by = auth.uid()
        OR EXISTS (
          SELECT 1 FROM tournament_players tp
          WHERE tp.tournament_id = t.id
            AND tp.player_id IN (
              SELECT id FROM players WHERE user_id = auth.uid()
            )
        )
      )
  )
);

CREATE POLICY "tournament_players_select_members"
ON tournament_players FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM tournaments t
    WHERE t.id = tournament_id AND t.created_by = auth.uid()
  )
  OR player_id IN (
    SELECT id FROM players WHERE user_id = auth.uid()
  )
);

CREATE POLICY "tournament_standings_select_members"
ON tournament_standings FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM tournaments t
    WHERE t.id = tournament_id
      AND (
        t.created_by = auth.uid()
        OR EXISTS (
          SELECT 1 FROM tournament_players tp
          WHERE tp.tournament_id = t.id
            AND tp.player_id IN (
              SELECT id FROM players WHERE user_id = auth.uid()
            )
        )
      )
  )
);

-- ============================================
-- STEP 13: APP_LOGS POLICIES
-- ============================================
CREATE POLICY "app_logs_select_own"
ON app_logs FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "app_logs_insert_own"
ON app_logs FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- ============================================
-- VERIFICATION QUERIES
-- ============================================
-- Check RLS is enabled on all tables:
-- SELECT tablename, rowsecurity 
-- FROM pg_tables 
-- WHERE schemaname = 'public'
-- ORDER BY tablename;

-- Check policies exist:
-- SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
-- FROM pg_policies
-- WHERE schemaname = 'public'
-- ORDER BY tablename, policyname;

-- ============================================
-- END OF MIGRATION 005
-- ============================================