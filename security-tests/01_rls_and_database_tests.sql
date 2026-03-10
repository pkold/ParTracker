-- ============================================================
-- ParTracker Security Test Suite — SQL Database Tests
-- Run via: supabase db query --file security-tests/01_rls_and_database_tests.sql
-- Or paste into Supabase SQL Editor
-- ============================================================

-- TEST 1: RLS enabled on all critical tables
SELECT
  t.table_name,
  CASE WHEN c.relrowsecurity THEN '✅ PASS' ELSE '❌ FAIL - RLS disabled!' END AS rls_enabled
FROM information_schema.tables t
JOIN pg_class c ON c.relname = t.table_name
WHERE t.table_schema = 'public'
  AND t.table_type = 'BASE TABLE'
  AND t.table_name IN (
    'players','rounds','round_players','scores','course_tees',
    'courses','friendships','friend_invite_codes','tournaments',
    'tournament_players','tournament_rounds','tournament_standings',
    'user_consents','skins_results','hole_results','round_results',
    'user_hidden_items','home_courses','contact_messages'
  )
ORDER BY t.table_name;

-- TEST 2: RLS policy count per table
SELECT
  tablename,
  COUNT(*) AS policy_count,
  CASE WHEN COUNT(*) > 0 THEN '✅ PASS' ELSE '❌ FAIL - no policies!' END AS has_policies
FROM pg_policies
WHERE schemaname = 'public'
GROUP BY tablename
ORDER BY tablename;

-- TEST 3: Critical functions exist and have correct security
SELECT
  p.proname AS function_name,
  '✅ EXISTS' AS exists,
  CASE WHEN p.prosecdef THEN '✅ SECURITY DEFINER' ELSE '⚠️ SECURITY INVOKER' END AS security_type
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'is_round_member',
    'calculate_playing_hcp',
    'calculate_stableford_points',
    'recalculate_round'
  );

-- TEST 4: Report any critical functions that are MISSING
SELECT
  f.expected_function AS function_name,
  '❌ MISSING' AS status
FROM (
  VALUES
    ('is_round_member'),
    ('calculate_playing_hcp'),
    ('calculate_stableford_points'),
    ('recalculate_round')
) AS f(expected_function)
WHERE NOT EXISTS (
  SELECT 1 FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = f.expected_function
);

-- TEST 5: Schema correctness checks
SELECT test_name, result FROM (

  SELECT 'no_is_guest_column_anywhere' AS test_name,
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM information_schema.columns WHERE column_name = 'is_guest' AND table_schema = 'public'
    ) THEN '✅ PASS' ELSE '❌ FAIL - is_guest column found in schema!' END AS result

  UNION ALL SELECT 'gender_column_on_players',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'players' AND column_name = 'gender'
    ) THEN '✅ PASS' ELSE '❌ FAIL' END

  UNION ALL SELECT 'gender_check_constraint_on_players',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.check_constraints cc
      JOIN information_schema.constraint_column_usage ccu ON cc.constraint_name = ccu.constraint_name
      WHERE ccu.table_name = 'players' AND ccu.column_name = 'gender'
    ) THEN '✅ PASS' ELSE '⚠️ WARN - no CHECK constraint on gender' END

  UNION ALL SELECT 'tees_have_slope_rating_male',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'course_tees' AND column_name = 'slope_rating_male'
    ) THEN '✅ PASS' ELSE '❌ FAIL' END

  UNION ALL SELECT 'tees_have_slope_rating_female',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'course_tees' AND column_name = 'slope_rating_female'
    ) THEN '✅ PASS' ELSE '❌ FAIL' END

  UNION ALL SELECT 'tees_have_course_rating_male',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'course_tees' AND column_name = 'course_rating_male'
    ) THEN '✅ PASS' ELSE '❌ FAIL' END

  UNION ALL SELECT 'tees_have_course_rating_female',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'course_tees' AND column_name = 'course_rating_female'
    ) THEN '✅ PASS' ELSE '❌ FAIL' END

  UNION ALL SELECT 'tees_no_old_slope_rating_column',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'course_tees' AND column_name = 'slope_rating'
    ) THEN '✅ PASS' ELSE '❌ FAIL - old slope_rating column still exists!' END

  UNION ALL SELECT 'tees_no_old_gender_column',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'course_tees' AND column_name = 'gender'
    ) THEN '✅ PASS' ELSE '❌ FAIL - old gender column still on tees!' END

  UNION ALL SELECT 'friendships_table_exists',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'friendships'
    ) THEN '✅ PASS' ELSE '❌ FAIL' END

  UNION ALL SELECT 'friend_invite_codes_table_exists',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'friend_invite_codes'
    ) THEN '✅ PASS' ELSE '❌ FAIL' END

  UNION ALL SELECT 'my_friends_view_exists',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.views WHERE table_schema = 'public' AND table_name = 'my_friends'
    ) THEN '✅ PASS' ELSE '❌ FAIL' END

  UNION ALL SELECT 'user_consents_table_exists',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_consents'
    ) THEN '✅ PASS' ELSE '❌ FAIL' END

  UNION ALL SELECT 'home_courses_table_exists',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'home_courses'
    ) THEN '✅ PASS' ELSE '❌ FAIL' END

  UNION ALL SELECT 'user_hidden_items_table_exists',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_hidden_items'
    ) THEN '✅ PASS' ELSE '❌ FAIL' END

  UNION ALL SELECT 'visible_to_friends_on_rounds',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'rounds' AND column_name = 'visible_to_friends'
    ) THEN '✅ PASS' ELSE '❌ FAIL' END

  UNION ALL SELECT 'unique_constraint_on_scores',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.table_constraints
      WHERE table_name = 'scores' AND (constraint_type = 'UNIQUE' OR constraint_type = 'PRIMARY KEY')
    ) THEN '✅ PASS' ELSE '⚠️ WARN - no unique constraint on scores' END

  UNION ALL SELECT 'foreign_key_round_players_to_rounds',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
      WHERE tc.table_name = 'round_players'
        AND tc.constraint_type = 'FOREIGN KEY'
        AND kcu.column_name = 'round_id'
    ) THEN '✅ PASS' ELSE '❌ FAIL - no FK from round_players to rounds' END

  UNION ALL SELECT 'foreign_key_scores_to_rounds',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
      WHERE tc.table_name = 'scores'
        AND tc.constraint_type = 'FOREIGN KEY'
        AND kcu.column_name = 'round_id'
    ) THEN '✅ PASS' ELSE '❌ FAIL - no FK from scores to rounds' END

  UNION ALL SELECT 'auth_users_not_in_public_schema',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = 'users'
    ) THEN '✅ PASS' ELSE '❌ FAIL - auth.users exposed in public schema!' END

  UNION ALL SELECT 'no_service_key_in_function_bodies',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND pg_get_functiondef(p.oid) ILIKE '%service_role%'
    ) THEN '✅ PASS' ELSE '❌ FAIL - service_role found in a function body!' END

  UNION ALL SELECT 'cascade_delete_scores_on_round_delete',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.referential_constraints rc
      JOIN information_schema.table_constraints tc ON rc.constraint_name = tc.constraint_name
      WHERE tc.table_name = 'scores'
        AND rc.delete_rule = 'CASCADE'
    ) THEN '✅ PASS' ELSE '⚠️ WARN - scores may not cascade-delete with round' END

  UNION ALL SELECT 'tournament_tables_exist',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.tables WHERE table_name = 'tournaments'
    ) AND EXISTS (
      SELECT 1 FROM information_schema.tables WHERE table_name = 'tournament_players'
    ) AND EXISTS (
      SELECT 1 FROM information_schema.tables WHERE table_name = 'tournament_standings'
    ) THEN '✅ PASS' ELSE '❌ FAIL - one or more tournament tables missing' END

) AS tests
ORDER BY result DESC, test_name;

-- TEST 6: Overall summary
SELECT
  COUNT(*) FILTER (WHERE result LIKE '✅%') AS passed,
  COUNT(*) FILTER (WHERE result LIKE '❌%') AS failed,
  COUNT(*) FILTER (WHERE result LIKE '⚠️%') AS warnings
FROM (
  SELECT test_name, result FROM (
    SELECT 'no_is_guest_column_anywhere' AS test_name,
      CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE column_name = 'is_guest' AND table_schema = 'public')
      THEN '✅ PASS' ELSE '❌ FAIL' END AS result
    UNION ALL SELECT 'gender_column_on_players',
      CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'players' AND column_name = 'gender')
      THEN '✅ PASS' ELSE '❌ FAIL' END
    UNION ALL SELECT 'tees_no_old_slope_rating',
      CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'course_tees' AND column_name = 'slope_rating')
      THEN '✅ PASS' ELSE '❌ FAIL' END
    UNION ALL SELECT 'friendships_exists',
      CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'friendships')
      THEN '✅ PASS' ELSE '❌ FAIL' END
    UNION ALL SELECT 'visible_to_friends_exists',
      CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'rounds' AND column_name = 'visible_to_friends')
      THEN '✅ PASS' ELSE '❌ FAIL' END
  ) s
) summary;
