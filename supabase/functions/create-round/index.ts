import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { createLogger } from '../_shared/log.ts'

const log = createLogger('create-round')

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
      game_types,       // Array of strings like ['skins', 'stableford']
      players,          // Array of { player_id, tee_id, guest_info }
      teams,            // { team1: [playerIds], team2: [playerIds] } or null
      play_mode,        // 'individual' or 'team'
      carryover_enabled,
      holes_to_play,    // 9 or 18
      start_hole,       // 1-18
      visible_to_friends,
      scheduled_at,
    } = await req.json()

    log.info('=== CREATE ROUND ===')
    log.info('Course:', course_id, 'Players:', players.length, 'Mode:', play_mode)
    log.debug('Created by:', user.id)
    log.debug('Players:', JSON.stringify(players))
    log.debug('Game types:', JSON.stringify(game_types))
    log.debug('Holes:', holes_to_play, 'Start:', start_hole)

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
              gender: player.guest_info.gender || null,
              user_id: user.id, // Link guest to creator
              // email and phone intentionally left NULL (guest identifier pattern)
            })
            .select()
            .single()

          if (guestError) {
            log.error('Error creating guest player:', guestError)
            throw new Error(`Failed to create guest: ${player.guest_info.display_name}`)
          }

          log.debug('Created guest player:', newGuest.id, newGuest.display_name)

          return {
            player_id: newGuest.id,
            tee_id: player.tee_id,
          }
        }

        // Existing player — pass through
        return {
          player_id: player.player_id,
          tee_id: player.tee_id,
        }
      })
    )

    // -------------------------------------------------------
    // STEP 2: Map game_types to rounds table columns
    // -------------------------------------------------------
    // The rounds table has specific columns for scoring config,
    // NOT a separate sidegames table.

    // Determine scoring format from game_types
    const hasMatchPlay = game_types?.includes('match_play') || false
    const hasStableford = game_types?.includes('stableford') || true // Default

    // Determine team mode
    const isTeamPlay = play_mode === 'team'
    const teamMode = isTeamPlay ? 'teams' : 'individual'

    // Build the round insert object with all required NOT NULL columns
    const isScheduled = !!scheduled_at
    const roundInsert = {
      course_id,
      created_by: user.id,
      status: isScheduled ? 'scheduled' : 'active',
      scheduled_at: scheduled_at || null,
      holes_played: holes_to_play || 18,
      start_hole: start_hole || 1,
      // Scoring configuration
      scoring_format: 'stableford',           // Default scoring format
      handicap_allowance: 1.00,               // 100% handicap allowance
      // Team configuration
      team_mode: teamMode,
      team_scoring_mode: isTeamPlay ? 'bestball' : 'bestball', // Default
      // Match play configuration
      match_play_enabled: hasMatchPlay,
      // Skins configuration
      skins_enabled: hasMatchPlay && carryover_enabled,
      skins_type: 'net',                      // Default to net skins
      skins_rollover: carryover_enabled || true,
      // Visibility
      visibility: 'private',
      visible_to_friends: visible_to_friends || false,
    }

    log.debug('Round insert data:', JSON.stringify(roundInsert))

    // -------------------------------------------------------
    // STEP 3: Create the round
    // -------------------------------------------------------
    const { data: round, error: roundError } = await supabaseAdmin
      .from('rounds')
      .insert(roundInsert)
      .select()
      .single()

    if (roundError) {
      log.error('Error creating round:', roundError)
      throw new Error(`Failed to create round: ${roundError.message}`)
    }

    log.info('Round created:', round.id)

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
        log.error('Error creating teams:', teamsError)
        throw new Error(`Failed to create teams: ${teamsError.message}`)
      }

      createdTeams = teamData || []
      log.debug('Teams created:', createdTeams.map(t => t.id))
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
        // Look up the tee by id
        const { data: tee, error: teeError } = await supabaseAdmin
          .from('course_tees')
          .select('id, slope_rating_male, slope_rating_female, course_rating_male, course_rating_female, par')
          .eq('id', player.tee_id)
          .single()

        if (teeError || !tee) {
          log.error('Error finding tee:', teeError, 'ID:', player.tee_id)
          throw new Error(`Tee not found for id: ${player.tee_id}`)
        }

        // Get the player's handicap index and gender
        const { data: playerData, error: playerError } = await supabaseAdmin
          .from('players')
          .select('handicap_index, gender, user_id')
          .eq('id', player.player_id)
          .single()

        if (playerError) {
          log.error('Error fetching player:', playerError)
          throw new Error(`Failed to fetch player: ${player.player_id}`)
        }

        // Pick slope/course rating based on player gender (fall back to male if null)
        const isFemale = playerData?.gender === 'female'
        const slopeRating = isFemale
          ? (tee.slope_rating_female ?? tee.slope_rating_male ?? 113)
          : (tee.slope_rating_male ?? tee.slope_rating_female ?? 113)
        const courseRating = isFemale
          ? (tee.course_rating_female ?? tee.course_rating_male ?? tee.par)
          : (tee.course_rating_male ?? tee.course_rating_female ?? tee.par)

        // Calculate playing handicap using WHS formula
        // Course Handicap = Handicap Index × (Slope Rating / 113) + (Course Rating - Par)
        const handicapIndex = playerData?.handicap_index || 0
        const playingHcp = Math.round(
          (Number(handicapIndex) * slopeRating) / 113 + (Number(courseRating) - tee.par)
        )

        log.debug(`Player ${player.player_id}: HCP ${handicapIndex} → Playing HCP ${playingHcp} (slope: ${slopeRating}, CR: ${courseRating}, par: ${tee.par}, gender: ${playerData?.gender || 'null'})`)

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

    log.debug('Inserting round_players:', JSON.stringify(roundPlayersData))

    const { error: playersInsertError } = await supabaseAdmin
      .from('round_players')
      .insert(roundPlayersData)

    if (playersInsertError) {
      log.error('Error inserting round_players:', playersInsertError)
      throw new Error(`Failed to add players: ${playersInsertError.message}`)
    }

    log.info('Round created successfully:', round.id, 'with', roundPlayersData.length, 'players')

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
    log.error('=== CREATE ROUND ERROR ===', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    )
  }
})