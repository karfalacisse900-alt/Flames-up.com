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

  // Build collage layout groups
  const Img = ({ uri, h, w, onPress }: { uri: string; h: number; w?: any; onPress?: () => void }) => (
    <TouchableOpacity style={[s.tile, { height: h, width: w || '100%' }]} activeOpacity={0.95} onPress={onPress}>
      <Image source={{ uri }} style={s.tileImg} resizeMode="cover" />
    </TouchableOpacity>
  );

  const collageGroups: React.ReactNode[] = [];
  let idx = 0;
  const BIG = COL_W * 1.3;
  const SMALL = (BIG - GAP) / 2;
  const ROW4 = COL_W * 0.95;

  while (idx < items.length) {
    const g = items.slice(idx, idx + 6);
    if (g.length >= 3) {
      // Row 1: 1 big left + 2 stacked right
      collageGroups.push(
        <View key={`c${idx}`} style={s.collageRow}>
          <Img uri={g[0].image || g[0].images?.[0]} h={BIG} w={COL_W} onPress={() => router.push(`/post/${g[0].id}` as any)} />
          <View style={s.collageStack}>
            <Img uri={g[1].image || g[1].images?.[0]} h={SMALL} onPress={() => router.push(`/post/${g[1].id}` as any)} />
            {g[2] && <Img uri={g[2].image || g[2].images?.[0]} h={SMALL} onPress={() => router.push(`/post/${g[2].id}` as any)} />}
          </View>
        </View>
      );
    }
    if (g.length >= 4) {
      // Row 2: 4 equal
      const row4 = g.slice(3, 7);
      if (row4.length > 0) {
        collageGroups.push(
          <View key={`r${idx}`} style={s.collageRow4}>
            {row4.map((p: any, i: number) => (
              <Img key={p.id || i} uri={p.image || p.images?.[0]} h={ROW4} w={(SW - PAD * 2 - GAP * 3) / 4} onPress={() => router.push(`/post/${p.id}` as any)} />
            ))}
          </View>
        );
      }
    }
    idx += Math.min(g.length, 7);
  }

  // Near You collage for places
  const nearCollage: React.ReactNode[] = [];
  Object.entries(nearbyPlaces).forEach(([label, places], sIdx) => {
    nearCollage.push(<Text key={`t${sIdx}`} style={s.nearSectionTitle}>{label}</Text>);
    const pp = places.slice(0, 6);
    if (pp.length >= 3) {
      nearCollage.push(
        <View key={`nr${sIdx}`} style={s.collageRow}>
          {pp[0]?.photo_url ? <Img uri={pp[0].photo_url} h={BIG} w={COL_W} /> : <View style={[s.tile, { height: BIG, width: COL_W, backgroundColor: '#E0DCD7' }]} />}
          <View style={s.collageStack}>
            {pp[1]?.photo_url ? <Img uri={pp[1].photo_url} h={SMALL} /> : <View style={[s.tile, { height: SMALL, backgroundColor: '#E0DCD7' }]} />}
            {pp[2]?.photo_url ? <Img uri={pp[2].photo_url} h={SMALL} /> : null}
          </View>
        </View>
      );
    }
    if (pp.length > 3) {
      nearCollage.push(
        <View key={`nr4${sIdx}`} style={s.collageRow4}>
          {pp.slice(3, 7).map((p: any, i: number) => (
            p.photo_url ? <Img key={i} uri={p.photo_url} h={ROW4} w={(SW - PAD * 2 - GAP * 3) / 4} /> : <View key={i} style={[s.tile, { height: ROW4, width: (SW - PAD * 2 - GAP * 3) / 4, backgroundColor: '#E0DCD7' }]} />
          ))}
        </View>
      );
    }
  });

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
            {/* Near You: Show nearby places in collage */}
            {filter === 'near' && Object.keys(nearbyPlaces).length > 0 && (
              <View style={s.collageWrap}>{nearCollage}</View>
            )}
            {/* Posts collage */}
            {items.length > 0 ? (
              <View style={s.collageWrap}>{collageGroups}</View>
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
  // Collage grid
  collageWrap: { paddingHorizontal: PAD, gap: GAP },
  collageRow: { flexDirection: 'row', gap: GAP },
  collageStack: { flex: 1, gap: GAP },
  collageRow4: { flexDirection: 'row', gap: GAP },
  tile: { borderRadius: 10, overflow: 'hidden', backgroundColor: '#E0DCD7' },
  tileImg: { width: '100%', height: '100%' },
  nearSectionTitle: { fontSize: 22, fontWeight: '900', color: '#1A1A1A', fontStyle: 'italic', marginTop: 16, marginBottom: 8 },

  empty: { paddingTop: 100, alignItems: 'center' },
  emptyTx: { fontSize: 14, color: '#CCC', marginTop: 10 },
});
