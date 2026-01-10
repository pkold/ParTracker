-- ============================================
-- MIGRATION 001: Initial Schema
-- ============================================
-- This creates the foundation tables for FuldNyborg App
-- Run this FIRST before any other migrations

-- ============================================
-- STEP 1: Enable UUID Extension
-- ============================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- STEP 2: PLAYERS TABLE
-- ============================================
CREATE TABLE players (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  display_name TEXT NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  handicap_index NUMERIC(4,1) CHECK (handicap_index >= 0 AND handicap_index <= 54),
  email TEXT,
  phone TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for faster lookups
CREATE INDEX idx_players_user_id ON players(user_id);
CREATE INDEX idx_players_display_name ON players(display_name);

COMMENT ON TABLE players IS 'Golf players with handicap and contact info';
COMMENT ON COLUMN players.handicap_index IS 'WHS handicap index (0-54)';
COMMENT ON COLUMN players.user_id IS 'Link to auth.users (nullable for guest players)';

-- ============================================
-- STEP 3: COURSES TABLE
-- ============================================
CREATE TABLE courses (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  club TEXT,
  city TEXT,
  country TEXT DEFAULT 'Denmark',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_courses_name ON courses(name);

COMMENT ON TABLE courses IS 'Golf courses/clubs';

-- ============================================
-- STEP 4: COURSE TEES (with JSONB holes)
-- ============================================
CREATE TABLE course_tees (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  course_id UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  tee_name TEXT NOT NULL,
  tee_color TEXT,
  gender TEXT NOT NULL DEFAULT 'mixed' CHECK (gender IN ('male','female','mixed')),
  
  -- WHS data for handicap calculation
  slope_rating INT NOT NULL CHECK (slope_rating BETWEEN 55 AND 155),
  course_rating NUMERIC(4,1) NOT NULL CHECK (course_rating BETWEEN 60 AND 80),
  par INT NOT NULL CHECK (par BETWEEN 54 AND 75),
  
  -- All 18 holes stored as JSONB array for performance
  -- Format: [{"hole_no":1,"par":4,"stroke_index":10}, ...]
  holes JSONB NOT NULL,
  
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_course_tees_course ON course_tees(course_id);
CREATE UNIQUE INDEX idx_course_tees_unique ON course_tees(course_id, tee_name, gender);

-- Validate holes JSONB structure
ALTER TABLE course_tees ADD CONSTRAINT validate_holes_json 
CHECK (
  jsonb_typeof(holes) = 'array' 
  AND jsonb_array_length(holes) = 18
);

COMMENT ON TABLE course_tees IS 'Tee-specific data (slope, rating, holes)';
COMMENT ON COLUMN course_tees.holes IS 'JSONB array of 18 holes with par and stroke_index';
COMMENT ON COLUMN course_tees.slope_rating IS 'WHS slope rating (55-155)';
COMMENT ON COLUMN course_tees.course_rating IS 'WHS course rating (60-80)';

-- ============================================
-- STEP 5: APP LOGS (debugging with error_id)
-- ============================================
CREATE TABLE app_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  user_id UUID,
  round_id UUID,
  severity TEXT NOT NULL CHECK (severity IN ('info','warn','error')),
  source TEXT NOT NULL,
  action TEXT NOT NULL,
  message TEXT NOT NULL,
  context_json JSONB,
  stacktrace TEXT,
  error_id UUID
);

CREATE INDEX idx_app_logs_user ON app_logs(user_id);
CREATE INDEX idx_app_logs_round ON app_logs(round_id);
CREATE INDEX idx_app_logs_error_id ON app_logs(error_id);
CREATE INDEX idx_app_logs_created ON app_logs(created_at DESC);

COMMENT ON TABLE app_logs IS 'Centralized logging with error_id for debugging';
COMMENT ON COLUMN app_logs.error_id IS 'Unique ID shown to users for support tickets';
COMMENT ON COLUMN app_logs.severity IS 'info = normal events, warn = potential issues, error = failures';

-- ============================================
-- VERIFICATION QUERIES
-- ============================================
-- Uncomment these to verify migration worked:

-- SELECT 'players table exists' as check, COUNT(*) as count FROM players;
-- SELECT 'courses table exists' as check, COUNT(*) as count FROM courses;
-- SELECT 'course_tees table exists' as check, COUNT(*) as count FROM course_tees;
-- SELECT 'app_logs table exists' as check, COUNT(*) as count FROM app_logs;

-- ============================================
-- END OF MIGRATION 001
-- ============================================