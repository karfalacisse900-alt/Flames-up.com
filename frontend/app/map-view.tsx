import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  Image,
  ActivityIndicator,
  Linking,
  Platform,
  Dimensions,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as Location from 'expo-location';
import { colors, shadows } from '../src/utils/theme';
import api from '../src/api/client';

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');

export default function MapViewScreen() {
  const router = useRouter();
  const { type } = useLocalSearchParams<{ type: string }>();
  const [places, setPlaces] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [userLat, setUserLat] = useState(40.7128);
  const [userLng, setUserLng] = useState(-74.006);
  const [locationName, setLocationName] = useState('New York');

  useEffect(() => {
    (async () => {
      try {
        const { status } = await Location.requestForegroundPermissionsAsync();
        if (status === 'granted') {
          const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
          setUserLat(loc.coords.latitude);
          setUserLng(loc.coords.longitude);
          try {
            const geo = await Location.reverseGeocodeAsync({
              latitude: loc.coords.latitude,
              longitude: loc.coords.longitude,
            });
            if (geo[0]) setLocationName(geo[0].city || geo[0].district || 'Your Area');
          } catch {}
        }
      } catch {}
    })();
  }, []);

  useEffect(() => {
    loadPlaces();
  }, [userLat, userLng]);

  const loadPlaces = async () => {
    try {
      const response = await api.get('/google-places/nearby', {
        params: { type: type || 'restaurant', lat: userLat, lng: userLng, radius: 5000 },
      });
      setPlaces(response.data);
    } catch (error) {
      console.log('Error loading places:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const openInMaps = (place: any) => {
    const lat = place.lat || userLat;
    const lng = place.lng || userLng;
    const label = encodeURIComponent(place.name);
    const url = Platform.select({
      ios: `maps:0,0?q=${label}@${lat},${lng}`,
      android: `geo:${lat},${lng}?q=${lat},${lng}(${label})`,
      default: `https://www.google.com/maps/search/?api=1&query=${lat},${lng}&query_place_id=${place.place_id}`,
    });
    if (url) Linking.openURL(url);
  };

  const openAllInGoogleMaps = () => {
    const url = `https://www.google.com/maps/search/${type || 'restaurant'}/@${userLat},${userLng},14z`;
    Linking.openURL(url);
  };

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      {/* Header */}
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <View style={{ flex: 1 }}>
          <Text style={s.headerTitle}>Map View</Text>
          <Text style={s.headerSubtitle}>{locationName} • {places.length} places</Text>
        </View>
        <TouchableOpacity style={s.openMapsBtn} onPress={openAllInGoogleMaps}>
          <Ionicons name="open-outline" size={16} color="#FFFFFF" />
          <Text style={s.openMapsBtnText}>Google Maps</Text>
        </TouchableOpacity>
      </View>

      {/* Map placeholder + list view */}
      <View style={s.mapContainer}>
        <View style={s.mapPlaceholder}>
          <Ionicons name="map" size={64} color={colors.accentPrimary} />
          <Text style={s.mapText}>{locationName}</Text>
          <Text style={s.mapSubtext}>Tap any place below to navigate</Text>
          <TouchableOpacity style={s.openFullMap} onPress={openAllInGoogleMaps}>
            <Ionicons name="navigate" size={18} color="#FFFFFF" />
            <Text style={s.openFullMapText}>Open Full Map</Text>
          </TouchableOpacity>
        </View>
      </View>

      {/* Places List */}
      {isLoading ? (
        <View style={s.loadingCenter}>
          <ActivityIndicator size="large" color={colors.accentPrimary} />
        </View>
      ) : (
        <ScrollView
          style={s.list}
          showsVerticalScrollIndicator={false}
          contentContainerStyle={{ paddingBottom: 60 }}
        >
          {places.map((place, idx) => (
            <TouchableOpacity
              key={place.place_id}
              style={s.placeCard}
              onPress={() => router.push(`/place/${place.place_id}`)}
            >
              <View style={s.placeIndex}>
                <Text style={s.placeIndexText}>{idx + 1}</Text>
              </View>
              {place.photo_url ? (
                <Image source={{ uri: place.photo_url }} style={s.placeImage} />
              ) : (
                <View style={[s.placeImage, s.placeImagePlaceholder]}>
                  <Ionicons name="image-outline" size={20} color={colors.textHint} />
                </View>
              )}
              <View style={s.placeInfo}>
                <Text style={s.placeName} numberOfLines={1}>{place.name}</Text>
                <View style={s.placeRatingRow}>
                  <Ionicons name="star" size={12} color="#FCD34D" />
                  <Text style={s.placeRating}>{place.rating?.toFixed(1) || '—'}</Text>
                  {place.open_now !== undefined && (
                    <View style={[s.statusBadge, { backgroundColor: place.open_now ? '#DCFCE7' : '#FEE2E2' }]}>
                      <Text style={[s.statusText, { color: place.open_now ? '#16A34A' : '#DC2626' }]}>
                        {place.open_now ? 'Open' : 'Closed'}
                      </Text>
                    </View>
                  )}
                </View>
                {place.vicinity && (
                  <Text style={s.placeAddress} numberOfLines={1}>{place.vicinity}</Text>
                )}
              </View>
              <TouchableOpacity
                style={s.navigateBtn}
                onPress={() => openInMaps(place)}
              >
                <Ionicons name="navigate" size={20} color={colors.accentPrimary} />
              </TouchableOpacity>
            </TouchableOpacity>
          ))}
        </ScrollView>
      )}
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bgApp },
  header: {
    flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12,
    borderBottomWidth: 1, borderBottomColor: colors.borderSubtle, gap: 12,
  },
  backBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 18, fontWeight: '700', color: colors.textPrimary },
  headerSubtitle: { fontSize: 12, color: colors.textHint, marginTop: 1 },
  openMapsBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    backgroundColor: colors.accentPrimary, paddingHorizontal: 14, paddingVertical: 10, borderRadius: 20,
  },
  openMapsBtnText: { fontSize: 13, fontWeight: '700', color: '#FFFFFF' },

  mapContainer: { height: SCREEN_HEIGHT * 0.25 },
  mapPlaceholder: {
    flex: 1, backgroundColor: colors.accentPrimaryLight, justifyContent: 'center',
    alignItems: 'center', borderBottomWidth: 1, borderBottomColor: colors.borderSubtle,
  },
  mapText: { fontSize: 18, fontWeight: '700', color: colors.accentPrimary, marginTop: 8 },
  mapSubtext: { fontSize: 13, color: colors.textHint, marginTop: 4 },
  openFullMap: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    backgroundColor: colors.accentPrimary, paddingHorizontal: 20, paddingVertical: 12,
    borderRadius: 24, marginTop: 16,
  },
  openFullMapText: { fontSize: 14, fontWeight: '700', color: '#FFFFFF' },

  loadingCenter: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  list: { flex: 1 },

  placeCard: {
    flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 14,
    borderBottomWidth: 1, borderBottomColor: colors.borderSubtle, gap: 12,
  },
  placeIndex: {
    width: 24, height: 24, borderRadius: 12, backgroundColor: colors.accentPrimaryLight,
    justifyContent: 'center', alignItems: 'center',
  },
  placeIndexText: { fontSize: 11, fontWeight: '700', color: colors.accentPrimary },
  placeImage: { width: 56, height: 56, borderRadius: 14, overflow: 'hidden' },
  placeImagePlaceholder: { backgroundColor: colors.bgSubtle, justifyContent: 'center', alignItems: 'center' },
  placeInfo: { flex: 1 },
  placeName: { fontSize: 15, fontWeight: '700', color: colors.textPrimary },
  placeRatingRow: { flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 4 },
  placeRating: { fontSize: 13, fontWeight: '600', color: colors.textSecondary },
  statusBadge: { paddingHorizontal: 8, paddingVertical: 2, borderRadius: 8, marginLeft: 4 },
  statusText: { fontSize: 11, fontWeight: '700' },
  placeAddress: { fontSize: 12, color: colors.textHint, marginTop: 2 },
  navigateBtn: {
    width: 44, height: 44, borderRadius: 22, backgroundColor: colors.accentPrimaryLight,
    justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: colors.accentPrimary + '30',
  },
});
