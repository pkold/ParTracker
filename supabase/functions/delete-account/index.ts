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

    // 1. Get player record
    const { data: player } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('user_id', user.id)
      .not('email', 'is', null)
      .single()

    if (!player) {
      throw new Error('Player profile not found')
    }

    // 2. Delete rounds created by user (cascades to scores, round_players, etc.)
    await supabaseAdmin
      .from('rounds')
      .delete()
      .eq('created_by', user.id)

    // 3. Delete user consents
    await supabaseAdmin
      .from('user_consents')
      .delete()
      .eq('user_id', user.id)

    // 4. Delete profile photos from storage
    const { data: files } = await supabaseAdmin.storage
      .from('profile-photos')
      .list(user.id)

    if (files && files.length > 0) {
      const filePaths = files.map((f) => `${user.id}/${f.name}`)
      await supabaseAdmin.storage
        .from('profile-photos')
        .remove(filePaths)
    }

    // 5. Anonymize player record (keep for historical round data integrity)
    await supabaseAdmin
      .from('players')
      .update({
        display_name: 'Deleted User',
        email: null,
        phone: null,
        avatar_url: null,
        first_name: null,
        last_name: null,
        settings: {},
        handicap_index: null,
      })
      .eq('id', player.id)

    // 6. Delete auth user
    const { error: deleteAuthError } = await supabaseAdmin.auth.admin.deleteUser(user.id)
    if (deleteAuthError) {
      throw deleteAuthError
    }

    return new Response(
      JSON.stringify({ success: true }),
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
