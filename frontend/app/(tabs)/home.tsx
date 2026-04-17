import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, FlatList,
  RefreshControl, Dimensions, ScrollView,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';

const { width: SW } = Dimensions.get('window');
const GAP = 8;
const PAD = 10;
const COL_W = (SW - PAD * 2 - GAP) / 2;
const RATIOS = [1.4, 1.05, 1.55, 1.2, 1.35, 1.0, 1.45, 1.1];

const FILTERS = [
  { id: 'all', label: 'For You' },
  { id: 'global', label: 'Global' },
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
  const [filter, setFilter] = useState('all');
  const [posts, setPosts] = useState<any[]>([]);
  const [refreshing, setRefreshing] = useState(false);

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
    if (filter === 'all' || filter === 'global') return posts;
    const kw = CITY_KW[filter] || [];
    const f = posts.filter((p: any) => {
      const t = ((p.location || '') + ' ' + (p.content || '')).toLowerCase();
      return kw.some(k => t.includes(k));
    });
    return f.length > 0 ? f : posts;
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
    if (lh <= rh) { L.push({ ...p, _h: h }); lh += h + GAP + 48; }
    else { R.push({ ...p, _h: h }); rh += h + GAP + 48; }
  });

  const PinCard = ({ p }: { p: any }) => {
    const img = p.image || (p.images && p.images[0]);
    const name = p.user_full_name || p.user_username || '';
    return (
      <TouchableOpacity style={s.pin} activeOpacity={0.96} onPress={() => router.push(`/post/${p.id}` as any)}>
        <Image source={{ uri: img }} style={[s.pinImg, { height: p._h }]} resizeMode="cover" />
        <View style={s.pinBot}>
          {p.content ? <Text style={s.pinCap} numberOfLines={2}>{p.content}</Text> : null}
          <View style={s.pinRow}>
            {p.user_profile_image ? (
              <Image source={{ uri: p.user_profile_image }} style={s.pinAv} />
            ) : (
              <View style={s.pinAvFb}><Text style={s.pinAvTx}>{(name || 'U')[0]}</Text></View>
            )}
            <Text style={s.pinName} numberOfLines={1}>{name}</Text>
            <TouchableOpacity><Ionicons name="ellipsis-horizontal" size={14} color="#CCC" /></TouchableOpacity>
          </View>
        </View>
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
          items.length > 0 ? (
            <View style={s.grid}>
              <View style={s.col}>{L.map(p => <PinCard key={p.id} p={p} />)}</View>
              <View style={s.col}>{R.map(p => <PinCard key={p.id} p={p} />)}</View>
            </View>
          ) : (
            <View style={s.empty}>
              <Ionicons name="images-outline" size={40} color="#DDD" />
              <Text style={s.emptyTx}>No posts yet</Text>
            </View>
          )
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

  pin: { borderRadius: 16, overflow: 'hidden', backgroundColor: '#FFF' },
  pinImg: { width: '100%', borderTopLeftRadius: 16, borderTopRightRadius: 16 },
  pinBot: { paddingHorizontal: 10, paddingTop: 8, paddingBottom: 10 },
  pinCap: { fontSize: 13, fontWeight: '600', color: '#1A1A1A', lineHeight: 17, marginBottom: 6 },
  pinRow: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  pinAv: { width: 20, height: 20, borderRadius: 10 },
  pinAvFb: { width: 20, height: 20, borderRadius: 10, backgroundColor: '#F0F0F0', justifyContent: 'center', alignItems: 'center' },
  pinAvTx: { fontSize: 9, fontWeight: '700', color: '#BBB' },
  pinName: { fontSize: 12, color: '#999', fontWeight: '500', flex: 1 },

  empty: { paddingTop: 100, alignItems: 'center' },
  emptyTx: { fontSize: 14, color: '#CCC', marginTop: 10 },
});
