-- ============================================
-- TEST: 2v2 Bestball Team Scoring
-- ============================================
-- This tests team mode with bestball scoring

-- ============================================
-- STEP 1: Create 2v2 bestball round
-- ============================================
DO $$
DECLARE
  v_course_id UUID;
  v_tee_id UUID;
  v_round_id UUID;
  v_peter_id UUID;
  v_marie_id UUID;
  v_lars_id UUID;
  v_anne_id UUID;
  v_team_a_id UUID;
  v_team_b_id UUID;
BEGIN
  -- Get IDs
  SELECT id INTO v_course_id FROM courses WHERE name = 'Nyborg Golf Club';
  SELECT id INTO v_tee_id FROM course_tees WHERE course_id = v_course_id AND tee_name = 'Yellow';
  SELECT id INTO v_peter_id FROM players WHERE display_name = 'Peter Hansen';
  SELECT id INTO v_marie_id FROM players WHERE display_name = 'Marie Nielsen';
  SELECT id INTO v_lars_id FROM players WHERE display_name = 'Lars Andersen';
  SELECT id INTO v_anne_id FROM players WHERE display_name = 'Anne Sørensen';
  
  -- Create round with TEAM MODE
  INSERT INTO rounds (
    course_id,
    tee_id,
    created_by,
    holes_played,
    start_hole,
    scoring_format,
    team_mode,
    team_scoring_mode,
    skins_enabled,
    skins_type,
    skins_rollover,
    status
  )
  VALUES (
    v_course_id,
    v_tee_id,
    v_peter_id,
    18,
    1,
    'stableford',
    'teams',           -- TEAMS MODE!
    'bestball',        -- BESTBALL SCORING!
    false,             -- No skins for now
    'net',
    false,
    'active'
  )
  RETURNING id INTO v_round_id;
  
  -- Create Team A and Team B
  INSERT INTO teams (round_id, name) VALUES
  (v_round_id, 'Team A')
  RETURNING id INTO v_team_a_id;
  
  INSERT INTO teams (round_id, name) VALUES
  (v_round_id, 'Team B')
  RETURNING id INTO v_team_b_id;
  
  -- Add players to teams
  -- Team A: Peter (HCP 3) + Marie (HCP 10)
  -- Team B: Lars (HCP 16) + Anne (HCP 24)
  INSERT INTO round_players (round_id, player_id, user_id, role, playing_hcp, team_id) VALUES
  (v_round_id, v_peter_id, NULL, 'owner', 3, v_team_a_id),
  (v_round_id, v_marie_id, NULL, 'player', 10, v_team_a_id),
  (v_round_id, v_lars_id, NULL, 'player', 16, v_team_b_id),
  (v_round_id, v_anne_id, NULL, 'player', 24, v_team_b_id);
  
  RAISE NOTICE '✅ 2v2 Bestball round created';
  RAISE NOTICE '   Team A: Peter (HCP 3) + Marie (HCP 10)';
  RAISE NOTICE '   Team B: Lars (HCP 16) + Anne (HCP 24)';
  RAISE NOTICE '   Round ID: %', v_round_id;
END $$;

-- ============================================
-- STEP 2: Add scores for 3 holes
-- ============================================
DO $$
DECLARE
  v_round_id UUID;
  v_peter_id UUID;
  v_marie_id UUID;
  v_lars_id UUID;
  v_anne_id UUID;
BEGIN
  -- Get the round we just created
  SELECT r.id INTO v_round_id 
  FROM rounds r
  JOIN courses c ON c.id = r.course_id
  WHERE c.name = 'Nyborg Golf Club'
  ORDER BY r.created_at DESC
  LIMIT 1;
  
  -- Get player IDs
  SELECT id INTO v_peter_id FROM players WHERE display_name = 'Peter Hansen';
  SELECT id INTO v_marie_id FROM players WHERE display_name = 'Marie Nielsen';
  SELECT id INTO v_lars_id FROM players WHERE display_name = 'Lars Andersen';
  SELECT id INTO v_anne_id FROM players WHERE display_name = 'Anne Sørensen';
  
  -- Hole 1 (Par 4, SI 11): 
  -- Team A: Peter 4 (0 help, net 4, 2 pts), Marie 5 (0 help, net 5, 1 pt) → BEST = 2 pts
  -- Team B: Lars 5 (1 help, net 4, 2 pts), Anne 6 (1 help, net 5, 1 pt) → BEST = 2 pts
  -- RESULT: TIE (both teams 2 pts)
  INSERT INTO scores (round_id, player_id, hole_no, strokes) VALUES
  (v_round_id, v_peter_id, 1, 4),
  (v_round_id, v_marie_id, 1, 5),
  (v_round_id, v_lars_id, 1, 5),
  (v_round_id, v_anne_id, 1, 6);
  
  -- Hole 2 (Par 5, SI 3):
  -- Team A: Peter 6 (1 help, net 5, 2 pts), Marie 7 (1 help, net 6, 1 pt) → BEST = 2 pts
  -- Team B: Lars 7 (1 help, net 6, 1 pt), Anne 8 (2 help, net 6, 1 pt) → BEST = 1 pt
  -- RESULT: Team A wins (2 vs 1)
  INSERT INTO scores (round_id, player_id, hole_no, strokes) VALUES
  (v_round_id, v_peter_id, 2, 6),
  (v_round_id, v_marie_id, 2, 7),
  (v_round_id, v_lars_id, 2, 7),
  (v_round_id, v_anne_id, 2, 8);
  
  -- Hole 3 (Par 3, SI 17):
  -- Team A: Peter 3 (0 help, net 3, 2 pts), Marie 4 (0 help, net 4, 1 pt) → BEST = 2 pts
  -- Team B: Lars 3 (0 help, net 3, 2 pts), Anne 4 (1 help, net 3, 2 pts) → BEST = 2 pts
  -- RESULT: TIE (both teams 2 pts)
  INSERT INTO scores (round_id, player_id, hole_no, strokes) VALUES
  (v_round_id, v_peter_id, 3, 3),
  (v_round_id, v_marie_id, 3, 4),
  (v_round_id, v_lars_id, 3, 3),
  (v_round_id, v_anne_id, 3, 4);
  
  RAISE NOTICE '✅ Scores added for 3 holes';
END $$;

-- ============================================
-- STEP 3: Recalculate round
-- ============================================
DO $$
DECLARE
  v_round_id UUID;
  v_result JSONB;
BEGIN
  SELECT r.id INTO v_round_id 
  FROM rounds r
  JOIN courses c ON c.id = r.course_id
  WHERE c.name = 'Nyborg Golf Club'
  ORDER BY r.created_at DESC
  LIMIT 1;
  
  SELECT recalculate_round(v_round_id) INTO v_result;
  
  RAISE NOTICE '✅ Recalculation result: %', v_result;
END $$;

-- ============================================
-- STEP 4: Show individual player results
-- ============================================
SELECT 
  '👤 INDIVIDUAL SCORES' as section,
  t.name as team,
  p.display_name as player,
  rp.playing_hcp as hcp,
  hr.hole_no,
  hr.par,
  hr.strokes as gross,
  hr.strokes_received as help,
  hr.net_strokes as net,
  hr.stableford_points as points
FROM hole_results hr
JOIN players p ON p.id = hr.player_id
JOIN round_players rp ON rp.round_id = hr.round_id AND rp.player_id = p.id
JOIN teams t ON t.id = rp.team_id
JOIN rounds r ON r.id = hr.round_id
JOIN courses c ON c.id = r.course_id
WHERE c.name = 'Nyborg Golf Club'
  AND r.id = (
    SELECT id FROM rounds 
    WHERE course_id = (SELECT id FROM courses WHERE name = 'Nyborg Golf Club')
    ORDER BY created_at DESC 
    LIMIT 1
  )
ORDER BY hr.hole_no, t.name, p.display_name;

-- ============================================
-- STEP 5: Show team results
-- ============================================
SELECT 
  '🏆 TEAM TOTALS' as section,
  t.name as team,
  tr.gross_total,
  tr.net_total,
  tr.stableford_total as points
FROM team_results tr
JOIN teams t ON t.id = tr.team_id
JOIN rounds r ON r.id = tr.round_id
JOIN courses c ON c.id = r.course_id
WHERE c.name = 'Nyborg Golf Club'
  AND r.id = (
    SELECT id FROM rounds 
    WHERE course_id = (SELECT id FROM courses WHERE name = 'Nyborg Golf Club')
    ORDER BY created_at DESC 
    LIMIT 1
  )
ORDER BY tr.stableford_total DESC;

-- ============================================
-- EXPECTED RESULTS:
-- ============================================
-- INDIVIDUAL POINTS:
-- Hole 1: Peter 2, Marie 1, Lars 2, Anne 1
-- Hole 2: Peter 2, Marie 1, Lars 1, Anne 1
-- Hole 3: Peter 2, Marie 1, Lars 2, Anne 2
--
-- BESTBALL (take best per hole per team):
-- Hole 1: Team A = 2, Team B = 2 (tie)
-- Hole 2: Team A = 2, Team B = 1 (A wins)
-- Hole 3: Team A = 2, Team B = 2 (tie)
--
-- TEAM TOTALS:
-- Team A: 2 + 2 + 2 = 6 points
-- Team B: 2 + 1 + 2 = 5 points
-- ============================================
