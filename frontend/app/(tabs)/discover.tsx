import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Image,
  FlatList,
  RefreshControl,
  TextInput,
  Alert,
  ActivityIndicator,
  Dimensions,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import { colors, spacing, borderRadius, shadows } from '../../src/utils/theme';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';
import { formatDistanceToNow } from 'date-fns';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

const TABS = [
  { id: 'foryou', label: 'For you' },
  { id: 'culture', label: 'Culture' },
  { id: 'science', label: 'Science' },
  { id: 'featured', label: 'Featured', badge: 'New' },
  { id: 'daily', label: 'Daily' },
];

function DiscoverPostCard({ post, onPress }: { post: any; onPress: () => void }) {
  const authorName = post.user_full_name || post.user_username || 'User';
  const timeAgo = post.created_at
    ? formatDistanceToNow(new Date(post.created_at), { addSuffix: true })
    : '';

  return (
    <TouchableOpacity style={dCardStyles.card} onPress={onPress} activeOpacity={0.9}>
      {post.image ? (
        <Image source={{ uri: post.image }} style={dCardStyles.image} />
      ) : null}
      <View style={dCardStyles.content}>
        <View style={dCardStyles.authorRow}>
          <View style={dCardStyles.avatar}>
            {post.user_profile_image ? (
              <Image source={{ uri: post.user_profile_image }} style={{ width: '100%', height: '100%' }} />
            ) : (
              <Text style={dCardStyles.avatarText}>{authorName[0].toUpperCase()}</Text>
            )}
          </View>
          <Text style={dCardStyles.authorName}>{authorName}</Text>
          <Text style={dCardStyles.dot}>·</Text>
          <Text style={dCardStyles.time}>{timeAgo}</Text>
        </View>
        <Text style={dCardStyles.postContent} numberOfLines={3}>{post.content}</Text>
        {post.location && (
          <View style={dCardStyles.locationRow}>
            <Ionicons name="location-outline" size={12} color={colors.textHint} />
            <Text style={dCardStyles.locationText}>{post.location}</Text>
          </View>
        )}
        <View style={dCardStyles.footer}>
          <View style={dCardStyles.footerItem}>
            <Ionicons name="heart-outline" size={16} color={colors.textHint} />
            <Text style={dCardStyles.footerText}>{post.likes_count || 0}</Text>
          </View>
          <View style={dCardStyles.footerItem}>
            <Ionicons name="chatbubble-outline" size={15} color={colors.textHint} />
            <Text style={dCardStyles.footerText}>{post.comments_count || 0}</Text>
          </View>
        </View>
      </View>
    </TouchableOpacity>
  );
}

const dCardStyles = StyleSheet.create({
  card: {
    backgroundColor: colors.bgCard,
    borderRadius: 20,
    marginHorizontal: 16,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    overflow: 'hidden',
    ...shadows.elevation1,
  },
  image: {
    width: '100%',
    height: SCREEN_WIDTH * 0.55,
  },
  content: {
    padding: 14,
  },
  authorRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
  },
  avatar: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: colors.avatarTeal,
    justifyContent: 'center',
    alignItems: 'center',
    overflow: 'hidden',
    marginRight: 8,
  },
  avatarText: {
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: '700',
  },
  authorName: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  dot: {
    fontSize: 13,
    color: colors.textHint,
    marginHorizontal: 4,
  },
  time: {
    fontSize: 12,
    color: colors.textHint,
  },
  postContent: {
    fontSize: 15,
    color: colors.textPrimary,
    lineHeight: 22,
  },
  locationRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    marginTop: 6,
  },
  locationText: {
    fontSize: 12,
    color: colors.textHint,
  },
  footer: {
    flexDirection: 'row',
    gap: 16,
    marginTop: 10,
    paddingTop: 10,
    borderTopWidth: 1,
    borderTopColor: colors.borderSubtle,
  },
  footerItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  footerText: {
    fontSize: 12,
    color: colors.textHint,
    fontWeight: '600',
  },
});

// ── Inline Quick Composer ─────────────────────────────────────
function DiscoverComposer({ user, visible, onClose, onCreated }: any) {
  const [content, setContent] = useState('');
  const [media, setMedia] = useState<{ uri: string; base64?: string }[]>([]);
  const [isPosting, setIsPosting] = useState(false);

  if (!visible) return null;

  const pickImage = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      quality: 0.7,
      base64: true,
    });
    if (!result.canceled && result.assets[0]) {
      const a = result.assets[0];
      setMedia([{ uri: a.uri, base64: a.base64 ? `data:image/jpeg;base64,${a.base64}` : undefined }]);
    }
  };

  const handlePost = async () => {
    if (!content.trim() && media.length === 0) return;
    setIsPosting(true);
    try {
      await api.post('/posts', {
        content: content.trim(),
        image: media[0]?.base64 || media[0]?.uri || null,
      });
      setContent('');
      setMedia([]);
      onClose();
      onCreated();
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.detail || 'Could not create post');
    } finally {
      setIsPosting(false);
    }
  };

  return (
    <View style={compStyles.container}>
      <View style={compStyles.header}>
        <Text style={compStyles.title}>Share on Discover</Text>
        <TouchableOpacity
          style={[compStyles.postBtn, (!content.trim() && media.length === 0) && { opacity: 0.4 }]}
          onPress={handlePost}
          disabled={(!content.trim() && media.length === 0) || isPosting}
        >
          {isPosting ? <ActivityIndicator size="small" color="#FFFFFF" /> : <Text style={compStyles.postBtnText}>Post</Text>}
        </TouchableOpacity>
        <TouchableOpacity onPress={onClose} style={{ padding: 4 }}>
          <Ionicons name="close" size={20} color={colors.textPrimary} />
        </TouchableOpacity>
      </View>
      <TextInput
        style={compStyles.input}
        placeholder="What's happening in your area?"
        placeholderTextColor={colors.textHint}
        value={content}
        onChangeText={setContent}
        multiline
        maxLength={2000}
      />
      {media.length > 0 && (
        <View style={compStyles.mediaPreview}>
          <Image source={{ uri: media[0].uri }} style={compStyles.previewImg} />
          <TouchableOpacity style={compStyles.removeBtn} onPress={() => setMedia([])}>
            <Ionicons name="close" size={14} color="#FFFFFF" />
          </TouchableOpacity>
        </View>
      )}
      <View style={compStyles.actions}>
        <TouchableOpacity onPress={pickImage} style={{ padding: 8 }}>
          <Ionicons name="image-outline" size={22} color={colors.accentSecondary} />
        </TouchableOpacity>
        <TouchableOpacity style={{ padding: 8 }}>
          <Ionicons name="camera-outline" size={22} color={colors.info} />
        </TouchableOpacity>
      </View>
    </View>
  );
}

const compStyles = StyleSheet.create({
  container: {
    backgroundColor: colors.bgCard,
    borderRadius: 20,
    marginHorizontal: 16,
    marginBottom: 12,
    padding: 14,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation2,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 10,
  },
  title: {
    flex: 1,
    fontSize: 15,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  postBtn: {
    backgroundColor: colors.accentPrimary,
    borderRadius: 16,
    paddingHorizontal: 14,
    paddingVertical: 6,
  },
  postBtnText: {
    fontSize: 13,
    fontWeight: '700',
    color: '#FFFFFF',
  },
  input: {
    fontSize: 15,
    color: colors.textPrimary,
    lineHeight: 22,
    minHeight: 50,
    textAlignVertical: 'top',
  },
  mediaPreview: {
    width: 80,
    height: 80,
    borderRadius: 12,
    overflow: 'hidden',
    marginTop: 8,
  },
  previewImg: {
    width: '100%',
    height: '100%',
  },
  removeBtn: {
    position: 'absolute',
    top: 2,
    right: 2,
    width: 20,
    height: 20,
    borderRadius: 10,
    backgroundColor: 'rgba(0,0,0,0.6)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  actions: {
    flexDirection: 'row',
    borderTopWidth: 1,
    borderTopColor: colors.borderSubtle,
    paddingTop: 8,
    marginTop: 8,
  },
});

// ── Main Discover Screen ──────────────────────────────────────
export default function DiscoverScreen() {
  const router = useRouter();
  const { user } = useAuthStore();
  const [activeTab, setActiveTab] = useState('foryou');
  const [neighborhood] = useState('Your Area');
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [posts, setPosts] = useState<any[]>([]);
  const [showComposer, setShowComposer] = useState(false);

  const loadPosts = async () => {
    try {
      const response = await api.get('/posts/feed');
      setPosts(response.data);
    } catch (error) {
      console.log('Error loading discover posts:', error);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadPosts();
  }, []);

  const onRefresh = useCallback(async () => {
    setIsRefreshing(true);
    await loadPosts();
    setIsRefreshing(false);
  }, []);

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <View style={styles.topRow}>
          <TouchableOpacity style={styles.locationBtn}>
            <View style={styles.locationIcon}>
              <Ionicons name="location" size={14} color={colors.accentPrimary} />
            </View>
            <Text style={styles.locationText}>{neighborhood}</Text>
            <Ionicons name="chevron-down" size={16} color={colors.textSecondary} />
          </TouchableOpacity>
          <View style={styles.headerActions}>
            <TouchableOpacity style={styles.iconBtn} onPress={() => setShowComposer(!showComposer)}>
              <Ionicons name="add-circle-outline" size={22} color={colors.accentPrimary} />
            </TouchableOpacity>
            <TouchableOpacity style={styles.iconBtn}>
              <Ionicons name="notifications-outline" size={20} color={colors.textSecondary} />
            </TouchableOpacity>
            {user && (
              <View style={styles.avatarSmall}>
                {user.profile_image ? (
                  <Image source={{ uri: user.profile_image }} style={{ width: '100%', height: '100%' }} />
                ) : (
                  <Text style={styles.avatarSmallText}>
                    {(user.full_name || 'U')[0].toUpperCase()}
                  </Text>
                )}
              </View>
            )}
          </View>
        </View>

        {/* Tabs */}
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.tabsRow}
        >
          {TABS.map((tab) => (
            <TouchableOpacity
              key={tab.id}
              style={[
                styles.tab,
                activeTab === tab.id && styles.tabActive,
              ]}
              onPress={() => setActiveTab(tab.id)}
            >
              <Text style={[
                styles.tabText,
                activeTab === tab.id && styles.tabTextActive,
              ]}>
                {tab.label}
              </Text>
              {tab.badge && (
                <View style={styles.tabBadge}>
                  <Text style={styles.tabBadgeText}>{tab.badge}</Text>
                </View>
              )}
            </TouchableOpacity>
          ))}
        </ScrollView>
      </View>

      {/* Feed */}
      <FlatList
        data={posts}
        keyExtractor={(item) => item.id}
        renderItem={({ item }) => (
          <DiscoverPostCard
            post={item}
            onPress={() => router.push(`/post/${item.id}`)}
          />
        )}
        ListHeaderComponent={
          <DiscoverComposer
            user={user}
            visible={showComposer}
            onClose={() => setShowComposer(false)}
            onCreated={() => loadPosts()}
          />
        }
        contentContainerStyle={{ paddingTop: 12, paddingBottom: 100 }}
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={onRefresh}
            tintColor={colors.accentPrimary}
          />
        }
        ListEmptyComponent={
          isLoading ? (
            <View style={styles.emptyState}>
              <ActivityIndicator size="large" color={colors.accentPrimary} />
            </View>
          ) : (
            <View style={styles.emptyState}>
              <Ionicons name="compass-outline" size={56} color={colors.textHint} />
              <Text style={styles.emptyTitle}>Nothing to discover yet</Text>
              <Text style={styles.emptyText}>Be the first to share something!</Text>
              <TouchableOpacity
                style={styles.emptyBtn}
                onPress={() => setShowComposer(true)}
              >
                <Text style={styles.emptyBtnText}>Create Post</Text>
              </TouchableOpacity>
            </View>
          )
        }
        showsVerticalScrollIndicator={false}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bgApp,
  },
  header: {
    backgroundColor: colors.bgCard,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderLight,
  },
  topRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  locationBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  locationIcon: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: colors.accentPrimaryLight,
    justifyContent: 'center',
    alignItems: 'center',
  },
  locationText: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  iconBtn: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: colors.bgSubtle,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarSmall: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: colors.accentPrimary,
    justifyContent: 'center',
    alignItems: 'center',
    overflow: 'hidden',
  },
  avatarSmallText: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '700',
  },
  tabsRow: {
    paddingHorizontal: 12,
    gap: 0,
  },
  tab: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  tabActive: {
    borderBottomColor: colors.textPrimary,
  },
  tabText: {
    fontSize: 14,
    fontWeight: '500',
    color: colors.textHint,
  },
  tabTextActive: {
    fontWeight: '700',
    color: colors.textPrimary,
  },
  tabBadge: {
    backgroundColor: '#16A34A',
    borderRadius: 8,
    paddingHorizontal: 6,
    paddingVertical: 2,
  },
  tabBadgeText: {
    fontSize: 10,
    fontWeight: '700',
    color: '#FFFFFF',
  },
  emptyState: {
    alignItems: 'center',
    paddingVertical: 60,
  },
  emptyTitle: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.textPrimary,
    marginTop: 16,
  },
  emptyText: {
    fontSize: 13,
    color: colors.textHint,
    marginTop: 4,
  },
  emptyBtn: {
    backgroundColor: colors.accentPrimary,
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 20,
    marginTop: 20,
  },
  emptyBtnText: {
    fontSize: 14,
    fontWeight: '700',
    color: '#FFFFFF',
  },
});
