-- Filter statistics to only include Stroke Play and Stableford rounds
-- (exclude match play and skins rounds)

-- ============================================
-- get_scoring_averages
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
      AND NOT r.match_play_enabled
      AND NOT r.skins_enabled
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
-- get_scoring_distribution
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
      AND NOT r.match_play_enabled
      AND NOT r.skins_enabled
      AND rp.exclude_from_stats = FALSE
      AND (p_course_id IS NULL OR r.course_id = p_course_id)
      AND (p_date_from IS NULL OR r.finished_at::date >= p_date_from)
      AND (p_date_to IS NULL OR r.finished_at::date <= p_date_to)
    ORDER BY r.finished_at DESC NULLS LAST
    LIMIT p_limit
  )
  SELECT
    COUNT(*) FILTER (WHERE hr.strokes <= hr.par - 2)::INT AS eagles_or_better,
    COUNT(*) FILTER (WHERE hr.strokes = hr.par - 1)::INT AS birdies,
    COUNT(*) FILTER (WHERE hr.strokes = hr.par)::INT AS pars,
    COUNT(*) FILTER (WHERE hr.strokes = hr.par + 1)::INT AS bogeys,
    COUNT(*) FILTER (WHERE hr.strokes >= hr.par + 2)::INT AS double_bogeys_plus
  FROM public.hole_results hr
  JOIN filtered_rounds fr ON fr.round_id = hr.round_id
  WHERE hr.player_id = p_player_id;
$$;

-- ============================================
-- get_par_type_averages
-- ============================================
CREATE OR REPLACE FUNCTION get_par_type_averages(
  p_player_id UUID,
  p_limit INT DEFAULT NULL,
  p_date_from DATE DEFAULT NULL,
  p_date_to DATE DEFAULT NULL,
  p_course_id UUID DEFAULT NULL
)
RETURNS TABLE (
  par_type INT,
  holes_played BIGINT,
  avg_strokes NUMERIC(4,1),
  avg_to_par NUMERIC(4,2)
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  WITH filtered_rounds AS (
    SELECT r.id AS round_id
    FROM public.rounds r
    JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = p_player_id
    WHERE r.status = 'completed'
      AND NOT r.match_play_enabled
      AND NOT r.skins_enabled
      AND rp.exclude_from_stats = FALSE
      AND (p_course_id IS NULL OR r.course_id = p_course_id)
      AND (p_date_from IS NULL OR r.finished_at::date >= p_date_from)
      AND (p_date_to IS NULL OR r.finished_at::date <= p_date_to)
    ORDER BY r.finished_at DESC NULLS LAST
    LIMIT p_limit
  )
  SELECT
    hr.par AS par_type,
    COUNT(*) AS holes_played,
    ROUND(AVG(hr.strokes), 1) AS avg_strokes,
    ROUND(AVG(hr.strokes - hr.par), 2) AS avg_to_par
  FROM public.hole_results hr
  JOIN filtered_rounds fr ON fr.round_id = hr.round_id
  WHERE hr.player_id = p_player_id
    AND hr.par IN (3, 4, 5)
  GROUP BY hr.par
  ORDER BY hr.par;
$$;

-- ============================================
-- get_hole_averages
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
      AND NOT r.match_play_enabled
      AND NOT r.skins_enabled
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
-- get_rounds_per_year
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
    AND NOT r.match_play_enabled
    AND NOT r.skins_enabled
    AND rp.exclude_from_stats = FALSE
  GROUP BY EXTRACT(YEAR FROM COALESCE(r.started_at, r.created_at))
  ORDER BY year DESC;
$$;

-- ============================================
-- get_fun_facts
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
  -- Eagles (gross)
  SELECT COUNT(*)::INT INTO v_eagles
  FROM public.hole_results hr
  JOIN public.rounds r ON r.id = hr.round_id
  JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = hr.player_id
  WHERE hr.player_id = p_player_id
    AND r.status = 'completed'
    AND NOT r.match_play_enabled AND NOT r.skins_enabled
    AND rp.exclude_from_stats = FALSE
    AND hr.strokes <= hr.par - 2;

  -- Holes in one (gross strokes = 1)
  SELECT COUNT(*)::INT INTO v_hio
  FROM public.hole_results hr
  JOIN public.rounds r ON r.id = hr.round_id
  JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = hr.player_id
  WHERE hr.player_id = p_player_id
    AND r.status = 'completed'
    AND NOT r.match_play_enabled AND NOT r.skins_enabled
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
    AND NOT r.match_play_enabled AND NOT r.skins_enabled
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
    AND NOT r.match_play_enabled AND NOT r.skins_enabled
    AND rp.exclude_from_stats = FALSE;

  -- Most played course
  SELECT c.name, COUNT(*)::INT
  INTO v_most_course, v_most_count
  FROM public.rounds r
  JOIN public.courses c ON c.id = r.course_id
  JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = p_player_id
  WHERE r.status = 'completed'
    AND NOT r.match_play_enabled AND NOT r.skins_enabled
    AND rp.exclude_from_stats = FALSE
  GROUP BY c.name
  ORDER BY COUNT(*) DESC
  LIMIT 1;

  -- Longest par streak (consecutive holes with strokes <= par)
  FOR rec IN
    SELECT hr.round_id, hr.hole_no, hr.strokes, hr.par
    FROM public.hole_results hr
    JOIN public.rounds r ON r.id = hr.round_id
    JOIN public.round_players rp ON rp.round_id = r.id AND rp.player_id = hr.player_id
    WHERE hr.player_id = p_player_id
      AND r.status = 'completed'
      AND NOT r.match_play_enabled AND NOT r.skins_enabled
      AND rp.exclude_from_stats = FALSE
    ORDER BY COALESCE(r.finished_at, r.created_at), hr.hole_no
  LOOP
    IF rec.round_id IS DISTINCT FROM v_prev_round THEN
      v_prev_round := rec.round_id;
    END IF;

    IF rec.strokes <= rec.par THEN
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
-- get_handicap_history
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
    AND NOT r.match_play_enabled
    AND NOT r.skins_enabled
    AND rp.exclude_from_stats = FALSE
  ORDER BY COALESCE(r.finished_at, r.created_at) DESC
  LIMIT p_limit;
$$;
