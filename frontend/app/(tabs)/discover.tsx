import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView,
  RefreshControl, Dimensions, ActivityIndicator,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import api from '../../src/api/client';

const { width: SW } = Dimensions.get('window');
const GAP = 6;
const PAD = 6;
const COL_W = (SW - PAD * 2 - GAP) / 2;

const TABS = [
  { id: 'all', label: 'For You' },
  { id: 'outfits', label: 'Outfits' },
  { id: 'travel', label: 'Travel' },
  { id: 'food', label: 'Food' },
  { id: 'car', label: 'Cars' },
  { id: 'humor', label: 'Humor' },
  { id: 'fitness', label: 'Fitness' },
  { id: 'beauty', label: 'Beauty' },
  { id: 'art', label: 'Art' },
  { id: 'music', label: 'Music' },
];

// Alternating image heights for staggered masonry
const RATIOS = [1.35, 1.0, 1.5, 1.15, 1.3, 0.95, 1.4, 1.1];

export default function DiscoverScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const [tab, setTab] = useState('all');
  const [posts, setPosts] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  useEffect(() => { load(); }, []);

  const load = async () => {
    try {
      setLoading(true);
      const r = await api.get('/posts/feed', { params: { limit: 50 } });
      setPosts(Array.isArray(r.data) ? r.data : []);
    } catch {} finally { setLoading(false); }
  };

  const onRefresh = useCallback(async () => {
    setRefreshing(true); await load(); setRefreshing(false);
  }, []);

  // Filter by tab
  const filtered = tab === 'all' ? posts : posts.filter((p: any) => {
    const t = ((p.content || '') + ' ' + (p.post_type || '')).toLowerCase();
    return t.includes(tab);
  });

  // Only posts with images
  const items = filtered.filter((p: any) => {
    const img = p.image || (p.images && p.images[0]);
    return img && typeof img === 'string' && (img.startsWith('http') || img.startsWith('data:'));
  });

  // Build masonry
  const L: any[] = [];
  const R: any[] = [];
  let lh = 0, rh = 0;
  items.forEach((p, i) => {
    const h = COL_W * RATIOS[i % RATIOS.length];
    if (lh <= rh) { L.push({ ...p, _h: h }); lh += h + GAP + 52; }
    else { R.push({ ...p, _h: h }); rh += h + GAP + 52; }
  });

  const Card = ({ p }: { p: any }) => {
    const img = p.image || (p.images && p.images[0]);
    const name = p.user_full_name || p.user_username || '';
    return (
      <TouchableOpacity style={s.card} activeOpacity={0.96} onPress={() => router.push(`/post/${p.id}` as any)}>
        <Image source={{ uri: img }} style={[s.cardImg, { height: p._h }]} resizeMode="cover" />
        <View style={s.cardBot}>
          {p.content ? <Text style={s.cardCap} numberOfLines={2}>{p.content}</Text> : null}
          <View style={s.cardRow}>
            {p.user_profile_image ? (
              <Image source={{ uri: p.user_profile_image }} style={s.av} />
            ) : (
              <View style={s.avFb}><Text style={s.avTx}>{(name || 'U')[0]}</Text></View>
            )}
            <Text style={s.cardName} numberOfLines={1}>{name}</Text>
            <Ionicons name="heart-outline" size={12} color="#CCC" />
          </View>
        </View>
      </TouchableOpacity>
    );
  };

  return (
    <View style={s.root}>
      <View style={[s.head, { paddingTop: insets.top + 4 }]}>
        <Text style={s.title}>Discover</Text>
        <TouchableOpacity style={s.searchBtn}><Ionicons name="search" size={18} color="#1A1A1A" /></TouchableOpacity>
      </View>

      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.tabs}>
        {TABS.map(t => (
          <TouchableOpacity key={t.id} onPress={() => setTab(t.id)} style={[s.tab, tab === t.id && s.tabOn]}>
            <Text style={[s.tabTx, tab === t.id && s.tabTxOn]}>{t.label}</Text>
          </TouchableOpacity>
        ))}
      </ScrollView>

      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {loading ? (
          <View style={s.center}><ActivityIndicator size="large" color="#1A1A1A" /></View>
        ) : items.length === 0 ? (
          <View style={s.center}>
            <Ionicons name="images-outline" size={40} color="#DDD" />
            <Text style={s.empty}>No posts yet</Text>
          </View>
        ) : (
          <View style={s.grid}>
            <View style={s.col}>{L.map(p => <Card key={p.id} p={p} />)}</View>
            <View style={s.col}>{R.map(p => <Card key={p.id} p={p} />)}</View>
          </View>
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#FAFAF8' },
  head: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingBottom: 6 },
  title: { fontSize: 24, fontWeight: '800', color: '#1A1A1A', letterSpacing: -0.5 },
  searchBtn: { width: 38, height: 38, borderRadius: 19, backgroundColor: '#F0F0F0', justifyContent: 'center', alignItems: 'center' },

  tabs: { paddingHorizontal: 12, paddingBottom: 8, gap: 4 },
  tab: { paddingHorizontal: 16, paddingVertical: 8, borderRadius: 20, backgroundColor: '#F0F0F0' },
  tabOn: { backgroundColor: '#1A1A1A' },
  tabTx: { fontSize: 13, fontWeight: '600', color: '#999' },
  tabTxOn: { color: '#FFF' },

  grid: { flexDirection: 'row', paddingHorizontal: PAD, gap: GAP },
  col: { flex: 1, gap: GAP },

  card: { borderRadius: 12, overflow: 'hidden', backgroundColor: '#FFF' },
  cardImg: { width: '100%' },
  cardBot: { paddingHorizontal: 8, paddingTop: 6, paddingBottom: 8 },
  cardCap: { fontSize: 13, fontWeight: '600', color: '#1A1A1A', lineHeight: 17, marginBottom: 5 },
  cardRow: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  av: { width: 16, height: 16, borderRadius: 8 },
  avFb: { width: 16, height: 16, borderRadius: 8, backgroundColor: '#EEE', justifyContent: 'center', alignItems: 'center' },
  avTx: { fontSize: 8, fontWeight: '700', color: '#BBB' },
  cardName: { fontSize: 11, color: '#AAA', flex: 1 },

  center: { paddingTop: 100, alignItems: 'center' },
  empty: { fontSize: 14, color: '#CCC', marginTop: 10 },
});
