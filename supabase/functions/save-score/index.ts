import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
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
    } = await supabaseClient.auth.getUser()

    if (!user) {
      throw new Error('Not authenticated')
    }

    const body = await req.json()
    const {
      round_id,
      player_id,
      hole_no,
      strokes,
      client_event_id, // For offline sync idempotency
    } = body

    // Validation
    if (!round_id || !player_id || !hole_no || !strokes) {
      throw new Error('Missing required fields: round_id, player_id, hole_no, strokes')
    }

    // Verify user has access to this round
    const { data: hasAccess } = await supabaseClient.rpc('is_round_member', {
      p_round_id: round_id,
    })

    if (!hasAccess) {
      throw new Error('Not authorized to update this round')
    }

    // Upsert score (insert or update if exists)
    const { error: scoreError } = await supabaseClient
      .from('scores')
      .upsert(
        {
          round_id,
          player_id,
          hole_no,
          strokes,
          client_event_id: client_event_id || null,
          updated_by: user.id,
        },
        {
          onConflict: 'round_id,player_id,hole_no',
        }
      )

    if (scoreError) {
      throw scoreError
    }

    // Recalculate round results
    const { data: snapshot, error: recalcError } = await supabaseClient.rpc(
      'recalculate_round',
      { p_round_id: round_id }
    )

    if (recalcError) {
      throw recalcError
    }

    return new Response(
      JSON.stringify({
        success: true,
        round_id,
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
