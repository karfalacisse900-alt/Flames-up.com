import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView,
  RefreshControl, Dimensions, ActivityIndicator,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import api from '../../src/api/client';
import { useAuthStore } from '../../src/store/authStore';

const { width: SW } = Dimensions.get('window');
const COL_GAP = 8;
const H_PAD = 12;
const COL_W = (SW - H_PAD * 2 - COL_GAP) / 2;

// Lemon8-style category filters
const CATEGORIES = [
  { id: 'all',      label: 'All' },
  { id: 'outfits',  label: 'Outfits' },
  { id: 'travel',   label: 'Travel' },
  { id: 'food',     label: 'Food' },
  { id: 'car',      label: 'Cars' },
  { id: 'humor',    label: 'Humor' },
  { id: 'fitness',  label: 'Fitness' },
  { id: 'beauty',   label: 'Beauty' },
  { id: 'art',      label: 'Art' },
  { id: 'music',    label: 'Music' },
  { id: 'nightlife',label: 'Nightlife' },
  { id: 'culture',  label: 'Culture' },
];

// Staggered heights for true masonry look — alternating pattern
const H_RATIOS = [1.35, 1.0, 1.5, 1.15, 1.25, 1.05, 1.4, 1.1];

export default function DiscoverScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();

  const [activeCategory, setActiveCategory] = useState('all');
  const [posts, setPosts] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  useEffect(() => { loadPosts(); }, []);

  const loadPosts = async () => {
    try {
      setIsLoading(true);
      const res = await api.get('/posts/feed', { params: { limit: 50 } });
      setPosts(Array.isArray(res.data) ? res.data : []);
    } catch {} finally { setIsLoading(false); }
  };

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await loadPosts();
    setRefreshing(false);
  }, []);

  // Filter posts by category (match against content or post_type)
  const filteredPosts = activeCategory === 'all'
    ? posts
    : posts.filter((p: any) => {
        const content = (p.content || '').toLowerCase();
        const type = (p.post_type || '').toLowerCase();
        const cat = activeCategory.toLowerCase();
        return content.includes(cat) || type.includes(cat) || type === cat;
      });

  // Only posts with images for the grid
  const imagePosts = filteredPosts.filter((p: any) => {
    const img = p.image || p.images?.[0];
    return img && (img.startsWith('http') || img.startsWith('data:'));
  });

  // Build masonry columns
  const leftCol: any[] = [];
  const rightCol: any[] = [];
  let leftH = 0, rightH = 0;

  imagePosts.forEach((post, idx) => {
    const h = COL_W * H_RATIOS[idx % H_RATIOS.length];
    if (leftH <= rightH) {
      leftCol.push({ ...post, _h: h });
      leftH += h + COL_GAP;
    } else {
      rightCol.push({ ...post, _h: h });
      rightH += h + COL_GAP;
    }
  });

  const renderCard = (post: any, idx: number) => {
    const img = post.image || post.images?.[0];
    return (
      <TouchableOpacity
        key={post.id}
        style={[s.card, { height: post._h }]}
        activeOpacity={0.92}
        onPress={() => router.push(`/post/${post.id}` as any)}
      >
        <Image source={{ uri: img }} style={s.cardImg} resizeMode="cover" />
        <View style={s.cardBottom}>
          <Text style={s.cardCaption} numberOfLines={2}>{post.content || ''}</Text>
          <View style={s.cardMeta}>
            <View style={s.cardAuthorRow}>
              {post.user_profile_image ? (
                <Image source={{ uri: post.user_profile_image }} style={s.cardAvatar} />
              ) : (
                <View style={s.cardAvatarFallback}>
                  <Text style={s.cardAvatarText}>{(post.user_full_name || 'U')[0]}</Text>
                </View>
              )}
              <Text style={s.cardAuthor} numberOfLines={1}>{post.user_full_name || post.user_username}</Text>
            </View>
            <View style={s.cardLikes}>
              <Ionicons name="heart-outline" size={12} color="#999" />
              <Text style={s.cardLikesText}>{post.likes_count || 0}</Text>
            </View>
          </View>
        </View>
      </TouchableOpacity>
    );
  };

  return (
    <View style={s.container}>
      {/* Header */}
      <View style={[s.header, { paddingTop: insets.top + 4 }]}>
        <Text style={s.headerTitle}>Discover</Text>
        <TouchableOpacity style={s.searchBtn} onPress={() => {}}>
          <Ionicons name="search-outline" size={20} color="#1A1A1A" />
        </TouchableOpacity>
      </View>

      {/* Lemon8-style Category Tabs */}
      <View style={s.tabBar}>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.tabContent}>
          {CATEGORIES.map(cat => {
            const active = activeCategory === cat.id;
            return (
              <TouchableOpacity
                key={cat.id}
                style={[s.tab, active && s.tabActive]}
                onPress={() => setActiveCategory(cat.id)}
              >
                <Text style={[s.tabText, active && s.tabTextActive]}>{cat.label}</Text>
              </TouchableOpacity>
            );
          })}
        </ScrollView>
      </View>

      {/* Pinterest Masonry Grid */}
      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
        contentContainerStyle={s.gridContainer}
      >
        {isLoading ? (
          <View style={s.loadingWrap}>
            <ActivityIndicator size="large" color="#1A1A1A" />
          </View>
        ) : imagePosts.length === 0 ? (
          <View style={s.emptyWrap}>
            <Ionicons name="images-outline" size={48} color="#CCC" />
            <Text style={s.emptyText}>No posts in this category yet</Text>
            <Text style={s.emptySub}>Be the first to share something!</Text>
          </View>
        ) : (
          <View style={s.masonry}>
            <View style={s.masonryCol}>
              {leftCol.map((post, i) => renderCard(post, i))}
            </View>
            <View style={s.masonryCol}>
              {rightCol.map((post, i) => renderCard(post, i))}
            </View>
          </View>
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FAFAF8' },

  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 20, paddingBottom: 4 },
  headerTitle: { fontSize: 26, fontWeight: '800', color: '#1A1A1A', letterSpacing: -0.5 },
  searchBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#F5F0EB', justifyContent: 'center', alignItems: 'center' },

  tabBar: { borderBottomWidth: 1, borderBottomColor: '#F0EDE7' },
  tabContent: { paddingHorizontal: 14, paddingVertical: 10, gap: 4 },
  tab: { paddingHorizontal: 16, paddingVertical: 8, borderRadius: 20 },
  tabActive: { backgroundColor: '#1A1A1A' },
  tabText: { fontSize: 14, fontWeight: '600', color: '#999' },
  tabTextActive: { color: '#FFF' },

  gridContainer: { paddingBottom: 100 },
  masonry: { flexDirection: 'row', paddingHorizontal: H_PAD, paddingTop: 10, gap: COL_GAP },
  masonryCol: { flex: 1, gap: COL_GAP },

  card: { borderRadius: 16, overflow: 'hidden', backgroundColor: '#F0EDE7' },
  cardImg: { width: '100%', height: '100%', position: 'absolute' },
  cardBottom: { position: 'absolute', bottom: 0, left: 0, right: 0, backgroundColor: '#FFF', paddingHorizontal: 10, paddingVertical: 8 },
  cardCaption: { fontSize: 13, fontWeight: '600', color: '#1A1A1A', lineHeight: 17, marginBottom: 6 },
  cardMeta: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  cardAuthorRow: { flexDirection: 'row', alignItems: 'center', gap: 5, flex: 1 },
  cardAvatar: { width: 18, height: 18, borderRadius: 9 },
  cardAvatarFallback: { width: 18, height: 18, borderRadius: 9, backgroundColor: '#E8E4DF', justifyContent: 'center', alignItems: 'center' },
  cardAvatarText: { fontSize: 9, fontWeight: '700', color: '#AAA' },
  cardAuthor: { fontSize: 11, color: '#999', fontWeight: '500', flex: 1 },
  cardLikes: { flexDirection: 'row', alignItems: 'center', gap: 3 },
  cardLikesText: { fontSize: 11, color: '#999' },

  loadingWrap: { paddingTop: 80, alignItems: 'center' },
  emptyWrap: { paddingTop: 80, alignItems: 'center' },
  emptyText: { fontSize: 16, fontWeight: '600', color: '#999', marginTop: 16 },
  emptySub: { fontSize: 13, color: '#CCC', marginTop: 4 },
});
