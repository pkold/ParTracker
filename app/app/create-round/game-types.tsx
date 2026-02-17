import { Ionicons } from '@expo/vector-icons';
import { useLocalSearchParams, useRouter } from 'expo-router';
import React, { useEffect, useState } from 'react';
import {
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

// Types
type GameType = 'stroke_play' | 'stableford' | 'match_play';

interface GameTypeOption {
  id: GameType;
  title: string;
  description: string;
  icon: string;
}

interface Course {
  id: string;
  name: string;
  [key: string]: any;
}

interface Player {
  id: string;
  display_name: string;
  [key: string]: any;
}

// Game type options
const gameTypeOptions: GameTypeOption[] = [
  {
    id: 'stroke_play',
    title: 'Stroke Play',
    description: 'Count total strokes',
    icon: 'flag',
  },
  {
    id: 'stableford',
    title: 'Stableford',
    description: 'Points-based scoring',
    icon: 'star',
  },
  {
    id: 'match_play',
    title: 'Match Play',
    description: 'Head-to-head competition',
    icon: 'people',
  },
];

export default function GameTypesSelectionScreen() {
  const router = useRouter();
  const params = useLocalSearchParams();
  const [course, setCourse] = useState<Course | null>(null);
  const [players, setPlayers] = useState<Player[]>([]);
  const [selectedGameTypes, setSelectedGameTypes] = useState<GameType[]>([]);
  const [carryoverEnabled, setCarryoverEnabled] = useState(false);

  // Get course and players from params
  useEffect(() => {
    // Parse the data from Step 3
    const courseData = params.courseData ? JSON.parse(params.courseData as string) : null;
    const playersData = params.playersData ? JSON.parse(params.playersData as string) : [];

    console.log('Received in Step 4:', { 
      course: courseData, 
      players: playersData,
      holesToPlay: params.holesToPlay,
      startHole: params.startHole,
    });

    setCourse(courseData);
    setPlayers(playersData);
  }, [params.courseData, params.playersData, params.holesToPlay, params.startHole]);

  // Toggle game type selection
  const toggleGameType = (gameTypeId: GameType) => {
    setSelectedGameTypes(prev =>
      prev.includes(gameTypeId)
        ? prev.filter(id => id !== gameTypeId)
        : [...prev, gameTypeId]
    );
  };

  // Handle next button press
  const handleNext = () => {
    if (selectedGameTypes.length === 0) {
      console.log('Please select at least one game type');
      return;
    }

    if (!course) {
      console.error('Course data is missing');
      return;
    }

    const playerCount = players.length;

    // If 4 players, go to Teams step
    if (playerCount === 4) {
      router.push({
        pathname: '/create-round/teams',
        params: {
          courseId: course.id,
          courseName: course.name,
          courseData: JSON.stringify(course),
          playersData: JSON.stringify(players),
          gameTypes: JSON.stringify(selectedGameTypes),
          carryoverEnabled: carryoverEnabled.toString(),
          teesData: params.teesData,
          holesToPlay: params.holesToPlay, // Pass round settings forward!
          startHole: params.startHole, // Pass round settings forward!
        },
      });
    } else {
      // Skip teams, go directly to tees
      router.push({
        pathname: '/create-round/tees',
        params: {
          courseId: course.id,
          courseName: course.name,
          courseData: JSON.stringify(course),
          playersData: JSON.stringify(players),
          gameTypesData: JSON.stringify(selectedGameTypes),
          teamsData: 'null',
          playMode: 'individual',
          carryoverEnabled: carryoverEnabled.toString(),
          teesData: params.teesData,
          holesToPlay: params.holesToPlay, // Pass round settings forward!
          startHole: params.startHole, // Pass round settings forward!
        },
      });
    }
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

        <Text style={styles.stepIndicator}>Step 4 of 6</Text>
      </View>

      <ScrollView style={styles.scrollView} showsVerticalScrollIndicator={false}>
        {/* Selected Info */}
        <View style={styles.infoContainer}>
          {course && (
            <View style={styles.selectedInfoCard}>
              <Text style={styles.courseName}>{course.name}</Text>
              <Text style={styles.playerCount}>{players.length} players</Text>
            </View>
          )}
        </View>

        {/* Game Types Section */}
        <View style={styles.sectionContainer}>
          <Text style={styles.sectionTitle}>Select Game Types</Text>
          <Text style={styles.sectionSubtitle}>You can select multiple</Text>

          <View style={styles.gameTypesContainer}>
            {gameTypeOptions.map((gameType) => {
              const isSelected = selectedGameTypes.includes(gameType.id);
              return (
                <TouchableOpacity
                  key={gameType.id}
                  style={[
                    styles.gameTypeCard,
                    isSelected && styles.gameTypeCardSelected,
                  ]}
                  onPress={() => toggleGameType(gameType.id)}
                  activeOpacity={0.7}
                >
                  <View style={styles.gameTypeHeader}>
                    <View style={styles.gameTypeIcon}>
                      <Ionicons
                        name={gameType.icon as any}
                        size={24}
                        color={isSelected ? "#fff" : "#006B4E"}
                      />
                    </View>
                    <View style={styles.gameTypeCheckbox}>
                      <Ionicons
                        name={isSelected ? "checkmark-circle" : "checkmark-circle-outline"}
                        size={24}
                        color={isSelected ? "#006B4E" : "#E5E5E5"}
                      />
                    </View>
                  </View>

                  <View style={styles.gameTypeContent}>
                    <Text style={[
                      styles.gameTypeTitle,
                      isSelected && styles.gameTypeTitleSelected,
                    ]}>
                      {gameType.title}
                    </Text>
                    <Text style={[
                      styles.gameTypeDescription,
                      isSelected && styles.gameTypeDescriptionSelected,
                    ]}>
                      {gameType.description}
                    </Text>
                  </View>
                </TouchableOpacity>
              );
            })}
          </View>

          {/* Carryover Toggle for Match Play */}
          {selectedGameTypes.includes('match_play') && (
            <View style={styles.carryoverSection}>
              <View style={styles.carryoverLabelContainer}>
                <Text style={styles.carryoverTitle}>Enable Carryover</Text>
                <Text style={styles.carryoverSubtitle}>Tied holes carry over to next hole</Text>
              </View>
              <Switch
                value={carryoverEnabled}
                onValueChange={setCarryoverEnabled}
                trackColor={{ false: '#E5E5E5', true: '#A5D6A7' }}
                thumbColor={carryoverEnabled ? '#006B4E' : '#F4F4F4'}
                ios_backgroundColor="#E5E5E5"
              />
            </View>
          )}
        </View>
      </ScrollView>

      {/* Bottom Button */}
      <View style={styles.bottomContainer}>
        <TouchableOpacity
          style={[
            styles.nextButton,
            selectedGameTypes.length === 0 && styles.nextButtonDisabled,
          ]}
          onPress={handleNext}
          disabled={selectedGameTypes.length === 0}
          activeOpacity={selectedGameTypes.length > 0 ? 0.8 : 1}
        >
          <Text style={[
            styles.nextButtonText,
            selectedGameTypes.length === 0 && styles.nextButtonTextDisabled,
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
  selectedInfoCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 1,
    },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  courseName: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#1A1A1A',
    marginBottom: 4,
  },
  playerCount: {
    fontSize: 14,
    color: '#7A7A7A',
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
  gameTypesContainer: {
    gap: 12,
  },
  gameTypeCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    borderWidth: 2,
    borderColor: '#E5E5E5',
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 1,
    },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  gameTypeCardSelected: {
    borderColor: '#006B4E',
    backgroundColor: '#E8F2EE',
  },
  gameTypeHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  gameTypeIcon: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: '#E8F2EE',
    justifyContent: 'center',
    alignItems: 'center',
  },
  gameTypeCheckbox: {
    padding: 4,
  },
  gameTypeContent: {
    flex: 1,
  },
  gameTypeTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1A1A1A',
    marginBottom: 4,
  },
  gameTypeTitleSelected: {
    color: '#006B4E',
  },
  gameTypeDescription: {
    fontSize: 14,
    color: '#7A7A7A',
    lineHeight: 20,
  },
  gameTypeDescriptionSelected: {
    color: '#1A1A1A',
  },
  carryoverSection: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    marginTop: 16,
    borderWidth: 2,
    borderColor: '#006B4E',
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 1,
    },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  carryoverLabelContainer: {
    flex: 1,
    marginRight: 16,
  },
  carryoverTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1A1A1A',
    marginBottom: 4,
  },
  carryoverSubtitle: {
    fontSize: 14,
    color: '#7A7A7A',
    lineHeight: 20,
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