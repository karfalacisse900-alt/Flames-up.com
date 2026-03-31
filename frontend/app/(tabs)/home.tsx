import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  RefreshControl,
  TouchableOpacity,
  ActivityIndicator,
  ScrollView,
  Image,
  Dimensions,
  Modal,
  TextInput,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { colors, spacing, borderRadius, shadows } from '../../src/utils/theme';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';
import { formatDistanceToNow } from 'date-fns';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

// ─── Community Post Card ─────────────────────────────────────────────────────
function CommunityPostCard({ post, currentUserId, onPress, onUserPress }: any) {
  const [liked, setLiked] = useState(post.liked_by?.includes(currentUserId));
  const [likesCount, setLikesCount] = useState(post.likes_count || 0);

  const handleLike = async () => {
    setLiked(!liked);
    setLikesCount(liked ? likesCount - 1 : likesCount + 1);
    try {
      await api.post(`/posts/${post.id}/like`);
    } catch {
      setLiked(liked);
      setLikesCount(likesCount);
    }
  };

  const timeAgo = post.created_at
    ? formatDistanceToNow(new Date(post.created_at), { addSuffix: false })
    : '';

  const title = post.content?.split('\n')[0] || '';
  const body = post.content?.split('\n').slice(1).join('\n') || '';

  return (
    <TouchableOpacity
      style={cardStyles.container}
      onPress={onPress}
      activeOpacity={0.9}
    >
      {/* Header */}
      <TouchableOpacity
        style={cardStyles.header}
        onPress={onUserPress}
        activeOpacity={0.7}
      >
        <View style={cardStyles.avatarRing}>
          {post.user_profile_image ? (
            <Image
              source={{ uri: post.user_profile_image }}
              style={cardStyles.avatarImage}
            />
          ) : (
            <View style={cardStyles.avatarPlaceholder}>
              <Text style={cardStyles.avatarText}>
                {(post.user_full_name || post.user_username || 'U')[0].toUpperCase()}
              </Text>
            </View>
          )}
        </View>
        <Text style={cardStyles.authorName}>
          {post.user_full_name || post.user_username}
        </Text>
        <Text style={cardStyles.dotSeparator}> · </Text>
        <Text style={cardStyles.categoryLabel}>Community</Text>
      </TouchableOpacity>

      {/* Content area */}
      <View style={cardStyles.contentRow}>
        <View style={cardStyles.textContent}>
          {title ? (
            <Text style={cardStyles.postTitle} numberOfLines={2}>
              {title}
            </Text>
          ) : null}
          {body ? (
            <Text style={cardStyles.postBody} numberOfLines={3}>
              {body}
            </Text>
          ) : (
            <Text style={cardStyles.postBody} numberOfLines={4}>
              {post.content}
            </Text>
          )}
        </View>
        {post.image && (
          <Image
            source={{ uri: post.image }}
            style={cardStyles.thumbnail}
          />
        )}
      </View>

      {/* Footer */}
      <View style={cardStyles.footer}>
        <Text style={cardStyles.dateText}>{timeAgo}</Text>
        <TouchableOpacity
          style={cardStyles.footerAction}
          onPress={handleLike}
        >
          <Ionicons
            name={liked ? 'heart' : 'heart-outline'}
            size={16}
            color={liked ? colors.error : colors.textHint}
          />
          {likesCount > 0 && (
            <Text
              style={[
                cardStyles.footerCount,
                liked && { color: colors.error },
              ]}
            >
              {likesCount}
            </Text>
          )}
        </TouchableOpacity>
        <TouchableOpacity style={cardStyles.footerAction} onPress={onPress}>
          <Ionicons
            name="chatbubble-outline"
            size={15}
            color={colors.textHint}
          />
          {post.comments_count > 0 && (
            <Text style={cardStyles.footerCount}>{post.comments_count}</Text>
          )}
        </TouchableOpacity>
        <TouchableOpacity style={cardStyles.footerAction}>
          <Ionicons name="link-outline" size={15} color={colors.textHint} />
          <Text style={cardStyles.footerCount}>Source</Text>
        </TouchableOpacity>
        <View style={{ flex: 1 }} />
        <TouchableOpacity style={cardStyles.footerAction}>
          <Ionicons
            name="remove-outline"
            size={18}
            color={colors.textHint}
          />
        </TouchableOpacity>
        <TouchableOpacity style={cardStyles.footerAction}>
          <Ionicons
            name="ellipsis-horizontal"
            size={18}
            color={colors.textHint}
          />
        </TouchableOpacity>
      </View>
    </TouchableOpacity>
  );
}

const cardStyles = StyleSheet.create({
  container: {
    backgroundColor: colors.bgCard,
    borderRadius: 24,
    marginHorizontal: 16,
    marginBottom: 12,
    padding: 16,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 12,
  },
  avatarRing: {
    width: 36,
    height: 36,
    borderRadius: 18,
    overflow: 'hidden',
    marginRight: 8,
  },
  avatarImage: {
    width: '100%',
    height: '100%',
  },
  avatarPlaceholder: {
    width: '100%',
    height: '100%',
    backgroundColor: colors.avatarTeal,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '700',
  },
  authorName: {
    fontSize: 14,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  dotSeparator: {
    fontSize: 14,
    color: colors.textHint,
  },
  categoryLabel: {
    fontSize: 14,
    color: colors.textHint,
    fontWeight: '500',
  },
  contentRow: {
    flexDirection: 'row',
    marginBottom: 12,
  },
  textContent: {
    flex: 1,
    paddingRight: 12,
  },
  postTitle: {
    fontSize: 16,
    fontWeight: '800',
    color: colors.textPrimary,
    lineHeight: 22,
    marginBottom: 6,
    textTransform: 'uppercase',
  },
  postBody: {
    fontSize: 14,
    color: colors.textSecondary,
    lineHeight: 20,
  },
  thumbnail: {
    width: 80,
    height: 80,
    borderRadius: 12,
  },
  footer: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingTop: 8,
    borderTopWidth: 1,
    borderTopColor: colors.borderSubtle,
  },
  dateText: {
    fontSize: 12,
    color: colors.textHint,
    marginRight: 16,
  },
  footerAction: {
    flexDirection: 'row',
    alignItems: 'center',
    marginRight: 14,
    paddingVertical: 4,
  },
  footerCount: {
    fontSize: 12,
    color: colors.textHint,
    marginLeft: 4,
  },
});

// ─── Quick Tip Composer ──────────────────────────────────────────────────────
function QuickTipComposer({
  user,
  visible,
  onClose,
}: {
  user: any;
  visible: boolean;
  onClose: () => void;
}) {
  const router = useRouter();

  if (!visible) return null;

  return (
    <View style={composerStyles.container}>
      <View style={composerStyles.headerRow}>
        <Text style={composerStyles.title}>Start post</Text>
        <View style={{ flex: 1 }} />
        <TouchableOpacity
          style={composerStyles.postBtnSmall}
          onPress={() => {
            onClose();
            router.push('/create-post');
          }}
        >
          <Text style={composerStyles.postBtnSmallText}>Post</Text>
        </TouchableOpacity>
        <TouchableOpacity onPress={onClose} style={composerStyles.closeBtn}>
          <Ionicons name="close" size={20} color={colors.textPrimary} />
        </TouchableOpacity>
      </View>

      {/* User row */}
      <View style={composerStyles.userRow}>
        <View style={composerStyles.avatar}>
          {user?.profile_image ? (
            <Image
              source={{ uri: user.profile_image }}
              style={composerStyles.avatarImg}
            />
          ) : (
            <View style={composerStyles.avatarFallback}>
              <Text style={composerStyles.avatarFallbackText}>
                {(user?.full_name || user?.username || 'U')[0].toUpperCase()}
              </Text>
            </View>
          )}
        </View>
        <View>
          <Text style={composerStyles.userName}>{user?.full_name}</Text>
          <TouchableOpacity style={composerStyles.visibilityRow}>
            <Ionicons name="globe-outline" size={12} color={colors.textSecondary} />
            <Text style={composerStyles.visibilityText}>Everyone</Text>
            <Ionicons name="chevron-down" size={12} color={colors.textSecondary} />
          </TouchableOpacity>
        </View>
      </View>

      {/* Placeholder input */}
      <TouchableOpacity
        onPress={() => {
          onClose();
          router.push('/create-post');
        }}
        activeOpacity={0.7}
      >
        <Text style={composerStyles.placeholder}>
          Share a tip, thought or update with the community...
        </Text>
      </TouchableOpacity>

      {/* Action buttons */}
      <View style={composerStyles.actionsRow}>
        <TouchableOpacity
          style={composerStyles.actionBtn}
          onPress={() => {
            onClose();
            router.push('/create-post');
          }}
        >
          <Ionicons name="image-outline" size={22} color={colors.accentSecondary} />
        </TouchableOpacity>
        <TouchableOpacity style={composerStyles.actionBtn}>
          <Ionicons name="camera-outline" size={22} color={colors.info} />
        </TouchableOpacity>
        <TouchableOpacity style={composerStyles.actionBtn}>
          <Ionicons name="document-outline" size={22} color={colors.warning} />
        </TouchableOpacity>
        <View style={{ flex: 1 }} />
        <TouchableOpacity>
          <Ionicons
            name="ellipsis-horizontal"
            size={22}
            color={colors.textHint}
          />
        </TouchableOpacity>
      </View>
    </View>
  );
}

const composerStyles = StyleSheet.create({
  container: {
    backgroundColor: colors.bgCard,
    borderRadius: 24,
    marginHorizontal: 16,
    marginBottom: 12,
    padding: 16,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation2,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
  },
  title: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  postBtnSmall: {
    backgroundColor: colors.accentPrimaryLight,
    borderRadius: 20,
    paddingHorizontal: 16,
    paddingVertical: 8,
    marginRight: 8,
  },
  postBtnSmallText: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.accentPrimary,
  },
  closeBtn: {
    padding: 4,
  },
  userRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
  },
  avatar: {
    width: 44,
    height: 44,
    borderRadius: 22,
    overflow: 'hidden',
    marginRight: 12,
  },
  avatarImg: {
    width: '100%',
    height: '100%',
  },
  avatarFallback: {
    width: '100%',
    height: '100%',
    backgroundColor: colors.avatarTeal,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarFallbackText: {
    color: '#FFFFFF',
    fontSize: 18,
    fontWeight: '700',
  },
  userName: {
    fontSize: 15,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  visibilityRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    marginTop: 2,
  },
  visibilityText: {
    fontSize: 12,
    color: colors.textSecondary,
    fontWeight: '500',
  },
  placeholder: {
    fontSize: 16,
    color: colors.textHint,
    lineHeight: 24,
    marginBottom: 24,
  },
  actionsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderTopWidth: 1,
    borderTopColor: colors.borderSubtle,
    paddingTop: 12,
  },
  actionBtn: {
    padding: 8,
    marginRight: 8,
  },
});

// ─── Main Home Screen ────────────────────────────────────────────────────────
export default function HomeScreen() {
  const router = useRouter();
  const { user } = useAuthStore();
  const [posts, setPosts] = useState<any[]>([]);
  const [statuses, setStatuses] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [showComposer, setShowComposer] = useState(false);
  const [feedFilter, setFeedFilter] = useState('global');

  const loadFeed = async () => {
    try {
      const response = await api.get('/posts/feed');
      setPosts(response.data);
    } catch (error) {
      console.log('Error loading feed:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const loadStatuses = async () => {
    try {
      const response = await api.get('/statuses');
      setStatuses(response.data);
    } catch (error) {
      console.log('Error loading statuses:', error);
    }
  };

  useEffect(() => {
    loadFeed();
    loadStatuses();
  }, []);

  const onRefresh = useCallback(async () => {
    setIsRefreshing(true);
    await Promise.all([loadFeed(), loadStatuses()]);
    setIsRefreshing(false);
  }, []);

  const greeting = () => {
    const h = new Date().getHours();
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  };

  const firstName = user?.full_name?.split(' ')[0] || '';

  const renderHeader = () => (
    <View>
      {/* App Header */}
      <View style={styles.header}>
        <View>
          <View style={styles.logoRow}>
            <View style={styles.logoIcon}>
              <Ionicons name="flame" size={14} color={colors.flameGold} />
            </View>
            <Text style={styles.logoText}>flames-up</Text>
          </View>
          <Text style={styles.greeting}>
            {greeting().toUpperCase()}
            {firstName ? `, ${firstName.toUpperCase()}` : ''}
          </Text>
        </View>
        <View style={styles.headerActions}>
          <TouchableOpacity
            style={styles.headerBtn}
            onPress={() => router.push('/(tabs)/discover')}
          >
            <Ionicons name="search" size={18} color={colors.accentPrimary} />
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.headerBtn}
            onPress={() => router.push('/notifications')}
          >
            <Ionicons
              name="notifications-outline"
              size={18}
              color={colors.accentPrimary}
            />
          </TouchableOpacity>
          {user && (
            <TouchableOpacity onPress={() => router.push('/(tabs)/profile')}>
              <View style={styles.headerAvatar}>
                {user.profile_image ? (
                  <Image
                    source={{ uri: user.profile_image }}
                    style={{ width: '100%', height: '100%' }}
                  />
                ) : (
                  <Text style={styles.headerAvatarText}>
                    {(user.full_name || 'U')[0].toUpperCase()}
                  </Text>
                )}
              </View>
            </TouchableOpacity>
          )}
        </View>
      </View>

      {/* Status/Story Bar */}
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.statusBar}
      >
        {/* Your Story button */}
        <TouchableOpacity
          style={styles.storyItem}
          onPress={() => router.push('/create-status')}
        >
          <View style={styles.storyAvatarAdd}>
            {user?.profile_image ? (
              <Image
                source={{ uri: user.profile_image }}
                style={styles.storyAvatarImg}
              />
            ) : (
              <View style={styles.storyAvatarFallback}>
                <Text style={styles.storyAvatarFallbackText}>
                  {(user?.full_name || 'U')[0].toUpperCase()}
                </Text>
              </View>
            )}
            <View style={styles.storyPlusBadge}>
              <Ionicons name="add" size={12} color="#FFFFFF" strokeWidth={3} />
            </View>
          </View>
          <Text style={styles.storyName}>Your Story</Text>
        </TouchableOpacity>

        {/* Other stories */}
        {statuses.map((status: any, idx: number) => (
          <TouchableOpacity key={status.id || idx} style={styles.storyItem}>
            <View style={styles.storyRing}>
              <View style={styles.storyRingInner}>
                {status.user_profile_image ? (
                  <Image
                    source={{ uri: status.user_profile_image }}
                    style={styles.storyAvatarImg}
                  />
                ) : (
                  <View
                    style={[
                      styles.storyAvatarFallback,
                      { backgroundColor: colors.avatarPurple },
                    ]}
                  >
                    <Text style={styles.storyAvatarFallbackText}>
                      {(status.user_full_name || 'U')[0].toUpperCase()}
                    </Text>
                  </View>
                )}
              </View>
            </View>
            <Text style={styles.storyName} numberOfLines={1}>
              {status.user_full_name?.split(' ')[0] || 'User'}
            </Text>
          </TouchableOpacity>
        ))}
      </ScrollView>

      {/* Divider */}
      <View style={styles.divider} />

      {/* Listen, Don't Judge Banner */}
      <TouchableOpacity
        style={styles.bannerContainer}
        activeOpacity={0.9}
      >
        <LinearGradient
          colors={[colors.gradientStart, colors.gradientEnd]}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 1 }}
          style={styles.bannerGradient}
        >
          <View style={styles.bannerIconCircle}>
            <Text style={{ fontSize: 24 }}>🤍</Text>
          </View>
          <View style={styles.bannerTextContent}>
            <Text style={styles.bannerTitle}>Listen, Don't Judge</Text>
            <Text style={styles.bannerSubtitle}>
              Share openly in a judgment-free space
            </Text>
          </View>
          <View style={styles.bannerArrow}>
            <Ionicons name="chevron-forward" size={16} color="#FFFFFF" />
          </View>
        </LinearGradient>
      </TouchableOpacity>

      {/* Divider */}
      <View style={styles.divider} />

      {/* Feed Header */}
      <View style={styles.feedHeader}>
        <TouchableOpacity style={styles.menuBtn}>
          <Ionicons name="menu" size={18} color={colors.textSecondary} />
        </TouchableOpacity>

        <View style={{ flex: 1 }} />

        {/* Global / Location Filter */}
        <TouchableOpacity style={styles.filterPill}>
          <Ionicons name="globe-outline" size={14} color={feedFilter === 'global' ? colors.textSecondary : '#FFFFFF'} />
          <Text style={styles.filterText}>Global</Text>
          <Ionicons name="chevron-down" size={14} color={colors.textSecondary} />
        </TouchableOpacity>

        {/* Post Button */}
        {user && (
          <TouchableOpacity
            style={styles.postBtn}
            onPress={() => setShowComposer(!showComposer)}
          >
            <Text style={styles.postBtnText}>Post</Text>
          </TouchableOpacity>
        )}
      </View>

      {/* Quick Tip Composer */}
      <QuickTipComposer
        user={user}
        visible={showComposer}
        onClose={() => setShowComposer(false)}
      />
    </View>
  );

  const renderPost = ({ item }: { item: any }) => (
    <CommunityPostCard
      post={item}
      currentUserId={user?.id || ''}
      onPress={() => router.push(`/post/${item.id}`)}
      onUserPress={() => router.push(`/user/${item.user_id}`)}
    />
  );

  if (isLoading) {
    return (
      <SafeAreaView style={styles.loadingContainer} edges={['top']}>
        <ActivityIndicator size="large" color={colors.accentPrimary} />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <FlatList
        data={posts}
        renderItem={renderPost}
        keyExtractor={(item) => item.id}
        ListHeaderComponent={renderHeader}
        ListEmptyComponent={
          <View style={styles.emptyContainer}>
            <Text style={{ fontSize: 48, marginBottom: 12 }}>💬</Text>
            <Text style={styles.emptyTitle}>Start the conversation</Text>
            <Text style={styles.emptyText}>
              Be the first to share something here!
            </Text>
            <TouchableOpacity
              style={styles.createFirstBtn}
              onPress={() => router.push('/create-post')}
            >
              <Text style={styles.createFirstBtnText}>Create First Post</Text>
            </TouchableOpacity>
          </View>
        }
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={onRefresh}
            tintColor={colors.accentPrimary}
          />
        }
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ paddingBottom: 100 }}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#FFFFFF',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.bgApp,
  },
  // Header
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderSubtle,
  },
  logoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 2,
  },
  logoIcon: {
    width: 28,
    height: 28,
    borderRadius: 10,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 8,
    backgroundColor: colors.flameDark,
  },
  logoText: {
    fontSize: 18,
    fontWeight: '700',
    fontStyle: 'italic',
    color: colors.textPrimary,
    letterSpacing: -0.5,
  },
  greeting: {
    fontSize: 11,
    fontWeight: '500',
    color: colors.textHint,
    letterSpacing: 0.8,
    marginLeft: 2,
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  headerBtn: {
    width: 40,
    height: 40,
    borderRadius: 14,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.bgCard,
    borderWidth: 1.5,
    borderColor: colors.borderLight,
  },
  headerAvatar: {
    width: 40,
    height: 40,
    borderRadius: 14,
    overflow: 'hidden',
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.accentSecondary,
  },
  headerAvatarText: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '800',
  },
  // Status Bar
  statusBar: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    gap: 12,
  },
  storyItem: {
    alignItems: 'center',
    width: 68,
  },
  storyAvatarAdd: {
    width: 62,
    height: 62,
    borderRadius: 31,
    borderWidth: 2.5,
    borderColor: colors.borderLight,
    overflow: 'visible',
    justifyContent: 'center',
    alignItems: 'center',
  },
  storyAvatarImg: {
    width: '100%',
    height: '100%',
    borderRadius: 31,
  },
  storyAvatarFallback: {
    width: '100%',
    height: '100%',
    borderRadius: 31,
    backgroundColor: colors.avatarTeal,
    justifyContent: 'center',
    alignItems: 'center',
  },
  storyAvatarFallbackText: {
    color: '#FFFFFF',
    fontSize: 18,
    fontWeight: '700',
  },
  storyPlusBadge: {
    position: 'absolute',
    bottom: -2,
    right: -2,
    width: 20,
    height: 20,
    borderRadius: 10,
    backgroundColor: colors.accentPrimary,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: '#FFFFFF',
  },
  storyRing: {
    width: 62,
    height: 62,
    borderRadius: 31,
    padding: 2.5,
    backgroundColor: colors.storyRingMid,
    overflow: 'hidden',
  },
  storyRingInner: {
    width: '100%',
    height: '100%',
    borderRadius: 28,
    borderWidth: 2,
    borderColor: '#FFFFFF',
    overflow: 'hidden',
  },
  storyName: {
    fontSize: 11,
    fontWeight: '600',
    color: colors.textSecondary,
    marginTop: 6,
    textAlign: 'center',
    maxWidth: 64,
  },
  // Divider
  divider: {
    height: 1,
    backgroundColor: colors.borderSubtle,
  },
  // Banner
  bannerContainer: {
    paddingHorizontal: 16,
    paddingVertical: 16,
  },
  bannerGradient: {
    borderRadius: 24,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 20,
  },
  bannerIconCircle: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: 'rgba(255,255,255,0.2)',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 16,
  },
  bannerTextContent: {
    flex: 1,
  },
  bannerTitle: {
    fontSize: 16,
    fontWeight: '700',
    color: '#FFFFFF',
    fontStyle: 'italic',
    marginBottom: 4,
  },
  bannerSubtitle: {
    fontSize: 12,
    color: 'rgba(255,255,255,0.8)',
    lineHeight: 16,
  },
  bannerArrow: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: 'rgba(255,255,255,0.2)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  // Feed Header
  feedHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderSubtle,
  },
  menuBtn: {
    width: 44,
    height: 44,
    borderRadius: 14,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.bgSubtle,
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  filterPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: colors.bgSubtle,
    borderWidth: 1,
    borderColor: colors.borderLight,
    marginRight: 8,
  },
  filterText: {
    fontSize: 12,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  postBtn: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: colors.accentPrimary,
  },
  postBtnText: {
    fontSize: 13,
    fontWeight: '700',
    color: '#FFFFFF',
  },
  // Empty state
  emptyContainer: {
    alignItems: 'center',
    paddingVertical: 60,
    paddingHorizontal: 32,
  },
  emptyTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: colors.textPrimary,
    fontStyle: 'italic',
    marginBottom: 6,
  },
  emptyText: {
    fontSize: 14,
    color: colors.textHint,
    marginBottom: 20,
    textAlign: 'center',
  },
  createFirstBtn: {
    paddingHorizontal: 24,
    paddingVertical: 14,
    borderRadius: 20,
    backgroundColor: colors.accentPrimary,
  },
  createFirstBtnText: {
    fontSize: 14,
    fontWeight: '700',
    color: '#FFFFFF',
  },
});
