-- ============================================
-- FINAL FIX: recalculate_round() 
-- Based on actual database schema
-- ============================================

CREATE OR REPLACE FUNCTION recalculate_round(p_round_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_round RECORD;
  v_result JSONB;
BEGIN
  -- Get round details
  SELECT * INTO v_round FROM rounds WHERE id = p_round_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Round % not found', p_round_id;
  END IF;
  
  -- Clear existing results
  DELETE FROM hole_results WHERE round_id = p_round_id;
  DELETE FROM round_results WHERE round_id = p_round_id;
  DELETE FROM team_results WHERE round_id = p_round_id;
  DELETE FROM skins_results WHERE round_id = p_round_id;
  
  -- Calculate hole-by-hole results
  -- Extract hole data from JSONB array in course_tees
  INSERT INTO hole_results (
    round_id, player_id, hole_no, par, stroke_index,
    strokes, strokes_received, net_strokes, stableford_points
  )
  SELECT
    s.round_id,
    s.player_id,
    s.hole_no,
    (hole_data->>'par')::int as par,
    (hole_data->>'stroke_index')::int as stroke_index,
    s.strokes,
    calculate_strokes_received(
      rp.playing_hcp, 
      (hole_data->>'stroke_index')::int, 
      v_round.holes_played
    ) as strokes_received,
    s.strokes - calculate_strokes_received(
      rp.playing_hcp, 
      (hole_data->>'stroke_index')::int, 
      v_round.holes_played
    ) as net_strokes,
    calculate_stableford_points(
      s.strokes - calculate_strokes_received(
        rp.playing_hcp, 
        (hole_data->>'stroke_index')::int, 
        v_round.holes_played
      ),
      (hole_data->>'par')::int
    ) as stableford_points
  FROM scores s
  JOIN round_players rp ON rp.round_id = s.round_id AND rp.player_id = s.player_id
  JOIN course_tees ct ON ct.id = rp.tee_id
  CROSS JOIN LATERAL jsonb_array_elements(ct.holes) as hole_data
  WHERE s.round_id = p_round_id
    AND (hole_data->>'hole_no')::int = s.hole_no;
  
  -- Calculate player totals (NO holes_played column)
  INSERT INTO round_results (
    round_id, player_id,
    gross_total, net_total, stableford_total
  )
  SELECT
    hr.round_id,
    hr.player_id,
    SUM(hr.strokes),
    SUM(hr.net_strokes),
    SUM(hr.stableford_points)
  FROM hole_results hr
  WHERE hr.round_id = p_round_id
  GROUP BY hr.round_id, hr.player_id;
  
  -- Calculate team results (if team mode = 'teams', NO holes_played column)
  IF v_round.team_mode = 'teams' THEN
    INSERT INTO team_results (round_id, team_id, gross_total, net_total, stableford_total)
    SELECT
      hr.round_id,
      rp.team_id,
      SUM(hr.strokes) as gross_total,
      SUM(hr.net_strokes) as net_total,
      CASE v_round.team_scoring_mode
        WHEN 'bestball' THEN (
          -- Best ball: sum of best stableford per hole
          SELECT SUM(best_per_hole.max_points)
          FROM (
            SELECT 
              hr2.hole_no,
              MAX(hr2.stableford_points) as max_points
            FROM hole_results hr2
            JOIN round_players rp2 ON rp2.round_id = hr2.round_id AND rp2.player_id = hr2.player_id
            WHERE hr2.round_id = hr.round_id
              AND rp2.team_id = rp.team_id
            GROUP BY hr2.hole_no
          ) best_per_hole
        )
        WHEN 'aggregate' THEN SUM(hr.stableford_points)
      END as stableford_total
    FROM hole_results hr
    JOIN round_players rp ON rp.round_id = hr.round_id AND rp.player_id = hr.player_id
    WHERE hr.round_id = p_round_id
      AND rp.team_id IS NOT NULL
    GROUP BY hr.round_id, rp.team_id;
  END IF;
  
  -- Calculate skins (if enabled)
  IF v_round.skins_enabled THEN
    -- Use net_strokes if skins_type = 'net', otherwise use gross strokes
    WITH score_for_skins AS (
      SELECT
        hr.round_id,
        hr.hole_no,
        hr.player_id,
        CASE 
          WHEN v_round.skins_type = 'net' THEN hr.net_strokes
          ELSE hr.strokes
        END as score_for_comparison
      FROM hole_results hr
      WHERE hr.round_id = p_round_id
    ),
    lowest_per_hole AS (
      SELECT
        hole_no,
        MIN(score_for_comparison) as lowest_score
      FROM score_for_skins
      GROUP BY hole_no
    ),
    unique_winner AS (
      SELECT
        sfs.hole_no,
        CASE 
          WHEN COUNT(*) = 1 THEN (array_agg(sfs.player_id))[1]
          ELSE NULL
        END as winner_player_id,
        MIN(sfs.score_for_comparison) as winning_score
      FROM score_for_skins sfs
      JOIN lowest_per_hole lph ON lph.hole_no = sfs.hole_no 
        AND lph.lowest_score = sfs.score_for_comparison
      GROUP BY sfs.hole_no
    )
    INSERT INTO skins_results (round_id, hole_no, winner_player_id, winning_score, carryover_value, skin_awarded_value)
    SELECT
      p_round_id,
      uw.hole_no,
      uw.winner_player_id,
      uw.winning_score,
      0,
      0
    FROM unique_winner uw;
    
    -- Calculate carryovers if rollover enabled
    IF v_round.skins_rollover THEN
      WITH ordered AS (
        SELECT
          hole_no,
          winner_player_id,
          ROW_NUMBER() OVER (ORDER BY hole_no) AS rn
        FROM skins_results
        WHERE round_id = p_round_id
      ),
      calc AS (
        SELECT
          o.hole_no,
          o.winner_player_id,
          (
            SELECT COUNT(*)
            FROM ordered o3
            WHERE o3.rn < o.rn
              AND o3.rn > COALESCE((
                SELECT MAX(o4.rn) 
                FROM ordered o4
                WHERE o4.rn < o.rn AND o4.winner_player_id IS NOT NULL
              ), 0)
              AND o3.winner_player_id IS NULL
          ) AS carries_since_last_win
        FROM ordered o
      )
      UPDATE skins_results sr
      SET
        carryover_value = CASE
          WHEN sr.winner_player_id IS NULL THEN 0
          ELSE calc.carries_since_last_win
        END,
        skin_awarded_value = CASE
          WHEN sr.winner_player_id IS NULL THEN 0
          ELSE (calc.carries_since_last_win + 1)
        END
      FROM calc
      WHERE sr.round_id = p_round_id
        AND sr.hole_no = calc.hole_no;
    ELSE
      UPDATE skins_results
      SET
        carryover_value = 0,
        skin_awarded_value = CASE WHEN winner_player_id IS NULL THEN 0 ELSE 1 END
      WHERE round_id = p_round_id;
    END IF;
  END IF;
  
  -- Return summary
  SELECT jsonb_build_object(
    'round_id', p_round_id,
    'players_calculated', (SELECT COUNT(*) FROM round_results WHERE round_id = p_round_id),
    'holes_calculated', (SELECT COUNT(*) FROM hole_results WHERE round_id = p_round_id),
    'teams_calculated', (SELECT COUNT(*) FROM team_results WHERE round_id = p_round_id),
    'skins_calculated', (SELECT COUNT(*) FROM skins_results WHERE round_id = p_round_id)
  ) INTO v_result;
  
  RETURN v_result;
END;
$$;

SELECT '✅ recalculate_round() updated - matches actual schema' as status;
