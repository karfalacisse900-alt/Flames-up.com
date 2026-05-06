import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, ScrollView,
  ActivityIndicator, Dimensions, RefreshControl,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import api from '../src/api/client';
import MediaPreview from '../src/components/MediaPreview';
import { cachePostForDetail, cachePostsForDetail, setPostDetailFeedContext } from '../src/store/postDetailCache';

const { width: SW } = Dimensions.get('window');
const COL_W = (SW - 48) / 2;
const TABS = ['Saved', 'Collections', 'Liked'] as const;

export default function MyLibraryScreen() {
  const router = useRouter();
  const [tab, setTab] = useState<typeof TABS[number]>('Saved');
  const [savedPosts, setSavedPosts] = useState<any[]>([]);
  const [likedPosts, setLikedPosts] = useState<any[]>([]);
  const [collections, setCollections] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const loadData = useCallback(async () => {
    setIsLoading(true);
    try {
      if (tab === 'Saved') {
        const res = await api.get('/library/saved');
        setSavedPosts(res.data || []);
        cachePostsForDetail(res.data || []);
      } else if (tab === 'Liked') {
        const res = await api.get('/library/liked');
        setLikedPosts(res.data || []);
        cachePostsForDetail(res.data || []);
      } else if (tab === 'Collections') {
        const res = await api.get('/library/collections');
        setCollections(res.data || []);
      }
    } catch (e) {
      console.log('Library load error:', e);
    } finally {
      setIsLoading(false);
      setRefreshing(false);
    }
  }, [tab]);

  useEffect(() => { void loadData(); }, [loadData]);

  const onRefresh = () => { setRefreshing(true); loadData(); };

  const navigateToPost = (post: any) => {
    const postId = String(post?.id || post?.post_id || '');
    if (!postId) return;
    cachePostForDetail(post);
    setPostDetailFeedContext(posts.map((item) => item.id || item.post_id));
    router.push(`/post/${postId}` as any);
  };

  const posts = tab === 'Saved' ? savedPosts : tab === 'Liked' ? likedPosts : [];

  return (
    <SafeAreaView style={s.container}>
      {/* Header */}
      <View style={s.header}>
        <TouchableOpacity onPress={() => router.back()} style={s.backBtn}>
          <Ionicons name="arrow-back" size={22} color="#111" />
        </TouchableOpacity>
        <Text style={s.title}>My Library</Text>
        <View style={{ width: 44 }} />
      </View>

      {/* Tabs */}
      <View style={s.tabsRow}>
        {TABS.map((t) => (
          <TouchableOpacity key={t} style={[s.tab, tab === t && s.tabActive]} onPress={() => setTab(t)}>
            <Text style={[s.tabText, tab === t && s.tabTextActive]}>{t}</Text>
          </TouchableOpacity>
        ))}
      </View>

      {/* Content */}
      {isLoading ? (
        <View style={s.centerState}>
          <ActivityIndicator size="large" color="#111" />
        </View>
      ) : tab === 'Collections' ? (
        <CollectionsView collections={collections} onRefresh={onRefresh} refreshing={refreshing} router={router} />
      ) : posts.length === 0 ? (
        <ScrollView
          contentContainerStyle={s.centerState}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#111" />}
        >
          <Ionicons name={tab === 'Saved' ? 'bookmark-outline' : 'heart-outline'} size={56} color="#D4D0C8" />
          <Text style={s.emptyTitle}>No {tab.toLowerCase()} posts yet</Text>
          <Text style={s.emptyText}>
            {tab === 'Saved' ? 'Save posts to access them anytime' : 'Like posts to collect your favorites'}
          </Text>
        </ScrollView>
      ) : (
        <ScrollView
          showsVerticalScrollIndicator={false}
          contentContainerStyle={s.grid}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#111" />}
        >
          {posts.map((post: any, idx: number) => (
            <PostCard key={post.id || post.post_id || idx} post={post} onPress={() => navigateToPost(post)} />
          ))}
        </ScrollView>
      )}
    </SafeAreaView>
  );
}

/* ── Post Card ── */
function PostCard({ post, onPress }: { post: any; onPress: () => void }) {
  const imageUri = post.image || post.images?.[0];
  const hasImg = imageUri && (imageUri.startsWith('http') || imageUri.startsWith('data:') || imageUri.startsWith('cfstream:'));
  const authorName = post.user_full_name || post.user_username || 'User';

  return (
    <TouchableOpacity style={s.card} activeOpacity={0.9} onPress={onPress}>
      <View style={s.cardImgWrap}>
        {hasImg ? (
          <MediaPreview uri={imageUri} mediaTypes={post.media_types} style={s.cardImg} />
        ) : (
          <View style={[s.cardImg, { backgroundColor: '#F0ECE4', justifyContent: 'center', alignItems: 'center' }]}>
            <Ionicons name="image-outline" size={28} color="#D4D0C8" />
          </View>
        )}
        {post.collection && post.collection !== 'default' && post.collection !== 'My Library' && (
          <View style={s.collectionBadge}>
            <Text style={s.collectionBadgeText} numberOfLines={1}>{post.collection}</Text>
          </View>
        )}
      </View>
      <View style={s.cardInfo}>
        <Text style={s.cardTitle} numberOfLines={2}>{post.content || 'No caption'}</Text>
        <Text style={s.cardAuthor}>{authorName}</Text>
      </View>
    </TouchableOpacity>
  );
}

/* ── Collections View ── */
function CollectionsView({ collections, onRefresh, refreshing, router }: any) {
  if (collections.length === 0) {
    return (
      <ScrollView
        contentContainerStyle={s.centerState}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#111" />}
      >
        <Ionicons name="folder-outline" size={56} color="#D4D0C8" />
        <Text style={s.emptyTitle}>No collections yet</Text>
        <Text style={s.emptyText}>Save posts to collections to organize them</Text>
      </ScrollView>
    );
  }

  return (
    <ScrollView
      showsVerticalScrollIndicator={false}
      contentContainerStyle={{ padding: 16 }}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#111" />}
    >
      {collections.map((col: any, idx: number) => (
        <TouchableOpacity
          key={idx}
          style={s.colCard}
          activeOpacity={0.85}
          onPress={() => {
            // Navigate to saved posts filtered by this collection
            // For now show all saved posts
            router.push('/my-library' as any);
          }}
        >
          <View style={[s.colIcon, { backgroundColor: ['#F3ECFF', '#FEE2E2', '#DBEAFE', '#D1FAE5', '#FEF3C7'][idx % 5] }]}>
            <Ionicons name="folder" size={24} color={['#7C3AED', '#DC2626', '#2563EB', '#059669', '#D97706'][idx % 5]} />
          </View>
          <View style={{ flex: 1 }}>
            <Text style={s.colName}>{col.collection}</Text>
            <Text style={s.colCount}>{col.count} item{col.count !== 1 ? 's' : ''}</Text>
          </View>
          <Ionicons name="chevron-forward" size={20} color="#CCC" />
        </TouchableOpacity>
      ))}
    </ScrollView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FAFAF8' },

  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 16, paddingVertical: 8,
    borderBottomWidth: 1, borderBottomColor: '#F0EDE7',
  },
  backBtn: { width: 44, height: 44, borderRadius: 22, justifyContent: 'center', alignItems: 'center' },
  title: { fontSize: 18, fontWeight: '700', color: '#111' },

  tabsRow: { flexDirection: 'row', paddingHorizontal: 16, marginTop: 12, gap: 8 },
  tab: { paddingHorizontal: 16, paddingVertical: 10, borderRadius: 20, backgroundColor: '#F0ECE4' },
  tabActive: { backgroundColor: '#111' },
  tabText: { fontSize: 14, fontWeight: '600', color: '#888' },
  tabTextActive: { color: '#FFFFFF' },

  centerState: { flex: 1, justifyContent: 'center', alignItems: 'center', paddingVertical: 80 },
  emptyTitle: { fontSize: 18, fontWeight: '700', color: '#111', marginTop: 16 },
  emptyText: { fontSize: 14, color: '#999', marginTop: 6, textAlign: 'center', paddingHorizontal: 40 },

  // Grid
  grid: { flexDirection: 'row', flexWrap: 'wrap', padding: 16, gap: 12 },

  // Card
  card: { width: COL_W, marginBottom: 4 },
  cardImgWrap: { width: COL_W, height: COL_W * 1.3, borderRadius: 16, overflow: 'hidden', position: 'relative' },
  cardImg: { width: '100%', height: '100%' },
  collectionBadge: {
    position: 'absolute', bottom: 8, left: 8,
    backgroundColor: 'rgba(0,0,0,0.6)', borderRadius: 10,
    paddingHorizontal: 8, paddingVertical: 3, maxWidth: COL_W - 20,
  },
  collectionBadgeText: { fontSize: 11, fontWeight: '600', color: '#FFF' },
  cardInfo: { paddingTop: 8, paddingHorizontal: 2 },
  cardTitle: { fontSize: 13, fontWeight: '600', color: '#111', lineHeight: 17 },
  cardAuthor: { fontSize: 12, color: '#999', marginTop: 2 },

  // Collections
  colCard: {
    flexDirection: 'row', alignItems: 'center', gap: 14,
    paddingVertical: 16, borderBottomWidth: 1, borderBottomColor: '#F0EDE7',
  },
  colIcon: { width: 52, height: 52, borderRadius: 16, justifyContent: 'center', alignItems: 'center' },
  colName: { fontSize: 16, fontWeight: '700', color: '#111' },
  colCount: { fontSize: 13, color: '#999', marginTop: 2 },
});
