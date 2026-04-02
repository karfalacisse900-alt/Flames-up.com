import React, { useState, useEffect, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Image,
  ActivityIndicator,
  Dimensions,
  FlatList,
  Linking,
  Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
let WebViewComp: any = null;
try { WebViewComp = require('react-native-webview').WebView; } catch {}
import { colors, spacing, borderRadius, shadows } from '../../src/utils/theme';
import api from '../../src/api/client';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const HERO_HEIGHT = SCREEN_WIDTH * 0.85;

// Price level helper
function priceLabel(level?: number) {
  if (level === undefined || level === null) return null;
  return '$'.repeat(level);
}

// Star row component
function Stars({ rating, size = 14 }: { rating: number; size?: number }) {
  const full = Math.floor(rating);
  const half = rating - full >= 0.3;
  const empty = 5 - full - (half ? 1 : 0);
  return (
    <View style={{ flexDirection: 'row', gap: 2 }}>
      {Array(full).fill(0).map((_, i) => (
        <Ionicons key={`f${i}`} name="star" size={size} color="#FBBF24" />
      ))}
      {half && <Ionicons name="star-half" size={size} color="#FBBF24" />}
      {Array(empty).fill(0).map((_, i) => (
        <Ionicons key={`e${i}`} name="star-outline" size={size} color="#D1D5DB" />
      ))}
    </View>
  );
}

// Review card
function ReviewCard({ review }: { review: any }) {
  return (
    <View style={s.reviewCard}>
      <View style={s.reviewHeader}>
        {review.profile_photo ? (
          <Image source={{ uri: review.profile_photo }} style={s.reviewAvatar} />
        ) : (
          <View style={[s.reviewAvatar, { backgroundColor: colors.accentPrimaryLight, justifyContent: 'center', alignItems: 'center' }]}>
            <Text style={{ fontSize: 12, fontWeight: '700', color: colors.accentPrimary }}>
              {(review.author || 'A')[0].toUpperCase()}
            </Text>
          </View>
        )}
        <View style={{ flex: 1 }}>
          <Text style={s.reviewAuthor} numberOfLines={1}>{review.author}</Text>
          <Text style={s.reviewTime}>{review.time}</Text>
        </View>
        <Stars rating={review.rating || 0} size={12} />
      </View>
      <Text style={s.reviewText} numberOfLines={4}>{review.text}</Text>
    </View>
  );
}

export default function PlaceDetailScreen() {
  const router = useRouter();
  const { id: placeId } = useLocalSearchParams<{ id: string }>();
  const [place, setPlace] = useState<any>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [activePhoto, setActivePhoto] = useState(0);
  const [showAllHours, setShowAllHours] = useState(false);
  const photoRef = useRef<FlatList>(null);

  useEffect(() => {
    loadPlace();
  }, [placeId]);

  const loadPlace = async () => {
    try {
      const response = await api.get(`/google-places/${placeId}`);
      setPlace(response.data);
    } catch (error) {
      console.log('Error loading place:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const openDirections = () => {
    if (!place) return;
    if (place.google_maps_url) {
      Linking.openURL(place.google_maps_url);
    } else if (place.lat && place.lng) {
      const url = Platform.select({
        ios: `maps:0,0?q=${place.lat},${place.lng}`,
        android: `geo:${place.lat},${place.lng}?q=${place.lat},${place.lng}(${place.name})`,
      });
      if (url) Linking.openURL(url);
    }
  };

  const openCall = () => {
    if (place?.phone) {
      Linking.openURL(`tel:${place.phone}`);
    }
  };

  const openWebsite = () => {
    if (place?.website) {
      Linking.openURL(place.website);
    }
  };

  if (isLoading) {
    return (
      <SafeAreaView style={s.loadingContainer}>
        <ActivityIndicator size="large" color={colors.accentPrimary} />
      </SafeAreaView>
    );
  }

  if (!place) {
    return (
      <SafeAreaView style={s.loadingContainer}>
        <View style={{ alignItems: 'center' }}>
          <Ionicons name="location-outline" size={56} color={colors.textHint} />
          <Text style={s.errorText}>Place not found</Text>
          <TouchableOpacity style={s.backButton} onPress={() => router.back()}>
            <Text style={s.backButtonText}>Go Back</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  const photos = place.photos || [];
  const reviews = place.reviews || [];
  const hours = place.hours || [];
  const types = (place.types || []).filter((t: string) => !['point_of_interest', 'establishment'].includes(t));

  return (
    <View style={s.container}>
      {/* Hero Photo Carousel */}
      <View style={s.heroContainer}>
        {photos.length > 0 ? (
          <FlatList
            ref={photoRef}
            data={photos}
            horizontal
            pagingEnabled
            showsHorizontalScrollIndicator={false}
            onMomentumScrollEnd={(e) => {
              const idx = Math.round(e.nativeEvent.contentOffset.x / SCREEN_WIDTH);
              setActivePhoto(idx);
            }}
            keyExtractor={(_, i) => `photo-${i}`}
            renderItem={({ item }) => (
              <Image source={{ uri: item }} style={s.heroImage} />
            )}
          />
        ) : (
          <View style={s.heroPlaceholder}>
            <Ionicons name="image-outline" size={56} color={colors.textHint} />
          </View>
        )}

        {/* Overlay gradient */}
        <View style={s.heroGradient} />

        {/* Top bar */}
        <SafeAreaView style={s.heroTopBar} edges={['top']}>
          <TouchableOpacity style={s.heroBtn} onPress={() => router.back()}>
            <Ionicons name="arrow-back" size={22} color="#FFFFFF" />
          </TouchableOpacity>
          <View style={{ flexDirection: 'row', gap: 10 }}>
            <TouchableOpacity style={s.heroBtn}>
              <Ionicons name="bookmark-outline" size={20} color="#FFFFFF" />
            </TouchableOpacity>
            <TouchableOpacity style={s.heroBtn}>
              <Ionicons name="share-outline" size={20} color="#FFFFFF" />
            </TouchableOpacity>
          </View>
        </SafeAreaView>

        {/* Photo indicators */}
        {photos.length > 1 && (
          <View style={s.photoIndicators}>
            {photos.map((_: any, i: number) => (
              <View
                key={i}
                style={[s.photoIndicator, activePhoto === i && s.photoIndicatorActive]}
              />
            ))}
          </View>
        )}

        {/* Bottom info overlay */}
        <View style={s.heroInfo}>
          {place.open_now !== undefined && (
            <View style={[s.statusBadge, { backgroundColor: place.open_now ? 'rgba(34,197,94,0.9)' : 'rgba(239,68,68,0.9)' }]}>
              <Text style={s.statusBadgeText}>{place.open_now ? 'Open Now' : 'Closed'}</Text>
            </View>
          )}
        </View>
      </View>

      {/* Content */}
      <ScrollView
        style={s.content}
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {/* Title section */}
        <View style={s.titleSection}>
          <Text style={s.placeName}>{place.name}</Text>
          <View style={s.ratingRow}>
            <Stars rating={place.rating || 0} />
            <Text style={s.ratingValue}>{(place.rating || 0).toFixed(1)}</Text>
            <Text style={s.ratingCount}>({place.user_ratings_total || 0} reviews)</Text>
            {place.price_level !== undefined && place.price_level !== null && (
              <>
                <View style={s.dotSeparator} />
                <Text style={s.priceText}>{priceLabel(place.price_level)}</Text>
              </>
            )}
          </View>

          {/* Type tags */}
          {types.length > 0 && (
            <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 10 }}>
              <View style={s.tagsRow}>
                {types.slice(0, 5).map((type: string, i: number) => (
                  <View key={i} style={s.tag}>
                    <Text style={s.tagText}>{type.replace(/_/g, ' ')}</Text>
                  </View>
                ))}
              </View>
            </ScrollView>
          )}
        </View>

        {/* Action Buttons */}
        <View style={s.actionsRow}>
          <TouchableOpacity style={s.actionBtn} onPress={openDirections}>
            <View style={s.actionIconWrap}>
              <Ionicons name="navigate" size={22} color={colors.accentPrimary} />
            </View>
            <Text style={s.actionLabel}>Directions</Text>
          </TouchableOpacity>

          {place.phone && (
            <TouchableOpacity style={s.actionBtn} onPress={openCall}>
              <View style={s.actionIconWrap}>
                <Ionicons name="call" size={22} color={colors.accentPrimary} />
              </View>
              <Text style={s.actionLabel}>Call</Text>
            </TouchableOpacity>
          )}

          {place.website && (
            <TouchableOpacity style={s.actionBtn} onPress={openWebsite}>
              <View style={s.actionIconWrap}>
                <Ionicons name="globe" size={22} color={colors.accentPrimary} />
              </View>
              <Text style={s.actionLabel}>Website</Text>
            </TouchableOpacity>
          )}

          <TouchableOpacity style={s.actionBtn}>
            <View style={s.actionIconWrap}>
              <Ionicons name="share-social" size={22} color={colors.accentPrimary} />
            </View>
            <Text style={s.actionLabel}>Share</Text>
          </TouchableOpacity>
        </View>

        {/* Check In & Post Button */}
        <TouchableOpacity
          style={s.checkinBtn}
          onPress={() => {
            router.push({
              pathname: '/checkin-post',
              params: {
                placeId: placeId,
                placeName: place.name,
                placeLat: String(place.lat || 0),
                placeLng: String(place.lng || 0),
                placePhoto: photos[0] || '',
              },
            } as any);
          }}
        >
          <Ionicons name="location" size={18} color="#FFFFFF" />
          <Text style={s.checkinBtnText}>Check In & Post</Text>
        </TouchableOpacity>

        {/* Divider */}
        <View style={s.divider} />

        {/* Address */}
        {place.address && (
          <TouchableOpacity style={s.infoRow} onPress={openDirections}>
            <Ionicons name="location-outline" size={20} color={colors.textSecondary} />
            <Text style={s.infoText}>{place.address}</Text>
            <Ionicons name="chevron-forward" size={16} color={colors.textHint} />
          </TouchableOpacity>
        )}

        {/* Phone */}
        {place.phone && (
          <TouchableOpacity style={s.infoRow} onPress={openCall}>
            <Ionicons name="call-outline" size={20} color={colors.textSecondary} />
            <Text style={s.infoText}>{place.phone}</Text>
            <Ionicons name="chevron-forward" size={16} color={colors.textHint} />
          </TouchableOpacity>
        )}

        {/* Website */}
        {place.website && (
          <TouchableOpacity style={s.infoRow} onPress={openWebsite}>
            <Ionicons name="globe-outline" size={20} color={colors.textSecondary} />
            <Text style={s.infoText} numberOfLines={1}>{place.website}</Text>
            <Ionicons name="chevron-forward" size={16} color={colors.textHint} />
          </TouchableOpacity>
        )}

        {/* Opening Hours */}
        {hours.length > 0 && (
          <>
            <View style={s.divider} />
            <TouchableOpacity
              style={s.sectionHeader}
              onPress={() => setShowAllHours(!showAllHours)}
            >
              <Ionicons name="time-outline" size={20} color={colors.textSecondary} />
              <Text style={s.sectionTitle}>Opening Hours</Text>
              <Ionicons
                name={showAllHours ? 'chevron-up' : 'chevron-down'}
                size={18}
                color={colors.textHint}
              />
            </TouchableOpacity>
            {showAllHours && (
              <View style={s.hoursContainer}>
                {hours.map((h: string, i: number) => {
                  const today = new Date().toLocaleDateString('en-US', { weekday: 'long' });
                  const isToday = h.toLowerCase().startsWith(today.toLowerCase().slice(0, 3));
                  return (
                    <View key={i} style={s.hourRow}>
                      <Text style={[s.hourText, isToday && s.hourTextToday]}>{h}</Text>
                    </View>
                  );
                })}
              </View>
            )}
          </>
        )}

        {/* Photo Gallery */}
        {photos.length > 1 && (
          <>
            <View style={s.divider} />
            <View style={s.sectionHeaderStatic}>
              <Ionicons name="images-outline" size={20} color={colors.textSecondary} />
              <Text style={s.sectionTitle}>Photos</Text>
              <Text style={s.sectionCount}>{photos.length}</Text>
            </View>
            <ScrollView
              horizontal
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={s.photoGallery}
            >
              {photos.map((url: string, i: number) => (
                <TouchableOpacity
                  key={i}
                  activeOpacity={0.9}
                  onPress={() => {
                    photoRef.current?.scrollToIndex({ index: i, animated: true });
                    setActivePhoto(i);
                  }}
                >
                  <Image source={{ uri: url }} style={s.galleryImage} />
                </TouchableOpacity>
              ))}
            </ScrollView>
          </>
        )}

        {/* Reviews */}
        {reviews.length > 0 && (
          <>
            <View style={s.divider} />
            <View style={s.sectionHeaderStatic}>
              <Ionicons name="chatbubbles-outline" size={20} color={colors.textSecondary} />
              <Text style={s.sectionTitle}>Reviews</Text>
              <Text style={s.sectionCount}>{place.user_ratings_total || reviews.length}</Text>
            </View>
            {reviews.map((review: any, i: number) => (
              <ReviewCard key={i} review={review} />
            ))}
          </>
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bgApp,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.bgApp,
  },
  errorText: {
    fontSize: 16,
    color: colors.textSecondary,
    marginTop: 12,
  },
  backButton: {
    marginTop: 16,
    paddingHorizontal: 20,
    paddingVertical: 10,
    backgroundColor: colors.accentPrimary,
    borderRadius: 20,
  },
  backButtonText: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '600',
  },

  // Hero
  heroContainer: {
    height: HERO_HEIGHT,
    backgroundColor: colors.bgSubtle,
  },
  heroImage: {
    width: SCREEN_WIDTH,
    height: HERO_HEIGHT,
    resizeMode: 'cover',
  },
  heroPlaceholder: {
    width: '100%',
    height: '100%',
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.bgSubtle,
  },
  heroGradient: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    height: 100,
    backgroundColor: 'transparent',
  },
  heroTopBar: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: 8,
  },
  heroBtn: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(0,0,0,0.35)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  photoIndicators: {
    position: 'absolute',
    bottom: 16,
    left: 0,
    right: 0,
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 6,
  },
  photoIndicator: {
    width: 7,
    height: 7,
    borderRadius: 3.5,
    backgroundColor: 'rgba(255,255,255,0.5)',
  },
  photoIndicatorActive: {
    backgroundColor: '#FFFFFF',
    width: 22,
    borderRadius: 4,
  },
  heroInfo: {
    position: 'absolute',
    bottom: 16,
    left: 16,
  },
  statusBadge: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 12,
  },
  statusBadgeText: {
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: '700',
  },

  // Content
  content: {
    flex: 1,
    marginTop: -20,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    backgroundColor: colors.bgApp,
  },
  titleSection: {
    paddingHorizontal: 20,
    paddingTop: 24,
    paddingBottom: 16,
  },
  placeName: {
    fontSize: 24,
    fontWeight: '800',
    color: colors.textPrimary,
    letterSpacing: -0.3,
    lineHeight: 30,
  },
  ratingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 8,
    gap: 6,
  },
  ratingValue: {
    fontSize: 15,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  ratingCount: {
    fontSize: 13,
    color: colors.textHint,
  },
  dotSeparator: {
    width: 4,
    height: 4,
    borderRadius: 2,
    backgroundColor: colors.textHint,
  },
  priceText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#10B981',
  },
  tagsRow: {
    flexDirection: 'row',
    gap: 8,
  },
  tag: {
    backgroundColor: colors.accentPrimaryLight,
    paddingHorizontal: 12,
    paddingVertical: 5,
    borderRadius: 14,
  },
  tagText: {
    fontSize: 12,
    fontWeight: '600',
    color: colors.accentPrimary,
    textTransform: 'capitalize',
  },

  // Actions
  actionsRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    paddingHorizontal: 20,
    paddingBottom: 16,
  },
  actionBtn: {
    alignItems: 'center',
    gap: 6,
  },
  actionIconWrap: {
    width: 52,
    height: 52,
    borderRadius: 26,
    backgroundColor: colors.accentPrimaryLight,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.accentPrimary + '30',
  },
  actionLabel: {
    fontSize: 12,
    fontWeight: '600',
    color: colors.textSecondary,
  },

  // Check In Button
  checkinBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    marginHorizontal: 20,
    marginBottom: 8,
    paddingVertical: 14,
    borderRadius: 20,
    backgroundColor: '#10B981',
  },
  checkinBtnText: {
    fontSize: 15,
    fontWeight: '700',
    color: '#FFFFFF',
  },

  // Inline Map
  inlineMapContainer: {
    height: 180,
    marginHorizontal: 20,
    marginVertical: 8,
    borderRadius: 16,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  mapOverlayBtn: {
    position: 'absolute',
    bottom: 10,
    right: 10,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: colors.accentPrimary,
  },
  mapOverlayText: {
    fontSize: 12,
    fontWeight: '700',
    color: '#FFFFFF',
  },

  // Divider
  divider: {
    height: 1,
    backgroundColor: colors.borderSubtle,
    marginHorizontal: 20,
    marginVertical: 12,
  },

  // Info rows
  infoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 10,
    gap: 12,
  },
  infoText: {
    flex: 1,
    fontSize: 14,
    color: colors.textPrimary,
    lineHeight: 20,
  },

  // Section headers
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 10,
    gap: 10,
  },
  sectionHeaderStatic: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 10,
    gap: 10,
  },
  sectionTitle: {
    flex: 1,
    fontSize: 16,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  sectionCount: {
    fontSize: 13,
    color: colors.textHint,
    fontWeight: '600',
  },

  // Hours
  hoursContainer: {
    paddingHorizontal: 20,
    paddingBottom: 8,
  },
  hourRow: {
    paddingVertical: 6,
    paddingHorizontal: 32,
  },
  hourText: {
    fontSize: 13,
    color: colors.textSecondary,
    lineHeight: 20,
  },
  hourTextToday: {
    fontWeight: '700',
    color: colors.accentPrimary,
  },

  // Photo gallery
  photoGallery: {
    paddingHorizontal: 20,
    gap: 10,
    paddingBottom: 4,
  },
  galleryImage: {
    width: 120,
    height: 90,
    borderRadius: 12,
    resizeMode: 'cover',
  },

  // Reviews
  reviewCard: {
    marginHorizontal: 20,
    marginBottom: 12,
    padding: 14,
    backgroundColor: colors.bgCard,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation1,
  },
  reviewHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    marginBottom: 8,
  },
  reviewAvatar: {
    width: 32,
    height: 32,
    borderRadius: 16,
    overflow: 'hidden',
  },
  reviewAuthor: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  reviewTime: {
    fontSize: 11,
    color: colors.textHint,
    marginTop: 1,
  },
  reviewText: {
    fontSize: 14,
    color: colors.textSecondary,
    lineHeight: 21,
  },
});
