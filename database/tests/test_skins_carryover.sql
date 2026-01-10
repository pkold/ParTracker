-- ============================================
-- TEST: Skins Carryover Verification
-- ============================================
-- This test creates a round with ACTUAL ties to verify rollover

-- ============================================
-- STEP 1: Create new test round
-- ============================================
DO $$
DECLARE
  v_course_id UUID;
  v_tee_id UUID;
  v_round_id UUID;
  v_peter_id UUID;
  v_marie_id UUID;
  v_lars_id UUID;
BEGIN
  -- Get IDs
  SELECT id INTO v_course_id FROM courses WHERE name = 'Nyborg Golf Club';
  SELECT id INTO v_tee_id FROM course_tees WHERE course_id = v_course_id AND tee_name = 'Yellow';
  SELECT id INTO v_peter_id FROM players WHERE display_name = 'Peter Hansen';
  SELECT id INTO v_marie_id FROM players WHERE display_name = 'Marie Nielsen';
  SELECT id INTO v_lars_id FROM players WHERE display_name = 'Lars Andersen';
  
  -- Create round
  INSERT INTO rounds (
    course_id,
    tee_id,
    created_by,
    holes_played,
    start_hole,
    scoring_format,
    team_mode,
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
    'individual',
    true,
    'net',
    true,  -- Rollover enabled!
    'active'
  )
  RETURNING id INTO v_round_id;
  
  -- Add players with SAME playing handicap for easier ties
  INSERT INTO round_players (round_id, player_id, user_id, role, playing_hcp) VALUES
  (v_round_id, v_peter_id, NULL, 'owner', 10),   -- All same HCP
  (v_round_id, v_marie_id, NULL, 'player', 10),  -- for easier ties
  (v_round_id, v_lars_id, NULL, 'player', 10);
  
  RAISE NOTICE '✅ Carryover test round created: %', v_round_id;
END $$;

-- ============================================
-- STEP 2: Add scores with DESIGNED TIES
-- ============================================
DO $$
DECLARE
  v_round_id UUID;
  v_peter_id UUID;
  v_marie_id UUID;
  v_lars_id UUID;
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
  
  -- Hole 1 (Par 4, SI 11): TIE - all net 4
  -- All players get 1 help stroke (HCP 10 >= SI 11? No, so 0 help)
  -- Wait, SI 11 means they DO get help. Let me recalculate...
  -- HCP 10 >= SI 11? No. So 0 help strokes.
  -- All shoot gross 4 = net 4 → TIE
  INSERT INTO scores (round_id, player_id, hole_no, strokes) VALUES
  (v_round_id, v_peter_id, 1, 4),
  (v_round_id, v_marie_id, 1, 4),
  (v_round_id, v_lars_id, 1, 4);
  
  -- Hole 2 (Par 5, SI 3): TIE - all net 5
  -- HCP 10 >= SI 3? Yes! So 1 help stroke
  -- All shoot gross 6 - 1 = net 5 → TIE
  INSERT INTO scores (round_id, player_id, hole_no, strokes) VALUES
  (v_round_id, v_peter_id, 2, 6),
  (v_round_id, v_marie_id, 2, 6),
  (v_round_id, v_lars_id, 2, 6);
  
  -- Hole 3 (Par 3, SI 17): WINNER - Peter net 3
  -- HCP 10 >= SI 17? No. So 0 help strokes
  -- Peter: 3, Marie: 4, Lars: 4 → Peter wins with 2 carryover!
  INSERT INTO scores (round_id, player_id, hole_no, strokes) VALUES
  (v_round_id, v_peter_id, 3, 3),
  (v_round_id, v_marie_id, 3, 4),
  (v_round_id, v_lars_id, 3, 4);
  
  -- Hole 4 (Par 4, SI 7): TIE - all net 4
  -- HCP 10 >= SI 7? Yes! So 1 help stroke
  -- All shoot gross 5 - 1 = net 4 → TIE
  INSERT INTO scores (round_id, player_id, hole_no, strokes) VALUES
  (v_round_id, v_peter_id, 4, 5),
  (v_round_id, v_marie_id, 4, 5),
  (v_round_id, v_lars_id, 4, 5);
  
  -- Hole 5 (Par 4, SI 13): WINNER - Marie net 4
  -- HCP 10 >= SI 13? No. So 0 help strokes
  -- Peter: 5, Marie: 4, Lars: 5 → Marie wins with 1 carryover!
  INSERT INTO scores (round_id, player_id, hole_no, strokes) VALUES
  (v_round_id, v_peter_id, 5, 5),
  (v_round_id, v_marie_id, 5, 4),
  (v_round_id, v_lars_id, 5, 5);
  
  RAISE NOTICE '✅ Scores added for 5 holes with designed ties';
END $$;

-- ============================================
-- STEP 3: Recalculate round
-- ============================================
DO $$
DECLARE
  v_round_id UUID;
  v_result JSONB;
BEGIN
  -- Get round ID
  SELECT r.id INTO v_round_id 
  FROM rounds r
  JOIN courses c ON c.id = r.course_id
  WHERE c.name = 'Nyborg Golf Club'
  ORDER BY r.created_at DESC
  LIMIT 1;
  
  -- Run the scoring engine!
  SELECT recalculate_round(v_round_id) INTO v_result;
  
  RAISE NOTICE '✅ Recalculation result: %', v_result;
END $$;

-- ============================================
-- STEP 4: Verify skins with carryover
-- ============================================
SELECT 
  '🎯 SKINS CARRYOVER TEST' as section,
  sr.hole_no,
  COALESCE(p.display_name, '🤝 TIE') as winner,
  sr.winning_score as score,
  sr.carryover_value as carry,
  sr.skin_awarded_value as value,
  CASE 
    WHEN sr.winner_player_id IS NULL THEN '→ Carries to next hole'
    ELSE '✅ SKIN WON!'
  END as result
FROM skins_results sr
JOIN rounds r ON r.id = sr.round_id
JOIN courses c ON c.id = r.course_id
LEFT JOIN players p ON p.id = sr.winner_player_id
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
-- Hole 1: TIE (all net 4)    → carry = 0, value = 0
-- Hole 2: TIE (all net 5)    → carry = 0, value = 0
-- Hole 3: Peter wins (net 3) → carry = 2, value = 3 (1 base + 2 carries)
-- Hole 4: TIE (all net 4)    → carry = 0, value = 0
-- Hole 5: Marie wins (net 4) → carry = 1, value = 2 (1 base + 1 carry)
-- ============================================
