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

    // 2. Delete friendships (both directions)
    await supabaseAdmin
      .from('friendships')
      .delete()
      .or(`user_id.eq.${user.id},friend_id.eq.${user.id}`)

    // 3. Delete friend invite codes
    await supabaseAdmin
      .from('friend_invite_codes')
      .delete()
      .eq('user_id', user.id)

    // 4. Delete home courses
    await supabaseAdmin
      .from('home_courses')
      .delete()
      .eq('user_id', user.id)

    // 5. Delete user hidden items
    await supabaseAdmin
      .from('user_hidden_items')
      .delete()
      .eq('user_id', user.id)

    // 6. Delete scores by this player (in all rounds)
    await supabaseAdmin
      .from('scores')
      .delete()
      .eq('player_id', player.id)

    // 7. Remove player from tournament standings and tournament players
    await supabaseAdmin
      .from('tournament_standings')
      .delete()
      .eq('player_id', player.id)

    await supabaseAdmin
      .from('tournament_players')
      .delete()
      .eq('player_id', player.id)

    // 8. Remove player from other users' rounds (remove round_player entries)
    await supabaseAdmin
      .from('round_players')
      .delete()
      .eq('player_id', player.id)

    // 9. Delete rounds created by user (cascades to remaining scores, round_players, etc.)
    await supabaseAdmin
      .from('rounds')
      .delete()
      .eq('created_by', user.id)

    // 8. Delete user consents
    await supabaseAdmin
      .from('user_consents')
      .delete()
      .eq('user_id', user.id)

    // 9. Delete profile photos from storage
    const { data: files } = await supabaseAdmin.storage
      .from('profile-photos')
      .list(user.id)

    if (files && files.length > 0) {
      const filePaths = files.map((f) => `${user.id}/${f.name}`)
      await supabaseAdmin.storage
        .from('profile-photos')
        .remove(filePaths)
    }

    // 10. Anonymize player record (keep for historical round data integrity)
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

    // 11. Delete auth user
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
