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
const COL_GAP = 8;
const H_PAD = 8;
const COL_W = (SW - H_PAD * 2 - COL_GAP) / 2;

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

// Staggered image heights for masonry
const IMG_HEIGHTS = [COL_W * 1.4, COL_W * 1.1, COL_W * 1.55, COL_W * 1.2, COL_W * 1.35, COL_W * 1.0, COL_W * 1.45, COL_W * 1.15];
const INFO_H = 62; // height of the white info area below image

export default function DiscoverScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
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

  const filteredPosts = activeCategory === 'all'
    ? posts
    : posts.filter((p: any) => {
        const content = (p.content || '').toLowerCase();
        const type = (p.post_type || '').toLowerCase();
        const cat = activeCategory.toLowerCase();
        return content.includes(cat) || type.includes(cat);
      });

  const imagePosts = filteredPosts.filter((p: any) => {
    const img = p.image || p.images?.[0];
    return img && (img.startsWith('http') || img.startsWith('data:'));
  });

  // Build masonry columns
  const leftCol: any[] = [];
  const rightCol: any[] = [];
  let leftH = 0, rightH = 0;

  imagePosts.forEach((post, idx) => {
    const imgH = IMG_HEIGHTS[idx % IMG_HEIGHTS.length];
    const totalH = imgH + INFO_H + COL_GAP;
    if (leftH <= rightH) {
      leftCol.push({ ...post, _imgH: imgH });
      leftH += totalH;
    } else {
      rightCol.push({ ...post, _imgH: imgH });
      rightH += totalH;
    }
  });

  const renderCard = (post: any) => {
    const img = post.image || post.images?.[0];
    return (
      <TouchableOpacity
        key={post.id}
        style={s.card}
        activeOpacity={0.95}
        onPress={() => router.push(`/post/${post.id}` as any)}
      >
        <Image source={{ uri: img }} style={[s.cardImg, { height: post._imgH }]} resizeMode="cover" />
        <View style={s.cardInfo}>
          {post.content ? <Text style={s.cardCaption} numberOfLines={2}>{post.content}</Text> : null}
          <View style={s.cardFooter}>
            <View style={s.cardAuthorRow}>
              {post.user_profile_image ? (
                <Image source={{ uri: post.user_profile_image }} style={s.cardAvatar} />
              ) : (
                <View style={s.cardAvatarFb}><Text style={s.cardAvatarTxt}>{(post.user_full_name || 'U')[0]}</Text></View>
              )}
              <Text style={s.cardAuthor} numberOfLines={1}>{post.user_full_name || post.user_username}</Text>
            </View>
            <View style={s.cardLikes}>
              <Ionicons name="heart-outline" size={13} color="#BBB" />
              <Text style={s.cardLikesTxt}>{post.likes_count || 0}</Text>
            </View>
          </View>
        </View>
      </TouchableOpacity>
    );
  };

  return (
    <View style={s.container}>
      <View style={[s.header, { paddingTop: insets.top + 4 }]}>
        <Text style={s.headerTitle}>Discover</Text>
        <TouchableOpacity style={s.searchBtn}>
          <Ionicons name="search-outline" size={20} color="#1A1A1A" />
        </TouchableOpacity>
      </View>

      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.tabRow}>
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

      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {isLoading ? (
          <View style={s.center}><ActivityIndicator size="large" color="#1A1A1A" /></View>
        ) : imagePosts.length === 0 ? (
          <View style={s.center}>
            <Ionicons name="images-outline" size={48} color="#DDD" />
            <Text style={s.emptyText}>No posts yet</Text>
          </View>
        ) : (
          <View style={s.masonry}>
            <View style={s.col}>{leftCol.map(p => renderCard(p))}</View>
            <View style={s.col}>{rightCol.map(p => renderCard(p))}</View>
          </View>
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FFF' },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingBottom: 8 },
  headerTitle: { fontSize: 24, fontWeight: '800', color: '#1A1A1A', letterSpacing: -0.5 },
  searchBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#F5F5F5', justifyContent: 'center', alignItems: 'center' },

  tabRow: { paddingHorizontal: 12, paddingBottom: 10, gap: 4 },
  tab: { paddingHorizontal: 16, paddingVertical: 8, borderRadius: 20, backgroundColor: '#F5F5F5' },
  tabActive: { backgroundColor: '#1A1A1A' },
  tabText: { fontSize: 14, fontWeight: '600', color: '#999' },
  tabTextActive: { color: '#FFF' },

  masonry: { flexDirection: 'row', paddingHorizontal: H_PAD, gap: COL_GAP },
  col: { flex: 1, gap: COL_GAP },

  card: { borderRadius: 14, overflow: 'hidden', backgroundColor: '#FFF', borderWidth: 0.5, borderColor: '#F0F0F0' },
  cardImg: { width: '100%' },
  cardInfo: { paddingHorizontal: 10, paddingTop: 8, paddingBottom: 10 },
  cardCaption: { fontSize: 13, fontWeight: '600', color: '#1A1A1A', lineHeight: 17, marginBottom: 6 },
  cardFooter: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  cardAuthorRow: { flexDirection: 'row', alignItems: 'center', gap: 5, flex: 1 },
  cardAvatar: { width: 18, height: 18, borderRadius: 9 },
  cardAvatarFb: { width: 18, height: 18, borderRadius: 9, backgroundColor: '#F0F0F0', justifyContent: 'center', alignItems: 'center' },
  cardAvatarTxt: { fontSize: 9, fontWeight: '700', color: '#BBB' },
  cardAuthor: { fontSize: 11, color: '#AAA', fontWeight: '500', flex: 1 },
  cardLikes: { flexDirection: 'row', alignItems: 'center', gap: 3 },
  cardLikesTxt: { fontSize: 11, color: '#BBB' },

  center: { paddingTop: 100, alignItems: 'center' },
  emptyText: { fontSize: 15, color: '#BBB', marginTop: 12 },
});
