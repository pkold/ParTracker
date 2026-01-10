-- ============================================
-- MISSING FUNCTIONS: Handicap Calculations
-- ============================================
-- DROP existing functions first to avoid conflicts

-- Drop if they exist
DROP FUNCTION IF EXISTS calculate_playing_hcp(NUMERIC, INT, NUMERIC, INT, NUMERIC, INT);
DROP FUNCTION IF EXISTS calculate_strokes_received(INT, INT, INT);
DROP FUNCTION IF EXISTS calculate_stableford_points(INT, INT);

-- ============================================
-- FUNCTION 1: Calculate Playing Handicap
-- ============================================
-- Converts handicap index to playing handicap for specific course/tee
CREATE FUNCTION calculate_playing_hcp(
  p_handicap_index NUMERIC,
  p_slope_rating INT,
  p_course_rating NUMERIC,
  p_par INT,
  p_handicap_allowance NUMERIC DEFAULT 1.0,
  p_holes_played INT DEFAULT 18
)
RETURNS INT
LANGUAGE SQL
IMMUTABLE
AS $$
  SELECT ROUND(
    (p_handicap_index * (p_slope_rating::numeric / 113.0) + (p_course_rating - p_par))
    * p_handicap_allowance
    * (p_holes_played::numeric / 18.0)
  )::INT;
$$;

COMMENT ON FUNCTION calculate_playing_hcp IS 
'WHS formula: (HI × (SR/113) + (CR - Par)) × Allowance × (Holes/18)';

-- ============================================
-- FUNCTION 2: Calculate Strokes Received Per Hole
-- ============================================
-- Determines how many handicap strokes a player gets on a specific hole
CREATE FUNCTION calculate_strokes_received(
  p_playing_hcp INT,
  p_stroke_index INT,
  p_holes_played INT DEFAULT 18
)
RETURNS INT
LANGUAGE SQL
IMMUTABLE
AS $$
  SELECT CASE
    -- 18 holes: Standard WHS allocation
    WHEN p_holes_played = 18 THEN
      CASE
        WHEN p_playing_hcp >= p_stroke_index THEN 1
        WHEN p_playing_hcp >= (18 + p_stroke_index) THEN 2
        WHEN p_playing_hcp >= (36 + p_stroke_index) THEN 3
        ELSE 0
      END
    -- 9 holes: Half the handicap applies
    WHEN p_holes_played = 9 THEN
      CASE
        WHEN (p_playing_hcp / 2) >= p_stroke_index THEN 1
        WHEN (p_playing_hcp / 2) >= (9 + p_stroke_index) THEN 2
        ELSE 0
      END
    ELSE 0
  END;
$$;

COMMENT ON FUNCTION calculate_strokes_received IS 
'Returns handicap strokes for a hole based on playing HCP and stroke index';

-- ============================================
-- FUNCTION 3: Calculate Stableford Points
-- ============================================
-- Converts net score to stableford points
CREATE FUNCTION calculate_stableford_points(
  p_net_strokes INT,
  p_par INT
)
RETURNS INT
LANGUAGE SQL
IMMUTABLE
AS $$
  SELECT GREATEST(0, 2 + (p_par - p_net_strokes));
$$;

COMMENT ON FUNCTION calculate_stableford_points IS 
'Stableford: 0=+3 or worse, 1=+2, 2=+1/par, 3=-1, 4=-2, 5=-3, etc.';

-- ============================================
-- VERIFICATION: Test the functions
-- ============================================
SELECT 
  'TEST RESULTS' as test_name,
  calculate_playing_hcp(5.2, 113, 69.5, 72, 1.0, 18) as peter_hcp_5,
  calculate_playing_hcp(12.4, 113, 69.5, 72, 1.0, 18) as marie_hcp_12,
  calculate_playing_hcp(18.7, 113, 69.5, 72, 1.0, 18) as lars_hcp_19,
  calculate_strokes_received(5, 11, 18) as hole1_peter_0,
  calculate_strokes_received(12, 11, 18) as hole1_marie_1,
  calculate_strokes_received(19, 11, 18) as hole1_lars_1,
  calculate_stableford_points(4, 4) as par_2pts,
  calculate_stableford_points(3, 4) as birdie_3pts,
  calculate_stableford_points(5, 4) as bogey_1pt;

-- ============================================
-- END OF CALCULATION FUNCTIONS
-- ============================================
