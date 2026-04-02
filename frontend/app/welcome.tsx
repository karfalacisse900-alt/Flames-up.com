import React, { useState, useRef, useEffect, useCallback } from 'react';
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

const SLIDES = [
  {
    id: '1',
    icon: 'flame',
    iconBg: '#F97316',
    title: 'Welcome to',
    titleBold: 'Flames-Up',
    subtitle: 'Connect. Share. Discover.',
    description: 'Your local community app — find what\'s happening around you, meet real people, and share your world.',
    illustrationIcons: [
      { name: 'people', color: '#2D6A4F', x: 60, y: 20, size: 32, delay: 200 },
      { name: 'heart', color: '#EF4444', x: 260, y: 40, size: 22, delay: 400 },
      { name: 'chatbubble', color: '#3B82F6', x: 160, y: 60, size: 26, delay: 300 },
      { name: 'star', color: '#F59E0B', x: 310, y: 10, size: 18, delay: 500 },
      { name: 'location', color: '#8B5CF6', x: 30, y: 65, size: 20, delay: 350 },
    ],
  },
  {
    id: '2',
    icon: 'compass',
    iconBg: '#2D6A4F',
    title: 'Discover',
    titleBold: 'Local Gems',
    subtitle: 'Places, events & people near you.',
    description: 'Check in at your favorite spots, explore an interactive map, and see what\'s trending in your neighborhood.',
    illustrationIcons: [
      { name: 'map', color: '#2D6A4F', x: 50, y: 25, size: 30, delay: 200 },
      { name: 'restaurant', color: '#F97316', x: 250, y: 15, size: 24, delay: 400 },
      { name: 'cafe', color: '#8B5CF6', x: 150, y: 55, size: 26, delay: 300 },
      { name: 'pin', color: '#EF4444', x: 300, y: 50, size: 20, delay: 500 },
      { name: 'navigate', color: '#3B82F6', x: 20, y: 60, size: 22, delay: 350 },
    ],
  },
  {
    id: '3',
    icon: 'newspaper',
    iconBg: '#3B82F6',
    title: 'Follow',
    titleBold: 'Local Publishers',
    subtitle: 'Stories from your community.',
    description: 'Get the best food, culture, events and news from verified local publishers in your area.',
    illustrationIcons: [
      { name: 'reader', color: '#3B82F6', x: 60, y: 20, size: 28, delay: 200 },
      { name: 'megaphone', color: '#F97316', x: 240, y: 35, size: 26, delay: 400 },
      { name: 'images', color: '#2D6A4F', x: 150, y: 60, size: 24, delay: 300 },
      { name: 'checkmark-circle', color: '#10B981', x: 300, y: 15, size: 22, delay: 500 },
      { name: 'globe', color: '#8B5CF6', x: 30, y: 55, size: 20, delay: 350 },
    ],
  },
  {
    id: '4',
    icon: 'chatbubbles',
    iconBg: '#8B5CF6',
    title: 'Connect &',
    titleBold: 'Share',
    subtitle: 'Your voice matters here.',
    description: 'Post photos & videos, send messages, share stories, and build real connections with people around you.',
    illustrationIcons: [
      { name: 'camera', color: '#F97316', x: 55, y: 30, size: 28, delay: 200 },
      { name: 'videocam', color: '#EF4444', x: 260, y: 20, size: 24, delay: 400 },
      { name: 'send', color: '#2D6A4F', x: 160, y: 55, size: 26, delay: 300 },
      { name: 'image', color: '#3B82F6', x: 310, y: 50, size: 20, delay: 500 },
      { name: 'happy', color: '#F59E0B', x: 25, y: 60, size: 22, delay: 350 },
    ],
  },
];

export default function WelcomeScreen() {
  const router = useRouter();
  const [currentIndex, setCurrentIndex] = useState(0);
  const flatListRef = useRef<FlatList>(null);
  const scrollX = useRef(new Animated.Value(0)).current;

  // Animations
  const fadeIn = useRef(new Animated.Value(0)).current;
  const slideUp = useRef(new Animated.Value(40)).current;
  const iconScale = useRef(new Animated.Value(0.5)).current;
  const floatingAnims = useRef(
    SLIDES[0].illustrationIcons.map(() => new Animated.Value(0))
  ).current;

  useEffect(() => {
    animateSlide();
  }, [currentIndex]);

  const animateSlide = () => {
    fadeIn.setValue(0);
    slideUp.setValue(40);
    iconScale.setValue(0.5);
    floatingAnims.forEach(a => a.setValue(0));

    Animated.parallel([
      Animated.timing(fadeIn, { toValue: 1, duration: 500, useNativeDriver: true }),
      Animated.spring(slideUp, { toValue: 0, friction: 8, tension: 40, useNativeDriver: true }),
      Animated.spring(iconScale, { toValue: 1, friction: 5, tension: 50, useNativeDriver: true }),
    ]).start();

    // Floating illustration icons stagger
    Animated.stagger(100,
      floatingAnims.map(a =>
        Animated.spring(a, { toValue: 1, friction: 6, tension: 40, useNativeDriver: true })
      )
    ).start();
  };

  const handleComplete = async () => {
    await AsyncStorage.setItem(ONBOARDING_KEY, 'true');
    router.replace('/(auth)/login');
  };

  const handleGuest = async () => {
    await AsyncStorage.setItem(ONBOARDING_KEY, 'true');
    await AsyncStorage.setItem('guest_mode', 'true');
    router.replace('/(tabs)/home');
  };

  const goNext = () => {
    if (currentIndex < SLIDES.length - 1) {
      flatListRef.current?.scrollToIndex({ index: currentIndex + 1, animated: true });
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

  const slide = SLIDES[currentIndex];
  const isLast = currentIndex === SLIDES.length - 1;

  const renderSlide = ({ item, index }: { item: typeof SLIDES[0]; index: number }) => {
    const isActive = index === currentIndex;
    return (
      <View style={[styles.slide, { width: SCREEN_WIDTH }]}>
        <View style={styles.slideInner}>
          {/* Floating illustration area */}
          <View style={styles.illustrationArea}>
            {/* Big circle bg */}
            <View style={[styles.bigCircle, { backgroundColor: item.iconBg + '08' }]} />
            <View style={[styles.medCircle, { backgroundColor: item.iconBg + '06' }]} />

            {/* Floating mini icons */}
            {item.illustrationIcons.map((icon, i) => (
              <Animated.View
                key={i}
                style={[
                  styles.floatingIcon,
                  {
                    left: icon.x,
                    top: icon.y,
                    opacity: isActive ? floatingAnims[i] : 0.3,
                    transform: [{
                      scale: isActive ? floatingAnims[i].interpolate({
                        inputRange: [0, 1],
                        outputRange: [0.3, 1],
                      }) : 0.7,
                    }],
                  },
                ]}
              >
                <View style={[styles.floatingIconBg, { backgroundColor: icon.color + '12' }]}>
                  <Ionicons name={icon.name as any} size={icon.size} color={icon.color} />
                </View>
              </Animated.View>
            ))}

            {/* Central icon */}
            <Animated.View
              style={[
                styles.centralIcon,
                {
                  backgroundColor: item.iconBg,
                  transform: [{ scale: isActive ? iconScale : 0.8 }],
                },
              ]}
            >
              <Ionicons name={item.icon as any} size={36} color="#FFF" />
            </Animated.View>
          </View>

          {/* Text content */}
          <Animated.View
            style={[
              styles.textContent,
              {
                opacity: isActive ? fadeIn : 0.6,
                transform: [{ translateY: isActive ? slideUp : 0 }],
              },
            ]}
          >
            <Text style={styles.title}>
              {item.title}{' '}
              <Text style={[styles.titleBold, { color: item.iconBg }]}>{item.titleBold}</Text>
            </Text>
            <Text style={styles.subtitle}>{item.subtitle}</Text>
            <Text style={styles.description}>{item.description}</Text>
          </Animated.View>
        </View>
      </View>
    );
  };

  return (
    <View style={styles.container}>
      <SafeAreaView style={styles.topBar} edges={['top']}>
        {/* Logo + Skip */}
        <View style={styles.topRow}>
          <View style={styles.logoRow}>
            <View style={styles.logoIcon}>
              <Ionicons name="flame" size={18} color="#F97316" />
            </View>
            <Text style={styles.logoText}>flames-up</Text>
          </View>
          {!isLast && (
            <TouchableOpacity onPress={handleComplete} style={styles.skipBtn}>
              <Text style={styles.skipText}>Skip</Text>
              <Ionicons name="chevron-forward" size={14} color="#9CA3AF" />
            </TouchableOpacity>
          )}
        </View>
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
      <SafeAreaView style={styles.bottomArea} edges={['bottom']}>
        {/* Progress dots */}
        <View style={styles.dotsRow}>
          {SLIDES.map((_, i) => {
            const inputRange = [
              (i - 1) * SCREEN_WIDTH,
              i * SCREEN_WIDTH,
              (i + 1) * SCREEN_WIDTH,
            ];
            const dotW = scrollX.interpolate({
              inputRange,
              outputRange: [8, 24, 8],
              extrapolate: 'clamp',
            });
            const dotOp = scrollX.interpolate({
              inputRange,
              outputRange: [0.25, 1, 0.25],
              extrapolate: 'clamp',
            });
            return (
              <Animated.View
                key={i}
                style={[styles.dot, {
                  width: dotW,
                  opacity: dotOp,
                  backgroundColor: slide.iconBg,
                }]}
              />
            );
          })}
        </View>

        {/* Action buttons */}
        {isLast ? (
          <View style={styles.lastActions}>
            <TouchableOpacity
              style={[styles.getStartedBtn, { backgroundColor: slide.iconBg }]}
              onPress={handleComplete}
              activeOpacity={0.8}
            >
              <Text style={styles.getStartedText}>Get Started</Text>
              <Ionicons name="arrow-forward" size={18} color="#FFF" />
            </TouchableOpacity>
            <TouchableOpacity style={styles.guestRow} onPress={handleGuest}>
              <Ionicons name="eye-outline" size={16} color="#9CA3AF" />
              <Text style={styles.guestText}>Explore as Guest</Text>
            </TouchableOpacity>
          </View>
        ) : (
          <View style={styles.navRow}>
            <TouchableOpacity style={styles.guestRow} onPress={handleGuest}>
              <Ionicons name="eye-outline" size={16} color="#9CA3AF" />
              <Text style={styles.guestText}>Explore as Guest</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.nextBtn, { backgroundColor: slide.iconBg }]}
              onPress={goNext}
              activeOpacity={0.8}
            >
              <Text style={styles.nextText}>Next</Text>
              <Ionicons name="arrow-forward" size={16} color="#FFF" />
            </TouchableOpacity>
          </View>
        )}
      </SafeAreaView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#FAFAF8',
  },
  topBar: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 10,
  },
  topRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 24,
    paddingVertical: 8,
  },
  logoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  logoIcon: {
    width: 32,
    height: 32,
    borderRadius: 10,
    backgroundColor: '#FFF',
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#F0ECE5',
  },
  logoText: {
    fontSize: 18,
    fontWeight: '800',
    fontStyle: 'italic',
    color: '#1B4332',
  },
  skipBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 2,
    paddingVertical: 8,
    paddingHorizontal: 4,
  },
  skipText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#9CA3AF',
  },
  // Slides
  slide: {
    flex: 1,
  },
  slideInner: {
    flex: 1,
    paddingHorizontal: 28,
    justifyContent: 'center',
    paddingBottom: 160,
    paddingTop: 80,
  },
  // Illustration area
  illustrationArea: {
    height: SCREEN_HEIGHT * 0.28,
    marginBottom: 24,
    position: 'relative',
    justifyContent: 'center',
    alignItems: 'center',
  },
  bigCircle: {
    position: 'absolute',
    width: SCREEN_WIDTH * 0.7,
    height: SCREEN_WIDTH * 0.7,
    borderRadius: SCREEN_WIDTH * 0.35,
  },
  medCircle: {
    position: 'absolute',
    width: SCREEN_WIDTH * 0.48,
    height: SCREEN_WIDTH * 0.48,
    borderRadius: SCREEN_WIDTH * 0.24,
  },
  centralIcon: {
    width: 80,
    height: 80,
    borderRadius: 28,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.15,
    shadowRadius: 16,
    elevation: 8,
  },
  floatingIcon: {
    position: 'absolute',
  },
  floatingIconBg: {
    width: 48,
    height: 48,
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
  },
  // Text
  textContent: {
    gap: 10,
  },
  title: {
    fontSize: 34,
    fontWeight: '400',
    color: '#1B4332',
    lineHeight: 40,
  },
  titleBold: {
    fontWeight: '900',
    fontStyle: 'italic',
  },
  subtitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#5C4033',
    marginTop: 2,
  },
  description: {
    fontSize: 15,
    color: '#9CA3AF',
    lineHeight: 22,
    marginTop: 4,
  },
  // Bottom
  bottomArea: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
  },
  dotsRow: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 6,
    marginBottom: 20,
  },
  dot: {
    height: 6,
    borderRadius: 3,
  },
  // Nav
  navRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 28,
    paddingBottom: Platform.OS === 'android' ? 24 : 8,
  },
  nextBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 24,
    paddingVertical: 14,
    borderRadius: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.12,
    shadowRadius: 8,
    elevation: 4,
  },
  nextText: {
    fontSize: 15,
    fontWeight: '700',
    color: '#FFF',
  },
  // Last slide
  lastActions: {
    paddingHorizontal: 28,
    gap: 10,
    paddingBottom: Platform.OS === 'android' ? 24 : 8,
  },
  getStartedBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingVertical: 16,
    borderRadius: 22,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 10,
    elevation: 5,
  },
  getStartedText: {
    fontSize: 17,
    fontWeight: '800',
    color: '#FFF',
  },
  guestRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingVertical: 10,
  },
  guestText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#9CA3AF',
  },
});
