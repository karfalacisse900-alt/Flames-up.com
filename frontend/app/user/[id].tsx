import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Dimensions,
  Modal,
  Pressable,
  RefreshControl,
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
import { cachePostForDetail, cachePostsForDetail, setPostDetailFeedContext } from '../../src/store/postDetailCache';
import { colors } from '../../src/utils/theme';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const TILE_SIZE = Math.floor((SCREEN_WIDTH - 4) / 3);

const REPORT_REASONS = [
  { id: 'spam', label: 'Spam' },
  { id: 'harassment', label: 'Harassment or bullying' },
  { id: 'fake_profile', label: 'Fake profile' },
  { id: 'hate_speech', label: 'Hate speech' },
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
  const [isRefreshing, setIsRefreshing] = useState(false);
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
        followers_count: Math.max(0, Number(prev?.followers_count || 0) + (response.data.following ? 1 : -1)),
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
    userProfile?.cover_image || getPostMedia(posts[0]) || userProfile?.profile_image || ''
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
  const location = userProfile.city || userProfile.location || 'Flames-Up';
  const isFriendPending = friendStatus === 'request_sent' || friendStatus === 'pending_sent';
  const isFriendReceived = friendStatus === 'request_received' || friendStatus === 'pending_received';

  return (
    <View style={s.root}>
      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} tintColor="#FFFFFF" />}
        contentContainerStyle={{ paddingBottom: 90 }}
      >
        <View style={s.hero}>
          {coverMedia ? (
            <MediaPreview uri={coverMedia} mediaTypes={posts[0]?.media_types} style={s.heroMedia} showVideoBadge={false} />
          ) : (
            <View style={s.heroFallback} />
          )}
          <View style={s.heroDim} />

          <View style={[s.nav, { paddingTop: insets.top + 8 }]}>
            <TouchableOpacity style={s.navBtn} onPress={() => router.back()}>
              <Ionicons name="chevron-back" size={22} color="#FFFFFF" />
            </TouchableOpacity>
            <View style={s.navRight}>
              <TouchableOpacity style={s.navBtn} onPress={() => router.push(`/conversation/${userId}` as any)}>
                <Ionicons name="paper-plane-outline" size={20} color="#FFFFFF" />
              </TouchableOpacity>
              <TouchableOpacity style={s.navBtn} onPress={() => setShowMenu(true)}>
                <Ionicons name="ellipsis-horizontal" size={22} color="#FFFFFF" />
              </TouchableOpacity>
            </View>
          </View>

          <View style={s.profileLanding}>
            <View style={s.profileActionGrid}>
              <TouchableOpacity
                style={[s.profileActionTile, s.messageTile]}
                activeOpacity={0.86}
                onPress={() => router.push(`/conversation/${userId}` as any)}
              >
                <Ionicons name="chatbubble" size={23} color="#FFFFFF" />
                <View>
                  <Text style={s.messageTileText}>Send</Text>
                  <Text style={s.messageTileText}>Message</Text>
                </View>
              </TouchableOpacity>
              <View style={s.profileSmallGrid}>
                <TouchableOpacity style={[s.profileActionTile, s.profileSmallTile]} activeOpacity={0.86}>
                  <Ionicons name="logo-instagram" size={23} color="#FFFFFF" />
                </TouchableOpacity>
                <TouchableOpacity style={[s.profileActionTile, s.profileSmallTile]} activeOpacity={0.86}>
                  <Ionicons name="logo-youtube" size={24} color="#FFFFFF" />
                </TouchableOpacity>
                <TouchableOpacity style={[s.profileActionTile, s.profileSmallTile]} activeOpacity={0.86}>
                  <Ionicons name="logo-twitch" size={23} color="#FFFFFF" />
                </TouchableOpacity>
                <TouchableOpacity style={[s.profileActionTile, s.profileSmallTile]} activeOpacity={0.86}>
                  <Text style={s.xIcon}>X</Text>
                </TouchableOpacity>
              </View>
            </View>

            <View style={s.profileInfoCard}>
              <View style={s.profileNameBlock}>
                <Text style={s.profileFirstName} numberOfLines={1}>{displayName.split(' ')[0] || displayName}</Text>
                <Text style={s.profileLastName} numberOfLines={1}>{displayName.split(' ').slice(1).join(' ') || `@${username}`}</Text>
              </View>
              <View style={s.profileAboutBlock}>
                <Text style={s.profileAboutLabel}>About:</Text>
                <Text style={s.profileAboutText} numberOfLines={4}>
                  {userProfile.bio || `${location} creator sharing moments, sounds, and stories with the Flames community.`}
                </Text>
              </View>
            </View>

            <View style={s.profileBottomActions}>
              {!isOwnProfile ? (
                <>
                  <TouchableOpacity style={[s.followMiniButton, isFollowing && s.followMiniButtonOn]} onPress={handleFollow} disabled={isFollowLoading}>
                    {isFollowLoading ? <ActivityIndicator color="#111111" /> : <Text style={s.followMiniText}>{isFollowing ? 'Following' : 'Follow'}</Text>}
                  </TouchableOpacity>
                  <TouchableOpacity style={s.statsMiniPill} onPress={handleFriendRequest} disabled={friendLoading}>
                    <Ionicons
                      name={friendStatus === 'friends' ? 'people' : isFriendReceived ? 'checkmark-circle-outline' : isFriendPending ? 'hourglass-outline' : 'person-add-outline'}
                      size={16}
                      color="#FFFFFF"
                    />
                    <Text style={s.statsMiniText}>{friendStatus === 'friends' ? 'Friends' : isFriendReceived ? 'Accept' : isFriendPending ? 'Pending' : 'Friend'}</Text>
                  </TouchableOpacity>
                </>
              ) : (
                <TouchableOpacity style={s.followMiniButton} onPress={() => router.push('/edit-profile' as any)}>
                  <Text style={s.followMiniText}>Edit profile</Text>
                </TouchableOpacity>
              )}
              <View style={s.statsMiniPill}>
                <Text style={s.statsMiniText}>{compact(userProfile.followers_count)} supporters</Text>
              </View>
            </View>
          </View>
        </View>

        <View style={s.tabs}>
          <View style={[s.tab, s.tabOn]}><Ionicons name="bag-outline" size={22} color="#DFFF32" /></View>
          <View style={s.tab}><Ionicons name="chatbubbles-outline" size={22} color="rgba(255,255,255,0.72)" /></View>
          <View style={s.tab}><Ionicons name="grid-outline" size={22} color="rgba(255,255,255,0.72)" /></View>
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
                  setPostDetailFeedContext(posts.map((item) => item.id));
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
          <View style={[s.menu, { top: insets.top + 54 }]}>
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
  root: { flex: 1, backgroundColor: '#050505' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: '#050505' },
  notFound: { color: 'rgba(255,255,255,0.72)', fontSize: 16, fontWeight: '800', marginTop: 12 },
  backPill: { marginTop: 16, minHeight: 42, borderRadius: 21, backgroundColor: '#FFFFFF', paddingHorizontal: 20, justifyContent: 'center' },
  backPillText: { color: '#111111', fontSize: 14, fontWeight: '900' },
  hero: { height: Math.max(650, SCREEN_WIDTH * 1.82), overflow: 'hidden', backgroundColor: '#111111' },
  heroMedia: { ...StyleSheet.absoluteFillObject },
  heroFallback: { ...StyleSheet.absoluteFillObject, backgroundColor: '#171717' },
  heroDim: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.22)' },
  nav: { position: 'absolute', left: 16, right: 16, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  navRight: { flexDirection: 'row', gap: 10 },
  navBtn: { width: 42, height: 42, borderRadius: 21, backgroundColor: 'rgba(0,0,0,0.32)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.16)', alignItems: 'center', justifyContent: 'center' },
  profileLanding: { position: 'absolute', left: 12, right: 12, bottom: 14, gap: 5 },
  profileActionGrid: { height: 136, flexDirection: 'row', gap: 5 },
  profileActionTile: { flex: 1, borderRadius: 9, backgroundColor: 'rgba(45,45,43,0.92)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
  messageTile: { flex: 1.08, alignItems: 'flex-start', justifyContent: 'space-between', padding: 15 },
  messageTileText: { color: '#FFFFFF', fontSize: 16, lineHeight: 17, fontWeight: '800' },
  profileSmallGrid: { flex: 1, flexDirection: 'row', flexWrap: 'wrap', gap: 5 },
  profileSmallTile: { flex: 0, width: '48.4%', height: 65 },
  xIcon: { color: '#FFFFFF', fontSize: 24, fontWeight: '800' },
  profileInfoCard: { minHeight: 112, borderRadius: 9, backgroundColor: 'rgba(45,45,43,0.94)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)', flexDirection: 'row', padding: 15, gap: 12 },
  profileNameBlock: { flex: 0.88, justifyContent: 'flex-start' },
  profileFirstName: { color: '#FFFFFF', fontSize: 23, lineHeight: 25, fontWeight: '900' },
  profileLastName: { color: '#FFFFFF', fontSize: 23, lineHeight: 25, fontWeight: '900' },
  profileAboutBlock: { flex: 1, gap: 12 },
  profileAboutLabel: { color: '#FFFFFF', fontSize: 12, fontWeight: '700' },
  profileAboutText: { color: 'rgba(255,255,255,0.44)', fontSize: 13, lineHeight: 16, fontWeight: '700' },
  profileBottomActions: { flexDirection: 'row', alignItems: 'center', gap: 7, paddingTop: 2 },
  followMiniButton: { minHeight: 38, borderRadius: 19, backgroundColor: '#DFFF32', borderWidth: 1.3, borderColor: '#111111', justifyContent: 'center', paddingHorizontal: 16 },
  followMiniButtonOn: { backgroundColor: '#FFFFFF' },
  followMiniText: { color: '#111111', fontSize: 13, fontWeight: '900' },
  statsMiniPill: { minHeight: 38, borderRadius: 19, backgroundColor: 'rgba(45,45,43,0.88)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.10)', flexDirection: 'row', alignItems: 'center', gap: 6, justifyContent: 'center', paddingHorizontal: 13 },
  statsMiniText: { color: '#FFFFFF', fontSize: 12, fontWeight: '900' },
  identity: { position: 'absolute', left: 22, right: 22, bottom: 30 },
  avatarRow: { flexDirection: 'row', alignItems: 'center', marginBottom: 8 },
  avatar: { width: 62, height: 62, borderRadius: 31, borderWidth: 2, borderColor: '#FFFFFF', backgroundColor: '#FFFFFF', overflow: 'hidden', alignItems: 'center', justifyContent: 'center' },
  avatarImage: { width: '100%', height: '100%' },
  avatarInitial: { color: '#111111', fontSize: 26, fontWeight: '900' },
  globeBadge: { width: 54, height: 54, borderRadius: 27, marginLeft: -8, backgroundColor: '#6ED3FF', borderWidth: 2, borderColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center' },
  globeText: { fontSize: 28 },
  name: { color: '#FFFFFF', fontSize: 47, lineHeight: 49, fontWeight: '900', letterSpacing: 0 },
  meta: { color: 'rgba(255,255,255,0.78)', fontSize: 14, lineHeight: 18, fontWeight: '800', marginTop: 6 },
  statsRow: { flexDirection: 'row', alignItems: 'center', gap: 14, marginTop: 20 },
  statValue: { color: '#FFFFFF', fontSize: 21, fontWeight: '900', fontVariant: ['tabular-nums'] },
  statLabel: { color: 'rgba(255,255,255,0.72)', fontSize: 11, fontWeight: '700' },
  supportBtn: { marginLeft: 'auto', width: 72, height: 72, borderRadius: 36, backgroundColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 6 },
  supportBtnText: { color: '#111111', fontSize: 11, fontWeight: '900', textAlign: 'center' },
  chatBtn: { width: 72, height: 72, borderRadius: 36, borderWidth: 1.4, borderColor: 'rgba(255,255,255,0.26)', backgroundColor: 'rgba(0,0,0,0.22)', alignItems: 'center', justifyContent: 'center' },
  chatBtnText: { color: '#FFFFFF', fontSize: 12, fontWeight: '900' },
  friendStrip: { paddingHorizontal: 16, paddingVertical: 12, backgroundColor: '#080808' },
  friendButton: { minHeight: 46, borderRadius: 23, backgroundColor: 'rgba(255,255,255,0.12)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.14)', flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8 },
  friendButtonOn: { backgroundColor: 'rgba(34,197,94,0.22)', borderColor: 'rgba(34,197,94,0.32)' },
  friendButtonText: { color: '#FFFFFF', fontSize: 14, fontWeight: '900' },
  bio: { color: 'rgba(255,255,255,0.78)', fontSize: 14, lineHeight: 20, fontWeight: '700', paddingHorizontal: 16, paddingVertical: 14 },
  tabs: { height: 58, flexDirection: 'row', backgroundColor: '#080808', borderTopWidth: 1, borderBottomWidth: 1, borderColor: 'rgba(255,255,255,0.08)' },
  tab: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  tabOn: { backgroundColor: '#171717' },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 2, backgroundColor: '#050505' },
  tile: { width: TILE_SIZE, height: TILE_SIZE, overflow: 'hidden', backgroundColor: '#161616' },
  tileMedia: { width: '100%', height: '100%' },
  textTile: { flex: 1, padding: 10, justifyContent: 'center', backgroundColor: '#191919' },
  textTileText: { color: '#FFFFFF', fontSize: 12, lineHeight: 16, fontWeight: '800' },
  emptyPosts: { width: SCREEN_WIDTH, minHeight: 170, alignItems: 'center', justifyContent: 'center', gap: 8 },
  emptyText: { color: 'rgba(255,255,255,0.56)', fontSize: 14, fontWeight: '800' },
  overlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.36)' },
  menu: { position: 'absolute', right: 14, width: 230, borderRadius: 18, backgroundColor: 'rgba(16,16,16,0.96)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.12)', overflow: 'hidden' },
  menuItem: { minHeight: 52, flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 16, borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.08)' },
  menuText: { color: '#FFFFFF', fontSize: 15, fontWeight: '800' },
  menuTextDanger: { color: '#FF5A5F' },
  reportOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.42)', justifyContent: 'flex-end' },
  reportSheet: { backgroundColor: '#101010', borderTopLeftRadius: 24, borderTopRightRadius: 24, paddingTop: 10, borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)' },
  sheetHandle: { width: 42, height: 5, borderRadius: 3, backgroundColor: 'rgba(255,255,255,0.22)', alignSelf: 'center', marginBottom: 14 },
  reportTitle: { color: '#FFFFFF', fontSize: 20, fontWeight: '900', paddingHorizontal: 20 },
  reportSubtitle: { color: 'rgba(255,255,255,0.62)', fontSize: 13, fontWeight: '700', paddingHorizontal: 20, marginTop: 4, marginBottom: 10 },
  reportItem: { minHeight: 52, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 20, borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.08)' },
  reportItemText: { color: '#FFFFFF', fontSize: 15, fontWeight: '800' },
});
