import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
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

    // Parse the request body
    const {
      course_id,
      created_by,
      game_types,       // Array of strings like ['skins', 'stableford']
      players,          // Array of { player_id, tee_color, guest_info }
      teams,            // { team1: [playerIds], team2: [playerIds] } or null
      play_mode,        // 'individual' or 'team'
      carryover_enabled,
      holes_to_play,    // 9 or 18
      start_hole,       // 1-18
    } = await req.json()

    console.log('=== CREATE ROUND ===')
    console.log('Course:', course_id)
    console.log('Created by:', created_by)
    console.log('Players:', JSON.stringify(players))
    console.log('Game types:', JSON.stringify(game_types))
    console.log('Play mode:', play_mode)
    console.log('Holes:', holes_to_play, 'Start:', start_hole)

    // -------------------------------------------------------
    // STEP 1: Process players — create guest players if needed
    // -------------------------------------------------------
    const processedPlayers = await Promise.all(
      players.map(async (player: any) => {
        if (!player.player_id && player.guest_info) {
          // Guest player: create in players table
          // Guests are identified by: user_id = creator, email = NULL, phone = NULL
          const { data: newGuest, error: guestError } = await supabaseAdmin
            .from('players')
            .insert({
              display_name: player.guest_info.display_name,
              handicap_index: player.guest_info.handicap_index,
              user_id: user.id, // Link guest to creator
              // email and phone intentionally left NULL (guest identifier pattern)
            })
            .select()
            .single()

          if (guestError) {
            console.error('Error creating guest player:', guestError)
            throw new Error(`Failed to create guest: ${player.guest_info.display_name}`)
          }

          console.log('Created guest player:', newGuest.id, newGuest.display_name)

          return {
            player_id: newGuest.id,
            tee_color: player.tee_color,
          }
        }

        // Existing player — pass through
        return {
          player_id: player.player_id,
          tee_color: player.tee_color,
        }
      })
    )

    // -------------------------------------------------------
    // STEP 2: Map game_types to rounds table columns
    // -------------------------------------------------------
    // The rounds table has specific columns for scoring config,
    // NOT a separate sidegames table.

    // Determine scoring format from game_types
    const hasSkins = game_types?.includes('skins') || false
    const hasStableford = game_types?.includes('stableford') || true // Default

    // Determine team mode
    const isTeamPlay = play_mode === 'team'
    const teamMode = isTeamPlay ? 'team' : 'individual'

    // Build the round insert object with all required NOT NULL columns
    const roundInsert = {
      course_id,
      created_by,
      status: 'active',
      holes_played: holes_to_play || 18,
      start_hole: start_hole || 1,
      // Scoring configuration
      scoring_format: 'stableford',           // Default scoring format
      handicap_allowance: 1.00,               // 100% handicap allowance
      // Team configuration
      team_mode: teamMode,
      team_scoring_mode: isTeamPlay ? 'bestball' : 'bestball', // Default
      // Skins configuration
      skins_enabled: hasSkins,
      skins_type: 'net',                      // Default to net skins
      skins_rollover: carryover_enabled || true,
      // Visibility
      visibility: 'private',
    }

    console.log('Round insert data:', JSON.stringify(roundInsert))

    // -------------------------------------------------------
    // STEP 3: Create the round
    // -------------------------------------------------------
    const { data: round, error: roundError } = await supabaseAdmin
      .from('rounds')
      .insert(roundInsert)
      .select()
      .single()

    if (roundError) {
      console.error('Error creating round:', roundError)
      throw new Error(`Failed to create round: ${roundError.message}`)
    }

    console.log('Round created:', round.id)

    // -------------------------------------------------------
    // STEP 4: Create teams (if team play)
    // -------------------------------------------------------
    let createdTeams: any[] = []

    if (isTeamPlay && teams && teams.team1 && teams.team2) {
      const teamsInsert = [
        { round_id: round.id, name: 'Team 1' },
        { round_id: round.id, name: 'Team 2' },
      ]

      const { data: teamData, error: teamsError } = await supabaseAdmin
        .from('teams')
        .insert(teamsInsert)
        .select()

      if (teamsError) {
        console.error('Error creating teams:', teamsError)
        throw new Error(`Failed to create teams: ${teamsError.message}`)
      }

      createdTeams = teamData || []
      console.log('Teams created:', createdTeams.map(t => t.id))
    }

    // -------------------------------------------------------
    // STEP 5: Create round_players with tee lookup and HCP calc
    // -------------------------------------------------------
    // Build a map of player_id → team_id for team assignment
    const playerTeamMap: { [key: string]: string } = {}
    if (createdTeams.length === 2 && teams) {
      // Map original player IDs to team IDs
      // We need to handle that guest player IDs may have changed
      teams.team1?.forEach((pid: string) => {
        // Find the processed player (may be a guest with new ID)
        const processed = processedPlayers.find(
          (p: any, idx: number) => players[idx]?.player_id === pid || players[idx]?.guest_info?.id === pid
        )
        if (processed) {
          playerTeamMap[processed.player_id] = createdTeams[0].id
        }
      })
      teams.team2?.forEach((pid: string) => {
        const processed = processedPlayers.find(
          (p: any, idx: number) => players[idx]?.player_id === pid || players[idx]?.guest_info?.id === pid
        )
        if (processed) {
          playerTeamMap[processed.player_id] = createdTeams[1].id
        }
      })
    }

    const roundPlayersData = await Promise.all(
      processedPlayers.map(async (player: any) => {
        // Look up the tee for this player's color and course
        const { data: tee, error: teeError } = await supabaseAdmin
          .from('course_tees')
          .select('id, slope_rating, course_rating, par')
          .eq('course_id', course_id)
          .eq('tee_color', player.tee_color)
          .single()

        if (teeError || !tee) {
          console.error('Error finding tee:', teeError, 'Color:', player.tee_color)
          throw new Error(`Tee not found for color: ${player.tee_color}`)
        }

        // Get the player's handicap index
        const { data: playerData, error: playerError } = await supabaseAdmin
          .from('players')
          .select('handicap_index, user_id')
          .eq('id', player.player_id)
          .single()

        if (playerError) {
          console.error('Error fetching player:', playerError)
          throw new Error(`Failed to fetch player: ${player.player_id}`)
        }

        // Calculate playing handicap using WHS formula
        // Playing HCP = Handicap Index × (Slope Rating / 113)
        const handicapIndex = playerData?.handicap_index || 0
        const playingHcp = Math.round(
          (Number(handicapIndex) * tee.slope_rating) / 113
        )

        console.log(`Player ${player.player_id}: HCP ${handicapIndex} → Playing HCP ${playingHcp} (slope: ${tee.slope_rating})`)

        return {
          round_id: round.id,
          player_id: player.player_id,
          user_id: playerData?.user_id || null,  // Link to auth user if exists
          tee_id: tee.id,                        // UUID reference to course_tees
          playing_hcp: playingHcp,               // CORRECT column name
          role: 'player',                        // REQUIRED: NOT NULL column
          team_id: playerTeamMap[player.player_id] || null, // Team assignment
        }
      })
    )

    console.log('Inserting round_players:', JSON.stringify(roundPlayersData))

    const { error: playersInsertError } = await supabaseAdmin
      .from('round_players')
      .insert(roundPlayersData)

    if (playersInsertError) {
      console.error('Error inserting round_players:', playersInsertError)
      throw new Error(`Failed to add players: ${playersInsertError.message}`)
    }

    console.log('=== ROUND CREATED SUCCESSFULLY ===')
    console.log('Round ID:', round.id)
    console.log('Players:', roundPlayersData.length)

    // Return success response
    return new Response(
      JSON.stringify({
        success: true,
        round_id: round.id,
        players: roundPlayersData.map(p => ({
          player_id: p.player_id,
          playing_hcp: p.playing_hcp,
          tee_id: p.tee_id,
        })),
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )
  } catch (error) {
    console.error('=== CREATE ROUND ERROR ===', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    )
  }
})