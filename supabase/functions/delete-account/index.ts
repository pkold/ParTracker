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

    const log: string[] = []

    // 1. Get player record
    const { data: player, error: playerErr } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('user_id', user.id)
      .not('email', 'is', null)
      .single()

    if (playerErr || !player) {
      throw new Error(`Player profile not found: ${playerErr?.message ?? 'no rows'}`)
    }
    log.push(`player=${player.id}`)

    // Helper: delete from table and log result
    async function deleteFrom(table: string, column: string, value: string) {
      const { error } = await supabaseAdmin
        .from(table)
        .delete()
        .eq(column, value)
      if (error) {
        log.push(`WARN ${table}: ${error.message}`)
      } else {
        log.push(`OK ${table}`)
      }
    }

    async function deleteFromOr(table: string, filter: string) {
      const { error } = await supabaseAdmin
        .from(table)
        .delete()
        .or(filter)
      if (error) {
        log.push(`WARN ${table}: ${error.message}`)
      } else {
        log.push(`OK ${table}`)
      }
    }

    // 2. Delete friendships (both directions)
    await deleteFromOr('friendships', `requester_id.eq.${user.id},addressee_id.eq.${user.id}`)

    // 3. Delete friend invite codes
    await deleteFrom('friend_invite_codes', 'user_id', user.id)

    // 4. Delete home courses
    await deleteFrom('home_courses', 'user_id', user.id)

    // 5. Delete user hidden items
    await deleteFrom('user_hidden_items', 'user_id', user.id)

    // 6. Delete rounds created by this user (cascades scores, round_players,
    //    hole_results, round_results, skins_results for those rounds)
    await deleteFrom('rounds', 'created_by', user.id)

    // 7. Delete tournaments created by this user
    await deleteFrom('tournaments', 'created_by', user.id)

    // 8. Remove from tournament standings/players (not tied to specific rounds)
    await deleteFrom('tournament_standings', 'player_id', player.id)
    await deleteFrom('tournament_players', 'player_id', player.id)

    // NOTE: scores, hole_results, round_results, skins_results, and round_players
    // for rounds created by OTHER users are intentionally preserved.
    // The player record is anonymized below so they show as "Deleted User".

    // 14. Delete user consents
    await deleteFrom('user_consents', 'user_id', user.id)

    // 15. Delete contact messages
    const { error: contactErr } = await supabaseAdmin
      .from('contact_messages')
      .delete()
      .eq('email', user.email ?? '')
    if (contactErr) log.push(`WARN contact_messages: ${contactErr.message}`)
    else log.push('OK contact_messages')

    // 16. Delete profile photos from storage
    const { data: files } = await supabaseAdmin.storage
      .from('profile-photos')
      .list(user.id)

    if (files && files.length > 0) {
      const filePaths = files.map((f: any) => `${user.id}/${f.name}`)
      await supabaseAdmin.storage
        .from('profile-photos')
        .remove(filePaths)
      log.push(`OK storage (${files.length} files)`)
    } else {
      log.push('OK storage (no files)')
    }

    // 17. Anonymize player record (keep for historical round data integrity)
    const { error: updateErr } = await supabaseAdmin
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
        user_id: null,
      })
      .eq('id', player.id)
    if (updateErr) log.push(`WARN anonymize: ${updateErr.message}`)
    else log.push('OK anonymize')

    // 18. Delete auth user
    const { error: deleteAuthError } = await supabaseAdmin.auth.admin.deleteUser(user.id)
    if (deleteAuthError) {
      log.push(`FAIL auth: ${deleteAuthError.message}`)
      throw new Error(`Failed to delete auth user: ${deleteAuthError.message}. Log: ${log.join(', ')}`)
    }
    log.push('OK auth')

    return new Response(
      JSON.stringify({ success: true, log }),
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
