import { Ionicons } from '@expo/vector-icons';
import { useLocalSearchParams, useRouter } from 'expo-router';
import React, { useEffect, useState } from 'react';
import {
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

// Types
type GameType = 'stroke_play' | 'stableford' | 'skins' | 'match_play';

interface Player {
  id: string;
  display_name: string;
  handicap_index?: number;
  is_guest?: boolean;
  team?: 1 | 2;
}

interface Course {
  id: string;
  name: string;
  [key: string]: any;
}

export default function TeamsSelectionScreen() {
  const router = useRouter();
  const params = useLocalSearchParams();
  const [course, setCourse] = useState<Course | null>(null);
  const [players, setPlayers] = useState<Player[]>([]);
  const [gameTypes, setGameTypes] = useState<GameType[]>([]);
  const [teamPlayers, setTeamPlayers] = useState<Player[]>([]);
  const [playMode, setPlayMode] = useState<'individual' | 'team'>('individual');

  // Get data from Step 4
  useEffect(() => {
    // Parse course data
    const courseData = params.courseData ? JSON.parse(params.courseData as string) : null;
    setCourse(courseData);

    // Parse players data
    const playersData = params.playersData ? JSON.parse(params.playersData as string) : [];
    setPlayers(playersData);
    setTeamPlayers(playersData.map((p: Player) => ({ ...p, team: undefined })));

    // Parse game types
    const gameTypesData = params.gameTypes ? JSON.parse(params.gameTypes as string) : [];
    setGameTypes(gameTypesData);

    console.log('Received in Step 5:', { 
      courseData, 
      playersData, 
      gameTypesData,
      holesToPlay: params.holesToPlay,
      startHole: params.startHole,
    });
  }, [params.courseData, params.playersData, params.gameTypes, params.holesToPlay, params.startHole]);

  // Check if we should even be on this screen
  const playerCount = players.length;
  
  // Redirect to tees if < 4 players
  useEffect(() => {
    if (playerCount > 0 && playerCount < 4) {
      const courseData = params.courseData ? JSON.parse(params.courseData as string) : null;
      const playersData = params.playersData ? JSON.parse(params.playersData as string) : [];
      const gameTypesData = params.gameTypes ? JSON.parse(params.gameTypes as string) : [];
      const carryoverEnabled = params.carryoverEnabled || 'false';

      router.replace({
        pathname: '/create-round/tees',
        params: {
          courseData: JSON.stringify(courseData),
          playersData: JSON.stringify(playersData),
          gameTypesData: JSON.stringify(gameTypesData),
          teamsData: 'null',
          playMode: 'individual',
          carryoverEnabled: carryoverEnabled,
          teesData: params.teesData,
          holesToPlay: params.holesToPlay, // Pass round settings forward!
          startHole: params.startHole, // Pass round settings forward!
        },
      });
    }
  }, [playerCount, params.courseData, params.playersData, params.gameTypes, params.carryoverEnabled, params.holesToPlay, params.startHole, router]);

  // Don't render anything while redirecting
  if (playerCount > 0 && playerCount < 4) {
    return null;
  }

  // Check if team games are selected
  const needsTeams = gameTypes.some(type => type === 'match_play' || type === 'skins');

  // Assign player to team
  const assignToTeam = (playerId: string, team: 1 | 2) => {
    setTeamPlayers(prev =>
      prev.map(player =>
        player.id === playerId ? { ...player, team } : player
      )
    );
  };

  // Get team statistics
  const getTeamStats = (team: 1 | 2) => {
    const teamMembers = teamPlayers.filter(p => p.team === team);
    const count = teamMembers.length;
    const handicaps = teamMembers
      .map(p => p.handicap_index)
      .filter((h): h is number => h !== undefined);
    const avgHandicap = handicaps.length > 0
      ? (handicaps.reduce((a, b) => a + b, 0) / handicaps.length).toFixed(1)
      : 'N/A';

    return { count, avgHandicap };
  };

  const team1Stats = getTeamStats(1);
  const team2Stats = getTeamStats(2);

  // Check if teams are valid
  const areTeamsValid = () => {
    if (playMode === 'individual') return true;
    const team1Count = teamPlayers.filter(p => p.team === 1).length;
    const team2Count = teamPlayers.filter(p => p.team === 2).length;
    return team1Count >= 1 && team2Count >= 1;
  };

  // Handle next button press
  const handleNext = () => {
    if (playMode === 'team' && !areTeamsValid()) {
      console.log('Please assign players to teams');
      return;
    }

    const finalPlayers = playMode === 'team'
      ? teamPlayers
      : players.map(p => ({ ...p, team: undefined }));

    const teamsData = playMode === 'team' ? {
      team1: teamPlayers.filter(p => p.team === 1),
      team2: teamPlayers.filter(p => p.team === 2),
    } : null;

    // Navigate to Step 6 with all data
    const carryoverEnabled = params.carryoverEnabled || 'false';
    router.push({
      pathname: '/create-round/tees',
      params: {
        courseId: course?.id,
        courseName: course?.name,
        courseData: JSON.stringify(course),
        playersData: JSON.stringify(finalPlayers),
        gameTypesData: JSON.stringify(gameTypes),
        teamsData: teamsData ? JSON.stringify(teamsData) : null,
        playMode: playMode,
        carryoverEnabled: carryoverEnabled,
        teesData: params.teesData,
        holesToPlay: params.holesToPlay, // Pass round settings forward!
        startHole: params.startHole, // Pass round settings forward!
      },
    });
  };

  return (
    <SafeAreaView style={styles.safeArea} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity style={styles.backButton} onPress={() => router.back()} activeOpacity={0.7}>
          <Ionicons name="chevron-back" size={24} color="#006B4E" />
          <Text style={styles.backButtonText}>Back</Text>
        </TouchableOpacity>

        <Text style={styles.headerTitle}>New Round</Text>

        <Text style={styles.stepIndicator}>Step 5 of 6</Text>
      </View>

      <ScrollView style={styles.scrollView} showsVerticalScrollIndicator={false}>
        {/* Selected Info */}
        <View style={styles.infoContainer}>
          {course && (
            <View style={styles.infoCard}>
              <View style={styles.infoContent}>
                <Text style={styles.courseName}>{course.name}</Text>
                <Text style={styles.infoSubtitle}>
                  {players.length} players • {gameTypes.length} game type{gameTypes.length !== 1 ? 's' : ''}
                </Text>
              </View>
              <Ionicons name="golf" size={24} color="#006B4E" />
            </View>
          )}
        </View>

        {/* Play Mode Toggle */}
        <View style={styles.playModeContainer}>
          <View style={styles.segmentedControl}>
            <TouchableOpacity
              style={[
                styles.segmentButton,
                styles.segmentButtonLeft,
                playMode === 'individual' && styles.segmentButtonActive,
              ]}
              onPress={() => setPlayMode('individual')}
              activeOpacity={0.7}
            >
              <Text
                style={[
                  styles.segmentButtonText,
                  playMode === 'individual' && styles.segmentButtonTextActive,
                ]}
              >
                Individual Match
              </Text>
            </TouchableOpacity>
            
            <TouchableOpacity
              style={[
                styles.segmentButton,
                styles.segmentButtonRight,
                playMode === 'team' && styles.segmentButtonActive,
              ]}
              onPress={() => setPlayMode('team')}
              activeOpacity={0.7}
            >
              <Text
                style={[
                  styles.segmentButtonText,
                  playMode === 'team' && styles.segmentButtonTextActive,
                ]}
              >
                Team Match
              </Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Teams Section */}
        {playMode === 'team' ? (
          <View style={styles.sectionContainer}>
            <Text style={styles.sectionTitle}>Assign Teams</Text>
            <Text style={styles.sectionSubtitle}>
              Tap to assign players to teams
            </Text>

            {/* Team Stats */}
            <View style={styles.teamStatsContainer}>
              <View style={[styles.teamStatCard, styles.team1Stat]}>
                <Text style={styles.teamStatTitle}>Team 1</Text>
                <Text style={styles.teamStatCount}>{team1Stats.count} players</Text>
                <Text style={styles.teamStatHandicap}>Avg HCP: {team1Stats.avgHandicap}</Text>
              </View>
              <View style={[styles.teamStatCard, styles.team2Stat]}>
                <Text style={styles.teamStatTitle}>Team 2</Text>
                <Text style={styles.teamStatCount}>{team2Stats.count} players</Text>
                <Text style={styles.teamStatHandicap}>Avg HCP: {team2Stats.avgHandicap}</Text>
              </View>
            </View>

            {/* Player Assignment */}
            <View style={styles.playersList}>
              {teamPlayers.map((player) => (
                <View key={player.id} style={styles.playerCard}>
                  <View style={styles.playerInfo}>
                    <Text style={styles.playerName}>{player.display_name}</Text>
                    {player.handicap_index !== undefined && (
                      <Text style={styles.playerHandicap}>
                        HCP: {player.handicap_index.toFixed(1)}
                      </Text>
                    )}
                  </View>
                  <View style={styles.teamButtons}>
                    <TouchableOpacity
                      style={[
                        styles.teamButton,
                        styles.team1Button,
                        player.team === 1 && styles.teamButtonSelected,
                      ]}
                      onPress={() => assignToTeam(player.id, 1)}
                      activeOpacity={0.7}
                    >
                      <Text style={[
                        styles.teamButtonText,
                        player.team === 1 && styles.teamButtonTextSelected,
                      ]}>
                        Team 1
                      </Text>
                    </TouchableOpacity>
                    <TouchableOpacity
                      style={[
                        styles.teamButton,
                        styles.team2Button,
                        player.team === 2 && styles.team2ButtonSelected,
                      ]}
                      onPress={() => assignToTeam(player.id, 2)}
                      activeOpacity={0.7}
                    >
                      <Text style={[
                        styles.team2ButtonText,
                        player.team === 2 && styles.teamButtonTextSelected,
                      ]}>
                        Team 2
                      </Text>
                    </TouchableOpacity>
                  </View>
                </View>
              ))}
            </View>
          </View>
        ) : (
          <View style={styles.sectionContainer}>
            <View style={styles.infoCard}>
              <Text style={styles.infoText}>Playing as individuals</Text>
            </View>
          </View>
        )}
      </ScrollView>

      {/* Bottom Button */}
      <View style={styles.bottomContainer}>
        <TouchableOpacity
          style={[
            styles.nextButton,
            playMode === 'team' && !areTeamsValid() && styles.nextButtonDisabled,
          ]}
          onPress={handleNext}
          disabled={playMode === 'team' && !areTeamsValid()}
          activeOpacity={(playMode === 'team' && !areTeamsValid()) ? 1 : 0.8}
        >
          <Text style={[
            styles.nextButtonText,
            playMode === 'team' && !areTeamsValid() && styles.nextButtonTextDisabled,
          ]}>
            Next
          </Text>
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: '#FAFAFA',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#E5E5E5',
    backgroundColor: '#fff',
  },
  backButton: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  backButtonText: {
    fontSize: 16,
    color: '#006B4E',
    fontWeight: '600',
    marginLeft: 4,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#1A1A1A',
  },
  stepIndicator: {
    fontSize: 14,
    color: '#7A7A7A',
    fontWeight: '500',
  },
  scrollView: {
    flex: 1,
  },
  infoContainer: {
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 16,
  },
  infoCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    flexDirection: 'row',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 1,
    },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  infoContent: {
    flex: 1,
  },
  courseName: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#1A1A1A',
    marginBottom: 4,
  },
  infoSubtitle: {
    fontSize: 14,
    color: '#7A7A7A',
  },
  infoText: {
    fontSize: 16,
    color: '#1A1A1A',
    textAlign: 'center',
  },
  playModeContainer: {
    marginHorizontal: 16,
    marginBottom: 24,
  },
  segmentedControl: {
    flexDirection: 'row',
    backgroundColor: '#F5F5F5',
    borderRadius: 12,
    padding: 4,
  },
  segmentButton: {
    flex: 1,
    paddingVertical: 12,
    paddingHorizontal: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  segmentButtonLeft: {
    borderTopLeftRadius: 8,
    borderBottomLeftRadius: 8,
  },
  segmentButtonRight: {
    borderTopRightRadius: 8,
    borderBottomRightRadius: 8,
  },
  segmentButtonActive: {
    backgroundColor: '#006B4E',
  },
  segmentButtonText: {
    fontSize: 15,
    fontWeight: '600',
    color: '#7A7A7A',
  },
  segmentButtonTextActive: {
    color: '#FFFFFF',
  },
  sectionContainer: {
    paddingHorizontal: 20,
    paddingBottom: 100, // Extra padding for bottom button
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#1A1A1A',
    marginBottom: 8,
  },
  sectionSubtitle: {
    fontSize: 14,
    color: '#7A7A7A',
    marginBottom: 20,
  },
  teamStatsContainer: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 24,
  },
  teamStatCard: {
    flex: 1,
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    borderWidth: 2,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 1,
    },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  team1Stat: {
    borderColor: '#006B4E',
    backgroundColor: '#E8F2EE',
  },
  team2Stat: {
    borderColor: '#2563EB',
    backgroundColor: '#EFF6FF',
  },
  teamStatTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1A1A1A',
    marginBottom: 8,
  },
  teamStatCount: {
    fontSize: 14,
    color: '#7A7A7A',
    marginBottom: 4,
  },
  teamStatHandicap: {
    fontSize: 14,
    fontWeight: '500',
    color: '#1A1A1A',
  },
  playersList: {
    gap: 12,
  },
  playerCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 1,
    },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  playerInfo: {
    flex: 1,
  },
  playerName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1A1A1A',
    marginBottom: 4,
  },
  playerHandicap: {
    fontSize: 14,
    color: '#7A7A7A',
  },
  teamButtons: {
    flexDirection: 'row',
    gap: 8,
  },
  teamButton: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 8,
    borderWidth: 2,
  },
  team1Button: {
    borderColor: '#006B4E',
    backgroundColor: '#fff',
  },
  team2Button: {
    borderColor: '#2563EB',
    backgroundColor: '#fff',
  },
  teamButtonSelected: {
    backgroundColor: '#006B4E',
  },
  team2ButtonSelected: {
    backgroundColor: '#2563EB',
  },
  teamButtonText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#006B4E',
  },
  team2ButtonText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#2563EB',
  },
  teamButtonTextSelected: {
    color: '#fff',
  },
  noTeamsContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 60,
  },
  noTeamsTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#1A1A1A',
    marginTop: 16,
    marginBottom: 8,
  },
  noTeamsText: {
    fontSize: 16,
    color: '#7A7A7A',
    textAlign: 'center',
    paddingHorizontal: 20,
  },
  bottomContainer: {
    paddingHorizontal: 20,
    paddingVertical: 16,
    backgroundColor: '#fff',
    borderTopWidth: 1,
    borderTopColor: '#E5E5E5',
  },
  nextButton: {
    backgroundColor: '#006B4E',
    paddingVertical: 16,
    borderRadius: 12,
    alignItems: 'center',
  },
  nextButtonDisabled: {
    opacity: 0.5,
  },
  nextButtonText: {
    color: '#fff',
    fontSize: 17,
    fontWeight: '600',
  },
  nextButtonTextDisabled: {
    color: '#fff',
  },
});