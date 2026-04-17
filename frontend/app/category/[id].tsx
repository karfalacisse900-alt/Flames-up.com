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
const GAP = 3;
const COL = 4;
const TILE = (SW - 24 - GAP * (COL - 1)) / COL;

const CAT_META: Record<string, { title: string; types: string[]; icon: string }> = {
  nearby: { title: 'Nearby', types: ['restaurant', 'cafe', 'bar', 'store'], icon: 'location' },
  restaurants: { title: 'Restaurants', types: ['restaurant'], icon: 'restaurant' },
  'things-to-do': { title: 'Things to Do', types: ['tourist_attraction', 'museum', 'park'], icon: 'compass' },
  events: { title: 'Events', types: ['night_club', 'stadium', 'movie_theater'], icon: 'calendar' },
  groups: { title: 'Groups', types: ['gym', 'church', 'library'], icon: 'people' },
  nightlife: { title: 'Nightlife', types: ['night_club', 'bar'], icon: 'moon' },
};

const TYPE_LABELS: Record<string, string> = {
  restaurant: 'Restaurants', cafe: 'Cafes', bar: 'Bars', store: 'Shopping',
  tourist_attraction: 'Attractions', museum: 'Museums', park: 'Parks',
  night_club: 'Clubs', stadium: 'Venues', movie_theater: 'Cinema',
  gym: 'Fitness', church: 'Community', library: 'Libraries',
};

export default function CategoryScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { id } = useLocalSearchParams<{ id: string }>();
  const meta = CAT_META[id || 'nearby'] || CAT_META.nearby;

  const [sections, setSections] = useState<Record<string, any[]>>({});
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [lat, setLat] = useState(40.7128);
  const [lng, setLng] = useState(-74.006);

  useEffect(() => {
    (async () => {
      try {
        const { status } = await Location.requestForegroundPermissionsAsync();
        if (status === 'granted') {
          const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High });
          setLat(loc.coords.latitude);
          setLng(loc.coords.longitude);
        }
      } catch {}
    })();
  }, []);

  useEffect(() => { if (lat !== 40.7128 || lng !== -74.006) loadData(); }, [lat, lng]);

  const loadData = async () => {
    setLoading(true);
    const result: Record<string, any[]> = {};
    for (const type of meta.types) {
      try {
        const r = await api.get('/google-places/nearby', { params: { lat, lng, radius: 3000, type } });
        if (Array.isArray(r.data) && r.data.length > 0) {
          result[type] = r.data;
        }
      } catch {}
    }
    setSections(result);
    setLoading(false);
  };

  const onRefresh = useCallback(async () => {
    setRefreshing(true); await loadData(); setRefreshing(false);
  }, [lat, lng]);

  return (
    <View style={s.container}>
      <View style={[s.header, { paddingTop: insets.top }]}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="chevron-back" size={20} color="#1A1A1A" />
        </TouchableOpacity>
        <Text style={s.headerTitle}>{meta.title}</Text>
        <View style={{ width: 40 }} />
      </View>

      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {loading ? (
          <View style={s.center}><ActivityIndicator size="large" color="#1A1A1A" /></View>
        ) : Object.keys(sections).length === 0 ? (
          <View style={s.center}>
            <Ionicons name="location-outline" size={40} color="#DDD" />
            <Text style={s.emptyTx}>No places found nearby</Text>
          </View>
        ) : (
          Object.entries(sections).map(([type, places]) => (
            <View key={type} style={s.section}>
              <Text style={s.sectionTitle}>{TYPE_LABELS[type] || type}</Text>
              <View style={s.grid}>
                {places.map((place, i) => (
                  <TouchableOpacity key={place.place_id || i} style={s.tile} activeOpacity={0.9}
                    onPress={() => router.push(`/place/${place.place_id}` as any)}>
                    {place.photo_url ? (
                      <Image source={{ uri: place.photo_url }} style={s.tileImg} resizeMode="cover" />
                    ) : (
                      <View style={[s.tileImg, { backgroundColor: '#F0F0F0', justifyContent: 'center', alignItems: 'center' }]}>
                        <Ionicons name={meta.icon as any} size={16} color="#CCC" />
                      </View>
                    )}
                  </TouchableOpacity>
                ))}
              </View>
            </View>
          ))
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#E8E6E1' },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingBottom: 8 },
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#FFF', justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 20, fontWeight: '800', color: '#1A1A1A' },

  section: { paddingHorizontal: 12, marginBottom: 20 },
  sectionTitle: { fontSize: 20, fontWeight: '800', color: '#1A1A1A', marginBottom: 8, fontStyle: 'italic' },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: GAP },
  tile: { width: TILE, height: TILE, borderRadius: 8, overflow: 'hidden' },
  tileImg: { width: '100%', height: '100%' },

  center: { paddingTop: 100, alignItems: 'center' },
  emptyTx: { fontSize: 14, color: '#AAA', marginTop: 10 },
});
