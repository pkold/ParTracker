import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { checkRateLimit, rateLimitResponse } from '../_shared/rate-limit.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Create Supabase admin client (bypasses RLS)
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Create user client for auth verification
    const supabaseUser = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: req.headers.get('Authorization')! },
        },
      }
    )

    // Get authenticated user from JWT
    const {
      data: { user },
    } = await supabaseUser.auth.getUser()

    if (!user) {
      throw new Error('Not authenticated')
    }

    // Rate limit: 30 requests per minute per user
    const rl = checkRateLimit(user.id, { maxRequests: 30 })
    if (!rl.allowed) return rateLimitResponse(rl.retryAfterMs!, corsHeaders)

    // Get round_id from URL query parameter
    const url = new URL(req.url)
    const round_id = url.searchParams.get('round_id')

    if (!round_id) {
      throw new Error('Missing required parameter: round_id')
    }

    // Verify user has access to this round (member or friend spectating)
    const { data: hasAccess } = await supabaseAdmin.rpc('is_round_member', {
      p_round_id: round_id,
      p_user_id: user.id,
    })

    if (!hasAccess) {
      // Check if round is visible to friends and user is a friend of the creator
      const { data: round_check } = await supabaseAdmin
        .from('rounds')
        .select('created_by, visible_to_friends')
        .eq('id', round_id)
        .single()

      if (!round_check?.visible_to_friends) {
        throw new Error('Not authorized to view this round')
      }

      const { data: friendship } = await supabaseAdmin
        .from('friendships')
        .select('id')
        .eq('status', 'accepted')
        .or(`and(requester_id.eq.${user.id},addressee_id.eq.${round_check.created_by}),and(requester_id.eq.${round_check.created_by},addressee_id.eq.${user.id})`)
        .limit(1)
        .single()

      if (!friendship) {
        throw new Error('Not authorized to view this round')
      }
    }

    // Get round details
    const { data: round, error: roundError } = await supabaseAdmin
      .from('rounds')
      .select(`
        *,
        course:courses(id, name)
      `)
      .eq('id', round_id)
      .single()

    if (roundError || !round) {
      throw new Error('Round not found')
    }

    // Get players
    const { data: players, error: playersError } = await supabaseAdmin
      .from('round_players')
      .select(`
        *,
        player:players(id, display_name, email)
      `)
      .eq('round_id', round_id)

    if (playersError) {
      throw playersError
    }

    // Get scores
    const { data: scores, error: scoresError } = await supabaseAdmin
      .from('scores')
      .select('*')
      .eq('round_id', round_id)
      .order('hole_no')

    if (scoresError) {
      throw scoresError
    }

    // Get hole results
    const { data: holeResults, error: holeError } = await supabaseAdmin
      .from('hole_results')
      .select('*')
      .eq('round_id', round_id)
      .order('hole_no')

    if (holeError) {
      throw holeError
    }

    // Get round results (player totals)
    const { data: roundResults, error: resultsError } = await supabaseAdmin
      .from('round_results')
      .select('*')
      .eq('round_id', round_id)

    if (resultsError) {
      throw resultsError
    }

    // Get team results (if team mode)
    let teamResults = null
    if (round.team_mode !== 'individual') {
      const { data: teams, error: teamsError } = await supabaseAdmin
        .from('team_results')
        .select('*, team:teams(id, name)')
        .eq('round_id', round_id)

      if (!teamsError) {
        teamResults = teams
      }
    }

    // Get skins results (if enabled)
    let skinsResults = null
    if (round.skins_enabled) {
      const { data: skins, error: skinsError } = await supabaseAdmin
        .from('skins_results')
        .select(`
          *,
          winner_player:players!winner_player_id(id, display_name),
          winner_team:teams!winner_team_id(id, name)
        `)
        .eq('round_id', round_id)
        .order('hole_no')

      if (!skinsError) {
        skinsResults = skins
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        round,
        players,
        scores,
        hole_results: holeResults,
        round_results: roundResults,
        team_results: teamResults,
        skins_results: skinsResults,
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