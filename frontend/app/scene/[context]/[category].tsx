import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView,
  RefreshControl, Dimensions, ActivityIndicator,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { isCFStreamVideo, extractStreamUid, getStreamPlaybackInfo } from '../../../src/utils/mediaUpload';
import api from '../../../src/api/client';

const { width: SW } = Dimensions.get('window');
const COL_GAP = 8;
const H_PAD = 8;
const COL_W = (SW - H_PAD * 2 - COL_GAP) / 2;

const CONTEXT_META: Record<string, { label: string; color: string; icon: string }> = {
  near:   { label: 'Near You',  color: '#1B4332', icon: 'location' },
  global: { label: 'Global',    color: '#0C2340', icon: 'globe-outline' },
  nyc:    { label: 'NYC',       color: '#1A1A1A', icon: 'business-outline' },
  miami:  { label: 'Miami',     color: '#0E7490', icon: 'sunny-outline' },
  tokyo:  { label: 'Tokyo',     color: '#B91C1C', icon: 'train-outline' },
  london: { label: 'London',    color: '#1E3A5F', icon: 'rainy-outline' },
  la:     { label: 'LA',        color: '#9A3412', icon: 'film-outline' },
  paris:  { label: 'Paris',     color: '#1E3A5F', icon: 'wine-outline' },
};

const CATEGORY_LABELS: Record<string, string> = {
  all: 'All Posts', people: 'People Out Now', spots: 'Spots',
};

// Staggered image heights for true masonry
const IMG_H = [COL_W * 1.4, COL_W * 1.05, COL_W * 1.55, COL_W * 1.15, COL_W * 1.3, COL_W * 1.0, COL_W * 1.45, COL_W * 1.1];
const INFO_H = 60;

// Pinterest-style card
function PinCard({ post, imgH, onPress }: { post: any; imgH: number; onPress: () => void }) {
  const img = post.image || post.images?.[0];
  const isVideo = isCFStreamVideo(img || '') || post.media_types?.includes('video');
  const [thumb, setThumb] = useState<string | null>(null);

  useEffect(() => {
    if (isVideo && img && isCFStreamVideo(img)) {
      const uid = extractStreamUid(img);
      if (uid) getStreamPlaybackInfo(uid).then(i => { if (i?.thumbnail) setThumb(i.thumbnail); }).catch(() => {});
    }
  }, [img, isVideo]);

  const displayImg = isVideo ? thumb : img;
  const hasImg = displayImg && (displayImg.startsWith('http') || displayImg.startsWith('data:'));
  const name = post.user_full_name || post.user_username || 'User';

  return (
    <TouchableOpacity style={s.card} activeOpacity={0.95} onPress={onPress}>
      {hasImg ? (
        <Image source={{ uri: displayImg }} style={[s.cardImg, { height: imgH }]} resizeMode="cover" />
      ) : (
        <View style={[s.cardImg, { height: imgH, backgroundColor: '#F0F0F0', justifyContent: 'center', alignItems: 'center' }]}>
          <Ionicons name="image-outline" size={32} color="#DDD" />
        </View>
      )}
      {isVideo && hasImg && (
        <View style={s.videoPlay}><Ionicons name="play-circle" size={28} color="rgba(255,255,255,0.85)" /></View>
      )}
      <View style={s.cardInfo}>
        {post.content ? <Text style={s.cardCaption} numberOfLines={2}>{post.content}</Text> : null}
        <View style={s.cardFooter}>
          <View style={s.cardAuthorRow}>
            {post.user_profile_image ? (
              <Image source={{ uri: post.user_profile_image }} style={s.cardAv} />
            ) : (
              <View style={s.cardAvFb}><Text style={s.cardAvTxt}>{name[0]}</Text></View>
            )}
            <Text style={s.cardAuthor} numberOfLines={1}>{name}</Text>
          </View>
          <View style={s.cardLikes}>
            <Ionicons name="heart-outline" size={13} color="#BBB" />
            <Text style={s.cardLikesTxt}>{post.likes_count || 0}</Text>
          </View>
        </View>
      </View>
    </TouchableOpacity>
  );
}

export default function SceneScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { context, category } = useLocalSearchParams<{ context: string; category: string }>();

  const [posts, setPosts] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);

  const ctxMeta = CONTEXT_META[context || 'global'] || CONTEXT_META.global;
  const catLabel = CATEGORY_LABELS[category || 'all'] || 'All Posts';

  useEffect(() => { loadPosts(); }, [context, category]);

  const loadPosts = async () => {
    try {
      setIsLoading(true);
      const res = await api.get('/posts/feed', { params: { limit: 50 } });
      let all = Array.isArray(res.data) ? res.data : [];

      // City filtering
      if (context && context !== 'global' && context !== 'near') {
        const cityMap: Record<string, string[]> = {
          nyc: ['new york', 'nyc', 'brooklyn', 'manhattan'], miami: ['miami', 'south beach', 'wynwood'],
          tokyo: ['tokyo', 'shibuya', 'shinjuku'], london: ['london', 'soho', 'shoreditch'],
          la: ['los angeles', 'la', 'hollywood', 'venice'], paris: ['paris', 'montmartre'],
        };
        const kw = cityMap[context] || [];
        if (kw.length) {
          const f = all.filter((p: any) => {
            const t = ((p.location || '') + ' ' + (p.content || '')).toLowerCase();
            return kw.some(k => t.includes(k));
          });
          if (f.length > 0) all = f;
        }
      }
      setPosts(all);
    } catch { setPosts([]); } finally { setIsLoading(false); }
  };

  const onRefresh = useCallback(async () => {
    setIsRefreshing(true); await loadPosts(); setIsRefreshing(false);
  }, [context, category]);

  // Only posts with images
  const imagePosts = posts.filter((p: any) => {
    const img = p.image || p.images?.[0];
    return img && (img.startsWith('http') || img.startsWith('data:') || isCFStreamVideo(img));
  });

  // Build masonry
  const leftCol: any[] = [], rightCol: any[] = [];
  let leftH = 0, rightH = 0;
  imagePosts.forEach((post, idx) => {
    const h = IMG_H[idx % IMG_H.length];
    const total = h + INFO_H + COL_GAP;
    if (leftH <= rightH) { leftCol.push({ ...post, _h: h }); leftH += total; }
    else { rightCol.push({ ...post, _h: h }); rightH += total; }
  });

  return (
    <View style={s.container}>
      {/* Header */}
      <View style={[s.header, { paddingTop: insets.top }]}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="chevron-back" size={22} color="#1A1A1A" />
        </TouchableOpacity>
        <View style={s.headerCenter}>
          <Ionicons name={ctxMeta.icon as any} size={16} color={ctxMeta.color} />
          <Text style={s.headerTitle}>{ctxMeta.label}</Text>
        </View>
        <View style={{ width: 40 }} />
      </View>

      <Text style={s.subTitle}>{catLabel}</Text>

      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {isLoading ? (
          <View style={s.center}><ActivityIndicator size="large" color="#1A1A1A" /></View>
        ) : imagePosts.length === 0 ? (
          <View style={s.center}>
            <Ionicons name="images-outline" size={48} color="#DDD" />
            <Text style={s.emptyText}>No posts yet</Text>
            <TouchableOpacity style={s.createBtn} onPress={() => router.push('/create-post' as any)}>
              <Text style={s.createBtnText}>Create Post</Text>
            </TouchableOpacity>
          </View>
        ) : (
          <View style={s.masonry}>
            <View style={s.col}>{leftCol.map(p => <PinCard key={p.id} post={p} imgH={p._h} onPress={() => router.push(`/post/${p.id}` as any)} />)}</View>
            <View style={s.col}>{rightCol.map(p => <PinCard key={p.id} post={p} imgH={p._h} onPress={() => router.push(`/post/${p.id}` as any)} />)}</View>
          </View>
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FFF' },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 12, paddingBottom: 4 },
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#F5F5F5', justifyContent: 'center', alignItems: 'center' },
  headerCenter: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  headerTitle: { fontSize: 18, fontWeight: '700', color: '#1A1A1A' },
  subTitle: { fontSize: 13, color: '#AAA', fontWeight: '600', paddingHorizontal: 16, marginBottom: 10 },

  masonry: { flexDirection: 'row', paddingHorizontal: H_PAD, gap: COL_GAP },
  col: { flex: 1, gap: COL_GAP },

  card: { borderRadius: 14, overflow: 'hidden', backgroundColor: '#FFF', borderWidth: 0.5, borderColor: '#F0F0F0' },
  cardImg: { width: '100%' },
  videoPlay: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 60, justifyContent: 'center', alignItems: 'center' },
  cardInfo: { paddingHorizontal: 10, paddingTop: 8, paddingBottom: 10 },
  cardCaption: { fontSize: 13, fontWeight: '600', color: '#1A1A1A', lineHeight: 17, marginBottom: 6 },
  cardFooter: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  cardAuthorRow: { flexDirection: 'row', alignItems: 'center', gap: 5, flex: 1 },
  cardAv: { width: 18, height: 18, borderRadius: 9 },
  cardAvFb: { width: 18, height: 18, borderRadius: 9, backgroundColor: '#F0F0F0', justifyContent: 'center', alignItems: 'center' },
  cardAvTxt: { fontSize: 9, fontWeight: '700', color: '#BBB' },
  cardAuthor: { fontSize: 11, color: '#AAA', fontWeight: '500', flex: 1 },
  cardLikes: { flexDirection: 'row', alignItems: 'center', gap: 3 },
  cardLikesTxt: { fontSize: 11, color: '#BBB' },

  center: { paddingTop: 100, alignItems: 'center' },
  emptyText: { fontSize: 15, color: '#BBB', marginTop: 12 },
  createBtn: { marginTop: 16, backgroundColor: '#1A1A1A', paddingHorizontal: 24, paddingVertical: 12, borderRadius: 12 },
  createBtnText: { color: '#FFF', fontSize: 14, fontWeight: '700' },
});
