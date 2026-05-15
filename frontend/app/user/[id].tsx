import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Dimensions,
  Image,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';

import MediaPreview from '../../src/components/MediaPreview';
import api from '../../src/api/client';
import { useAuthStore } from '../../src/store/authStore';
import { cachePostForDetail, cachePostsForDetail } from '../../src/store/postDetailCache';
import { borderRadius, colors, hitSlop, layout, spacing } from '../../src/utils/theme';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const TILE_SIZE = Math.floor((SCREEN_WIDTH - 4) / 3);

const REPORT_REASONS = [
  { id: 'spam', label: 'Spam' },
  { id: 'scam', label: 'Scam or suspicious link' },
  { id: 'harassment', label: 'Harassment or bullying' },
  { id: 'impersonation', label: 'Impersonation' },
  { id: 'hate', label: 'Hate speech' },
  { id: 'private_personal_information', label: 'Private personal information' },
  { id: 'phone_number_exposed', label: 'Phone number exposed' },
  { id: 'address_exposed', label: 'Address exposed' },
  { id: 'school_information', label: 'School or workplace info' },
  { id: 'copyright_issue', label: 'Copyright or stolen content' },
  { id: 'other', label: 'Other' },
];

function parseImages(value: unknown): string[] {
  if (Array.isArray(value)) return value.map(String).filter(Boolean);
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      if (Array.isArray(parsed)) return parsed.map(String).filter(Boolean);
    } catch {}
    return value ? [value] : [];
  }
  return [];
}

function getPostMedia(post: any) {
  return [post?.image, ...parseImages(post?.images)]
    .map((item) => String(item || '').trim())
    .find(Boolean) || '';
}

function compact(value: unknown) {
  const count = Math.max(0, Number(value || 0));
  if (count >= 1000000) return `${(count / 1000000).toFixed(1).replace(/\.0$/, '')}M`;
  if (count >= 1000) return `${(count / 1000).toFixed(1).replace(/\.0$/, '')}K`;
  return String(Math.round(count));
}

export default function UserProfileScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { id: userId } = useLocalSearchParams<{ id: string }>();
  const { user: currentUser } = useAuthStore();
  const [userProfile, setUserProfile] = useState<any>(null);
  const [posts, setPosts] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isFollowing, setIsFollowing] = useState(false);
  const [isFollowLoading, setIsFollowLoading] = useState(false);
  const [showMenu, setShowMenu] = useState(false);
  const [showReport, setShowReport] = useState(false);
  const [friendStatus, setFriendStatus] = useState('none');
  const [friendRequestId, setFriendRequestId] = useState<string | null>(null);
  const [friendLoading, setFriendLoading] = useState(false);

  const loadUserData = useCallback(async () => {
    try {
      const [userRes, postsRes] = await Promise.all([
        api.get(`/users/${userId}`),
        api.get(`/users/${userId}/posts`),
      ]);
      const nextPosts = Array.isArray(postsRes.data) ? postsRes.data : [];
      cachePostsForDetail(nextPosts);
      setUserProfile(userRes.data);
      setPosts(nextPosts);
      setIsFollowing(!!userRes.data?.is_following);

      try {
        const friendRes = await api.get(`/friends/status/${userId}`);
        setFriendStatus(friendRes.data.status || 'none');
        setFriendRequestId(friendRes.data.request_id || null);
      } catch {}
    } catch {
      setUserProfile(null);
    } finally {
      setIsLoading(false);
    }
  }, [userId]);

  useEffect(() => {
    void loadUserData();
  }, [loadUserData]);

  const handleFollow = async () => {
    if (isFollowLoading) return;
    setIsFollowLoading(true);
    try {
      const nextFollowing = !isFollowing;
      const response = await api.post(`/users/${userId}/follow`, { following: nextFollowing });
      setIsFollowing(response.data.following);
      setUserProfile((prev: any) => ({
        ...prev,
        followers_count: Number.isFinite(Number(response.data?.followers_count))
          ? Number(response.data.followers_count)
          : Math.max(0, Number(prev?.followers_count || 0) + (response.data.following ? 1 : -1)),
      }));
    } finally {
      setIsFollowLoading(false);
    }
  };

  const handleFriendRequest = async () => {
    if (friendLoading) return;
    setFriendLoading(true);
    try {
      if (friendStatus === 'none') {
        const res = await api.post(`/friends/request/${userId}`);
        setFriendStatus(res.data.status || 'request_sent');
        setFriendRequestId(res.data.request_id || res.data.id || null);
      } else if ((friendStatus === 'request_received' || friendStatus === 'pending_received') && friendRequestId) {
        await api.post(`/friends/accept/${friendRequestId}`);
        setFriendStatus('friends');
      } else if (friendStatus === 'friends') {
        Alert.alert('Remove Friend', 'Are you sure you want to remove this friend?', [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Remove',
            style: 'destructive',
            onPress: async () => {
              await api.delete(`/friends/${userId}`);
              setFriendStatus('none');
            },
          },
        ]);
      }
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.detail || 'Something went wrong');
    } finally {
      setFriendLoading(false);
    }
  };

  const handleReport = async (reason: string) => {
    try {
      await api.post('/reports', {
        reported_type: 'user',
        reported_id: userId,
        report_type: 'user',
        reason,
        details: 'Reported from user profile.',
      });
      Alert.alert('Report Submitted', 'Thank you for helping keep the community safe.');
    } catch {
      Alert.alert('Error', 'Could not submit report. Please try again.');
    } finally {
      setShowReport(false);
    }
  };

  const coverMedia = useMemo(() => (
    userProfile?.profile_background_image || userProfile?.cover_image || getPostMedia(posts[0]) || userProfile?.profile_image || ''
  ), [posts, userProfile]);

  if (isLoading) {
    return (
      <SafeAreaView style={s.center}>
        <ActivityIndicator size="large" color={colors.accentPrimary} />
      </SafeAreaView>
    );
  }

  if (!userProfile) {
    return (
      <SafeAreaView style={s.center}>
        <Ionicons name="person-outline" size={56} color="rgba(255,255,255,0.42)" />
        <Text style={s.notFound}>User not found</Text>
        <TouchableOpacity style={s.backPill} onPress={() => router.back()}>
          <Text style={s.backPillText}>Go Back</Text>
        </TouchableOpacity>
      </SafeAreaView>
    );
  }

  const isOwnProfile = userId === currentUser?.id;
  const displayName = userProfile.full_name || userProfile.username || 'Flames';
  const username = userProfile.username || userProfile.email?.split('@')[0] || 'profile';
  const isPremium = !!userProfile?.is_premium;
  const isFriendPending = friendStatus === 'request_sent' || friendStatus === 'pending_sent';
  const isFriendReceived = friendStatus === 'request_received' || friendStatus === 'pending_received';

  return (
    <View style={s.root}>
      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ paddingBottom: 90 }}
      >
        <View style={s.hero}>
          {coverMedia ? (
            <MediaPreview uri={coverMedia} mediaTypes={posts[0]?.media_types} style={s.heroMedia} showVideoBadge={false} />
          ) : (
            <View style={s.heroFallback} />
          )}
          <View style={s.heroDim} />

          <View style={[s.topbar, { paddingTop: insets.top + 2 }]}>
            <TouchableOpacity style={s.roundNav} onPress={() => router.back()} hitSlop={hitSlop} accessibilityLabel="Go back">
              <Ionicons name="chevron-back" size={22} color="#FFFFFF" />
            </TouchableOpacity>
            <View style={s.topActions}>
              <TouchableOpacity style={s.roundNav} onPress={() => router.push(`/conversation/${userId}` as any)} hitSlop={hitSlop} accessibilityLabel="Message user">
                <Ionicons name="paper-plane-outline" size={20} color="#FFFFFF" />
              </TouchableOpacity>
              <TouchableOpacity style={s.roundNav} onPress={() => setShowMenu(true)} hitSlop={hitSlop} accessibilityLabel="Open user menu">
                <Ionicons name="ellipsis-horizontal" size={22} color="#FFFFFF" />
              </TouchableOpacity>
            </View>
          </View>

          <View style={s.identityBlock}>
            <View style={s.avatarRow}>
              <View style={s.avatar}>
                {userProfile.profile_image ? (
                  <Image source={{ uri: userProfile.profile_image }} style={s.avatarImage} />
                ) : (
                  <Text style={s.avatarInitial}>{displayName[0]?.toUpperCase() || 'F'}</Text>
                )}
              </View>
              <View style={s.smallBadge}>
                <Ionicons name="earth-outline" size={28} color="#FFFFFF" />
              </View>
            </View>

            <Text style={s.name}>{displayName}</Text>
            <View style={s.metaRow}>
              <Text style={s.meta}>@{username}</Text>
              {isPremium ? (
                <View style={s.premiumBadge}>
                  <Ionicons name="sparkles" size={11} color="#FFFFFF" />
                  <Text style={s.premiumBadgeText}>Premium</Text>
                </View>
              ) : null}
            </View>

            <View style={s.followStatsRow}>
              <View style={s.followStat}>
                <Text style={s.followStatValue}>{compact(userProfile.followers_count)}</Text>
                <Text style={s.followStatLabel}>Followers</Text>
              </View>
              <View style={s.followStat}>
                <Text style={s.followStatValue}>{compact(userProfile.following_count)}</Text>
                <Text style={s.followStatLabel}>Following</Text>
              </View>
              {!isOwnProfile ? (
                <>
                  <TouchableOpacity style={[s.primaryAction, isFollowing && s.primaryActionOn]} onPress={handleFollow} disabled={isFollowLoading}>
                    {isFollowLoading ? (
                      <ActivityIndicator color={isFollowing ? '#FFFFFF' : '#111111'} />
                    ) : (
                      <Text style={[s.primaryActionText, isFollowing && s.primaryActionTextOn]}>{isFollowing ? 'Following' : 'Follow'}</Text>
                    )}
                  </TouchableOpacity>
                  <TouchableOpacity style={s.secondaryAction} onPress={handleFriendRequest} disabled={friendLoading}>
                    {friendLoading ? (
                      <ActivityIndicator color="#FFFFFF" />
                    ) : (
                      <Text style={s.secondaryActionText}>{friendStatus === 'friends' ? 'Friends' : isFriendReceived ? 'Accept' : isFriendPending ? 'Pending' : 'Friend'}</Text>
                    )}
                  </TouchableOpacity>
                </>
              ) : (
                <TouchableOpacity style={s.primaryAction} onPress={() => router.push('/edit-profile' as any)}>
                  <Text style={s.primaryActionText}>Edit</Text>
                </TouchableOpacity>
              )}
            </View>
          </View>
        </View>

        <View style={s.grid}>
          {posts.length === 0 ? (
            <View style={s.emptyPosts}>
              <Ionicons name="camera-outline" size={44} color="rgba(255,255,255,0.42)" />
              <Text style={s.emptyText}>No posts yet</Text>
            </View>
          ) : posts.map((post) => {
            const media = getPostMedia(post);
            return (
              <TouchableOpacity
                key={post.id}
                style={s.tile}
                activeOpacity={0.9}
                onPress={() => {
                  cachePostForDetail(post);
                  router.push(`/post/${post.id}` as any);
                }}
              >
                {media ? (
                  <MediaPreview uri={media} mediaTypes={post.media_types} style={s.tileMedia} />
                ) : (
                  <View style={s.textTile}>
                    <Text style={s.textTileText} numberOfLines={5}>{post.content || 'Post'}</Text>
                  </View>
                )}
              </TouchableOpacity>
            );
          })}
        </View>
      </ScrollView>

      <Modal visible={showMenu} transparent animationType="fade" onRequestClose={() => setShowMenu(false)}>
        <Pressable style={s.overlay} onPress={() => setShowMenu(false)}>
          <View style={[s.menu, { top: insets.top + 48 }]}>
            <MenuItem icon="flag-outline" label="Report User" danger onPress={() => { setShowMenu(false); setShowReport(true); }} />
            <MenuItem icon="ban-outline" label="Block User" onPress={() => { setShowMenu(false); Alert.alert('Blocked', 'This user has been blocked.'); }} />
            <MenuItem icon="share-outline" label="Share Profile" onPress={() => setShowMenu(false)} />
          </View>
        </Pressable>
      </Modal>

      <Modal visible={showReport} transparent animationType="slide" onRequestClose={() => setShowReport(false)}>
        <Pressable style={s.reportOverlay} onPress={() => setShowReport(false)}>
          <Pressable style={[s.reportSheet, { paddingBottom: insets.bottom + 18 }]}>
            <View style={s.sheetHandle} />
            <Text style={s.reportTitle}>Report this user</Text>
            <Text style={s.reportSubtitle}>Your report is anonymous.</Text>
            {REPORT_REASONS.map((reason) => (
              <TouchableOpacity key={reason.id} style={s.reportItem} onPress={() => handleReport(reason.id)}>
                <Text style={s.reportItemText}>{reason.label}</Text>
                <Ionicons name="chevron-forward" size={16} color="rgba(255,255,255,0.42)" />
              </TouchableOpacity>
            ))}
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}

function MenuItem({ danger, icon, label, onPress }: { danger?: boolean; icon: keyof typeof Ionicons.glyphMap; label: string; onPress: () => void }) {
  return (
    <TouchableOpacity style={s.menuItem} onPress={onPress}>
      <Ionicons name={icon} size={20} color={danger ? '#FF5A5F' : '#FFFFFF'} />
      <Text style={[s.menuText, danger && s.menuTextDanger]}>{label}</Text>
    </TouchableOpacity>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#070806' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: '#070806' },
  notFound: { color: 'rgba(255,255,255,0.72)', fontSize: 16, fontWeight: '500', marginTop: 12 },
  backPill: { marginTop: 16, minHeight: layout.minTouchTarget, borderRadius: borderRadius.full, backgroundColor: '#FFFFFF', paddingHorizontal: 20, justifyContent: 'center' },
  backPillText: { color: colors.textPrimary, fontSize: 14, fontWeight: '500' },
  hero: { height: Math.max(480, SCREEN_WIDTH * 1.36), overflow: 'hidden', backgroundColor: '#11120F' },
  heroMedia: { ...StyleSheet.absoluteFillObject },
  heroFallback: { ...StyleSheet.absoluteFillObject, backgroundColor: '#171717' },
  heroDim: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.36)' },
  topbar: { position: 'absolute', left: spacing.md, right: spacing.md, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  topActions: { flexDirection: 'row', gap: spacing.sm },
  roundNav: { width: layout.iconButton, height: layout.iconButton, borderRadius: layout.iconButton / 2, backgroundColor: 'rgba(0,0,0,0.30)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.18)', alignItems: 'center', justifyContent: 'center' },
  nav: { position: 'absolute', left: 16, right: 16, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  navRight: { flexDirection: 'row', gap: 10 },
  navBtn: { width: 42, height: 42, borderRadius: 21, backgroundColor: 'rgba(0,0,0,0.32)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.16)', alignItems: 'center', justifyContent: 'center' },
  profileLanding: { position: 'absolute', left: 12, right: 12, bottom: 14, gap: 8 },
  profileCircleRow: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 4 },
  profileAvatarCircle: { width: 70, height: 70, borderRadius: 35, borderWidth: 2, borderColor: '#FFFFFF', backgroundColor: '#FFFFFF', overflow: 'hidden', alignItems: 'center', justifyContent: 'center' },
  profileAvatarImage: { width: '100%', height: '100%' },
  profileAvatarInitial: { color: '#111111', fontSize: 29, fontWeight: '500' },
  profileMarkCircle: { width: 54, height: 54, borderRadius: 27, marginLeft: -10, backgroundColor: colors.accentPrimary, borderWidth: 2, borderColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center' },
  profileInfoCard: { minHeight: 112, borderRadius: 9, backgroundColor: 'rgba(45,45,43,0.94)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)', flexDirection: 'row', padding: 15, gap: 12 },
  profileNameBlock: { flex: 0.88, justifyContent: 'flex-start' },
  profileFirstName: { color: '#FFFFFF', fontSize: 23, lineHeight: 25, fontWeight: '500' },
  profileLastName: { color: '#FFFFFF', fontSize: 23, lineHeight: 25, fontWeight: '500' },
  profileAboutBlock: { flex: 1, gap: 12 },
  profileAboutLabel: { color: '#FFFFFF', fontSize: 12, fontWeight: '500' },
  profileAboutText: { color: 'rgba(255,255,255,0.44)', fontSize: 13, lineHeight: 16, fontWeight: '500' },
  profileBottomActions: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 7, paddingTop: 2 },
  followMiniButton: { minHeight: 34, borderRadius: 17, backgroundColor: colors.accentPrimary, borderWidth: 1, borderColor: colors.accentPrimaryHover, justifyContent: 'center', paddingHorizontal: 14 },
  followMiniButtonOn: { backgroundColor: '#FFFFFF' },
  followMiniText: { color: '#FFFFFF', fontSize: 12, fontWeight: '500' },
  statsMiniPill: { minHeight: 38, borderRadius: 19, backgroundColor: 'rgba(45,45,43,0.88)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.10)', flexDirection: 'row', alignItems: 'center', gap: 6, justifyContent: 'center', paddingHorizontal: 13 },
  statsMiniText: { color: '#FFFFFF', fontSize: 12, fontWeight: '500' },
  identityBlock: { position: 'absolute', left: spacing.lg, right: spacing.lg, bottom: spacing.xl },
  identity: { position: 'absolute', left: 22, right: 22, bottom: 30 },
  avatarRow: { flexDirection: 'row', alignItems: 'center', marginBottom: 8 },
  avatar: { width: 62, height: 62, borderRadius: 31, borderWidth: 2, borderColor: '#FFFFFF', backgroundColor: '#FFFFFF', overflow: 'hidden', alignItems: 'center', justifyContent: 'center' },
  avatarImage: { width: '100%', height: '100%' },
  avatarInitial: { color: '#111111', fontSize: 26, fontWeight: '500' },
  smallBadge: { width: 50, height: 50, borderRadius: 25, marginLeft: -8, backgroundColor: colors.accentPrimary, borderWidth: 2, borderColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center' },
  globeBadge: { width: 50, height: 50, borderRadius: 25, marginLeft: -8, backgroundColor: colors.accentPrimary, borderWidth: 2, borderColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center' },
  globeText: { fontSize: 28 },
  name: { color: '#FFFFFF', fontSize: 34, lineHeight: 38, fontWeight: '600', letterSpacing: 0 },
  meta: { color: 'rgba(255,255,255,0.78)', fontSize: 13, lineHeight: 18, fontWeight: '500', marginTop: 5 },
  metaRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, flexWrap: 'wrap' },
  premiumBadge: { height: 24, borderRadius: 12, backgroundColor: colors.accentLime, flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 9, marginTop: 6 },
  premiumBadgeText: { color: colors.textInverse, fontSize: 11, fontWeight: '600' },
  followStatsRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.gutter, marginTop: spacing.section },
  followStat: { minWidth: 70 },
  followStatValue: { color: '#FFFFFF', fontSize: 19, lineHeight: 23, fontWeight: '600', fontVariant: ['tabular-nums'] },
  followStatLabel: { color: 'rgba(255,255,255,0.72)', fontSize: 11, fontWeight: '500' },
  primaryAction: { marginLeft: 'auto', minWidth: 72, minHeight: 38, borderRadius: 19, backgroundColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center', paddingHorizontal: spacing.gutter },
  primaryActionOn: { backgroundColor: colors.accentPrimary },
  primaryActionText: { color: colors.textPrimary, fontSize: 13, fontWeight: '600', textAlign: 'center' },
  primaryActionTextOn: { color: colors.textInverse },
  secondaryAction: { minWidth: 78, minHeight: layout.minTouchTarget, borderRadius: borderRadius.full, borderWidth: 1.2, borderColor: 'rgba(255,255,255,0.28)', backgroundColor: 'rgba(0,0,0,0.22)', alignItems: 'center', justifyContent: 'center', paddingHorizontal: spacing.md },
  secondaryActionText: { color: '#FFFFFF', fontSize: 13, fontWeight: '500', textAlign: 'center' },
  statsRow: { flexDirection: 'row', alignItems: 'center', gap: 14, marginTop: 20 },
  statValue: { color: '#FFFFFF', fontSize: 21, fontWeight: '500', fontVariant: ['tabular-nums'] },
  statLabel: { color: 'rgba(255,255,255,0.72)', fontSize: 11, fontWeight: '500' },
  supportBtn: { marginLeft: 'auto', width: 72, height: 72, borderRadius: 36, backgroundColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 6 },
  supportBtnText: { color: '#111111', fontSize: 11, fontWeight: '500', textAlign: 'center' },
  chatBtn: { width: 72, height: 72, borderRadius: 36, borderWidth: 1.4, borderColor: 'rgba(255,255,255,0.26)', backgroundColor: 'rgba(0,0,0,0.22)', alignItems: 'center', justifyContent: 'center' },
  chatBtnText: { color: '#FFFFFF', fontSize: 12, fontWeight: '500' },
  friendStrip: { paddingHorizontal: 16, paddingVertical: 12, backgroundColor: '#080808' },
  friendButton: { minHeight: 46, borderRadius: 23, backgroundColor: 'rgba(255,255,255,0.12)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.14)', flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8 },
  friendButtonOn: { backgroundColor: 'rgba(34,197,94,0.22)', borderColor: 'rgba(34,197,94,0.32)' },
  friendButtonText: { color: '#FFFFFF', fontSize: 14, fontWeight: '500' },
  tabs: { height: 58, flexDirection: 'row', backgroundColor: '#080808', borderTopWidth: 1, borderBottomWidth: 1, borderColor: 'rgba(255,255,255,0.08)' },
  tab: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  tabOn: { backgroundColor: '#171717' },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 2, backgroundColor: '#070806' },
  tile: { width: TILE_SIZE, height: TILE_SIZE, overflow: 'hidden', backgroundColor: '#161713' },
  tileMedia: { width: '100%', height: '100%' },
  textTile: { flex: 1, padding: 10, justifyContent: 'center', backgroundColor: '#191919' },
  textTileText: { color: '#FFFFFF', fontSize: 12, lineHeight: 16, fontWeight: '600' },
  emptyPosts: { width: SCREEN_WIDTH, minHeight: 170, alignItems: 'center', justifyContent: 'center', gap: 8 },
  emptyText: { color: 'rgba(255,255,255,0.56)', fontSize: 14, fontWeight: '500' },
  overlay: { flex: 1, backgroundColor: colors.modalScrim },
  menu: { position: 'absolute', right: spacing.md, width: 230, borderRadius: borderRadius.xl, backgroundColor: 'rgba(16,16,16,0.96)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.12)', overflow: 'hidden' },
  menuItem: { minHeight: 52, flexDirection: 'row', alignItems: 'center', gap: spacing.gutter, paddingHorizontal: spacing.md, borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.08)' },
  menuText: { color: '#FFFFFF', fontSize: 15, fontWeight: '500' },
  menuTextDanger: { color: '#FF5A5F' },
  reportOverlay: { flex: 1, backgroundColor: colors.modalScrim, justifyContent: 'flex-end' },
  reportSheet: { backgroundColor: '#101010', borderTopLeftRadius: 24, borderTopRightRadius: 24, paddingTop: 10, borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)' },
  sheetHandle: { width: 42, height: 5, borderRadius: 3, backgroundColor: 'rgba(255,255,255,0.22)', alignSelf: 'center', marginBottom: 14 },
  reportTitle: { color: '#FFFFFF', fontSize: 20, fontWeight: '500', paddingHorizontal: 20 },
  reportSubtitle: { color: 'rgba(255,255,255,0.62)', fontSize: 13, fontWeight: '500', paddingHorizontal: 20, marginTop: 4, marginBottom: 10 },
  reportItem: { minHeight: 52, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 20, borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.08)' },
  reportItemText: { color: '#FFFFFF', fontSize: 15, fontWeight: '600' },
});
