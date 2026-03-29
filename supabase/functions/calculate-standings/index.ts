import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { createLogger } from '../_shared/log.ts'
import { checkRateLimit, rateLimitResponse } from '../_shared/rate-limit.ts'
import { ValidationError, requireUUID } from '../_shared/validate.ts'

const log = createLogger('calculate-standings')

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

    // Verify auth
    const authHeader = req.headers.get('Authorization')!
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token)
    if (userError || !user) throw new Error('Unauthorized')

    // Rate limit: 20 requests per minute per user
    const rl = checkRateLimit(user.id, { maxRequests: 20 })
    if (!rl.allowed) return rateLimitResponse(rl.retryAfterMs!, corsHeaders)

    const body = await req.json()
    const round_id = requireUUID(body.round_id, 'round_id')

    log.info('=== CALCULATE STANDINGS ===')
    log.info('Round ID:', round_id)

    // -------------------------------------------------------
    // STEP 1: Find tournament for this round
    // -------------------------------------------------------
    const { data: tournamentRound, error: trError } = await supabaseAdmin
      .from('tournament_rounds')
      .select('tournament_id, round_no')
      .eq('round_id', round_id)
      .single()

    if (trError || !tournamentRound) {
      throw new Error('Round is not part of a tournament')
    }

    const tournamentId = tournamentRound.tournament_id
    log.info('Tournament ID:', tournamentId)

    // -------------------------------------------------------
    // STEP 2: Get tournament config
    // -------------------------------------------------------
    const { data: tournament, error: tError } = await supabaseAdmin
      .from('tournaments')
      .select('*')
      .eq('id', tournamentId)
      .single()

    if (tError || !tournament) throw new Error('Tournament not found')

    const pointsTable: { rank: number; points: number }[] = tournament.points_table || []
    const aggregationRule = tournament.aggregation_rule
    const bestN = tournament.best_n
    const scoringSplit = tournament.scoring_split || null

    log.debug('Aggregation:', aggregationRule, 'Best N:', bestN, 'Scoring split:', scoringSplit ? 'yes' : 'no')

    // -------------------------------------------------------
    // STEP 3: Get all completed rounds for this tournament
    // -------------------------------------------------------
    const { data: allTournamentRounds, error: atrError } = await supabaseAdmin
      .from('tournament_rounds')
      .select('round_id, round_no')
      .eq('tournament_id', tournamentId)
      .order('round_no', { ascending: true })

    if (atrError) throw new Error('Failed to fetch tournament rounds')

    const roundIds = allTournamentRounds?.map((r: any) => r.round_id) || []

    // Check which rounds are completed (also fetch scoring_format for split filtering)
    const { data: completedRounds, error: crError } = await supabaseAdmin
      .from('rounds')
      .select('id, scoring_format')
      .in('id', roundIds)
      .eq('status', 'completed')

    if (crError) throw new Error('Failed to check round statuses')

    const completedRoundIds = completedRounds?.map((r: any) => r.id) || []
    const roundFormatMap: Record<string, string> = {}
    completedRounds?.forEach((r: any) => { roundFormatMap[r.id] = r.scoring_format })
    log.info('Completed rounds:', completedRoundIds.length, 'of', roundIds.length)

    // When scoring_split is set, filter rounds by format
    const individualRoundIds = scoringSplit
      ? completedRoundIds.filter((rid: string) => roundFormatMap[rid] === scoringSplit.individual_format)
      : completedRoundIds
    const teamRoundIds = scoringSplit
      ? completedRoundIds.filter((rid: string) => roundFormatMap[rid] === scoringSplit.team_format)
      : completedRoundIds

    if (completedRoundIds.length === 0) {
      return new Response(
        JSON.stringify({ success: true, message: 'No completed rounds yet' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      )
    }

    // -------------------------------------------------------
    // STEP 4: Get tournament players
    // -------------------------------------------------------
    const { data: tournamentPlayers, error: tpError } = await supabaseAdmin
      .from('tournament_players')
      .select('player_id, team_name')
      .eq('tournament_id', tournamentId)

    if (tpError) throw new Error('Failed to fetch tournament players')

    const playerIds = tournamentPlayers?.map((tp: any) => tp.player_id) || []
    const playerTeamMap: Record<string, string> = {}
    tournamentPlayers?.forEach((tp: any) => {
      if (tp.team_name) playerTeamMap[tp.player_id] = tp.team_name
    })

    // -------------------------------------------------------
    // STEP 5: For each completed round, rank players and assign season points
    // -------------------------------------------------------
    const { data: roundResults, error: rrError } = await supabaseAdmin
      .from('round_results')
      .select('round_id, player_id, stableford_total')
      .in('round_id', completedRoundIds)
      .in('player_id', playerIds)

    if (rrError) throw new Error('Failed to fetch round results')

    // Group results by round
    const resultsByRound: Record<string, { player_id: string; stableford_total: number }[]> = {}
    roundResults?.forEach((rr: any) => {
      if (!resultsByRound[rr.round_id]) resultsByRound[rr.round_id] = []
      resultsByRound[rr.round_id].push({
        player_id: rr.player_id,
        stableford_total: rr.stableford_total || 0,
      })
    })

    // Per-round points and round winners
    const playerRoundPoints: Record<string, number[]> = {} // player_id → array of round points
    const playerTotalSeasonPoints: Record<string, number> = {}
    const playerRoundsWon: Record<string, number> = {}
    const playerStablefordTotal: Record<string, number> = {}
    const playerRoundsPlayed: Record<string, number> = {}
    // Initialize
    playerIds.forEach((pid: string) => {
      playerRoundPoints[pid] = []
      playerTotalSeasonPoints[pid] = 0
      playerRoundsWon[pid] = 0
      playerStablefordTotal[pid] = 0
      playerRoundsPlayed[pid] = 0
    })

    for (const roundId of individualRoundIds) {
      const results = resultsByRound[roundId] || []
      if (results.length === 0) continue

      // Sort by stableford DESC
      results.sort((a, b) => b.stableford_total - a.stableford_total)

      // Assign ranks with ties (same rank, skip next)
      let currentRank = 1
      for (let i = 0; i < results.length; i++) {
        if (i > 0 && results[i].stableford_total < results[i - 1].stableford_total) {
          currentRank = i + 1
        }
        const pid = results[i].player_id
        const pts = pointsTable.find((pt: any) => pt.rank === currentRank)?.points || 0

        playerRoundPoints[pid].push(pts)
        playerStablefordTotal[pid] += results[i].stableford_total
        playerRoundsPlayed[pid]++

        // Track round winners (rank 1)
        if (currentRank === 1) {
          playerRoundsWon[pid]++
        }
      }
    }

    // -------------------------------------------------------
    // STEP 6: Apply aggregation rule for season points
    // -------------------------------------------------------
    playerIds.forEach((pid: string) => {
      const pts = playerRoundPoints[pid]
      if (pts.length === 0) {
        playerTotalSeasonPoints[pid] = 0
        return
      }

      switch (aggregationRule) {
        case 'best_n': {
          const sorted = [...pts].sort((a, b) => b - a)
          const topN = sorted.slice(0, bestN || pts.length)
          playerTotalSeasonPoints[pid] = topN.reduce((sum, p) => sum + p, 0)
          break
        }
        case 'average': {
          const sum = pts.reduce((s, p) => s + p, 0)
          playerTotalSeasonPoints[pid] = Math.round((sum / pts.length) * 10) / 10
          break
        }
        case 'sum':
        default: {
          playerTotalSeasonPoints[pid] = pts.reduce((sum, p) => sum + p, 0)
          break
        }
      }
    })

    // -------------------------------------------------------
    // STEP 7: Bonus points disabled — all set to 0
    // -------------------------------------------------------
    const playerBonusPoints: Record<string, number> = {}
    playerIds.forEach((pid: string) => { playerBonusPoints[pid] = 0 })

    // Skins total value across tournament
    const playerSkinsTotalValue: Record<string, number> = {}
    playerIds.forEach((pid: string) => { playerSkinsTotalValue[pid] = 0 })

    const { data: allSkins } = await supabaseAdmin
      .from('skins_results')
      .select('winner_player_id, skin_awarded_value')
      .in('round_id', completedRoundIds)
      .not('winner_player_id', 'is', null)

    allSkins?.forEach((s: any) => {
      if (playerIds.includes(s.winner_player_id)) {
        playerSkinsTotalValue[s.winner_player_id] += (s.skin_awarded_value || 0)
      }
    })

    // -------------------------------------------------------
    // STEP 8: Calculate total points and rank
    // -------------------------------------------------------
    const standings = playerIds.map((pid: string) => ({
      player_id: pid,
      season_points: playerTotalSeasonPoints[pid],
      bonus_points: playerBonusPoints[pid],
      total_points: playerTotalSeasonPoints[pid],
      rounds_played: playerRoundsPlayed[pid],
      rounds_won: playerRoundsWon[pid],
      stableford_total: playerStablefordTotal[pid],
      skins_total_value: playerSkinsTotalValue[pid],
    }))

    // Sort by total_points DESC for ranking
    standings.sort((a, b) => b.total_points - a.total_points)

    // Assign ranks with ties
    let rank = 1
    for (let i = 0; i < standings.length; i++) {
      if (i > 0 && standings[i].total_points < standings[i - 1].total_points) {
        rank = i + 1
      }
      (standings[i] as any).rank = rank
    }

    // -------------------------------------------------------
    // STEP 9: UPSERT tournament_standings
    // -------------------------------------------------------
    for (const s of standings) {
      const { error: upsertError } = await supabaseAdmin
        .from('tournament_standings')
        .upsert({
          tournament_id: tournamentId,
          player_id: s.player_id,
          season_points: s.season_points,
          bonus_points: s.bonus_points,
          total_points: s.total_points,
          rounds_played: s.rounds_played,
          rounds_won: s.rounds_won,
          stableford_total: s.stableford_total,
          skins_total_value: s.skins_total_value,
          rank: (s as any).rank,
          last_updated: new Date().toISOString(),
        }, { onConflict: 'tournament_id,player_id' })

      if (upsertError) {
        log.error('Error upserting standing for', s.player_id, upsertError)
      }
    }

    log.info('Standings updated for', standings.length, 'players')

    // -------------------------------------------------------
    // STEP 10: Update team standings (if teams exist)
    // -------------------------------------------------------
    const teamNames = [...new Set(Object.values(playerTeamMap))]

    if (teamNames.length > 0) {
      let teamStandings: { team_name: string; season_points: number; bonus_points: number; total_points: number; rounds_played: number }[]

      if (scoringSplit) {
        // FedEx-style team points: rank teams per round, award points from team points table
        const teamPointsMax = scoringSplit.team_points_max || 100
        // Generate team points table (e.g. 100, 70, 49... decaying)
        const teamPointsTable: number[] = []
        let tp = teamPointsMax
        for (let i = 0; i < teamNames.length; i++) {
          teamPointsTable.push(Math.max(Math.round(tp), 5))
          tp = tp * 0.7
        }

        // Fetch team_results for team rounds
        const { data: teamResults } = await supabaseAdmin
          .from('team_results')
          .select('round_id, team_id, stableford_total, gross_total')
          .in('round_id', teamRoundIds)

        // If no team_results exist (rounds are individual, not team-mode),
        // fall back to ranking teams by summing their members' individual scores per round
        const hasTeamResults = (teamResults || []).length > 0

        if (hasTeamResults) {
          // Map team_id to team_name via round_players
          const { data: rpForTeams } = await supabaseAdmin
            .from('round_players')
            .select('team_id, player_id')
            .in('round_id', teamRoundIds)
            .not('team_id', 'is', null)

          // Build team_id → team_name mapping
          const teamIdToName: Record<string, string> = {}
          rpForTeams?.forEach((rp: any) => {
            if (rp.team_id && playerTeamMap[rp.player_id]) {
              teamIdToName[rp.team_id] = playerTeamMap[rp.player_id]
            }
          })

          // Per-round team FedEx points
          const teamTotalPoints: Record<string, number> = {}
          const teamRoundsPlayedMap: Record<string, number> = {}
          teamNames.forEach((tn) => { teamTotalPoints[tn] = 0; teamRoundsPlayedMap[tn] = 0 })

          for (const roundId of teamRoundIds) {
            const roundTeamResults = (teamResults || [])
              .filter((tr: any) => tr.round_id === roundId)
              .map((tr: any) => ({
                team_name: teamIdToName[tr.team_id] || 'Unknown',
                score: scoringSplit.team_format === 'stroke_play' ? tr.gross_total : tr.stableford_total,
              }))

            if (roundTeamResults.length === 0) continue

            // Rank: for stableford = highest wins, for stroke_play = lowest wins
            if (scoringSplit.team_format === 'stroke_play') {
              roundTeamResults.sort((a: any, b: any) => a.score - b.score)
            } else {
              roundTeamResults.sort((a: any, b: any) => b.score - a.score)
            }

            // Assign FedEx points per team rank
            roundTeamResults.forEach((tr: any, idx: number) => {
              const pts = teamPointsTable[idx] || 5
              teamTotalPoints[tr.team_name] = (teamTotalPoints[tr.team_name] || 0) + pts
              teamRoundsPlayedMap[tr.team_name] = (teamRoundsPlayedMap[tr.team_name] || 0) + 1
            })
          }

          teamStandings = teamNames.map((tn) => ({
            team_name: tn,
            season_points: teamTotalPoints[tn] || 0,
            bonus_points: 0,
            total_points: teamTotalPoints[tn] || 0,
            rounds_played: teamRoundsPlayedMap[tn] || 0,
          }))
        } else {
          // No team_results: rank teams per round by summing individual stableford per team
          const teamTotalPoints: Record<string, number> = {}
          const teamRoundsPlayedMap: Record<string, number> = {}
          teamNames.forEach((tn) => { teamTotalPoints[tn] = 0; teamRoundsPlayedMap[tn] = 0 })

          for (const roundId of completedRoundIds) {
            const results = resultsByRound[roundId] || []
            if (results.length === 0) continue

            // Sum stableford per team for this round
            const teamRoundScores: { team_name: string; score: number }[] = teamNames.map((tn) => {
              const memberResults = results.filter((r) => playerTeamMap[r.player_id] === tn)
              const totalScore = memberResults.reduce((sum, r) => sum + r.stableford_total, 0)
              return { team_name: tn, score: totalScore }
            }).filter((t) => t.score > 0)

            if (teamRoundScores.length === 0) continue

            // Rank: highest stableford wins
            teamRoundScores.sort((a, b) => b.score - a.score)

            // Assign FedEx points per team rank
            teamRoundScores.forEach((tr, idx) => {
              const pts = teamPointsTable[idx] || 5
              teamTotalPoints[tr.team_name] = (teamTotalPoints[tr.team_name] || 0) + pts
              teamRoundsPlayedMap[tr.team_name] = (teamRoundsPlayedMap[tr.team_name] || 0) + 1
            })
          }

          teamStandings = teamNames.map((tn) => ({
            team_name: tn,
            season_points: teamTotalPoints[tn] || 0,
            bonus_points: 0,
            total_points: teamTotalPoints[tn] || 0,
            rounds_played: teamRoundsPlayedMap[tn] || 0,
          }))
        }
      } else {
        // Default: sum individual season points per team
        teamStandings = teamNames.map((teamName: string) => {
          const teamMembers = standings.filter(s => playerTeamMap[s.player_id] === teamName)
          const teamSeasonPts = teamMembers.reduce((sum, m) => sum + m.season_points, 0)
          const teamRoundsPlayed = Math.max(...teamMembers.map(m => m.rounds_played), 0)
          return {
            team_name: teamName,
            season_points: teamSeasonPts,
            bonus_points: 0,
            total_points: teamSeasonPts,
            rounds_played: teamRoundsPlayed,
          }
        })
      }

      // Sort and rank teams
      teamStandings.sort((a, b) => b.total_points - a.total_points)
      let teamRank = 1
      for (let i = 0; i < teamStandings.length; i++) {
        if (i > 0 && teamStandings[i].total_points < teamStandings[i - 1].total_points) {
          teamRank = i + 1
        }

        const { error: teamUpsertError } = await supabaseAdmin
          .from('tournament_team_standings')
          .upsert({
            tournament_id: tournamentId,
            team_name: teamStandings[i].team_name,
            season_points: teamStandings[i].season_points,
            bonus_points: teamStandings[i].bonus_points,
            total_points: teamStandings[i].total_points,
            rounds_played: teamStandings[i].rounds_played,
            rank: teamRank,
            last_updated: new Date().toISOString(),
          }, { onConflict: 'tournament_id,team_name' })

        if (teamUpsertError) {
          log.error('Error upserting team standing:', teamUpsertError)
        }
      }

      log.info('Team standings updated for', teamNames.length, 'teams')
    }

    log.info('=== STANDINGS CALCULATED SUCCESSFULLY ===')

    return new Response(
      JSON.stringify({
        success: true,
        tournament_id: tournamentId,
        standings: standings.map(s => ({
          player_id: s.player_id,
          rank: (s as any).rank,
          total_points: s.total_points,
          season_points: s.season_points,
          bonus_points: s.bonus_points,
        })),
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )
  } catch (error) {
    const status = error instanceof ValidationError ? 422 : 400
    log.error('=== CALCULATE STANDINGS ERROR ===', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status,
      }
    )
  }
})
