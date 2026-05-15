import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, ScrollView,
  ActivityIndicator, Dimensions,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import api from '../src/api/client';
import MediaPreview from '../src/components/MediaPreview';
import { cachePostForDetail, cachePostsForDetail } from '../src/store/postDetailCache';
import { borderRadius, colors, shadows, spacing } from '../src/utils/theme';

const { width: SW } = Dimensions.get('window');
const COL_W = (SW - 48) / 2;
const TABS = ['Saved', 'Collections', 'Liked'] as const;

export default function MyLibraryScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{ collection?: string }>();
  const [tab, setTab] = useState<typeof TABS[number]>('Saved');
  const [selectedCollection, setSelectedCollection] = useState<string | null>(
    typeof params.collection === 'string' ? params.collection : null
  );
  const [savedPosts, setSavedPosts] = useState<any[]>([]);
  const [likedPosts, setLikedPosts] = useState<any[]>([]);
  const [collections, setCollections] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  const loadData = useCallback(async () => {
    setIsLoading(true);
    try {
      if (tab === 'Saved') {
        const res = await api.get('/library/saved');
        const allSaved = res.data || [];
        const visibleSaved = selectedCollection
          ? allSaved.filter((post: any) => String(post.collection || 'My Library') === selectedCollection)
          : allSaved;
        setSavedPosts(visibleSaved);
        cachePostsForDetail(visibleSaved);
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
    }
  }, [selectedCollection, tab]);

  useEffect(() => { void loadData(); }, [loadData]);
  useEffect(() => {
    if (typeof params.collection === 'string' && params.collection) {
      setSelectedCollection(params.collection);
      setTab('Saved');
    }
  }, [params.collection]);

  const navigateToPost = (post: any) => {
    const postId = String(post?.id || post?.post_id || '');
    if (!postId) return;
    cachePostForDetail(post);
    router.push(`/post/${postId}` as any);
  };

  const posts = tab === 'Saved' ? savedPosts : tab === 'Liked' ? likedPosts : [];

  return (
    <SafeAreaView style={s.container}>
      {/* Header */}
      <View style={s.header}>
        <TouchableOpacity onPress={() => router.back()} style={s.backBtn}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={s.title}>My Library</Text>
        <View style={{ width: 44 }} />
      </View>

      {/* Tabs */}
      <View style={s.tabsRow}>
        {TABS.map((t) => (
          <TouchableOpacity
            key={t}
            style={[s.tab, tab === t && s.tabActive]}
            onPress={() => {
              setTab(t);
              if (t !== 'Saved') setSelectedCollection(null);
              if (t === 'Saved' && selectedCollection) setSelectedCollection(null);
            }}
          >
            <Text style={[s.tabText, tab === t && s.tabTextActive]}>{t}</Text>
          </TouchableOpacity>
        ))}
      </View>

      {selectedCollection ? (
        <View style={s.activeCollectionPill}>
          <Ionicons name="folder" size={15} color={colors.textPrimary} />
          <Text style={s.activeCollectionText} numberOfLines={1}>{selectedCollection}</Text>
          <TouchableOpacity onPress={() => setSelectedCollection(null)} hitSlop={8}>
            <Ionicons name="close" size={15} color={colors.textHint} />
          </TouchableOpacity>
        </View>
      ) : null}

      {/* Content */}
      {isLoading ? (
        <View style={s.centerState}>
          <ActivityIndicator size="large" color={colors.accentPrimary} />
        </View>
      ) : tab === 'Collections' ? (
        <CollectionsView
          collections={collections}
          onOpenCollection={(collection: string) => {
            setSelectedCollection(collection);
            setTab('Saved');
          }}
        />
      ) : posts.length === 0 ? (
        <ScrollView
          contentContainerStyle={s.centerState}
        >
          <Ionicons name={tab === 'Saved' ? 'bookmark-outline' : 'heart-outline'} size={56} color={colors.textDisabled} />
          <Text style={s.emptyTitle}>No {tab.toLowerCase()} posts yet</Text>
          <Text style={s.emptyText}>
            {tab === 'Saved' ? 'Save posts to access them anytime' : 'Like posts to collect your favorites'}
          </Text>
        </ScrollView>
      ) : (
        <ScrollView
          showsVerticalScrollIndicator={false}
          contentContainerStyle={s.grid}
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
          <View style={[s.cardImg, { backgroundColor: colors.skeletonSoft, justifyContent: 'center', alignItems: 'center' }]}>
            <Ionicons name="image-outline" size={28} color={colors.textDisabled} />
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
function CollectionsView({ collections, onOpenCollection }: any) {
  if (collections.length === 0) {
    return (
      <ScrollView
        contentContainerStyle={s.centerState}
      >
        <Ionicons name="folder-outline" size={56} color={colors.textDisabled} />
        <Text style={s.emptyTitle}>No collections yet</Text>
        <Text style={s.emptyText}>Save posts to collections to organize them</Text>
      </ScrollView>
    );
  }

  return (
    <ScrollView
      showsVerticalScrollIndicator={false}
      contentContainerStyle={{ padding: spacing.md }}
    >
      {collections.map((col: any, idx: number) => (
        <TouchableOpacity
          key={idx}
          style={s.colCard}
          activeOpacity={0.85}
          onPress={() => onOpenCollection(col.collection)}
        >
          <View style={[s.colIcon, { backgroundColor: ['#F3ECFF', '#FEE2E2', '#DBEAFE', '#D1FAE5', '#FEF3C7'][idx % 5] }]}>
            <Ionicons name="folder" size={24} color={['#7C3AED', '#DC2626', '#2563EB', '#059669', '#D97706'][idx % 5]} />
          </View>
          <View style={{ flex: 1 }}>
            <Text style={s.colName}>{col.collection}</Text>
            <Text style={s.colCount}>{col.count} item{col.count !== 1 ? 's' : ''}</Text>
          </View>
          <Ionicons name="chevron-forward" size={20} color={colors.textHint} />
        </TouchableOpacity>
      ))}
    </ScrollView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bgApp },

  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    borderBottomWidth: 1, borderBottomColor: colors.divider,
  },
  backBtn: {
    width: 44,
    height: 44,
    borderRadius: 22,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation1,
  },
  title: { fontSize: 18, fontWeight: '600', color: colors.textPrimary },

  tabsRow: { flexDirection: 'row', paddingHorizontal: spacing.md, marginTop: spacing.gutter, gap: spacing.sm },
  tab: {
    paddingHorizontal: spacing.md,
    paddingVertical: 10,
    borderRadius: borderRadius.full,
    backgroundColor: colors.bgSubtle,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
  },
  tabActive: { backgroundColor: colors.accentPrimary, borderColor: colors.accentPrimary },
  tabText: { fontSize: 14, fontWeight: '600', color: colors.textSecondary },
  tabTextActive: { color: colors.textInverse },
  activeCollectionPill: {
    alignSelf: 'flex-start',
    marginLeft: spacing.md,
    marginTop: 10,
    maxWidth: SW - 32,
    minHeight: 34,
    borderRadius: 17,
    backgroundColor: colors.accentPrimaryLight,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    paddingHorizontal: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 7,
  },
  activeCollectionText: { flexShrink: 1, color: colors.textPrimary, fontSize: 13, fontWeight: '700' },

  centerState: { flex: 1, justifyContent: 'center', alignItems: 'center', paddingVertical: 80 },
  emptyTitle: { fontSize: 18, fontWeight: '600', color: colors.textPrimary, marginTop: spacing.md },
  emptyText: { fontSize: 14, color: colors.textSecondary, marginTop: 6, textAlign: 'center', paddingHorizontal: 40 },

  // Grid
  grid: { flexDirection: 'row', flexWrap: 'wrap', padding: spacing.md, gap: spacing.gutter },

  // Card
  card: { width: COL_W, marginBottom: spacing.sm },
  cardImgWrap: { width: COL_W, height: COL_W * 1.3, borderRadius: borderRadius.lg, overflow: 'hidden', position: 'relative', backgroundColor: colors.skeletonSoft },
  cardImg: { width: '100%', height: '100%' },
  collectionBadge: {
    position: 'absolute', bottom: 8, left: 8,
    backgroundColor: 'rgba(0,0,0,0.6)', borderRadius: 10,
    paddingHorizontal: 8, paddingVertical: 3, maxWidth: COL_W - 20,
  },
  collectionBadgeText: { fontSize: 11, fontWeight: '600', color: '#FFF' },
  cardInfo: { paddingTop: 8, paddingHorizontal: 2 },
  cardTitle: { fontSize: 13, fontWeight: '600', color: colors.textPrimary, lineHeight: 17 },
  cardAuthor: { fontSize: 12, color: colors.textHint, marginTop: 2 },

  // Collections
  colCard: {
    flexDirection: 'row', alignItems: 'center', gap: 14,
    padding: spacing.md,
    marginBottom: spacing.gutter,
    borderRadius: borderRadius.card,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation1,
  },
  colIcon: { width: 52, height: 52, borderRadius: 16, justifyContent: 'center', alignItems: 'center' },
  colName: { fontSize: 16, fontWeight: '600', color: colors.textPrimary },
  colCount: { fontSize: 13, color: colors.textSecondary, marginTop: 2 },
});
