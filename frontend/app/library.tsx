import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Image,
  FlatList,
  ActivityIndicator,
  Dimensions,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, shadows } from '../src/utils/theme';
import api from '../src/api/client';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const THUMB_SIZE = (SCREEN_WIDTH - 48) / 3;

const TABS = [
  { id: 'liked', label: 'Liked', icon: 'heart' },
  { id: 'saved', label: 'Saved', icon: 'bookmark' },
  { id: 'collections', label: 'Collections', icon: 'folder-open' },
];

export default function LibraryScreen() {
  const router = useRouter();
  const [activeTab, setActiveTab] = useState('liked');
  const [likedPosts, setLikedPosts] = useState<any[]>([]);
  const [savedPosts, setSavedPosts] = useState<any[]>([]);
  const [collections, setCollections] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => { loadData(); }, []);

  const loadData = async () => {
    try {
      const [liked, saved, cols] = await Promise.all([
        api.get('/library/liked'),
        api.get('/library/saved'),
        api.get('/library/collections'),
      ]);
      setLikedPosts(liked.data);
      setSavedPosts(saved.data);
      setCollections(cols.data);
    } catch (error) {
      console.log('Error loading library:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const renderPostGrid = (posts: any[]) => (
    <View style={s.grid}>
      {posts.map((post) => (
        <TouchableOpacity key={post.id} style={s.thumb} onPress={() => router.push(`/post/${post.id}`)}>
          {post.image ? (
            <Image source={{ uri: post.image }} style={s.thumbImage} />
          ) : (
            <View style={s.thumbText}>
              <Text style={s.thumbTextContent} numberOfLines={4}>{post.content}</Text>
            </View>
          )}
        </TouchableOpacity>
      ))}
    </View>
  );

  const renderCollections = () => (
    <View style={s.collectionsGrid}>
      {collections.map((col) => (
        <TouchableOpacity key={col.name} style={s.collectionCard}>
          <View style={s.collectionIcon}>
            <Ionicons
              name={col.name === 'funny' ? 'happy-outline' : col.name === 'inspirational' ? 'sparkles-outline' : col.name === 'ideas' ? 'bulb-outline' : 'bookmark-outline'}
              size={28}
              color={colors.accentPrimary}
            />
          </View>
          <Text style={s.collectionName}>{col.name}</Text>
          <Text style={s.collectionCount}>{col.count} posts</Text>
        </TouchableOpacity>
      ))}
      {collections.length === 0 && (
        <View style={s.emptyState}>
          <Ionicons name="folder-open-outline" size={56} color={colors.textHint} />
          <Text style={s.emptyTitle}>No collections yet</Text>
          <Text style={s.emptyText}>Save posts to collections from the home feed</Text>
        </View>
      )}
    </View>
  );

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      {/* Header */}
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={s.headerTitle}>My Library</Text>
        <View style={{ width: 44 }} />
      </View>

      {/* Tabs */}
      <View style={s.tabRow}>
        {TABS.map((tab) => (
          <TouchableOpacity
            key={tab.id}
            style={[s.tab, activeTab === tab.id && s.tabActive]}
            onPress={() => setActiveTab(tab.id)}
          >
            <Ionicons
              name={tab.icon as any}
              size={18}
              color={activeTab === tab.id ? colors.accentPrimary : colors.textHint}
            />
            <Text style={[s.tabText, activeTab === tab.id && s.tabTextActive]}>{tab.label}</Text>
          </TouchableOpacity>
        ))}
      </View>

      {isLoading ? (
        <View style={s.loadingCenter}>
          <ActivityIndicator size="large" color={colors.accentPrimary} />
        </View>
      ) : (
        <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingBottom: 40 }}>
          {activeTab === 'liked' && (
            likedPosts.length > 0 ? renderPostGrid(likedPosts) : (
              <View style={s.emptyState}>
                <Ionicons name="heart-outline" size={56} color={colors.textHint} />
                <Text style={s.emptyTitle}>No liked posts yet</Text>
                <Text style={s.emptyText}>Posts you like will appear here</Text>
              </View>
            )
          )}
          {activeTab === 'saved' && (
            savedPosts.length > 0 ? renderPostGrid(savedPosts) : (
              <View style={s.emptyState}>
                <Ionicons name="bookmark-outline" size={56} color={colors.textHint} />
                <Text style={s.emptyTitle}>No saved posts yet</Text>
                <Text style={s.emptyText}>Bookmark posts to save them here</Text>
              </View>
            )
          )}
          {activeTab === 'collections' && renderCollections()}
        </ScrollView>
      )}
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bgApp },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingVertical: 12 },
  backBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 18, fontWeight: '700', color: colors.textPrimary, fontStyle: 'italic' },
  tabRow: { flexDirection: 'row', paddingHorizontal: 16, gap: 8, marginBottom: 16 },
  tab: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, paddingVertical: 12, borderRadius: 16, backgroundColor: colors.bgSubtle, borderWidth: 1, borderColor: colors.borderLight },
  tabActive: { backgroundColor: colors.accentPrimaryLight, borderColor: colors.accentPrimary + '40' },
  tabText: { fontSize: 13, fontWeight: '600', color: colors.textHint },
  tabTextActive: { color: colors.accentPrimary, fontWeight: '700' },
  grid: { flexDirection: 'row', flexWrap: 'wrap', paddingHorizontal: 16, gap: 4 },
  thumb: { width: THUMB_SIZE, height: THUMB_SIZE, borderRadius: 12, overflow: 'hidden', backgroundColor: colors.bgSubtle },
  thumbImage: { width: '100%', height: '100%' },
  thumbText: { flex: 1, padding: 8, justifyContent: 'center', backgroundColor: colors.bgSubtle },
  thumbTextContent: { fontSize: 10, color: colors.textSecondary, lineHeight: 14 },
  collectionsGrid: { paddingHorizontal: 16, gap: 12 },
  collectionCard: { flexDirection: 'row', alignItems: 'center', gap: 14, backgroundColor: colors.bgCard, borderRadius: 20, padding: 16, borderWidth: 1, borderColor: colors.borderLight },
  collectionIcon: { width: 52, height: 52, borderRadius: 16, backgroundColor: colors.accentPrimaryLight, justifyContent: 'center', alignItems: 'center' },
  collectionName: { fontSize: 16, fontWeight: '700', color: colors.textPrimary, flex: 1, textTransform: 'capitalize' },
  collectionCount: { fontSize: 13, color: colors.textHint },
  loadingCenter: { flex: 1, justifyContent: 'center', alignItems: 'center', paddingTop: 60 },
  emptyState: { alignItems: 'center', paddingVertical: 60 },
  emptyTitle: { fontSize: 16, fontWeight: '700', color: colors.textPrimary, marginTop: 16 },
  emptyText: { fontSize: 13, color: colors.textHint, marginTop: 4 },
});
