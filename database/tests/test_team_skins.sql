-- ============================================
-- TEST: 2v2 Team Skins
-- ============================================
-- This tests skins in team mode

-- ============================================
-- STEP 1: Create 2v2 round WITH SKINS
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
  
  -- Create round with TEAMS + SKINS
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
    'teams',
    'bestball',
    true,              -- SKINS ENABLED!
    'net',
    true,              -- ROLLOVER ENABLED!
    'active'
  )
  RETURNING id INTO v_round_id;
  
  -- Create teams
  INSERT INTO teams (round_id, name) VALUES
  (v_round_id, 'Team A')
  RETURNING id INTO v_team_a_id;
  
  INSERT INTO teams (round_id, name) VALUES
  (v_round_id, 'Team B')
  RETURNING id INTO v_team_b_id;
  
  -- Add players
  INSERT INTO round_players (round_id, player_id, user_id, role, playing_hcp, team_id) VALUES
  (v_round_id, v_peter_id, NULL, 'owner', 3, v_team_a_id),
  (v_round_id, v_marie_id, NULL, 'player', 10, v_team_a_id),
  (v_round_id, v_lars_id, NULL, 'player', 16, v_team_b_id),
  (v_round_id, v_anne_id, NULL, 'player', 24, v_team_b_id);
  
  RAISE NOTICE '✅ 2v2 Team Skins round created';
END $$;

-- ============================================
-- STEP 2: Add scores with DESIGNED SKINS
-- ============================================
DO $$
DECLARE
  v_round_id UUID;
  v_peter_id UUID;
  v_marie_id UUID;
  v_lars_id UUID;
  v_anne_id UUID;
BEGIN
  SELECT r.id INTO v_round_id 
  FROM rounds r
  JOIN courses c ON c.id = r.course_id
  WHERE c.name = 'Nyborg Golf Club'
  ORDER BY r.created_at DESC
  LIMIT 1;
  
  SELECT id INTO v_peter_id FROM players WHERE display_name = 'Peter Hansen';
  SELECT id INTO v_marie_id FROM players WHERE display_name = 'Marie Nielsen';
  SELECT id INTO v_lars_id FROM players WHERE display_name = 'Lars Andersen';
  SELECT id INTO v_anne_id FROM players WHERE display_name = 'Anne Sørensen';
  
  -- Hole 1 (Par 4, SI 11): TIE
  -- Team A best: Peter 4 (net 4)
  -- Team B best: Lars 5-1=4 (net 4)
  -- Result: TIE
  INSERT INTO scores (round_id, player_id, hole_no, strokes) VALUES
  (v_round_id, v_peter_id, 1, 4),
  (v_round_id, v_marie_id, 1, 5),
  (v_round_id, v_lars_id, 1, 5),
  (v_round_id, v_anne_id, 1, 6);
  
  -- Hole 2 (Par 5, SI 3): TIE
  -- Team A best: Peter 6-1=5 (net 5)
  -- Team B best: Lars 7-1=6, Anne 8-1=7, best=6 (net 6)
  -- Wait, that's not a tie. Let me recalculate...
  -- Team A: Peter 6-1=5, Marie 7-1=6, best=5
  -- Team B: Lars 7-1=6, Anne 8-1=7, best=6
  -- Still not a tie. Let me fix scores...
  -- Team A: Peter 5 (gets 1 help, net 4), Marie 6 (gets 1 help, net 5)
  -- Team B: Lars 5 (gets 1 help, net 4), Anne 7 (gets 1 help, net 6)
  -- Result: Both teams net 4 → TIE
  INSERT INTO scores (round_id, player_id, hole_no, strokes) VALUES
  (v_round_id, v_peter_id, 2, 5),
  (v_round_id, v_marie_id, 2, 6),
  (v_round_id, v_lars_id, 2, 5),
  (v_round_id, v_anne_id, 2, 7);
  
  -- Hole 3 (Par 3, SI 17): Team A WINS
  -- Team A: Peter 3 (net 3), Marie 4 (net 4), best=3
  -- Team B: Lars 4 (net 4), Anne 5-1=4 (net 4), best=4
  -- Result: Team A wins with 2 carryovers → 3 skins!
  INSERT INTO scores (round_id, player_id, hole_no, strokes) VALUES
  (v_round_id, v_peter_id, 3, 3),
  (v_round_id, v_marie_id, 3, 4),
  (v_round_id, v_lars_id, 3, 4),
  (v_round_id, v_anne_id, 3, 5);
  
  -- Hole 4 (Par 4, SI 7): TIE
  -- Team A: Peter 4 (gets 1, net 3), Marie 5 (gets 1, net 4), best=3
  -- Team B: Lars 4 (gets 1, net 3), Anne 5 (gets 2, net 3), best=3
  -- Result: TIE at net 3
  INSERT INTO scores (round_id, player_id, hole_no, strokes) VALUES
  (v_round_id, v_peter_id, 4, 4),
  (v_round_id, v_marie_id, 4, 5),
  (v_round_id, v_lars_id, 4, 4),
  (v_round_id, v_anne_id, 4, 5);
  
  -- Hole 5 (Par 4, SI 13): Team B WINS
  -- Team A: Peter 5 (net 5), Marie 5 (net 5), best=5
  -- Team B: Lars 4 (net 4), Anne 6 (gets 1, net 5), best=4
  -- Result: Team B wins with 1 carryover → 2 skins!
  INSERT INTO scores (round_id, player_id, hole_no, strokes) VALUES
  (v_round_id, v_peter_id, 5, 5),
  (v_round_id, v_marie_id, 5, 5),
  (v_round_id, v_lars_id, 5, 4),
  (v_round_id, v_anne_id, 5, 6);
  
  RAISE NOTICE '✅ Scores added with team skins scenario';
END $$;

-- ============================================
-- STEP 3: Recalculate
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
  RAISE NOTICE '✅ Result: %', v_result;
END $$;

-- ============================================
-- STEP 4: Show team best scores per hole
-- ============================================
SELECT 
  '🎯 TEAM BEST SCORES' as section,
  t.name as team,
  hr.hole_no,
  MIN(hr.net_strokes) as best_net,
  MIN(hr.strokes) as best_gross
FROM hole_results hr
JOIN round_players rp ON rp.round_id = hr.round_id AND rp.player_id = hr.player_id
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
GROUP BY t.name, hr.hole_no
ORDER BY hr.hole_no, t.name;

-- ============================================
-- STEP 5: Show skins results
-- ============================================
SELECT 
  '🏆 TEAM SKINS' as section,
  sr.hole_no,
  CASE 
    WHEN sr.winner_player_id IS NULL AND sr.skin_awarded_value = 0 THEN '🤝 TIE'
    ELSE 'WINNER'
  END as result,
  sr.winning_score as score,
  sr.carryover_value as carry,
  sr.skin_awarded_value as value
FROM skins_results sr
JOIN rounds r ON r.id = sr.round_id
JOIN courses c ON c.id = r.course_id
WHERE c.name = 'Nyborg Golf Club'
  AND r.id = (
    SELECT id FROM rounds 
    WHERE course_id = (SELECT id FROM courses WHERE name = 'Nyborg Golf Club')
    ORDER BY created_at DESC 
    LIMIT 1
  )
ORDER BY sr.hole_no;

-- ============================================
-- EXPECTED RESULTS:
-- ============================================
-- TEAM BEST SCORES:
-- Hole 1: Team A net 4, Team B net 4 → TIE
-- Hole 2: Team A net 4, Team B net 4 → TIE
-- Hole 3: Team A net 3, Team B net 4 → Team A wins (3 skins)
-- Hole 4: Team A net 3, Team B net 3 → TIE
-- Hole 5: Team A net 5, Team B net 4 → Team B wins (2 skins)
--
-- SKINS:
-- Hole 1: TIE, carry=0, value=0
-- Hole 2: TIE, carry=0, value=0
-- Hole 3: WINNER, score=3, carry=2, value=3
-- Hole 4: TIE, carry=0, value=0
-- Hole 5: WINNER, score=4, carry=1, value=2
-- ============================================
