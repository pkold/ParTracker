-- ============================================
-- TEST DATA SETUP
-- ============================================
-- Creates realistic test data for FuldNyborg App
-- Run this to get started with testing

-- ============================================
-- STEP 1: Create Nyborg Golf Club
-- ============================================
INSERT INTO courses (name, club, city, country)
VALUES ('Nyborg Golf Club', 'Nyborg GC', 'Nyborg', 'Denmark')
ON CONFLICT DO NOTHING
RETURNING id, name;

-- ============================================
-- STEP 2: Create Yellow Tee with 18 holes
-- ============================================
-- Get course_id for next insert
DO $$
DECLARE
  v_course_id UUID;
BEGIN
  -- Get the Nyborg course ID
  SELECT id INTO v_course_id 
  FROM courses 
  WHERE name = 'Nyborg Golf Club';
  
  -- Insert Yellow Tee with realistic hole data
  INSERT INTO course_tees (
    course_id,
    tee_name,
    tee_color,
    gender,
    slope_rating,
    course_rating,
    par,
    holes
  )
  VALUES (
    v_course_id,
    'Yellow',
    'yellow',
    'mixed',
    113,
    69.5,
    72,
    -- 18 holes as JSONB array
    -- Based on typical Danish parkland course layout
    '[
      {"hole_no": 1,  "par": 4, "stroke_index": 11},
      {"hole_no": 2,  "par": 5, "stroke_index": 3},
      {"hole_no": 3,  "par": 3, "stroke_index": 17},
      {"hole_no": 4,  "par": 4, "stroke_index": 7},
      {"hole_no": 5,  "par": 4, "stroke_index": 13},
      {"hole_no": 6,  "par": 5, "stroke_index": 1},
      {"hole_no": 7,  "par": 3, "stroke_index": 15},
      {"hole_no": 8,  "par": 4, "stroke_index": 9},
      {"hole_no": 9,  "par": 4, "stroke_index": 5},
      {"hole_no": 10, "par": 4, "stroke_index": 10},
      {"hole_no": 11, "par": 5, "stroke_index": 2},
      {"hole_no": 12, "par": 3, "stroke_index": 18},
      {"hole_no": 13, "par": 4, "stroke_index": 6},
      {"hole_no": 14, "par": 4, "stroke_index": 14},
      {"hole_no": 15, "par": 5, "stroke_index": 4},
      {"hole_no": 16, "par": 3, "stroke_index": 16},
      {"hole_no": 17, "par": 4, "stroke_index": 8},
      {"hole_no": 18, "par": 4, "stroke_index": 12}
    ]'::jsonb
  )
  ON CONFLICT (course_id, tee_name, gender) DO NOTHING;
  
  RAISE NOTICE 'Yellow Tee created for course_id: %', v_course_id;
END $$;

-- ============================================
-- STEP 3: Create Test Players
-- ============================================
INSERT INTO players (display_name, handicap_index, email) VALUES
('Peter Hansen', 5.2, 'peter@example.com'),
('Marie Nielsen', 12.4, 'marie@example.com'),
('Lars Andersen', 18.7, 'lars@example.com'),
('Anne Sørensen', 24.3, 'anne@example.com'),
('Jens Møller', 9.8, 'jens@example.com')
ON CONFLICT DO NOTHING;

-- ============================================
-- VERIFICATION: Show what we created
-- ============================================
SELECT 
  '📍 COURSE' as category,
  c.name,
  c.city,
  c.country,
  NULL::text as tee_name,
  NULL::int as slope_rating,
  NULL::numeric as course_rating,
  NULL::int as par
FROM courses c
WHERE c.name = 'Nyborg Golf Club'

UNION ALL

SELECT 
  '⛳ TEE' as category,
  c.name,
  NULL::text as city,
  NULL::text as country,
  ct.tee_name,
  ct.slope_rating,
  ct.course_rating,
  ct.par
FROM course_tees ct
JOIN courses c ON c.id = ct.course_id
WHERE c.name = 'Nyborg Golf Club'

UNION ALL

SELECT 
  '🏌️ PLAYERS' as category,
  p.display_name as name,
  NULL::text as city,
  NULL::text as country,
  NULL::text as tee_name,
  NULL::int as slope_rating,
  p.handicap_index as course_rating,
  NULL::int as par
FROM players p
ORDER BY category, name;

-- ============================================
-- BONUS: Show hole details
-- ============================================
SELECT 
  '🕳️ HOLE DETAILS' as info,
  elem->>'hole_no' as hole_no,
  elem->>'par' as par,
  elem->>'stroke_index' as stroke_index
FROM course_tees ct
JOIN courses c ON c.id = ct.course_id,
LATERAL jsonb_array_elements(ct.holes) AS elem
WHERE c.name = 'Nyborg Golf Club'
  AND ct.tee_name = 'Yellow'
ORDER BY (elem->>'hole_no')::int;

-- ============================================
-- SUMMARY
-- ============================================
SELECT 
  '✅ SUMMARY' as status,
  (SELECT COUNT(*) FROM courses WHERE name = 'Nyborg Golf Club') as courses_created,
  (SELECT COUNT(*) FROM course_tees ct JOIN courses c ON c.id = ct.course_id 
   WHERE c.name = 'Nyborg Golf Club') as tees_created,
  (SELECT COUNT(*) FROM players) as total_players;

-- ============================================
-- END OF TEST DATA SETUP
-- ============================================