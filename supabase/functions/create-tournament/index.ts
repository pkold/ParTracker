import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { createLogger } from '../_shared/log.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rate-limit.ts'

const log = createLogger('create-tournament')

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Create admin client (bypasses RLS for database operations)
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Verify the user from the Authorization header
    const authHeader = req.headers.get('Authorization')!
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token)

    if (userError || !user) {
      throw new Error('Unauthorized')
    }

    // Rate limit: 10 requests per minute per user
    const rl = checkRateLimit(user.id, { maxRequests: 10 })
    if (!rl.allowed) return rateLimitResponse(rl.retryAfterMs!, corsHeaders)

    // Parse the request body
    const {
      name,
      description,
      rounds_to_count,
      aggregation_rule,
      best_n,
      scoring_mode,
      start_date,
      end_date,
      default_course_id,
      default_game_types,
      points_table,
      bonus_config,
      players, // Array of { player_id, team_name? }
    } = await req.json()

    log.info('=== CREATE TOURNAMENT ===')
    log.info('Name:', name, 'Players:', players.length, 'Mode:', scoring_mode)
    log.debug('Created by:', user.id)
    log.debug('Players:', JSON.stringify(players))

    // -------------------------------------------------------
    // STEP 1: Create guest players if needed
    // -------------------------------------------------------
    const processedPlayers = await Promise.all(
      players.map(async (p: any) => {
        if (!p.player_id && p.guest_info) {
          const { data: newGuest, error: guestError } = await supabaseAdmin
            .from('players')
            .insert({
              display_name: p.guest_info.display_name,
              handicap_index: p.guest_info.handicap_index,
              gender: p.guest_info.gender || null,
              user_id: user.id,
            })
            .select()
            .single()

          if (guestError) {
            log.error('Error creating guest player:', guestError)
            throw new Error(`Failed to create guest: ${p.guest_info.display_name}`)
          }

          log.debug('Created guest player:', newGuest.id, newGuest.display_name)
          return { ...p, player_id: newGuest.id }
        }
        return p
      })
    )

    // -------------------------------------------------------
    // STEP 2: Auto-generate points_table if not provided
    // -------------------------------------------------------
    let finalPointsTable = points_table
    if (!finalPointsTable && processedPlayers?.length > 0) {
      const table: { rank: number; points: number }[] = []
      let pts = 100
      for (let i = 1; i <= processedPlayers.length; i++) {
        table.push({ rank: i, points: Math.max(Math.round(pts), 5) })
        pts = pts * 0.7
      }
      finalPointsTable = table
    }

    // -------------------------------------------------------
    // STEP 2: Insert tournament
    // -------------------------------------------------------
    const tournamentInsert: Record<string, any> = {
      name,
      description: description || null,
      created_by: user.id,
      rounds_to_count: rounds_to_count || 6,
      aggregation_rule: aggregation_rule || 'sum',
      best_n: aggregation_rule === 'best_n' ? best_n : null,
      scoring_mode: scoring_mode || 'individual',
      start_date: start_date || null,
      end_date: end_date || null,
      default_course_id: default_course_id || null,
      default_game_types: default_game_types || [],
      points_table: finalPointsTable,
      bonus_config: bonus_config || { round_winner: 10, skins_leader: 5, eagle: 5, hole_in_one: 20, hot_streak: 10 },
      status: 'active',
    }

    log.debug('Tournament insert:', JSON.stringify(tournamentInsert))

    const { data: tournament, error: tournamentError } = await supabaseAdmin
      .from('tournaments')
      .insert(tournamentInsert)
      .select()
      .single()

    if (tournamentError) {
      log.error('Error creating tournament:', tournamentError)
      throw new Error(`Failed to create tournament: ${tournamentError.message}`)
    }

    log.info('Tournament created:', tournament.id)

    // -------------------------------------------------------
    // STEP 3: Insert tournament_players
    // -------------------------------------------------------
    if (processedPlayers && processedPlayers.length > 0) {
      const playersInsert = processedPlayers.map((p: any) => ({
        tournament_id: tournament.id,
        player_id: p.player_id,
        team_name: p.team_name || null,
      }))

      const { error: playersError } = await supabaseAdmin
        .from('tournament_players')
        .insert(playersInsert)

      if (playersError) {
        log.error('Error inserting tournament_players:', playersError)
        throw new Error(`Failed to add players: ${playersError.message}`)
      }

      log.info('Tournament players added:', processedPlayers.length)

      // -------------------------------------------------------
      // STEP 5: Initialize tournament_standings (all zeros)
      // -------------------------------------------------------
      const standingsInsert = processedPlayers.map((p: any) => ({
        tournament_id: tournament.id,
        player_id: p.player_id,
        rounds_played: 0,
        rounds_won: 0,
        stableford_total: 0,
        skins_total_value: 0,
        season_points: 0,
        bonus_points: 0,
        total_points: 0,
        rank: null,
      }))

      const { error: standingsError } = await supabaseAdmin
        .from('tournament_standings')
        .insert(standingsInsert)

      if (standingsError) {
        log.error('Error initializing standings:', standingsError)
        throw new Error(`Failed to initialize standings: ${standingsError.message}`)
      }

      log.debug('Tournament standings initialized')

      // -------------------------------------------------------
      // STEP 6: Initialize tournament_team_standings (if teams)
      // -------------------------------------------------------
      const teamNames = [...new Set(processedPlayers.filter((p: any) => p.team_name).map((p: any) => p.team_name))]

      if (teamNames.length > 0) {
        const teamStandingsInsert = teamNames.map((teamName: string) => ({
          tournament_id: tournament.id,
          team_name: teamName,
          rounds_played: 0,
          season_points: 0,
          bonus_points: 0,
          total_points: 0,
          rank: null,
        }))

        const { error: teamStandingsError } = await supabaseAdmin
          .from('tournament_team_standings')
          .insert(teamStandingsInsert)

        if (teamStandingsError) {
          log.error('Error initializing team standings:', teamStandingsError)
          throw new Error(`Failed to initialize team standings: ${teamStandingsError.message}`)
        }

        log.debug('Team standings initialized for:', teamNames)
      }
    }

    log.info('=== TOURNAMENT CREATED SUCCESSFULLY ===')

    return new Response(
      JSON.stringify({
        success: true,
        tournament_id: tournament.id,
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )
  } catch (error) {
    log.error('=== CREATE TOURNAMENT ERROR ===', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    )
  }
})
