-- ============================================
-- MIGRATION 009: Fix RLS infinite recursion
-- ============================================
-- The tournaments and tournament_players SELECT policies
-- reference each other, causing infinite recursion.
-- Fix: use SECURITY DEFINER helper functions that bypass RLS.

-- ============================================
-- STEP 1: Create helper functions (SECURITY DEFINER bypasses RLS)
-- ============================================

CREATE OR REPLACE FUNCTION public.is_tournament_creator(t_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tournaments WHERE id = t_id AND created_by = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.is_tournament_player(t_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tournament_players tp
    JOIN public.players p ON p.id = tp.player_id
    WHERE tp.tournament_id = t_id AND p.user_id = auth.uid()
  );
$$;

-- ============================================
-- STEP 2: Replace tournaments SELECT policy
-- ============================================

DROP POLICY IF EXISTS "tournaments_select_members" ON tournaments;

CREATE POLICY "tournaments_select_members"
ON tournaments FOR SELECT
TO authenticated
USING (
  public.is_tournament_creator(id)
  OR public.is_tournament_player(id)
);

-- ============================================
-- STEP 3: Replace tournament_players SELECT policy
-- ============================================

DROP POLICY IF EXISTS "tournament_players_select_members" ON tournament_players;

CREATE POLICY "tournament_players_select_members"
ON tournament_players FOR SELECT
TO authenticated
USING (
  public.is_tournament_creator(tournament_id)
  OR player_id IN (SELECT id FROM players WHERE user_id = auth.uid())
);

-- ============================================
-- STEP 4: Replace tournament_standings SELECT policy
-- ============================================

DROP POLICY IF EXISTS "tournament_standings_select_members" ON tournament_standings;

CREATE POLICY "tournament_standings_select_members"
ON tournament_standings FOR SELECT
TO authenticated
USING (
  public.is_tournament_creator(tournament_id)
  OR public.is_tournament_player(tournament_id)
);

-- ============================================
-- STEP 5: Replace tournament_rounds SELECT policy
-- ============================================

DROP POLICY IF EXISTS "tournament_rounds_select_members" ON tournament_rounds;

CREATE POLICY "tournament_rounds_select_members"
ON tournament_rounds FOR SELECT
TO authenticated
USING (
  public.is_tournament_creator(tournament_id)
  OR public.is_tournament_player(tournament_id)
);

-- ============================================
-- STEP 6: Replace tournament_team_standings SELECT policy
-- ============================================

DROP POLICY IF EXISTS "tournament_team_standings_select" ON tournament_team_standings;

CREATE POLICY "tournament_team_standings_select"
ON tournament_team_standings FOR SELECT
USING (
  public.is_tournament_creator(tournament_id)
  OR public.is_tournament_player(tournament_id)
);

DROP POLICY IF EXISTS "tournament_team_standings_modify" ON tournament_team_standings;

CREATE POLICY "tournament_team_standings_modify"
ON tournament_team_standings FOR ALL
USING (
  public.is_tournament_creator(tournament_id)
);

-- ============================================
-- END OF MIGRATION 009
-- ============================================
