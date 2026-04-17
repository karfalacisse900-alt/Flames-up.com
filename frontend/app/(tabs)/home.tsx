import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, FlatList,
  RefreshControl, Dimensions, ScrollView,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as Location from 'expo-location';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';

const { width: SW } = Dimensions.get('window');
const GAP = 6;
const PAD = 8;
const COL_W = (SW - PAD * 2 - GAP) / 2;
const RATIOS = [1.4, 1.05, 1.55, 1.2, 1.35, 1.0, 1.45, 1.1];

const FILTERS = [
  { id: 'near', label: 'Near You' },
  { id: 'world', label: 'World Board' },
  { id: 'nyc', label: 'NYC' },
  { id: 'miami', label: 'Miami' },
  { id: 'la', label: 'LA' },
  { id: 'tokyo', label: 'Tokyo' },
  { id: 'london', label: 'London' },
  { id: 'paris', label: 'Paris' },
];

const CITY_KW: Record<string, string[]> = {
  nyc: ['new york', 'nyc', 'brooklyn', 'manhattan'],
  miami: ['miami', 'south beach', 'wynwood'],
  la: ['los angeles', 'la', 'hollywood', 'venice'],
  tokyo: ['tokyo', 'shibuya', 'shinjuku'],
  london: ['london', 'soho', 'shoreditch'],
  paris: ['paris', 'montmartre'],
};

export default function HomeScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();
  const [filter, setFilter] = useState('near');
  const [posts, setPosts] = useState<any[]>([]);
  const [nearbyPlaces, setNearbyPlaces] = useState<Record<string, any[]>>({});
  const [refreshing, setRefreshing] = useState(false);
  const [userCity, setUserCity] = useState('');
  const [userLat, setUserLat] = useState(40.7128);
  const [userLng, setUserLng] = useState(-74.006);

  useEffect(() => { loadData(); detectCity(); }, []);
  useEffect(() => { if (filter === 'near') loadNearby(); }, [filter, userLat]);

  const detectCity = async () => {
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') return;
      const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Highest });
      setUserLat(loc.coords.latitude);
      setUserLng(loc.coords.longitude);
      const [addr] = await Location.reverseGeocodeAsync({ latitude: loc.coords.latitude, longitude: loc.coords.longitude });
      if (addr?.city) setUserCity(addr.city.toLowerCase());
    } catch {}
  };

  const loadNearby = async () => {
    const types = [
      { key: 'park', label: 'Parks' },
      { key: 'restaurant', label: 'Restaurants' },
      { key: 'art_gallery', label: 'Art' },
      { key: 'cafe', label: 'Cafes' },
      { key: 'tourist_attraction', label: 'Places' },
    ];
    const result: Record<string, any[]> = {};
    for (const t of types) {
      try {
        const r = await api.get('/google-places/nearby', { params: { lat: userLat, lng: userLng, radius: 8000, type: t.key } });
        if (Array.isArray(r.data) && r.data.length > 0) result[t.label] = r.data;
      } catch {}
    }
    setNearbyPlaces(result);
  };

  useEffect(() => { loadData(); }, []);

  const loadData = async () => {
    try {
      const r = await api.get('/posts/feed', { params: { limit: 40 } });
      setPosts(Array.isArray(r.data) ? r.data : []);
    } catch {}
  };

  const onRefresh = useCallback(async () => {
    setRefreshing(true); await loadData(); setRefreshing(false);
  }, []);

  const filtered = (() => {
    if (filter === 'world') return posts; // World Board = all posts
    if (filter === 'near') {
      if (!userCity) return posts;
      const f = posts.filter((p: any) => {
        const loc = ((p.location || '') + ' ' + (p.content || '')).toLowerCase();
        return loc.includes(userCity);
      });
      return f.length > 0 ? f : posts;
    }
    const kw = CITY_KW[filter] || [];
    const f = posts.filter((p: any) => {
      const t = ((p.location || '') + ' ' + (p.content || '')).toLowerCase();
      return kw.some(k => t.includes(k));
    });
    return f.length > 0 ? f : [];
  })();

  const items = filtered.filter((p: any) => {
    const img = p.image || (p.images && p.images[0]);
    return img && typeof img === 'string' && (img.startsWith('http') || img.startsWith('data:'));
  });

  // Build masonry
  const L: any[] = [], R: any[] = [];
  let lh = 0, rh = 0;
  items.forEach((p, i) => {
    const h = COL_W * RATIOS[i % RATIOS.length];
    if (lh <= rh) { L.push({ ...p, _h: h }); lh += h + GAP; }
    else { R.push({ ...p, _h: h }); rh += h + GAP; }
  });

  const PinCard = ({ p }: { p: any }) => {
    const img = p.image || (p.images && p.images[0]);
    return (
      <TouchableOpacity style={[s.pin, { height: p._h }]} activeOpacity={0.96} onPress={() => router.push(`/post/${p.id}` as any)}>
        <Image source={{ uri: img }} style={s.pinImg} resizeMode="cover" />
        <TouchableOpacity style={s.pinMore}>
          <Ionicons name="ellipsis-horizontal" size={16} color="#FFF" />
        </TouchableOpacity>
      </TouchableOpacity>
    );
  };

  return (
    <View style={s.root}>
      {/* STICKY HEADER — stays fixed at top */}
      <View style={[s.stickyHeader, { paddingTop: insets.top + 6 }]}>
        {/* Top row: buttons */}
        <View style={s.topRow}>
          <View style={s.headerR}>
            <TouchableOpacity style={s.hBtn} onPress={() => router.push('/create-post' as any)}>
              <Ionicons name="add" size={20} color="#FFF" />
            </TouchableOpacity>
            <TouchableOpacity style={s.hBtnLight} onPress={() => router.push('/notifications' as any)}>
              <Ionicons name="notifications-outline" size={18} color="#1A1A1A" />
            </TouchableOpacity>
          </View>
        </View>
        {/* Filter tabs */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.filters}>
          {FILTERS.map(f => (
            <TouchableOpacity key={f.id} style={[s.chip, filter === f.id && s.chipOn]} onPress={() => setFilter(f.id)}>
              <Text style={[s.chipTx, filter === f.id && s.chipTxOn]}>{f.label}</Text>
            </TouchableOpacity>
          ))}
        </ScrollView>
      </View>

      {/* SCROLLABLE GRID */}
      <FlatList
        data={[1]}
        keyExtractor={() => 'grid'}
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
        contentContainerStyle={{ paddingBottom: 100 }}
        renderItem={() => (
          <>
            {/* Near You: Show nearby places in sections */}
            {filter === 'near' && Object.keys(nearbyPlaces).length > 0 && (
              <View style={s.nearSections}>
                {Object.entries(nearbyPlaces).map(([label, places]) => (
                  <View key={label} style={s.nearSection}>
                    <Text style={s.nearSectionTitle}>{label}</Text>
                    <View style={s.nearGrid}>
                      {places.slice(0, 8).map((place: any, i: number) => (
                        <TouchableOpacity key={place.place_id || i} style={s.nearTile} activeOpacity={0.92}>
                          {place.photo_url ? (
                            <Image source={{ uri: place.photo_url }} style={s.nearTileImg} resizeMode="cover" />
                          ) : (
                            <View style={[s.nearTileImg, { backgroundColor: '#E0DCD7', justifyContent: 'center', alignItems: 'center' }]}>
                              <Ionicons name="image-outline" size={16} color="#BBB" />
                            </View>
                          )}
                        </TouchableOpacity>
                      ))}
                    </View>
                  </View>
                ))}
              </View>
            )}
            {/* Regular posts grid */}
            {items.length > 0 ? (
              <View style={s.grid}>
                <View style={s.col}>{L.map(p => <PinCard key={p.id} p={p} />)}</View>
                <View style={s.col}>{R.map(p => <PinCard key={p.id} p={p} />)}</View>
              </View>
            ) : filter !== 'near' ? (
              <View style={s.empty}>
                <Ionicons name="images-outline" size={40} color="#DDD" />
                <Text style={s.emptyTx}>No posts in this city yet</Text>
              </View>
            ) : null}
          </>
        )}
      />
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#FFF' },

  // Sticky header
  stickyHeader: { backgroundColor: '#FFF', borderBottomWidth: 0.5, borderBottomColor: '#F0F0F0', zIndex: 10 },
  topRow: { flexDirection: 'row', justifyContent: 'flex-end', alignItems: 'center', paddingHorizontal: 16, paddingBottom: 6 },
  headerR: { flexDirection: 'row', gap: 8 },
  hBtn: { width: 36, height: 36, borderRadius: 18, backgroundColor: '#1A1A1A', justifyContent: 'center', alignItems: 'center' },
  hBtnLight: { width: 36, height: 36, borderRadius: 18, backgroundColor: '#F0F0F0', justifyContent: 'center', alignItems: 'center' },

  filters: { paddingHorizontal: 12, paddingBottom: 10, gap: 6 },
  chip: { paddingHorizontal: 16, paddingVertical: 8, borderRadius: 20, backgroundColor: '#F5F5F5' },
  chipOn: { backgroundColor: '#1A1A1A' },
  chipTx: { fontSize: 13, fontWeight: '600', color: '#999' },
  chipTxOn: { color: '#FFF' },

  // Grid
  grid: { flexDirection: 'row', paddingHorizontal: PAD, gap: GAP, paddingTop: 6 },
  col: { flex: 1, gap: GAP },

  pin: { borderRadius: 12, overflow: 'hidden', backgroundColor: '#F0F0F0' },
  pinImg: { width: '100%', height: '100%' },
  pinMore: { position: 'absolute', bottom: 8, right: 8, width: 28, height: 28, borderRadius: 14, backgroundColor: 'rgba(0,0,0,0.4)', justifyContent: 'center', alignItems: 'center' },

  // Near You sections (Things to Do style)
  nearSections: { paddingHorizontal: 10, marginBottom: 16 },
  nearSection: { marginBottom: 20 },
  nearSectionTitle: { fontSize: 22, fontWeight: '900', color: '#1A1A1A', fontStyle: 'italic', marginBottom: 8 },
  nearGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 3 },
  nearTile: { width: (SW - 20 - 9) / 4, height: (SW - 20 - 9) / 4, borderRadius: 8, overflow: 'hidden' },
  nearTileImg: { width: '100%', height: '100%' },

  empty: { paddingTop: 100, alignItems: 'center' },
  emptyTx: { fontSize: 14, color: '#CCC', marginTop: 10 },
});
