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
  KeyboardAvoidingView,
  Platform,
  Modal,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import { colors, spacing, shadows } from '../../src/utils/theme';
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

// Avatar color generator (matches original)
const avatarColors = ['#7C69C4', '#D98B62', '#3C6E5A', '#E05C7A', '#4A7FC1'];
function getAvatarColor(name: string) {
  return avatarColors[(name || 'U').charCodeAt(0) % avatarColors.length];
}

// ── Discover Post Card (improved visual layout) ────────────
function DiscoverPostCard({ post, onPress, featured = false }: { post: any; onPress: () => void; featured?: boolean }) {
  const authorName = post.user_full_name || post.user_username || 'User';
  const avatarColor = getAvatarColor(authorName);
  const dateStr = post.created_at
    ? formatDistanceToNow(new Date(post.created_at), { addSuffix: false })
    : '';

  if (featured && post.image) {
    // Featured card: large image with overlay
    return (
      <TouchableOpacity style={cardStyles.featuredContainer} onPress={onPress} activeOpacity={0.9}>
        <Image source={{ uri: post.image }} style={cardStyles.featuredImage} />
        <View style={cardStyles.featuredOverlay} />
        <View style={cardStyles.featuredContent}>
          <View style={cardStyles.featuredBadge}>
            <Ionicons name="flame" size={10} color="#FFFFFF" />
            <Text style={cardStyles.featuredBadgeText}>Trending</Text>
          </View>
          <Text style={cardStyles.featuredTitle} numberOfLines={2}>{post.content}</Text>
          <View style={cardStyles.featuredAuthor}>
            <View style={[cardStyles.avatar, { borderWidth: 1.5, borderColor: 'rgba(255,255,255,0.4)' }]}>
              {post.user_profile_image ? (
                <Image source={{ uri: post.user_profile_image }} style={{ width: '100%', height: '100%' }} />
              ) : (
                <Text style={[cardStyles.avatarLetter, { color: '#FFFFFF' }]}>{authorName[0].toUpperCase()}</Text>
              )}
            </View>
            <Text style={cardStyles.featuredAuthorName}>{authorName}</Text>
            <View style={{ flex: 1 }} />
            <Text style={cardStyles.featuredDate}>{dateStr}</Text>
          </View>
        </View>
      </TouchableOpacity>
    );
  }

  return (
    <TouchableOpacity style={cardStyles.container} onPress={onPress} activeOpacity={0.8}>
      {/* Large thumbnail if available */}
      {post.image && (
        <Image source={{ uri: post.image }} style={cardStyles.cardImage} />
      )}
      {/* Author row */}
      <View style={cardStyles.authorRow}>
        {post.user_profile_image ? (
          <Image source={{ uri: post.user_profile_image }} style={cardStyles.avatar} />
        ) : (
          <View style={[cardStyles.avatar, { backgroundColor: `${avatarColor}22` }]}>
            <Text style={[cardStyles.avatarLetter, { color: avatarColor }]}>
              {authorName[0].toUpperCase()}
            </Text>
          </View>
        )}
        <Text style={cardStyles.authorText}>{authorName}</Text>
        <View style={{ flex: 1 }} />
        <Text style={cardStyles.authorHint}>{dateStr} ago</Text>
      </View>

      {/* Content */}
      <Text style={cardStyles.title} numberOfLines={3}>{post.content}</Text>

      {post.location && (
        <View style={cardStyles.locationRow}>
          <Ionicons name="location" size={11} color={colors.accentPrimary} />
          <Text style={cardStyles.locationText}>{post.location}</Text>
        </View>
      )}

      {/* Footer */}
      <View style={cardStyles.footer}>
        <View style={cardStyles.footerStat}>
          <Ionicons name="heart" size={14} color={colors.textHint} />
          <Text style={cardStyles.footerStatText}>{post.likes_count || 0}</Text>
        </View>
        <View style={cardStyles.footerStat}>
          <Ionicons name="chatbubble-outline" size={13} color={colors.textHint} />
          <Text style={cardStyles.footerStatText}>{post.comments_count || 0}</Text>
        </View>
        <View style={{ flex: 1 }} />
        <TouchableOpacity hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}>
          <Ionicons name="bookmark-outline" size={16} color={colors.textHint} />
        </TouchableOpacity>
        <TouchableOpacity style={{ marginLeft: 16 }} hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}>
          <Ionicons name="share-outline" size={16} color={colors.textHint} />
        </TouchableOpacity>
      </View>
    </TouchableOpacity>
  );
}

const cardStyles = StyleSheet.create({
  // Standard card
  container: {
    marginHorizontal: 16,
    marginBottom: 12,
    backgroundColor: colors.bgCard,
    borderRadius: 20,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  cardImage: {
    width: '100%',
    height: 180,
    resizeMode: 'cover',
  },
  authorRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingTop: 12,
    gap: 8,
  },
  avatar: {
    width: 26,
    height: 26,
    borderRadius: 13,
    justifyContent: 'center',
    alignItems: 'center',
    overflow: 'hidden',
  },
  avatarLetter: {
    fontSize: 11,
    fontWeight: '700',
  },
  authorText: {
    fontSize: 13,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  authorHint: {
    fontSize: 11,
    color: colors.textHint,
  },
  title: {
    fontSize: 15,
    fontWeight: '600',
    color: colors.textPrimary,
    lineHeight: 21,
    paddingHorizontal: 14,
    paddingTop: 8,
  },
  locationRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    paddingHorizontal: 14,
    marginTop: 6,
  },
  locationText: {
    fontSize: 12,
    color: colors.accentPrimary,
    fontWeight: '500',
  },
  footer: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 12,
    gap: 14,
  },
  footerStat: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  footerStatText: {
    fontSize: 12,
    fontWeight: '600',
    color: colors.textHint,
  },
  // Featured card
  featuredContainer: {
    marginHorizontal: 16,
    marginBottom: 16,
    borderRadius: 24,
    overflow: 'hidden',
    height: 220,
  },
  featuredImage: {
    width: '100%',
    height: '100%',
    resizeMode: 'cover',
  },
  featuredOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.35)',
  },
  featuredContent: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    padding: 18,
  },
  featuredBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: 'rgba(255,120,50,0.85)',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 10,
    alignSelf: 'flex-start',
    marginBottom: 8,
  },
  featuredBadgeText: {
    fontSize: 11,
    fontWeight: '700',
    color: '#FFFFFF',
  },
  featuredTitle: {
    fontSize: 18,
    fontWeight: '800',
    color: '#FFFFFF',
    lineHeight: 24,
    marginBottom: 10,
  },
  featuredAuthor: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  featuredAuthorName: {
    fontSize: 13,
    fontWeight: '600',
    color: 'rgba(255,255,255,0.9)',
  },
  featuredDate: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.7)',
  },
});

// ── Full Screen Post Composer (matching original web design) ──────────
function FullScreenComposer({
  visible,
  user,
  onClose,
  onCreated,
}: {
  visible: boolean;
  user: any;
  onClose: () => void;
  onCreated: () => void;
}) {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [selectedTab, setSelectedTab] = useState('foryou');
  const [media, setMedia] = useState<{ uri: string; base64?: string }[]>([]);
  const [isPosting, setIsPosting] = useState(false);
  const [showTabPicker, setShowTabPicker] = useState(false);

  const pickMedia = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      quality: 0.7,
      base64: true,
      allowsMultipleSelection: true,
      selectionLimit: 4,
    });
    if (!result.canceled && result.assets) {
      const newMedia = result.assets.map((a) => ({
        uri: a.uri,
        base64: a.base64 ? `data:image/jpeg;base64,${a.base64}` : undefined,
      }));
      setMedia((prev) => [...prev, ...newMedia].slice(0, 4));
    }
  };

  const removeMedia = (idx: number) => {
    setMedia((prev) => prev.filter((_, i) => i !== idx));
  };

  const handlePost = async () => {
    if (!body.trim() || isPosting) return;
    setIsPosting(true);
    try {
      await api.post('/posts', {
        content: title.trim() ? `${title.trim()}\n\n${body.trim()}` : body.trim(),
        image: media[0]?.base64 || media[0]?.uri || null,
      });
      setTitle('');
      setBody('');
      setMedia([]);
      onClose();
      onCreated();
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.detail || 'Could not create post');
    } finally {
      setIsPosting(false);
    }
  };

  if (!visible) return null;

  const authorName = user?.full_name || user?.username || 'User';
  const currentTabLabel = TABS.find((t) => t.id === selectedTab)?.label || 'For you';

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="fullScreen">
      <SafeAreaView style={compStyles.container} edges={['top', 'bottom']}>
        <KeyboardAvoidingView
          style={{ flex: 1 }}
          behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        >
          {/* Header */}
          <View style={compStyles.header}>
            <TouchableOpacity style={compStyles.closeBtn} onPress={onClose}>
              <Ionicons name="close" size={18} color={colors.textSecondary} />
            </TouchableOpacity>
            <Text style={compStyles.headerTitle}>New Post</Text>
            <TouchableOpacity
              style={[
                compStyles.publishBtn,
                (!body.trim() || isPosting) && { opacity: 0.4 },
              ]}
              onPress={handlePost}
              disabled={!body.trim() || isPosting}
            >
              {isPosting ? (
                <ActivityIndicator size="small" color="#FFFFFF" />
              ) : (
                <Text style={compStyles.publishBtnText}>Publish</Text>
              )}
            </TouchableOpacity>
          </View>

          <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16 }}>
            {/* Author */}
            <View style={compStyles.authorRow}>
              <View style={compStyles.authorAvatar}>
                {user?.profile_image ? (
                  <Image
                    source={{ uri: user.profile_image }}
                    style={{ width: '100%', height: '100%' }}
                  />
                ) : (
                  <Text style={compStyles.authorAvatarText}>
                    {authorName[0].toUpperCase()}
                  </Text>
                )}
              </View>
              <View>
                <Text style={compStyles.authorName}>{authorName}</Text>
                <TouchableOpacity
                  style={compStyles.tabPickerBtn}
                  onPress={() => setShowTabPicker(!showTabPicker)}
                >
                  <Text style={compStyles.tabPickerText}>{currentTabLabel}</Text>
                  <Ionicons
                    name="chevron-down"
                    size={12}
                    color={colors.accentPrimary}
                  />
                </TouchableOpacity>
              </View>
            </View>

            {/* Tab picker dropdown */}
            {showTabPicker && (
              <View style={compStyles.tabDropdown}>
                {TABS.map((tab) => (
                  <TouchableOpacity
                    key={tab.id}
                    style={[
                      compStyles.tabDropdownItem,
                      selectedTab === tab.id && compStyles.tabDropdownItemActive,
                    ]}
                    onPress={() => {
                      setSelectedTab(tab.id);
                      setShowTabPicker(false);
                    }}
                  >
                    <Text
                      style={[
                        compStyles.tabDropdownText,
                        selectedTab === tab.id && compStyles.tabDropdownTextActive,
                      ]}
                    >
                      {tab.label}
                    </Text>
                  </TouchableOpacity>
                ))}
              </View>
            )}

            {/* Title */}
            <TextInput
              style={compStyles.titleInput}
              placeholder="Add a title (optional)"
              placeholderTextColor={colors.textHint}
              value={title}
              onChangeText={setTitle}
            />

            {/* Upload button */}
            <View style={compStyles.uploadRow}>
              <TouchableOpacity style={compStyles.uploadBtn} onPress={pickMedia}>
                <Ionicons name="image" size={16} color="#FFFFFF" />
                <Text style={compStyles.uploadBtnText}>Photo / Video</Text>
              </TouchableOpacity>
              {media.length > 0 && (
                <Text style={compStyles.mediaCount}>{media.length} added</Text>
              )}
            </View>

            {/* Body */}
            <TextInput
              style={compStyles.bodyInput}
              placeholder="Share what you learned, discovered, or want to discuss..."
              placeholderTextColor={colors.textHint}
              value={body}
              onChangeText={setBody}
              multiline
              maxLength={5000}
              textAlignVertical="top"
            />

            {/* Media previews */}
            {media.length > 0 && (
              <View style={compStyles.mediaGrid}>
                {media.map((m, idx) => (
                  <View key={idx} style={compStyles.mediaItem}>
                    <Image source={{ uri: m.uri }} style={compStyles.mediaImage} />
                    <TouchableOpacity
                      style={compStyles.mediaRemove}
                      onPress={() => removeMedia(idx)}
                    >
                      <Ionicons name="close" size={12} color="#FFFFFF" />
                    </TouchableOpacity>
                  </View>
                ))}
              </View>
            )}
          </ScrollView>
        </KeyboardAvoidingView>
      </SafeAreaView>
    </Modal>
  );
}

const compStyles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bgApp,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderLight,
  },
  closeBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: colors.bgSubtle,
    justifyContent: 'center',
    alignItems: 'center',
  },
  headerTitle: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.textPrimary,
    fontStyle: 'italic',
  },
  publishBtn: {
    paddingHorizontal: 18,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: colors.accentPrimary,
  },
  publishBtnText: {
    fontSize: 14,
    fontWeight: '700',
    color: '#FFFFFF',
  },
  authorRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginBottom: 16,
  },
  authorAvatar: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: colors.accentPrimaryLight,
    justifyContent: 'center',
    alignItems: 'center',
    overflow: 'hidden',
  },
  authorAvatarText: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.accentPrimary,
  },
  authorName: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  tabPickerBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: colors.accentPrimaryLight,
    paddingHorizontal: 10,
    paddingVertical: 3,
    borderRadius: 12,
    marginTop: 2,
  },
  tabPickerText: {
    fontSize: 12,
    fontWeight: '700',
    color: colors.accentPrimary,
  },
  tabDropdown: {
    backgroundColor: colors.bgCard,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: colors.borderLight,
    overflow: 'hidden',
    marginBottom: 12,
    ...shadows.elevation2,
  },
  tabDropdownItem: {
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  tabDropdownItemActive: {
    backgroundColor: colors.accentPrimaryLight,
  },
  tabDropdownText: {
    fontSize: 14,
    fontWeight: '500',
    color: colors.textPrimary,
  },
  tabDropdownTextActive: {
    fontWeight: '700',
    color: colors.accentPrimary,
  },
  titleInput: {
    fontSize: 20,
    fontWeight: '700',
    color: colors.textPrimary,
    fontStyle: 'italic',
    marginBottom: 12,
  },
  uploadRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    marginBottom: 16,
  },
  uploadBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: colors.accentPrimary,
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 20,
  },
  uploadBtnText: {
    fontSize: 13,
    fontWeight: '700',
    color: '#FFFFFF',
  },
  mediaCount: {
    fontSize: 12,
    fontWeight: '600',
    color: colors.accentSecondary,
  },
  bodyInput: {
    fontSize: 15,
    color: colors.textPrimary,
    lineHeight: 24,
    minHeight: 120,
  },
  mediaGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginTop: 16,
  },
  mediaItem: {
    width: (SCREEN_WIDTH - 48) / 2,
    aspectRatio: 1,
    borderRadius: 16,
    overflow: 'hidden',
  },
  mediaImage: {
    width: '100%',
    height: '100%',
    resizeMode: 'cover',
  },
  mediaRemove: {
    position: 'absolute',
    top: 8,
    right: 8,
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: 'rgba(0,0,0,0.6)',
    justifyContent: 'center',
    alignItems: 'center',
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
      {/* Header – matches original web design exactly */}
      <View style={styles.header}>
        {/* Top row: location + actions */}
        <View style={styles.topRow}>
          <TouchableOpacity style={styles.locationBtn}>
            <View style={styles.locationIcon}>
              <Ionicons name="location" size={14} color={colors.accentPrimary} />
            </View>
            <Text style={styles.locationText}>{neighborhood}</Text>
            <Ionicons name="chevron-down" size={16} color={colors.textSecondary} />
          </TouchableOpacity>
          <View style={styles.headerActions}>
            <TouchableOpacity
              style={styles.iconBtn}
              onPress={() => router.push('/notifications' as any)}
            >
              <Ionicons name="notifications-outline" size={20} color={colors.textSecondary} />
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.iconBtn}
              onPress={() => router.push('/(tabs)/messages' as any)}
            >
              <Ionicons name="chatbubble-outline" size={19} color={colors.textSecondary} />
            </TouchableOpacity>
            {user && (
              <View style={styles.avatarSmall}>
                {user.profile_image ? (
                  <Image
                    source={{ uri: user.profile_image }}
                    style={{ width: '100%', height: '100%' }}
                  />
                ) : (
                  <Text style={styles.avatarSmallText}>
                    {(user.full_name || 'U')[0].toUpperCase()}
                  </Text>
                )}
              </View>
            )}
          </View>
        </View>

        {/* Tabs – exactly matches original */}
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.tabsRow}
        >
          {TABS.map((tab) => (
            <TouchableOpacity
              key={tab.id}
              style={[styles.tab, activeTab === tab.id && styles.tabActive]}
              onPress={() => setActiveTab(tab.id)}
            >
              <Text
                style={[
                  styles.tabText,
                  activeTab === tab.id && styles.tabTextActive,
                ]}
              >
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

      {/* Feed – article-style list matching original web design */}
      <FlatList
        data={posts}
        keyExtractor={(item) => item.id}
        renderItem={({ item, index }) => (
          <DiscoverPostCard
            post={item}
            onPress={() => router.push(`/post/${item.id}`)}
            featured={index === 0}
          />
        )}
        contentContainerStyle={{ paddingBottom: 100 }}
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

      {/* FAB to compose */}
      <TouchableOpacity
        style={styles.fab}
        onPress={() => setShowComposer(true)}
        activeOpacity={0.85}
      >
        <Ionicons name="pencil" size={22} color="#FFFFFF" />
      </TouchableOpacity>

      {/* Full-screen composer modal */}
      <FullScreenComposer
        visible={showComposer}
        user={user}
        onClose={() => setShowComposer(false)}
        onCreated={() => loadPosts()}
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
  fab: {
    position: 'absolute',
    bottom: 100,
    right: 20,
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: colors.accentPrimary,
    justifyContent: 'center',
    alignItems: 'center',
    ...shadows.elevation3,
  },
});
