import React, { useState, useRef, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Dimensions,
  TouchableOpacity,
  Animated,
  FlatList,
  Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import AsyncStorage from '@react-native-async-storage/async-storage';

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');

const ONBOARDING_KEY = 'flames_up_onboarding_seen';

// Onboarding slides data
const SLIDES = [
  {
    id: '1',
    emoji: '🔥',
    title: 'Welcome to\nFlames-Up',
    subtitle: 'Your local community, connected.',
    description: 'Discover what\'s happening around you, meet real people, and share your world.',
    bgColor: '#1B4332',
    accentColor: '#F97316',
    iconName: 'flame',
    iconColor: '#F97316',
    features: ['Connect with locals', 'Share your story', 'Explore your city'],
  },
  {
    id: '2',
    emoji: '📍',
    title: 'Discover\nLocal Gems',
    subtitle: 'Places, events, and people near you.',
    description: 'Check in at your favorite spots, discover new places, and see what\'s trending in your neighborhood.',
    bgColor: '#0C3B2E',
    accentColor: '#10B981',
    iconName: 'compass',
    iconColor: '#10B981',
    features: ['Interactive map', 'Check-in at places', 'Verified local spots'],
  },
  {
    id: '3',
    emoji: '🗞️',
    title: 'Local\nPublishers',
    subtitle: 'News and stories from your community.',
    description: 'Follow verified local publishers for the best food, culture, events, and news in your area.',
    bgColor: '#14532D',
    accentColor: '#3B82F6',
    iconName: 'newspaper',
    iconColor: '#3B82F6',
    features: ['Verified publishers', 'Local news & events', 'Food & culture guides'],
  },
  {
    id: '4',
    emoji: '💬',
    title: 'Connect &\nShare',
    subtitle: 'Your voice matters here.',
    description: 'Post photos, send messages, share stories, and build real connections with people around you.',
    bgColor: '#052E16',
    accentColor: '#8B5CF6',
    iconName: 'chatbubbles',
    iconColor: '#8B5CF6',
    features: ['Photo & video messages', 'Stories & statuses', 'Real conversations'],
  },
];

export default function WelcomeScreen() {
  const router = useRouter();
  const [currentIndex, setCurrentIndex] = useState(0);
  const flatListRef = useRef<FlatList>(null);
  const scrollX = useRef(new Animated.Value(0)).current;

  // Animated values for each element
  const titleAnim = useRef(new Animated.Value(0)).current;
  const subtitleAnim = useRef(new Animated.Value(0)).current;
  const descAnim = useRef(new Animated.Value(0)).current;
  const featuresAnim = useRef(new Animated.Value(0)).current;
  const iconScale = useRef(new Animated.Value(0.3)).current;
  const iconRotate = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    animateIn();
  }, [currentIndex]);

  const animateIn = () => {
    titleAnim.setValue(0);
    subtitleAnim.setValue(0);
    descAnim.setValue(0);
    featuresAnim.setValue(0);
    iconScale.setValue(0.3);
    iconRotate.setValue(0);

    Animated.stagger(100, [
      Animated.spring(iconScale, { toValue: 1, friction: 4, tension: 50, useNativeDriver: true }),
      Animated.timing(iconRotate, { toValue: 1, duration: 600, useNativeDriver: true }),
      Animated.spring(titleAnim, { toValue: 1, friction: 6, tension: 40, useNativeDriver: true }),
      Animated.spring(subtitleAnim, { toValue: 1, friction: 6, tension: 40, useNativeDriver: true }),
      Animated.spring(descAnim, { toValue: 1, friction: 6, tension: 40, useNativeDriver: true }),
      Animated.spring(featuresAnim, { toValue: 1, friction: 6, tension: 40, useNativeDriver: true }),
    ]).start();
  };

  const handleComplete = async () => {
    await AsyncStorage.setItem(ONBOARDING_KEY, 'true');
    router.replace('/(auth)/login');
  };

  const handleGuest = async () => {
    await AsyncStorage.setItem(ONBOARDING_KEY, 'true');
    // Set a guest flag
    await AsyncStorage.setItem('guest_mode', 'true');
    router.replace('/(tabs)/home');
  };

  const goToSlide = (index: number) => {
    if (index >= 0 && index < SLIDES.length) {
      flatListRef.current?.scrollToIndex({ index, animated: true });
      setCurrentIndex(index);
    }
  };

  const handleNext = () => {
    if (currentIndex < SLIDES.length - 1) {
      goToSlide(currentIndex + 1);
    } else {
      handleComplete();
    }
  };

  const onViewableItemsChanged = useRef(({ viewableItems }: any) => {
    if (viewableItems.length > 0) {
      setCurrentIndex(viewableItems[0].index || 0);
    }
  }).current;

  const viewabilityConfig = useRef({ viewAreaCoveragePercentThreshold: 50 }).current;

  const rotateInterpolation = iconRotate.interpolate({
    inputRange: [0, 1],
    outputRange: ['-15deg', '0deg'],
  });

  const renderSlide = ({ item, index }: { item: typeof SLIDES[0]; index: number }) => {
    return (
      <View style={[styles.slide, { width: SCREEN_WIDTH, backgroundColor: item.bgColor }]}>
        <View style={styles.slideContent}>
          {/* Decorative circles */}
          <View style={[styles.decorCircle1, { backgroundColor: item.accentColor + '10' }]} />
          <View style={[styles.decorCircle2, { backgroundColor: item.accentColor + '08' }]} />
          <View style={[styles.decorCircle3, { backgroundColor: item.accentColor + '05' }]} />

          {/* Icon section */}
          <Animated.View style={[
            styles.iconContainer,
            {
              transform: [
                { scale: index === currentIndex ? iconScale : 1 },
                { rotate: index === currentIndex ? rotateInterpolation : '0deg' },
              ],
            },
          ]}>
            <View style={[styles.iconCircle, { backgroundColor: item.accentColor + '20' }]}>
              <View style={[styles.iconInner, { backgroundColor: item.accentColor + '30' }]}>
                <Ionicons name={item.iconName as any} size={48} color={item.accentColor} />
              </View>
            </View>
          </Animated.View>

          {/* Text content */}
          <Animated.View style={{
            opacity: index === currentIndex ? titleAnim : 1,
            transform: [{
              translateY: index === currentIndex ? titleAnim.interpolate({
                inputRange: [0, 1],
                outputRange: [30, 0],
              }) : 0,
            }],
          }}>
            <Text style={styles.title}>{item.title}</Text>
          </Animated.View>

          <Animated.View style={{
            opacity: index === currentIndex ? subtitleAnim : 1,
            transform: [{
              translateY: index === currentIndex ? subtitleAnim.interpolate({
                inputRange: [0, 1],
                outputRange: [20, 0],
              }) : 0,
            }],
          }}>
            <Text style={[styles.subtitle, { color: item.accentColor }]}>{item.subtitle}</Text>
          </Animated.View>

          <Animated.View style={{
            opacity: index === currentIndex ? descAnim : 1,
            transform: [{
              translateY: index === currentIndex ? descAnim.interpolate({
                inputRange: [0, 1],
                outputRange: [20, 0],
              }) : 0,
            }],
          }}>
            <Text style={styles.description}>{item.description}</Text>
          </Animated.View>

          {/* Feature pills */}
          <Animated.View style={[
            styles.featureList,
            {
              opacity: index === currentIndex ? featuresAnim : 1,
              transform: [{
                translateY: index === currentIndex ? featuresAnim.interpolate({
                  inputRange: [0, 1],
                  outputRange: [20, 0],
                }) : 0,
              }],
            },
          ]}>
            {item.features.map((feature, i) => (
              <View key={i} style={[styles.featurePill, { borderColor: item.accentColor + '40' }]}>
                <Ionicons name="checkmark-circle" size={16} color={item.accentColor} />
                <Text style={styles.featureText}>{feature}</Text>
              </View>
            ))}
          </Animated.View>
        </View>
      </View>
    );
  };

  const currentSlide = SLIDES[currentIndex];
  const isLastSlide = currentIndex === SLIDES.length - 1;

  return (
    <View style={[styles.container, { backgroundColor: currentSlide.bgColor }]}>
      <SafeAreaView style={styles.safeArea} edges={['top']}>
        {/* Skip button */}
        {!isLastSlide && (
          <TouchableOpacity style={styles.skipBtn} onPress={handleComplete}>
            <Text style={styles.skipText}>Skip</Text>
          </TouchableOpacity>
        )}
      </SafeAreaView>

      {/* Slides */}
      <FlatList
        ref={flatListRef}
        data={SLIDES}
        renderItem={renderSlide}
        keyExtractor={(item) => item.id}
        horizontal
        pagingEnabled
        showsHorizontalScrollIndicator={false}
        bounces={false}
        onViewableItemsChanged={onViewableItemsChanged}
        viewabilityConfig={viewabilityConfig}
        onScroll={Animated.event(
          [{ nativeEvent: { contentOffset: { x: scrollX } } }],
          { useNativeDriver: false }
        )}
        scrollEventThrottle={16}
      />

      {/* Bottom section */}
      <SafeAreaView style={styles.bottomSafe} edges={['bottom']}>
        <View style={styles.bottomSection}>
          {/* Dots */}
          <View style={styles.dotsContainer}>
            {SLIDES.map((_, index) => {
              const inputRange = [
                (index - 1) * SCREEN_WIDTH,
                index * SCREEN_WIDTH,
                (index + 1) * SCREEN_WIDTH,
              ];
              const dotWidth = scrollX.interpolate({
                inputRange,
                outputRange: [8, 28, 8],
                extrapolate: 'clamp',
              });
              const dotOpacity = scrollX.interpolate({
                inputRange,
                outputRange: [0.3, 1, 0.3],
                extrapolate: 'clamp',
              });
              return (
                <Animated.View
                  key={index}
                  style={[
                    styles.dot,
                    {
                      width: dotWidth,
                      opacity: dotOpacity,
                      backgroundColor: currentSlide.accentColor,
                    },
                  ]}
                />
              );
            })}
          </View>

          {/* Action buttons */}
          {isLastSlide ? (
            <View style={styles.lastSlideActions}>
              <TouchableOpacity
                style={[styles.getStartedBtn, { backgroundColor: currentSlide.accentColor }]}
                onPress={handleComplete}
              >
                <Text style={styles.getStartedText}>Get Started</Text>
                <Ionicons name="arrow-forward" size={20} color="#FFF" />
              </TouchableOpacity>

              <TouchableOpacity style={styles.guestBtn} onPress={handleGuest}>
                <Ionicons name="eye-outline" size={18} color="rgba(255,255,255,0.7)" />
                <Text style={styles.guestText}>Explore as Guest</Text>
              </TouchableOpacity>
            </View>
          ) : (
            <View style={styles.navActions}>
              <TouchableOpacity style={styles.guestBtn} onPress={handleGuest}>
                <Ionicons name="eye-outline" size={18} color="rgba(255,255,255,0.7)" />
                <Text style={styles.guestText}>Explore as Guest</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.nextBtn, { backgroundColor: currentSlide.accentColor }]}
                onPress={handleNext}
              >
                <Ionicons name="arrow-forward" size={22} color="#FFF" />
              </TouchableOpacity>
            </View>
          )}
        </View>
      </SafeAreaView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  safeArea: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 10,
  },
  skipBtn: {
    alignSelf: 'flex-end',
    paddingHorizontal: 20,
    paddingVertical: 12,
    marginRight: 8,
    marginTop: 4,
  },
  skipText: {
    fontSize: 16,
    fontWeight: '600',
    color: 'rgba(255,255,255,0.6)',
  },
  slide: {
    flex: 1,
    justifyContent: 'center',
  },
  slideContent: {
    flex: 1,
    paddingHorizontal: 32,
    justifyContent: 'center',
    paddingBottom: 180,
  },
  // Decorative
  decorCircle1: {
    position: 'absolute',
    width: 300,
    height: 300,
    borderRadius: 150,
    top: -50,
    right: -80,
  },
  decorCircle2: {
    position: 'absolute',
    width: 200,
    height: 200,
    borderRadius: 100,
    bottom: 100,
    left: -60,
  },
  decorCircle3: {
    position: 'absolute',
    width: 150,
    height: 150,
    borderRadius: 75,
    top: SCREEN_HEIGHT * 0.25,
    right: -30,
  },
  // Icon
  iconContainer: {
    marginBottom: 32,
    alignSelf: 'flex-start',
  },
  iconCircle: {
    width: 100,
    height: 100,
    borderRadius: 50,
    justifyContent: 'center',
    alignItems: 'center',
  },
  iconInner: {
    width: 72,
    height: 72,
    borderRadius: 36,
    justifyContent: 'center',
    alignItems: 'center',
  },
  // Text
  title: {
    fontSize: 42,
    fontWeight: '900',
    color: '#FFFFFF',
    lineHeight: 48,
    letterSpacing: -1,
    fontStyle: 'italic',
    marginBottom: 12,
  },
  subtitle: {
    fontSize: 17,
    fontWeight: '700',
    marginBottom: 16,
  },
  description: {
    fontSize: 16,
    color: 'rgba(255,255,255,0.65)',
    lineHeight: 24,
    marginBottom: 24,
  },
  // Features
  featureList: {
    gap: 10,
  },
  featurePill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    alignSelf: 'flex-start',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
    borderWidth: 1,
    backgroundColor: 'rgba(255,255,255,0.05)',
  },
  featureText: {
    fontSize: 14,
    fontWeight: '600',
    color: 'rgba(255,255,255,0.85)',
  },
  // Bottom
  bottomSafe: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
  },
  bottomSection: {
    paddingHorizontal: 32,
    paddingBottom: Platform.OS === 'android' ? 24 : 8,
  },
  dotsContainer: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 6,
    marginBottom: 24,
  },
  dot: {
    height: 6,
    borderRadius: 3,
  },
  // Nav
  navActions: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  nextBtn: {
    width: 56,
    height: 56,
    borderRadius: 28,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 6,
  },
  // Last slide
  lastSlideActions: {
    gap: 12,
  },
  getStartedBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
    paddingVertical: 16,
    borderRadius: 28,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 6,
  },
  getStartedText: {
    fontSize: 18,
    fontWeight: '800',
    color: '#FFF',
  },
  guestBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingVertical: 12,
  },
  guestText: {
    fontSize: 15,
    fontWeight: '600',
    color: 'rgba(255,255,255,0.6)',
  },
});
