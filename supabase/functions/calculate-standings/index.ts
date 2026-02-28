import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
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

    // Verify auth
    const authHeader = req.headers.get('Authorization')!
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token)
    if (userError || !user) throw new Error('Unauthorized')

    const { round_id } = await req.json()
    if (!round_id) throw new Error('round_id is required')

    console.log('=== CALCULATE STANDINGS ===')
    console.log('Round ID:', round_id)

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
    console.log('Tournament ID:', tournamentId)

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
    const bonusConfig = tournament.bonus_config || {}
    const aggregationRule = tournament.aggregation_rule
    const bestN = tournament.best_n

    console.log('Aggregation:', aggregationRule, 'Best N:', bestN)

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

    // Check which rounds are completed
    const { data: completedRounds, error: crError } = await supabaseAdmin
      .from('rounds')
      .select('id')
      .in('id', roundIds)
      .eq('status', 'completed')

    if (crError) throw new Error('Failed to check round statuses')

    const completedRoundIds = completedRounds?.map((r: any) => r.id) || []
    console.log('Completed rounds:', completedRoundIds.length, 'of', roundIds.length)

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
    // Track per-round rank for hot streak calculation
    const playerRoundRanks: Record<string, number[]> = {}

    // Initialize
    playerIds.forEach((pid: string) => {
      playerRoundPoints[pid] = []
      playerTotalSeasonPoints[pid] = 0
      playerRoundsWon[pid] = 0
      playerStablefordTotal[pid] = 0
      playerRoundsPlayed[pid] = 0
      playerRoundRanks[pid] = []
    })

    // Track round winners for bonus
    const roundWinners: Record<string, string[]> = {} // round_id → [player_ids]

    for (const roundId of completedRoundIds) {
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
        playerRoundRanks[pid].push(currentRank)

        // Track round winners (rank 1)
        if (currentRank === 1) {
          if (!roundWinners[roundId]) roundWinners[roundId] = []
          roundWinners[roundId].push(pid)
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
    // STEP 7: Calculate bonus points
    // -------------------------------------------------------
    const playerBonusPoints: Record<string, number> = {}
    playerIds.forEach((pid: string) => { playerBonusPoints[pid] = 0 })

    // Bonus: round_winner
    if (bonusConfig.round_winner) {
      Object.values(roundWinners).forEach((winners: string[]) => {
        winners.forEach((pid: string) => {
          playerBonusPoints[pid] += bonusConfig.round_winner
        })
      })
    }

    // Bonus: skins_leader (per round)
    if (bonusConfig.skins_leader) {
      for (const roundId of completedRoundIds) {
        const { data: skinsData } = await supabaseAdmin
          .from('skins_results')
          .select('winner_player_id, skin_awarded_value')
          .eq('round_id', roundId)
          .not('winner_player_id', 'is', null)

        if (skinsData && skinsData.length > 0) {
          const skinsTotals: Record<string, number> = {}
          skinsData.forEach((s: any) => {
            skinsTotals[s.winner_player_id] = (skinsTotals[s.winner_player_id] || 0) + (s.skin_awarded_value || 0)
          })
          const maxSkins = Math.max(...Object.values(skinsTotals))
          if (maxSkins > 0) {
            Object.entries(skinsTotals).forEach(([pid, total]) => {
              if (total === maxSkins && playerIds.includes(pid)) {
                playerBonusPoints[pid] += bonusConfig.skins_leader
              }
            })
          }
        }
      }
    }

    // Bonus: eagle (net eagle from hole_results)
    if (bonusConfig.eagle) {
      const { data: holeResults } = await supabaseAdmin
        .from('hole_results')
        .select('player_id, net_strokes, par')
        .in('round_id', completedRoundIds)
        .in('player_id', playerIds)

      holeResults?.forEach((hr: any) => {
        if (hr.par && hr.net_strokes && (hr.par - hr.net_strokes) >= 2) {
          playerBonusPoints[hr.player_id] += bonusConfig.eagle
        }
      })
    }

    // Bonus: hole_in_one (strokes = 1 in scores)
    if (bonusConfig.hole_in_one) {
      const { data: aceScores } = await supabaseAdmin
        .from('scores')
        .select('player_id')
        .in('round_id', completedRoundIds)
        .in('player_id', playerIds)
        .eq('strokes', 1)

      aceScores?.forEach((s: any) => {
        playerBonusPoints[s.player_id] += bonusConfig.hole_in_one
      })
    }

    // Bonus: hot_streak (3+ consecutive top-3 finishes)
    if (bonusConfig.hot_streak) {
      playerIds.forEach((pid: string) => {
        const ranks = playerRoundRanks[pid]
        let streak = 0
        let awarded = false
        for (const rank of ranks) {
          if (rank <= 3) {
            streak++
            if (streak >= 3 && !awarded) {
              playerBonusPoints[pid] += bonusConfig.hot_streak
              awarded = true
            }
          } else {
            streak = 0
            awarded = false
          }
        }
      })
    }

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
      total_points: playerTotalSeasonPoints[pid] + playerBonusPoints[pid],
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
        console.error('Error upserting standing for', s.player_id, upsertError)
      }
    }

    console.log('Standings updated for', standings.length, 'players')

    // -------------------------------------------------------
    // STEP 10: Update team standings (if teams exist)
    // -------------------------------------------------------
    const teamNames = [...new Set(Object.values(playerTeamMap))]

    if (teamNames.length > 0) {
      const teamStandings = teamNames.map((teamName: string) => {
        const teamMembers = standings.filter(s => playerTeamMap[s.player_id] === teamName)
        const teamSeasonPts = teamMembers.reduce((sum, m) => sum + m.total_points, 0)
        const teamBonusPts = teamMembers.reduce((sum, m) => sum + m.bonus_points, 0)
        const teamRoundsPlayed = Math.max(...teamMembers.map(m => m.rounds_played), 0)
        return {
          team_name: teamName,
          season_points: teamSeasonPts - teamBonusPts, // Just season component
          bonus_points: teamBonusPts,
          total_points: teamSeasonPts,
          rounds_played: teamRoundsPlayed,
        }
      })

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
          console.error('Error upserting team standing:', teamUpsertError)
        }
      }

      console.log('Team standings updated for', teamNames.length, 'teams')
    }

    console.log('=== STANDINGS CALCULATED SUCCESSFULLY ===')

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
    console.error('=== CALCULATE STANDINGS ERROR ===', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    )
  }
})
