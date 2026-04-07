import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView,
  RefreshControl, Dimensions, ActivityIndicator, FlatList,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { formatDistanceToNow } from 'date-fns';
import { colors } from '../../../src/utils/theme';
import { useAuthStore } from '../../../src/store/authStore';
import { isCFStreamVideo, extractStreamUid, getStreamPlaybackInfo } from '../../../src/utils/mediaUpload';
import api from '../../../src/api/client';

const { width: SW } = Dimensions.get('window');
const GAP = 8;
const COL_W = (SW - GAP * 3) / 2;

// ── Context metadata for the scene header ──
type ContextMeta = {
  label: string;
  color: string;
  darkColor: string;
  icon: string;
};

const CONTEXT_META: Record<string, ContextMeta> = {
  near:   { label: 'Near You',  color: '#1B4332', darkColor: '#0D2920', icon: 'location' },
  global: { label: 'Global',    color: '#0C2340', darkColor: '#06111F', icon: 'globe-outline' },
  nyc:    { label: 'NYC',       color: '#1A1A1A', darkColor: '#0D0D0D', icon: 'business-outline' },
  miami:  { label: 'Miami',     color: '#0E7490', darkColor: '#064E63', icon: 'sunny-outline' },
  tokyo:  { label: 'Tokyo',     color: '#B91C1C', darkColor: '#7F1D1D', icon: 'train-outline' },
  london: { label: 'London',    color: '#1E3A5F', darkColor: '#0F1D30', icon: 'rainy-outline' },
  la:     { label: 'LA',        color: '#9A3412', darkColor: '#5C1D09', icon: 'film-outline' },
  paris:  { label: 'Paris',     color: '#1E3A5F', darkColor: '#0F1D30', icon: 'wine-outline' },
};

const CATEGORY_LABELS: Record<string, { title: string; icon: string }> = {
  'open-now':     { title: 'Open Now',       icon: 'time-outline' },
  'nearby-spots': { title: 'Nearby Spots',   icon: 'navigate-outline' },
  'active':       { title: 'People Out Now',  icon: 'people-outline' },
  'food':         { title: 'Food',            icon: 'restaurant-outline' },
  'hidden':       { title: 'Hidden Gems',     icon: 'diamond-outline' },
  'culture':      { title: 'Culture',         icon: 'color-palette-outline' },
  'fashion':      { title: 'Fashion',         icon: 'shirt-outline' },
  'travel':       { title: 'Travel',          icon: 'airplane-outline' },
  'nightlife':    { title: 'Nightlife',       icon: 'moon-outline' },
  'places':       { title: 'Places to Go',    icon: 'location-outline' },
  'street':       { title: 'Street Culture',  icon: 'musical-notes-outline' },
  'beach':        { title: 'Beach Life',      icon: 'water-outline' },
  'art':          { title: 'Art & Culture',   icon: 'color-palette-outline' },
  'cafes':        { title: 'Cafés',           icon: 'cafe-outline' },
  'all':          { title: 'All',             icon: 'apps-outline' },
};

// ── Post Card Component ──
function PostCard({ post, onPress, wide }: { post: any; onPress: () => void; wide?: boolean }) {
  const w = wide ? SW - GAP * 2 : COL_W;
  const h = wide ? SW * 0.55 : COL_W * 1.3;
  const imageUri = post.image || post.images?.[0];
  const isVideo = isCFStreamVideo(imageUri || '') || post.media_types?.includes('video');
  
  // For video posts, resolve thumbnail
  const [thumbnailUri, setThumbnailUri] = React.useState<string | null>(null);
  
  React.useEffect(() => {
    if (isVideo && imageUri && isCFStreamVideo(imageUri)) {
      const uid = extractStreamUid(imageUri);
      if (uid) {
        getStreamPlaybackInfo(uid).then((info) => {
          if (info?.thumbnail) setThumbnailUri(info.thumbnail);
        }).catch(() => {});
      }
    }
  }, [imageUri, isVideo]);
  
  const displayImage = isVideo ? thumbnailUri : imageUri;
  const hasImage = displayImage && (displayImage.startsWith('http') || displayImage.startsWith('data:'));
  const authorName = post.user_full_name || post.user_username || 'User';

  return (
    <TouchableOpacity style={[pc.card, { width: w, height: h }]} activeOpacity={0.92} onPress={onPress}>
      {hasImage ? (
        <Image source={{ uri: displayImage }} style={pc.image} />
      ) : (
        <View style={[pc.image, { backgroundColor: '#1A1A1A' }]} />
      )}
      <View style={pc.overlay} />
      {/* Video play indicator */}
      {isVideo && (
        <View style={pc.videoIndicator}>
          <Ionicons name="play-circle" size={36} color="rgba(255,255,255,0.85)" />
        </View>
      )}
      <View style={pc.content}>
        <View style={pc.authorRow}>
          {post.user_profile_image ? (
            <Image source={{ uri: post.user_profile_image }} style={pc.avatar} />
          ) : (
            <View style={[pc.avatar, pc.avatarFallback]}>
              <Text style={pc.avatarInit}>{authorName[0]}</Text>
            </View>
          )}
          <Text style={pc.authorName} numberOfLines={1}>{authorName}</Text>
        </View>
        {post.content ? (
          <Text style={pc.caption} numberOfLines={wide ? 3 : 2}>{post.content}</Text>
        ) : null}
        <View style={pc.metaRow}>
          {post.location ? (
            <View style={pc.locWrap}>
              <Ionicons name="location-outline" size={10} color="rgba(255,255,255,0.55)" />
              <Text style={pc.locText} numberOfLines={1}>{post.location}</Text>
            </View>
          ) : null}
          <View style={pc.statRow}>
            <Ionicons name="heart" size={10} color="rgba(255,255,255,0.5)" />
            <Text style={pc.statText}>{post.likes_count || 0}</Text>
          </View>
        </View>
      </View>
    </TouchableOpacity>
  );
}

const pc = StyleSheet.create({
  card: { borderRadius: 18, overflow: 'hidden', position: 'relative', marginBottom: GAP },
  image: { position: 'absolute', width: '100%', height: '100%' },
  overlay: {
    position: 'absolute', width: '100%', height: '100%',
    backgroundColor: 'rgba(0,0,0,0.35)',
  },
  videoIndicator: {
    position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
    justifyContent: 'center', alignItems: 'center', zIndex: 2,
  },
  content: { position: 'absolute', bottom: 12, left: 12, right: 12 },
  authorRow: { flexDirection: 'row', alignItems: 'center', marginBottom: 6 },
  avatar: { width: 22, height: 22, borderRadius: 11, marginRight: 6, borderWidth: 1, borderColor: 'rgba(255,255,255,0.3)' },
  avatarFallback: { backgroundColor: 'rgba(255,255,255,0.15)', justifyContent: 'center', alignItems: 'center' },
  avatarInit: { fontSize: 10, fontWeight: '700', color: '#FFF' },
  authorName: { fontSize: 12, fontWeight: '700', color: '#FFF', flex: 1 },
  caption: { fontSize: 13, color: 'rgba(255,255,255,0.85)', lineHeight: 18, marginBottom: 6 },
  metaRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  locWrap: { flexDirection: 'row', alignItems: 'center', gap: 3, flex: 1 },
  locText: { fontSize: 10, color: 'rgba(255,255,255,0.5)' },
  statRow: { flexDirection: 'row', alignItems: 'center', gap: 3 },
  statText: { fontSize: 10, color: 'rgba(255,255,255,0.5)' },
});


// ── Scene Screen ──
export default function SceneScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();
  const { context, category } = useLocalSearchParams<{ context: string; category: string }>();

  const [posts, setPosts] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);

  const ctxMeta = CONTEXT_META[context || 'global'] || CONTEXT_META.global;
  const catMeta = CATEGORY_LABELS[category || 'all'] || { title: category || 'Scene', icon: 'apps-outline' };

  useEffect(() => {
    loadPosts();
  }, [context, category]);

  const loadPosts = async () => {
    try {
      setIsLoading(true);
      const res = await api.get('/posts/feed', { params: { limit: 40 } });
      const allPosts = Array.isArray(res.data) ? res.data : [];

      // Filter posts by context/category heuristics
      let filtered = allPosts;

      // Location-based filtering for city contexts
      if (context && context !== 'global' && context !== 'near') {
        const cityNames: Record<string, string[]> = {
          nyc: ['new york', 'nyc', 'brooklyn', 'manhattan', 'queens', 'bronx', 'harlem'],
          miami: ['miami', 'south beach', 'wynwood', 'brickell'],
          tokyo: ['tokyo', 'shibuya', 'shinjuku', 'akihabara', 'harajuku'],
          london: ['london', 'soho', 'shoreditch', 'camden', 'brixton'],
          la: ['los angeles', 'la', 'hollywood', 'venice', 'santa monica'],
          paris: ['paris', 'le marais', 'montmartre', 'pigalle'],
        };
        const cityKeywords = cityNames[context] || [];
        if (cityKeywords.length > 0) {
          const cityFiltered = allPosts.filter((p: any) => {
            const loc = (p.location || '').toLowerCase();
            const content = (p.content || '').toLowerCase();
            return cityKeywords.some(k => loc.includes(k) || content.includes(k));
          });
          // If we found city-specific posts, use them; otherwise show all (better UX)
          if (cityFiltered.length > 0) filtered = cityFiltered;
        }
      }

      // Category-based filtering  
      if (category && category !== 'all') {
        const catKeywords: Record<string, string[]> = {
          food: ['food', 'restaurant', 'eat', 'pizza', 'ramen', 'cafe', 'coffee', 'brunch', 'dinner', 'lunch', 'cook'],
          nightlife: ['night', 'bar', 'club', 'party', 'drinks', 'cocktail', 'dj', 'dance'],
          culture: ['art', 'museum', 'gallery', 'culture', 'history', 'exhibit', 'theater', 'theatre'],
          fashion: ['fashion', 'style', 'outfit', 'wear', 'designer', 'brand', 'clothing'],
          hidden: ['hidden', 'secret', 'gem', 'underrated', 'local', 'discover'],
          street: ['street', 'graffiti', 'mural', 'music', 'busker', 'skateboard'],
          travel: ['travel', 'trip', 'destination', 'explore', 'adventure', 'journey'],
          beach: ['beach', 'ocean', 'sea', 'surf', 'sand', 'wave', 'coast'],
          cafes: ['cafe', 'coffee', 'espresso', 'latte', 'tea', 'pastry'],
          places: ['place', 'spot', 'location', 'visit', 'recommend', 'must'],
          active: ['check', 'here', 'now', 'live', 'currently'],
          'open-now': ['open', 'available', 'now', 'today'],
          'nearby-spots': ['near', 'close', 'around', 'nearby'],
        };
        const keywords = catKeywords[category] || [];
        if (keywords.length > 0) {
          const catFiltered = filtered.filter((p: any) => {
            const content = (p.content || '').toLowerCase();
            const loc = (p.location || '').toLowerCase();
            const pType = (p.post_type || '').toLowerCase();
            return keywords.some(k => content.includes(k) || loc.includes(k) || pType.includes(k));
          });
          if (catFiltered.length >= 3) filtered = catFiltered;
        }
      }

      setPosts(filtered);
    } catch (err) {
      console.log('Scene load error:', err);
      setPosts([]);
    } finally {
      setIsLoading(false);
    }
  };

  const onRefresh = useCallback(async () => {
    setIsRefreshing(true);
    await loadPosts();
    setIsRefreshing(false);
  }, [context, category]);

  const renderMasonryGrid = () => {
    if (posts.length === 0) {
      return (
        <View style={s.emptyState}>
          <View style={s.emptyIcon}>
            <Ionicons name={catMeta.icon as any} size={32} color="rgba(255,255,255,0.3)" />
          </View>
          <Text style={s.emptyTitle}>No posts yet</Text>
          <Text style={s.emptySub}>Be the first to share something in {catMeta.title}</Text>
          <TouchableOpacity style={s.emptyBtn} onPress={() => router.push('/create-post' as any)}>
            <Ionicons name="camera-outline" size={16} color="#FFF" />
            <Text style={s.emptyBtnText}>Create Post</Text>
          </TouchableOpacity>
        </View>
      );
    }

    // Masonry layout: alternate between wide and 2-col
    const items: React.ReactNode[] = [];
    let idx = 0;

    // First post is always wide/featured
    if (posts.length > 0) {
      items.push(
        <PostCard
          key={posts[0].id}
          post={posts[0]}
          wide
          onPress={() => router.push(`/post/${posts[0].id}` as any)}
        />
      );
      idx = 1;
    }

    // Remaining posts in 2-column pairs
    while (idx < posts.length) {
      const left = posts[idx];
      const right = posts[idx + 1];
      items.push(
        <View key={`row-${idx}`} style={s.twoColRow}>
          <PostCard
            post={left}
            onPress={() => router.push(`/post/${left.id}` as any)}
          />
          {right ? (
            <PostCard
              post={right}
              onPress={() => router.push(`/post/${right.id}` as any)}
            />
          ) : <View style={{ width: COL_W }} />}
        </View>
      );
      idx += 2;
    }

    return items;
  };

  return (
    <View style={s.container}>
      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} tintColor="#FFF" />
        }
        contentContainerStyle={{ paddingBottom: 40 }}
      >
        {/* ── Immersive Header ── */}
        <View style={[s.header, { backgroundColor: ctxMeta.color, paddingTop: insets.top }]}>
          <View style={s.headerOverlay} />
          
          {/* Nav bar */}
          <View style={s.navBar}>
            <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
              <Ionicons name="arrow-back" size={20} color="#FFF" />
            </TouchableOpacity>
            <TouchableOpacity style={s.shareBtn} onPress={() => router.push('/create-post' as any)}>
              <Ionicons name="add" size={20} color="#FFF" />
            </TouchableOpacity>
          </View>

          {/* Title area */}
          <View style={s.headerContent}>
            <View style={s.headerBadge}>
              <Ionicons name={ctxMeta.icon as any} size={12} color="rgba(255,255,255,0.7)" />
              <Text style={s.headerBadgeText}>{ctxMeta.label}</Text>
            </View>
            <Text style={s.headerTitle}>{catMeta.title}</Text>
            <Text style={s.headerSub}>
              {posts.length > 0
                ? `${posts.length} post${posts.length !== 1 ? 's' : ''} to explore`
                : 'Curated content'}
            </Text>
          </View>
        </View>

        {/* ── Content Grid ── */}
        <View style={s.gridWrap}>
          {isLoading ? (
            <View style={s.loadingWrap}>
              <ActivityIndicator size="large" color={ctxMeta.color} />
              <Text style={s.loadingText}>Loading scene...</Text>
            </View>
          ) : (
            renderMasonryGrid()
          )}
        </View>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#F5F2EC' },

  // Header
  header: {
    paddingBottom: 28,
    position: 'relative',
    overflow: 'hidden',
  },
  headerOverlay: {
    position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.1)',
  },
  navBar: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  backBtn: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.15)',
    justifyContent: 'center', alignItems: 'center',
  },
  shareBtn: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.15)',
    justifyContent: 'center', alignItems: 'center',
  },
  headerContent: { paddingHorizontal: 20, paddingTop: 8 },
  headerBadge: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    backgroundColor: 'rgba(255,255,255,0.12)',
    paddingHorizontal: 10, paddingVertical: 5, borderRadius: 12,
    alignSelf: 'flex-start', marginBottom: 12,
  },
  headerBadgeText: { fontSize: 11, fontWeight: '700', color: 'rgba(255,255,255,0.7)', letterSpacing: 0.5 },
  headerTitle: { fontSize: 30, fontWeight: '800', color: '#FFFFFF', letterSpacing: -0.5, marginBottom: 4 },
  headerSub: { fontSize: 14, color: 'rgba(255,255,255,0.55)', fontWeight: '400' },

  // Grid
  gridWrap: { padding: GAP, marginTop: -12, borderTopLeftRadius: 16, borderTopRightRadius: 16, backgroundColor: '#F5F2EC' },
  twoColRow: { flexDirection: 'row', gap: GAP },

  // Loading
  loadingWrap: { alignItems: 'center', paddingVertical: 60 },
  loadingText: { fontSize: 14, color: '#999', marginTop: 12 },

  // Empty
  emptyState: { alignItems: 'center', paddingVertical: 60, paddingHorizontal: 40 },
  emptyIcon: {
    width: 72, height: 72, borderRadius: 36,
    backgroundColor: 'rgba(26,26,26,0.06)',
    justifyContent: 'center', alignItems: 'center', marginBottom: 16,
  },
  emptyTitle: { fontSize: 18, fontWeight: '700', color: '#1A1A1A', marginBottom: 6 },
  emptySub: { fontSize: 14, color: '#999', textAlign: 'center', lineHeight: 20, marginBottom: 20 },
  emptyBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    backgroundColor: '#1A1A1A', paddingHorizontal: 20, paddingVertical: 12,
    borderRadius: 24,
  },
  emptyBtnText: { fontSize: 14, fontWeight: '700', color: '#FFF' },
});
