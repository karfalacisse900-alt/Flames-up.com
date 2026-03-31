import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Image,
  ActivityIndicator,
  RefreshControl,
  FlatList,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, borderRadius } from '../../src/utils/theme';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';
import PostCard from '../../src/components/PostCard';

export default function UserProfileScreen() {
  const router = useRouter();
  const { id: userId } = useLocalSearchParams<{ id: string }>();
  const { user: currentUser } = useAuthStore();
  const [userProfile, setUserProfile] = useState<any>(null);
  const [posts, setPosts] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isFollowing, setIsFollowing] = useState(false);
  const [isFollowLoading, setIsFollowLoading] = useState(false);

  useEffect(() => {
    loadUserData();
  }, [userId]);

  const loadUserData = async () => {
    try {
      const [userRes, postsRes] = await Promise.all([
        api.get(`/users/${userId}`),
        api.get(`/users/${userId}/posts`),
      ]);
      setUserProfile(userRes.data);
      setPosts(postsRes.data);
      setIsFollowing(userRes.data.is_following);
    } catch (error) {
      console.log('Error loading user data:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const onRefresh = async () => {
    setIsRefreshing(true);
    await loadUserData();
    setIsRefreshing(false);
  };

  const handleFollow = async () => {
    if (isFollowLoading) return;
    setIsFollowLoading(true);

    try {
      const response = await api.post(`/users/${userId}/follow`);
      setIsFollowing(response.data.following);
      // Update follower count
      setUserProfile((prev: any) => ({
        ...prev,
        followers_count: prev.followers_count + (response.data.following ? 1 : -1),
      }));
    } catch (error) {
      console.log('Error following user:', error);
    } finally {
      setIsFollowLoading(false);
    }
  };

  const handleMessage = () => {
    router.push(`/conversation/${userId}`);
  };

  const renderHeader = () => (
    <View>
      {/* Profile Info */}
      <View style={styles.profileSection}>
        {userProfile?.profile_image ? (
          <Image source={{ uri: userProfile.profile_image }} style={styles.avatar} />
        ) : (
          <View style={styles.avatarPlaceholder}>
            <Text style={styles.avatarText}>{userProfile?.username[0].toUpperCase()}</Text>
          </View>
        )}
        <Text style={styles.fullName}>{userProfile?.full_name}</Text>
        <Text style={styles.username}>@{userProfile?.username}</Text>
        {userProfile?.bio && <Text style={styles.bio}>{userProfile.bio}</Text>}
        {userProfile?.location && (
          <View style={styles.locationRow}>
            <Ionicons name="location-outline" size={14} color={colors.textTertiary} />
            <Text style={styles.locationText}>{userProfile.location}</Text>
          </View>
        )}
      </View>

      {/* Stats */}
      <View style={styles.statsSection}>
        <View style={styles.statItem}>
          <Text style={styles.statValue}>{userProfile?.posts_count || 0}</Text>
          <Text style={styles.statLabel}>Posts</Text>
        </View>
        <View style={styles.statDivider} />
        <View style={styles.statItem}>
          <Text style={styles.statValue}>{userProfile?.followers_count || 0}</Text>
          <Text style={styles.statLabel}>Followers</Text>
        </View>
        <View style={styles.statDivider} />
        <View style={styles.statItem}>
          <Text style={styles.statValue}>{userProfile?.following_count || 0}</Text>
          <Text style={styles.statLabel}>Following</Text>
        </View>
      </View>

      {/* Action Buttons */}
      {userId !== currentUser?.id && (
        <View style={styles.actionSection}>
          <TouchableOpacity
            style={[styles.followButton, isFollowing && styles.followingButton]}
            onPress={handleFollow}
            disabled={isFollowLoading}
          >
            {isFollowLoading ? (
              <ActivityIndicator size="small" color={isFollowing ? colors.primary : colors.textInverse} />
            ) : (
              <Text style={[styles.followButtonText, isFollowing && styles.followingButtonText]}>
                {isFollowing ? 'Following' : 'Follow'}
              </Text>
            )}
          </TouchableOpacity>
          <TouchableOpacity style={styles.messageButton} onPress={handleMessage}>
            <Ionicons name="chatbubble-outline" size={20} color={colors.textPrimary} />
          </TouchableOpacity>
        </View>
      )}

      {/* Posts Section Title */}
      <View style={styles.postsHeader}>
        <Text style={styles.postsTitle}>Posts</Text>
      </View>
    </View>
  );

  if (isLoading) {
    return (
      <SafeAreaView style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={24} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>{userProfile?.username}</Text>
        <View style={{ width: 24 }} />
      </View>

      <FlatList
        data={posts}
        renderItem={({ item }) => (
          <PostCard
            post={item}
            currentUserId={currentUser?.id || ''}
            onPress={() => router.push(`/post/${item.id}`)}
            onUserPress={() => {}}
          />
        )}
        keyExtractor={(item) => item.id}
        ListHeaderComponent={renderHeader}
        ListEmptyComponent={
          <View style={styles.emptyContainer}>
            <Ionicons name="camera-outline" size={48} color={colors.textTertiary} />
            <Text style={styles.emptyText}>No posts yet</Text>
          </View>
        }
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={onRefresh}
            tintColor={colors.primary}
          />
        }
        showsVerticalScrollIndicator={false}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.background,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderLight,
  },
  headerTitle: {
    fontSize: 17,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  profileSection: {
    alignItems: 'center',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.lg,
  },
  avatar: {
    width: 100,
    height: 100,
    borderRadius: 50,
    marginBottom: spacing.md,
  },
  avatarPlaceholder: {
    width: 100,
    height: 100,
    borderRadius: 50,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: spacing.md,
  },
  avatarText: {
    color: colors.textInverse,
    fontSize: 40,
    fontWeight: '600',
  },
  fullName: {
    fontSize: 22,
    fontWeight: '700',
    color: colors.textPrimary,
    marginBottom: 4,
  },
  username: {
    fontSize: 15,
    color: colors.textSecondary,
    marginBottom: spacing.sm,
  },
  bio: {
    fontSize: 14,
    color: colors.textPrimary,
    textAlign: 'center',
    lineHeight: 20,
    marginBottom: spacing.sm,
  },
  locationRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  locationText: {
    fontSize: 13,
    color: colors.textTertiary,
    marginLeft: 4,
  },
  statsSection: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: spacing.md,
    marginHorizontal: spacing.md,
    backgroundColor: colors.backgroundSecondary,
    borderRadius: borderRadius.lg,
  },
  statItem: {
    flex: 1,
    alignItems: 'center',
  },
  statValue: {
    fontSize: 20,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  statLabel: {
    fontSize: 12,
    color: colors.textSecondary,
    marginTop: 2,
  },
  statDivider: {
    width: 1,
    height: 30,
    backgroundColor: colors.border,
  },
  actionSection: {
    flexDirection: 'row',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
  },
  followButton: {
    flex: 1,
    backgroundColor: colors.primary,
    borderRadius: borderRadius.md,
    paddingVertical: spacing.sm,
    alignItems: 'center',
    marginRight: spacing.sm,
  },
  followingButton: {
    backgroundColor: colors.backgroundSecondary,
    borderWidth: 1,
    borderColor: colors.border,
  },
  followButtonText: {
    fontSize: 15,
    fontWeight: '600',
    color: colors.textInverse,
  },
  followingButtonText: {
    color: colors.textPrimary,
  },
  messageButton: {
    width: 44,
    height: 44,
    backgroundColor: colors.backgroundSecondary,
    borderRadius: borderRadius.md,
    justifyContent: 'center',
    alignItems: 'center',
  },
  postsHeader: {
    paddingHorizontal: spacing.md,
    paddingTop: spacing.md,
    paddingBottom: spacing.sm,
    borderTopWidth: 1,
    borderTopColor: colors.borderLight,
  },
  postsTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  emptyContainer: {
    alignItems: 'center',
    paddingVertical: spacing.xxl,
  },
  emptyText: {
    fontSize: 14,
    color: colors.textSecondary,
    marginTop: spacing.sm,
  },
});
