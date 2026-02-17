import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import React from 'react';
import {
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

// Types
interface Round {
  id: string;
  courseName: string;
  date: string;
  time: string;
  score: string;
  gameType: string;
}

interface Tournament {
  id: string;
  name: string;
  currentRound: number;
  totalRounds: number;
  nextRoundDate: string;
  leader: {
    name: string;
    score: string;
  };
  status: string;
}

interface Stats {
  average: number;
  roundsPlayed: number;
  bestScore: number;
}

// Placeholder data
const placeholderRounds: Round[] = [
  {
    id: "1",
    courseName: "Royal Copenhagen Golf Club",
    date: "Jan 12, 2026",
    time: "10:30 AM",
    score: "72 (+2)",
    gameType: "Stroke Play",
  },
  {
    id: "2",
    courseName: "Nordsjællands Golf Club",
    date: "Jan 8, 2026",
    time: "2:00 PM",
    score: "35 pts",
    gameType: "Stableford",
  },
  {
    id: "3",
    courseName: "Hillerød Golf Club",
    date: "Jan 5, 2026",
    time: "9:00 AM",
    score: "74 (+4)",
    gameType: "Stroke Play",
  },
];

const placeholderTournaments: Tournament[] = [
  {
    id: "1",
    name: "Summer Championship 2026",
    currentRound: 2,
    totalRounds: 4,
    nextRoundDate: "22 June",
    leader: { name: "Anders", score: "145 (+1)" },
    status: "upcoming",
  },
  {
    id: "2",
    name: "Weekend Masters",
    currentRound: 1,
    totalRounds: 2,
    nextRoundDate: "Today",
    leader: { name: "Erik", score: "72 (E)" },
    status: "ready",
  },
];

const stats: Stats = { average: 82, roundsPlayed: 24, bestScore: 74 };

export default function HomeScreen() {
  const router = useRouter();

  const getGreeting = () => {
    const hour = new Date().getHours();
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  };

  const handleQuickAction = (action: string) => {
    if (action === 'Start New Round') {
      router.push('/create-round/courses');
    } else {
      console.log(`Pressed: ${action}`);
    }
  };

  const handleViewRound = (roundId: string) => {
    console.log(`View round: ${roundId}`);
  };

  const handleViewTournament = (tournamentId: string) => {
    console.log(`View tournament: ${tournamentId}`);
  };

  const handleStartTournament = (tournamentId: string) => {
    console.log(`Start tournament: ${tournamentId}`);
  };

  return (
    <SafeAreaView style={styles.safeArea} edges={['top']}>
      <ScrollView style={styles.scrollView} showsVerticalScrollIndicator={false}>
        {/* Header */}
        <View style={styles.header}>
          <View style={styles.logoContainer}>
            <Text style={styles.logoText}>ParTracker</Text>
          </View>
          <TouchableOpacity style={styles.avatarContainer} activeOpacity={0.7}>
            <View style={styles.avatar}>
              <Text style={styles.avatarText}>A</Text>
            </View>
          </TouchableOpacity>
        </View>

        {/* Welcome Message */}
        <View style={styles.welcomeContainer}>
          <Text style={styles.welcomeText}>
            {getGreeting()}, Anders
          </Text>
          <Text style={styles.welcomeSubtext}>
            Ready for your next round?
          </Text>
        </View>

        {/* Quick Actions */}
        <View style={styles.sectionContainer}>
          <Text style={styles.sectionTitle}>Quick Actions</Text>
          <View style={styles.quickActionsGrid}>
            <TouchableOpacity
              style={[styles.quickActionButton, { marginRight: 12, marginBottom: 12 }]}
              onPress={() => handleQuickAction('Start New Round')}
              activeOpacity={0.7}
            >
              <View style={styles.quickActionIcon}>
                <Ionicons name="add" size={24} color="#006B4E" />
              </View>
              <Text style={styles.quickActionText}>Start New Round</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.quickActionButton, { marginBottom: 12 }]}
              onPress={() => handleQuickAction('View Statistics')}
              activeOpacity={0.7}
            >
              <View style={styles.quickActionIcon}>
                <Ionicons name="stats-chart" size={24} color="#006B4E" />
              </View>
              <Text style={styles.quickActionText}>View Statistics</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.quickActionButton, { marginRight: 12 }]}
              onPress={() => handleQuickAction('Course Library')}
              activeOpacity={0.7}
            >
              <View style={styles.quickActionIcon}>
                <Ionicons name="location" size={24} color="#006B4E" />
              </View>
              <Text style={styles.quickActionText}>Course Library</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={styles.quickActionButton}
              onPress={() => handleQuickAction('Create Tournament')}
              activeOpacity={0.7}
            >
              <View style={styles.quickActionIcon}>
                <Ionicons name="trophy" size={24} color="#006B4E" />
              </View>
              <Text style={styles.quickActionText}>Create Tournament</Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Recent Rounds */}
        <View style={styles.sectionContainer}>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Recent Rounds</Text>
            <TouchableOpacity activeOpacity={0.7}>
              <Text style={styles.seeAllText}>See all</Text>
            </TouchableOpacity>
          </View>

          {placeholderRounds.map((round) => (
            <TouchableOpacity
              key={round.id}
              style={styles.roundCard}
              onPress={() => handleViewRound(round.id)}
              activeOpacity={0.7}
            >
              <View style={styles.roundCardContent}>
                <View style={styles.roundMainInfo}>
                  <Text style={styles.courseName}>{round.courseName}</Text>
                  <Text style={styles.roundDate}>{round.date} at {round.time}</Text>
                </View>
                <View style={styles.roundScoreInfo}>
                  <Text style={styles.roundScore}>{round.score}</Text>
                  <Text style={styles.roundPar}>Score</Text>
                </View>
                <View style={styles.roundGameType}>
                  <Ionicons name="flag" size={16} color="#7A7A7A" style={{ marginRight: 4 }} />
                  <Text style={styles.gameTypeText}>{round.gameType}</Text>
                </View>
              </View>
              <Ionicons name="chevron-forward" size={20} color="#7A7A7A" />
            </TouchableOpacity>
          ))}
        </View>

        {/* Tournaments */}
        <View style={styles.sectionContainer}>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Tournaments</Text>
            <TouchableOpacity activeOpacity={0.7}>
              <Text style={styles.seeAllText}>See all</Text>
            </TouchableOpacity>
          </View>

          {placeholderTournaments.map((tournament) => (
            <View key={tournament.id} style={styles.tournamentCard}>
              <View style={styles.tournamentHeader}>
                <View style={styles.tournamentInfo}>
                  <Text style={styles.tournamentName}>{tournament.name}</Text>
                  <Text style={styles.tournamentCourse}>Round {tournament.currentRound} of {tournament.totalRounds}</Text>
                  <Text style={styles.tournamentDate}>Next round: {tournament.nextRoundDate}</Text>
                </View>
                <View style={styles.tournamentStatus}>
                  <Text style={[
                    styles.statusText,
                    tournament.status === 'active' && styles.statusActive,
                    tournament.status === 'upcoming' && styles.statusUpcoming,
                    tournament.status === 'completed' && styles.statusCompleted,
                    tournament.status === 'ready' && styles.statusReady,
                  ]}>
                    {tournament.status}
                  </Text>
                </View>
              </View>

              <View style={styles.tournamentActions}>
                <TouchableOpacity
                  style={[styles.tournamentActionButton, { marginRight: 12 }]}
                  onPress={() => handleViewTournament(tournament.id)}
                  activeOpacity={0.7}
                >
                  <Ionicons name="eye" size={16} color="#006B4E" style={{ marginRight: 6 }} />
                  <Text style={styles.tournamentActionText}>View</Text>
                </TouchableOpacity>

                {tournament.status === 'active' && (
                  <TouchableOpacity
                    style={[styles.tournamentActionButton, styles.tournamentActionPrimary]}
                    onPress={() => handleStartTournament(tournament.id)}
                    activeOpacity={0.7}
                  >
                    <Ionicons name="play" size={16} color="#fff" style={{ marginRight: 6 }} />
                    <Text style={styles.tournamentActionTextPrimary}>Start Round</Text>
                  </TouchableOpacity>
                )}

                {tournament.status === 'ready' && (
                  <TouchableOpacity
                    style={[styles.tournamentActionButton, styles.tournamentActionPrimary]}
                    onPress={() => handleStartTournament(tournament.id)}
                    activeOpacity={0.7}
                  >
                    <Ionicons name="play" size={16} color="#fff" style={{ marginRight: 6 }} />
                    <Text style={styles.tournamentActionTextPrimary}>Start Round</Text>
                  </TouchableOpacity>
                )}
              </View>
            </View>
          ))}
        </View>

        {/* Statistics Preview */}
        <View style={styles.sectionContainer}>
          <Text style={styles.sectionTitle}>Your Statistics</Text>
          <View style={styles.statsContainer}>
            <View style={styles.statItem}>
              <Text style={styles.statValue}>
                {stats.roundsPlayed > 0 ? stats.average.toFixed(1) : '0.0'}
              </Text>
              <Text style={styles.statLabel}>Average</Text>
            </View>
            <View style={styles.statDivider} />
            <View style={styles.statItem}>
              <Text style={styles.statValue}>{stats.roundsPlayed}</Text>
              <Text style={styles.statLabel}>Rounds</Text>
            </View>
            <View style={styles.statDivider} />
            <View style={styles.statItem}>
              <Text style={styles.statValue}>
                {stats.roundsPlayed > 0 ? stats.bestScore : '0'}
              </Text>
              <Text style={styles.statLabel}>Best</Text>
            </View>
          </View>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: '#FAFAFA',
  },
  scrollView: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 16,
  },
  logoContainer: {
    flex: 1,
  },
  logoText: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#006B4E',
  },
  avatarContainer: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: '#E5E5E5',
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatar: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: '#006B4E',
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
  },
  welcomeContainer: {
    paddingHorizontal: 20,
    marginBottom: 24,
  },
  welcomeText: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#1A1A1A',
    marginBottom: 4,
  },
  welcomeSubtext: {
    fontSize: 16,
    color: '#7A7A7A',
  },
  sectionContainer: {
    marginBottom: 32,
    paddingHorizontal: 20,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#1A1A1A',
  },
  seeAllText: {
    fontSize: 16,
    color: '#006B4E',
    fontWeight: '600',
  },
  quickActionsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  quickActionButton: {
    flex: 1,
    minWidth: '45%',
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
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
  quickActionIcon: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: '#E8F2EE',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 8,
  },
  quickActionText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#1A1A1A',
    textAlign: 'center',
  },
  roundCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    marginBottom: 12,
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
  roundCardContent: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
  },
  roundMainInfo: {
    flex: 1,
  },
  courseName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1A1A1A',
    marginBottom: 2,
  },
  roundDate: {
    fontSize: 14,
    color: '#7A7A7A',
  },
  roundScoreInfo: {
    alignItems: 'center',
    marginRight: 16,
  },
  roundScore: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#006B4E',
  },
  roundPar: {
    fontSize: 12,
    color: '#7A7A7A',
  },
  roundGameType: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  gameTypeText: {
    fontSize: 14,
    color: '#7A7A7A',
  },
  tournamentCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    marginBottom: 12,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 1,
    },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  tournamentHeader: {
    flexDirection: 'row',
    marginBottom: 16,
  },
  tournamentInfo: {
    flex: 1,
  },
  tournamentName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1A1A1A',
    marginBottom: 2,
  },
  tournamentCourse: {
    fontSize: 14,
    color: '#7A7A7A',
    marginBottom: 2,
  },
  tournamentDate: {
    fontSize: 14,
    color: '#7A7A7A',
  },
  tournamentStatus: {
    alignItems: 'flex-end',
  },
  statusText: {
    fontSize: 12,
    fontWeight: '600',
    textTransform: 'uppercase',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 12,
  },
  statusActive: {
    backgroundColor: '#E8F2EE',
    color: '#006B4E',
  },
  statusUpcoming: {
    backgroundColor: '#FFF3CD',
    color: '#856404',
  },
  statusCompleted: {
    backgroundColor: '#D1ECF1',
    color: '#0C5460',
  },
  statusReady: {
    backgroundColor: '#D4EDDA',
    color: '#155724',
  },
  tournamentActions: {
    flexDirection: 'row',
  },
  tournamentActionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#E5E5E5',
  },
  tournamentActionPrimary: {
    backgroundColor: '#006B4E',
    borderColor: '#006B4E',
  },
  tournamentActionText: {
    fontSize: 14,
    color: '#7A7A7A',
    fontWeight: '500',
  },
  tournamentActionTextPrimary: {
    fontSize: 14,
    color: '#fff',
    fontWeight: '500',
  },
  statsContainer: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 20,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-around',
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 1,
    },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  statItem: {
    alignItems: 'center',
    flex: 1,
  },
  statValue: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#006B4E',
    marginBottom: 4,
  },
  statLabel: {
    fontSize: 14,
    color: '#7A7A7A',
    textAlign: 'center',
  },
  statDivider: {
    width: 1,
    height: 40,
    backgroundColor: '#E5E5E5',
  },
});