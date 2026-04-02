import React, { useState, useEffect, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Image,
  ActivityIndicator,
  Linking,
  Platform,
  Dimensions,
  ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { WebView } from 'react-native-webview';
import * as Location from 'expo-location';
import { colors } from '../src/utils/theme';
import api from '../src/api/client';

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');
const GOOGLE_MAPS_KEY = 'AIzaSyCEY8QKlhF-Kxlo8Sxv8Z0bnTVVzTBTEIw';

export default function MapViewScreen() {
  const router = useRouter();
  const { type } = useLocalSearchParams<{ type: string }>();
  const [places, setPlaces] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [userLat, setUserLat] = useState(40.7128);
  const [userLng, setUserLng] = useState(-74.006);
  const [locationName, setLocationName] = useState('New York');
  const [selectedPlace, setSelectedPlace] = useState<any>(null);
  const [mapExpanded, setMapExpanded] = useState(false);
  const webViewRef = useRef<any>(null);

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

  const generateMapHTML = () => {
    const markersJS = places.map((p, i) => `
      var marker${i} = new google.maps.Marker({
        position: { lat: ${p.lat || userLat}, lng: ${p.lng || userLng} },
        map: map,
        title: "${(p.name || '').replace(/"/g, '\\"')}",
        icon: {
          path: google.maps.SymbolPath.CIRCLE,
          scale: 10,
          fillColor: "${p.open_now === false ? '#EF4444' : '#10B981'}",
          fillOpacity: 1,
          strokeWeight: 2.5,
          strokeColor: '#FFFFFF',
        },
        label: {
          text: "${i + 1}",
          color: "#FFFFFF",
          fontSize: "10px",
          fontWeight: "bold"
        }
      });

      var info${i} = new google.maps.InfoWindow({
        content: '<div style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:4px;min-width:160px">' +
          '<div style="font-weight:700;font-size:14px;margin-bottom:4px">${(p.name || '').replace(/'/g, "\\'").replace(/"/g, '\\"')}</div>' +
          '<div style="display:flex;align-items:center;gap:4px;margin-bottom:4px">' +
            '<span style="color:#F59E0B;font-weight:600">${p.rating ? p.rating.toFixed(1) : '—'} ★</span>' +
            '<span style="color:${p.open_now === false ? '#EF4444' : '#10B981'};font-size:12px;font-weight:600">${p.open_now === false ? 'Closed' : 'Open'}</span>' +
          '</div>' +
          '${p.vicinity ? '<div style="font-size:12px;color:#6B7280">' + (p.vicinity || '').replace(/'/g, "\\'").replace(/"/g, '\\"') + '</div>' : ''}' +
        '</div>'
      });

      marker${i}.addListener('click', function() {
        ${places.map((_, j) => `info${j}.close();`).join('\n')}
        info${i}.open(map, marker${i});
        window.ReactNativeWebView.postMessage(JSON.stringify({ type: 'markerClick', index: ${i} }));
      });
    `).join('\n');

    return `
    <!DOCTYPE html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
      <style>
        * { margin: 0; padding: 0; }
        html, body, #map { width: 100%; height: 100%; }
      </style>
    </head>
    <body>
      <div id="map"></div>
      <script>
        function initMap() {
          var map = new google.maps.Map(document.getElementById('map'), {
            center: { lat: ${userLat}, lng: ${userLng} },
            zoom: 14,
            mapTypeControl: false,
            streetViewControl: false,
            fullscreenControl: false,
            zoomControl: true,
            styles: [
              { featureType: 'poi', elementType: 'labels', stylers: [{ visibility: 'off' }] },
              { featureType: 'transit', stylers: [{ visibility: 'off' }] }
            ]
          });

          // User location marker
          new google.maps.Marker({
            position: { lat: ${userLat}, lng: ${userLng} },
            map: map,
            icon: {
              path: google.maps.SymbolPath.CIRCLE,
              scale: 8,
              fillColor: '#3B82F6',
              fillOpacity: 1,
              strokeWeight: 3,
              strokeColor: '#FFFFFF',
            },
            title: 'You',
            zIndex: 999,
          });

          // User accuracy circle
          new google.maps.Circle({
            map: map,
            center: { lat: ${userLat}, lng: ${userLng} },
            radius: 50,
            fillColor: '#3B82F6',
            fillOpacity: 0.1,
            strokeColor: '#3B82F6',
            strokeOpacity: 0.3,
            strokeWeight: 1,
          });

          ${markersJS}
        }
      </script>
      <script src="https://maps.googleapis.com/maps/api/js?key=${GOOGLE_MAPS_KEY}&callback=initMap" async defer></script>
    </body>
    </html>
    `;
  };

  const handleWebViewMessage = (event: any) => {
    try {
      const data = JSON.parse(event.nativeEvent.data);
      if (data.type === 'markerClick' && places[data.index]) {
        setSelectedPlace(places[data.index]);
      }
    } catch {}
  };

  const mapHeight = mapExpanded ? SCREEN_HEIGHT * 0.65 : SCREEN_HEIGHT * 0.4;

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      {/* Header */}
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <View style={{ flex: 1 }}>
          <Text style={s.headerTitle}>Map View</Text>
          <Text style={s.headerSubtitle}>{locationName} · {places.length} places</Text>
        </View>
        <TouchableOpacity
          style={s.expandBtn}
          onPress={() => setMapExpanded(!mapExpanded)}
        >
          <Ionicons name={mapExpanded ? 'contract' : 'expand'} size={18} color={colors.accentPrimary} />
        </TouchableOpacity>
      </View>

      {/* Real Google Map */}
      <View style={[s.mapContainer, { height: mapHeight }]}>
        {isLoading ? (
          <View style={s.loadingCenter}>
            <ActivityIndicator size="large" color={colors.accentPrimary} />
            <Text style={s.loadingText}>Loading map...</Text>
          </View>
        ) : (
          <WebView
            ref={webViewRef}
            source={{ html: generateMapHTML() }}
            style={{ flex: 1 }}
            onMessage={handleWebViewMessage}
            javaScriptEnabled
            domStorageEnabled
            startInLoadingState
            renderLoading={() => (
              <View style={s.loadingCenter}>
                <ActivityIndicator size="large" color={colors.accentPrimary} />
              </View>
            )}
          />
        )}
      </View>

      {/* Selected Place Preview */}
      {selectedPlace && (
        <TouchableOpacity
          style={s.selectedCard}
          onPress={() => router.push(`/place/${selectedPlace.place_id}`)}
          activeOpacity={0.8}
        >
          {selectedPlace.photo_url ? (
            <Image source={{ uri: selectedPlace.photo_url }} style={s.selectedImage} />
          ) : (
            <View style={[s.selectedImage, s.selectedImagePlaceholder]}>
              <Ionicons name="image-outline" size={24} color={colors.textHint} />
            </View>
          )}
          <View style={s.selectedInfo}>
            <Text style={s.selectedName} numberOfLines={1}>{selectedPlace.name}</Text>
            <View style={s.selectedMeta}>
              <Ionicons name="star" size={12} color="#FCD34D" />
              <Text style={s.selectedRating}>{selectedPlace.rating?.toFixed(1) || '—'}</Text>
              {selectedPlace.open_now !== undefined && (
                <View style={[s.statusBadge, { backgroundColor: selectedPlace.open_now ? '#DCFCE7' : '#FEE2E2' }]}>
                  <Text style={[s.statusText, { color: selectedPlace.open_now ? '#16A34A' : '#DC2626' }]}>
                    {selectedPlace.open_now ? 'Open' : 'Closed'}
                  </Text>
                </View>
              )}
            </View>
            {selectedPlace.vicinity && (
              <Text style={s.selectedAddress} numberOfLines={1}>{selectedPlace.vicinity}</Text>
            )}
          </View>
          <TouchableOpacity style={s.navigateBtn} onPress={() => openInMaps(selectedPlace)}>
            <Ionicons name="navigate" size={20} color={colors.accentPrimary} />
          </TouchableOpacity>
        </TouchableOpacity>
      )}

      {/* Places List */}
      <ScrollView
        style={s.list}
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ paddingBottom: 60 }}
      >
        {places.map((place, idx) => (
          <TouchableOpacity
            key={place.place_id}
            style={[s.placeCard, selectedPlace?.place_id === place.place_id && s.placeCardSelected]}
            onPress={() => {
              setSelectedPlace(place);
              router.push(`/place/${place.place_id}`);
            }}
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
              style={s.dirNavBtn}
              onPress={() => openInMaps(place)}
            >
              <Ionicons name="navigate" size={18} color={colors.accentPrimary} />
            </TouchableOpacity>
          </TouchableOpacity>
        ))}
      </ScrollView>
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
  expandBtn: {
    width: 40, height: 40, borderRadius: 20, backgroundColor: colors.accentPrimaryLight,
    justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: colors.accentPrimary + '30',
  },

  mapContainer: {
    borderBottomWidth: 1, borderBottomColor: colors.borderSubtle,
    overflow: 'hidden',
  },
  loadingCenter: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#F3F4F6' },
  loadingText: { marginTop: 8, fontSize: 13, color: colors.textHint },

  selectedCard: {
    flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12,
    backgroundColor: colors.accentPrimaryLight, borderBottomWidth: 1, borderBottomColor: colors.accentPrimary + '30',
    gap: 12,
  },
  selectedImage: { width: 50, height: 50, borderRadius: 12, overflow: 'hidden' },
  selectedImagePlaceholder: { backgroundColor: colors.bgSubtle, justifyContent: 'center', alignItems: 'center' },
  selectedInfo: { flex: 1 },
  selectedName: { fontSize: 15, fontWeight: '700', color: colors.textPrimary },
  selectedMeta: { flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 3 },
  selectedRating: { fontSize: 13, fontWeight: '600', color: colors.textSecondary },
  selectedAddress: { fontSize: 12, color: colors.textHint, marginTop: 2 },
  navigateBtn: {
    width: 44, height: 44, borderRadius: 22, backgroundColor: '#FFFFFF',
    justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: colors.accentPrimary + '30',
  },

  list: { flex: 1 },
  placeCard: {
    flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 14,
    borderBottomWidth: 1, borderBottomColor: colors.borderSubtle, gap: 12,
  },
  placeCardSelected: { backgroundColor: colors.accentPrimaryLight },
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
  dirNavBtn: {
    width: 44, height: 44, borderRadius: 22, backgroundColor: colors.accentPrimaryLight,
    justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: colors.accentPrimary + '30',
  },
});
