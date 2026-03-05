-- Migration: Gender-specific tee ratings for WHS handicap calculations
--
-- 1. course_tees: Replace single gender/slope_rating/course_rating columns
--    with gender-specific rating columns (nullable, since some courses only
--    publish ratings for one gender).
-- 2. players: Add nullable gender column for WHS calculations.
-- 3. Migrate existing Nyborg Golf Club tee data to the new columns.

-- ============================================
-- STEP 1: Alter course_tees
-- ============================================

-- First, drop the NOT NULL constraints and checks on the old columns so we can
-- migrate data before dropping them.

-- Add new gender-specific columns
ALTER TABLE course_tees
  ADD COLUMN slope_rating_male INTEGER,
  ADD COLUMN slope_rating_female INTEGER,
  ADD COLUMN course_rating_male NUMERIC(4,1),
  ADD COLUMN course_rating_female NUMERIC(4,1);

-- Migrate existing data: copy current ratings into the male columns
UPDATE course_tees
SET slope_rating_male = slope_rating,
    course_rating_male = course_rating;

-- Drop the old columns (this also drops their constraints)
ALTER TABLE course_tees
  DROP COLUMN gender,
  DROP COLUMN slope_rating,
  DROP COLUMN course_rating;

-- ============================================
-- STEP 2: Alter players
-- ============================================

ALTER TABLE players
  ADD COLUMN gender TEXT CHECK (gender IN ('male', 'female'));
