-- Fix scoring distribution to use gross strokes instead of net
-- Add average scoring per par type (par 3, par 4, par 5)

-- ============================================
-- FIX: get_scoring_distribution — use gross strokes
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
-- NEW: get_par_type_averages
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
