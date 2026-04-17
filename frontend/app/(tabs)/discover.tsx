import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView,
  RefreshControl, Dimensions, ActivityIndicator, Modal,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import api from '../../src/api/client';

const { width: SW } = Dimensions.get('window');
const HALF = (SW - 40) / 2;

const CITY_TABS = [
  { id: 'all', label: 'For You' },
  { id: 'nyc', label: 'New York' },
  { id: 'miami', label: 'Miami' },
  { id: 'la', label: 'LA' },
  { id: 'london', label: 'London' },
  { id: 'tokyo', label: 'Tokyo' },
  { id: 'paris', label: 'Paris' },
];

const BLOCKS = [
  { id: 'things-to-do', label: 'Things to Do', sub: 'Parks, museums, restaurants & more', type: 'tourist_attraction', big: true },
  { id: 'events', label: 'Events', sub: 'Venues & meetups', type: 'stadium' },
  { id: 'nightlife', label: 'Nightlife', sub: 'Clubs, bars & parties', type: 'night_club' },
  { id: 'groups', label: 'Groups to Join', sub: 'Fitness & community', type: 'gym', big: true },
  { id: 'activity', label: 'Activity', sub: 'Outdoor & wellness', type: 'park' },
  { id: 'world-board', label: 'World Board', sub: 'Discover everywhere', type: 'museum' },
];

const CITY_KEYWORDS: Record<string, string[]> = {
  nyc: ['new york', 'nyc', 'brooklyn', 'manhattan', 'queens'],
  miami: ['miami', 'south beach', 'wynwood'],
  la: ['los angeles', 'la', 'hollywood', 'venice'],
  london: ['london', 'soho', 'shoreditch'],
  tokyo: ['tokyo', 'shibuya', 'shinjuku'],
  paris: ['paris', 'montmartre'],
};

export default function DiscoverScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const [tab, setTab] = useState('all');
  const [posts, setPosts] = useState<any[]>([]);
  const [blockImages, setBlockImages] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [showMenu, setShowMenu] = useState(false);

  useEffect(() => { load(); loadBlockImages(); }, []);

  const load = async () => {
    try {
      setLoading(true);
      const r = await api.get('/posts/feed', { params: { limit: 50 } });
      setPosts(Array.isArray(r.data) ? r.data : []);
    } catch {} finally { setLoading(false); }
  };

  const loadBlockImages = async () => {
    const imgs: Record<string, string> = {};
    for (const b of BLOCKS) {
      try {
        const r = await api.get('/google-places/nearby', { params: { lat: 40.7128, lng: -74.006, radius: 40000, type: b.type } });
        const places = Array.isArray(r.data) ? r.data : [];
        const withPhoto = places.find((p: any) => p.photo_url);
        if (withPhoto?.photo_url) imgs[b.id] = withPhoto.photo_url;
      } catch {}
    }
    setBlockImages(imgs);
  };

  const onRefresh = useCallback(async () => {
    setRefreshing(true); await load(); setRefreshing(false);
  }, []);

  const filtered = tab === 'all' ? posts : (() => {
    const kw = CITY_KEYWORDS[tab] || [];
    const f = posts.filter((p: any) => {
      const t = ((p.location || '') + ' ' + (p.content || '')).toLowerCase();
      return kw.some(k => t.includes(k));
    });
    return f.length > 0 ? f : posts;
  })();

  const imgPosts = filtered.filter((p: any) => {
    const img = p.image || (p.images && p.images[0]);
    return img && typeof img === 'string' && img.startsWith('http');
  });

  const featured = imgPosts[0];
  const row1 = imgPosts.slice(1, 3);

  return (
    <View style={s.root}>
      {/* Header */}
      <View style={[s.header, { paddingTop: insets.top + 4 }]}>
        <TouchableOpacity onPress={() => setShowMenu(true)}><Ionicons name="menu" size={24} color="#1A1A1A" /></TouchableOpacity>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.tabs}>
          {CITY_TABS.map(c => (
            <TouchableOpacity key={c.id} onPress={() => setTab(c.id)}>
              <Text style={[s.tabTx, tab === c.id && s.tabTxOn]}>{c.label.toUpperCase()}</Text>
            </TouchableOpacity>
          ))}
        </ScrollView>
        <TouchableOpacity style={s.searchIcon}><Ionicons name="search" size={18} color="#1A1A1A" /></TouchableOpacity>
      </View>

      {/* Menu */}
      <Modal visible={showMenu} transparent animationType="fade" onRequestClose={() => setShowMenu(false)}>
        <TouchableOpacity style={s.menuOv} activeOpacity={1} onPress={() => setShowMenu(false)}>
          <View style={s.menuSheet} onStartShouldSetResponder={() => true}>
            <TouchableOpacity style={s.menuItem} onPress={() => { setShowMenu(false); router.push('/map-view' as any); }}>
              <Ionicons name="map-outline" size={22} color="#1A1A1A" />
              <Text style={s.menuItemTx}>Places & Map</Text>
              <Ionicons name="chevron-forward" size={16} color="#CCC" />
            </TouchableOpacity>
          </View>
        </TouchableOpacity>
      </Modal>

      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {loading ? (
          <View style={s.center}><ActivityIndicator size="large" color="#1A1A1A" /></View>
        ) : (
          <>
            {/* Search */}
            <View style={s.searchWrap}>
              <View style={s.searchBar}>
                <Ionicons name="search" size={18} color="#999" />
                <Text style={s.searchPh}>What are you looking for?</Text>
              </View>
            </View>

            {/* Category Blocks with Google Places Images */}
            <View style={s.blocks}>
              {BLOCKS.map((b, idx) => {
                const img = blockImages[b.id];
                const isBig = idx === 0 || idx === 3;
                if (isBig) {
                  return (
                    <TouchableOpacity key={b.id} style={s.blockBig} activeOpacity={0.9} onPress={() => router.push(`/category/${b.id}` as any)}>
                      {img ? <Image source={{ uri: img }} style={s.blockBigImg} resizeMode="cover" /> : <View style={[s.blockBigImg, { backgroundColor: '#E0DCD7' }]} />}
                      <View style={s.blockBigOverlay} />
                      <View style={s.blockBigContent}>
                        <Text style={s.blockBigTitle}>{b.label}</Text>
                        <Text style={s.blockBigSub}>{b.sub}</Text>
                      </View>
                    </TouchableOpacity>
                  );
                }
                return null;
              })}

              {/* Pair rows */}
              <View style={s.blockRow}>
                {BLOCKS.filter((_, i) => i === 1 || i === 2).map(b => {
                  const img = blockImages[b.id];
                  return (
                    <TouchableOpacity key={b.id} style={s.blockHalf} activeOpacity={0.9} onPress={() => router.push(`/category/${b.id}` as any)}>
                      {img ? <Image source={{ uri: img }} style={s.blockHalfImg} resizeMode="cover" /> : <View style={[s.blockHalfImg, { backgroundColor: '#E0DCD7' }]} />}
                      <View style={s.blockHalfOverlay} />
                      <View style={s.blockHalfContent}>
                        <Text style={s.blockHalfTitle}>{b.label}</Text>
                        <Text style={s.blockHalfSub}>{b.sub}</Text>
                      </View>
                    </TouchableOpacity>
                  );
                })}
              </View>
              <View style={s.blockRow}>
                {BLOCKS.filter((_, i) => i === 4 || i === 5).map(b => {
                  const img = blockImages[b.id];
                  return (
                    <TouchableOpacity key={b.id} style={s.blockHalf} activeOpacity={0.9} onPress={() => router.push(`/category/${b.id}` as any)}>
                      {img ? <Image source={{ uri: img }} style={s.blockHalfImg} resizeMode="cover" /> : <View style={[s.blockHalfImg, { backgroundColor: '#E0DCD7' }]} />}
                      <View style={s.blockHalfOverlay} />
                      <View style={s.blockHalfContent}>
                        <Text style={s.blockHalfTitle}>{b.label}</Text>
                        <Text style={s.blockHalfSub}>{b.sub}</Text>
                      </View>
                    </TouchableOpacity>
                  );
                })}
              </View>
            </View>
          </>
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#FFF' },
  header: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingBottom: 10, gap: 12 },
  tabs: { gap: 20, alignItems: 'center' },
  tabTx: { fontSize: 13, fontWeight: '600', color: '#BBB', letterSpacing: 0.5 },
  tabTxOn: { color: '#1A1A1A', fontWeight: '800', textDecorationLine: 'underline' },
  searchIcon: { width: 38, height: 38, borderRadius: 19, backgroundColor: '#F0F0F0', justifyContent: 'center', alignItems: 'center' },

  menuOv: { flex: 1, backgroundColor: 'rgba(0,0,0,0.3)', justifyContent: 'flex-start' },
  menuSheet: { backgroundColor: '#FFF', marginTop: 100, marginHorizontal: 20, borderRadius: 16, paddingVertical: 8 },
  menuItem: { flexDirection: 'row', alignItems: 'center', gap: 14, paddingHorizontal: 20, paddingVertical: 16 },
  menuItemTx: { fontSize: 16, fontWeight: '600', color: '#1A1A1A', flex: 1 },

  feat: { paddingHorizontal: 16, marginBottom: 16 },
  featTitle: { fontSize: 26, fontWeight: '900', color: '#1A1A1A', letterSpacing: -0.5, lineHeight: 32, marginBottom: 14 },
  featImg: { width: '100%', height: SW * 0.5, borderRadius: 14 },

  row2: { flexDirection: 'row', paddingHorizontal: 16, gap: 10, marginBottom: 16 },
  row2Card: { flex: 1 },
  row2Img: { width: '100%', height: HALF * 0.85, borderRadius: 14 },
  row2Tx: { fontSize: 14, fontWeight: '600', color: '#1A1A1A', marginTop: 8 },

  searchWrap: { paddingHorizontal: 16, paddingBottom: 16 },
  searchBar: { flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: '#F5F5F5', borderRadius: 24, paddingHorizontal: 16, paddingVertical: 12 },
  searchPh: { fontSize: 14, color: '#AAA' },

  blocks: { paddingHorizontal: 16, gap: 10 },
  blockBig: { borderRadius: 20, overflow: 'hidden', height: 180, position: 'relative' },
  blockBigImg: { position: 'absolute', width: '100%', height: '100%' },
  blockBigOverlay: { position: 'absolute', width: '100%', height: '100%', backgroundColor: 'rgba(0,0,0,0.35)' },
  blockBigContent: { position: 'absolute', bottom: 20, left: 20, right: 20 },
  blockBigTitle: { fontSize: 24, fontWeight: '900', color: '#FFF' },
  blockBigSub: { fontSize: 13, color: 'rgba(255,255,255,0.7)', marginTop: 4 },

  blockRow: { flexDirection: 'row', gap: 10 },
  blockHalf: { flex: 1, borderRadius: 16, overflow: 'hidden', height: 140, position: 'relative' },
  blockHalfImg: { position: 'absolute', width: '100%', height: '100%' },
  blockHalfOverlay: { position: 'absolute', width: '100%', height: '100%', backgroundColor: 'rgba(0,0,0,0.35)' },
  blockHalfContent: { position: 'absolute', bottom: 14, left: 14, right: 14 },
  blockHalfTitle: { fontSize: 18, fontWeight: '800', color: '#FFF' },
  blockHalfSub: { fontSize: 11, color: 'rgba(255,255,255,0.65)', marginTop: 2 },

  center: { paddingTop: 100, alignItems: 'center' },
});
