import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { checkRateLimit, rateLimitResponse } from '../_shared/rate-limit.ts'
import { ValidationError, requireUUID, requireString, requireEnum } from '../_shared/validate.ts'

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

    // Rate limit: 20 requests per minute per user
    const rl = checkRateLimit(user.id, { maxRequests: 20 })
    if (!rl.allowed) return rateLimitResponse(rl.retryAfterMs!, corsHeaders)

    const { action, ...params } = await req.json()

    if (!action) {
      throw new Error('Missing required field: action')
    }

    let result: Record<string, unknown>

    switch (action) {
      case 'search_users':
        result = await searchUsers(supabaseAdmin, user.id, params)
        break
      case 'send_request':
        result = await sendRequest(supabaseAdmin, user.id, params)
        break
      case 'respond_request':
        result = await respondRequest(supabaseAdmin, user.id, params)
        break
      case 'unfriend':
        result = await unfriend(supabaseAdmin, user.id, params)
        break
      case 'list_friends':
        result = await listFriends(supabaseAdmin, user.id)
        break
      case 'pending_requests':
        result = await pendingRequests(supabaseAdmin, user.id)
        break
      case 'generate_invite_code':
        result = await generateInviteCode(supabaseAdmin, user.id)
        break
      case 'redeem_invite_code':
        result = await redeemInviteCode(supabaseAdmin, user.id, params)
        break
      default:
        throw new Error(`Unknown action: ${action}`)
    }

    return new Response(
      JSON.stringify({ success: true, ...result }),
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
        status: error instanceof ValidationError ? 422 : 400,
      }
    )
  }
})

// ============================================================
// Action handlers
// ============================================================

async function searchUsers(
  supabaseAdmin: ReturnType<typeof createClient>,
  userId: string,
  params: { query: string }
) {
  const query = requireString(params.query, 'query', 500)
  if (query.length < 2) {
    throw new Error('Search query must be at least 2 characters')
  }

  const searchTerm = `%${query}%`

  // Search players by name or email
  const { data: playerResults, error } = await supabaseAdmin
    .from('players')
    .select('id, user_id, display_name, email, handicap_index')
    .or(`email.ilike.${searchTerm},display_name.ilike.${searchTerm}`)
    .not('email', 'is', null)
    .neq('user_id', userId)
    .limit(10)

  if (error) throw error

  // Also search by club name (via home_courses → courses)
  const { data: clubResults } = await supabaseAdmin
    .from('home_courses')
    .select('user_id, courses(name, club)')
    .ilike('courses.club', searchTerm)

  // Get player info for club matches not already in results
  const existingUserIds = new Set((playerResults || []).map((p: any) => p.user_id))
  const clubUserIds = (clubResults || [])
    .filter((hc: any) => hc.courses && !existingUserIds.has(hc.user_id) && hc.user_id !== userId)
    .map((hc: any) => hc.user_id)

  let clubPlayers: any[] = []
  if (clubUserIds.length > 0) {
    const { data: extraPlayers } = await supabaseAdmin
      .from('players')
      .select('id, user_id, display_name, email, handicap_index')
      .in('user_id', clubUserIds)
      .not('email', 'is', null)
      .limit(10)
    clubPlayers = extraPlayers || []
  }

  // Fetch home course/club for all result users
  const allUsers = [...(playerResults || []), ...clubPlayers]
  const allUserIds = allUsers.map((p: any) => p.user_id)

  let clubMap = new Map<string, string>()
  if (allUserIds.length > 0) {
    const { data: homeCourses } = await supabaseAdmin
      .from('home_courses')
      .select('user_id, courses(club)')
      .in('user_id', allUserIds)

    for (const hc of (homeCourses || [])) {
      if ((hc as any).courses?.club) {
        clubMap.set(hc.user_id, (hc as any).courses.club)
      }
    }
  }

  const users = allUsers.map((p: any) => ({
    ...p,
    club: clubMap.get(p.user_id) || null,
  }))

  return { users }
}

async function sendRequest(
  supabaseAdmin: ReturnType<typeof createClient>,
  userId: string,
  params: { addressee_id: string }
) {
  const addressee_id = requireUUID(params.addressee_id, 'addressee_id')

  if (addressee_id === userId) {
    throw new Error('Cannot send friend request to yourself')
  }

  // Check if friendship already exists in either direction
  const { data: existing } = await supabaseAdmin
    .from('friendships')
    .select('id, status')
    .or(
      `and(requester_id.eq.${userId},addressee_id.eq.${addressee_id}),` +
      `and(requester_id.eq.${addressee_id},addressee_id.eq.${userId})`
    )
    .maybeSingle()

  if (existing) {
    if (existing.status === 'accepted') {
      throw new Error('Already friends')
    }
    if (existing.status === 'pending') {
      throw new Error('Friend request already pending')
    }
    if (existing.status === 'declined') {
      // Allow re-requesting after decline by updating
      const { error } = await supabaseAdmin
        .from('friendships')
        .update({ status: 'pending', updated_at: new Date().toISOString() })
        .eq('id', existing.id)

      if (error) throw error
      return { friendship_id: existing.id }
    }
  }

  const { data, error } = await supabaseAdmin
    .from('friendships')
    .insert({
      requester_id: userId,
      addressee_id: addressee_id,
    })
    .select('id')
    .single()

  if (error) throw error

  return { friendship_id: data.id }
}

async function respondRequest(
  supabaseAdmin: ReturnType<typeof createClient>,
  userId: string,
  params: { friendship_id: string; response: string }
) {
  const friendship_id = requireUUID(params.friendship_id, 'friendship_id')
  const response = requireEnum(params.response, 'response', ['accepted', 'declined'])

  // Verify this request is addressed to the current user and is pending
  const { data: friendship, error: fetchError } = await supabaseAdmin
    .from('friendships')
    .select('id, addressee_id, status')
    .eq('id', friendship_id)
    .single()

  if (fetchError || !friendship) {
    throw new Error('Friend request not found')
  }

  if (friendship.addressee_id !== userId) {
    throw new Error('Not authorized to respond to this request')
  }

  if (friendship.status !== 'pending') {
    throw new Error('This request is no longer pending')
  }

  const { error } = await supabaseAdmin
    .from('friendships')
    .update({
      status: response,
      updated_at: new Date().toISOString(),
    })
    .eq('id', friendship_id)

  if (error) throw error

  return { friendship_id, status: response }
}

async function unfriend(
  supabaseAdmin: ReturnType<typeof createClient>,
  userId: string,
  params: { friendship_id: string }
) {
  const friendship_id = requireUUID(params.friendship_id, 'friendship_id')

  // Verify user is part of this friendship
  const { data: friendship, error: fetchError } = await supabaseAdmin
    .from('friendships')
    .select('id, requester_id, addressee_id')
    .eq('id', friendship_id)
    .single()

  if (fetchError || !friendship) {
    throw new Error('Friendship not found')
  }

  if (friendship.requester_id !== userId && friendship.addressee_id !== userId) {
    throw new Error('Not authorized to remove this friendship')
  }

  const { error } = await supabaseAdmin
    .from('friendships')
    .delete()
    .eq('id', friendship_id)

  if (error) throw error

  return { removed: true }
}

async function listFriends(
  supabaseAdmin: ReturnType<typeof createClient>,
  userId: string
) {
  // Get accepted friendships where user is either requester or addressee
  const { data: friendships, error } = await supabaseAdmin
    .from('friendships')
    .select('id, requester_id, addressee_id, created_at')
    .eq('status', 'accepted')
    .or(`requester_id.eq.${userId},addressee_id.eq.${userId}`)

  if (error) throw error

  if (!friendships || friendships.length === 0) {
    return { friends: [] }
  }

  // Collect the other user's IDs
  const friendUserIds = friendships.map((f) =>
    f.requester_id === userId ? f.addressee_id : f.requester_id
  )

  // Fetch player info for friends
  const { data: players, error: playersError } = await supabaseAdmin
    .from('players')
    .select('id, user_id, display_name, email, phone, handicap_index, gender')
    .in('user_id', friendUserIds)
    .not('email', 'is', null)

  if (playersError) throw playersError

  // Map friendship data with player info
  const friends = friendships.map((f) => {
    const friendUserId = f.requester_id === userId ? f.addressee_id : f.requester_id
    const player = players?.find((p) => p.user_id === friendUserId)
    return {
      friendship_id: f.id,
      since: f.created_at,
      user_id: friendUserId,
      player_id: player?.id ?? null,
      display_name: player?.display_name ?? null,
      email: player?.email ?? null,
      phone: player?.phone ?? null,
      handicap_index: player?.handicap_index ?? null,
      gender: player?.gender ?? null,
    }
  })

  return { friends }
}

async function pendingRequests(
  supabaseAdmin: ReturnType<typeof createClient>,
  userId: string
) {
  // Get pending requests where user is the addressee
  const { data: requests, error } = await supabaseAdmin
    .from('friendships')
    .select('id, requester_id, created_at')
    .eq('status', 'pending')
    .eq('addressee_id', userId)

  if (error) throw error

  if (!requests || requests.length === 0) {
    return { requests: [] }
  }

  const requesterIds = requests.map((r) => r.requester_id)

  const { data: players, error: playersError } = await supabaseAdmin
    .from('players')
    .select('id, user_id, display_name, email, handicap_index')
    .in('user_id', requesterIds)
    .not('email', 'is', null)

  if (playersError) throw playersError

  const pendingList = requests.map((r) => {
    const player = players?.find((p) => p.user_id === r.requester_id)
    return {
      friendship_id: r.id,
      requested_at: r.created_at,
      user_id: r.requester_id,
      player_id: player?.id ?? null,
      display_name: player?.display_name ?? null,
      email: player?.email ?? null,
      handicap_index: player?.handicap_index ?? null,
    }
  })

  return { requests: pendingList }
}

async function generateInviteCode(
  supabaseAdmin: ReturnType<typeof createClient>,
  userId: string
) {
  // Generate a unique code using the DB function
  const { data: code, error: codeError } = await supabaseAdmin
    .rpc('generate_friend_invite_code')

  if (codeError) throw codeError

  // Insert the invite code record
  const { data, error } = await supabaseAdmin
    .from('friend_invite_codes')
    .insert({
      user_id: userId,
      code: code,
    })
    .select('id, code, expires_at')
    .single()

  if (error) throw error

  return { invite_code: data }
}

async function redeemInviteCode(
  supabaseAdmin: ReturnType<typeof createClient>,
  userId: string,
  params: { code: string }
) {
  const code = requireString(params.code, 'code', 20)

  // Look up the invite code
  const { data: invite, error: lookupError } = await supabaseAdmin
    .from('friend_invite_codes')
    .select('id, user_id, code, expires_at, used_by')
    .eq('code', code.toUpperCase().trim())
    .single()

  if (lookupError || !invite) {
    throw new Error('Invalid invite code')
  }

  if (invite.used_by) {
    throw new Error('This invite code has already been used')
  }

  if (new Date(invite.expires_at) < new Date()) {
    throw new Error('This invite code has expired')
  }

  if (invite.user_id === userId) {
    throw new Error('Cannot redeem your own invite code')
  }

  // Check if already friends
  const { data: existing } = await supabaseAdmin
    .from('friendships')
    .select('id, status')
    .or(
      `and(requester_id.eq.${userId},addressee_id.eq.${invite.user_id}),` +
      `and(requester_id.eq.${invite.user_id},addressee_id.eq.${userId})`
    )
    .maybeSingle()

  if (existing?.status === 'accepted') {
    throw new Error('Already friends with this user')
  }

  // Create accepted friendship (or update existing declined one)
  if (existing) {
    const { error } = await supabaseAdmin
      .from('friendships')
      .update({ status: 'accepted', updated_at: new Date().toISOString() })
      .eq('id', existing.id)

    if (error) throw error
  } else {
    const { error } = await supabaseAdmin
      .from('friendships')
      .insert({
        requester_id: invite.user_id,
        addressee_id: userId,
        status: 'accepted',
      })

    if (error) throw error
  }

  // Mark invite code as used
  const { error: updateError } = await supabaseAdmin
    .from('friend_invite_codes')
    .update({
      used_by: userId,
      used_at: new Date().toISOString(),
    })
    .eq('id', invite.id)

  if (updateError) throw updateError

  return { redeemed: true, friend_user_id: invite.user_id }
}
