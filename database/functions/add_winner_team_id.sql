-- ============================================
-- FIX: Add winner_team_id to skins_results
-- ============================================

-- Step 1: Add the column
ALTER TABLE skins_results 
ADD COLUMN IF NOT EXISTS winner_team_id UUID REFERENCES teams(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_skins_results_team_winner 
ON skins_results(round_id, winner_team_id) 
WHERE winner_team_id IS NOT NULL;

COMMENT ON COLUMN skins_results.winner_team_id IS 
'Winner team in team mode (NULL in individual mode or if tie)';

-- Step 2: Update recalculate_round() to use winner_team_id
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
  JOIN course_tees ct ON ct.id = v_round.tee_id
  CROSS JOIN LATERAL jsonb_array_elements(ct.holes) as hole_data
  WHERE s.round_id = p_round_id
    AND (hole_data->>'hole_no')::int = s.hole_no;
  
  -- Calculate player totals
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
  
  -- Calculate team results (if team mode = 'teams')
  IF v_round.team_mode = 'teams' THEN
    INSERT INTO team_results (round_id, team_id, gross_total, net_total, stableford_total)
    SELECT
      rp.round_id,
      rp.team_id,
      -- BESTBALL GROSS: Sum of best gross per hole
      (
        SELECT SUM(best_gross)
        FROM (
          SELECT 
            hr2.hole_no,
            MIN(hr2.strokes) as best_gross
          FROM hole_results hr2
          JOIN round_players rp2 ON rp2.round_id = hr2.round_id AND rp2.player_id = hr2.player_id
          WHERE hr2.round_id = rp.round_id
            AND rp2.team_id = rp.team_id
          GROUP BY hr2.hole_no
        ) best_gross_per_hole
      ) as gross_total,
      -- BESTBALL NET: Sum of best net per hole
      (
        SELECT SUM(best_net)
        FROM (
          SELECT 
            hr2.hole_no,
            MIN(hr2.net_strokes) as best_net
          FROM hole_results hr2
          JOIN round_players rp2 ON rp2.round_id = hr2.round_id AND rp2.player_id = hr2.player_id
          WHERE hr2.round_id = rp.round_id
            AND rp2.team_id = rp.team_id
          GROUP BY hr2.hole_no
        ) best_net_per_hole
      ) as net_total,
      -- BESTBALL STABLEFORD: Sum of best points per hole
      CASE v_round.team_scoring_mode
        WHEN 'bestball' THEN (
          SELECT SUM(best_points)
          FROM (
            SELECT 
              hr2.hole_no,
              MAX(hr2.stableford_points) as best_points
            FROM hole_results hr2
            JOIN round_players rp2 ON rp2.round_id = hr2.round_id AND rp2.player_id = hr2.player_id
            WHERE hr2.round_id = rp.round_id
              AND rp2.team_id = rp.team_id
            GROUP BY hr2.hole_no
          ) best_points_per_hole
        )
        WHEN 'aggregate' THEN (
          SELECT SUM(hr2.stableford_points)
          FROM hole_results hr2
          JOIN round_players rp2 ON rp2.round_id = hr2.round_id AND rp2.player_id = hr2.player_id
          WHERE hr2.round_id = rp.round_id
            AND rp2.team_id = rp.team_id
        )
      END as stableford_total
    FROM round_players rp
    WHERE rp.round_id = p_round_id
      AND rp.team_id IS NOT NULL
    GROUP BY rp.round_id, rp.team_id;
  END IF;
  
  -- Calculate skins (if enabled)
  IF v_round.skins_enabled THEN
    -- For TEAMS: compare best team scores per hole
    -- For INDIVIDUAL: compare player scores per hole
    IF v_round.team_mode = 'teams' THEN
      -- TEAM SKINS: Best net/gross per team per hole
      WITH team_best_scores AS (
        SELECT
          hr.round_id,
          hr.hole_no,
          rp.team_id,
          CASE 
            WHEN v_round.skins_type = 'net' THEN MIN(hr.net_strokes)
            ELSE MIN(hr.strokes)
          END as team_score
        FROM hole_results hr
        JOIN round_players rp ON rp.round_id = hr.round_id AND rp.player_id = hr.player_id
        WHERE hr.round_id = p_round_id
        GROUP BY hr.round_id, hr.hole_no, rp.team_id
      ),
      lowest_per_hole AS (
        SELECT
          hole_no,
          MIN(team_score) as lowest_score
        FROM team_best_scores
        GROUP BY hole_no
      ),
      unique_winner AS (
        SELECT
          tbs.hole_no,
          CASE 
            WHEN COUNT(*) = 1 THEN (array_agg(tbs.team_id))[1]
            ELSE NULL
          END as winner_team_id,
          MIN(tbs.team_score) as winning_score
        FROM team_best_scores tbs
        JOIN lowest_per_hole lph ON lph.hole_no = tbs.hole_no 
          AND lph.lowest_score = tbs.team_score
        GROUP BY tbs.hole_no
      )
      INSERT INTO skins_results (round_id, hole_no, winner_player_id, winner_team_id, winning_score, carryover_value, skin_awarded_value)
      SELECT
        p_round_id,
        uw.hole_no,
        NULL,  -- No individual winner in team mode
        uw.winner_team_id,
        uw.winning_score,
        0,
        0
      FROM unique_winner uw;
      
    ELSE
      -- INDIVIDUAL SKINS (original logic)
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
      INSERT INTO skins_results (round_id, hole_no, winner_player_id, winner_team_id, winning_score, carryover_value, skin_awarded_value)
      SELECT
        p_round_id,
        uw.hole_no,
        uw.winner_player_id,
        NULL,  -- No team winner in individual mode
        uw.winning_score,
        0,
        0
      FROM unique_winner uw;
    END IF;
    
    -- Calculate carryovers if rollover enabled (same for both modes)
    IF v_round.skins_rollover THEN
      WITH ordered AS (
        SELECT
          hole_no,
          winner_player_id,
          winner_team_id,
          ROW_NUMBER() OVER (ORDER BY hole_no) AS rn
        FROM skins_results
        WHERE round_id = p_round_id
      ),
      calc AS (
        SELECT
          o.hole_no,
          o.winner_player_id,
          o.winner_team_id,
          (
            SELECT COUNT(*)
            FROM ordered o3
            WHERE o3.rn < o.rn
              AND o3.rn > COALESCE((
                SELECT MAX(o4.rn) 
                FROM ordered o4
                WHERE o4.rn < o.rn 
                  AND (o4.winner_player_id IS NOT NULL OR o4.winner_team_id IS NOT NULL)
              ), 0)
              AND o3.winner_player_id IS NULL
              AND o3.winner_team_id IS NULL
          ) AS carries_since_last_win
        FROM ordered o
      )
      UPDATE skins_results sr
      SET
        carryover_value = CASE
          WHEN sr.winner_player_id IS NULL AND sr.winner_team_id IS NULL THEN 0
          ELSE calc.carries_since_last_win
        END,
        skin_awarded_value = CASE
          WHEN sr.winner_player_id IS NULL AND sr.winner_team_id IS NULL THEN 0
          ELSE (calc.carries_since_last_win + 1)
        END
      FROM calc
      WHERE sr.round_id = p_round_id
        AND sr.hole_no = calc.hole_no;
    ELSE
      UPDATE skins_results
      SET
        carryover_value = 0,
        skin_awarded_value = CASE 
          WHEN winner_player_id IS NULL AND winner_team_id IS NULL THEN 0 
          ELSE 1 
        END
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

SELECT '✅ Added winner_team_id column and updated skins logic' as status;
