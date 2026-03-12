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
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const supabaseUser = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: req.headers.get('Authorization')! },
        },
      }
    )

    const {
      data: { user },
    } = await supabaseUser.auth.getUser()

    if (!user) {
      throw new Error('Not authenticated')
    }

    // Rate limit: 5 requests per minute per user (heavy operation)
    const rl = checkRateLimit(user.id, { maxRequests: 5 })
    if (!rl.allowed) return rateLimitResponse(rl.retryAfterMs!, corsHeaders)

    // Fetch all user data (GDPR Articles 15 + 20)
    const [
      playerResult,
      roundsResult,
      roundPlayersResult,
      scoresResult,
      roundResultsResult,
      consentsResult,
    ] = await Promise.all([
      supabaseAdmin
        .from('players')
        .select('*')
        .eq('user_id', user.id)
        .not('email', 'is', null)
        .single(),
      supabaseAdmin
        .from('rounds')
        .select('*')
        .eq('created_by', user.id),
      supabaseAdmin
        .from('round_players')
        .select('*')
        .eq('user_id', user.id),
      supabaseAdmin
        .from('scores')
        .select('*')
        .eq('updated_by', user.id),
      supabaseAdmin
        .from('round_results')
        .select('*')
        .eq('player_id', playerResult.data?.id ?? ''),
      supabaseAdmin
        .from('user_consents')
        .select('*')
        .eq('user_id', user.id),
    ])

    const exportData = {
      exported_at: new Date().toISOString(),
      user_id: user.id,
      email: user.email,
      player: playerResult.data,
      rounds_created: roundsResult.data ?? [],
      round_participations: roundPlayersResult.data ?? [],
      scores: scoresResult.data ?? [],
      round_results: roundResultsResult.data ?? [],
      consents: consentsResult.data ?? [],
    }

    return new Response(
      JSON.stringify({ success: true, data: exportData }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    )
  }
})
