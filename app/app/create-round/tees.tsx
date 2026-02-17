import { Ionicons } from '@expo/vector-icons';
import { useLocalSearchParams, useRouter } from 'expo-router';
import React, { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { supabase } from '../../lib/supabase';

interface Player {
  id: string;
  display_name: string;
  handicap_index?: number;
  is_guest?: boolean;
}

interface Tee {
  id: string;
  tee_name: string;
  tee_color: string;
  gender: string;
  slope_rating: number;
  course_rating: number;
  par: number;
}

export default function TeesScreen() {
  const router = useRouter();
  const params = useLocalSearchParams();
  
  // Parse data from previous steps
  const courseData = params.courseData ? JSON.parse(params.courseData as string) : null;
  const playersData = params.playersData ? JSON.parse(params.playersData as string) : [];
  const gameTypesData = params.gameTypesData ? JSON.parse(params.gameTypesData as string) : [];
  const teamsData = params.teamsData && params.teamsData !== 'null' 
    ? JSON.parse(params.teamsData as string) 
    : null;
  const playMode = params.playMode || 'individual';
  
  // Parse dynamic tees from Step 1
  const teesData: Tee[] = params.teesData ? JSON.parse(params.teesData as string) : [];
  
  // Parse round settings from Step 2
  const holesToPlay = params.holesToPlay ? parseInt(params.holesToPlay as string) : 18;
  const startHole = params.startHole ? parseInt(params.startHole as string) : 1;
  
  // Determine step number based on whether Teams step was shown
  const stepNumber = playersData.length === 4 ? "Step 6 of 6" : "Step 5 of 5";
  
  console.log('Received in Tees step (Step 6):', { 
    courseData, 
    playersData, 
    gameTypesData, 
    teamsData, 
    playMode, 
    teesData, 
    stepNumber,
    holesToPlay,
    startHole,
  });
  
  // Initialize all players with first tee
  const initialTees: { [key: string]: string } = {};
  playersData.forEach((player: Player) => {
    initialTees[player.id] = teesData[0]?.tee_color || 'blue';
  });
  
  const [playerTees, setPlayerTees] = useState<{ [key: string]: string }>(initialTees);
  const [creating, setCreating] = useState(false);
  
  const handleTeeSelect = (playerId: string, teeColor: string) => {
    setPlayerTees(prev => ({ ...prev, [playerId]: teeColor }));
  };
  
  // Helper function to get color code for display
  const getTeeDisplayColor = (teeColor: string): string => {
    const colorMap: { [key: string]: string } = {
      'championship': '#FFD700',
      'blue': '#0066CC',
      'white': '#FFFFFF',
      'red': '#DC143C',
      'yellow': '#FFD700',
      'black': '#000000',
      'green': '#00A86B',
      'orange': '#FF8C00',
    };
    return colorMap[teeColor.toLowerCase()] || '#808080';
  };
  
  const handleCreateRound = async () => {
    if (creating) return;
    
    setCreating(true);
    
    try {
      // Get current user
      const { data: { user }, error: userError } = await supabase.auth.getUser();
      
      if (userError || !user) {
        Alert.alert('Error', 'Not authenticated');
        setCreating(false);
        return;
      }
      
      // Prepare payload for Edge Function
      // Backend will handle guest player creation
      const payload = {
        course_id: courseData.id,
        created_by: user.id,
        game_types: gameTypesData,
        holes_to_play: holesToPlay, // NEW: Round settings!
        start_hole: startHole, // NEW: Round settings!
        players: playersData.map((player: Player) => ({
          player_id: player.is_guest ? null : player.id,
          tee_color: playerTees[player.id],
          // Include guest info for backend to create
          guest_info: player.is_guest ? {
            display_name: player.display_name,
            handicap_index: player.handicap_index || null,
          } : null,
        })),
        teams: teamsData,
        play_mode: playMode,
        carryover_enabled: params.carryoverEnabled === 'true',
      };
      
      console.log('Creating round with payload:', payload);
      
      // Call Edge Function
      const { data, error } = await supabase.functions.invoke('create-round', {
        body: payload,
      });
      
      if (error) {
        console.error('Edge Function error:', error);
        // Try to get the actual error body
        try {
          const errorContext = error.context;
          if (errorContext && errorContext.json) {
            const errorBody = await errorContext.json();
            console.error('Edge Function error body:', JSON.stringify(errorBody));
            Alert.alert('Error', errorBody?.error || error.message || 'Failed to create round');
          } else {
            Alert.alert('Error', error.message || 'Failed to create round');
          }
        } catch (e) {
          Alert.alert('Error', error.message || 'Failed to create round');
        }
        setCreating(false);
        return;
      }
      
      console.log('Round created successfully:', data);
      
      // Navigate to the round
      Alert.alert('Success', 'Round created successfully!', [
        {
          text: 'OK',
          onPress: () => router.replace('/(tabs)'),
        },
      ]);
    } catch (error: any) {
      console.error('Error creating round:', error);
      Alert.alert('Error', error.message || 'Failed to create round');
      setCreating(false);
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

        <Text style={styles.stepIndicator}>{stepNumber}</Text>
      </View>

      <ScrollView style={styles.scrollView} showsVerticalScrollIndicator={false}>
        {/* Course Info */}
        {courseData && (
          <View style={styles.courseCard}>
            <View style={styles.courseInfo}>
              <Text style={styles.courseName}>{courseData.name}</Text>
              <Text style={styles.courseDetails}>
                {holesToPlay} holes • Starting at hole {startHole}
              </Text>
            </View>
            <Ionicons name="golf" size={24} color="#006B4E" />
          </View>
        )}

        {/* Instructions */}
        <View style={styles.instructionCard}>
          <Text style={styles.instructionTitle}>Select Tees</Text>
          <Text style={styles.instructionText}>
            Choose which tees each player will play from
          </Text>
        </View>

        {/* Tee Selection for Each Player */}
        {playersData.map((player: Player) => (
          <View key={player.id} style={styles.playerCard}>
            <View style={styles.playerInfo}>
              <Text style={styles.playerName}>{player.display_name}</Text>
              {player.is_guest && <Text style={styles.guestBadge}>Guest</Text>}
              <Text style={styles.playerHandicap}>
                HCP: {player.handicap_index?.toFixed(1) || 'N/A'}
              </Text>
            </View>

            <View style={styles.teeButtons}>
              {teesData.map((tee) => (
                <TouchableOpacity
                  key={tee.id}
                  style={[
                    styles.teeButton,
                    playerTees[player.id] === tee.tee_color && styles.teeButtonSelected,
                    { borderColor: getTeeDisplayColor(tee.tee_color) },
                  ]}
                  onPress={() => handleTeeSelect(player.id, tee.tee_color)}
                  activeOpacity={0.7}
                >
                  <View
                    style={[
                      styles.teeColorDot,
                      { backgroundColor: getTeeDisplayColor(tee.tee_color) },
                      tee.tee_color.toLowerCase() === 'white' && styles.teeColorDotBorder,
                    ]}
                  />
                  <Text
                    style={[
                      styles.teeButtonText,
                      playerTees[player.id] === tee.tee_color && styles.teeButtonTextSelected,
                    ]}
                  >
                    {tee.tee_name}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>
        ))}
      </ScrollView>

      {/* Bottom Button */}
      <View style={styles.bottomContainer}>
        <TouchableOpacity
          style={[styles.createButton, creating && styles.createButtonDisabled]}
          onPress={handleCreateRound}
          disabled={creating}
          activeOpacity={creating ? 1 : 0.8}
        >
          {creating ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.createButtonText}>Create Round</Text>
          )}
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
  courseCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    marginHorizontal: 20,
    marginTop: 20,
    marginBottom: 16,
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
  courseInfo: {
    flex: 1,
  },
  courseName: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#1A1A1A',
    marginBottom: 4,
  },
  courseDetails: {
    fontSize: 14,
    color: '#7A7A7A',
  },
  instructionCard: {
    backgroundColor: '#E8F2EE',
    padding: 16,
    marginHorizontal: 20,
    marginBottom: 24,
    borderRadius: 12,
    borderLeftWidth: 4,
    borderLeftColor: '#006B4E',
  },
  instructionTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#1A1A1A',
    marginBottom: 4,
  },
  instructionText: {
    fontSize: 14,
    color: '#7A7A7A',
  },
  playerCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    marginHorizontal: 20,
    marginBottom: 16,
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
    marginBottom: 12,
  },
  playerName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1A1A1A',
    marginBottom: 4,
  },
  guestBadge: {
    fontSize: 12,
    color: '#006B4E',
    fontWeight: '600',
    backgroundColor: '#E8F2EE',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 8,
    alignSelf: 'flex-start',
    marginBottom: 4,
  },
  playerHandicap: {
    fontSize: 14,
    color: '#7A7A7A',
  },
  teeButtons: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  teeButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 8,
    borderWidth: 2,
    borderColor: '#E5E5E5',
    backgroundColor: '#fff',
  },
  teeButtonSelected: {
    backgroundColor: '#E8F2EE',
  },
  teeColorDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
    marginRight: 6,
  },
  teeColorDotBorder: {
    borderWidth: 1,
    borderColor: '#E5E5E5',
  },
  teeButtonText: {
    fontSize: 14,
    color: '#7A7A7A',
    fontWeight: '500',
  },
  teeButtonTextSelected: {
    color: '#006B4E',
    fontWeight: '600',
  },
  bottomContainer: {
    paddingHorizontal: 20,
    paddingVertical: 16,
    backgroundColor: '#fff',
    borderTopWidth: 1,
    borderTopColor: '#E5E5E5',
  },
  createButton: {
    backgroundColor: '#006B4E',
    paddingVertical: 16,
    borderRadius: 12,
    alignItems: 'center',
  },
  createButtonDisabled: {
    opacity: 0.5,
  },
  createButtonText: {
    color: '#fff',
    fontSize: 17,
    fontWeight: '600',
  },
});