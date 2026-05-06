import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Dimensions,
  Image,
  Linking,
  Modal,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useRouter } from 'expo-router';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';

import MediaPreview from '../../src/components/MediaPreview';
import api from '../../src/api/client';
import { useAuthStore } from '../../src/store/authStore';
import { cachePostForDetail, cachePostsForDetail, setPostDetailFeedContext } from '../../src/store/postDetailCache';
import { colors } from '../../src/utils/theme';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const GRID_GAP = 2;
const TILE_SIZE = Math.floor((SCREEN_WIDTH - GRID_GAP * 2) / 3);

function parseImages(value: unknown): string[] {
  if (Array.isArray(value)) return value.map((item) => String(item)).filter(Boolean);
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      if (Array.isArray(parsed)) return parsed.map((item) => String(item)).filter(Boolean);
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

export default function ProfileScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user, logout } = useAuthStore();
  const [posts, setPosts] = useState<any[]>([]);
  const [stats, setStats] = useState({ posts: 0, followers: 0, following: 0 });
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [showMore, setShowMore] = useState(false);

  const loadUserData = useCallback(async () => {
    if (!user?.id) return;
    try {
      const [postsRes, userRes] = await Promise.all([
        api.get(`/users/${user.id}/posts`),
        api.get(`/users/${user.id}`),
      ]);
      const nextPosts = Array.isArray(postsRes.data) ? postsRes.data : [];
      cachePostsForDetail(nextPosts);
      setPosts(nextPosts);
      setStats({
        posts: Number(userRes.data?.posts_count || nextPosts.length || 0),
        followers: Number(userRes.data?.followers_count || 0),
        following: Number(userRes.data?.following_count || 0),
      });
    } catch {
    } finally {
      setIsLoading(false);
    }
  }, [user?.id]);

  useEffect(() => {
    if (user?.id) void loadUserData();
  }, [loadUserData, user?.id]);

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

  const coverMedia = useMemo(() => (
    (user as any)?.cover_image || getPostMedia(posts[0]) || user?.profile_image || ''
  ), [posts, user]);

  if (isLoading || !user) {
    return (
      <SafeAreaView style={s.loadingContainer}>
        <ActivityIndicator size="large" color={colors.accentPrimary} />
      </SafeAreaView>
    );
  }

  const displayName = user.full_name || user.username || 'Flames';
  const username = user.username || user.email?.split('@')[0] || 'profile';
  const location = user.city || 'Flames-Up';

  return (
    <View style={s.root}>
      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} tintColor="#FFFFFF" />}
        contentContainerStyle={{ paddingBottom: 122 }}
      >
        <View style={s.hero}>
          {coverMedia ? (
            <MediaPreview uri={coverMedia} mediaTypes={posts[0]?.media_types} style={s.heroMedia} showVideoBadge={false} />
          ) : (
            <View style={s.heroFallback} />
          )}
          <View style={s.heroDim} />

          <View style={[s.topbar, { paddingTop: insets.top + 8 }]}>
            <TouchableOpacity style={s.roundNav} onPress={() => router.push('/(tabs)/home' as any)}>
              <Ionicons name="chevron-back" size={22} color="#FFFFFF" />
            </TouchableOpacity>
            <View style={s.topActions}>
              <TouchableOpacity style={s.roundNav} onPress={() => router.push('/(tabs)/messages' as any)}>
                <Ionicons name="chatbubble-outline" size={20} color="#FFFFFF" />
              </TouchableOpacity>
              <TouchableOpacity style={s.roundNav} onPress={() => setShowMore(true)}>
                <Ionicons name="ellipsis-horizontal" size={22} color="#FFFFFF" />
              </TouchableOpacity>
            </View>
          </View>

          <View style={s.identityBlock}>
            <View style={s.avatarRow}>
              <View style={s.avatar}>
                {user.profile_image ? (
                  <Image source={{ uri: user.profile_image }} style={s.avatarImage} />
                ) : (
                  <Text style={s.avatarInitial}>{displayName[0]?.toUpperCase() || 'F'}</Text>
                )}
              </View>
              <View style={s.smallBadge}>
                <Text style={s.smallBadgeText}>🌍</Text>
              </View>
            </View>

            <Text style={s.name}>{displayName}</Text>
            <Text style={s.meta}>iAm  @{username}  ·  {location}</Text>

            <View style={s.supportRow}>
              <View style={s.supportAvatars}>
                {posts.slice(0, 3).map((post, index) => {
                  const media = getPostMedia(post);
                  return (
                    <View key={post.id || index} style={[s.supportAvatar, { marginLeft: index === 0 ? 0 : -10 }]}>
                      {media ? <MediaPreview uri={media} mediaTypes={post.media_types} style={s.supportAvatarMedia} /> : <Text style={s.supportInitial}>{index + 1}</Text>}
                    </View>
                  );
                })}
              </View>
              <View>
                <Text style={s.supportCount}>{compact(stats.followers)}</Text>
                <Text style={s.supportLabel}>Supporters</Text>
              </View>
              <TouchableOpacity style={s.primaryAction} onPress={() => router.push('/edit-profile' as any)}>
                <Text style={s.primaryActionText}>Edit</Text>
              </TouchableOpacity>
              <TouchableOpacity style={s.secondaryAction}>
                <Text style={s.secondaryActionText}>Share</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>

        <View style={s.profileTabs}>
          <TouchableOpacity style={[s.profileTab, s.profileTabOn]}>
            <Ionicons name="bag-outline" size={22} color="#DFFF32" />
          </TouchableOpacity>
          <TouchableOpacity style={s.profileTab} onPress={() => router.push('/(tabs)/messages' as any)}>
            <Ionicons name="chatbubbles-outline" size={22} color="rgba(255,255,255,0.74)" />
          </TouchableOpacity>
          <TouchableOpacity style={s.profileTab}>
            <Ionicons name="grid-outline" size={22} color="rgba(255,255,255,0.74)" />
          </TouchableOpacity>
        </View>

        {user.bio ? (
          <Text style={s.bio}>{user.bio}</Text>
        ) : null}

        <View style={s.grid}>
          {posts.length === 0 ? (
            <View style={s.emptyPosts}>
              <Ionicons name="camera-outline" size={42} color="rgba(255,255,255,0.42)" />
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

      <Modal visible={showMore} transparent animationType="fade" onRequestClose={() => setShowMore(false)}>
        <Pressable style={s.menuOverlay} onPress={() => setShowMore(false)}>
          <View style={[s.menu, { top: insets.top + 54 }]}>
            <MenuItem icon="library-outline" label="My Library" onPress={() => router.push('/library' as any)} />
            {user?.is_admin ? (
              <MenuItem icon="shield-checkmark-outline" label="Governance Mobile" onPress={() => Alert.alert('Governance Mobile', 'Open the separate Governance Mobile app for moderation.')} />
            ) : null}
            <MenuItem icon="settings-outline" label="Settings" onPress={() => router.push('/settings' as any)} />
            {user.social_website ? (
              <MenuItem icon="globe-outline" label="Open website" onPress={() => Linking.openURL(user.social_website!.startsWith('http') ? user.social_website! : `https://${user.social_website}`)} />
            ) : null}
            <MenuItem danger icon="log-out-outline" label="Logout" onPress={handleLogout} />
          </View>
        </Pressable>
      </Modal>
    </View>
  );
}

function MenuItem({
  danger,
  icon,
  label,
  onPress,
}: {
  danger?: boolean;
  icon: keyof typeof Ionicons.glyphMap;
  label: string;
  onPress: () => void;
}) {
  return (
    <TouchableOpacity style={s.menuItem} onPress={onPress}>
      <Ionicons name={icon} size={20} color={danger ? '#FF5A5F' : '#FFFFFF'} />
      <Text style={[s.menuItemText, danger && s.menuItemTextDanger]}>{label}</Text>
    </TouchableOpacity>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#050505' },
  loadingContainer: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#050505' },
  hero: { height: Math.max(520, SCREEN_WIDTH * 1.52), backgroundColor: '#111111', overflow: 'hidden' },
  heroMedia: { ...StyleSheet.absoluteFillObject },
  heroFallback: { ...StyleSheet.absoluteFillObject, backgroundColor: '#171717' },
  heroDim: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.42)' },
  topbar: { position: 'absolute', left: 18, right: 18, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  topActions: { flexDirection: 'row', gap: 10 },
  roundNav: { width: 42, height: 42, borderRadius: 21, backgroundColor: 'rgba(0,0,0,0.32)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.16)', alignItems: 'center', justifyContent: 'center' },
  identityBlock: { position: 'absolute', left: 22, right: 22, bottom: 30 },
  avatarRow: { flexDirection: 'row', alignItems: 'center', marginBottom: 8 },
  avatar: { width: 62, height: 62, borderRadius: 31, borderWidth: 2, borderColor: '#FFFFFF', backgroundColor: '#FFFFFF', overflow: 'hidden', alignItems: 'center', justifyContent: 'center' },
  avatarImage: { width: '100%', height: '100%' },
  avatarInitial: { color: '#111111', fontSize: 26, fontWeight: '900' },
  smallBadge: { width: 54, height: 54, borderRadius: 27, marginLeft: -8, backgroundColor: '#6ED3FF', borderWidth: 2, borderColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center' },
  smallBadgeText: { fontSize: 28 },
  name: { color: '#FFFFFF', fontSize: 47, lineHeight: 49, fontWeight: '900', letterSpacing: 0 },
  meta: { color: 'rgba(255,255,255,0.78)', fontSize: 14, lineHeight: 18, fontWeight: '800', marginTop: 6 },
  supportRow: { flexDirection: 'row', alignItems: 'center', gap: 12, marginTop: 20 },
  supportAvatars: { flexDirection: 'row', minWidth: 66 },
  supportAvatar: { width: 32, height: 32, borderRadius: 16, borderWidth: 1.5, borderColor: '#FFFFFF', backgroundColor: '#222222', overflow: 'hidden', alignItems: 'center', justifyContent: 'center' },
  supportAvatarMedia: { width: '100%', height: '100%' },
  supportInitial: { color: '#FFFFFF', fontSize: 12, fontWeight: '900' },
  supportCount: { color: '#FFFFFF', fontSize: 21, lineHeight: 23, fontWeight: '900', fontVariant: ['tabular-nums'] },
  supportLabel: { color: 'rgba(255,255,255,0.72)', fontSize: 11, fontWeight: '700' },
  primaryAction: { marginLeft: 'auto', width: 70, height: 70, borderRadius: 35, backgroundColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center' },
  primaryActionText: { color: '#111111', fontSize: 12, fontWeight: '900' },
  secondaryAction: { width: 70, height: 70, borderRadius: 35, borderWidth: 1.4, borderColor: 'rgba(255,255,255,0.26)', backgroundColor: 'rgba(0,0,0,0.22)', alignItems: 'center', justifyContent: 'center' },
  secondaryActionText: { color: '#FFFFFF', fontSize: 12, fontWeight: '900' },
  profileTabs: { height: 58, marginTop: -1, flexDirection: 'row', backgroundColor: '#080808', borderTopWidth: 1, borderBottomWidth: 1, borderColor: 'rgba(255,255,255,0.08)' },
  profileTab: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  profileTabOn: { backgroundColor: '#171717' },
  bio: { color: 'rgba(255,255,255,0.78)', fontSize: 14, lineHeight: 20, fontWeight: '700', paddingHorizontal: 16, paddingVertical: 16 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: GRID_GAP, backgroundColor: '#050505' },
  tile: { width: TILE_SIZE, height: TILE_SIZE, overflow: 'hidden', backgroundColor: '#161616' },
  tileMedia: { width: '100%', height: '100%' },
  textTile: { flex: 1, padding: 10, justifyContent: 'center', backgroundColor: '#191919' },
  textTileText: { color: '#FFFFFF', fontSize: 12, lineHeight: 16, fontWeight: '800' },
  emptyPosts: { width: SCREEN_WIDTH, minHeight: 170, alignItems: 'center', justifyContent: 'center', gap: 8 },
  emptyText: { color: 'rgba(255,255,255,0.56)', fontSize: 14, fontWeight: '800' },
  menuOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.36)' },
  menu: { position: 'absolute', right: 14, width: 236, borderRadius: 18, backgroundColor: 'rgba(16,16,16,0.96)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.12)', overflow: 'hidden' },
  menuItem: { minHeight: 52, flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 16, borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.08)' },
  menuItemText: { color: '#FFFFFF', fontSize: 15, fontWeight: '800' },
  menuItemTextDanger: { color: '#FF5A5F' },
});
