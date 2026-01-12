


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."calculate_playing_hcp"("p_handicap_index" numeric, "p_slope_rating" integer, "p_course_rating" numeric, "p_par" integer, "p_handicap_allowance" numeric DEFAULT 1.0, "p_holes_played" integer DEFAULT 18) RETURNS integer
    LANGUAGE "sql" IMMUTABLE
    AS $$
  SELECT ROUND(
    (p_handicap_index * (p_slope_rating::numeric / 113.0) + (p_course_rating - p_par))
    * p_handicap_allowance
    * (p_holes_played::numeric / 18.0)
  )::INT;
$$;


ALTER FUNCTION "public"."calculate_playing_hcp"("p_handicap_index" numeric, "p_slope_rating" integer, "p_course_rating" numeric, "p_par" integer, "p_handicap_allowance" numeric, "p_holes_played" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."calculate_playing_hcp"("p_handicap_index" numeric, "p_slope_rating" integer, "p_course_rating" numeric, "p_par" integer, "p_handicap_allowance" numeric, "p_holes_played" integer) IS 'WHS formula: (HI × (SR/113) + (CR - Par)) × Allowance × (Holes/18)';



CREATE OR REPLACE FUNCTION "public"."calculate_stableford_points"("p_net_strokes" integer, "p_par" integer) RETURNS integer
    LANGUAGE "sql" IMMUTABLE
    AS $$
  SELECT GREATEST(0, 2 + (p_par - p_net_strokes));
$$;


ALTER FUNCTION "public"."calculate_stableford_points"("p_net_strokes" integer, "p_par" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."calculate_stableford_points"("p_net_strokes" integer, "p_par" integer) IS 'Stableford: 0=+3 or worse, 1=+2, 2=+1/par, 3=-1, 4=-2, 5=-3, etc.';



CREATE OR REPLACE FUNCTION "public"."calculate_strokes_received"("p_playing_hcp" integer, "p_stroke_index" integer, "p_holes_played" integer DEFAULT 18) RETURNS integer
    LANGUAGE "sql" IMMUTABLE
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


ALTER FUNCTION "public"."calculate_strokes_received"("p_playing_hcp" integer, "p_stroke_index" integer, "p_holes_played" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."calculate_strokes_received"("p_playing_hcp" integer, "p_stroke_index" integer, "p_holes_played" integer) IS 'Returns handicap strokes for a hole based on playing HCP and stroke index';



CREATE OR REPLACE FUNCTION "public"."is_round_member"("p_round_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM rounds r
    WHERE r.id = p_round_id
      AND (
        r.created_by = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM round_players rp
          WHERE rp.round_id = r.id
            AND rp.user_id = auth.uid()
        )
      )
  );
$$;


ALTER FUNCTION "public"."is_round_member"("p_round_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."is_round_member"("p_round_id" "uuid") IS 'Returns true if current user is owner or member of round';



CREATE OR REPLACE FUNCTION "public"."recalculate_round"("p_round_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."recalculate_round"("p_round_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."recalculate_round"("p_round_id" "uuid") IS 'Deterministic recalculation of all round results from base scores. Can be run multiple times safely.';


SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."app_logs" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid",
    "round_id" "uuid",
    "severity" "text" NOT NULL,
    "source" "text" NOT NULL,
    "action" "text" NOT NULL,
    "message" "text" NOT NULL,
    "context_json" "jsonb",
    "stacktrace" "text",
    "error_id" "uuid",
    CONSTRAINT "app_logs_severity_check" CHECK (("severity" = ANY (ARRAY['info'::"text", 'warn'::"text", 'error'::"text"])))
);


ALTER TABLE "public"."app_logs" OWNER TO "postgres";


COMMENT ON TABLE "public"."app_logs" IS 'Centralized logging with error_id for debugging';



COMMENT ON COLUMN "public"."app_logs"."severity" IS 'info = normal events, warn = potential issues, error = failures';



COMMENT ON COLUMN "public"."app_logs"."error_id" IS 'Unique ID shown to users for support tickets';



CREATE TABLE IF NOT EXISTS "public"."course_tees" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "course_id" "uuid" NOT NULL,
    "tee_name" "text" NOT NULL,
    "tee_color" "text",
    "gender" "text" DEFAULT 'mixed'::"text" NOT NULL,
    "slope_rating" integer NOT NULL,
    "course_rating" numeric(4,1) NOT NULL,
    "par" integer NOT NULL,
    "holes" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "course_tees_course_rating_check" CHECK ((("course_rating" >= (60)::numeric) AND ("course_rating" <= (80)::numeric))),
    CONSTRAINT "course_tees_gender_check" CHECK (("gender" = ANY (ARRAY['male'::"text", 'female'::"text", 'mixed'::"text"]))),
    CONSTRAINT "course_tees_par_check" CHECK ((("par" >= 54) AND ("par" <= 75))),
    CONSTRAINT "course_tees_slope_rating_check" CHECK ((("slope_rating" >= 55) AND ("slope_rating" <= 155))),
    CONSTRAINT "validate_holes_json" CHECK ((("jsonb_typeof"("holes") = 'array'::"text") AND ("jsonb_array_length"("holes") = 18)))
);


ALTER TABLE "public"."course_tees" OWNER TO "postgres";


COMMENT ON TABLE "public"."course_tees" IS 'Tee-specific data (slope, rating, holes)';



COMMENT ON COLUMN "public"."course_tees"."slope_rating" IS 'WHS slope rating (55-155)';



COMMENT ON COLUMN "public"."course_tees"."course_rating" IS 'WHS course rating (60-80)';



COMMENT ON COLUMN "public"."course_tees"."holes" IS 'JSONB array of 18 holes with par and stroke_index';



CREATE TABLE IF NOT EXISTS "public"."courses" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "club" "text",
    "city" "text",
    "country" "text" DEFAULT 'Denmark'::"text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."courses" OWNER TO "postgres";


COMMENT ON TABLE "public"."courses" IS 'Golf courses/clubs';



CREATE TABLE IF NOT EXISTS "public"."hole_results" (
    "round_id" "uuid" NOT NULL,
    "player_id" "uuid" NOT NULL,
    "hole_no" integer NOT NULL,
    "strokes" integer NOT NULL,
    "par" integer NOT NULL,
    "stroke_index" integer NOT NULL,
    "strokes_received" integer NOT NULL,
    "net_strokes" integer NOT NULL,
    "stableford_points" integer NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "hole_results_hole_no_check" CHECK ((("hole_no" >= 1) AND ("hole_no" <= 18)))
);


ALTER TABLE "public"."hole_results" OWNER TO "postgres";


COMMENT ON TABLE "public"."hole_results" IS 'Calculated results per hole (derived from scores)';



COMMENT ON COLUMN "public"."hole_results"."strokes_received" IS 'Handicap strokes allocated to this hole';



COMMENT ON COLUMN "public"."hole_results"."net_strokes" IS 'strokes - strokes_received';



COMMENT ON COLUMN "public"."hole_results"."stableford_points" IS 'Points earned (max(0, 2 + (par - net_strokes)))';



CREATE TABLE IF NOT EXISTS "public"."players" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "display_name" "text" NOT NULL,
    "user_id" "uuid",
    "handicap_index" numeric(4,1),
    "email" "text",
    "phone" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "players_handicap_index_check" CHECK ((("handicap_index" >= (0)::numeric) AND ("handicap_index" <= (54)::numeric)))
);


ALTER TABLE "public"."players" OWNER TO "postgres";


COMMENT ON TABLE "public"."players" IS 'Golf players with handicap and contact info';



COMMENT ON COLUMN "public"."players"."user_id" IS 'Link to auth.users (nullable for guest players)';



COMMENT ON COLUMN "public"."players"."handicap_index" IS 'WHS handicap index (0-54)';



CREATE TABLE IF NOT EXISTS "public"."round_players" (
    "round_id" "uuid" NOT NULL,
    "player_id" "uuid" NOT NULL,
    "user_id" "uuid",
    "role" "text" DEFAULT 'player'::"text" NOT NULL,
    "playing_hcp" integer NOT NULL,
    "team_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "round_players_playing_hcp_check" CHECK ((("playing_hcp" >= 0) AND ("playing_hcp" <= 54))),
    CONSTRAINT "round_players_role_check" CHECK (("role" = ANY (ARRAY['owner'::"text", 'scorekeeper'::"text", 'player'::"text", 'viewer'::"text"])))
);


ALTER TABLE "public"."round_players" OWNER TO "postgres";


COMMENT ON TABLE "public"."round_players" IS 'Links players to rounds with role and playing handicap';



COMMENT ON COLUMN "public"."round_players"."role" IS 'owner = creator, scorekeeper = can write all scores, player = participant, viewer = read-only';



COMMENT ON COLUMN "public"."round_players"."playing_hcp" IS 'Calculated WHS playing handicap for this round/tee';



CREATE TABLE IF NOT EXISTS "public"."round_results" (
    "round_id" "uuid" NOT NULL,
    "player_id" "uuid" NOT NULL,
    "gross_total" integer NOT NULL,
    "net_total" integer NOT NULL,
    "stableford_total" integer NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."round_results" OWNER TO "postgres";


COMMENT ON TABLE "public"."round_results" IS 'Aggregated totals per player (derived from hole_results)';



COMMENT ON COLUMN "public"."round_results"."gross_total" IS 'Sum of gross strokes';



COMMENT ON COLUMN "public"."round_results"."net_total" IS 'Sum of net strokes';



COMMENT ON COLUMN "public"."round_results"."stableford_total" IS 'Sum of stableford points';



CREATE TABLE IF NOT EXISTS "public"."round_sidegames" (
    "round_id" "uuid" NOT NULL,
    "sidegame_code" "text" NOT NULL,
    "is_enabled" boolean DEFAULT true NOT NULL,
    "custom_value" numeric,
    "custom_rules_json" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."round_sidegames" OWNER TO "postgres";


COMMENT ON TABLE "public"."round_sidegames" IS 'Which sidegames are active for each round';



COMMENT ON COLUMN "public"."round_sidegames"."custom_value" IS 'Override default_value for this round (e.g. 5 kr per sandy)';



CREATE TABLE IF NOT EXISTS "public"."rounds" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "course_id" "uuid" NOT NULL,
    "tee_id" "uuid" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "holes_played" integer NOT NULL,
    "start_hole" integer NOT NULL,
    "handicap_allowance" numeric(4,2) DEFAULT 1.00 NOT NULL,
    "scoring_format" "text" DEFAULT 'stableford'::"text" NOT NULL,
    "team_mode" "text" DEFAULT 'individual'::"text" NOT NULL,
    "team_scoring_mode" "text" DEFAULT 'bestball'::"text" NOT NULL,
    "skins_enabled" boolean DEFAULT false NOT NULL,
    "skins_type" "text" DEFAULT 'net'::"text" NOT NULL,
    "skins_rollover" boolean DEFAULT true NOT NULL,
    "join_code" "text",
    "visibility" "text" DEFAULT 'private'::"text" NOT NULL,
    "status" "text" DEFAULT 'setup'::"text" NOT NULL,
    "started_at" timestamp with time zone,
    "finished_at" timestamp with time zone,
    CONSTRAINT "rounds_handicap_allowance_check" CHECK ((("handicap_allowance" >= (0)::numeric) AND ("handicap_allowance" <= 1.00))),
    CONSTRAINT "rounds_holes_played_check" CHECK (("holes_played" = ANY (ARRAY[9, 18]))),
    CONSTRAINT "rounds_scoring_format_check" CHECK (("scoring_format" = ANY (ARRAY['stableford'::"text", 'strokeplay'::"text"]))),
    CONSTRAINT "rounds_skins_type_check" CHECK (("skins_type" = ANY (ARRAY['gross'::"text", 'net'::"text"]))),
    CONSTRAINT "rounds_start_hole_check" CHECK (("start_hole" = ANY (ARRAY[1, 10]))),
    CONSTRAINT "rounds_status_check" CHECK (("status" = ANY (ARRAY['setup'::"text", 'active'::"text", 'completed'::"text", 'cancelled'::"text"]))),
    CONSTRAINT "rounds_team_mode_check" CHECK (("team_mode" = ANY (ARRAY['individual'::"text", 'teams'::"text"]))),
    CONSTRAINT "rounds_team_scoring_mode_check" CHECK (("team_scoring_mode" = ANY (ARRAY['bestball'::"text", 'aggregate'::"text"]))),
    CONSTRAINT "rounds_visibility_check" CHECK (("visibility" = ANY (ARRAY['private'::"text", 'group'::"text", 'public'::"text"])))
);


ALTER TABLE "public"."rounds" OWNER TO "postgres";


COMMENT ON TABLE "public"."rounds" IS 'Game sessions with scoring rules and settings';



COMMENT ON COLUMN "public"."rounds"."holes_played" IS '9 or 18 holes';



COMMENT ON COLUMN "public"."rounds"."start_hole" IS '1 (front nine) or 10 (back nine)';



COMMENT ON COLUMN "public"."rounds"."handicap_allowance" IS 'Percentage of handicap to use (0.85 = 85%, 1.0 = 100%)';



COMMENT ON COLUMN "public"."rounds"."join_code" IS 'Code for players to join round (nullable)';



CREATE TABLE IF NOT EXISTS "public"."scores" (
    "round_id" "uuid" NOT NULL,
    "player_id" "uuid" NOT NULL,
    "hole_no" integer NOT NULL,
    "strokes" integer NOT NULL,
    "client_event_id" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    CONSTRAINT "scores_hole_no_check" CHECK ((("hole_no" >= 1) AND ("hole_no" <= 18))),
    CONSTRAINT "scores_strokes_check" CHECK ((("strokes" >= 1) AND ("strokes" <= 20)))
);


ALTER TABLE "public"."scores" OWNER TO "postgres";


COMMENT ON TABLE "public"."scores" IS 'Raw stroke input per hole (source of truth)';



COMMENT ON COLUMN "public"."scores"."strokes" IS 'Gross strokes taken on hole';



COMMENT ON COLUMN "public"."scores"."client_event_id" IS 'UUID for idempotent offline sync (nullable)';



CREATE TABLE IF NOT EXISTS "public"."sidegame_events" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "round_id" "uuid" NOT NULL,
    "sidegame_code" "text" NOT NULL,
    "player_id" "uuid" NOT NULL,
    "hole_no" integer,
    "value" numeric DEFAULT 1 NOT NULL,
    "note" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" NOT NULL,
    "is_auto_detected" boolean DEFAULT false NOT NULL,
    CONSTRAINT "sidegame_events_hole_no_check" CHECK ((("hole_no" >= 1) AND ("hole_no" <= 18)))
);


ALTER TABLE "public"."sidegame_events" OWNER TO "postgres";


COMMENT ON TABLE "public"."sidegame_events" IS 'Individual sidegame occurrences (manual v1, auto v2)';



COMMENT ON COLUMN "public"."sidegame_events"."hole_no" IS 'Nullable for round-level events (e.g. Amerikaner)';



COMMENT ON COLUMN "public"."sidegame_events"."created_by" IS 'User who recorded the event';



COMMENT ON COLUMN "public"."sidegame_events"."is_auto_detected" IS 'False = manual entry, True = auto-detected (v2)';



CREATE TABLE IF NOT EXISTS "public"."sidegame_types" (
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "scoring_mode" "text" NOT NULL,
    "default_value" numeric,
    "rules_json" "jsonb",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "sidegame_types_scoring_mode_check" CHECK (("scoring_mode" = ANY (ARRAY['count'::"text", 'value'::"text"])))
);


ALTER TABLE "public"."sidegame_types" OWNER TO "postgres";


COMMENT ON TABLE "public"."sidegame_types" IS 'Pre-populated with common sidegames';



COMMENT ON COLUMN "public"."sidegame_types"."code" IS 'Unique code identifier (e.g. "sandy", "lay")';



COMMENT ON COLUMN "public"."sidegame_types"."scoring_mode" IS 'count = fixed 1 per event, value = numeric amount';



COMMENT ON COLUMN "public"."sidegame_types"."rules_json" IS 'V2: Auto-detection rules (future)';



CREATE OR REPLACE VIEW "public"."sidegame_totals" AS
 SELECT "e"."round_id",
    "e"."sidegame_code",
    "st"."name" AS "sidegame_name",
    "st"."scoring_mode",
    "e"."player_id",
    "p"."display_name" AS "player_name",
    "count"(*) AS "event_count",
    "sum"("e"."value") AS "total_value"
   FROM (("public"."sidegame_events" "e"
     JOIN "public"."sidegame_types" "st" ON (("st"."code" = "e"."sidegame_code")))
     JOIN "public"."players" "p" ON (("p"."id" = "e"."player_id")))
  GROUP BY "e"."round_id", "e"."sidegame_code", "st"."name", "st"."scoring_mode", "e"."player_id", "p"."display_name";


ALTER VIEW "public"."sidegame_totals" OWNER TO "postgres";


COMMENT ON VIEW "public"."sidegame_totals" IS 'Aggregated sidegame statistics per player per round';



CREATE TABLE IF NOT EXISTS "public"."skins_results" (
    "round_id" "uuid" NOT NULL,
    "hole_no" integer NOT NULL,
    "winner_player_id" "uuid",
    "winning_score" integer,
    "carryover_value" numeric DEFAULT 0 NOT NULL,
    "skin_awarded_value" numeric DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "winner_team_id" "uuid",
    CONSTRAINT "skins_results_hole_no_check" CHECK ((("hole_no" >= 1) AND ("hole_no" <= 18)))
);


ALTER TABLE "public"."skins_results" OWNER TO "postgres";


COMMENT ON TABLE "public"."skins_results" IS 'Skin winners per hole with rollover tracking';



COMMENT ON COLUMN "public"."skins_results"."winner_player_id" IS 'NULL if tie (no winner)';



COMMENT ON COLUMN "public"."skins_results"."carryover_value" IS 'Accumulated carryover from previous ties';



COMMENT ON COLUMN "public"."skins_results"."skin_awarded_value" IS 'Total value awarded (carryover + 1)';



COMMENT ON COLUMN "public"."skins_results"."winner_team_id" IS 'Winner team in team mode (NULL in individual mode or if tie)';



CREATE TABLE IF NOT EXISTS "public"."team_results" (
    "round_id" "uuid" NOT NULL,
    "team_id" "uuid" NOT NULL,
    "gross_total" integer NOT NULL,
    "net_total" integer NOT NULL,
    "stableford_total" integer NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."team_results" OWNER TO "postgres";


COMMENT ON TABLE "public"."team_results" IS 'Aggregated team totals (bestball or aggregate mode)';



CREATE TABLE IF NOT EXISTS "public"."teams" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "round_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."teams" OWNER TO "postgres";


COMMENT ON TABLE "public"."teams" IS 'Team groupings within a round';



CREATE TABLE IF NOT EXISTS "public"."tournament_players" (
    "tournament_id" "uuid" NOT NULL,
    "player_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."tournament_players" OWNER TO "postgres";


COMMENT ON TABLE "public"."tournament_players" IS 'Player registrations for tournaments';



CREATE TABLE IF NOT EXISTS "public"."tournament_rounds" (
    "tournament_id" "uuid" NOT NULL,
    "round_id" "uuid" NOT NULL,
    "round_no" integer NOT NULL,
    "weight" numeric DEFAULT 1.0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."tournament_rounds" OWNER TO "postgres";


COMMENT ON TABLE "public"."tournament_rounds" IS 'Links rounds to tournaments with ordering';



COMMENT ON COLUMN "public"."tournament_rounds"."round_no" IS 'Sequential number (1, 2, 3...) for sorting';



COMMENT ON COLUMN "public"."tournament_rounds"."weight" IS 'Multiplier for scoring (e.g. 1.5 for final round)';



CREATE OR REPLACE VIEW "public"."tournament_round_wins" AS
 WITH "round_rankings" AS (
         SELECT "tr"."tournament_id",
            "tr"."round_id",
            "rr"."player_id",
            "rr"."stableford_total",
            "rank"() OVER (PARTITION BY "tr"."tournament_id", "tr"."round_id" ORDER BY "rr"."stableford_total" DESC) AS "rank"
           FROM ("public"."tournament_rounds" "tr"
             JOIN "public"."round_results" "rr" ON (("rr"."round_id" = "tr"."round_id")))
        )
 SELECT "tournament_id",
    "player_id",
    "count"(*) FILTER (WHERE ("rank" = 1)) AS "rounds_won",
    "count"(*) AS "rounds_played"
   FROM "round_rankings"
  GROUP BY "tournament_id", "player_id";


ALTER VIEW "public"."tournament_round_wins" OWNER TO "postgres";


COMMENT ON VIEW "public"."tournament_round_wins" IS 'Count of rounds won per player in tournaments';



CREATE OR REPLACE VIEW "public"."tournament_sidegame_totals" AS
 SELECT "tr"."tournament_id",
    "e"."sidegame_code",
    "st"."name" AS "sidegame_name",
    "e"."player_id",
    "p"."display_name" AS "player_name",
    "count"(*) AS "event_count",
    "sum"("e"."value") AS "total_value"
   FROM ((("public"."tournament_rounds" "tr"
     JOIN "public"."sidegame_events" "e" ON (("e"."round_id" = "tr"."round_id")))
     JOIN "public"."sidegame_types" "st" ON (("st"."code" = "e"."sidegame_code")))
     JOIN "public"."players" "p" ON (("p"."id" = "e"."player_id")))
  GROUP BY "tr"."tournament_id", "e"."sidegame_code", "st"."name", "e"."player_id", "p"."display_name";


ALTER VIEW "public"."tournament_sidegame_totals" OWNER TO "postgres";


COMMENT ON VIEW "public"."tournament_sidegame_totals" IS 'Sidegame event totals per player in tournaments';



CREATE OR REPLACE VIEW "public"."tournament_skins_totals" AS
 SELECT "tr"."tournament_id",
    "sr"."winner_player_id" AS "player_id",
    "p"."display_name" AS "player_name",
    "sum"("sr"."skin_awarded_value") AS "skins_total_value",
    "count"(*) AS "skins_won"
   FROM (("public"."tournament_rounds" "tr"
     JOIN "public"."skins_results" "sr" ON (("sr"."round_id" = "tr"."round_id")))
     JOIN "public"."players" "p" ON (("p"."id" = "sr"."winner_player_id")))
  WHERE ("sr"."winner_player_id" IS NOT NULL)
  GROUP BY "tr"."tournament_id", "sr"."winner_player_id", "p"."display_name";


ALTER VIEW "public"."tournament_skins_totals" OWNER TO "postgres";


COMMENT ON VIEW "public"."tournament_skins_totals" IS 'Total skins value won per player in tournaments';



CREATE OR REPLACE VIEW "public"."tournament_stableford_totals" AS
 SELECT "tr"."tournament_id",
    "rr"."player_id",
    "p"."display_name" AS "player_name",
    "count"(DISTINCT "tr"."round_id") AS "rounds_played",
    "sum"((("rr"."stableford_total")::numeric * "tr"."weight")) AS "weighted_stableford_total",
    "sum"("rr"."stableford_total") AS "stableford_total"
   FROM (("public"."tournament_rounds" "tr"
     JOIN "public"."round_results" "rr" ON (("rr"."round_id" = "tr"."round_id")))
     JOIN "public"."players" "p" ON (("p"."id" = "rr"."player_id")))
  GROUP BY "tr"."tournament_id", "rr"."player_id", "p"."display_name";


ALTER VIEW "public"."tournament_stableford_totals" OWNER TO "postgres";


COMMENT ON VIEW "public"."tournament_stableford_totals" IS 'Aggregate stableford scores across tournament rounds';



CREATE TABLE IF NOT EXISTS "public"."tournament_standings" (
    "tournament_id" "uuid" NOT NULL,
    "player_id" "uuid" NOT NULL,
    "rounds_played" integer DEFAULT 0 NOT NULL,
    "rounds_won" integer DEFAULT 0 NOT NULL,
    "stableford_total" integer DEFAULT 0 NOT NULL,
    "skins_total_value" numeric DEFAULT 0 NOT NULL,
    "rank" integer,
    "last_updated" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."tournament_standings" OWNER TO "postgres";


COMMENT ON TABLE "public"."tournament_standings" IS 'Materialized leaderboard for performance (updated after each round)';



COMMENT ON COLUMN "public"."tournament_standings"."rank" IS 'Current position in tournament (1 = leader)';



CREATE TABLE IF NOT EXISTS "public"."tournaments" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "rounds_to_count" integer DEFAULT 6 NOT NULL,
    "aggregation_rule" "text" DEFAULT 'sum'::"text" NOT NULL,
    "best_n" integer,
    "start_date" "date",
    "end_date" "date",
    "status" "text" DEFAULT 'setup'::"text" NOT NULL,
    CONSTRAINT "tournaments_aggregation_rule_check" CHECK (("aggregation_rule" = ANY (ARRAY['sum'::"text", 'best_n'::"text", 'average'::"text"]))),
    CONSTRAINT "tournaments_best_n_check" CHECK ((("best_n" IS NULL) OR ("best_n" > 0))),
    CONSTRAINT "tournaments_status_check" CHECK (("status" = ANY (ARRAY['setup'::"text", 'active'::"text", 'completed'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."tournaments" OWNER TO "postgres";


COMMENT ON TABLE "public"."tournaments" IS 'Multi-round tournament definitions';



COMMENT ON COLUMN "public"."tournaments"."rounds_to_count" IS 'How many rounds count toward final standings (e.g. 6)';



COMMENT ON COLUMN "public"."tournaments"."aggregation_rule" IS 'sum = total all rounds, best_n = best N of M rounds';



COMMENT ON COLUMN "public"."tournaments"."best_n" IS 'Used when aggregation_rule = best_n (e.g. best 4 of 6)';



ALTER TABLE ONLY "public"."app_logs"
    ADD CONSTRAINT "app_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."course_tees"
    ADD CONSTRAINT "course_tees_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."courses"
    ADD CONSTRAINT "courses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hole_results"
    ADD CONSTRAINT "hole_results_pkey" PRIMARY KEY ("round_id", "player_id", "hole_no");



ALTER TABLE ONLY "public"."players"
    ADD CONSTRAINT "players_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."round_players"
    ADD CONSTRAINT "round_players_pkey" PRIMARY KEY ("round_id", "player_id");



ALTER TABLE ONLY "public"."round_results"
    ADD CONSTRAINT "round_results_pkey" PRIMARY KEY ("round_id", "player_id");



ALTER TABLE ONLY "public"."round_sidegames"
    ADD CONSTRAINT "round_sidegames_pkey" PRIMARY KEY ("round_id", "sidegame_code");



ALTER TABLE ONLY "public"."rounds"
    ADD CONSTRAINT "rounds_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."scores"
    ADD CONSTRAINT "scores_pkey" PRIMARY KEY ("round_id", "player_id", "hole_no");



ALTER TABLE ONLY "public"."sidegame_events"
    ADD CONSTRAINT "sidegame_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sidegame_types"
    ADD CONSTRAINT "sidegame_types_pkey" PRIMARY KEY ("code");



ALTER TABLE ONLY "public"."skins_results"
    ADD CONSTRAINT "skins_results_pkey" PRIMARY KEY ("round_id", "hole_no");



ALTER TABLE ONLY "public"."team_results"
    ADD CONSTRAINT "team_results_pkey" PRIMARY KEY ("round_id", "team_id");



ALTER TABLE ONLY "public"."teams"
    ADD CONSTRAINT "teams_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tournament_players"
    ADD CONSTRAINT "tournament_players_pkey" PRIMARY KEY ("tournament_id", "player_id");



ALTER TABLE ONLY "public"."tournament_rounds"
    ADD CONSTRAINT "tournament_rounds_pkey" PRIMARY KEY ("tournament_id", "round_id");



ALTER TABLE ONLY "public"."tournament_standings"
    ADD CONSTRAINT "tournament_standings_pkey" PRIMARY KEY ("tournament_id", "player_id");



ALTER TABLE ONLY "public"."tournaments"
    ADD CONSTRAINT "tournaments_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_app_logs_created" ON "public"."app_logs" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_app_logs_error_id" ON "public"."app_logs" USING "btree" ("error_id");



CREATE INDEX "idx_app_logs_round" ON "public"."app_logs" USING "btree" ("round_id");



CREATE INDEX "idx_app_logs_user" ON "public"."app_logs" USING "btree" ("user_id");



CREATE INDEX "idx_course_tees_course" ON "public"."course_tees" USING "btree" ("course_id");



CREATE UNIQUE INDEX "idx_course_tees_unique" ON "public"."course_tees" USING "btree" ("course_id", "tee_name", "gender");



CREATE INDEX "idx_courses_name" ON "public"."courses" USING "btree" ("name");



CREATE INDEX "idx_hole_results_round" ON "public"."hole_results" USING "btree" ("round_id");



CREATE INDEX "idx_players_display_name" ON "public"."players" USING "btree" ("display_name");



CREATE INDEX "idx_players_user_id" ON "public"."players" USING "btree" ("user_id");



CREATE INDEX "idx_round_players_role" ON "public"."round_players" USING "btree" ("round_id", "role");



CREATE INDEX "idx_round_players_user" ON "public"."round_players" USING "btree" ("user_id");



CREATE INDEX "idx_round_results_round" ON "public"."round_results" USING "btree" ("round_id");



CREATE INDEX "idx_round_results_stableford" ON "public"."round_results" USING "btree" ("round_id", "stableford_total" DESC);



CREATE INDEX "idx_round_sidegames_round" ON "public"."round_sidegames" USING "btree" ("round_id") WHERE ("is_enabled" = true);



CREATE INDEX "idx_rounds_course" ON "public"."rounds" USING "btree" ("course_id");



CREATE INDEX "idx_rounds_created_by" ON "public"."rounds" USING "btree" ("created_by");



CREATE INDEX "idx_rounds_join_code" ON "public"."rounds" USING "btree" ("join_code") WHERE ("join_code" IS NOT NULL);



CREATE UNIQUE INDEX "idx_rounds_join_code_unique" ON "public"."rounds" USING "btree" ("join_code") WHERE ("join_code" IS NOT NULL);



CREATE INDEX "idx_rounds_tee" ON "public"."rounds" USING "btree" ("tee_id");



CREATE UNIQUE INDEX "idx_scores_client_event" ON "public"."scores" USING "btree" ("client_event_id") WHERE ("client_event_id" IS NOT NULL);



CREATE INDEX "idx_scores_round" ON "public"."scores" USING "btree" ("round_id");



CREATE INDEX "idx_sidegame_events_hole" ON "public"."sidegame_events" USING "btree" ("round_id", "hole_no") WHERE ("hole_no" IS NOT NULL);



CREATE INDEX "idx_sidegame_events_player" ON "public"."sidegame_events" USING "btree" ("round_id", "player_id");



CREATE INDEX "idx_sidegame_events_round" ON "public"."sidegame_events" USING "btree" ("round_id");



CREATE INDEX "idx_sidegame_events_sidegame" ON "public"."sidegame_events" USING "btree" ("round_id", "sidegame_code");



CREATE INDEX "idx_skins_results_round" ON "public"."skins_results" USING "btree" ("round_id");



CREATE INDEX "idx_skins_results_team_winner" ON "public"."skins_results" USING "btree" ("round_id", "winner_team_id") WHERE ("winner_team_id" IS NOT NULL);



CREATE INDEX "idx_skins_results_winner" ON "public"."skins_results" USING "btree" ("round_id", "winner_player_id") WHERE ("winner_player_id" IS NOT NULL);



CREATE INDEX "idx_team_results_round" ON "public"."team_results" USING "btree" ("round_id");



CREATE INDEX "idx_teams_round" ON "public"."teams" USING "btree" ("round_id");



CREATE INDEX "idx_tournament_players_tournament" ON "public"."tournament_players" USING "btree" ("tournament_id");



CREATE INDEX "idx_tournament_rounds_tournament" ON "public"."tournament_rounds" USING "btree" ("tournament_id", "round_no");



CREATE UNIQUE INDEX "idx_tournament_rounds_unique_no" ON "public"."tournament_rounds" USING "btree" ("tournament_id", "round_no");



CREATE INDEX "idx_tournament_standings_rank" ON "public"."tournament_standings" USING "btree" ("tournament_id", "rank");



CREATE INDEX "idx_tournaments_created_by" ON "public"."tournaments" USING "btree" ("created_by");



CREATE INDEX "idx_tournaments_dates" ON "public"."tournaments" USING "btree" ("start_date", "end_date");



CREATE INDEX "idx_tournaments_status" ON "public"."tournaments" USING "btree" ("status");



ALTER TABLE ONLY "public"."course_tees"
    ADD CONSTRAINT "course_tees_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "public"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sidegame_events"
    ADD CONSTRAINT "fk_round_sidegame" FOREIGN KEY ("round_id", "sidegame_code") REFERENCES "public"."round_sidegames"("round_id", "sidegame_code") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."hole_results"
    ADD CONSTRAINT "hole_results_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."hole_results"
    ADD CONSTRAINT "hole_results_round_id_fkey" FOREIGN KEY ("round_id") REFERENCES "public"."rounds"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."players"
    ADD CONSTRAINT "players_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."round_players"
    ADD CONSTRAINT "round_players_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."round_players"
    ADD CONSTRAINT "round_players_round_id_fkey" FOREIGN KEY ("round_id") REFERENCES "public"."rounds"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."round_players"
    ADD CONSTRAINT "round_players_team_id_fkey" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."round_players"
    ADD CONSTRAINT "round_players_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."round_results"
    ADD CONSTRAINT "round_results_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."round_results"
    ADD CONSTRAINT "round_results_round_id_fkey" FOREIGN KEY ("round_id") REFERENCES "public"."rounds"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."round_sidegames"
    ADD CONSTRAINT "round_sidegames_round_id_fkey" FOREIGN KEY ("round_id") REFERENCES "public"."rounds"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."round_sidegames"
    ADD CONSTRAINT "round_sidegames_sidegame_code_fkey" FOREIGN KEY ("sidegame_code") REFERENCES "public"."sidegame_types"("code") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."rounds"
    ADD CONSTRAINT "rounds_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "public"."courses"("id");



ALTER TABLE ONLY "public"."rounds"
    ADD CONSTRAINT "rounds_tee_id_fkey" FOREIGN KEY ("tee_id") REFERENCES "public"."course_tees"("id");



ALTER TABLE ONLY "public"."scores"
    ADD CONSTRAINT "scores_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."scores"
    ADD CONSTRAINT "scores_round_id_fkey" FOREIGN KEY ("round_id") REFERENCES "public"."rounds"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sidegame_events"
    ADD CONSTRAINT "sidegame_events_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sidegame_events"
    ADD CONSTRAINT "sidegame_events_round_id_fkey" FOREIGN KEY ("round_id") REFERENCES "public"."rounds"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sidegame_events"
    ADD CONSTRAINT "sidegame_events_sidegame_code_fkey" FOREIGN KEY ("sidegame_code") REFERENCES "public"."sidegame_types"("code") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."skins_results"
    ADD CONSTRAINT "skins_results_round_id_fkey" FOREIGN KEY ("round_id") REFERENCES "public"."rounds"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."skins_results"
    ADD CONSTRAINT "skins_results_winner_player_id_fkey" FOREIGN KEY ("winner_player_id") REFERENCES "public"."players"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."skins_results"
    ADD CONSTRAINT "skins_results_winner_team_id_fkey" FOREIGN KEY ("winner_team_id") REFERENCES "public"."teams"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."team_results"
    ADD CONSTRAINT "team_results_round_id_fkey" FOREIGN KEY ("round_id") REFERENCES "public"."rounds"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."team_results"
    ADD CONSTRAINT "team_results_team_id_fkey" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."teams"
    ADD CONSTRAINT "teams_round_id_fkey" FOREIGN KEY ("round_id") REFERENCES "public"."rounds"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tournament_players"
    ADD CONSTRAINT "tournament_players_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tournament_players"
    ADD CONSTRAINT "tournament_players_tournament_id_fkey" FOREIGN KEY ("tournament_id") REFERENCES "public"."tournaments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tournament_rounds"
    ADD CONSTRAINT "tournament_rounds_round_id_fkey" FOREIGN KEY ("round_id") REFERENCES "public"."rounds"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tournament_rounds"
    ADD CONSTRAINT "tournament_rounds_tournament_id_fkey" FOREIGN KEY ("tournament_id") REFERENCES "public"."tournaments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tournament_standings"
    ADD CONSTRAINT "tournament_standings_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tournament_standings"
    ADD CONSTRAINT "tournament_standings_tournament_id_fkey" FOREIGN KEY ("tournament_id") REFERENCES "public"."tournaments"("id") ON DELETE CASCADE;



ALTER TABLE "public"."app_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "app_logs_insert_own" ON "public"."app_logs" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "app_logs_select_own" ON "public"."app_logs" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."course_tees" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "course_tees_select_all" ON "public"."course_tees" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."courses" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "courses_select_all" ON "public"."courses" FOR SELECT TO "authenticated" USING (true);



COMMENT ON POLICY "courses_select_all" ON "public"."courses" IS 'Course data is public (read-only for all)';



ALTER TABLE "public"."hole_results" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hole_results_select_members" ON "public"."hole_results" FOR SELECT TO "authenticated" USING ("public"."is_round_member"("round_id"));



ALTER TABLE "public"."players" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "players_insert_own" ON "public"."players" FOR INSERT TO "authenticated" WITH CHECK ((("user_id" IS NULL) OR ("user_id" = "auth"."uid"())));



CREATE POLICY "players_select_all" ON "public"."players" FOR SELECT TO "authenticated" USING (true);



COMMENT ON POLICY "players_select_all" ON "public"."players" IS 'All authenticated users can see all players (names are public)';



CREATE POLICY "players_update_own" ON "public"."players" FOR UPDATE TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."round_players" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "round_players_modify_owner" ON "public"."round_players" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."rounds" "r"
  WHERE (("r"."id" = "round_players"."round_id") AND ("r"."created_by" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."rounds" "r"
  WHERE (("r"."id" = "round_players"."round_id") AND ("r"."created_by" = "auth"."uid"())))));



CREATE POLICY "round_players_select_members" ON "public"."round_players" FOR SELECT TO "authenticated" USING ("public"."is_round_member"("round_id"));



ALTER TABLE "public"."round_results" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "round_results_select_members" ON "public"."round_results" FOR SELECT TO "authenticated" USING ("public"."is_round_member"("round_id"));



ALTER TABLE "public"."round_sidegames" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "round_sidegames_select_members" ON "public"."round_sidegames" FOR SELECT TO "authenticated" USING ("public"."is_round_member"("round_id"));



ALTER TABLE "public"."rounds" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "rounds_insert_owner" ON "public"."rounds" FOR INSERT TO "authenticated" WITH CHECK (("created_by" = "auth"."uid"()));



CREATE POLICY "rounds_select_members" ON "public"."rounds" FOR SELECT TO "authenticated" USING ("public"."is_round_member"("id"));



COMMENT ON POLICY "rounds_select_members" ON "public"."rounds" IS 'Users can only see rounds they created or are members of';



CREATE POLICY "rounds_update_owner" ON "public"."rounds" FOR UPDATE TO "authenticated" USING (("created_by" = "auth"."uid"())) WITH CHECK (("created_by" = "auth"."uid"()));



ALTER TABLE "public"."scores" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "scores_insert_authorized" ON "public"."scores" FOR INSERT TO "authenticated" WITH CHECK (((EXISTS ( SELECT 1
   FROM "public"."rounds" "r"
  WHERE (("r"."id" = "scores"."round_id") AND ("r"."created_by" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM "public"."round_players" "rp"
  WHERE (("rp"."round_id" = "scores"."round_id") AND ("rp"."user_id" = "auth"."uid"()) AND ("rp"."role" = ANY (ARRAY['owner'::"text", 'scorekeeper'::"text"])))))));



COMMENT ON POLICY "scores_insert_authorized" ON "public"."scores" IS 'Only owner or scorekeeper can write scores';



CREATE POLICY "scores_select_members" ON "public"."scores" FOR SELECT TO "authenticated" USING ("public"."is_round_member"("round_id"));



CREATE POLICY "scores_update_authorized" ON "public"."scores" FOR UPDATE TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."rounds" "r"
  WHERE (("r"."id" = "scores"."round_id") AND ("r"."created_by" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM "public"."round_players" "rp"
  WHERE (("rp"."round_id" = "scores"."round_id") AND ("rp"."user_id" = "auth"."uid"()) AND ("rp"."role" = ANY (ARRAY['owner'::"text", 'scorekeeper'::"text"]))))))) WITH CHECK (((EXISTS ( SELECT 1
   FROM "public"."rounds" "r"
  WHERE (("r"."id" = "scores"."round_id") AND ("r"."created_by" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM "public"."round_players" "rp"
  WHERE (("rp"."round_id" = "scores"."round_id") AND ("rp"."user_id" = "auth"."uid"()) AND ("rp"."role" = ANY (ARRAY['owner'::"text", 'scorekeeper'::"text"])))))));



ALTER TABLE "public"."sidegame_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sidegame_events_delete_creator_or_owner" ON "public"."sidegame_events" FOR DELETE TO "authenticated" USING ((("created_by" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."rounds" "r"
  WHERE (("r"."id" = "sidegame_events"."round_id") AND ("r"."created_by" = "auth"."uid"()))))));



CREATE POLICY "sidegame_events_insert_members" ON "public"."sidegame_events" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_round_member"("round_id") AND ("created_by" = "auth"."uid"())));



CREATE POLICY "sidegame_events_select_members" ON "public"."sidegame_events" FOR SELECT TO "authenticated" USING ("public"."is_round_member"("round_id"));



ALTER TABLE "public"."sidegame_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sidegame_types_select_all" ON "public"."sidegame_types" FOR SELECT TO "authenticated" USING (("is_active" = true));



ALTER TABLE "public"."skins_results" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "skins_results_select_members" ON "public"."skins_results" FOR SELECT TO "authenticated" USING ("public"."is_round_member"("round_id"));



ALTER TABLE "public"."team_results" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "team_results_select_members" ON "public"."team_results" FOR SELECT TO "authenticated" USING ("public"."is_round_member"("round_id"));



ALTER TABLE "public"."teams" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "teams_modify_owner" ON "public"."teams" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."rounds" "r"
  WHERE (("r"."id" = "teams"."round_id") AND ("r"."created_by" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."rounds" "r"
  WHERE (("r"."id" = "teams"."round_id") AND ("r"."created_by" = "auth"."uid"())))));



CREATE POLICY "teams_select_members" ON "public"."teams" FOR SELECT TO "authenticated" USING ("public"."is_round_member"("round_id"));



ALTER TABLE "public"."tournament_players" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tournament_players_select_members" ON "public"."tournament_players" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."tournaments" "t"
  WHERE (("t"."id" = "tournament_players"."tournament_id") AND ("t"."created_by" = "auth"."uid"())))) OR ("player_id" IN ( SELECT "players"."id"
   FROM "public"."players"
  WHERE ("players"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."tournament_rounds" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tournament_rounds_select_members" ON "public"."tournament_rounds" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."tournaments" "t"
  WHERE (("t"."id" = "tournament_rounds"."tournament_id") AND (("t"."created_by" = "auth"."uid"()) OR (EXISTS ( SELECT 1
           FROM "public"."tournament_players" "tp"
          WHERE (("tp"."tournament_id" = "t"."id") AND ("tp"."player_id" IN ( SELECT "players"."id"
                   FROM "public"."players"
                  WHERE ("players"."user_id" = "auth"."uid"())))))))))));



ALTER TABLE "public"."tournament_standings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tournament_standings_select_members" ON "public"."tournament_standings" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."tournaments" "t"
  WHERE (("t"."id" = "tournament_standings"."tournament_id") AND (("t"."created_by" = "auth"."uid"()) OR (EXISTS ( SELECT 1
           FROM "public"."tournament_players" "tp"
          WHERE (("tp"."tournament_id" = "t"."id") AND ("tp"."player_id" IN ( SELECT "players"."id"
                   FROM "public"."players"
                  WHERE ("players"."user_id" = "auth"."uid"())))))))))));



ALTER TABLE "public"."tournaments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tournaments_insert_own" ON "public"."tournaments" FOR INSERT TO "authenticated" WITH CHECK (("created_by" = "auth"."uid"()));



CREATE POLICY "tournaments_select_members" ON "public"."tournaments" FOR SELECT TO "authenticated" USING ((("created_by" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."tournament_players" "tp"
  WHERE (("tp"."tournament_id" = "tournaments"."id") AND ("tp"."player_id" IN ( SELECT "players"."id"
           FROM "public"."players"
          WHERE ("players"."user_id" = "auth"."uid"()))))))));



CREATE POLICY "tournaments_update_own" ON "public"."tournaments" FOR UPDATE TO "authenticated" USING (("created_by" = "auth"."uid"())) WITH CHECK (("created_by" = "auth"."uid"()));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_playing_hcp"("p_handicap_index" numeric, "p_slope_rating" integer, "p_course_rating" numeric, "p_par" integer, "p_handicap_allowance" numeric, "p_holes_played" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_playing_hcp"("p_handicap_index" numeric, "p_slope_rating" integer, "p_course_rating" numeric, "p_par" integer, "p_handicap_allowance" numeric, "p_holes_played" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_playing_hcp"("p_handicap_index" numeric, "p_slope_rating" integer, "p_course_rating" numeric, "p_par" integer, "p_handicap_allowance" numeric, "p_holes_played" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_stableford_points"("p_net_strokes" integer, "p_par" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_stableford_points"("p_net_strokes" integer, "p_par" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_stableford_points"("p_net_strokes" integer, "p_par" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_strokes_received"("p_playing_hcp" integer, "p_stroke_index" integer, "p_holes_played" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_strokes_received"("p_playing_hcp" integer, "p_stroke_index" integer, "p_holes_played" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_strokes_received"("p_playing_hcp" integer, "p_stroke_index" integer, "p_holes_played" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_round_member"("p_round_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_round_member"("p_round_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_round_member"("p_round_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."recalculate_round"("p_round_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."recalculate_round"("p_round_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."recalculate_round"("p_round_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."app_logs" TO "anon";
GRANT ALL ON TABLE "public"."app_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."app_logs" TO "service_role";



GRANT ALL ON TABLE "public"."course_tees" TO "anon";
GRANT ALL ON TABLE "public"."course_tees" TO "authenticated";
GRANT ALL ON TABLE "public"."course_tees" TO "service_role";



GRANT ALL ON TABLE "public"."courses" TO "anon";
GRANT ALL ON TABLE "public"."courses" TO "authenticated";
GRANT ALL ON TABLE "public"."courses" TO "service_role";



GRANT ALL ON TABLE "public"."hole_results" TO "anon";
GRANT ALL ON TABLE "public"."hole_results" TO "authenticated";
GRANT ALL ON TABLE "public"."hole_results" TO "service_role";



GRANT ALL ON TABLE "public"."players" TO "anon";
GRANT ALL ON TABLE "public"."players" TO "authenticated";
GRANT ALL ON TABLE "public"."players" TO "service_role";



GRANT ALL ON TABLE "public"."round_players" TO "anon";
GRANT ALL ON TABLE "public"."round_players" TO "authenticated";
GRANT ALL ON TABLE "public"."round_players" TO "service_role";



GRANT ALL ON TABLE "public"."round_results" TO "anon";
GRANT ALL ON TABLE "public"."round_results" TO "authenticated";
GRANT ALL ON TABLE "public"."round_results" TO "service_role";



GRANT ALL ON TABLE "public"."round_sidegames" TO "anon";
GRANT ALL ON TABLE "public"."round_sidegames" TO "authenticated";
GRANT ALL ON TABLE "public"."round_sidegames" TO "service_role";



GRANT ALL ON TABLE "public"."rounds" TO "anon";
GRANT ALL ON TABLE "public"."rounds" TO "authenticated";
GRANT ALL ON TABLE "public"."rounds" TO "service_role";



GRANT ALL ON TABLE "public"."scores" TO "anon";
GRANT ALL ON TABLE "public"."scores" TO "authenticated";
GRANT ALL ON TABLE "public"."scores" TO "service_role";



GRANT ALL ON TABLE "public"."sidegame_events" TO "anon";
GRANT ALL ON TABLE "public"."sidegame_events" TO "authenticated";
GRANT ALL ON TABLE "public"."sidegame_events" TO "service_role";



GRANT ALL ON TABLE "public"."sidegame_types" TO "anon";
GRANT ALL ON TABLE "public"."sidegame_types" TO "authenticated";
GRANT ALL ON TABLE "public"."sidegame_types" TO "service_role";



GRANT ALL ON TABLE "public"."sidegame_totals" TO "anon";
GRANT ALL ON TABLE "public"."sidegame_totals" TO "authenticated";
GRANT ALL ON TABLE "public"."sidegame_totals" TO "service_role";



GRANT ALL ON TABLE "public"."skins_results" TO "anon";
GRANT ALL ON TABLE "public"."skins_results" TO "authenticated";
GRANT ALL ON TABLE "public"."skins_results" TO "service_role";



GRANT ALL ON TABLE "public"."team_results" TO "anon";
GRANT ALL ON TABLE "public"."team_results" TO "authenticated";
GRANT ALL ON TABLE "public"."team_results" TO "service_role";



GRANT ALL ON TABLE "public"."teams" TO "anon";
GRANT ALL ON TABLE "public"."teams" TO "authenticated";
GRANT ALL ON TABLE "public"."teams" TO "service_role";



GRANT ALL ON TABLE "public"."tournament_players" TO "anon";
GRANT ALL ON TABLE "public"."tournament_players" TO "authenticated";
GRANT ALL ON TABLE "public"."tournament_players" TO "service_role";



GRANT ALL ON TABLE "public"."tournament_rounds" TO "anon";
GRANT ALL ON TABLE "public"."tournament_rounds" TO "authenticated";
GRANT ALL ON TABLE "public"."tournament_rounds" TO "service_role";



GRANT ALL ON TABLE "public"."tournament_round_wins" TO "anon";
GRANT ALL ON TABLE "public"."tournament_round_wins" TO "authenticated";
GRANT ALL ON TABLE "public"."tournament_round_wins" TO "service_role";



GRANT ALL ON TABLE "public"."tournament_sidegame_totals" TO "anon";
GRANT ALL ON TABLE "public"."tournament_sidegame_totals" TO "authenticated";
GRANT ALL ON TABLE "public"."tournament_sidegame_totals" TO "service_role";



GRANT ALL ON TABLE "public"."tournament_skins_totals" TO "anon";
GRANT ALL ON TABLE "public"."tournament_skins_totals" TO "authenticated";
GRANT ALL ON TABLE "public"."tournament_skins_totals" TO "service_role";



GRANT ALL ON TABLE "public"."tournament_stableford_totals" TO "anon";
GRANT ALL ON TABLE "public"."tournament_stableford_totals" TO "authenticated";
GRANT ALL ON TABLE "public"."tournament_stableford_totals" TO "service_role";



GRANT ALL ON TABLE "public"."tournament_standings" TO "anon";
GRANT ALL ON TABLE "public"."tournament_standings" TO "authenticated";
GRANT ALL ON TABLE "public"."tournament_standings" TO "service_role";



GRANT ALL ON TABLE "public"."tournaments" TO "anon";
GRANT ALL ON TABLE "public"."tournaments" TO "authenticated";
GRANT ALL ON TABLE "public"."tournaments" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







