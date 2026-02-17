import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
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
interface Course {
  id: string;
  name: string;
  [key: string]: any;
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

export default function CreateRoundScreen() {
  const router = useRouter();
  const [courses, setCourses] = useState<Course[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');

  // Fetch courses from Supabase
  const fetchCourses = async () => {
    try {
      setLoading(true);
      const { data: { user } } = await supabase.auth.getUser();

      if (!user) {
        setCourses([]);
        return;
      }

      const { data: coursesData, error } = await supabase
        .from('courses')
        .select('*')
        .order('name');

      if (error) {
        console.error('Error fetching courses:', error);
        setCourses([]);
        return;
      }

      console.log('Courses data from DB:', coursesData);

      const formattedCourses: Course[] = coursesData.map((course: any) => ({
        ...course,
        id: course.id,
        name: course.name,
      }));

      setCourses(formattedCourses);
    } catch (error) {
      console.error('Error in fetchCourses:', error);
      setCourses([]);
    } finally {
      setLoading(false);
    }
  };

  // Filter courses based on search query
  const filteredCourses = courses.filter(course =>
    course.name.toLowerCase().includes(searchQuery.toLowerCase())
  );

  // Handle course selection - fetch tees first, then navigate
  const handleCourseSelect = async (course: Course) => {
    try {
      // Show loading state
      setLoading(true);

      // Fetch tees for this course
      const { data: teesData, error: teesError } = await supabase
        .from('course_tees')
        .select('id, tee_name, tee_color, gender, slope_rating, course_rating, par')
        .eq('course_id', course.id)
        .order('tee_name');

      if (teesError) {
        console.error('Error fetching tees:', teesError);
        Alert.alert('Error', 'Failed to load tees for this course');
        setLoading(false);
        return;
      }

      if (!teesData || teesData.length === 0) {
        Alert.alert('Error', 'No tees found for this course');
        setLoading(false);
        return;
      }

      console.log('Tees for course:', teesData);

      // Navigate to Step 2 with course AND tees data
      router.push({
        pathname: '/create-round/round-settings',
        params: {
          courseId: course.id,
          courseName: course.name,
          courseData: JSON.stringify(course),
          teesData: JSON.stringify(teesData), // Pass tees data!
        },
      });

      setLoading(false);
    } catch (error) {
      console.error('Error in handleCourseSelect:', error);
      Alert.alert('Error', 'Failed to select course');
      setLoading(false);
    }
  };

  // Fetch courses on component mount
  useEffect(() => {
    fetchCourses();
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

        <Text style={styles.stepIndicator}>Step 1 of 5</Text>
      </View>

      <ScrollView style={styles.scrollView} showsVerticalScrollIndicator={false}>
        {/* Search Input */}
        <View style={styles.searchContainer}>
          <View style={styles.searchInputContainer}>
            <Ionicons name="search" size={20} color="#7A7A7A" style={styles.searchIcon} />
            <TextInput
              style={styles.searchInput}
              placeholder="Search courses..."
              placeholderTextColor="#7A7A7A"
              value={searchQuery}
              onChangeText={setSearchQuery}
            />
          </View>
        </View>

        {/* Course List */}
        <View style={styles.contentContainer}>
          <Text style={styles.sectionTitle}>Select Course</Text>

          {loading ? (
            <View style={styles.loadingContainer}>
              <ActivityIndicator size="large" color="#006B4E" />
              <Text style={styles.loadingText}>Loading courses...</Text>
            </View>
          ) : filteredCourses.length === 0 ? (
            <View style={styles.emptyContainer}>
              <Text style={styles.emptyText}>
                {searchQuery ? 'No courses found matching your search' : 'No courses found'}
              </Text>
            </View>
          ) : (
            <View style={styles.coursesList}>
              {filteredCourses.map((course) => (
                <TouchableOpacity
                  key={course.id}
                  style={styles.courseCard}
                  onPress={() => handleCourseSelect(course)}
                  activeOpacity={0.7}
                >
                  <View style={styles.courseInfo}>
                    <Text style={styles.courseName}>{course.name}</Text>
                    <Text style={styles.courseDetails}>
                      18 holes • Par 72
                    </Text>
                  </View>
                  <Ionicons name="chevron-forward" size={20} color="#7A7A7A" />
                </TouchableOpacity>
              ))}
            </View>
          )}
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
  searchContainer: {
    paddingHorizontal: 20,
    paddingVertical: 16,
    backgroundColor: '#fff',
  },
  searchInputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#FAFAFA',
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
  contentContainer: {
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 40,
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#1A1A1A',
    marginBottom: 16,
  },
  loadingContainer: {
    padding: 40,
    alignItems: 'center',
    justifyContent: 'center',
  },
  loadingText: {
    marginTop: 12,
    fontSize: 16,
    color: '#7A7A7A',
  },
  emptyContainer: {
    padding: 40,
    alignItems: 'center',
    justifyContent: 'center',
  },
  emptyText: {
    fontSize: 16,
    color: '#7A7A7A',
    textAlign: 'center',
  },
  coursesList: {
    gap: 12,
  },
  courseCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
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
  courseInfo: {
    flex: 1,
  },
  courseName: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#1A1A1A',
    marginBottom: 4,
  },
  courseDetails: {
    fontSize: 14,
    color: '#7A7A7A',
  },
});