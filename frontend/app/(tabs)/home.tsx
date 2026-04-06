import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView, RefreshControl,
  ActivityIndicator, Dimensions, TextInput, Alert, FlatList, Platform,
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import * as Location from 'expo-location';
import { Video, ResizeMode } from 'expo-av';
import { colors } from '../../src/utils/theme';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';
import { uploadImage } from '../../src/utils/mediaUpload';

const { width: SW } = Dimensions.get('window');
const COL_GAP = 3;
const NUM_COLS = 2;
const COL_W = (SW - COL_GAP * 3) / NUM_COLS;

// ─── Category Tabs ─────────────────────────────────────────────
const CATEGORIES = ['All', 'Fashion', 'Food', 'Culture', 'Street', 'Nightlife'];

// ─── Location Presets ──────────────────────────────────────────
const LOCATIONS = [
  { id: 'global', label: 'Global', icon: 'globe-outline' },
  { id: 'near', label: 'Near You', icon: 'location-outline' },
  { id: 'nyc', label: 'NYC', icon: 'business-outline' },
  { id: 'miami', label: 'Miami', icon: 'sunny-outline' },
  { id: 'la', label: 'LA', icon: 'film-outline' },
  { id: 'london', label: 'London', icon: 'umbrella-outline' },
];

// ─── Masonry Item Heights (visual variation) ───────────────────
const HEIGHTS = [COL_W * 1.0, COL_W * 1.25, COL_W * 1.5, COL_W * 1.1, COL_W * 1.35];
const getItemHeight = (idx: number) => HEIGHTS[idx % HEIGHTS.length];

// ═══════════════════════════════════════════════════════════════════
// MASONRY CARD
// ═══════════════════════════════════════════════════════════════════
function MasonryCard({
  post, height, onPress, onLike, onSave, isLiked, isSaved,
}: {
  post: any; height: number; onPress: () => void;
  onLike: () => void; onSave: () => void; isLiked: boolean; isSaved: boolean;
}) {
  const isVideo = post.media_type === 'video' || (post.media_types && post.media_types[0] === 'video');
  const hasImage = post.image || (post.images && post.images.length > 0);
  const imageUri = post.image || (post.images && post.images[0]) || null;
  const isCheckIn = post.post_type === 'check_in';

  return (
    <TouchableOpacity
      style={[ms.card, { height }]}
      activeOpacity={0.92}
      onPress={onPress}
    >
      {/* Media */}
      {isVideo && imageUri ? (
        <Video
          source={{ uri: imageUri }}
          style={ms.cardMedia}
          resizeMode={ResizeMode.COVER}
          shouldPlay={false}
          isMuted
          isLooping
        />
      ) : hasImage ? (
        <Image source={{ uri: imageUri }} style={ms.cardMedia} />
      ) : (
        <View style={[ms.cardMedia, ms.textOnlyBg, { backgroundColor: post.background_color || colors.accentPrimary }]}>
          <Text style={ms.textOnlyContent} numberOfLines={5}>
            {post.content}
          </Text>
        </View>
      )}

      {/* Gradient overlay at bottom */}
      <View style={ms.gradient} />

      {/* Video badge */}
      {isVideo && (
        <View style={ms.videoBadge}>
          <Ionicons name="play" size={10} color="#FFF" />
        </View>
      )}

      {/* Check-in place tag */}
      {isCheckIn && post.place_name && (
        <View style={ms.placeBadge}>
          <Ionicons name="location" size={10} color="#FFF" />
          <Text style={ms.placeText} numberOfLines={1}>{post.place_name}</Text>
        </View>
      )}

      {/* Bottom info */}
      <View style={ms.cardBottom}>
        {hasImage && post.content ? (
          <Text style={ms.cardCaption} numberOfLines={2}>{post.content}</Text>
        ) : null}
        <View style={ms.cardActions}>
          <TouchableOpacity onPress={onLike} hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}>
            <Ionicons name={isLiked ? 'heart' : 'heart-outline'} size={18} color={isLiked ? '#EF4444' : 'rgba(255,255,255,0.9)'} />
          </TouchableOpacity>
          <TouchableOpacity onPress={onSave} hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}>
            <Ionicons name={isSaved ? 'bookmark' : 'bookmark-outline'} size={17} color={isSaved ? '#F59E0B' : 'rgba(255,255,255,0.9)'} />
          </TouchableOpacity>
        </View>
      </View>
    </TouchableOpacity>
  );
}

const ms = StyleSheet.create({
  card: { width: COL_W, borderRadius: 12, overflow: 'hidden', backgroundColor: colors.bgSubtle, marginBottom: COL_GAP },
  cardMedia: { width: '100%', height: '100%', backgroundColor: colors.bgSubtle },
  textOnlyBg: { justifyContent: 'center', alignItems: 'center', paddingHorizontal: 16 },
  textOnlyContent: { color: '#FFF', fontSize: 15, fontWeight: '700', textAlign: 'center', lineHeight: 22 },
  gradient: { position: 'absolute', bottom: 0, left: 0, right: 0, height: '40%', backgroundColor: 'transparent', 
    // Using a simple semi-transparent overlay since LinearGradient isn't available
  },
  videoBadge: { position: 'absolute', top: 8, right: 8, backgroundColor: 'rgba(0,0,0,0.5)', borderRadius: 10, width: 24, height: 24, justifyContent: 'center', alignItems: 'center' },
  placeBadge: { position: 'absolute', top: 8, left: 8, flexDirection: 'row', alignItems: 'center', gap: 3, backgroundColor: 'rgba(0,0,0,0.5)', paddingHorizontal: 8, paddingVertical: 4, borderRadius: 10, maxWidth: COL_W - 48 },
  placeText: { color: '#FFF', fontSize: 10, fontWeight: '600' },
  cardBottom: { position: 'absolute', bottom: 0, left: 0, right: 0, padding: 10, backgroundColor: 'rgba(0,0,0,0.25)' },
  cardCaption: { color: '#FFF', fontSize: 12, fontWeight: '500', lineHeight: 16, marginBottom: 6 },
  cardActions: { flexDirection: 'row', alignItems: 'center', gap: 12 },
});


// ═══════════════════════════════════════════════════════════════════
// HOME SCREEN
// ═══════════════════════════════════════════════════════════════════
export default function HomeScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();

  const [posts, setPosts] = useState<any[]>([]);
  const [statuses, setStatuses] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [activeCategory, setActiveCategory] = useState('All');
  const [activeLocation, setActiveLocation] = useState('global');
  const [tonightMode, setTonightMode] = useState(false);
  const [likedPosts, setLikedPosts] = useState<Set<string>>(new Set());
  const [savedPosts, setSavedPosts] = useState<Set<string>>(new Set());

  useEffect(() => { loadFeed(); loadStatuses(); }, [activeCategory, activeLocation]);

  const loadFeed = async () => {
    try {
      const params: any = {};
      if (activeCategory !== 'All') params.category = activeCategory.toLowerCase();
      if (activeLocation === 'near') params.nearby = true;
      if (activeLocation !== 'global' && activeLocation !== 'near') params.city = activeLocation;
      const response = await api.get('/posts/feed', { params });
      const feedPosts = Array.isArray(response.data) ? response.data : [];
      setPosts(feedPosts);
      // Track liked posts
      const liked = new Set<string>();
      feedPosts.forEach((p: any) => { if (p.user_liked) liked.add(p.id); });
      setLikedPosts(liked);
    } catch (error) {
      console.log('Error loading feed:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const loadStatuses = async () => {
    try {
      const response = await api.get('/statuses');
      setStatuses(Array.isArray(response.data) ? response.data : []);
    } catch (error) {
      console.log('Error loading statuses:', error);
    }
  };

  const onRefresh = useCallback(async () => {
    setIsRefreshing(true);
    await Promise.all([loadFeed(), loadStatuses()]);
    setIsRefreshing(false);
  }, [activeCategory, activeLocation]);

  const handleLike = async (postId: string) => {
    try {
      await api.post(`/posts/${postId}/like`);
      setLikedPosts(prev => {
        const next = new Set(prev);
        if (next.has(postId)) next.delete(postId); else next.add(postId);
        return next;
      });
    } catch {}
  };

  const handleSave = async (postId: string) => {
    try {
      if (savedPosts.has(postId)) {
        await api.delete(`/bookmarks/${postId}`);
        setSavedPosts(prev => { const n = new Set(prev); n.delete(postId); return n; });
      } else {
        await api.post('/bookmarks', { post_id: postId, collection: 'saved' });
        setSavedPosts(prev => new Set(prev).add(postId));
      }
    } catch {}
  };

  // ─── Drop a Moment ─────────────────────────────────────
  const dropMoment = async () => {
    try {
      const { status } = await ImagePicker.requestCameraPermissionsAsync();
      if (status !== 'granted') { Alert.alert('Permission needed', 'Camera access required'); return; }
      const result = await ImagePicker.launchCameraAsync({
        quality: 0.8, base64: true, allowsEditing: false,
      });
      if (!result.canceled && result.assets[0]) {
        const asset = result.assets[0];
        const imageData = asset.base64 ? `data:image/jpeg;base64,${asset.base64}` : asset.uri;
        // Upload to CF Images
        const cfUrl = await uploadImage(imageData);
        // Auto-detect location
        let locationText = '';
        try {
          const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Low });
          const geo = await Location.reverseGeocodeAsync({ latitude: loc.coords.latitude, longitude: loc.coords.longitude });
          if (geo[0]) locationText = geo[0].city || geo[0].district || '';
        } catch {}
        // Post immediately
        await api.post('/posts', {
          content: locationText ? `Moment in ${locationText}` : 'Dropped a moment',
          image: cfUrl,
          post_type: 'lifestyle',
        });
        Alert.alert('Moment dropped!', 'Your moment is now live.');
        loadFeed();
      }
    } catch (error: any) {
      Alert.alert('Error', 'Could not drop moment');
    }
  };

  // ─── Build 2-column masonry ────────────────────────────
  const buildMasonry = () => {
    const left: { post: any; h: number }[] = [];
    const right: { post: any; h: number }[] = [];
    let leftH = 0, rightH = 0;

    posts.forEach((post, idx) => {
      const h = getItemHeight(idx);
      if (leftH <= rightH) {
        left.push({ post, h });
        leftH += h + COL_GAP;
      } else {
        right.push({ post, h });
        rightH += h + COL_GAP;
      }
    });
    return { left, right };
  };

  const { left, right } = buildMasonry();

  const greeting = () => {
    const h = new Date().getHours();
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  };

  return (
    <View style={s.container}>
      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} tintColor={colors.accentPrimary} />}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {/* ── Header ── */}
        <View style={[s.header, { paddingTop: insets.top + 8 }]}>
          <View>
            <Text style={s.logo}>Flames-Up</Text>
            <Text style={s.greeting}>{greeting()}, {user?.full_name?.split(' ')[0] || 'there'}</Text>
          </View>
          <View style={s.headerRight}>
            <TouchableOpacity
              style={[s.tonightBtn, tonightMode && s.tonightBtnActive]}
              onPress={() => setTonightMode(!tonightMode)}
            >
              <Ionicons name="moon" size={16} color={tonightMode ? '#FFF' : colors.textPrimary} />
              <Text style={[s.tonightText, tonightMode && { color: '#FFF' }]}>Tonight</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.iconBtn} onPress={() => router.push('/notifications' as any)}>
              <Ionicons name="notifications-outline" size={22} color={colors.textPrimary} />
            </TouchableOpacity>
          </View>
        </View>

        {/* ── Stories Bar ── */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.storiesBar}>
          <TouchableOpacity style={s.storyItem} onPress={() => router.push('/create-status')}>
            <View style={s.storyAdd}>
              {user?.profile_image ? (
                <Image source={{ uri: user.profile_image }} style={s.storyImg} />
              ) : (
                <View style={s.storyPlaceholder}>
                  <Text style={s.storyPlaceholderText}>{(user?.full_name || 'U')[0]}</Text>
                </View>
              )}
              <View style={s.plusBadge}><Ionicons name="add" size={12} color="#FFF" /></View>
            </View>
            <Text style={s.storyName}>Your Story</Text>
          </TouchableOpacity>
          {statuses.filter((g: any) => g.user_id !== user?.id).map((group: any, idx: number) => (
            <TouchableOpacity
              key={group.user_id || idx}
              style={s.storyItem}
              onPress={() => router.push(`/story-viewer?userId=${group.user_id}` as any)}
            >
              <View style={[s.storyRing, group.has_unviewed && s.storyRingActive]}>
                {group.user_profile_image ? (
                  <Image source={{ uri: group.user_profile_image }} style={s.storyImg} />
                ) : (
                  <View style={s.storyPlaceholder}>
                    <Text style={s.storyPlaceholderText}>{(group.user_full_name || 'U')[0]}</Text>
                  </View>
                )}
              </View>
              <Text style={s.storyName} numberOfLines={1}>{group.user_full_name?.split(' ')[0] || 'User'}</Text>
            </TouchableOpacity>
          ))}
        </ScrollView>

        {/* ── Location Toggle ── */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.locRow}>
          {LOCATIONS.map(loc => (
            <TouchableOpacity
              key={loc.id}
              style={[s.locChip, activeLocation === loc.id && s.locChipActive]}
              onPress={() => setActiveLocation(loc.id)}
            >
              <Ionicons name={loc.icon as any} size={14} color={activeLocation === loc.id ? '#FFF' : colors.textSecondary} />
              <Text style={[s.locText, activeLocation === loc.id && { color: '#FFF' }]}>{loc.label}</Text>
            </TouchableOpacity>
          ))}
        </ScrollView>

        {/* ── Category Tabs ── */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.catRow}>
          {CATEGORIES.map(cat => (
            <TouchableOpacity
              key={cat}
              style={[s.catTab, activeCategory === cat && s.catTabActive]}
              onPress={() => setActiveCategory(cat)}
            >
              <Text style={[s.catText, activeCategory === cat && s.catTextActive]}>{cat}</Text>
            </TouchableOpacity>
          ))}
        </ScrollView>

        {/* ── Tonight Mode Banner ── */}
        {tonightMode && (
          <View style={s.tonightBanner}>
            <Text style={s.tonightBannerIcon}>🌙</Text>
            <View style={{ flex: 1 }}>
              <Text style={s.tonightBannerTitle}>Tonight Mode</Text>
              <Text style={s.tonightBannerSub}>Active spots, places open now, recent check-ins</Text>
            </View>
          </View>
        )}

        {/* ── Masonry Grid ── */}
        {isLoading ? (
          <View style={s.loadingWrap}>
            <ActivityIndicator size="large" color={colors.accentPrimary} />
          </View>
        ) : posts.length === 0 ? (
          <View style={s.emptyWrap}>
            <Ionicons name="images-outline" size={48} color={colors.textHint} />
            <Text style={s.emptyTitle}>No posts yet</Text>
            <Text style={s.emptyBody}>Be the first to drop a moment</Text>
          </View>
        ) : (
          <View style={s.masonry}>
            <View style={s.column}>
              {left.map(({ post, h }) => (
                <MasonryCard
                  key={post.id}
                  post={post}
                  height={h}
                  onPress={() => router.push(`/post/${post.id}` as any)}
                  onLike={() => handleLike(post.id)}
                  onSave={() => handleSave(post.id)}
                  isLiked={likedPosts.has(post.id)}
                  isSaved={savedPosts.has(post.id)}
                />
              ))}
            </View>
            <View style={s.column}>
              {right.map(({ post, h }) => (
                <MasonryCard
                  key={post.id}
                  post={post}
                  height={h}
                  onPress={() => router.push(`/post/${post.id}` as any)}
                  onLike={() => handleLike(post.id)}
                  onSave={() => handleSave(post.id)}
                  isLiked={likedPosts.has(post.id)}
                  isSaved={savedPosts.has(post.id)}
                />
              ))}
            </View>
          </View>
        )}
      </ScrollView>

      {/* ── Floating Action Button: Drop a Moment ── */}
      <TouchableOpacity style={[s.fab, { bottom: insets.bottom + 80 }]} onPress={dropMoment} activeOpacity={0.85}>
        <Ionicons name="add" size={26} color="#FFF" />
      </TouchableOpacity>
    </View>
  );
}

// ═══════════════════════════════════════════════════════════════════
// STYLES
// ═══════════════════════════════════════════════════════════════════
const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FAFAF8' },

  // Header
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start', paddingHorizontal: 16, paddingBottom: 6 },
  logo: { fontSize: 22, fontWeight: '800', color: colors.textPrimary, fontStyle: 'italic' },
  greeting: { fontSize: 13, color: colors.textHint, marginTop: 1 },
  headerRight: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingTop: 4 },
  tonightBtn: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 12, paddingVertical: 7, borderRadius: 20, backgroundColor: colors.bgSubtle, borderWidth: 1, borderColor: colors.borderLight },
  tonightBtnActive: { backgroundColor: '#1B1B1B', borderColor: '#1B1B1B' },
  tonightText: { fontSize: 13, fontWeight: '600', color: colors.textPrimary },
  iconBtn: { width: 40, height: 40, borderRadius: 20, justifyContent: 'center', alignItems: 'center' },

  // Stories
  storiesBar: { paddingHorizontal: 12, paddingVertical: 10, gap: 12 },
  storyItem: { alignItems: 'center', width: 64 },
  storyAdd: { position: 'relative' },
  storyImg: { width: 56, height: 56, borderRadius: 28 },
  storyPlaceholder: { width: 56, height: 56, borderRadius: 28, backgroundColor: colors.bgSubtle, justifyContent: 'center', alignItems: 'center' },
  storyPlaceholderText: { fontSize: 18, fontWeight: '700', color: colors.textHint },
  plusBadge: { position: 'absolute', bottom: -1, right: -1, width: 20, height: 20, borderRadius: 10, backgroundColor: colors.accentPrimary, justifyContent: 'center', alignItems: 'center', borderWidth: 2, borderColor: '#FAFAF8' },
  storyRing: { width: 60, height: 60, borderRadius: 30, borderWidth: 2, borderColor: colors.borderLight, justifyContent: 'center', alignItems: 'center' },
  storyRingActive: { borderColor: colors.accentPrimary },
  storyName: { fontSize: 11, color: colors.textSecondary, marginTop: 4, textAlign: 'center' },

  // Location toggle
  locRow: { paddingHorizontal: 12, gap: 6, paddingBottom: 8 },
  locChip: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 12, paddingVertical: 7, borderRadius: 18, backgroundColor: '#FFF', borderWidth: 1, borderColor: colors.borderLight },
  locChipActive: { backgroundColor: '#1B4332', borderColor: '#1B4332' },
  locText: { fontSize: 12, fontWeight: '600', color: colors.textSecondary },

  // Category tabs
  catRow: { paddingHorizontal: 12, gap: 6, paddingBottom: 10 },
  catTab: { paddingHorizontal: 14, paddingVertical: 7, borderRadius: 16, backgroundColor: 'transparent' },
  catTabActive: { backgroundColor: '#1B1B1B' },
  catText: { fontSize: 14, fontWeight: '600', color: colors.textHint },
  catTextActive: { color: '#FFF' },

  // Tonight banner
  tonightBanner: { flexDirection: 'row', alignItems: 'center', gap: 10, marginHorizontal: 12, marginBottom: 10, padding: 14, borderRadius: 16, backgroundColor: '#1B1B1B' },
  tonightBannerIcon: { fontSize: 20 },
  tonightBannerTitle: { fontSize: 15, fontWeight: '700', color: '#FFF' },
  tonightBannerSub: { fontSize: 12, color: 'rgba(255,255,255,0.6)', marginTop: 1 },

  // Masonry
  masonry: { flexDirection: 'row', paddingHorizontal: COL_GAP, gap: COL_GAP },
  column: { flex: 1 },

  // Loading / Empty
  loadingWrap: { paddingTop: 60, alignItems: 'center' },
  emptyWrap: { paddingTop: 60, alignItems: 'center' },
  emptyTitle: { fontSize: 18, fontWeight: '700', color: colors.textPrimary, marginTop: 12 },
  emptyBody: { fontSize: 14, color: colors.textHint, marginTop: 4 },

  // FAB
  fab: { position: 'absolute', right: 16, width: 56, height: 56, borderRadius: 28, backgroundColor: colors.accentPrimary, justifyContent: 'center', alignItems: 'center', elevation: 8, shadowColor: '#000', shadowOffset: { width: 0, height: 4 }, shadowOpacity: 0.25, shadowRadius: 8 },
});
