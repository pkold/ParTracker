import { Picker } from '@react-native-picker/picker';
import { Stack, router, useLocalSearchParams } from 'expo-router';
import React, { useState } from 'react';
import {
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';

// Type definitions
type HolesToPlay = 9 | 18;
type StartingHoleOption = 'front' | 'back' | 'custom';

/**
 * Round Settings Screen - Step 2 of Create Round Flow
 * 
 * Allows users to configure:
 * - Number of holes to play (9 or 18)
 * - Starting hole (front nine, back nine, or custom gun start)
 */
export default function RoundSettingsScreen() {
  // Get course info from navigation params
  const params = useLocalSearchParams();
  const courseName = params.courseName as string || 'Selected Course';

  // State
  const [holesToPlay, setHolesToPlay] = useState<HolesToPlay>(18);
  const [startingHoleOption, setStartingHoleOption] = useState<StartingHoleOption>('front');
  const [customStartHole, setCustomStartHole] = useState<number>(1);

  // Calculate actual starting hole based on selection
  const actualStartHole =
    startingHoleOption === 'front'
      ? 1
      : startingHoleOption === 'back'
      ? 10
      : customStartHole;

  // Handle continue button press
  const handleContinue = () => {
    // Navigate to players screen with all collected data
    router.push({
      pathname: '/create-round/players',
      params: {
        courseId: params.courseId,           // PASS FORWARD!
        courseName: params.courseName,       // PASS FORWARD!
        courseData: params.courseData,       // PASS FORWARD!
        teesData: params.teesData,           // PASS FORWARD!
        holesToPlay,                         // NEW
        startHole: actualStartHole,                           // NEW
      },
    });
  };

  return (
    <>
      <Stack.Screen
        options={{
          title: 'Round Settings',
          headerBackTitle: 'Back',
        }}
      />

      <View style={styles.container}>
        {/* Course name subtitle */}
        <View style={styles.header}>
          <Text style={styles.subtitle}>{courseName}</Text>
          <Text style={styles.stepIndicator}>Step 2 of 6</Text>
        </View>

        {/* Scrollable Content */}
        <ScrollView
          style={styles.content}
          contentContainerStyle={styles.contentContainer}
          showsVerticalScrollIndicator={false}
        >
          {/* Number of Holes Section */}
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Number of Holes</Text>
            
            <TouchableOpacity
              style={[
                styles.optionCard,
                holesToPlay === 18 && styles.optionCardSelected,
              ]}
              onPress={() => setHolesToPlay(18)}
              activeOpacity={0.7}
            >
              <View style={styles.radioContainer}>
                <View
                  style={[
                    styles.radioOuter,
                    holesToPlay === 18 && styles.radioOuterSelected,
                  ]}
                >
                  {holesToPlay === 18 && <View style={styles.radioInner} />}
                </View>
              </View>
              <View style={styles.optionContent}>
                <Text style={styles.optionLabel}>18 holes</Text>
                <Text style={styles.optionDescription}>Full round</Text>
              </View>
            </TouchableOpacity>

            <TouchableOpacity
              style={[
                styles.optionCard,
                holesToPlay === 9 && styles.optionCardSelected,
              ]}
              onPress={() => setHolesToPlay(9)}
              activeOpacity={0.7}
            >
              <View style={styles.radioContainer}>
                <View
                  style={[
                    styles.radioOuter,
                    holesToPlay === 9 && styles.radioOuterSelected,
                  ]}
                >
                  {holesToPlay === 9 && <View style={styles.radioInner} />}
                </View>
              </View>
              <View style={styles.optionContent}>
                <Text style={styles.optionLabel}>9 holes</Text>
                <Text style={styles.optionDescription}>Half round</Text>
              </View>
            </TouchableOpacity>
          </View>

          {/* Starting Hole Section */}
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Starting Hole</Text>

            <TouchableOpacity
              style={[
                styles.optionCard,
                startingHoleOption === 'front' && styles.optionCardSelected,
              ]}
              onPress={() => setStartingHoleOption('front')}
              activeOpacity={0.7}
            >
              <View style={styles.radioContainer}>
                <View
                  style={[
                    styles.radioOuter,
                    startingHoleOption === 'front' && styles.radioOuterSelected,
                  ]}
                >
                  {startingHoleOption === 'front' && <View style={styles.radioInner} />}
                </View>
              </View>
              <View style={styles.optionContent}>
                <Text style={styles.optionLabel}>Hole 1 (Front Nine)</Text>
                <Text style={styles.optionDescription}>Standard start</Text>
              </View>
            </TouchableOpacity>

            <TouchableOpacity
              style={[
                styles.optionCard,
                startingHoleOption === 'back' && styles.optionCardSelected,
              ]}
              onPress={() => setStartingHoleOption('back')}
              activeOpacity={0.7}
            >
              <View style={styles.radioContainer}>
                <View
                  style={[
                    styles.radioOuter,
                    startingHoleOption === 'back' && styles.radioOuterSelected,
                  ]}
                >
                  {startingHoleOption === 'back' && <View style={styles.radioInner} />}
                </View>
              </View>
              <View style={styles.optionContent}>
                <Text style={styles.optionLabel}>Hole 10 (Back Nine)</Text>
                <Text style={styles.optionDescription}>Back nine start</Text>
              </View>
            </TouchableOpacity>

            <TouchableOpacity
              style={[
                styles.optionCard,
                startingHoleOption === 'custom' && styles.optionCardSelected,
              ]}
              onPress={() => setStartingHoleOption('custom')}
              activeOpacity={0.7}
            >
              <View style={styles.radioContainer}>
                <View
                  style={[
                    styles.radioOuter,
                    startingHoleOption === 'custom' && styles.radioOuterSelected,
                  ]}
                >
                  {startingHoleOption === 'custom' && <View style={styles.radioInner} />}
                </View>
              </View>
              <View style={styles.optionContent}>
                <Text style={styles.optionLabel}>Custom (Gun Start)</Text>
                <Text style={styles.optionDescription}>Select any hole</Text>
              </View>
            </TouchableOpacity>

            {/* Custom hole picker */}
            {startingHoleOption === 'custom' && (
              <View style={styles.customPicker}>
                <Text style={styles.pickerLabel}>Starting Hole Number</Text>
                <View style={styles.pickerContainer}>
                  <Picker
                    selectedValue={customStartHole}
                    onValueChange={(value) => setCustomStartHole(value)}
                    style={styles.picker}
                    itemStyle={styles.pickerItem}
                  >
                    {Array.from({ length: 18 }, (_, i) => i + 1).map((hole) => (
                      <Picker.Item
                        key={hole}
                        label={`Hole ${hole}`}
                        value={hole}
                      />
                    ))}
                  </Picker>
                </View>
              </View>
            )}
          </View>

          {/* Summary */}
          <View style={styles.summary}>
            <Text style={styles.summaryText}>
              You will play{' '}
              <Text style={styles.summaryBold}>{holesToPlay} holes</Text>{' '}
              starting from{' '}
              <Text style={styles.summaryBold}>Hole {actualStartHole}</Text>
            </Text>
          </View>
        </ScrollView>

        {/* Bottom Navigation */}
        <View style={styles.footer}>
          <TouchableOpacity
            style={styles.continueButton}
            onPress={handleContinue}
            activeOpacity={0.8}
          >
            <Text style={styles.continueButtonText}>Continue</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.backButton}
            onPress={() => router.back()}
            activeOpacity={0.6}
          >
            <Text style={styles.backButtonText}>Back</Text>
          </TouchableOpacity>
        </View>
      </View>
    </>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#FFFFFF',
  },
  header: {
    paddingHorizontal: 24,
    paddingTop: 16,
    paddingBottom: 20,
    borderBottomWidth: 1,
    borderBottomColor: '#E5E7EB',
  },
  subtitle: {
    fontSize: 16,
    color: '#6B7280',
    fontFamily: Platform.select({ ios: 'Inter', android: 'Inter' }),
    marginBottom: 8,
  },
  stepIndicator: {
    fontSize: 14,
    color: '#9CA3AF',
    fontFamily: Platform.select({ ios: 'Inter', android: 'Inter' }),
  },
  content: {
    flex: 1,
  },
  contentContainer: {
    paddingHorizontal: 24,
    paddingTop: 24,
    paddingBottom: 120, // Space for footer
  },
  section: {
    marginBottom: 32,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#1F2937',
    fontFamily: Platform.select({ ios: 'Inter', android: 'Inter' }),
    marginBottom: 16,
  },
  optionCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#FFFFFF',
    borderWidth: 2,
    borderColor: '#E5E7EB',
    borderRadius: 12,
    padding: 16,
    marginBottom: 12,
  },
  optionCardSelected: {
    borderColor: '#2D5016', // Forest green
    backgroundColor: '#F0F4ED', // Light green tint
  },
  radioContainer: {
    marginRight: 16,
  },
  radioOuter: {
    width: 24,
    height: 24,
    borderRadius: 12,
    borderWidth: 2,
    borderColor: '#9CA3AF',
    alignItems: 'center',
    justifyContent: 'center',
  },
  radioOuterSelected: {
    borderColor: '#2D5016',
  },
  radioInner: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: '#2D5016',
  },
  optionContent: {
    flex: 1,
  },
  optionLabel: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1F2937',
    fontFamily: Platform.select({ ios: 'Inter', android: 'Inter' }),
    marginBottom: 2,
  },
  optionDescription: {
    fontSize: 14,
    color: '#6B7280',
    fontFamily: Platform.select({ ios: 'Inter', android: 'Inter' }),
  },
  customPicker: {
    marginTop: 16,
    backgroundColor: '#F9FAFB',
    borderWidth: 1,
    borderColor: '#E5E7EB',
    borderRadius: 12,
    padding: 16,
  },
  pickerLabel: {
    fontSize: 14,
    fontWeight: '500',
    color: '#1F2937',
    fontFamily: Platform.select({ ios: 'Inter', android: 'Inter' }),
    marginBottom: 8,
  },
  pickerContainer: {
    backgroundColor: '#FFFFFF',
    borderWidth: 1,
    borderColor: '#E5E7EB',
    borderRadius: 8,
    overflow: 'hidden',
  },
  picker: {
    height: Platform.OS === 'ios' ? 180 : 50,
  },
  pickerItem: {
    fontSize: 18,
    fontFamily: Platform.select({ ios: 'DM Mono', android: 'DM Mono' }),
  },
  summary: {
    backgroundColor: '#F9FAFB',
    borderWidth: 1,
    borderColor: '#E5E7EB',
    borderRadius: 12,
    padding: 16,
    marginTop: 8,
  },
  summaryText: {
    fontSize: 14,
    color: '#6B7280',
    fontFamily: Platform.select({ ios: 'Inter', android: 'Inter' }),
    lineHeight: 20,
  },
  summaryBold: {
    fontWeight: '600',
    color: '#1F2937',
  },
  footer: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: '#FFFFFF',
    borderTopWidth: 1,
    borderTopColor: '#E5E7EB',
    paddingHorizontal: 24,
    paddingVertical: 16,
    paddingBottom: Platform.OS === 'ios' ? 32 : 16,
  },
  continueButton: {
    backgroundColor: '#2D5016', // Forest green
    borderRadius: 12,
    height: 56,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 12,
    ...Platform.select({
      ios: {
        shadowColor: '#2D5016',
        shadowOffset: { width: 0, height: 4 },
        shadowOpacity: 0.3,
        shadowRadius: 8,
      },
      android: {
        elevation: 4,
      },
    }),
  },
  continueButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#FFFFFF',
    fontFamily: Platform.select({ ios: 'Inter', android: 'Inter' }),
  },
  backButton: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
  },
  backButtonText: {
    fontSize: 14,
    color: '#6B7280',
    fontFamily: Platform.select({ ios: 'Inter', android: 'Inter' }),
  },
});