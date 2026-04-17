import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView,
  RefreshControl, Dimensions, ActivityIndicator,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as Location from 'expo-location';
import api from '../../src/api/client';

const { width: SW } = Dimensions.get('window');
const G = 3;
const P = 12;
const C4 = (SW - P * 2 - G * 3) / 4;
const C2 = C4 * 2 + G;
const RADIUS = 40000; // 25 miles in meters

const CAT_CONFIG: Record<string, { title: string; types: { key: string; label: string }[] }> = {
  'things-to-do': {
    title: 'Things to Do',
    types: [
      { key: 'park', label: 'Parks' },
      { key: 'library', label: 'Libraries' },
      { key: 'museum', label: 'Museums' },
      { key: 'art_gallery', label: 'Art' },
      { key: 'restaurant', label: 'Restaurants' },
      { key: 'tourist_attraction', label: 'Places to Go' },
      { key: 'shopping_mall', label: 'Shopping' },
      { key: 'amusement_park', label: 'Fun & Play' },
    ],
  },
  nightlife: {
    title: 'Nightlife',
    types: [
      { key: 'night_club', label: 'Clubs' },
      { key: 'bar', label: 'Bars & Lounges' },
      { key: 'casino', label: 'Casino' },
      { key: 'movie_theater', label: 'Late Night Cinema' },
    ],
  },
  events: {
    title: 'Events',
    types: [
      { key: 'stadium', label: 'Venues' },
      { key: 'movie_theater', label: 'Cinema' },
      { key: 'church', label: 'Community' },
      { key: 'city_hall', label: 'Local Events' },
    ],
  },
  groups: {
    title: 'Groups to Join',
    types: [
      { key: 'gym', label: 'Fitness' },
      { key: 'church', label: 'Community' },
      { key: 'library', label: 'Book Clubs' },
      { key: 'university', label: 'Education' },
    ],
  },
  activity: {
    title: 'Activity',
    types: [
      { key: 'gym', label: 'Fitness' },
      { key: 'park', label: 'Outdoor' },
      { key: 'bowling_alley', label: 'Bowling' },
      { key: 'spa', label: 'Wellness' },
    ],
  },
  'world-board': {
    title: 'World Board',
    types: [
      { key: 'tourist_attraction', label: 'Attractions' },
      { key: 'museum', label: 'Museums' },
      { key: 'restaurant', label: 'Dining' },
      { key: 'lodging', label: 'Hotels' },
    ],
  },
};

export default function CategoryScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { id } = useLocalSearchParams<{ id: string }>();
  const config = CAT_CONFIG[id || 'things-to-do'] || CAT_CONFIG['things-to-do'];

  const [sections, setSections] = useState<Record<string, any[]>>({});
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [coords, setCoords] = useState({ lat: 40.7128, lng: -74.006 }); // Default NYC
  const [locReady, setLocReady] = useState(false);

  useEffect(() => {
    (async () => {
      try {
        const { status } = await Location.requestForegroundPermissionsAsync();
        if (status === 'granted') {
          const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High });
          setCoords({ lat: loc.coords.latitude, lng: loc.coords.longitude });
        }
      } catch {}
      setLocReady(true);
    })();
  }, []);

  useEffect(() => { if (locReady) loadData(); }, [locReady]);

  const loadData = async () => {
    setLoading(true);
    const result: Record<string, any[]> = {};
    for (const t of config.types) {
      try {
        const r = await api.get('/google-places/nearby', { params: { lat: coords.lat, lng: coords.lng, radius: RADIUS, type: t.key } });
        if (Array.isArray(r.data) && r.data.length > 0) result[t.label] = r.data;
      } catch {}
    }
    setSections(result);
    setLoading(false);
  };

  const onRefresh = useCallback(async () => { setRefreshing(true); await loadData(); setRefreshing(false); }, [coords]);

  // Masonry tile layout — varying sizes like the reference
  const renderSection = (label: string, places: any[]) => {
    const tiles: React.ReactNode[] = [];
    let i = 0;
    while (i < places.length) {
      const p1 = places[i];
      const p2 = places[i + 1];
      const p3 = places[i + 2];
      const p4 = places[i + 3];

      if (i === 0 && places.length >= 3) {
        // First row: 1 large + 2 small stacked
        tiles.push(
          <View key={`r${i}`} style={ms.row}>
            <Tile place={p1} w={C2} h={C2} />
            <View style={ms.stackCol}>
              {p2 && <Tile place={p2} w={C4 * 2 + G} h={C4} />}
              {p3 && <Tile place={p3} w={C4 * 2 + G} h={C4} />}
            </View>
          </View>
        );
        i += 3;
      } else {
        // Regular 4-column row
        tiles.push(
          <View key={`r${i}`} style={ms.row4}>
            {[p1, p2, p3, p4].filter(Boolean).map((p, idx) => (
              <Tile key={p?.place_id || idx} place={p} w={C4} h={C4} />
            ))}
          </View>
        );
        i += 4;
      }
    }
    return (
      <View key={label} style={ms.section}>
        <Text style={ms.sectionTitle}>{label}</Text>
        {tiles}
      </View>
    );
  };

  const Tile = ({ place, w, h }: { place: any; w: number; h: number }) => {
    if (!place) return null;
    return (
      <TouchableOpacity style={[ms.tile, { width: w, height: h }]} activeOpacity={0.92}
        onPress={() => router.push(`/place/${place.place_id}` as any)}>
        {place.photo_url ? (
          <Image source={{ uri: place.photo_url }} style={ms.tileImg} resizeMode="cover" />
        ) : (
          <View style={[ms.tileImg, { backgroundColor: '#D5D0C8', justifyContent: 'center', alignItems: 'center' }]}>
            <Ionicons name="image-outline" size={20} color="#AAA" />
          </View>
        )}
      </TouchableOpacity>
    );
  };

  return (
    <View style={ms.container}>
      {/* Header */}
      <View style={[ms.header, { paddingTop: insets.top }]}>
        <TouchableOpacity style={ms.backBtn} onPress={() => router.back()}>
          <Ionicons name="chevron-back" size={20} color="#1A1A1A" />
        </TouchableOpacity>
        <Text style={ms.headerTitle}>{config.title}</Text>
        <View style={{ width: 40 }} />
      </View>

      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {loading ? (
          <View style={ms.center}><ActivityIndicator size="large" color="#1A1A1A" /></View>
        ) : Object.keys(sections).length === 0 ? (
          <View style={ms.center}>
            <Ionicons name="location-outline" size={48} color="#BBB" />
            <Text style={ms.emptyTx}>No places found within 25 miles</Text>
          </View>
        ) : (
          Object.entries(sections).map(([label, places]) => renderSection(label, places))
        )}
      </ScrollView>
    </View>
  );
}

const ms = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#E2DFD7' },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 14, paddingBottom: 8 },
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#FFF', justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 20, fontWeight: '800', color: '#1A1A1A' },

  section: { paddingHorizontal: P, marginBottom: 24 },
  sectionTitle: { fontSize: 22, fontWeight: '900', color: '#1A1A1A', fontStyle: 'italic', marginBottom: 8 },

  row: { flexDirection: 'row', gap: G, marginBottom: G },
  stackCol: { gap: G },
  row4: { flexDirection: 'row', gap: G, marginBottom: G },

  tile: { borderRadius: 10, overflow: 'hidden' },
  tileImg: { width: '100%', height: '100%' },

  center: { paddingTop: 100, alignItems: 'center' },
  emptyTx: { fontSize: 14, color: '#999', marginTop: 12 },
});
