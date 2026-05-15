import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
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
import { useRouter } from 'expo-router';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';

import MediaPreview from '../../src/components/MediaPreview';
import api from '../../src/api/client';
import { useAuthStore } from '../../src/store/authStore';
import { cachePostForDetail, cachePostsForDetail } from '../../src/store/postDetailCache';
import { borderRadius, colors, hitSlop, layout, spacing } from '../../src/utils/theme';
import { openSafeUrl } from '../../src/utils/safeLinking';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const GRID_GAP = 1;
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
    (user as any)?.profile_background_image || (user as any)?.cover_image || getPostMedia(posts[0]) || user?.profile_image || ''
  ), [posts, user]);

  if (isLoading || !user) {
    return (
      <SafeAreaView style={s.loadingContainer}>
        <View style={s.profileLoadingCard}>
          <View style={s.profileLoadingHero} />
          <View style={s.profileLoadingAvatar} />
          <View style={s.profileLoadingLine} />
          <View style={[s.profileLoadingLine, s.profileLoadingLineShort]} />
        </View>
      </SafeAreaView>
    );
  }

  const displayName = user.full_name || user.username || 'Flames';
  const username = user.username || user.email?.split('@')[0] || 'profile';
  const isPremium = !!(user as any)?.is_premium;

  return (
    <View style={s.root}>
      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ paddingBottom: 122 }}
      >
        <View style={s.hero}>
          {coverMedia ? (
            <MediaPreview uri={coverMedia} mediaTypes={posts[0]?.media_types} style={s.heroMedia} showVideoBadge={false} />
          ) : (
            <View style={s.heroFallback} />
          )}
          <View style={s.heroDim} />

          <View style={[s.topbar, { paddingTop: insets.top + 2 }]}>
            <TouchableOpacity style={s.roundNav} onPress={() => router.push('/(tabs)/home' as any)} hitSlop={hitSlop} accessibilityLabel="Back to home">
              <Ionicons name="chevron-back" size={22} color="#FFFFFF" />
            </TouchableOpacity>
            <View style={s.topActions}>
              <TouchableOpacity style={s.roundNav} onPress={() => router.push('/(tabs)/messages' as any)} hitSlop={hitSlop} accessibilityLabel="Open messages">
                <Ionicons name="chatbubble-outline" size={20} color="#FFFFFF" />
              </TouchableOpacity>
              <TouchableOpacity style={s.roundNav} onPress={() => setShowMore(true)} hitSlop={hitSlop} accessibilityLabel="Open profile menu">
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
                <Ionicons name="earth-outline" size={26} color="#FFFFFF" />
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
                <Text style={s.followStatValue}>{compact(stats.followers)}</Text>
                <Text style={s.followStatLabel}>Followers</Text>
              </View>
              <View style={s.followStat}>
                <Text style={s.followStatValue}>{compact(stats.following)}</Text>
                <Text style={s.followStatLabel}>Following</Text>
              </View>
              <TouchableOpacity style={s.primaryAction} onPress={() => router.push('/edit-profile' as any)} accessibilityLabel="Edit profile">
                <Text style={s.primaryActionText}>Edit</Text>
              </TouchableOpacity>
              <TouchableOpacity style={s.secondaryAction} accessibilityLabel="Share profile">
                <Text style={s.secondaryActionText}>Share</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>

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
          <View style={[s.menu, { top: insets.top + 48 }]}>
            <MenuItem icon="library-outline" label="My Library" onPress={() => router.push('/library' as any)} />
            <MenuItem icon="wallet-outline" label="Wallet" onPress={() => router.push('/wallet' as any)} />
            {user?.is_admin ? (
              <MenuItem icon="shield-checkmark-outline" label="Governance Mobile" onPress={() => Alert.alert('Governance Mobile', 'Open the separate Governance Mobile app for moderation.')} />
            ) : null}
            <MenuItem icon="settings-outline" label="Settings" onPress={() => router.push('/settings' as any)} />
            {user.social_website ? (
              <MenuItem icon="globe-outline" label="Open website" onPress={() => openSafeUrl(user.social_website)} />
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
  root: { flex: 1, backgroundColor: colors.bgApp },
  loadingContainer: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: colors.bgApp, paddingHorizontal: spacing.lg },
  profileLoadingCard: {
    width: '100%',
    maxWidth: 320,
    borderRadius: 30,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    padding: spacing.md,
    alignItems: 'center',
  },
  profileLoadingHero: {
    width: '100%',
    height: 112,
    borderRadius: 24,
    backgroundColor: colors.bgSubtle,
  },
  profileLoadingAvatar: {
    width: 74,
    height: 74,
    borderRadius: 37,
    marginTop: -37,
    backgroundColor: colors.accentPrimaryLight,
    borderWidth: 4,
    borderColor: colors.surfaceRaised,
  },
  profileLoadingLine: {
    width: '72%',
    height: 13,
    borderRadius: 7,
    backgroundColor: colors.bgSubtle,
    marginTop: spacing.md,
  },
  profileLoadingLineShort: {
    width: '45%',
    marginTop: spacing.sm,
  },
  hero: { height: Math.max(470, SCREEN_WIDTH * 1.32), backgroundColor: '#11120F', overflow: 'hidden' },
  heroMedia: { ...StyleSheet.absoluteFillObject },
  heroFallback: { ...StyleSheet.absoluteFillObject, backgroundColor: colors.surfaceTint },
  heroDim: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.32)' },
  topbar: { position: 'absolute', left: spacing.md, right: spacing.md, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  topActions: { flexDirection: 'row', gap: spacing.sm },
  roundNav: { width: layout.iconButton, height: layout.iconButton, borderRadius: layout.iconButton / 2, backgroundColor: 'rgba(12,16,11,0.42)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.20)', alignItems: 'center', justifyContent: 'center' },
  identityBlock: { position: 'absolute', left: spacing.lg, right: spacing.lg, bottom: spacing.xl },
  avatarRow: { flexDirection: 'row', alignItems: 'center', marginBottom: spacing.gutter },
  avatar: { width: 62, height: 62, borderRadius: 31, borderWidth: 2, borderColor: '#FFFFFF', backgroundColor: '#FFFFFF', overflow: 'hidden', alignItems: 'center', justifyContent: 'center' },
  avatarImage: { width: '100%', height: '100%' },
  avatarInitial: { color: '#111111', fontSize: 26, fontWeight: '500' },
  smallBadge: { width: 50, height: 50, borderRadius: 25, marginLeft: -8, backgroundColor: colors.accentPrimary, borderWidth: 2, borderColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center' },
  name: { color: '#FFFFFF', fontSize: 32, lineHeight: 37, fontWeight: '600', letterSpacing: 0 },
  meta: { color: 'rgba(255,255,255,0.78)', fontSize: 13, lineHeight: 18, fontWeight: '500', marginTop: 5 },
  metaRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, flexWrap: 'wrap' },
  premiumBadge: { height: 24, borderRadius: 12, backgroundColor: colors.accentLime, flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 9, marginTop: 6 },
  premiumBadgeText: { color: colors.textInverse, fontSize: 11, fontWeight: '600' },
  followStatsRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.gutter, marginTop: spacing.section },
  followStat: { minWidth: 70 },
  followStatValue: { color: '#FFFFFF', fontSize: 19, lineHeight: 23, fontWeight: '600', fontVariant: ['tabular-nums'] },
  followStatLabel: { color: 'rgba(255,255,255,0.72)', fontSize: 11, fontWeight: '500' },
  primaryAction: { marginLeft: 'auto', minWidth: 72, minHeight: 38, borderRadius: 19, backgroundColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center', paddingHorizontal: spacing.gutter },
  primaryActionText: { color: colors.textPrimary, fontSize: 13, fontWeight: '600' },
  secondaryAction: { minWidth: 78, minHeight: 38, borderRadius: borderRadius.full, borderWidth: 1.2, borderColor: 'rgba(255,255,255,0.30)', backgroundColor: 'rgba(0,0,0,0.24)', alignItems: 'center', justifyContent: 'center', paddingHorizontal: spacing.md },
  secondaryActionText: { color: '#FFFFFF', fontSize: 13, fontWeight: '500' },
  profileTabs: { height: 58, marginTop: -1, flexDirection: 'row', backgroundColor: '#080808', borderTopWidth: 1, borderBottomWidth: 1, borderColor: 'rgba(255,255,255,0.08)' },
  profileTab: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  profileTabOn: { backgroundColor: '#171717' },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: GRID_GAP, backgroundColor: 'rgba(17,17,17,0.14)' },
  tile: { width: TILE_SIZE, height: TILE_SIZE, overflow: 'hidden', backgroundColor: colors.bgSubtle },
  tileMedia: { width: '100%', height: '100%' },
  textTile: { flex: 1, padding: 10, justifyContent: 'center', backgroundColor: colors.surfaceTint },
  textTileText: { color: colors.textPrimary, fontSize: 12, lineHeight: 16, fontWeight: '600' },
  emptyPosts: { width: SCREEN_WIDTH, minHeight: 190, alignItems: 'center', justifyContent: 'center', gap: 8, backgroundColor: colors.bgApp },
  emptyText: { color: colors.textHint, fontSize: 14, fontWeight: '500' },
  menuOverlay: { flex: 1, backgroundColor: colors.modalScrim },
  menu: { position: 'absolute', right: spacing.md, width: 236, borderRadius: borderRadius.xl, backgroundColor: 'rgba(16,16,16,0.96)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.12)', overflow: 'hidden' },
  menuItem: { minHeight: 52, flexDirection: 'row', alignItems: 'center', gap: spacing.gutter, paddingHorizontal: spacing.md, borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.08)' },
  menuItemText: { color: '#FFFFFF', fontSize: 15, fontWeight: '500' },
  menuItemTextDanger: { color: '#FF5A5F' },
});
