import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView,
  RefreshControl, Dimensions, ActivityIndicator, TextInput, Modal,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import api from '../../src/api/client';

const { width: SW } = Dimensions.get('window');

const CITY_TABS = [
  { id: 'all', label: 'For You' },
  { id: 'nyc', label: 'New York' },
  { id: 'miami', label: 'Miami' },
  { id: 'la', label: 'LA' },
  { id: 'london', label: 'London' },
  { id: 'tokyo', label: 'Tokyo' },
  { id: 'paris', label: 'Paris' },
];

const CITY_KEYWORDS: Record<string, string[]> = {
  nyc: ['new york', 'nyc', 'brooklyn', 'manhattan', 'queens'],
  miami: ['miami', 'south beach', 'wynwood', 'brickell'],
  la: ['los angeles', 'la', 'hollywood', 'venice', 'santa monica'],
  london: ['london', 'soho', 'shoreditch', 'camden'],
  tokyo: ['tokyo', 'shibuya', 'shinjuku', 'harajuku'],
  paris: ['paris', 'montmartre', 'le marais'],
};

export default function DiscoverScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const [tab, setTab] = useState('all');
  const [posts, setPosts] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [showMenu, setShowMenu] = useState(false);

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

  // Filter by city tab
  const filtered = tab === 'all' ? posts : (() => {
    const kw = CITY_KEYWORDS[tab] || [];
    const cityPosts = posts.filter((p: any) => {
      const t = ((p.location || '') + ' ' + (p.content || '')).toLowerCase();
      return kw.some(k => t.includes(k));
    });
    return cityPosts.length > 0 ? cityPosts : posts; // fallback to all if no city matches
  })();

  // Posts with images
  const imgPosts = filtered.filter((p: any) => {
    const img = p.image || (p.images && p.images[0]);
    return img && typeof img === 'string' && img.startsWith('http');
  });

  // Featured post (first)
  const featured = imgPosts[0];
  // Rest for horizontal rows & smaller cards
  const rest = imgPosts.slice(1);
  const row1 = rest.slice(0, 4);
  const row2 = rest.slice(4, 8);
  const remaining = rest.slice(8);

  const cityLabel = CITY_TABS.find(c => c.id === tab)?.label || 'For You';

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
        <TouchableOpacity style={s.searchBtn}><Ionicons name="search" size={18} color="#1A1A1A" /></TouchableOpacity>
      </View>

      {/* Menu Modal */}
      <Modal visible={showMenu} transparent animationType="fade" onRequestClose={() => setShowMenu(false)}>
        <TouchableOpacity style={s.menuOverlay} activeOpacity={1} onPress={() => setShowMenu(false)}>
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
            {/* Featured Card */}
            {featured && (
              <TouchableOpacity style={s.featured} activeOpacity={0.95} onPress={() => router.push(`/post/${featured.id}` as any)}>
                <Text style={s.featTitle} numberOfLines={3}>
                  {featured.content || `Discover ${cityLabel}`}
                </Text>
                <Image source={{ uri: featured.image || featured.images?.[0] }} style={s.featImg} resizeMode="cover" />
              </TouchableOpacity>
            )}

            {/* Horizontal scroll row 1 */}
            {row1.length > 0 && (
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.hRow}>
                {row1.map((p: any) => {
                  const img = p.image || p.images?.[0];
                  return (
                    <TouchableOpacity key={p.id} style={s.hCard} activeOpacity={0.95} onPress={() => router.push(`/post/${p.id}` as any)}>
                      <Image source={{ uri: img }} style={s.hCardImg} resizeMode="cover" />
                      <Text style={s.hCardTx} numberOfLines={2}>{p.content || ''}</Text>
                    </TouchableOpacity>
                  );
                })}
              </ScrollView>
            )}

            {/* Search Bar */}
            <View style={s.searchWrap}>
              <View style={s.searchBar}>
                <Ionicons name="search" size={18} color="#999" />
                <Text style={s.searchPlaceholder}>What are you looking for?</Text>
              </View>
            </View>

            {/* Full-width cards */}
            {row2.map((p: any) => {
              const img = p.image || p.images?.[0];
              return (
                <TouchableOpacity key={p.id} style={s.fullCard} activeOpacity={0.95} onPress={() => router.push(`/post/${p.id}` as any)}>
                  <Image source={{ uri: img }} style={s.fullCardImg} resizeMode="cover" />
                  <Text style={s.fullCardTx} numberOfLines={2}>{p.content || ''}</Text>
                  <View style={s.fullCardMeta}>
                    {p.user_profile_image ? (
                      <Image source={{ uri: p.user_profile_image }} style={s.metaAv} />
                    ) : null}
                    <Text style={s.metaName}>{p.user_full_name || ''}</Text>
                  </View>
                </TouchableOpacity>
              );
            })}

            {/* Horizontal scroll row 2 */}
            {remaining.length > 0 && (
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.hRow}>
                {remaining.map((p: any) => {
                  const img = p.image || p.images?.[0];
                  return (
                    <TouchableOpacity key={p.id} style={s.hCard} activeOpacity={0.95} onPress={() => router.push(`/post/${p.id}` as any)}>
                      <Image source={{ uri: img }} style={s.hCardImg} resizeMode="cover" />
                      <Text style={s.hCardTx} numberOfLines={2}>{p.content || ''}</Text>
                    </TouchableOpacity>
                  );
                })}
              </ScrollView>
            )}
          </>
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#FFF' },
  header: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingBottom: 12, gap: 12 },
  tabs: { gap: 20, alignItems: 'center' },
  tabTx: { fontSize: 13, fontWeight: '600', color: '#BBB', letterSpacing: 0.5 },
  tabTxOn: { color: '#1A1A1A', fontWeight: '800', textDecorationLine: 'underline' },
  searchBtn: { width: 38, height: 38, borderRadius: 19, backgroundColor: '#F0F0F0', justifyContent: 'center', alignItems: 'center' },

  menuOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.3)', justifyContent: 'flex-start' },
  menuSheet: { backgroundColor: '#FFF', marginTop: 100, marginHorizontal: 20, borderRadius: 16, paddingVertical: 8, shadowColor: '#000', shadowOffset: { width: 0, height: 4 }, shadowOpacity: 0.15, shadowRadius: 12, elevation: 8 },
  menuItem: { flexDirection: 'row', alignItems: 'center', gap: 14, paddingHorizontal: 20, paddingVertical: 16, borderBottomWidth: 0.5, borderBottomColor: '#F0F0F0' },
  menuItemTx: { fontSize: 16, fontWeight: '600', color: '#1A1A1A', flex: 1 },

  featured: { paddingHorizontal: 16, marginBottom: 16 },
  featTitle: { fontSize: 28, fontWeight: '900', color: '#1A1A1A', letterSpacing: -0.5, lineHeight: 34, marginBottom: 16 },
  featImg: { width: '100%', height: SW * 0.55, borderRadius: 12 },

  hRow: { paddingLeft: 16, gap: 10, paddingVertical: 8 },
  hCard: { width: SW * 0.55, borderRadius: 12, overflow: 'hidden' },
  hCardImg: { width: '100%', height: SW * 0.4, borderRadius: 12 },
  hCardTx: { fontSize: 13, fontWeight: '600', color: '#1A1A1A', marginTop: 8, paddingRight: 8 },

  searchWrap: { paddingHorizontal: 16, paddingVertical: 12 },
  searchBar: { flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: '#F5F5F5', borderRadius: 24, paddingHorizontal: 16, paddingVertical: 12 },
  searchPlaceholder: { fontSize: 14, color: '#AAA' },

  fullCard: { paddingHorizontal: 16, marginBottom: 20 },
  fullCardImg: { width: '100%', height: SW * 0.5, borderRadius: 12 },
  fullCardTx: { fontSize: 16, fontWeight: '700', color: '#1A1A1A', marginTop: 10, lineHeight: 22 },
  fullCardMeta: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 6 },
  metaAv: { width: 20, height: 20, borderRadius: 10 },
  metaName: { fontSize: 12, color: '#999' },

  center: { paddingTop: 100, alignItems: 'center' },
});
