import React, { useState, useEffect, useCallback, useMemo } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, FlatList,
  RefreshControl, Dimensions, ScrollView,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuthStore } from '../../src/store/authStore';
import api, { API_URL } from '../../src/api/client';
import { rankFeed, RecommendationItem } from '../../src/recommendation';
import { requireVerifiedPhone } from '../../src/utils/phoneVerification';
import MediaPreview from '../../src/components/MediaPreview';

const { width: SW } = Dimensions.get('window');

const FILTERS = [
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

const WORLD_BOARD_SECTIONS = [
  { label: 'For You', kind: 'ranked' },
  { label: 'Trending', kind: 'trending' },
  { label: 'Latest', kind: 'latest' },
  { label: 'Fresh', kind: 'fresh' },
  { label: 'Explore More', kind: 'explore' },
] as const;

function engagementScore(post: any): number {
  return Number(post.likes_count || 0) * 4
    + Number(post.comments_count || 0) * 6
    + Number(post.shares_count || 0) * 7
    + Number(post.saves_count || 0) * 5
    + Number(post.views_count || 0);
}

function uniquePosts(posts: any[]): any[] {
  const seen = new Set<string>();
  return posts.filter((post) => {
    const id = String(post.id || '');
    if (!id || seen.has(id)) return false;
    seen.add(id);
    return true;
  });
}

function parsePostImages(value: unknown): string[] {
  if (Array.isArray(value)) return value.map((item) => String(item)).filter(Boolean);
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      if (Array.isArray(parsed)) return parsed.map((item) => String(item)).filter(Boolean);
    } catch {}
    return value ? [value] : [];
  }
  return [];
}

function getPrimaryMediaUri(post: any): string {
  const candidates = [
    typeof post?.image === 'string' ? post.image : '',
    ...parsePostImages(post?.images),
  ];
  return candidates.find((uri) => (
    uri.startsWith('http')
    || uri.startsWith('data:')
    || uri.startsWith('cfstream:')
  )) || '';
}

function hasBoardContent(post: any): boolean {
  return !!getPrimaryMediaUri(post) || String(post?.content || '').trim().length > 0;
}

export default function HomeScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();
  const [filter, setFilter] = useState('world');
  const [posts, setPosts] = useState<any[]>([]);
  const [refreshing, setRefreshing] = useState(false);
  const userLat = 40.7128;
  const userLng = -74.006;

  const rankPosts = useCallback((rawPosts: any[]) => {
    const interestTokens = String(user?.interests || '')
      .split(',')
      .map((s: string) => s.trim().toLowerCase())
      .filter(Boolean);

    const items: RecommendationItem[] = rawPosts.map((p: any) => ({
      id: String(p.id),
      authorId: p.user_id ? String(p.user_id) : '',
      category: String(p.category || p.post_type || ''),
      content: String(p.content || ''),
      location: String(p.location || p.place_name || ''),
      createdAtMs: Number(Date.parse(p.created_at || '') || Date.now()),
      likes: Number(p.likes_count || 0),
      comments: Number(p.comments_count || 0),
      shares: Number(p.shares_count || 0),
      saves: Number(p.saves_count || 0),
      impressions: Number(p.views_count || 0),
      lat: p.place_lat !== undefined && p.place_lat !== null ? Number(p.place_lat) : undefined,
      lng: p.place_lng !== undefined && p.place_lng !== null ? Number(p.place_lng) : undefined,
      original: p,
    }));

    const ranked = rankFeed(
      items,
      {
        userId: user?.id,
        interests: interestTokens,
        nowMs: Date.now(),
        userLat,
        userLng,
      },
      { maxItems: items.length, lambda: 0.82, halfLifeHours: 40 }
    );

    return ranked.map((r) => r.original);
  }, [user?.id, user?.interests, userLat, userLng]);

  const loadPublicWorldBoard = useCallback(async () => {
    const response = await fetch(`${API_URL}/api/posts/world-board?limit=60`);
    if (!response.ok) return [];
    const data = await response.json();
    return Array.isArray(data) ? data : [];
  }, []);

  const loadData = useCallback(async () => {
    let raw: any[] = [];
    try {
      const r = await api.get('/posts/feed', { params: { limit: 60 } });
      raw = Array.isArray(r.data) ? r.data : [];
    } catch {
      try {
        raw = await loadPublicWorldBoard();
      } catch {}
    }

    if (raw.length === 0) {
      try {
        raw = await loadPublicWorldBoard();
      } catch {}
    }

    setPosts(rankPosts(raw));
  }, [loadPublicWorldBoard, rankPosts]);

  useEffect(() => { loadData(); }, [loadData]);

  const onRefresh = useCallback(async () => {
    setRefreshing(true); await loadData(); setRefreshing(false);
  }, [loadData]);

  const filtered = useMemo(() => {
    if (filter === 'world') return posts;
    const kw = CITY_KW[filter] || [];
    const f = posts.filter((p: any) => {
      const t = ((p.location || '') + ' ' + (p.content || '')).toLowerCase();
      return kw.some(k => t.includes(k));
    });
    return f.length > 0 ? f : [];
  }, [filter, posts]);

  const items = useMemo(() => filtered.filter(hasBoardContent), [filtered]);

  const G = 2;
  const TILE_SIZE = Math.floor((SW - G * 2) / 3); // 3 cols exactly

  const postSections = useMemo(() => {
    const sections: Record<string, any[]> = {};
    if (items.length === 0) return sections;

    const newest = [...items].sort((a, b) => Date.parse(b.created_at || '') - Date.parse(a.created_at || ''));
    const trending = [...items].sort((a, b) => {
      const recencyA = Math.max(0, 72 - ((Date.now() - Date.parse(a.created_at || '')) / 3600000));
      const recencyB = Math.max(0, 72 - ((Date.now() - Date.parse(b.created_at || '')) / 3600000));
      return (engagementScore(b) + recencyB) - (engagementScore(a) + recencyA);
    });
    const fresh = newest.filter((post) => Date.now() - Date.parse(post.created_at || '') < 1000 * 60 * 60 * 72);

    for (const section of WORLD_BOARD_SECTIONS) {
      let source = items;
      if ('kind' in section && section.kind === 'trending') source = trending;
      if ('kind' in section && section.kind === 'latest') source = newest;
      if ('kind' in section && section.kind === 'fresh') source = fresh.length > 0 ? fresh : newest;
      if ('kind' in section && section.kind === 'explore') source = [...items].reverse();

      const slice = uniquePosts(source).slice(0, 9);
      if (slice.length > 0) sections[section.label] = slice;
    }

    return sections;
  }, [items]);

  const openCreatePost = () => {
    if (!requireVerifiedPhone(user, router, 'create posts')) return;
    router.push('/create-post' as any);
  };

  return (
    <View style={s.root}>
      {/* STICKY HEADER — stays fixed at top */}
      <View style={[s.stickyHeader, { paddingTop: insets.top + 6 }]}>
        <View style={s.topRow}>
          <View style={s.headerR}>
            <TouchableOpacity style={s.hBtn} onPress={openCreatePost}>
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
            {/* World Board / Cities: ranked post sections */}
            {Object.keys(postSections).length > 0 && (
              <View>
                {Object.entries(postSections).map(([label, sectionPosts]) => (
                  <View key={label}>
                    <Text style={s.sectionLabel}>{label}</Text>
                    <View style={s.gallery}>
                      {sectionPosts.slice(0, 9).map((p: any) => (
                        <TouchableOpacity key={p.id} style={[s.gTile, { width: TILE_SIZE, height: TILE_SIZE }]} activeOpacity={0.95}
                          onPress={() => router.push(`/post/${p.id}` as any)}>
                          {getPrimaryMediaUri(p) ? (
                            <MediaPreview
                              uri={getPrimaryMediaUri(p)}
                              mediaTypes={p.media_types}
                              style={s.gImg}
                            />
                          ) : (
                            <View style={s.textTile}>
                              <Text style={s.textTileAuthor} numberOfLines={1}>@{p.user_username || 'flames'}</Text>
                              <Text style={s.textTileContent} numberOfLines={5}>{p.content}</Text>
                            </View>
                          )}
                        </TouchableOpacity>
                      ))}
                    </View>
                  </View>
                ))}
              </View>
            )}
            {items.length === 0 && (
              <View style={s.empty}>
                <Ionicons name="images-outline" size={40} color="#DDD" />
                <Text style={s.emptyTx}>No posts here yet</Text>
              </View>
            )}
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
  // 3-column gallery
  gallery: { flexDirection: 'row', flexWrap: 'wrap', gap: 2 },
  gTile: { overflow: 'hidden' },
  gImg: { width: '100%', height: '100%' },
  textTile: { flex: 1, backgroundColor: '#F7F4EE', padding: 10, justifyContent: 'space-between' },
  textTileAuthor: { fontSize: 11, fontWeight: '800', color: '#6F6A60' },
  textTileContent: { fontSize: 15, lineHeight: 19, fontWeight: '800', color: '#1A1A1A' },
  sectionLabel: { fontSize: 20, fontWeight: '900', color: '#1A1A1A', fontStyle: 'italic', paddingHorizontal: 12, paddingVertical: 10 },

  empty: { paddingTop: 100, alignItems: 'center' },
  emptyTx: { fontSize: 14, color: '#CCC', marginTop: 10 },
});
