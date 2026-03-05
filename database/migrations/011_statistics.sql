-- ============================================
-- MIGRATION 011: Statistics functions & tables
-- ============================================

-- ============================================
-- STEP 1: home_courses table
-- ============================================

CREATE TABLE home_courses (
  user_id UUID NOT NULL,
  course_id UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, course_id)
);

CREATE INDEX idx_home_courses_user ON home_courses(user_id);

ALTER TABLE home_courses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own home courses"
  ON home_courses FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own home courses"
  ON home_courses FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own home courses"
  ON home_courses FOR DELETE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update own home courses"
  ON home_courses FOR UPDATE
  USING (auth.uid() = user_id);

-- ============================================
-- STEP 2: exclude_from_stats on round_players
-- ============================================

ALTER TABLE round_players
ADD COLUMN exclude_from_stats BOOLEAN NOT NULL DEFAULT FALSE;

-- RLS: players can update their own exclude_from_stats
-- (existing UPDATE policy may already cover this, but ensure it exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'round_players' AND policyname = 'round_players_update_own_exclude'
  ) THEN
    CREATE POLICY "round_players_update_own_exclude"
    ON round_players FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- ============================================
-- STEP 3: get_scoring_averages
-- ============================================

CREATE OR REPLACE FUNCTION get_scoring_averages(
  p_player_id UUID,
  p_limit INT DEFAULT NULL,
  p_date_from DATE DEFAULT NULL,
  p_date_to DATE DEFAULT NULL,
  p_course_id UUID DEFAULT NULL
)
RETURNS TABLE (
  rounds_count INT,
  avg_gross NUMERIC(5,1),
  avg_net NUMERIC(5,1),
  avg_stableford NUMERIC(5,1),
  best_gross INT,
  best_net INT,
  best_stableford INT
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  WITH filtered_rounds AS (
    SELECT rr.gross_total, rr.net_total, rr.stableford_total
    FROM public.round_results rr
    JOIN public.rounds r ON r.id = rr.round_id
    JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = rr.player_id
    WHERE rr.player_id = p_player_id
      AND r.status = 'completed'
      AND rp.exclude_from_stats = FALSE
      AND (p_course_id IS NULL OR r.course_id = p_course_id)
      AND (p_date_from IS NULL OR r.finished_at::date >= p_date_from)
      AND (p_date_to IS NULL OR r.finished_at::date <= p_date_to)
    ORDER BY r.finished_at DESC NULLS LAST
    LIMIT p_limit
  )
  SELECT
    COUNT(*)::INT AS rounds_count,
    ROUND(AVG(gross_total), 1) AS avg_gross,
    ROUND(AVG(net_total), 1) AS avg_net,
    ROUND(AVG(stableford_total), 1) AS avg_stableford,
    MIN(gross_total)::INT AS best_gross,
    MIN(net_total)::INT AS best_net,
    MAX(stableford_total)::INT AS best_stableford
  FROM filtered_rounds;
$$;

-- ============================================
-- STEP 4: get_scoring_distribution
-- ============================================

CREATE OR REPLACE FUNCTION get_scoring_distribution(
  p_player_id UUID,
  p_limit INT DEFAULT NULL,
  p_date_from DATE DEFAULT NULL,
  p_date_to DATE DEFAULT NULL,
  p_course_id UUID DEFAULT NULL
)
RETURNS TABLE (
  eagles_or_better INT,
  birdies INT,
  pars INT,
  bogeys INT,
  double_bogeys_plus INT
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  WITH filtered_rounds AS (
    SELECT r.id AS round_id
    FROM public.rounds r
    JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = p_player_id
    WHERE r.status = 'completed'
      AND rp.exclude_from_stats = FALSE
      AND (p_course_id IS NULL OR r.course_id = p_course_id)
      AND (p_date_from IS NULL OR r.finished_at::date >= p_date_from)
      AND (p_date_to IS NULL OR r.finished_at::date <= p_date_to)
    ORDER BY r.finished_at DESC NULLS LAST
    LIMIT p_limit
  )
  SELECT
    COUNT(*) FILTER (WHERE hr.net_strokes <= hr.par - 2)::INT AS eagles_or_better,
    COUNT(*) FILTER (WHERE hr.net_strokes = hr.par - 1)::INT AS birdies,
    COUNT(*) FILTER (WHERE hr.net_strokes = hr.par)::INT AS pars,
    COUNT(*) FILTER (WHERE hr.net_strokes = hr.par + 1)::INT AS bogeys,
    COUNT(*) FILTER (WHERE hr.net_strokes >= hr.par + 2)::INT AS double_bogeys_plus
  FROM public.hole_results hr
  JOIN filtered_rounds fr ON fr.round_id = hr.round_id
  WHERE hr.player_id = p_player_id;
$$;

-- ============================================
-- STEP 5: get_hole_averages
-- ============================================

CREATE OR REPLACE FUNCTION get_hole_averages(
  p_player_id UUID,
  p_course_id UUID,
  p_limit INT DEFAULT NULL,
  p_date_from DATE DEFAULT NULL,
  p_date_to DATE DEFAULT NULL
)
RETURNS TABLE (
  hole_no INT,
  par INT,
  avg_strokes NUMERIC(4,1),
  avg_net NUMERIC(4,1),
  best_score INT,
  worst_score INT,
  times_played INT
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  WITH filtered_rounds AS (
    SELECT r.id AS round_id
    FROM public.rounds r
    JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = p_player_id
    WHERE r.status = 'completed'
      AND r.course_id = p_course_id
      AND rp.exclude_from_stats = FALSE
      AND (p_date_from IS NULL OR r.finished_at::date >= p_date_from)
      AND (p_date_to IS NULL OR r.finished_at::date <= p_date_to)
    ORDER BY r.finished_at DESC NULLS LAST
    LIMIT p_limit
  )
  SELECT
    hr.hole_no::INT,
    hr.par::INT,
    ROUND(AVG(hr.strokes), 1) AS avg_strokes,
    ROUND(AVG(hr.net_strokes), 1) AS avg_net,
    MIN(hr.strokes)::INT AS best_score,
    MAX(hr.strokes)::INT AS worst_score,
    COUNT(*)::INT AS times_played
  FROM public.hole_results hr
  JOIN filtered_rounds fr ON fr.round_id = hr.round_id
  WHERE hr.player_id = p_player_id
  GROUP BY hr.hole_no, hr.par
  ORDER BY hr.hole_no;
$$;

-- ============================================
-- STEP 6: get_rounds_per_year
-- ============================================

CREATE OR REPLACE FUNCTION get_rounds_per_year(
  p_player_id UUID
)
RETURNS TABLE (
  year INT,
  rounds_count INT
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    EXTRACT(YEAR FROM COALESCE(r.started_at, r.created_at))::INT AS year,
    COUNT(*)::INT AS rounds_count
  FROM public.rounds r
  JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = p_player_id
  WHERE r.status = 'completed'
    AND rp.exclude_from_stats = FALSE
  GROUP BY EXTRACT(YEAR FROM COALESCE(r.started_at, r.created_at))
  ORDER BY year DESC;
$$;

-- ============================================
-- STEP 7: get_competition_stats
-- ============================================

CREATE OR REPLACE FUNCTION get_competition_stats(
  p_player_id UUID,
  p_limit INT DEFAULT NULL,
  p_date_from DATE DEFAULT NULL,
  p_date_to DATE DEFAULT NULL
)
RETURNS TABLE (
  total_skins_won INT,
  total_skins_value NUMERIC,
  rounds_played INT,
  rounds_won INT,
  top_3_finishes INT,
  win_rate NUMERIC(5,2)
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  WITH filtered_rounds AS (
    SELECT r.id AS round_id
    FROM public.rounds r
    JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = p_player_id
    WHERE r.status = 'completed'
      AND rp.exclude_from_stats = FALSE
      AND (p_date_from IS NULL OR r.finished_at::date >= p_date_from)
      AND (p_date_to IS NULL OR r.finished_at::date <= p_date_to)
    ORDER BY r.finished_at DESC NULLS LAST
    LIMIT p_limit
  ),
  skins AS (
    SELECT
      COUNT(*)::INT AS won,
      COALESCE(SUM(sr.skin_awarded_value), 0) AS value
    FROM public.skins_results sr
    JOIN filtered_rounds fr ON fr.round_id = sr.round_id
    WHERE sr.winner_player_id = p_player_id
      AND sr.skin_awarded_value > 0
  ),
  ranked AS (
    SELECT
      rr.round_id,
      rr.player_id,
      RANK() OVER (PARTITION BY rr.round_id ORDER BY rr.stableford_total DESC) AS player_rank
    FROM public.round_results rr
    JOIN filtered_rounds fr ON fr.round_id = rr.round_id
  ),
  my_ranks AS (
    SELECT player_rank
    FROM ranked
    WHERE player_id = p_player_id
  ),
  round_count AS (
    SELECT COUNT(*)::INT AS cnt FROM filtered_rounds
  )
  SELECT
    s.won AS total_skins_won,
    s.value AS total_skins_value,
    rc.cnt AS rounds_played,
    (SELECT COUNT(*) FROM my_ranks WHERE player_rank = 1)::INT AS rounds_won,
    (SELECT COUNT(*) FROM my_ranks WHERE player_rank <= 3)::INT AS top_3_finishes,
    CASE WHEN rc.cnt > 0
      THEN ROUND((SELECT COUNT(*) FROM my_ranks WHERE player_rank = 1)::NUMERIC / rc.cnt * 100, 2)
      ELSE 0
    END AS win_rate
  FROM skins s, round_count rc;
$$;

-- ============================================
-- STEP 8: get_head_to_head
-- ============================================

CREATE OR REPLACE FUNCTION get_head_to_head(
  p_player_id UUID,
  p_opponent_id UUID
)
RETURNS TABLE (
  rounds_together INT,
  player_wins INT,
  opponent_wins INT,
  ties INT,
  player_avg_stableford NUMERIC(5,1),
  opponent_avg_stableford NUMERIC(5,1),
  player_skins_won INT,
  opponent_skins_won INT
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  WITH shared_rounds AS (
    SELECT r.id AS round_id
    FROM public.rounds r
    JOIN public.round_players rp1 ON rp1.round_id = r.id AND rp1.player_id = p_player_id
    JOIN public.round_players rp2 ON rp2.round_id = r.id AND rp2.player_id = p_opponent_id
    WHERE r.status = 'completed'
      AND rp1.exclude_from_stats = FALSE
  ),
  results AS (
    SELECT
      sr.round_id,
      MAX(CASE WHEN rr.player_id = p_player_id THEN rr.stableford_total END) AS my_pts,
      MAX(CASE WHEN rr.player_id = p_opponent_id THEN rr.stableford_total END) AS opp_pts
    FROM shared_rounds sr
    JOIN public.round_results rr ON rr.round_id = sr.round_id
      AND rr.player_id IN (p_player_id, p_opponent_id)
    GROUP BY sr.round_id
  ),
  skins AS (
    SELECT
      COALESCE(SUM(CASE WHEN sk.winner_player_id = p_player_id THEN 1 ELSE 0 END), 0)::INT AS my_skins,
      COALESCE(SUM(CASE WHEN sk.winner_player_id = p_opponent_id THEN 1 ELSE 0 END), 0)::INT AS opp_skins
    FROM public.skins_results sk
    JOIN shared_rounds sr ON sr.round_id = sk.round_id
    WHERE sk.winner_player_id IN (p_player_id, p_opponent_id)
      AND sk.skin_awarded_value > 0
  )
  SELECT
    (SELECT COUNT(*) FROM shared_rounds)::INT AS rounds_together,
    COUNT(*) FILTER (WHERE res.my_pts > res.opp_pts)::INT AS player_wins,
    COUNT(*) FILTER (WHERE res.my_pts < res.opp_pts)::INT AS opponent_wins,
    COUNT(*) FILTER (WHERE res.my_pts = res.opp_pts)::INT AS ties,
    ROUND(AVG(res.my_pts), 1) AS player_avg_stableford,
    ROUND(AVG(res.opp_pts), 1) AS opponent_avg_stableford,
    (SELECT my_skins FROM skins) AS player_skins_won,
    (SELECT opp_skins FROM skins) AS opponent_skins_won
  FROM results res;
$$;

-- ============================================
-- STEP 9: get_fun_facts
-- ============================================

CREATE OR REPLACE FUNCTION get_fun_facts(
  p_player_id UUID
)
RETURNS TABLE (
  total_eagles INT,
  total_holes_in_one INT,
  best_gross_ever INT,
  best_stableford_ever INT,
  best_round_course TEXT,
  best_round_date DATE,
  most_played_course TEXT,
  most_played_count INT,
  longest_par_streak INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_eagles INT;
  v_hio INT;
  v_best_gross INT;
  v_best_stableford INT;
  v_best_course TEXT;
  v_best_date DATE;
  v_most_course TEXT;
  v_most_count INT;
  v_longest_streak INT := 0;
  v_current_streak INT := 0;
  v_prev_round UUID := NULL;
  rec RECORD;
BEGIN
  -- Eagles (net)
  SELECT COUNT(*)::INT INTO v_eagles
  FROM public.hole_results hr
  JOIN public.rounds r ON r.id = hr.round_id
  JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = hr.player_id
  WHERE hr.player_id = p_player_id
    AND r.status = 'completed'
    AND rp.exclude_from_stats = FALSE
    AND hr.net_strokes <= hr.par - 2;

  -- Holes in one (gross strokes = 1)
  SELECT COUNT(*)::INT INTO v_hio
  FROM public.hole_results hr
  JOIN public.rounds r ON r.id = hr.round_id
  JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = hr.player_id
  WHERE hr.player_id = p_player_id
    AND r.status = 'completed'
    AND rp.exclude_from_stats = FALSE
    AND hr.strokes = 1;

  -- Best gross round + course info
  SELECT rr.gross_total, c.name, r.finished_at::date
  INTO v_best_gross, v_best_course, v_best_date
  FROM public.round_results rr
  JOIN public.rounds r ON r.id = rr.round_id
  JOIN public.courses c ON c.id = r.course_id
  JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = rr.player_id
  WHERE rr.player_id = p_player_id
    AND r.status = 'completed'
    AND rp.exclude_from_stats = FALSE
  ORDER BY rr.gross_total ASC
  LIMIT 1;

  -- Best stableford
  SELECT MAX(rr.stableford_total)::INT INTO v_best_stableford
  FROM public.round_results rr
  JOIN public.rounds r ON r.id = rr.round_id
  JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = rr.player_id
  WHERE rr.player_id = p_player_id
    AND r.status = 'completed'
    AND rp.exclude_from_stats = FALSE;

  -- Most played course
  SELECT c.name, COUNT(*)::INT
  INTO v_most_course, v_most_count
  FROM public.rounds r
  JOIN public.courses c ON c.id = r.course_id
  JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = p_player_id
  WHERE r.status = 'completed'
    AND rp.exclude_from_stats = FALSE
  GROUP BY c.name
  ORDER BY COUNT(*) DESC
  LIMIT 1;

  -- Longest par streak (consecutive holes with net_strokes <= par)
  FOR rec IN
    SELECT hr.round_id, hr.hole_no, hr.net_strokes, hr.par
    FROM public.hole_results hr
    JOIN public.rounds r ON r.id = hr.round_id
    JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = hr.player_id
    WHERE hr.player_id = p_player_id
      AND r.status = 'completed'
      AND rp.exclude_from_stats = FALSE
    ORDER BY COALESCE(r.finished_at, r.created_at), hr.hole_no
  LOOP
    IF rec.round_id IS DISTINCT FROM v_prev_round THEN
      -- New round: reset streak only if the last hole broke it
      -- Actually, streaks can span rounds, so only reset on bad hole
      v_prev_round := rec.round_id;
    END IF;

    IF rec.net_strokes <= rec.par THEN
      v_current_streak := v_current_streak + 1;
      IF v_current_streak > v_longest_streak THEN
        v_longest_streak := v_current_streak;
      END IF;
    ELSE
      v_current_streak := 0;
    END IF;
  END LOOP;

  RETURN QUERY SELECT
    COALESCE(v_eagles, 0),
    COALESCE(v_hio, 0),
    v_best_gross,
    v_best_stableford,
    v_best_course,
    v_best_date,
    v_most_course,
    COALESCE(v_most_count, 0),
    v_longest_streak;
END;
$$;

-- ============================================
-- STEP 10: get_handicap_history
-- ============================================

CREATE OR REPLACE FUNCTION get_handicap_history(
  p_player_id UUID,
  p_limit INT DEFAULT 20
)
RETURNS TABLE (
  round_date DATE,
  course_name TEXT,
  gross_total INT,
  net_total INT,
  stableford_total INT,
  playing_hcp INT
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    COALESCE(r.finished_at, r.created_at)::date AS round_date,
    c.name AS course_name,
    rr.gross_total::INT,
    rr.net_total::INT,
    rr.stableford_total::INT,
    rp.playing_hcp::INT
  FROM public.round_results rr
  JOIN public.rounds r ON r.id = rr.round_id
  JOIN public.courses c ON c.id = r.course_id
  JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = rr.player_id
  WHERE rr.player_id = p_player_id
    AND r.status = 'completed'
    AND rp.exclude_from_stats = FALSE
  ORDER BY COALESCE(r.finished_at, r.created_at) DESC
  LIMIT p_limit;
$$;

-- ============================================
-- END OF MIGRATION 011
-- ============================================
