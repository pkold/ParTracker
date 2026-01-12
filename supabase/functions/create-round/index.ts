import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

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
    // Create Supabase client
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: req.headers.get('Authorization')! },
        },
      }
    )

    // Get user
    const {
      data: { user },
    } = await supabaseClient.auth.getUser()

    if (!user) {
      throw new Error('Not authenticated')
    }

    // Parse request body
    const body = await req.json()
    const {
      course_id,
      tee_id,
      players, // [{player_id, handicap_index}]
      holes_played = 18,
      start_hole = 1,
      handicap_allowance = 1.0,
      scoring_format = 'stableford',
      team_mode = 'individual',
      team_scoring_mode = 'aggregate',
      skins_enabled = false,
      skins_type = 'net',
      skins_rollover = true,
    } = body

    // Validation
    if (!course_id || !tee_id || !players || players.length === 0) {
      throw new Error('Missing required fields: course_id, tee_id, players')
    }

    // Get course and tee info for handicap calculation
    const { data: tee, error: teeError } = await supabaseClient
      .from('course_tees')
      .select('slope_rating, course_rating, par')
      .eq('id', tee_id)
      .single()

    if (teeError || !tee) {
      throw new Error('Tee not found')
    }

    // Create round
    const { data: round, error: roundError } = await supabaseClient
      .from('rounds')
      .insert({
        course_id,
        tee_id,
        created_by: user.id,
        holes_played,
        start_hole,
        handicap_allowance,
        scoring_format,
        team_mode,
        team_scoring_mode,
        skins_enabled,
        skins_type,
        skins_rollover,
        status: 'active',
      })
      .select()
      .single()

    if (roundError) {
      throw roundError
    }

    // Calculate playing handicaps and add players
    const roundPlayers = []
    for (const player of players) {
      // Calculate playing handicap using WHS formula
      const { data: playingHcp } = await supabaseClient.rpc(
        'calculate_playing_hcp',
        {
          p_handicap_index: player.handicap_index,
          p_slope_rating: tee.slope_rating,
          p_course_rating: tee.course_rating,
          p_par: tee.par,
          p_handicap_allowance: handicap_allowance,
          p_holes_played: holes_played,
        }
      )

      // Insert round_player
      const { data: roundPlayer, error: rpError } = await supabaseClient
        .from('round_players')
        .insert({
          round_id: round.id,
          player_id: player.player_id,
          user_id: player.user_id || null,
          role: player.player_id === user.id ? 'owner' : 'player',
          playing_hcp: playingHcp || 0,
          team_id: player.team_id || null,
        })
        .select()
        .single()

      if (rpError) {
        throw rpError
      }

      roundPlayers.push(roundPlayer)
    }

    // Get initial snapshot
    const { data: snapshot, error: snapshotError } = await supabaseClient.rpc(
      'recalculate_round',
      { p_round_id: round.id }
    )

    return new Response(
      JSON.stringify({
        success: true,
        round_id: round.id,
        round,
        players: roundPlayers,
        snapshot,
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    )
  }
})
