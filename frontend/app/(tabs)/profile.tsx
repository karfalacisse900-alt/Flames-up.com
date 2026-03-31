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
  Alert,
  Dimensions,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, borderRadius, shadows } from '../../src/utils/theme';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

export default function ProfileScreen() {
  const router = useRouter();
  const { user, logout } = useAuthStore();
  const [posts, setPosts] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [stats, setStats] = useState({ posts: 0, followers: 0, following: 0 });
  const [showMore, setShowMore] = useState(false);

  useEffect(() => {
    if (user) loadUserData();
  }, [user]);

  const loadUserData = async () => {
    try {
      const [postsRes, userRes] = await Promise.all([
        api.get(`/users/${user?.id}/posts`),
        api.get(`/users/${user?.id}`),
      ]);
      setPosts(postsRes.data);
      setStats({
        posts: userRes.data.posts_count,
        followers: userRes.data.followers_count,
        following: userRes.data.following_count,
      });
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

  const handleLogout = () => {
    Alert.alert('Logout', 'Are you sure you want to logout?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Logout',
        style: 'destructive',
        onPress: async () => {
          await logout();
          router.replace('/(auth)/login');
        },
      },
    ]);
  };

  if (isLoading || !user) {
    return (
      <SafeAreaView style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.accentPrimary} />
      </SafeAreaView>
    );
  }

  // Mock data for interests/looking-for that match the original screenshots
  const interests = user.interests || ['Startups', 'Music', 'Tech', 'Fashion'];
  const lookingFor = user.looking_for || ['Creative collaboration', 'Networking', 'Friends'];
  const personalInfo = {
    age: user.age || '20',
    borough: user.location || 'Bronx',
  };

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <ScrollView
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={onRefresh}
            tintColor={colors.accentPrimary}
          />
        }
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {/* Header */}
        <View style={styles.header}>
          <Text style={styles.headerTitle}>Profile</Text>
          <View style={styles.headerActions}>
            <TouchableOpacity style={styles.headerBtn} onPress={() => router.push('/(tabs)/messages')}>
              <Ionicons name="chatbubble-outline" size={18} color={colors.textPrimary} />
            </TouchableOpacity>
            <TouchableOpacity style={styles.headerBtn} onPress={() => setShowMore(!showMore)}>
              <Ionicons name="ellipsis-horizontal" size={18} color={colors.textPrimary} />
            </TouchableOpacity>
          </View>
        </View>

        {/* More menu */}
        {showMore && (
          <View style={styles.moreMenu}>
            <TouchableOpacity style={styles.moreItem} onPress={() => { setShowMore(false); router.push('/edit-profile'); }}>
              <Ionicons name="create-outline" size={18} color={colors.accentPrimary} />
              <Text style={styles.moreItemText}>Edit Profile</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.moreItem} onPress={() => { setShowMore(false); }}>
              <Ionicons name="library-outline" size={18} color={colors.textSecondary} />
              <Text style={styles.moreItemText}>My Library</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.moreItem} onPress={() => { setShowMore(false); }}>
              <Ionicons name="newspaper-outline" size={18} color={colors.textSecondary} />
              <Text style={styles.moreItemText}>Apply: Local Publisher</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.moreItem} onPress={() => { setShowMore(false); }}>
              <Ionicons name="shield-outline" size={18} color={colors.textSecondary} />
              <Text style={styles.moreItemText}>Admin Panel</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.moreItem} onPress={() => { setShowMore(false); }}>
              <Ionicons name="settings-outline" size={18} color={colors.textSecondary} />
              <Text style={styles.moreItemText}>Settings</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[styles.moreItem, { borderBottomWidth: 0 }]} onPress={() => { setShowMore(false); handleLogout(); }}>
              <Ionicons name="log-out-outline" size={18} color={colors.error} />
              <Text style={[styles.moreItemText, { color: colors.error }]}>Logout</Text>
            </TouchableOpacity>
          </View>
        )}

        {/* Profile Card */}
        <View style={styles.profileCard}>
          {/* Banner overlay */}
          <View style={styles.bannerOverlay} />

          {/* Avatar + Info */}
          <View style={styles.profileRow}>
            <View style={styles.avatarContainer}>
              {user.profile_image ? (
                <Image source={{ uri: user.profile_image }} style={styles.avatar} />
              ) : (
                <View style={styles.avatarPlaceholder}>
                  <Text style={styles.avatarText}>
                    {(user.full_name || 'U')[0].toUpperCase()}
                  </Text>
                </View>
              )}
            </View>
            <View style={styles.profileInfo}>
              <Text style={styles.fullName}>{user.full_name}</Text>
              <Text style={styles.username}>{user.username ? `@${user.username}` : `@${user.email?.split('@')[0]}`}</Text>
              <View style={styles.tagRow}>
                {interests.slice(0, 2).map((item: string) => (
                  <View key={item} style={styles.tag}>
                    <Text style={styles.tagText}>{item}</Text>
                  </View>
                ))}
              </View>
            </View>
          </View>

          {/* Bio */}
          {(user.bio || true) && (
            <View style={styles.bioCard}>
              <Text style={styles.bioText}>
                {user.bio || `Hey! I'm building a new social app called flames-up and I'm inviting a few people to try it early before everyone else.`}
              </Text>
            </View>
          )}

          {/* Stats row */}
          <View style={styles.statsRow}>
            <TouchableOpacity style={styles.statItem}>
              <Text style={styles.statValue}>{stats.posts}</Text>
              <Text style={styles.statLabel}>Posts</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.statItem}>
              <Text style={styles.statValue}>{stats.followers}</Text>
              <Text style={styles.statLabel}>Followers</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.statItem}>
              <Text style={styles.statValue}>{stats.following}</Text>
              <Text style={styles.statLabel}>Following</Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Personal Info Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>PERSONAL INFO</Text>
          <View style={styles.infoCard}>
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>Age</Text>
              <Text style={styles.infoValue}>{personalInfo.age}</Text>
            </View>
            <View style={[styles.infoRow, { borderBottomWidth: 0 }]}>
              <Text style={styles.infoLabel}>Borough</Text>
              <Text style={styles.infoValue}>{personalInfo.borough}</Text>
            </View>
          </View>
        </View>

        {/* Looking For Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>LOOKING FOR</Text>
          <View style={styles.chipContainer}>
            {lookingFor.map((item: string) => (
              <View key={item} style={styles.chipLight}>
                <Text style={styles.chipLightText}>{item}</Text>
              </View>
            ))}
          </View>
        </View>

        {/* Interests Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>INTERESTS</Text>
          <View style={styles.chipContainer}>
            {interests.map((item: string) => (
              <View key={item} style={styles.interestChip}>
                <Text style={styles.interestChipText}>{item}</Text>
              </View>
            ))}
          </View>
        </View>

        {/* Social Links */}
        <View style={styles.section}>
          <View style={styles.socialLinks}>
            <TouchableOpacity style={styles.socialLink}>
              <Ionicons name="globe-outline" size={16} color={colors.accentPrimary} />
              <Text style={styles.socialLinkText}>Website</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.socialLink}>
              <Ionicons name="musical-notes-outline" size={16} color={colors.error} />
              <Text style={styles.socialLinkText}>TikTok</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.socialLink}>
              <Ionicons name="camera-outline" size={16} color={colors.avatarPurple} />
              <Text style={styles.socialLinkText}>Instagram</Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Action Buttons */}
        <View style={styles.actionRow}>
          <TouchableOpacity style={styles.friendsBtn}>
            <Ionicons name="people-outline" size={18} color={colors.accentPrimary} />
            <Text style={styles.friendsBtnText}>Friends</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.moreBtn}>
            <Ionicons name="ellipsis-horizontal" size={20} color={colors.textSecondary} />
          </TouchableOpacity>
        </View>

        {/* Edit Profile Button */}
        <TouchableOpacity
          style={styles.editBtn}
          onPress={() => router.push('/edit-profile')}
        >
          <Ionicons name="create-outline" size={18} color={colors.accentPrimary} />
          <Text style={styles.editBtnText}>Edit Profile</Text>
        </TouchableOpacity>

        {/* Posts Grid */}
        <View style={styles.postsSection}>
          <Text style={styles.postsSectionTitle}>Posts</Text>
          {posts.length === 0 ? (
            <View style={styles.emptyPosts}>
              <Ionicons name="camera-outline" size={48} color={colors.textHint} />
              <Text style={styles.emptyText}>No posts yet</Text>
            </View>
          ) : (
            <View style={styles.postsGrid}>
              {posts.map((post) => (
                <TouchableOpacity
                  key={post.id}
                  style={styles.postThumbnail}
                  onPress={() => router.push(`/post/${post.id}`)}
                >
                  {post.image ? (
                    <Image source={{ uri: post.image }} style={styles.thumbnailImage} />
                  ) : (
                    <View style={styles.textThumbnail}>
                      <Text style={styles.textThumbnailContent} numberOfLines={3}>
                        {post.content}
                      </Text>
                    </View>
                  )}
                </TouchableOpacity>
              ))}
            </View>
          )}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bgApp,
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
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  headerTitle: {
    fontSize: 24,
    fontWeight: '600',
    color: colors.textPrimary,
    fontStyle: 'italic',
  },
  headerActions: {
    flexDirection: 'row',
    gap: 8,
  },
  headerBtn: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: 'rgba(255,255,255,0.9)',
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.borderLight,
    ...shadows.elevation1,
  },
  // More menu
  moreMenu: {
    backgroundColor: '#FFFFFF',
    borderRadius: 16,
    marginHorizontal: 16,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: colors.borderLight,
    overflow: 'hidden',
    ...shadows.elevation2,
  },
  moreItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderLight,
  },
  moreItemText: {
    fontSize: 14,
    fontWeight: '500',
    color: colors.textPrimary,
  },
  // Profile Card
  profileCard: {
    marginHorizontal: 16,
    borderRadius: 28,
    backgroundColor: colors.bgCard,
    borderWidth: 1,
    borderColor: colors.borderLight,
    padding: 16,
    overflow: 'hidden',
    ...shadows.elevation2,
  },
  bannerOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    height: 100,
    backgroundColor: colors.accentPrimaryLight,
    opacity: 0.3,
  },
  profileRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 16,
    paddingTop: 8,
    marginBottom: 16,
  },
  avatarContainer: {
    width: 96,
    height: 96,
    borderRadius: 48,
    borderWidth: 3,
    borderColor: colors.bgCard,
    overflow: 'hidden',
    ...shadows.elevation2,
  },
  avatar: {
    width: '100%',
    height: '100%',
  },
  avatarPlaceholder: {
    width: '100%',
    height: '100%',
    backgroundColor: colors.bgSubtle,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    fontSize: 36,
    fontWeight: '700',
    color: colors.accentPrimary,
  },
  profileInfo: {
    flex: 1,
    paddingTop: 8,
  },
  fullName: {
    fontSize: 26,
    fontWeight: '700',
    color: colors.textPrimary,
    fontStyle: 'italic',
    lineHeight: 32,
  },
  username: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.textHint,
    marginTop: 2,
  },
  tagRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginTop: 8,
  },
  tag: {
    backgroundColor: '#d9eef7',
    paddingHorizontal: 12,
    paddingVertical: 4,
    borderRadius: 12,
  },
  tagText: {
    fontSize: 12,
    fontWeight: '600',
    color: '#2d5b7c',
  },
  // Bio
  bioCard: {
    backgroundColor: colors.bgSubtle,
    borderRadius: 20,
    paddingHorizontal: 16,
    paddingVertical: 12,
    marginBottom: 16,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
  },
  bioText: {
    fontSize: 14,
    color: colors.textPrimary,
    lineHeight: 20,
    fontWeight: '500',
  },
  // Stats
  statsRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    paddingTop: 12,
    borderTopWidth: 1,
    borderTopColor: colors.borderSubtle,
  },
  statItem: {
    alignItems: 'center',
  },
  statValue: {
    fontSize: 18,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  statLabel: {
    fontSize: 12,
    color: colors.textHint,
    marginTop: 2,
  },
  // Sections
  section: {
    marginHorizontal: 16,
    marginTop: 20,
  },
  sectionTitle: {
    fontSize: 13,
    fontWeight: '800',
    color: colors.textPrimary,
    letterSpacing: 0.5,
    marginBottom: 12,
  },
  infoCard: {
    backgroundColor: colors.bgCard,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    overflow: 'hidden',
  },
  infoRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderSubtle,
  },
  infoLabel: {
    fontSize: 15,
    color: colors.textSecondary,
  },
  infoValue: {
    fontSize: 15,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  chipContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  chipLight: {
    backgroundColor: colors.bgCard,
    borderWidth: 1,
    borderColor: colors.borderLight,
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 16,
  },
  chipLightText: {
    fontSize: 13,
    color: colors.textSecondary,
    fontWeight: '500',
  },
  interestChip: {
    backgroundColor: '#d9eef7',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 16,
  },
  interestChipText: {
    fontSize: 13,
    fontWeight: '600',
    color: '#2d5b7c',
  },
  // Social links
  socialLinks: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 16,
  },
  socialLink: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  socialLinkText: {
    fontSize: 14,
    color: colors.textPrimary,
    fontWeight: '500',
  },
  // Actions
  actionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginHorizontal: 16,
    marginTop: 20,
    justifyContent: 'center',
  },
  friendsBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: colors.accentPrimaryLight,
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: colors.accentPrimary,
  },
  friendsBtnText: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.accentPrimary,
  },
  moreBtn: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: colors.bgCard,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  editBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    marginHorizontal: 16,
    marginTop: 12,
    backgroundColor: colors.bgSubtle,
    paddingVertical: 12,
    borderRadius: 16,
  },
  editBtnText: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.accentPrimary,
  },
  // Posts Grid
  postsSection: {
    paddingHorizontal: 16,
    marginTop: 24,
  },
  postsSectionTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: colors.textPrimary,
    fontStyle: 'italic',
    marginBottom: 16,
  },
  emptyPosts: {
    alignItems: 'center',
    paddingVertical: 40,
  },
  emptyText: {
    fontSize: 14,
    color: colors.textHint,
    marginTop: 8,
  },
  postsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
  },
  postThumbnail: {
    width: (SCREEN_WIDTH - 32 - 12) / 2,
    aspectRatio: 1,
    borderRadius: 20,
    overflow: 'hidden',
    backgroundColor: colors.bgCard,
    borderWidth: 1,
    borderColor: colors.borderLight,
    ...shadows.elevation1,
  },
  thumbnailImage: {
    width: '100%',
    height: '100%',
  },
  textThumbnail: {
    flex: 1,
    backgroundColor: colors.bgSubtle,
    padding: 12,
    justifyContent: 'center',
  },
  textThumbnailContent: {
    fontSize: 11,
    color: colors.textSecondary,
    lineHeight: 15,
  },
});
