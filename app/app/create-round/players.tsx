import { Ionicons } from '@expo/vector-icons';
import { useLocalSearchParams, useRouter } from 'expo-router';
import React, { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { supabase } from '../../lib/supabase';

// Types
interface Player {
  id: string;
  display_name: string;
  email?: string;
  handicap_index?: number;
  phone?: string;
  user_id?: string;
  is_guest?: boolean;
}

interface Friend {
  id: string;
  display_name: string;
  email?: string;
  handicap_index?: number;
  phone?: string;
  user_id?: string;
}

interface Course {
  id: string;
  name: string;
  [key: string]: any;
}

export default function PlayersSelectionScreen() {
  const router = useRouter();
  const params = useLocalSearchParams();
  const [course, setCourse] = useState<Course | null>(null);
  const [friends, setFriends] = useState<Friend[]>([]);
  const [selectedPlayers, setSelectedPlayers] = useState<Player[]>([]);
  const [loadingFriends, setLoadingFriends] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [showGuestInput, setShowGuestInput] = useState(false);
  const [guestName, setGuestName] = useState('');
  const [guestHandicap, setGuestHandicap] = useState('');

  // Get selected course and tees from params
  useEffect(() => {
    // Parse the tees data from Step 1
    const teesData = params.teesData ? JSON.parse(params.teesData as string) : [];
    
    // Parse the course data from Step 1
    const courseData = params.courseData ? JSON.parse(params.courseData as string) : 
                      params.course ? JSON.parse(params.course as string) : null;
    
    console.log('Received in Step 3:', { courseData, teesData, holesToPlay: params.holesToPlay, startHole: params.startHole });
    
    if (courseData) {
      setCourse(courseData);
    }
  }, [params.courseData, params.course, params.teesData, params.holesToPlay, params.startHole]);

  // Fetch friends from Supabase
  const fetchFriends = async () => {
    try {
      setLoadingFriends(true);

      const { data, error } = await supabase
        .from('players')
        .select('*');

      if (error) {
        console.error('Error fetching friends:', error);
        setFriends([]);
        return;
      }

      if (data) {
        console.log('Players data:', data);
        setFriends(data || []);
      } else {
        setFriends([]);
      }
    } catch (error) {
      console.error('Error in fetchFriends:', error);
      setFriends([]);
    } finally {
      setLoadingFriends(false);
    }
  };

  // Filter friends based on search query
  const filteredFriends = friends.filter(friend =>
    (friend.display_name || '').toLowerCase().includes(searchQuery.toLowerCase())
  );

  // Add player to selected list
  const addPlayer = (player: Friend | Player) => {
    if (selectedPlayers.length >= 4) {
      console.log('Maximum 4 players reached');
      return;
    }

    if (!selectedPlayers.find(p => p.id === player.id)) {
      setSelectedPlayers([...selectedPlayers, { ...player }]);
    }
  };

  // Remove player from selected list
  const removePlayer = (playerId: string) => {
    setSelectedPlayers(selectedPlayers.filter(p => p.id !== playerId));
  };

  // Add guest player
  const addGuestPlayer = () => {
    if (!guestName.trim()) {
      Alert.alert('Error', 'Please enter a guest name');
      return;
    }

    if (selectedPlayers.length >= 4) {
      Alert.alert('Maximum Players', 'You can add a maximum of 4 players per round');
      return;
    }

    const guestPlayer: Player = {
      id: `guest_${Date.now()}`,
      display_name: guestName.trim(),
      handicap_index: guestHandicap ? parseFloat(guestHandicap) : undefined,
      is_guest: true,
    };

    addPlayer(guestPlayer);
    setGuestName('');
    setGuestHandicap('');
    setShowGuestInput(false);
  };

  // Handle next button press
  const handleNext = () => {
    if (selectedPlayers.length === 0) {
      Alert.alert('Error', 'Please select at least one player');
      return;
    }

    if (!course) {
      Alert.alert('Error', 'Course data is missing');
      return;
    }

    // Navigate to Step 4 with course, players, tees, and round settings data
    router.push({
      pathname: '/create-round/game-types',
      params: {
        courseId: course.id,
        courseName: course.name,
        courseData: JSON.stringify(course),
        playersData: JSON.stringify(selectedPlayers),
        playerCount: selectedPlayers.length,
        teesData: params.teesData, // Pass tees forward!
        holesToPlay: params.holesToPlay, // Pass round settings forward!
        startHole: params.startHole, // Pass round settings forward!
      },
    });
  };

  // Fetch friends on component mount
  useEffect(() => {
    fetchFriends();
  }, []);

  return (
    <SafeAreaView style={styles.safeArea} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity style={styles.backButton} onPress={() => router.back()} activeOpacity={0.7}>
          <Ionicons name="chevron-back" size={24} color="#006B4E" />
          <Text style={styles.backButtonText}>Back</Text>
        </TouchableOpacity>

        <Text style={styles.headerTitle}>New Round</Text>

        <Text style={styles.stepIndicator}>Step 3 of 6</Text>
      </View>

      <ScrollView style={styles.scrollView} showsVerticalScrollIndicator={false}>
        {/* Selected Course */}
        {course && (
          <View style={styles.courseCard}>
            <View style={styles.courseInfo}>
              <Text style={styles.courseName}>{course.name}</Text>
              <Text style={styles.courseDetails}>18 holes • Par 72</Text>
            </View>
            <Ionicons name="golf" size={24} color="#006B4E" />
          </View>
        )}

        {/* Selected Players Summary */}
        {selectedPlayers.length > 0 && (
          <View style={styles.selectedSummary}>
            <Text style={styles.selectedSummaryText}>
              {selectedPlayers.length}/4 Players Selected
            </Text>
          </View>
        )}

        {/* Selected Players Section */}
        <View style={[
          styles.sectionContainer,
          selectedPlayers.length > 0 && styles.selectedSectionHighlight,
        ]}>
          <View style={styles.sectionHeader}>
            <Text style={[
              styles.sectionTitle,
              selectedPlayers.length >= 4 && styles.sectionTitleWarning,
            ]}>
              Playing ({selectedPlayers.length}/4)
            </Text>
            {selectedPlayers.length === 0 && (
              <Text style={styles.infoText}>You can add up to 4 players per round</Text>
            )}
          </View>

          {selectedPlayers.length === 0 ? (
            <View style={styles.emptyContainer}>
              <Text style={styles.emptyText}>No players selected yet</Text>
            </View>
          ) : (
            <View style={styles.selectedPlayersList}>
              {selectedPlayers.map((player) => (
                <View key={player.id} style={styles.selectedPlayerCard}>
                  <View style={styles.selectedPlayerInfo}>
                    <Text style={styles.selectedPlayerName}>{player.display_name}</Text>
                    {player.is_guest && <Text style={styles.guestBadge}>Guest</Text>}
                    {!player.is_guest && (
                      <Text style={styles.selectedPlayerHandicap}>
                        HCP: {player.handicap_index?.toFixed(1) || 'N/A'}
                      </Text>
                    )}
                  </View>
                  <TouchableOpacity
                    style={styles.removeButton}
                    onPress={() => removePlayer(player.id)}
                    activeOpacity={0.7}
                  >
                    <Ionicons name="close-circle" size={24} color="#DC2626" />
                  </TouchableOpacity>
                </View>
              ))}
            </View>
          )}
        </View>

        {/* Add Players Section */}
        <View style={styles.sectionContainer}>
          <Text style={styles.sectionTitle}>Add Players</Text>

          {/* Search Input */}
          <View style={styles.searchContainer}>
            <View style={styles.searchInputContainer}>
              <Ionicons name="search" size={20} color="#7A7A7A" style={styles.searchIcon} />
              <TextInput
                style={styles.searchInput}
                placeholder="Search friends..."
                placeholderTextColor="#7A7A7A"
                value={searchQuery}
                onChangeText={setSearchQuery}
              />
            </View>
          </View>

          {/* Add Guest Player Button */}
          <TouchableOpacity
            style={[
              styles.addGuestButton,
              selectedPlayers.length >= 4 && styles.addGuestButtonDisabled,
            ]}
            onPress={() => setShowGuestInput(!showGuestInput)}
            activeOpacity={selectedPlayers.length >= 4 ? 1 : 0.7}
            disabled={selectedPlayers.length >= 4}
          >
            <Ionicons
              name="person-add"
              size={20}
              color={selectedPlayers.length >= 4 ? "#CCC" : "#006B4E"}
            />
            <Text style={[
              styles.addGuestText,
              selectedPlayers.length >= 4 && styles.addGuestTextDisabled,
            ]}>
              {selectedPlayers.length >= 4 ? 'Maximum 4 Players' : 'Add Guest Player'}
            </Text>
          </TouchableOpacity>

          {/* Guest Input Section */}
          {showGuestInput && (
            <View style={styles.guestInputContainer}>
              <TextInput
                style={styles.input}
                placeholder="Guest name"
                placeholderTextColor="#7A7A7A"
                value={guestName}
                onChangeText={setGuestName}
              />
              <TextInput
                style={styles.input}
                placeholder="Handicap index (optional)"
                placeholderTextColor="#7A7A7A"
                value={guestHandicap}
                onChangeText={setGuestHandicap}
                keyboardType="numeric"
              />
              <TouchableOpacity style={styles.addButton} onPress={addGuestPlayer} activeOpacity={0.7}>
                <Text style={styles.addButtonText}>Add Guest</Text>
              </TouchableOpacity>
            </View>
          )}

          {/* Friends List */}
          {loadingFriends ? (
            <View style={styles.loadingContainer}>
              <ActivityIndicator size="small" color="#006B4E" />
              <Text style={styles.loadingText}>Loading friends...</Text>
            </View>
          ) : filteredFriends.length === 0 ? (
            <View style={styles.emptyContainer}>
              <Text style={styles.emptyText}>
                {searchQuery ? 'No friends found matching your search' : 'No friends yet'}
              </Text>
            </View>
          ) : (
            <View style={styles.friendsList}>
              {filteredFriends.map((friend) => {
                const isAtMax = selectedPlayers.length >= 4;
                return (
                  <TouchableOpacity
                    key={friend.id}
                    style={[
                      styles.friendCard,
                      isAtMax && styles.friendCardDisabled,
                    ]}
                    onPress={() => addPlayer(friend)}
                    activeOpacity={isAtMax ? 1 : 0.7}
                    disabled={isAtMax}
                  >
                    <View style={styles.friendInfo}>
                      <Text style={[styles.friendName, isAtMax && styles.friendTextDisabled]}>
                        {friend.display_name}
                      </Text>
                      <Text style={[styles.friendHandicap, isAtMax && styles.friendTextDisabled]}>
                        HCP: {friend.handicap_index?.toFixed(1) || 'N/A'}
                      </Text>
                    </View>
                    <Ionicons
                      name="add-circle"
                      size={24}
                      color={isAtMax ? "#CCC" : "#006B4E"}
                    />
                  </TouchableOpacity>
                );
              })}
            </View>
          )}
        </View>
      </ScrollView>

      {/* Bottom Button */}
      <View style={styles.bottomContainer}>
        <TouchableOpacity
          style={[
            styles.nextButton,
            selectedPlayers.length === 0 && styles.nextButtonDisabled,
          ]}
          onPress={handleNext}
          disabled={selectedPlayers.length === 0}
          activeOpacity={selectedPlayers.length > 0 ? 0.8 : 1}
        >
          <Text style={[
            styles.nextButtonText,
            selectedPlayers.length === 0 && styles.nextButtonTextDisabled,
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
  selectedSummary: {
    backgroundColor: '#E8F5E9',
    padding: 12,
    marginHorizontal: 16,
    marginBottom: 16,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#006B4E',
    alignItems: 'center',
  },
  selectedSummaryText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#006B4E',
  },
  selectedSectionHighlight: {
    backgroundColor: '#F0F9F4',
    borderRadius: 12,
    padding: 16,
    marginHorizontal: 16,
    marginBottom: 16,
    borderWidth: 2,
    borderColor: '#006B4E',
  },
  sectionContainer: {
    marginBottom: 32,
    paddingHorizontal: 20,
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#1A1A1A',
  },
  sectionTitleWarning: {
    color: '#DC2626',
  },
  sectionHeader: {
    marginBottom: 16,
  },
  infoText: {
    fontSize: 14,
    color: '#7A7A7A',
    marginTop: 4,
  },
  searchContainer: {
    marginBottom: 16,
  },
  searchInputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#fff',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#E5E5E5',
    paddingHorizontal: 16,
    height: 48,
  },
  searchIcon: {
    marginRight: 12,
  },
  searchInput: {
    flex: 1,
    fontSize: 16,
    color: '#1A1A1A',
  },
  addGuestButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderRadius: 12,
    borderWidth: 2,
    borderColor: '#006B4E',
    marginBottom: 16,
  },
  addGuestButtonDisabled: {
    borderColor: '#CCC',
  },
  addGuestText: {
    fontSize: 16,
    color: '#006B4E',
    fontWeight: '600',
    marginLeft: 8,
  },
  addGuestTextDisabled: {
    color: '#CCC',
  },
  guestInputContainer: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
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
  input: {
    borderWidth: 1,
    borderColor: '#E5E5E5',
    borderRadius: 8,
    padding: 12,
    fontSize: 16,
    color: '#1A1A1A',
    marginBottom: 12,
  },
  addButton: {
    backgroundColor: '#006B4E',
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
  },
  addButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  loadingContainer: {
    padding: 20,
    alignItems: 'center',
    justifyContent: 'center',
  },
  loadingText: {
    marginTop: 8,
    fontSize: 14,
    color: '#7A7A7A',
  },
  emptyContainer: {
    padding: 20,
    alignItems: 'center',
    justifyContent: 'center',
  },
  emptyText: {
    fontSize: 16,
    color: '#7A7A7A',
    textAlign: 'center',
  },
  friendsList: {
    gap: 8,
  },
  friendCard: {
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
  friendCardDisabled: {
    opacity: 0.6,
  },
  friendTextDisabled: {
    color: '#CCC',
  },
  friendInfo: {
    flex: 1,
  },
  friendName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1A1A1A',
    marginBottom: 2,
  },
  friendHandicap: {
    fontSize: 14,
    color: '#7A7A7A',
  },
  selectedPlayersList: {
    gap: 8,
  },
  selectedPlayerCard: {
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
  selectedPlayerInfo: {
    flex: 1,
  },
  selectedPlayerName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1A1A1A',
    marginBottom: 2,
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
  },
  selectedPlayerHandicap: {
    fontSize: 14,
    color: '#7A7A7A',
  },
  removeButton: {
    padding: 4,
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