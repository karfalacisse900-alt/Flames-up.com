import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Dimensions,
  Image,
  Linking,
  Platform,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import api from '../../src/api/client';
import { useAuthStore } from '../../src/store/authStore';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

export default function PlaceDetailScreen() {
  const router = useRouter();
  const { id: placeId } = useLocalSearchParams<{ id: string }>();
  const { user } = useAuthStore();

  const [place, setPlace] = useState<any>(null);
  const [isLoading, setIsLoading] = useState(true);

  const loadPlace = useCallback(async () => {
    setIsLoading(true);
    try {
      const response = await api.get(`/google-places/${placeId}`);
      setPlace(response.data);
    } catch (error) {
      console.log('Error loading place:', error);
      setPlace(null);
    } finally {
      setIsLoading(false);
    }
  }, [placeId]);

  useEffect(() => {
    loadPlace();
  }, [loadPlace]);

  const openDirections = () => {
    if (!place) return;

    if (place.google_maps_url) {
      Linking.openURL(place.google_maps_url);
      return;
    }

    if (place.lat && place.lng) {
      const label = encodeURIComponent(place.name || 'Destination');
      const url = Platform.select({
        ios: `maps:0,0?q=${label}@${place.lat},${place.lng}`,
        android: `geo:${place.lat},${place.lng}?q=${place.lat},${place.lng}(${label})`,
      });
      if (url) Linking.openURL(url);
    }
  };

  const openWebsite = () => {
    if (place?.website) {
      Linking.openURL(place.website);
    }
  };

  const handleOrder = () => {
    if (place?.website) {
      openWebsite();
      return;
    }
    openDirections();
  };

  const heroImage = place?.photos?.[0] || place?.photo_url || null;
  const firstName = user?.full_name?.split(' ')[0] || user?.username || 'Friend';
  const greetingName = firstName.toUpperCase();
  const placeName = (place?.name || 'Unknown Spot').toUpperCase();

  const estimateMinutes = useMemo(() => {
    const seed = Number(place?.user_ratings_total ?? place?.rating ?? 3);
    return 9 + (Math.abs(Math.floor(seed)) % 7);
  }, [place?.user_ratings_total, place?.rating]);

  if (isLoading) {
    return (
      <SafeAreaView style={styles.loadingContainer}>
        <ActivityIndicator size="large" color="#202020" />
      </SafeAreaView>
    );
  }

  if (!place) {
    return (
      <SafeAreaView style={styles.loadingContainer}>
        <View style={styles.errorWrap}>
          <Ionicons name="location-outline" size={54} color="#777777" />
          <Text style={styles.errorText}>Place not found</Text>
          <TouchableOpacity style={styles.errorBtn} onPress={() => router.back()}>
            <Text style={styles.errorBtnText}>Go Back</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.safeArea} edges={['top']}>
      <View style={styles.screen}>
        <View style={styles.heroCard}>
          {heroImage ? (
            <Image source={{ uri: heroImage }} style={styles.heroImage} />
          ) : (
            <View style={styles.heroFallback}>
              <Ionicons name="image-outline" size={56} color="#7F7F7F" />
            </View>
          )}

          <View style={styles.heroShade} />

          <View style={styles.topRow}>
            <TouchableOpacity style={styles.backTile} onPress={() => router.back()}>
              <Ionicons name="water-outline" size={24} color="#2A8FD3" />
            </TouchableOpacity>

            <View style={styles.greetingWrap}>
              <Text style={styles.greetingTitle}>HI {greetingName}</Text>
              <Text style={styles.greetingSub}>Let us get something brewing.</Text>
            </View>
          </View>

          <View style={styles.bottomDock}>
            <View style={styles.infoCol}>
              <Text style={styles.etaText}>Estimated pick-up in {estimateMinutes} mins</Text>
              <TouchableOpacity style={styles.placeRow} onPress={openDirections} activeOpacity={0.8}>
                <Text style={styles.placeName} numberOfLines={1}>{placeName}</Text>
                <Ionicons name="chevron-forward" size={16} color="#242424" />
              </TouchableOpacity>
            </View>

            <TouchableOpacity style={styles.orderBtn} onPress={handleOrder}>
              <Text style={styles.orderBtnText}>Order</Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: '#DCDCDC',
  },
  screen: {
    flex: 1,
    paddingHorizontal: 8,
    paddingBottom: 8,
    paddingTop: 4,
    backgroundColor: '#DCDCDC',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#E4E4E4',
  },
  errorWrap: {
    alignItems: 'center',
  },
  errorText: {
    marginTop: 10,
    fontSize: 16,
    color: '#555555',
  },
  errorBtn: {
    marginTop: 14,
    paddingHorizontal: 18,
    paddingVertical: 10,
    borderRadius: 22,
    backgroundColor: '#242424',
  },
  errorBtnText: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '700',
  },
  heroCard: {
    flex: 1,
    borderRadius: 24,
    overflow: 'hidden',
    backgroundColor: '#BEBEBE',
  },
  heroImage: {
    width: '100%',
    height: '100%',
    resizeMode: 'cover',
  },
  heroFallback: {
    width: '100%',
    height: '100%',
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#C3C3C3',
  },
  heroShade: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.08)',
  },
  topRow: {
    position: 'absolute',
    top: 12,
    left: 12,
    right: 16,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
  },
  backTile: {
    width: 56,
    height: 64,
    backgroundColor: '#F4F4F4',
    justifyContent: 'center',
    alignItems: 'center',
  },
  greetingWrap: {
    alignItems: 'flex-end',
    marginTop: 8,
    maxWidth: SCREEN_WIDTH * 0.62,
  },
  greetingTitle: {
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: '600',
  },
  greetingSub: {
    marginTop: 3,
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: '500',
  },
  bottomDock: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: '#EDEBE7',
    paddingHorizontal: 14,
    paddingTop: 14,
    paddingBottom: 12,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-end',
    gap: 10,
  },
  infoCol: {
    flex: 1,
  },
  etaText: {
    color: '#727272',
    fontSize: 12,
    marginBottom: 5,
  },
  placeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingRight: 10,
  },
  placeName: {
    flex: 1,
    color: '#111111',
    fontSize: 27,
    fontWeight: '500',
    letterSpacing: 2,
  },
  orderBtn: {
    minWidth: 86,
    height: 38,
    borderWidth: 1,
    borderColor: '#202020',
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#F7F6F3',
    paddingHorizontal: 18,
  },
  orderBtnText: {
    color: '#111111',
    fontSize: 15,
    fontWeight: '500',
  },
});
