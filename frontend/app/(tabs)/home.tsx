import React, { useState, useEffect, useCallback, useMemo } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, FlatList,
  RefreshControl, Dimensions, ScrollView, Image, Alert,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuthStore } from '../../src/store/authStore';
import api, { API_URL } from '../../src/api/client';
import { rankFeed, RecommendationItem } from '../../src/recommendation';
import { requireVerifiedPhone } from '../../src/utils/phoneVerification';
import MediaPreview from '../../src/components/MediaPreview';

const { width: SW, height: SH } = Dimensions.get('window');

const HOME_TABS = [
  { id: 'world', label: 'World Board' },
  { id: 'foryou', label: 'For You' },
] as const;

const WORLD_BOARD_SECTIONS = [
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

function postTitle(post: any): string {
  const content = String(post?.content || '').trim();
  if (content) return content;
  if (post?.place_name) return String(post.place_name);
  return 'New post';
}

function avatarInitial(post: any): string {
  const source = String(post?.user_full_name || post?.user_username || 'F');
  return source.trim().slice(0, 1).toUpperCase() || 'F';
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

  const filtered = useMemo(() => posts, [posts]);

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

  const followUser = async (post: any) => {
    if (!user) {
      router.push('/(auth)/login' as any);
      return;
    }
    if (!post?.user_id || post.user_id === user.id) return;

    try {
      await api.post(`/users/${post.user_id}/follow`);
    } catch (error: any) {
      Alert.alert('Follow failed', error?.response?.data?.detail || 'Could not follow this user.');
    }
  };

  const renderForYouCard = ({ item: p }: { item: any }) => {
    const mediaUri = getPrimaryMediaUri(p);
    const cardHeight = Math.max(520, SH - insets.top - 175);
    const creatorName = p.user_full_name || p.user_username || 'Flames creator';

    return (
      <TouchableOpacity
        style={[s.feedCard, { height: cardHeight }]}
        activeOpacity={0.96}
        onPress={() => router.push(`/post/${p.id}` as any)}
      >
        {mediaUri ? (
          <MediaPreview uri={mediaUri} mediaTypes={p.media_types} style={s.feedMedia} showVideoBadge={false} />
        ) : (
          <View style={s.feedTextBackdrop}>
            <Text style={s.feedTextBackdropContent}>{postTitle(p)}</Text>
          </View>
        )}
        <View style={s.feedScrim} />

        <View style={s.feedCopy}>
          <Text style={s.feedEyebrow} numberOfLines={1}>{String(p.location || p.place_name || 'For You').toUpperCase()}</Text>
          <Text style={s.feedTitle} numberOfLines={3}>{postTitle(p)}</Text>
          <TouchableOpacity style={s.feedCta} activeOpacity={0.86} onPress={() => router.push(`/post/${p.id}` as any)}>
            <Text style={s.feedCtaText}>Open post</Text>
          </TouchableOpacity>
        </View>

        <View style={s.feedRail}>
          <TouchableOpacity style={s.creatorButton} activeOpacity={0.88} onPress={() => router.push(`/profile/${p.user_id}` as any)}>
            {p.user_profile_image ? (
              <Image source={{ uri: p.user_profile_image }} style={s.creatorImage} />
            ) : (
              <View style={s.creatorFallback}>
                <Text style={s.creatorFallbackText}>{avatarInitial(p)}</Text>
              </View>
            )}
            {p.user_id !== user?.id ? (
              <TouchableOpacity style={s.followPlus} activeOpacity={0.9} onPress={() => followUser(p)}>
                <Ionicons name="add" size={16} color="#101010" />
              </TouchableOpacity>
            ) : null}
          </TouchableOpacity>
          <TouchableOpacity style={s.roundAction} activeOpacity={0.86}>
            <Ionicons name="heart-outline" size={31} color="#101010" />
          </TouchableOpacity>
          <TouchableOpacity style={s.roundAction} activeOpacity={0.86}>
            <Ionicons name="chatbubble-outline" size={28} color="#101010" />
          </TouchableOpacity>
          <TouchableOpacity style={s.roundAction} activeOpacity={0.86}>
            <Ionicons name="paper-plane-outline" size={27} color="#101010" />
          </TouchableOpacity>
        </View>

        <View style={s.creatorPill}>
          {p.user_profile_image ? (
            <Image source={{ uri: p.user_profile_image }} style={s.creatorPillImage} />
          ) : (
            <View style={s.creatorPillFallback}>
              <Text style={s.creatorPillFallbackText}>{avatarInitial(p)}</Text>
            </View>
          )}
          <View style={s.creatorPillText}>
            <Text style={s.creatorPillName} numberOfLines={1}>{creatorName}</Text>
            <Text style={s.creatorPillHandle} numberOfLines={1}>@{p.user_username || 'flames'}</Text>
          </View>
          {p.user_id !== user?.id ? (
            <TouchableOpacity style={s.creatorPillFollow} activeOpacity={0.86} onPress={() => followUser(p)}>
              <Text style={s.creatorPillFollowText}>Follow</Text>
            </TouchableOpacity>
          ) : null}
        </View>
      </TouchableOpacity>
    );
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
        {/* Page tabs */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.filters}>
          {HOME_TABS.map(f => (
            <TouchableOpacity key={f.id} style={[s.chip, filter === f.id && s.chipOn]} onPress={() => setFilter(f.id)}>
              <Text style={[s.chipTx, filter === f.id && s.chipTxOn]}>{f.label}</Text>
            </TouchableOpacity>
          ))}
        </ScrollView>
      </View>

      {filter === 'foryou' ? (
        <FlatList
          data={items}
          keyExtractor={(p) => `foryou-${p.id}`}
          renderItem={renderForYouCard}
          showsVerticalScrollIndicator={false}
          snapToAlignment="start"
          decelerationRate="fast"
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
          contentContainerStyle={items.length === 0 ? s.emptyFeedContent : { paddingBottom: 92 }}
          ListEmptyComponent={(
            <View style={s.empty}>
              <Ionicons name="sparkles-outline" size={40} color="#DDD" />
              <Text style={s.emptyTx}>No posts here yet</Text>
            </View>
          )}
        />
      ) : (
        <FlatList
          data={[1]}
          keyExtractor={() => 'grid'}
          showsVerticalScrollIndicator={false}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
          contentContainerStyle={{ paddingBottom: 100 }}
          renderItem={() => (
            <>
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
      )}
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

  feedCard: { width: SW, backgroundColor: '#111', overflow: 'hidden', position: 'relative' },
  feedMedia: { ...StyleSheet.absoluteFillObject, width: '100%', height: '100%' },
  feedTextBackdrop: { ...StyleSheet.absoluteFillObject, backgroundColor: '#1D1D1B', justifyContent: 'center', padding: 30 },
  feedTextBackdropContent: { color: '#FFF', fontSize: 38, lineHeight: 42, fontWeight: '900' },
  feedScrim: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.22)' },
  feedCopy: { position: 'absolute', top: 42, left: 22, right: 100 },
  feedEyebrow: { color: '#FFF', fontSize: 23, fontWeight: '500', letterSpacing: 0 },
  feedTitle: { marginTop: 10, color: '#FFF', fontSize: 40, lineHeight: 45, fontWeight: '900', letterSpacing: 0 },
  feedCta: { marginTop: 22, alignSelf: 'flex-start', minHeight: 49, paddingHorizontal: 23, borderRadius: 26, borderWidth: 2, borderColor: '#101010', backgroundColor: '#DFFF32', justifyContent: 'center' },
  feedCtaText: { color: '#111', fontSize: 22, fontWeight: '500' },
  feedRail: { position: 'absolute', top: 36, right: 18, gap: 17, alignItems: 'center' },
  creatorButton: { width: 64, height: 64, borderRadius: 32, backgroundColor: '#FFF', alignItems: 'center', justifyContent: 'center', borderWidth: 3, borderColor: '#111' },
  creatorImage: { width: 54, height: 54, borderRadius: 27 },
  creatorFallback: { width: 54, height: 54, borderRadius: 27, backgroundColor: '#F5F2EA', alignItems: 'center', justifyContent: 'center' },
  creatorFallbackText: { color: '#111', fontSize: 25, fontWeight: '900' },
  followPlus: { position: 'absolute', bottom: -7, right: -4, width: 26, height: 26, borderRadius: 13, backgroundColor: '#DFFF32', borderWidth: 2, borderColor: '#111', alignItems: 'center', justifyContent: 'center' },
  roundAction: { width: 61, height: 61, borderRadius: 31, backgroundColor: 'rgba(255,255,255,0.94)', alignItems: 'center', justifyContent: 'center' },
  creatorPill: { position: 'absolute', left: 22, right: 22, bottom: 28, minHeight: 75, borderRadius: 38, backgroundColor: 'rgba(255,255,255,0.94)', flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 13, paddingVertical: 10 },
  creatorPillImage: { width: 51, height: 51, borderRadius: 25.5 },
  creatorPillFallback: { width: 51, height: 51, borderRadius: 25.5, backgroundColor: '#DFFF32', alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: '#111' },
  creatorPillFallbackText: { color: '#111', fontSize: 20, fontWeight: '900' },
  creatorPillText: { flex: 1, minWidth: 0 },
  creatorPillName: { color: '#111', fontSize: 22, fontWeight: '900' },
  creatorPillHandle: { color: '#575757', fontSize: 13, fontWeight: '700', marginTop: 2 },
  creatorPillFollow: { height: 42, borderRadius: 22, paddingHorizontal: 18, backgroundColor: '#111', alignItems: 'center', justifyContent: 'center' },
  creatorPillFollowText: { color: '#FFF', fontSize: 14, fontWeight: '900' },
  emptyFeedContent: { flexGrow: 1, paddingBottom: 100 },
  empty: { paddingTop: 100, alignItems: 'center' },
  emptyTx: { fontSize: 14, color: '#CCC', marginTop: 10 },
});
