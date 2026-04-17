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
  Dimensions,
  Alert,
  Modal,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, shadows } from '../../src/utils/theme';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

const REPORT_REASONS = [
  { id: 'spam', label: 'Spam' },
  { id: 'harassment', label: 'Harassment or bullying' },
  { id: 'fake_profile', label: 'Fake profile' },
  { id: 'hate_speech', label: 'Hate speech' },
  { id: 'other', label: 'Other' },
];

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
  const [showMenu, setShowMenu] = useState(false);
  const [showReport, setShowReport] = useState(false);
  const [friendStatus, setFriendStatus] = useState<string>('none');
  const [friendRequestId, setFriendRequestId] = useState<string | null>(null);
  const [friendLoading, setFriendLoading] = useState(false);

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
      
      // Load friendship status
      try {
        const friendRes = await api.get(`/friends/status/${userId}`);
        setFriendStatus(friendRes.data.status);
        if (friendRes.data.request_id) setFriendRequestId(friendRes.data.request_id);
      } catch {}
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

  const handleReport = async (reason: string) => {
    try {
      await api.post('/reports', {
        target_type: 'user',
        target_id: userId,
        reason,
      });
      Alert.alert('Report Submitted', 'Thank you for helping keep our community safe.');
    } catch {
      Alert.alert('Error', 'Could not submit report. Please try again.');
    }
    setShowReport(false);
  };

  const handleFriendRequest = async () => {
    if (friendLoading) return;
    setFriendLoading(true);
    try {
      if (friendStatus === 'none') {
        const res = await api.post(`/friends/request/${userId}`);
        if (res.data.status === 'accepted') {
          setFriendStatus('friends');
          Alert.alert('Friends!', 'You are now friends!');
        } else {
          setFriendStatus('pending_sent');
          setFriendRequestId(res.data.request_id);
        }
      } else if (friendStatus === 'pending_received' && friendRequestId) {
        await api.post(`/friends/accept/${friendRequestId}`);
        setFriendStatus('friends');
        Alert.alert('Friends!', 'You are now friends!');
      } else if (friendStatus === 'friends') {
        Alert.alert(
          'Remove Friend',
          'Are you sure you want to remove this friend?',
          [
            { text: 'Cancel', style: 'cancel' },
            {
              text: 'Remove',
              style: 'destructive',
              onPress: async () => {
                await api.delete(`/friends/${userId}`);
                setFriendStatus('none');
              },
            },
          ]
        );
      }
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.detail || 'Something went wrong');
    } finally {
      setFriendLoading(false);
    }
  };

  if (isLoading) {
    return (
      <SafeAreaView style={s.loadingContainer}>
        <ActivityIndicator size="large" color={colors.accentPrimary} />
      </SafeAreaView>
    );
  }

  if (!userProfile) {
    return (
      <SafeAreaView style={s.loadingContainer}>
        <Ionicons name="person-outline" size={56} color={colors.textHint} />
        <Text style={{ fontSize: 16, color: colors.textHint, marginTop: 12 }}>User not found</Text>
        <TouchableOpacity style={s.goBackBtn} onPress={() => router.back()}>
          <Text style={s.goBackBtnText}>Go Back</Text>
        </TouchableOpacity>
      </SafeAreaView>
    );
  }

  const isOwnProfile = userId === currentUser?.id;
  const interests: string[] = (() => {
    try {
      const raw = userProfile.interests;
      if (Array.isArray(raw)) return raw;
      if (typeof raw === 'string') return JSON.parse(raw);
      return [];
    } catch { return []; }
  })();
  const lookingFor: string[] = (() => {
    try {
      const raw = userProfile.looking_for;
      if (Array.isArray(raw)) return raw;
      if (typeof raw === 'string') return JSON.parse(raw);
      return [];
    } catch { return []; }
  })();
  const personalInfo = {
    age: userProfile.age || '—',
    borough: userProfile.location || '—',
  };

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      {/* Nav Header */}
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={s.headerTitle}>{userProfile.username || userProfile.full_name}</Text>
        <TouchableOpacity style={s.menuBtn} onPress={() => setShowMenu(true)}>
          <Ionicons name="ellipsis-horizontal" size={20} color={colors.textPrimary} />
        </TouchableOpacity>
      </View>

      {/* Action Sheet */}
      <Modal visible={showMenu} transparent animationType="fade" onRequestClose={() => setShowMenu(false)}>
        <TouchableOpacity style={s.overlay} activeOpacity={1} onPress={() => setShowMenu(false)}>
          <View style={s.sheet}>
            <View style={s.sheetHandle} />
            <TouchableOpacity style={s.sheetItem} onPress={() => { setShowMenu(false); setShowReport(true); }}>
              <Ionicons name="flag-outline" size={22} color={colors.error} />
              <Text style={[s.sheetItemText, { color: colors.error }]}>Report User</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.sheetItem} onPress={() => { setShowMenu(false); Alert.alert('Blocked', 'This user has been blocked.'); }}>
              <Ionicons name="ban-outline" size={22} color={colors.textPrimary} />
              <Text style={s.sheetItemText}>Block User</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[s.sheetItem, { borderBottomWidth: 0 }]} onPress={() => { setShowMenu(false); }}>
              <Ionicons name="share-outline" size={22} color={colors.textPrimary} />
              <Text style={s.sheetItemText}>Share Profile</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.sheetCancel} onPress={() => setShowMenu(false)}>
              <Text style={s.sheetCancelText}>Cancel</Text>
            </TouchableOpacity>
          </View>
        </TouchableOpacity>
      </Modal>

      {/* Report Modal */}
      <Modal visible={showReport} transparent animationType="slide" onRequestClose={() => setShowReport(false)}>
        <TouchableOpacity style={s.overlay} activeOpacity={1} onPress={() => setShowReport(false)}>
          <View style={s.reportSheet}>
            <View style={s.sheetHandle} />
            <Text style={s.reportTitle}>Report this user</Text>
            <Text style={s.reportSubtitle}>Your report is anonymous.</Text>
            {REPORT_REASONS.map((r) => (
              <TouchableOpacity key={r.id} style={s.reportItem} onPress={() => handleReport(r.id)}>
                <Text style={s.reportItemText}>{r.label}</Text>
                <Ionicons name="chevron-forward" size={16} color={colors.textHint} />
              </TouchableOpacity>
            ))}
          </View>
        </TouchableOpacity>
      </Modal>

      <ScrollView
        refreshControl={
          <RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} tintColor={colors.accentPrimary} />
        }
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {/* Profile Card – matching own profile style */}
        <View style={s.profileCard}>
          <View style={s.bannerOverlay} />
          <View style={s.profileRow}>
            <View style={s.avatarContainer}>
              {userProfile.profile_image ? (
                <Image source={{ uri: userProfile.profile_image }} style={s.avatar} />
              ) : (
                <View style={s.avatarPlaceholder}>
                  <Text style={s.avatarText}>
                    {(userProfile.full_name || 'U')[0].toUpperCase()}
                  </Text>
                </View>
              )}
            </View>
            <View style={s.profileInfo}>
              <Text style={s.fullName}>{userProfile.full_name}</Text>
              <Text style={s.username}>@{userProfile.username || userProfile.email?.split('@')[0]}</Text>
              <View style={s.tagRow}>
                {interests.slice(0, 2).map((item: string) => (
                  <View key={item} style={s.tag}>
                    <Text style={s.tagText}>{item}</Text>
                  </View>
                ))}
              </View>
            </View>
          </View>

          {/* Bio */}
          {(userProfile.bio || true) && (
            <View style={s.bioCard}>
              <Text style={s.bioText}>
                {userProfile.bio || 'No bio yet.'}
              </Text>
            </View>
          )}

          {/* Stats */}
          <View style={s.statsRow}>
            <View style={s.statItem}>
              <Text style={s.statValue}>{userProfile.posts_count || 0}</Text>
              <Text style={s.statLabel}>Posts</Text>
            </View>
            <View style={s.statItem}>
              <Text style={s.statValue}>{userProfile.followers_count || 0}</Text>
              <Text style={s.statLabel}>Followers</Text>
            </View>
            <View style={s.statItem}>
              <Text style={s.statValue}>{userProfile.following_count || 0}</Text>
              <Text style={s.statLabel}>Following</Text>
            </View>
          </View>
        </View>

        {/* Personal Info */}
        <View style={s.section}>
          <Text style={s.sectionTitle}>PERSONAL INFO</Text>
          <View style={s.infoCard}>
            <View style={s.infoRow}>
              <Text style={s.infoLabel}>Age</Text>
              <Text style={s.infoValue}>{personalInfo.age}</Text>
            </View>
            <View style={[s.infoRow, { borderBottomWidth: 0 }]}>
              <Text style={s.infoLabel}>Borough</Text>
              <Text style={s.infoValue}>{personalInfo.borough}</Text>
            </View>
          </View>
        </View>

        {/* Looking For */}
        <View style={s.section}>
          <Text style={s.sectionTitle}>LOOKING FOR</Text>
          <View style={s.chipContainer}>
            {lookingFor.map((item: string) => (
              <View key={item} style={s.chipLight}>
                <Text style={s.chipLightText}>{item}</Text>
              </View>
            ))}
          </View>
        </View>

        {/* Interests */}
        <View style={s.section}>
          <Text style={s.sectionTitle}>INTERESTS</Text>
          <View style={s.chipContainer}>
            {interests.map((item: string) => (
              <View key={item} style={s.interestChip}>
                <Text style={s.interestChipText}>{item}</Text>
              </View>
            ))}
          </View>
        </View>

        {/* Social Links */}
        <View style={s.section}>
          <View style={s.socialLinks}>
            <TouchableOpacity style={s.socialLink}>
              <Ionicons name="globe-outline" size={16} color={colors.accentPrimary} />
              <Text style={s.socialLinkText}>Website</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.socialLink}>
              <Ionicons name="musical-notes-outline" size={16} color={colors.error} />
              <Text style={s.socialLinkText}>TikTok</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.socialLink}>
              <Ionicons name="camera-outline" size={16} color={colors.avatarPurple} />
              <Text style={s.socialLinkText}>Instagram</Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Action Buttons */}
        {!isOwnProfile && (
          <View style={s.actionRow}>
            <TouchableOpacity
              style={[s.followBtn, isFollowing && s.followingBtn]}
              onPress={handleFollow}
              disabled={isFollowLoading}
            >
              {isFollowLoading ? (
                <ActivityIndicator size="small" color={isFollowing ? colors.accentPrimary : '#FFFFFF'} />
              ) : (
                <>
                  <Ionicons
                    name={isFollowing ? 'checkmark-outline' : 'person-add-outline'}
                    size={18}
                    color={isFollowing ? colors.accentPrimary : '#FFFFFF'}
                  />
                  <Text style={[s.followBtnText, isFollowing && s.followingBtnText]}>
                    {isFollowing ? 'Following' : 'Follow'}
                  </Text>
                </>
              )}
            </TouchableOpacity>
            <TouchableOpacity
              style={[
                s.friendBtn,
                friendStatus === 'friends' && s.friendBtnActive,
                friendStatus === 'pending_sent' && s.friendBtnPending,
              ]}
              onPress={handleFriendRequest}
              disabled={friendLoading}
            >
              {friendLoading ? (
                <ActivityIndicator size="small" color={colors.accentPrimary} />
              ) : (
                <>
                  <Ionicons
                    name={
                      friendStatus === 'friends' ? 'people' :
                      friendStatus === 'pending_sent' ? 'hourglass-outline' :
                      friendStatus === 'pending_received' ? 'checkmark-circle-outline' :
                      'person-add-outline'
                    }
                    size={18}
                    color={friendStatus === 'friends' ? '#22C55E' : colors.accentPrimary}
                  />
                  <Text style={[
                    s.friendBtnText,
                    friendStatus === 'friends' && { color: '#22C55E' },
                  ]}>
                    {friendStatus === 'friends' ? 'Friends' :
                     friendStatus === 'pending_sent' ? 'Pending' :
                     friendStatus === 'pending_received' ? 'Accept' :
                     'Add Friend'}
                  </Text>
                </>
              )}
            </TouchableOpacity>
          </View>
        )}
        {!isOwnProfile && (
          <View style={[s.actionRow, { marginTop: 8 }]}>
            <TouchableOpacity
              style={s.messageBtn}
              onPress={() => router.push(`/conversation/${userId}` as any)}
            >
              <Ionicons name="chatbubble-outline" size={18} color={colors.accentPrimary} />
              <Text style={s.messageBtnText}>Message</Text>
            </TouchableOpacity>
          </View>
        )}

        {/* Posts Grid */}
        <View style={s.postsSection}>
          <Text style={s.postsSectionTitle}>Posts</Text>
          {posts.length === 0 ? (
            <View style={s.emptyPosts}>
              <Ionicons name="camera-outline" size={48} color={colors.textHint} />
              <Text style={s.emptyText}>No posts yet</Text>
            </View>
          ) : (
            <View style={s.postsGrid}>
              {posts.map((post) => (
                <TouchableOpacity
                  key={post.id}
                  style={s.postThumbnail}
                  onPress={() => router.push(`/post/${post.id}`)}
                >
                  {post.image ? (
                    <Image source={{ uri: post.image }} style={s.thumbnailImage} />
                  ) : (
                    <View style={s.textThumbnail}>
                      <Text style={s.textThumbnailContent} numberOfLines={3}>
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

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bgApp },
  loadingContainer: {
    flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: colors.bgApp,
  },
  goBackBtn: {
    marginTop: 16, paddingHorizontal: 20, paddingVertical: 10,
    backgroundColor: colors.accentPrimary, borderRadius: 20,
  },
  goBackBtnText: { color: '#FFFFFF', fontSize: 14, fontWeight: '600' },

  // Header
  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 16, paddingVertical: 8,
    borderBottomWidth: 1, borderBottomColor: colors.borderSubtle,
  },
  backBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 17, fontWeight: '700', color: colors.textPrimary, fontStyle: 'italic' },
  menuBtn: {
    width: 44, height: 44, borderRadius: 22, backgroundColor: colors.bgSubtle,
    justifyContent: 'center', alignItems: 'center',
  },

  // Action Sheets
  overlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.4)', justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: '#FFFFFF', borderTopLeftRadius: 20, borderTopRightRadius: 20,
    paddingTop: 8, paddingBottom: 34,
  },
  sheetHandle: {
    width: 40, height: 4, borderRadius: 2, backgroundColor: colors.borderLight,
    alignSelf: 'center', marginBottom: 12,
  },
  sheetItem: {
    flexDirection: 'row', alignItems: 'center', gap: 14,
    paddingHorizontal: 20, paddingVertical: 16,
    borderBottomWidth: 1, borderBottomColor: colors.borderSubtle,
  },
  sheetItemText: { fontSize: 16, fontWeight: '500', color: colors.textPrimary },
  sheetCancel: { alignItems: 'center', paddingVertical: 16, marginTop: 4 },
  sheetCancelText: { fontSize: 16, fontWeight: '600', color: colors.textHint },
  reportSheet: {
    backgroundColor: '#FFFFFF', borderTopLeftRadius: 20, borderTopRightRadius: 20,
    paddingTop: 8, paddingBottom: 34,
  },
  reportTitle: {
    fontSize: 18, fontWeight: '700', color: colors.textPrimary,
    paddingHorizontal: 20, marginBottom: 4,
  },
  reportSubtitle: {
    fontSize: 13, color: colors.textHint, paddingHorizontal: 20, marginBottom: 16,
  },
  reportItem: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 20, paddingVertical: 15,
    borderTopWidth: 1, borderTopColor: colors.borderSubtle,
  },
  reportItemText: { fontSize: 15, fontWeight: '500', color: colors.textPrimary },

  // Profile Card
  profileCard: {
    marginHorizontal: 16, marginTop: 8, borderRadius: 28,
    backgroundColor: colors.bgCard, borderWidth: 1, borderColor: colors.borderLight,
    padding: 16, overflow: 'hidden', ...shadows.elevation2,
  },
  bannerOverlay: {
    position: 'absolute', top: 0, left: 0, right: 0, height: 100,
    backgroundColor: colors.accentPrimaryLight, opacity: 0.3,
  },
  profileRow: {
    flexDirection: 'row', alignItems: 'flex-start', gap: 16, paddingTop: 8, marginBottom: 16,
  },
  avatarContainer: {
    width: 96, height: 96, borderRadius: 48, borderWidth: 3,
    borderColor: colors.bgCard, overflow: 'hidden', ...shadows.elevation2,
  },
  avatar: { width: '100%', height: '100%' },
  avatarPlaceholder: {
    width: '100%', height: '100%', backgroundColor: colors.bgSubtle,
    justifyContent: 'center', alignItems: 'center',
  },
  avatarText: { fontSize: 36, fontWeight: '700', color: colors.accentPrimary },
  profileInfo: { flex: 1, paddingTop: 8 },
  fullName: {
    fontSize: 24, fontWeight: '700', color: colors.textPrimary, fontStyle: 'italic', lineHeight: 30,
  },
  username: { fontSize: 14, fontWeight: '600', color: colors.textHint, marginTop: 2 },
  tagRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginTop: 8 },
  tag: { backgroundColor: '#d9eef7', paddingHorizontal: 12, paddingVertical: 4, borderRadius: 12 },
  tagText: { fontSize: 12, fontWeight: '600', color: '#2d5b7c' },

  // Bio
  bioCard: {
    backgroundColor: colors.bgSubtle, borderRadius: 20, paddingHorizontal: 16,
    paddingVertical: 12, marginBottom: 16, borderWidth: 1, borderColor: colors.borderSubtle,
  },
  bioText: { fontSize: 14, color: colors.textPrimary, lineHeight: 20, fontWeight: '500' },

  // Stats
  statsRow: {
    flexDirection: 'row', justifyContent: 'space-around', paddingTop: 12,
    borderTopWidth: 1, borderTopColor: colors.borderSubtle,
  },
  statItem: { alignItems: 'center' },
  statValue: { fontSize: 18, fontWeight: '700', color: colors.textPrimary },
  statLabel: { fontSize: 12, color: colors.textHint, marginTop: 2 },

  // Sections
  section: { marginHorizontal: 16, marginTop: 20 },
  sectionTitle: {
    fontSize: 13, fontWeight: '800', color: colors.textPrimary, letterSpacing: 0.5, marginBottom: 12,
  },
  infoCard: {
    backgroundColor: colors.bgCard, borderRadius: 20, borderWidth: 1,
    borderColor: colors.borderSubtle, overflow: 'hidden',
  },
  infoRow: {
    flexDirection: 'row', justifyContent: 'space-between', paddingHorizontal: 16,
    paddingVertical: 14, borderBottomWidth: 1, borderBottomColor: colors.borderSubtle,
  },
  infoLabel: { fontSize: 15, color: colors.textSecondary },
  infoValue: { fontSize: 15, fontWeight: '700', color: colors.textPrimary },
  chipContainer: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  chipLight: {
    backgroundColor: colors.bgCard, borderWidth: 1, borderColor: colors.borderLight,
    paddingHorizontal: 14, paddingVertical: 8, borderRadius: 16,
  },
  chipLightText: { fontSize: 13, color: colors.textSecondary, fontWeight: '500' },
  interestChip: { backgroundColor: '#d9eef7', paddingHorizontal: 14, paddingVertical: 8, borderRadius: 16 },
  interestChipText: { fontSize: 13, fontWeight: '600', color: '#2d5b7c' },
  socialLinks: { flexDirection: 'row', flexWrap: 'wrap', gap: 16 },
  socialLink: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  socialLinkText: { fontSize: 14, color: colors.textPrimary, fontWeight: '500' },

  // Actions
  actionRow: {
    flexDirection: 'row', alignItems: 'center', gap: 12,
    marginHorizontal: 16, marginTop: 20,
  },
  followBtn: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: 8, backgroundColor: colors.accentPrimary, paddingVertical: 14, borderRadius: 20,
  },
  followingBtn: {
    backgroundColor: 'transparent', borderWidth: 1.5, borderColor: colors.accentPrimary,
  },
  followBtnText: { fontSize: 15, fontWeight: '700', color: '#FFFFFF' },
  followingBtnText: { color: colors.accentPrimary },
  friendBtn: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: 8, backgroundColor: colors.accentPrimaryLight, paddingVertical: 14, borderRadius: 20,
    borderWidth: 1, borderColor: colors.accentPrimary + '30',
  },
  friendBtnActive: {
    backgroundColor: '#DCFCE7', borderColor: '#22C55E30',
  },
  friendBtnPending: {
    backgroundColor: '#FEF3C7', borderColor: '#F59E0B30',
  },
  friendBtnText: { fontSize: 15, fontWeight: '700', color: colors.accentPrimary },
  messageBtn: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: 8, backgroundColor: colors.accentPrimaryLight, paddingVertical: 14,
    borderRadius: 20, borderWidth: 1, borderColor: colors.accentPrimary + '30',
  },
  messageBtnText: { fontSize: 15, fontWeight: '700', color: colors.accentPrimary },

  // Posts Grid
  postsSection: { paddingHorizontal: 16, marginTop: 24 },
  postsSectionTitle: {
    fontSize: 18, fontWeight: '700', color: colors.textPrimary, fontStyle: 'italic', marginBottom: 16,
  },
  emptyPosts: { alignItems: 'center', paddingVertical: 40 },
  emptyText: { fontSize: 14, color: colors.textHint, marginTop: 8 },
  postsGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 },
  postThumbnail: {
    width: (SCREEN_WIDTH - 32 - 12) / 2, aspectRatio: 1, borderRadius: 20,
    overflow: 'hidden', backgroundColor: colors.bgCard, borderWidth: 1,
    borderColor: colors.borderLight, ...shadows.elevation1,
  },
  thumbnailImage: { width: '100%', height: '100%' },
  textThumbnail: { flex: 1, backgroundColor: colors.bgSubtle, padding: 12, justifyContent: 'center' },
  textThumbnailContent: { fontSize: 11, color: colors.textSecondary, lineHeight: 15 },
});
