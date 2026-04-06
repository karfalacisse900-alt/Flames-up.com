import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView, RefreshControl,
  ActivityIndicator, Dimensions, Alert, Platform,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
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
const GAP = 2;

const CATEGORIES = ['All', 'Fashion', 'Food', 'Culture', 'Street', 'Nightlife'];
const LOCATIONS = [
  { id: 'global', label: 'Global', icon: 'globe-outline' },
  { id: 'near', label: 'Near You', icon: 'location-outline' },
  { id: 'nyc', label: 'NYC', icon: 'business-outline' },
  { id: 'miami', label: 'Miami', icon: 'sunny-outline' },
  { id: 'la', label: 'LA', icon: 'film-outline' },
  { id: 'london', label: 'London', icon: 'umbrella-outline' },
];

// ═══════════════════════════════════════════════════════════════
// SCENE CARD — Every post is a "scene" tied to a place
// ═══════════════════════════════════════════════════════════════
function SceneCard({
  post, width, height, onPress, onLike, onSave, isLiked, isSaved,
}: {
  post: any; width: number; height: number; onPress: () => void;
  onLike: () => void; onSave: () => void; isLiked: boolean; isSaved: boolean;
}) {
  const isVideo = post.media_type === 'video' || (post.media_types?.[0] === 'video');
  const hasImage = post.image || (post.images?.length > 0);
  const imageUri = post.image || post.images?.[0] || null;
  const location = post.place_name || post.location || post.user_city || '';

  return (
    <TouchableOpacity
      style={[cs.card, { width, height }]}
      activeOpacity={0.95}
      onPress={onPress}
    >
      {/* Media */}
      {isVideo && imageUri ? (
        <Video
          source={{ uri: imageUri }}
          style={cs.media}
          resizeMode={ResizeMode.COVER}
          shouldPlay={false}
          isMuted
        />
      ) : hasImage ? (
        <Image source={{ uri: imageUri }} style={cs.media} />
      ) : (
        <View style={[cs.media, cs.textCard]}>
          <Text style={cs.textContent} numberOfLines={6}>{post.content}</Text>
        </View>
      )}

      {/* Gradient overlay */}
      <View style={cs.overlay} />

      {/* Video indicator */}
      {isVideo && (
        <View style={cs.videoDot}>
          <Ionicons name="play" size={8} color="#FFF" />
        </View>
      )}

      {/* Bottom: location + caption + actions */}
      <View style={cs.bottom}>
        {location ? (
          <View style={cs.locRow}>
            <Ionicons name="location" size={10} color="rgba(255,255,255,0.8)" />
            <Text style={cs.locText} numberOfLines={1}>{location}</Text>
          </View>
        ) : null}
        {hasImage && post.content ? (
          <Text style={cs.caption} numberOfLines={1}>{post.content}</Text>
        ) : null}
        <View style={cs.actions}>
          <TouchableOpacity onPress={onLike} hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}>
            <Ionicons name={isLiked ? 'heart' : 'heart-outline'} size={16} color={isLiked ? '#EF4444' : 'rgba(255,255,255,0.85)'} />
          </TouchableOpacity>
          <TouchableOpacity onPress={onSave} hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}>
            <Ionicons name={isSaved ? 'bookmark' : 'bookmark-outline'} size={15} color={isSaved ? '#F59E0B' : 'rgba(255,255,255,0.85)'} />
          </TouchableOpacity>
        </View>
      </View>
    </TouchableOpacity>
  );
}

const cs = StyleSheet.create({
  card: { overflow: 'hidden', backgroundColor: '#E8E4DF' },
  media: { width: '100%', height: '100%' },
  textCard: { justifyContent: 'center', alignItems: 'center', paddingHorizontal: 16, backgroundColor: '#F5F0EB' },
  textContent: { fontSize: 14, fontWeight: '600', color: '#2D2D2D', textAlign: 'center', lineHeight: 20, fontStyle: 'italic', letterSpacing: 0.5 },
  overlay: { position: 'absolute', bottom: 0, left: 0, right: 0, height: '35%', backgroundColor: 'rgba(0,0,0,0.15)' },
  videoDot: { position: 'absolute', top: 8, right: 8, width: 20, height: 20, borderRadius: 10, backgroundColor: 'rgba(0,0,0,0.4)', justifyContent: 'center', alignItems: 'center' },
  bottom: { position: 'absolute', bottom: 0, left: 0, right: 0, padding: 8 },
  locRow: { flexDirection: 'row', alignItems: 'center', gap: 3, marginBottom: 2 },
  locText: { fontSize: 10, fontWeight: '600', color: 'rgba(255,255,255,0.85)', letterSpacing: 0.3 },
  caption: { fontSize: 11, color: 'rgba(255,255,255,0.9)', fontWeight: '400', letterSpacing: 0.2, marginBottom: 4 },
  actions: { flexDirection: 'row', alignItems: 'center', gap: 10 },
});


// ═══════════════════════════════════════════════════════════════
// TONIGHT MODE — Active spots using real places
// ═══════════════════════════════════════════════════════════════
function TonightView({ onClose }: { onClose: () => void }) {
  const router = useRouter();
  const [spots, setSpots] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadTonightSpots();
  }, []);

  const loadTonightSpots = async () => {
    try {
      const types = ['bar', 'restaurant', 'night_club', 'cafe'];
      const allSpots: any[] = [];
      for (const type of types) {
        try {
          const res = await api.get('/google-places/nearby', { params: { type, lat: 40.7128, lng: -74.006, radius: 5000 } });
          const data = Array.isArray(res.data) ? res.data : res.data?.places || [];
          allSpots.push(...data.filter((p: any) => p.open_now).slice(0, 3));
        } catch {}
      }
      setSpots(allSpots.slice(0, 12));
    } catch {} finally { setLoading(false); }
  };

  return (
    <View style={tn.container}>
      <View style={tn.header}>
        <View>
          <Text style={tn.title}>Tonight</Text>
          <Text style={tn.sub}>Active spots open now</Text>
        </View>
        <TouchableOpacity onPress={onClose} style={tn.closeBtn}>
          <Ionicons name="close" size={20} color="#FFF" />
        </TouchableOpacity>
      </View>

      {loading ? (
        <ActivityIndicator color="#FFF" style={{ marginTop: 40 }} />
      ) : spots.length === 0 ? (
        <View style={tn.emptyWrap}>
          <Ionicons name="moon-outline" size={40} color="rgba(255,255,255,0.4)" />
          <Text style={tn.emptyText}>No spots data available</Text>
          <Text style={tn.emptySub}>Enable Google Maps billing to see active spots</Text>
        </View>
      ) : (
        <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingBottom: 40 }}>
          {spots.map((spot, idx) => (
            <TouchableOpacity
              key={spot.place_id || idx}
              style={tn.spotCard}
              onPress={() => router.push(`/place/${spot.place_id}` as any)}
            >
              {spot.photo_url ? (
                <Image source={{ uri: spot.photo_url }} style={tn.spotImage} />
              ) : (
                <View style={[tn.spotImage, { backgroundColor: '#333', justifyContent: 'center', alignItems: 'center' }]}>
                  <Ionicons name="business-outline" size={20} color="#666" />
                </View>
              )}
              <View style={tn.spotInfo}>
                <Text style={tn.spotName} numberOfLines={1}>{spot.name}</Text>
                <Text style={tn.spotVicinity} numberOfLines={1}>{spot.vicinity}</Text>
                <View style={tn.spotMeta}>
                  {spot.open_now && <View style={tn.openDot} />}
                  <Text style={tn.openText}>Open Now</Text>
                  {spot.rating && <Text style={tn.ratingText}>★ {spot.rating}</Text>}
                </View>
              </View>
            </TouchableOpacity>
          ))}
        </ScrollView>
      )}
    </View>
  );
}

const tn = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0F0F0F', paddingHorizontal: 16, paddingTop: 16 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 20 },
  title: { fontSize: 28, fontWeight: '800', color: '#FFF', fontStyle: 'italic' },
  sub: { fontSize: 14, color: 'rgba(255,255,255,0.5)', marginTop: 2 },
  closeBtn: { width: 36, height: 36, borderRadius: 18, backgroundColor: 'rgba(255,255,255,0.1)', justifyContent: 'center', alignItems: 'center' },
  emptyWrap: { alignItems: 'center', paddingTop: 60 },
  emptyText: { fontSize: 16, fontWeight: '600', color: 'rgba(255,255,255,0.6)', marginTop: 12 },
  emptySub: { fontSize: 13, color: 'rgba(255,255,255,0.3)', marginTop: 4, textAlign: 'center' },
  spotCard: { flexDirection: 'row', backgroundColor: '#1A1A1A', borderRadius: 16, overflow: 'hidden', marginBottom: 10 },
  spotImage: { width: 80, height: 80 },
  spotInfo: { flex: 1, padding: 12, justifyContent: 'center' },
  spotName: { fontSize: 15, fontWeight: '700', color: '#FFF' },
  spotVicinity: { fontSize: 12, color: 'rgba(255,255,255,0.5)', marginTop: 2 },
  spotMeta: { flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: 6 },
  openDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: '#22C55E' },
  openText: { fontSize: 11, fontWeight: '600', color: '#22C55E' },
  ratingText: { fontSize: 11, color: '#F59E0B', marginLeft: 8 },
});


// ═══════════════════════════════════════════════════════════════
// EDITORIAL GRID — Mixed block layouts
// ═══════════════════════════════════════════════════════════════

// Block patterns: each consumes N posts and returns JSX
const FULL = SW;
const HALF = (SW - GAP) / 2;
const THIRD = (SW - GAP * 2) / 3;
const TWO_THIRD = THIRD * 2 + GAP;
const CELL_H = SW * 0.55;
const SMALL_H = SW * 0.42;
const TALL_H = SMALL_H * 2 + GAP;

type CardProps = {
  post: any; w: number; h: number;
  onPress: () => void; onLike: () => void; onSave: () => void;
  isLiked: boolean; isSaved: boolean;
};

function renderCard(p: CardProps) {
  return (
    <SceneCard
      key={p.post.id}
      post={p.post}
      width={p.w}
      height={p.h}
      onPress={p.onPress}
      onLike={p.onLike}
      onSave={p.onSave}
      isLiked={p.isLiked}
      isSaved={p.isSaved}
    />
  );
}


// ═══════════════════════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════════════════════
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
      const res = await api.get('/posts/feed', { params });
      const data = Array.isArray(res.data) ? res.data : [];
      setPosts(data);
      const liked = new Set<string>();
      data.forEach((p: any) => { if (p.user_liked) liked.add(p.id); });
      setLikedPosts(liked);
    } catch { } finally { setIsLoading(false); }
  };

  const loadStatuses = async () => {
    try {
      const res = await api.get('/statuses');
      setStatuses(Array.isArray(res.data) ? res.data : []);
    } catch { }
  };

  const onRefresh = useCallback(async () => {
    setIsRefreshing(true);
    await Promise.all([loadFeed(), loadStatuses()]);
    setIsRefreshing(false);
  }, [activeCategory, activeLocation]);

  const handleLike = async (id: string) => {
    try { await api.post(`/posts/${id}/like`); } catch {}
    setLikedPosts(p => { const n = new Set(p); n.has(id) ? n.delete(id) : n.add(id); return n; });
  };

  const handleSave = async (id: string) => {
    try {
      if (savedPosts.has(id)) { await api.delete(`/bookmarks/${id}`); }
      else { await api.post('/bookmarks', { post_id: id }); }
    } catch {}
    setSavedPosts(p => { const n = new Set(p); n.has(id) ? n.delete(id) : n.add(id); return n; });
  };

  // Drop a Moment
  const dropMoment = async () => {
    try {
      const { status } = await ImagePicker.requestCameraPermissionsAsync();
      if (status !== 'granted') return;
      const result = await ImagePicker.launchCameraAsync({ quality: 0.8, base64: true });
      if (!result.canceled && result.assets[0]) {
        const asset = result.assets[0];
        const imageData = asset.base64 ? `data:image/jpeg;base64,${asset.base64}` : asset.uri;
        const cfUrl = await uploadImage(imageData);
        let loc = '';
        try {
          const l = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Low });
          const g = await Location.reverseGeocodeAsync({ latitude: l.coords.latitude, longitude: l.coords.longitude });
          if (g[0]) loc = g[0].city || g[0].district || '';
        } catch {}
        await api.post('/posts', { content: loc ? `Moment in ${loc}` : '', image: cfUrl, post_type: 'lifestyle', location: loc });
        loadFeed();
      }
    } catch { Alert.alert('Error', 'Could not drop moment'); }
  };

  const cp = (post: any): CardProps => ({
    post, w: 0, h: 0,
    onPress: () => router.push(`/post/${post.id}` as any),
    onLike: () => handleLike(post.id),
    onSave: () => handleSave(post.id),
    isLiked: likedPosts.has(post.id),
    isSaved: savedPosts.has(post.id),
  });

  // Build editorial blocks from posts
  const buildBlocks = () => {
    const blocks: React.ReactNode[] = [];
    let i = 0;
    let blockIdx = 0;

    while (i < posts.length) {
      const pattern = blockIdx % 5;

      if (pattern === 0 && i < posts.length) {
        // BLOCK A: Full-width hero
        blocks.push(
          <View key={`b-${blockIdx}`} style={{ marginBottom: GAP }}>
            {renderCard({ ...cp(posts[i]), w: FULL, h: CELL_H })}
          </View>
        );
        i += 1;
      } else if (pattern === 1 && i + 2 < posts.length) {
        // BLOCK B: 1 tall left + 2 small stacked right
        blocks.push(
          <View key={`b-${blockIdx}`} style={{ flexDirection: 'row', marginBottom: GAP, gap: GAP }}>
            {renderCard({ ...cp(posts[i]), w: HALF, h: TALL_H })}
            <View style={{ gap: GAP }}>
              {renderCard({ ...cp(posts[i + 1]), w: HALF, h: SMALL_H })}
              {renderCard({ ...cp(posts[i + 2]), w: HALF, h: SMALL_H })}
            </View>
          </View>
        );
        i += 3;
      } else if (pattern === 2 && i + 2 < posts.length) {
        // BLOCK C: 3 equal columns
        blocks.push(
          <View key={`b-${blockIdx}`} style={{ flexDirection: 'row', marginBottom: GAP, gap: GAP }}>
            {renderCard({ ...cp(posts[i]), w: THIRD, h: THIRD })}
            {renderCard({ ...cp(posts[i + 1]), w: THIRD, h: THIRD })}
            {renderCard({ ...cp(posts[i + 2]), w: THIRD, h: THIRD })}
          </View>
        );
        i += 3;
      } else if (pattern === 3 && i + 2 < posts.length) {
        // BLOCK D: 2 small stacked left + 1 tall right
        blocks.push(
          <View key={`b-${blockIdx}`} style={{ flexDirection: 'row', marginBottom: GAP, gap: GAP }}>
            <View style={{ gap: GAP }}>
              {renderCard({ ...cp(posts[i]), w: HALF, h: SMALL_H })}
              {renderCard({ ...cp(posts[i + 1]), w: HALF, h: SMALL_H })}
            </View>
            {renderCard({ ...cp(posts[i + 2]), w: HALF, h: TALL_H })}
          </View>
        );
        i += 3;
      } else if (pattern === 4 && i + 2 < posts.length) {
        // BLOCK E: 1 large 2/3 + 1 small 1/3 top, then 1 small 1/3 + 1 large 2/3 bottom
        blocks.push(
          <View key={`b-${blockIdx}`} style={{ marginBottom: GAP }}>
            <View style={{ flexDirection: 'row', marginBottom: GAP, gap: GAP }}>
              {renderCard({ ...cp(posts[i]), w: TWO_THIRD, h: SMALL_H })}
              {renderCard({ ...cp(posts[i + 1]), w: THIRD, h: SMALL_H })}
            </View>
            {i + 2 < posts.length && (
              <View style={{ flexDirection: 'row', gap: GAP }}>
                {renderCard({ ...cp(posts[i + 2]), w: THIRD, h: SMALL_H })}
                {i + 3 < posts.length ? renderCard({ ...cp(posts[i + 3]), w: TWO_THIRD, h: SMALL_H }) : <View style={{ width: TWO_THIRD }} />}
              </View>
            )}
          </View>
        );
        i += Math.min(4, posts.length - i);
      } else {
        // Fallback: single card
        blocks.push(
          <View key={`b-${blockIdx}`} style={{ marginBottom: GAP }}>
            {renderCard({ ...cp(posts[i]), w: FULL, h: SMALL_H })}
          </View>
        );
        i += 1;
      }
      blockIdx++;
    }
    return blocks;
  };

  // Tonight mode
  if (tonightMode) {
    return (
      <View style={[s.container, { backgroundColor: '#0F0F0F', paddingTop: insets.top }]}>
        <TonightView onClose={() => setTonightMode(false)} />
      </View>
    );
  }

  return (
    <View style={s.container}>
      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} tintColor={colors.accentPrimary} />}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {/* Header */}
        <View style={[s.header, { paddingTop: insets.top + 8 }]}>
          <Text style={s.logo}>Flames-Up</Text>
          <View style={s.headerRight}>
            <TouchableOpacity
              style={[s.tonightBtn, tonightMode && s.tonightActive]}
              onPress={() => setTonightMode(true)}
            >
              <Text style={s.tonightIcon}>🌙</Text>
              <Text style={s.tonightLabel}>Tonight</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.headerIcon} onPress={() => router.push('/notifications' as any)}>
              <Ionicons name="notifications-outline" size={20} color={colors.textPrimary} />
            </TouchableOpacity>
          </View>
        </View>

        {/* Stories */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.stories}>
          <TouchableOpacity style={s.storyItem} onPress={() => router.push('/create-status')}>
            <View style={s.storyAddWrap}>
              {user?.profile_image ? (
                <Image source={{ uri: user.profile_image }} style={s.storyAvatar} />
              ) : (
                <View style={[s.storyAvatar, s.storyAvatarEmpty]}>
                  <Text style={s.storyInitial}>{(user?.full_name || 'U')[0]}</Text>
                </View>
              )}
              <View style={s.storyPlus}><Ionicons name="add" size={11} color="#FFF" /></View>
            </View>
            <Text style={s.storyLabel}>Your Story</Text>
          </TouchableOpacity>
          {statuses.filter((g: any) => g.user_id !== user?.id).map((g: any) => (
            <TouchableOpacity
              key={g.user_id}
              style={s.storyItem}
              onPress={() => router.push(`/story-viewer?userId=${g.user_id}` as any)}
            >
              <View style={[s.storyRing, g.has_unviewed && s.storyRingNew]}>
                {g.user_profile_image ? (
                  <Image source={{ uri: g.user_profile_image }} style={s.storyAvatar} />
                ) : (
                  <View style={[s.storyAvatar, s.storyAvatarEmpty]}>
                    <Text style={s.storyInitial}>{(g.user_full_name || 'U')[0]}</Text>
                  </View>
                )}
              </View>
              <Text style={s.storyLabel} numberOfLines={1}>{g.user_full_name?.split(' ')[0]}</Text>
            </TouchableOpacity>
          ))}
        </ScrollView>

        {/* Location toggle */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.chipRow}>
          {LOCATIONS.map(loc => (
            <TouchableOpacity
              key={loc.id}
              style={[s.chip, activeLocation === loc.id && s.chipActive]}
              onPress={() => setActiveLocation(loc.id)}
            >
              <Ionicons name={loc.icon as any} size={12} color={activeLocation === loc.id ? '#FFF' : '#888'} />
              <Text style={[s.chipText, activeLocation === loc.id && s.chipTextActive]}>{loc.label}</Text>
            </TouchableOpacity>
          ))}
        </ScrollView>

        {/* Category tabs */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.catRow}>
          {CATEGORIES.map(cat => (
            <TouchableOpacity
              key={cat}
              style={[s.catPill, activeCategory === cat && s.catPillActive]}
              onPress={() => setActiveCategory(cat)}
            >
              <Text style={[s.catLabel, activeCategory === cat && s.catLabelActive]}>{cat}</Text>
            </TouchableOpacity>
          ))}
        </ScrollView>

        {/* Editorial Grid */}
        {isLoading ? (
          <View style={s.loadWrap}><ActivityIndicator size="large" color="#999" /></View>
        ) : posts.length === 0 ? (
          <View style={s.emptyWrap}>
            <Ionicons name="camera-outline" size={44} color="#CCC" />
            <Text style={s.emptyTitle}>No scenes yet</Text>
            <Text style={s.emptyBody}>Drop a moment to start curating</Text>
          </View>
        ) : (
          <View>{buildBlocks()}</View>
        )}
      </ScrollView>

      {/* FAB — Drop a Moment */}
      <TouchableOpacity style={[s.fab, { bottom: insets.bottom + 80 }]} onPress={dropMoment} activeOpacity={0.85}>
        <Ionicons name="camera-outline" size={22} color="#FFF" />
      </TouchableOpacity>
    </View>
  );
}

// ═══════════════════════════════════════════════════════════════
// STYLES
// ═══════════════════════════════════════════════════════════════
const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FAFAF8' },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, paddingBottom: 8 },
  logo: { fontSize: 22, fontWeight: '800', color: '#1A1A1A', fontStyle: 'italic', letterSpacing: -0.5 },
  headerRight: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  tonightBtn: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 12, paddingVertical: 7, borderRadius: 20, backgroundColor: '#1A1A1A' },
  tonightActive: { backgroundColor: '#2D1B69' },
  tonightIcon: { fontSize: 12 },
  tonightLabel: { fontSize: 12, fontWeight: '600', color: '#FFF' },
  headerIcon: { width: 36, height: 36, borderRadius: 18, justifyContent: 'center', alignItems: 'center', backgroundColor: '#F0EDE8' },

  // Stories
  stories: { paddingHorizontal: 14, paddingVertical: 10, gap: 14 },
  storyItem: { alignItems: 'center', width: 60 },
  storyAddWrap: { position: 'relative' },
  storyAvatar: { width: 52, height: 52, borderRadius: 26 },
  storyAvatarEmpty: { backgroundColor: '#E8E4DF', justifyContent: 'center', alignItems: 'center' },
  storyInitial: { fontSize: 18, fontWeight: '700', color: '#999' },
  storyPlus: { position: 'absolute', bottom: -1, right: -1, width: 18, height: 18, borderRadius: 9, backgroundColor: '#1A1A1A', justifyContent: 'center', alignItems: 'center', borderWidth: 2, borderColor: '#FAFAF8' },
  storyRing: { width: 56, height: 56, borderRadius: 28, borderWidth: 2, borderColor: '#DDD', justifyContent: 'center', alignItems: 'center' },
  storyRingNew: { borderColor: '#1A1A1A' },
  storyLabel: { fontSize: 10, color: '#888', marginTop: 4, textAlign: 'center' },

  // Chips
  chipRow: { paddingHorizontal: 14, gap: 6, paddingBottom: 6 },
  chip: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 12, paddingVertical: 6, borderRadius: 16, borderWidth: 1, borderColor: '#E0DCD7' },
  chipActive: { backgroundColor: '#1B4332', borderColor: '#1B4332' },
  chipText: { fontSize: 12, fontWeight: '500', color: '#888' },
  chipTextActive: { color: '#FFF' },

  // Category
  catRow: { paddingHorizontal: 14, gap: 4, paddingBottom: 10 },
  catPill: { paddingHorizontal: 14, paddingVertical: 6, borderRadius: 14 },
  catPillActive: { backgroundColor: '#1A1A1A' },
  catLabel: { fontSize: 13, fontWeight: '600', color: '#AAA' },
  catLabelActive: { color: '#FFF' },

  // Loading / Empty
  loadWrap: { paddingTop: 60, alignItems: 'center' },
  emptyWrap: { paddingTop: 60, alignItems: 'center' },
  emptyTitle: { fontSize: 18, fontWeight: '700', color: '#1A1A1A', marginTop: 12 },
  emptyBody: { fontSize: 14, color: '#AAA', marginTop: 4 },

  // FAB
  fab: { position: 'absolute', right: 16, width: 52, height: 52, borderRadius: 26, backgroundColor: '#1A1A1A', justifyContent: 'center', alignItems: 'center', elevation: 8, shadowColor: '#000', shadowOffset: { width: 0, height: 4 }, shadowOpacity: 0.2, shadowRadius: 8 },
});
