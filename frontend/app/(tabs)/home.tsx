import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, FlatList,
  RefreshControl, Dimensions, ScrollView, Image, Alert, Share,
  Modal, Pressable, ActivityIndicator, Platform, TextInput, KeyboardAvoidingView,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useFocusEffect, useNavigation, useRouter } from 'expo-router';
import { useIsFocused } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { Audio, ResizeMode, Video } from 'expo-av';
import { useAuthStore } from '../../src/store/authStore';
import { cachePostForDetail, cachePostsForDetail, setPostDetailFeedContext } from '../../src/store/postDetailCache';
import api, { API_URL } from '../../src/api/client';
import { rankFeed, RecommendationItem } from '../../src/recommendation';
import { requireVerifiedPhone } from '../../src/utils/phoneVerification';
import MediaPreview from '../../src/components/MediaPreview';
import { colors } from '../../src/utils/theme';
import { extractStreamUid, getStreamPlaybackInfo, isCFStreamVideo } from '../../src/utils/mediaUpload';
import { getAudiusTrackStream, soundFromPost } from '../../src/utils/music';

const { width: SW, height: SH } = Dimensions.get('window');

const HOME_TABS = [
  { id: 'world', label: 'World Board' },
  { id: 'foryou', label: 'For You' },
] as const;

const WORLD_BOARD_SECTIONS = [
  { label: 'Trending', kind: 'trending' },
  { label: 'Fresh', kind: 'fresh' },
  { label: 'Latest', kind: 'latest' },
  { label: 'Explore More', kind: 'explore' },
] as const;

function engagementScore(post: any): number {
  return Number(post.likes_count || 0) * 4
    + Number(post.comments_count || 0) * 6
    + Number(post.shares_count || 0) * 7
    + Number(post.saves_count || 0) * 5
    + Number(post.views_count || 0);
}

function uniquePosts(posts: any[]): any[] {
  const seen = new Set<string>();
  return posts.filter((post) => {
    const id = String(post.id || '');
    if (!id || seen.has(id)) return false;
    seen.add(id);
    return true;
  });
}

function parsePostImages(value: unknown): string[] {
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

type EditorOverlay =
  | { type: 'text'; text: string; x: number; y: number; width?: number }
  | { type: 'media'; media_index?: number; uri?: string; x: number; y: number; width?: number };

function parseEditorOverlays(value: unknown): EditorOverlay[] {
  let raw: any[] = [];
  if (Array.isArray(value)) {
    raw = value;
  } else if (typeof value === 'string' && value.trim()) {
    try {
      const parsed = JSON.parse(value);
      raw = Array.isArray(parsed) ? parsed : [];
    } catch {
      raw = [];
    }
  }

  const overlays: EditorOverlay[] = [];
  raw.forEach((item) => {
    if (!item || typeof item !== 'object') return;
    const x = Math.min(0.96, Math.max(0.04, Number(item.x || 0.5)));
    const y = Math.min(0.96, Math.max(0.04, Number(item.y || 0.5)));
    if (item.type === 'text') {
      const width = Math.min(0.9, Math.max(0.18, Number(item.width || 0.72)));
      const text = String(item.text || '').trim();
      if (text) overlays.push({ type: 'text', text, x, y, width });
      return;
    }
    if (item.type === 'media') {
      const width = Math.min(0.46, Math.max(0.18, Number(item.width || 0.32)));
      const mediaIndex = Number.isFinite(Number(item.media_index)) ? Number(item.media_index) : undefined;
      const uri = typeof item.uri === 'string' ? item.uri : undefined;
      overlays.push({ type: 'media', media_index: mediaIndex, uri, x, y, width });
    }
  });
  return overlays;
}

function getPrimaryMediaUri(post: any): string {
  const candidates = [
    typeof post?.image === 'string' ? post.image : '',
    ...parsePostImages(post?.images),
  ];
  return candidates.find((uri) => (
    uri.startsWith('http')
    || uri.startsWith('data:')
    || uri.startsWith('cfstream:')
  )) || '';
}

function hasBoardContent(post: any): boolean {
  return !!getPrimaryMediaUri(post) || String(post?.content || '').trim().length > 0;
}

function postTitle(post: any): string {
  const content = String(post?.content || '').trim();
  if (content) return content;
  if (post?.place_name) return String(post.place_name);
  return 'New post';
}

function postCaption(post: any): string {
  return String(post?.content || post?.caption || '').replace(/\s+/g, ' ').trim();
}

function avatarInitial(post: any): string {
  const source = String(post?.user_full_name || post?.user_username || 'F');
  return source.trim().slice(0, 1).toUpperCase() || 'F';
}

function formatCompactCount(value: unknown): string {
  const count = Math.max(0, Number(value || 0));
  if (count >= 1000000) {
    return `${(count / 1000000).toFixed(count >= 10000000 ? 0 : 1).replace(/\.0$/, '')}M`;
  }
  if (count >= 1000) {
    return `${(count / 1000).toFixed(count >= 10000 ? 0 : 1).replace(/\.0$/, '')}K`;
  }
  return String(Math.round(count));
}

function commentName(comment: any): string {
  return comment?.user_full_name || comment?.user_username || 'User';
}

function commentInitial(comment: any): string {
  return String(commentName(comment)).trim().slice(0, 1).toUpperCase() || 'U';
}

function commentThreads(comments: any[]) {
  const topLevel: any[] = [];
  const repliesByParent = new Map<string, any[]>();

  comments.forEach((comment) => {
    const parentId = comment?.parent_id ? String(comment.parent_id) : '';
    if (parentId) {
      const replies = repliesByParent.get(parentId) || [];
      replies.push(comment);
      repliesByParent.set(parentId, replies);
    } else {
      topLevel.push(comment);
    }
  });

  return topLevel.map((comment) => ({
    ...comment,
    replies: repliesByParent.get(String(comment.id)) || [],
  }));
}

function normalizeMediaTypes(mediaTypes?: string[] | string | null): string[] {
  if (Array.isArray(mediaTypes)) return mediaTypes.map((item) => String(item).toLowerCase());
  if (typeof mediaTypes === 'string') {
    try {
      const parsed = JSON.parse(mediaTypes);
      if (Array.isArray(parsed)) return parsed.map((item) => String(item).toLowerCase());
    } catch {}
    return mediaTypes.split(',').map((item) => item.trim().toLowerCase()).filter(Boolean);
  }
  return [];
}

function isVideoMedia(uri?: string | null, mediaTypes?: string[] | string | null) {
  if (!uri) return false;
  if (isCFStreamVideo(uri)) return true;
  if (/^data:video\//i.test(uri)) return true;
  if (/\.(mp4|mov|m4v|webm|m3u8)(\?.*)?$/i.test(uri)) return true;
  if (/\.(jpe?g|png|webp|gif|heic|heif|avif)(\?.*)?$/i.test(uri)) return false;
  if (normalizeMediaTypes(mediaTypes).some((type) => type.includes('video'))) return true;
  return false;
}

function isVideoMediaAt(uri?: string | null, mediaTypes?: string[] | string | null, index = 0) {
  if (!uri) return false;
  if (isCFStreamVideo(uri)) return true;
  if (/^data:video\//i.test(uri)) return true;
  if (/\.(mp4|mov|m4v|webm|m3u8)(\?.*)?$/i.test(uri)) return true;
  if (/\.(jpe?g|png|webp|gif|heic|heif|avif)(\?.*)?$/i.test(uri)) return false;
  const type = normalizeMediaTypes(mediaTypes)[index] || '';
  if (type.includes('video')) return true;
  return false;
}

function getPrimaryVideoMediaUri(post: any): string {
  const images = parsePostImages(post?.images);
  const candidates = images.map((uri, index) => ({ uri, index }));
  const primary = typeof post?.image === 'string' ? post.image : '';
  if (primary && !images.includes(primary)) candidates.unshift({ uri: primary, index: 0 });

  return candidates.find(({ uri, index }) => (
    (uri.startsWith('http') || uri.startsWith('data:') || uri.startsWith('cfstream:'))
    && isVideoMediaAt(uri, post?.media_types, index)
  ))?.uri || '';
}

function hasVideoBoardContent(post: any): boolean {
  return !!getPrimaryVideoMediaUri(post);
}

function ForYouMedia({ active, mediaTypes, muted, paused, uri }: { active: boolean; mediaTypes?: string[] | string | null; muted?: boolean; paused: boolean; uri: string }) {
  const videoRef = useRef<any>(null);
  const [streamUri, setStreamUri] = useState('');
  const [ready, setReady] = useState(false);
  const video = isVideoMedia(uri, mediaTypes);

  useEffect(() => {
    let mounted = true;
    setStreamUri('');
    setReady(false);
    if (!uri || !isCFStreamVideo(uri)) return () => { mounted = false; };

    getStreamPlaybackInfo(extractStreamUid(uri)).then((info) => {
      if (mounted && info?.hls) setStreamUri(info.hls);
    });

    return () => {
      mounted = false;
    };
  }, [uri]);

  const playbackUri = isCFStreamVideo(uri) ? streamUri : uri;

  useEffect(() => {
    if (!videoRef.current || !video) return;
    if (!active || paused) {
      videoRef.current.pauseAsync?.().catch?.(() => undefined);
      videoRef.current.setIsMutedAsync?.(true).catch?.(() => undefined);
      return;
    }
    videoRef.current.setIsMutedAsync?.(!!muted).catch?.(() => undefined);
    videoRef.current.playAsync?.().catch?.(() => undefined);
  }, [active, muted, paused, playbackUri, video]);

  useEffect(() => () => {
    videoRef.current?.pauseAsync?.().catch?.(() => undefined);
  }, []);

  if (video && playbackUri) {
    return (
      <View style={s.feedMedia}>
        <Video
          ref={videoRef}
          source={{ uri: playbackUri }}
          style={s.feedMedia}
          resizeMode={ResizeMode.COVER}
          shouldPlay={active && !paused}
          isLooping
          isMuted={!active || paused || !!muted}
          volume={active && !paused && !muted ? 1 : 0}
          progressUpdateIntervalMillis={250}
          onLoadStart={() => setReady(false)}
          onLoad={() => setReady(true)}
          onReadyForDisplay={() => setReady(true)}
        />
        {!ready ? (
          <View pointerEvents="none" style={s.feedLoadingCover}>
            <MediaPreview uri={uri} mediaTypes={mediaTypes} style={s.feedMedia} resizeMode="cover" showVideoBadge={false} />
            <View style={s.feedLoadingScrim}>
              <ActivityIndicator color="#FFFFFF" />
            </View>
          </View>
        ) : null}
      </View>
    );
  }

  return <MediaPreview uri={uri} mediaTypes={mediaTypes} style={s.feedMedia} resizeMode="cover" showVideoBadge={false} />;
}

function ForYouDoodleBackground() {
  return <View pointerEvents="none" style={s.forYouPatternLayer} />;
}

export default function HomeScreen() {
  const router = useRouter();
  const navigation = useNavigation();
  const insets = useSafeAreaInsets();
  const isFocused = useIsFocused();
  const { user } = useAuthStore();
  const [filter, setFilter] = useState('world');
  const [posts, setPosts] = useState<any[]>([]);
  const [likedPostIds, setLikedPostIds] = useState<Set<string>>(new Set());
  const [pausedPostIds, setPausedPostIds] = useState<Set<string>>(new Set());
  const [activeForYouPostId, setActiveForYouPostId] = useState('');
  const [followedUserIds, setFollowedUserIds] = useState<Set<string>>(new Set());
  const [shareTarget, setShareTarget] = useState<any | null>(null);
  const [shareFriends, setShareFriends] = useState<any[]>([]);
  const [isShareLoading, setIsShareLoading] = useState(false);
  const [sendingToId, setSendingToId] = useState<string | null>(null);
  const [commentTarget, setCommentTarget] = useState<any | null>(null);
  const [comments, setComments] = useState<any[]>([]);
  const [commentText, setCommentText] = useState('');
  const [replyingTo, setReplyingTo] = useState<any | null>(null);
  const [commentsLoading, setCommentsLoading] = useState(false);
  const [commentSending, setCommentSending] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [unreadNotifications, setUnreadNotifications] = useState(0);
  const userLat = 40.7128;
  const userLng = -74.006;
  const feedCardHeight = filter === 'foryou' ? Math.max(650, SH - insets.bottom) : Math.max(590, SH - insets.top - insets.bottom - 96);
  const forYouMediaWidth = Math.min(SW - 16, 450);
  const forYouMediaHeight = Math.min(
    Math.round(forYouMediaWidth * 1.22),
    Math.max(500, feedCardHeight - insets.top - Math.max(insets.bottom, 18) - 76)
  );
  const forYouMediaTop = Math.max(insets.top + 58, Math.round((feedCardHeight - forYouMediaHeight) / 2));
  const threadedComments = useMemo(() => commentThreads(comments), [comments]);
  const feedAudioRef = useRef<Audio.Sound | null>(null);
  const feedAudioKeyRef = useRef('');
  const feedAudioRunIdRef = useRef(0);
  const forYouViewabilityConfig = useRef({ itemVisiblePercentThreshold: 58, minimumViewTime: 40 }).current;
  const onForYouViewableItemsChanged = useRef(({ viewableItems }: { viewableItems: { item?: any; isViewable?: boolean }[] }) => {
    const visible = viewableItems.find((entry) => entry.isViewable && entry.item?.id);
    if (visible?.item?.id) setActiveForYouPostId(String(visible.item.id));
  }).current;

  useEffect(() => {
    Audio.setAudioModeAsync({
      playsInSilentModeIOS: true,
      shouldDuckAndroid: true,
      playThroughEarpieceAndroid: false,
      staysActiveInBackground: false,
    }).catch(() => {});
  }, []);

  const unloadFeedAudio = useCallback(async () => {
    const existing = feedAudioRef.current;
    feedAudioRef.current = null;
    feedAudioKeyRef.current = '';
    if (existing) {
      await existing.stopAsync().catch(() => undefined);
      await existing.unloadAsync().catch(() => undefined);
    }
  }, []);

  const stopFeedAudio = useCallback(async () => {
    feedAudioRunIdRef.current += 1;
    await unloadFeedAudio();
  }, [unloadFeedAudio]);

  useEffect(() => () => {
    feedAudioRunIdRef.current += 1;
    void unloadFeedAudio();
  }, [unloadFeedAudio]);

  useEffect(() => {
    if (!isFocused) void stopFeedAudio();
  }, [isFocused, stopFeedAudio]);

  useEffect(() => {
    const tabBarStyle = filter === 'foryou'
      ? { display: 'none' as const }
      : {
          backgroundColor: colors.bgCard,
          borderTopColor: colors.borderLight,
          borderTopWidth: 1,
          height: Platform.OS === 'ios' ? 88 : 64,
          paddingTop: 8,
          paddingBottom: Platform.OS === 'ios' ? 28 : 8,
        };
    navigation.setOptions({ tabBarStyle });
  }, [filter, navigation]);

  const rankPosts = useCallback((rawPosts: any[]) => {
    const interestTokens = String(user?.interests || '')
      .split(',')
      .map((s: string) => s.trim().toLowerCase())
      .filter(Boolean);

    const items: RecommendationItem[] = rawPosts.map((p: any) => ({
      id: String(p.id),
      authorId: p.user_id ? String(p.user_id) : '',
      category: String(p.category || p.post_type || ''),
      content: String(p.content || ''),
      location: String(p.location || p.place_name || ''),
      createdAtMs: Number(Date.parse(p.created_at || '') || Date.now()),
      likes: Number(p.likes_count || 0),
      comments: Number(p.comments_count || 0),
      shares: Number(p.shares_count || 0),
      saves: Number(p.saves_count || 0),
      impressions: Number(p.views_count || 0),
      lat: p.place_lat !== undefined && p.place_lat !== null ? Number(p.place_lat) : undefined,
      lng: p.place_lng !== undefined && p.place_lng !== null ? Number(p.place_lng) : undefined,
      original: p,
    }));

    const ranked = rankFeed(
      items,
      {
        userId: user?.id,
        interests: interestTokens,
        nowMs: Date.now(),
        userLat,
        userLng,
      },
      { maxItems: items.length, lambda: 0.82, halfLifeHours: 40 }
    );

    return ranked.map((r) => r.original);
  }, [user?.id, user?.interests, userLat, userLng]);

  const loadPublicWorldBoard = useCallback(async () => {
    const response = await fetch(`${API_URL}/api/posts/world-board?limit=60`);
    if (!response.ok) return [];
    const data = await response.json();
    return Array.isArray(data) ? data : [];
  }, []);

  const loadData = useCallback(async () => {
    let raw: any[] = [];
    try {
      const r = await api.get('/posts/feed', { params: { limit: 60 } });
      raw = Array.isArray(r.data) ? r.data : [];
    } catch {
      try {
        raw = await loadPublicWorldBoard();
      } catch {}
    }

    if (raw.length === 0) {
      try {
        raw = await loadPublicWorldBoard();
      } catch {}
    }

    const ranked = rankPosts(raw);
    cachePostsForDetail(ranked);
    setPostDetailFeedContext(ranked.map((post) => post.id));
    setPosts(ranked);
    if (user?.id) {
      setLikedPostIds(new Set(
        ranked
          .filter((post) => Array.isArray(post.liked_by) && post.liked_by.map(String).includes(String(user.id)))
          .map((post) => String(post.id))
      ));
    }
  }, [loadPublicWorldBoard, rankPosts, user?.id]);

  const loadUnreadNotifications = useCallback(async () => {
    if (!user?.id) {
      setUnreadNotifications(0);
      return;
    }
    try {
      const response = await api.get('/notifications/unread-count');
      setUnreadNotifications(Math.max(0, Number(response.data?.count || 0)));
    } catch {
      setUnreadNotifications(0);
    }
  }, [user?.id]);

  useEffect(() => { loadData(); }, [loadData]);

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await Promise.all([loadData(), loadUnreadNotifications()]);
    setRefreshing(false);
  }, [loadData, loadUnreadNotifications]);

  useFocusEffect(useCallback(() => {
    loadUnreadNotifications();
    return () => {
      void stopFeedAudio();
      setActiveForYouPostId('');
    };
  }, [loadUnreadNotifications, stopFeedAudio]));

  const filtered = useMemo(() => posts, [posts]);
  const boardItems = useMemo(() => filtered.filter(hasBoardContent), [filtered]);
  const forYouItems = useMemo(() => boardItems.filter(hasVideoBoardContent), [boardItems]);
  const items = filter === 'foryou' ? forYouItems : boardItems;

  useEffect(() => {
    const runId = ++feedAudioRunIdRef.current;
    let cancelled = false;
    const isCurrentRun = () => !cancelled && runId === feedAudioRunIdRef.current;

    const playAttachedSound = async () => {
      if (!isFocused || filter !== 'foryou') {
        await unloadFeedAudio();
        return;
      }

      const activePost = items.find((post) => String(post.id) === String(activeForYouPostId));
      const attachedSound = soundFromPost(activePost);
      if (!activePost || !attachedSound || pausedPostIds.has(String(activePost.id))) {
        await unloadFeedAudio();
        return;
      }

      const startMs = Math.max(0, Number(attachedSound.audio_start_time || 0) * 1000);
      const durationMs = Math.max(5000, Number(attachedSound.audio_duration || 15) * 1000);
      const endMs = startMs + durationMs;
      const key = `${activePost.id}:${attachedSound.audio_track_id}:${startMs}:${durationMs}`;
      if (feedAudioKeyRef.current === key && feedAudioRef.current) {
        await feedAudioRef.current.playAsync().catch(() => undefined);
        return;
      }

      await unloadFeedAudio();
      let streamUrl = '';
      try {
        const streamTrack = await getAudiusTrackStream(attachedSound.audio_track_id);
        streamUrl = streamTrack.stream_url || attachedSound.audio_stream_url || '';
      } catch {
        streamUrl = attachedSound.audio_stream_url || '';
      }
      if (!streamUrl || !isCurrentRun()) return;

      await Audio.setAudioModeAsync({
        playsInSilentModeIOS: true,
        shouldDuckAndroid: false,
        playThroughEarpieceAndroid: false,
        staysActiveInBackground: false,
      }).catch(() => undefined);

      const { sound } = await Audio.Sound.createAsync(
        { uri: streamUrl },
        { shouldPlay: false, positionMillis: startMs, volume: 1, isLooping: false }
      );
      if (!isCurrentRun()) {
        await sound.stopAsync().catch(() => undefined);
        await sound.unloadAsync().catch(() => undefined);
        return;
      }
      sound.setOnPlaybackStatusUpdate((status: any) => {
        if (!isCurrentRun()) return;
        if (!status?.isLoaded) return;
        if (status.positionMillis >= endMs || status.didJustFinish) {
          sound.setPositionAsync(startMs).then(() => sound.playAsync()).catch(() => undefined);
        }
      });
      feedAudioRef.current = sound;
      feedAudioKeyRef.current = key;
      await sound.playAsync().catch(() => undefined);
    };

    playAttachedSound().catch(() => {
      if (isCurrentRun()) void unloadFeedAudio();
    });
    return () => {
      cancelled = true;
      if (feedAudioRunIdRef.current === runId) feedAudioRunIdRef.current += 1;
      void unloadFeedAudio();
    };
  }, [activeForYouPostId, filter, isFocused, items, pausedPostIds, unloadFeedAudio]);

  useEffect(() => {
    if (filter !== 'foryou') {
      setActiveForYouPostId('');
      return;
    }
    if (!items.length) return;
    const stillVisible = items.some((post) => String(post.id) === activeForYouPostId);
    if (!activeForYouPostId || !stillVisible) setActiveForYouPostId(String(items[0].id));
  }, [activeForYouPostId, filter, items]);

  const WORLD_GAP = 2;
  const WORLD_TILE_WIDTH = Math.floor((SW - WORLD_GAP * 2) / 3);
  const WORLD_TILE_HEIGHT = Math.round(WORLD_TILE_WIDTH * 1.24);
  const postSections = useMemo(() => {
    const sections: Record<string, any[]> = {};
    if (boardItems.length === 0) return sections;

    const newest = [...boardItems].sort((a, b) => Date.parse(b.created_at || '') - Date.parse(a.created_at || ''));
    const trending = [...boardItems].sort((a, b) => {
      const recencyA = Math.max(0, 72 - ((Date.now() - Date.parse(a.created_at || '')) / 3600000));
      const recencyB = Math.max(0, 72 - ((Date.now() - Date.parse(b.created_at || '')) / 3600000));
      return (engagementScore(b) + recencyB) - (engagementScore(a) + recencyA);
    });
    const fresh = newest.filter((post) => Date.now() - Date.parse(post.created_at || '') < 1000 * 60 * 60 * 72);

    for (const section of WORLD_BOARD_SECTIONS) {
      let source = boardItems;
      if (section.kind === 'trending') source = trending;
      if (section.kind === 'fresh') source = fresh.length > 0 ? fresh : newest;
      if (section.kind === 'latest') source = newest;
      if (section.kind === 'explore') source = [...boardItems].reverse();

      const slice = uniquePosts(source).slice(0, 12);
      if (slice.length > 0) sections[section.label] = slice;
    }

    return sections;
  }, [boardItems]);

  const worldBoardSections = useMemo(() => Object.entries(postSections), [postSections]);

  const openPostDetail = useCallback((post: any) => {
    cachePostForDetail(post);
    setPostDetailFeedContext(boardItems.map((item) => item.id));
    router.push(`/post/${post.id}` as any);
  }, [boardItems, router]);

  const openCreatePost = () => {
    if (!requireVerifiedPhone(user, router, 'create posts')) return;
    router.push('/create-post' as any);
  };

  const followUser = async (post: any) => {
    if (!user) {
      router.push('/(auth)/login' as any);
      return;
    }
    if (!post?.user_id || post.user_id === user.id) return;

    const userId = String(post.user_id);
    const wasFollowing = followedUserIds.has(userId);
    setFollowedUserIds((prev) => {
      const next = new Set(prev);
      if (wasFollowing) next.delete(userId);
      else next.add(userId);
      return next;
    });

    try {
      const response = await api.post(`/users/${post.user_id}/follow`);
      if (typeof response.data?.following === 'boolean') {
        setFollowedUserIds((prev) => {
          const next = new Set(prev);
          if (response.data.following) next.add(userId);
          else next.delete(userId);
          return next;
        });
      }
    } catch (error: any) {
      setFollowedUserIds((prev) => {
        const next = new Set(prev);
        if (wasFollowing) next.add(userId);
        else next.delete(userId);
        return next;
      });
      Alert.alert('Follow failed', error?.response?.data?.detail || 'Could not follow this user.');
    }
  };

  const toggleLike = async (post: any) => {
    if (!user) {
      router.push('/(auth)/login' as any);
      return;
    }

    const postId = String(post.id);
    const wasLiked = likedPostIds.has(postId);
    setLikedPostIds((prev) => {
      const next = new Set(prev);
      if (wasLiked) next.delete(postId);
      else next.add(postId);
      return next;
    });
    setPosts((prev) => prev.map((item) => (
      String(item.id) === postId
        ? { ...item, likes_count: Math.max(0, Number(item.likes_count || 0) + (wasLiked ? -1 : 1)) }
        : item
    )));

    try {
      await api.post(`/posts/${post.id}/like`);
    } catch (error: any) {
      setLikedPostIds((prev) => {
        const next = new Set(prev);
        if (wasLiked) next.add(postId);
        else next.delete(postId);
        return next;
      });
      setPosts((prev) => prev.map((item) => (
        String(item.id) === postId
          ? { ...item, likes_count: Math.max(0, Number(item.likes_count || 0) + (wasLiked ? 1 : -1)) }
          : item
      )));
      Alert.alert('Like failed', error?.response?.data?.detail || 'Could not update this like.');
    }
  };

  const togglePause = (post: any) => {
    const postId = String(post.id);
    setPausedPostIds((prev) => {
      const next = new Set(prev);
      if (next.has(postId)) next.delete(postId);
      else next.add(postId);
      return next;
    });
  };

  const postLink = (post: any) => `https://flames-up.com/post/${post.id}`;

  const loadShareFriends = async () => {
    if (!user) return;
    setIsShareLoading(true);
    try {
      const conversationsRes = await api.get('/conversations');
      const fromConversations = Array.isArray(conversationsRes.data)
        ? conversationsRes.data
            .filter((item: any) => item.type !== 'group' && item.other_user?.id)
            .map((item: any) => item.other_user)
        : [];
      if (fromConversations.length > 0) {
        setShareFriends(fromConversations.slice(0, 12));
        return;
      }

      const suggestedRes = await api.get('/discover/suggested-users');
      setShareFriends(Array.isArray(suggestedRes.data) ? suggestedRes.data.slice(0, 12) : []);
    } catch {
      setShareFriends([]);
    } finally {
      setIsShareLoading(false);
    }
  };

  const openShareSheet = (post: any) => {
    setShareTarget(post);
    loadShareFriends();
  };

  const sharePostSystem = async (post: any) => {
    try {
      await Share.share({
        title: postTitle(post),
        message: `${postTitle(post)}\n${postLink(post)}`,
      });
    } catch (error: any) {
      Alert.alert('Share failed', error?.message || 'Could not open the share sheet.');
    }
  };

  const copyPostLink = async (post: any) => {
    const link = postLink(post);
    try {
      const clipboard = typeof navigator !== 'undefined' ? navigator.clipboard : undefined;
      if (clipboard?.writeText) {
        await clipboard.writeText(link);
        Alert.alert('Copied', 'Post link copied.');
      } else {
        await Share.share({ message: link });
      }
    } catch {
      Alert.alert('Copy failed', 'Could not copy this link.');
    }
  };

  const sendPostToFriend = (friend: any) => {
    if (!shareTarget) return;
    if (!requireVerifiedPhone(user, router, 'send messages')) return;
    const friendName = friend.full_name || friend.username || 'this friend';
    Alert.alert(
      'Send post?',
      `Send this post to ${friendName}?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Send',
          onPress: async () => {
            setSendingToId(String(friend.id));
            try {
              await api.post('/messages', {
                receiver_id: friend.id,
                content: `${postTitle(shareTarget)}\n${postLink(shareTarget)}`,
              });
              Alert.alert('Sent', `Post sent to ${friendName}.`);
            } catch (error: any) {
              Alert.alert('Send failed', error?.response?.data?.detail || 'Could not send this post.');
            } finally {
              setSendingToId(null);
            }
          },
        },
      ]
    );
  };

  const reportPost = (post: any) => {
    Alert.alert(
      'Report this post?',
      'This sends a report to Flames moderation.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Report',
          style: 'destructive',
          onPress: async () => {
            try {
              await api.post('/reports', {
                reported_type: 'post',
                reported_id: post.user_id || post.id,
                report_type: 'post',
                content_id: post.id,
                reason: 'Reported from For You',
                details: 'User reported this post from the share menu.',
              });
              Alert.alert('Reported', 'Thanks. We sent this to moderation.');
              setShareTarget(null);
            } catch (error: any) {
              Alert.alert('Report failed', error?.response?.data?.detail || 'Could not report this post.');
            }
          },
        },
      ]
    );
  };

  const openCreateWithSound = (post: any) => {
    const sound = soundFromPost(post);
    if (!sound) return;
    router.push({
      pathname: '/create-post',
      params: {
        audio_provider: sound.audio_provider,
        audio_track_id: sound.audio_track_id,
        audio_title: sound.audio_title,
        audio_artist: sound.audio_artist,
        audio_artwork_url: sound.audio_artwork_url,
        audio_stream_url: sound.audio_stream_url,
        audio_start_time: String(sound.audio_start_time || 0),
        audio_duration: String(sound.audio_duration || 15),
      },
    } as any);
  };

  const reportSound = (post: any) => {
    const sound = soundFromPost(post);
    if (!sound) return;
    Alert.alert(
      'Report this sound?',
      'This sends the audio to Flames moderation.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Report sound',
          style: 'destructive',
          onPress: async () => {
            try {
              await api.post('/reports', {
                reported_type: 'sound',
                reported_id: sound.audio_track_id,
                report_type: 'sound',
                content_id: post.id,
                reason: 'Reported sound',
                details: `${sound.audio_title} - ${sound.audio_artist}`,
              });
              Alert.alert('Reported', 'Thanks. We sent this sound to moderation.');
              setShareTarget(null);
            } catch (error: any) {
              Alert.alert('Report failed', error?.response?.data?.detail || 'Could not report this sound.');
            }
          },
        },
      ]
    );
  };

  const markNotInterested = (post: any) => {
    setPosts((prev) => prev.filter((item) => String(item.id) !== String(post.id)));
    setShareTarget(null);
  };

  const openComments = async (post: any) => {
    setCommentTarget(post);
    setCommentText('');
    setReplyingTo(null);
    setComments([]);
    setCommentsLoading(true);
    try {
      const response = await api.get(`/posts/${post.id}/comments`);
      setComments(Array.isArray(response.data) ? response.data : []);
    } catch (error: any) {
      Alert.alert('Comments failed', error?.response?.data?.detail || 'Could not load comments.');
    } finally {
      setCommentsLoading(false);
    }
  };

  const submitComment = async () => {
    if (!commentTarget) return;
    const content = commentText.trim();
    if (!content) return;
    setCommentSending(true);
    try {
      const response = await api.post(`/posts/${commentTarget.id}/comments`, {
        content,
        parent_id: replyingTo?.id || null,
      });
      setComments((prev) => [...prev, response.data]);
      setCommentText('');
      setReplyingTo(null);
      setPosts((prev) => prev.map((post) => (
        String(post.id) === String(commentTarget.id)
          ? { ...post, comments_count: Number(post.comments_count || 0) + 1 }
          : post
      )));
      setCommentTarget((prev: any) => prev ? { ...prev, comments_count: Number(prev.comments_count || 0) + 1 } : prev);
    } catch (error: any) {
      Alert.alert('Comment failed', error?.response?.data?.detail || 'Could not post comment.');
    } finally {
      setCommentSending(false);
    }
  };

  const toggleCommentLike = async (comment: any) => {
    const commentId = String(comment.id || '');
    if (!commentId) return;
    const wasLiked = !!comment.liked_by_me;
    const nextLikes = Math.max(0, Number(comment.likes_count || 0) + (wasLiked ? -1 : 1));
    setComments((prev) => prev.map((item) => (
      String(item.id) === commentId
        ? { ...item, liked_by_me: !wasLiked, likes_count: nextLikes }
        : item
    )));

    try {
      const response = await api.post(`/comments/${commentId}/like`);
      setComments((prev) => prev.map((item) => (
        String(item.id) === commentId
          ? { ...item, liked_by_me: !!response.data?.liked, likes_count: Number(response.data?.likes_count || 0) }
          : item
      )));
    } catch (error: any) {
      setComments((prev) => prev.map((item) => (
        String(item.id) === commentId
          ? { ...item, liked_by_me: wasLiked, likes_count: Number(comment.likes_count || 0) }
          : item
      )));
      Alert.alert('Like failed', error?.response?.data?.detail || 'Could not like this comment.');
    }
  };

  const reportComment = (comment: any) => {
    Alert.alert(
      'Report this comment?',
      'This sends the comment to Flames moderation.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Report',
          style: 'destructive',
          onPress: async () => {
            try {
              await api.post('/reports', {
                reported_type: 'comment',
                reported_id: comment.id,
                report_type: 'comment',
                content_id: comment.post_id || commentTarget?.id,
                reason: 'Reported comment',
                details: String(comment.content || '').slice(0, 500),
              });
              Alert.alert('Reported', 'Thanks. We sent this to moderation.');
            } catch (error: any) {
              Alert.alert('Report failed', error?.response?.data?.detail || 'Could not report this comment.');
            }
          },
        },
      ]
    );
  };

  const closeComments = () => {
    setCommentTarget(null);
    setReplyingTo(null);
    setCommentText('');
  };

  const renderCommentItem = (comment: any, isReply = false) => {
    const liked = !!comment.liked_by_me;
    return (
      <View key={comment.id} style={[s.commentThread, isReply && s.commentThreadReply]}>
        <Pressable
          style={[s.commentRow, isReply && s.commentRowReply]}
          onLongPress={() => reportComment(comment)}
          delayLongPress={420}
        >
          {comment.user_profile_image ? (
            <Image source={{ uri: comment.user_profile_image }} style={[s.commentAvatar, isReply && s.commentAvatarSmall]} />
          ) : (
            <View style={[s.commentAvatarFallback, isReply && s.commentAvatarSmall]}>
              <Text style={s.commentAvatarText}>{commentInitial(comment)}</Text>
            </View>
          )}
          <View style={s.commentBodyColumn}>
            <View style={[s.commentBubble, isReply && s.commentBubbleReply]}>
              <Text style={s.commentName}>{commentName(comment)}</Text>
              <Text style={s.commentBody}>{comment.content}</Text>
            </View>
            <View style={s.commentActionsRow}>
              <TouchableOpacity style={s.commentActionPill} onPress={() => toggleCommentLike(comment)}>
                <Ionicons name={liked ? 'heart' : 'heart-outline'} size={14} color={liked ? '#16A34A' : '#555'} />
                <Text style={[s.commentActionText, liked && s.commentActionTextOn]}>
                  {Number(comment.likes_count || 0) > 0 ? formatCompactCount(comment.likes_count) : 'Like'}
                </Text>
              </TouchableOpacity>
              {!isReply ? (
                <TouchableOpacity style={s.commentActionPill} onPress={() => setReplyingTo(comment)}>
                  <Ionicons name="chatbubble-ellipses-outline" size={14} color="#555" />
                  <Text style={s.commentActionText}>Reply</Text>
                </TouchableOpacity>
              ) : null}
              <TouchableOpacity style={s.commentActionPill} onPress={() => reportComment(comment)}>
                <Ionicons name="flag-outline" size={14} color="#8A8A8A" />
                <Text style={s.commentActionText}>Report</Text>
              </TouchableOpacity>
            </View>
          </View>
        </Pressable>
        {!isReply && Array.isArray(comment.replies) && comment.replies.length > 0 ? (
          <View style={s.commentReplies}>
            {comment.replies.map((reply: any) => renderCommentItem(reply, true))}
          </View>
        ) : null}
      </View>
    );
  };

  const renderForYouCard = ({ item: p }: { item: any }) => {
    const mediaUri = getPrimaryVideoMediaUri(p);
    const postImages = parsePostImages(p.images);
    const editorOverlays = parseEditorOverlays(p.editor_overlays);
    const isVideo = isVideoMedia(mediaUri, p.media_types);
    const isLiked = likedPostIds.has(String(p.id));
    const isPaused = pausedPostIds.has(String(p.id));
    const isActive = filter === 'foryou' && String(p.id) === activeForYouPostId;
    const isFollowing = followedUserIds.has(String(p.user_id));
    const canFollow = !!p.user_id && p.user_id !== user?.id;
    const authorName = p.user_full_name || p.user_username || 'Flames';
    const authorSubtitle = p.category || p.post_type || p.place_name || 'For You';
    const sound = soundFromPost(p);
    const caption = postCaption(p);
    const cardLeft = (SW - forYouMediaWidth) / 2;
    const cardBottom = feedCardHeight - forYouMediaTop - forYouMediaHeight;
    const cardBounds = {
      top: forYouMediaTop,
      left: cardLeft,
      width: forYouMediaWidth,
      height: forYouMediaHeight,
      borderRadius: 28,
    };

    return (
      <View style={[s.feedCard, { height: feedCardHeight }]}>
        <View style={[s.feedMediaFrame, cardBounds]}>
          {mediaUri ? (
            <ForYouMedia active={isFocused && isActive} uri={mediaUri} mediaTypes={p.media_types} muted={!!sound} paused={isVideo && isPaused} />
          ) : (
            <View style={s.feedTextBackdrop}>
              <Text style={s.feedTextBackdropContent}>{postTitle(p)}</Text>
            </View>
          )}
          {editorOverlays.map((overlay, index) => {
            if (overlay.type === 'text') {
              const overlayWidth = forYouMediaWidth * (overlay.width || 0.72);
              const left = Math.max(8, Math.min(forYouMediaWidth - overlayWidth - 8, overlay.x * forYouMediaWidth - overlayWidth / 2));
              const top = Math.max(8, Math.min(forYouMediaHeight - 92, overlay.y * forYouMediaHeight - 30));
              return (
                <View
                  key={`editor-text-${index}`}
                  pointerEvents="none"
                  style={[
                    s.feedEditorTextOverlay,
                    { left, top, width: overlayWidth },
                  ]}
                >
                  <Text style={s.feedEditorTextOverlayText}>{overlay.text}</Text>
                </View>
              );
            }

            const overlayUri = overlay.uri || postImages[Math.max(0, Number(overlay.media_index || 0))];
            if (!overlayUri || overlayUri === mediaUri) return null;
            const overlayWidth = forYouMediaWidth * (overlay.width || 0.32);
            const overlayHeight = overlayWidth / 0.74;
            const left = Math.max(8, Math.min(forYouMediaWidth - overlayWidth - 8, overlay.x * forYouMediaWidth - overlayWidth / 2));
            const top = Math.max(8, Math.min(forYouMediaHeight - overlayHeight - 8, overlay.y * forYouMediaHeight - overlayHeight / 2));
            return (
              <View
                key={`editor-media-${index}`}
                pointerEvents="none"
                style={[
                  s.feedEditorMediaOverlay,
                  { left, top, width: overlayWidth },
                ]}
              >
                <MediaPreview uri={overlayUri} mediaTypes={p.media_types} style={s.feedMedia} resizeMode="cover" showVideoBadge={false} />
              </View>
            );
          })}
        </View>
        <View style={[s.feedScrim, cardBounds]} />
        {isVideo ? (
          <TouchableOpacity style={[s.feedTapTarget, cardBounds]} activeOpacity={1} onPress={() => togglePause(p)} />
        ) : null}
        {isVideo && isPaused ? (
          <View pointerEvents="none" style={[s.pausedIndicator, { left: cardLeft + forYouMediaWidth / 2 - 36, top: forYouMediaTop + forYouMediaHeight / 2 - 36 }]}>
            <Ionicons name="play" size={34} color="#FFFFFF" />
          </View>
        ) : null}

        <View style={[s.viewerTop, { top: forYouMediaTop + 10, left: cardLeft + 10, right: cardLeft + 10 }]}>
          <TouchableOpacity style={s.viewerAuthor} activeOpacity={0.86} onPress={() => router.push(`/user/${p.user_id}` as any)}>
            <View style={s.viewerAvatarWrap}>
              {p.user_profile_image ? (
                <Image source={{ uri: p.user_profile_image }} style={s.viewerAvatar} />
              ) : (
                <View style={s.viewerAvatarFallback}>
                  <Text style={s.viewerAvatarText}>{avatarInitial(p)}</Text>
                </View>
              )}
              {canFollow ? (
                <TouchableOpacity style={s.viewerFollowPlus} activeOpacity={0.9} onPress={() => followUser(p)}>
                  <Ionicons name={isFollowing ? 'checkmark' : 'add'} size={14} color="#111111" />
                </TouchableOpacity>
              ) : null}
            </View>
            <View style={s.viewerAuthorCopy}>
              <Text style={s.viewerAuthorName} numberOfLines={1}>{authorSubtitle || authorName}</Text>
              <Text style={s.viewerAuthorSub} numberOfLines={1}>@{p.user_username || authorName}</Text>
            </View>
          </TouchableOpacity>
        </View>

        <View style={[s.viewerActionRail, { top: forYouMediaTop + Math.round(forYouMediaHeight * 0.34), right: cardLeft + 10 }]}>
          <TouchableOpacity style={[s.viewerRailButton, isLiked && s.viewerRailButtonOn]} activeOpacity={0.86} onPress={() => toggleLike(p)}>
            <Ionicons name={isLiked ? 'flame' : 'flame-outline'} size={20} color={isLiked ? '#111111' : '#FFFFFF'} />
            <Text style={[s.viewerRailLabel, isLiked && s.viewerRailLabelOn]}>{formatCompactCount(p.likes_count || p.likes || 0)}</Text>
          </TouchableOpacity>
          <TouchableOpacity style={s.viewerRailButton} activeOpacity={0.86} onPress={() => openComments(p)}>
            <Ionicons name="chatbubble-outline" size={20} color="#FFFFFF" />
            <Text style={s.viewerRailLabel}>{formatCompactCount(p.comments_count || p.comment_count || 0)}</Text>
          </TouchableOpacity>
          <TouchableOpacity style={s.viewerRailButton} activeOpacity={0.86} onPress={() => openShareSheet(p)}>
            <Ionicons name="paper-plane-outline" size={20} color="#FFFFFF" />
            <Text style={s.viewerRailLabel}>Share</Text>
          </TouchableOpacity>
        </View>

        <View style={[s.viewerBottom, { left: cardLeft + 14, right: cardLeft + 14, bottom: cardBottom + 14 }]}>
          {caption ? (
            <TouchableOpacity style={s.viewerCaptionWrap} activeOpacity={0.86} onPress={() => openPostDetail(p)}>
              <Text style={s.viewerCaption} numberOfLines={3}>
                <Text style={s.viewerCaptionName}>{authorName} </Text>
                {caption}
              </Text>
            </TouchableOpacity>
          ) : null}
        </View>
      </View>
    );
  };

  const renderWorldTile = ({ item: p, index }: { item: any; index: number }) => {
    const mediaUri = getPrimaryMediaUri(p);

    return (
      <TouchableOpacity
        style={[
          s.worldTile,
          {
            width: WORLD_TILE_WIDTH,
            height: WORLD_TILE_HEIGHT,
            marginRight: (index + 1) % 3 === 0 ? 0 : WORLD_GAP,
            marginBottom: WORLD_GAP,
          },
        ]}
        activeOpacity={0.92}
        onPress={() => openPostDetail(p)}
      >
        {mediaUri ? (
          <MediaPreview
            uri={mediaUri}
            mediaTypes={p.media_types}
            style={s.worldMedia}
            resizeMode="cover"
            showVideoBadge={false}
          />
        ) : (
          <View style={s.worldTextTile}>
            <Text style={s.worldTextAuthor} numberOfLines={1}>@{p.user_username || 'flames'}</Text>
            <Text style={s.worldTextContent} numberOfLines={5}>{p.content}</Text>
          </View>
        )}
      </TouchableOpacity>
    );
  };

  const renderWorldSection = ({ item }: { item: [string, any[]] }) => {
    const [label, sectionPosts] = item;
    return (
      <View style={s.worldSection}>
        <View style={s.worldSectionHeader}>
          <Text style={s.worldSectionTitle}>{label}</Text>
          <View style={s.worldSectionLine} />
        </View>
        <View style={s.worldGallery}>
          {sectionPosts.map((post, index) => (
            <React.Fragment key={`${label}-${post.id}`}>
              {renderWorldTile({ item: post, index })}
            </React.Fragment>
          ))}
        </View>
      </View>
    );
  };

  const activeShareSound = shareTarget ? soundFromPost(shareTarget) : null;

  return (
    <View style={s.root}>
      {/* STICKY HEADER — stays fixed at top */}
      <View style={[s.stickyHeader, filter === 'foryou' && { display: 'none' }, { paddingTop: insets.top + 6 }]}>
        <View style={s.homeHeaderRow}>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} style={s.tabScroller} contentContainerStyle={s.filters}>
            {HOME_TABS.map(f => (
              <TouchableOpacity key={f.id} style={[s.chip, filter === 'foryou' && s.chipGlass, filter === f.id && s.chipOn]} onPress={() => setFilter(f.id)}>
                <Text style={[s.chipTx, filter === 'foryou' && s.chipTxGlass, filter === f.id && s.chipTxOn]}>{f.label}</Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
          <TouchableOpacity style={[s.hBtn, filter === 'foryou' && s.hBtnGlass]} onPress={openCreatePost}>
            <Ionicons name="add" size={20} color="#FFF" />
          </TouchableOpacity>
          <TouchableOpacity style={[s.hBtnLight, filter === 'foryou' && s.hBtnLightGlass]} onPress={() => { setUnreadNotifications(0); router.push('/notifications' as any); }}>
            <Ionicons name="notifications-outline" size={18} color={filter === 'foryou' ? '#FFF' : '#1A1A1A'} />
            {unreadNotifications > 0 ? (
              <View style={s.notificationBadge}>
                <Text style={s.notificationBadgeText}>{unreadNotifications > 9 ? '9+' : unreadNotifications}</Text>
              </View>
            ) : null}
          </TouchableOpacity>
        </View>
      </View>

      {filter === 'foryou' ? <ForYouDoodleBackground /> : null}

      {filter === 'foryou' ? (
        <TouchableOpacity
          style={[s.forYouExitButton, { top: insets.top + 8 }]}
          activeOpacity={0.88}
          onPress={() => setFilter('world')}
        >
          <Ionicons name="close" size={23} color="#111111" />
        </TouchableOpacity>
      ) : null}

      {filter === 'foryou' ? (
        <FlatList
          key="for-you-feed"
          data={items}
          keyExtractor={(p) => `foryou-${p.id}`}
          renderItem={renderForYouCard}
          style={s.forYouFeedList}
          showsVerticalScrollIndicator={false}
          snapToAlignment="start"
          snapToInterval={feedCardHeight}
          disableIntervalMomentum
          decelerationRate="fast"
          scrollEventThrottle={16}
          bounces={false}
          overScrollMode="never"
          getItemLayout={(_, index) => ({ length: feedCardHeight, offset: feedCardHeight * index, index })}
          initialNumToRender={3}
          maxToRenderPerBatch={3}
          updateCellsBatchingPeriod={16}
          windowSize={5}
          removeClippedSubviews={false}
          viewabilityConfig={forYouViewabilityConfig}
          onViewableItemsChanged={onForYouViewableItemsChanged}
          extraData={{
            activeForYouPostId,
            followedUserIds,
            likedPostIds,
            pausedPostIds,
          }}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
          contentContainerStyle={items.length === 0 ? s.emptyFeedContent : undefined}
          ListEmptyComponent={(
            <View style={s.empty}>
              <Ionicons name="sparkles-outline" size={40} color="#DDD" />
              <Text style={s.emptyTx}>No videos here yet</Text>
            </View>
          )}
        />
      ) : (
        <FlatList
          key="world-board-sections"
          data={worldBoardSections}
          keyExtractor={([label]) => `world-${label}`}
          renderItem={renderWorldSection}
          showsVerticalScrollIndicator={false}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
          contentContainerStyle={[
            s.worldGridContent,
            worldBoardSections.length === 0 && s.emptyFeedContent,
          ]}
          ListEmptyComponent={(
            <View style={s.empty}>
              <Ionicons name="images-outline" size={40} color="#DDD" />
              <Text style={s.emptyTx}>No posts here yet</Text>
            </View>
          )}
        />
      )}

      <Modal visible={!!shareTarget} transparent animationType="slide" onRequestClose={() => setShareTarget(null)}>
        <Pressable style={s.shareOverlay} onPress={() => setShareTarget(null)}>
          <Pressable style={[s.shareSheet, { paddingBottom: Math.max(22, insets.bottom + 14) }]} onPress={() => {}}>
            <View style={s.shareHandle} />
            <View style={s.shareHeader}>
              <View>
                <Text style={s.shareTitle}>Share post</Text>
                <Text style={s.shareSubtitle}>Send to friends or manage this post</Text>
              </View>
              <TouchableOpacity style={s.shareClose} onPress={() => setShareTarget(null)}>
                <Ionicons name="close" size={20} color="#111" />
              </TouchableOpacity>
            </View>

            <Text style={s.shareSectionTitle}>Send to</Text>
            {isShareLoading ? (
              <View style={s.shareLoading}>
                <ActivityIndicator color="#111" />
              </View>
            ) : (
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.friendRail}>
                {shareFriends.length === 0 ? (
                  <View style={s.noFriendsCard}>
                    <Text style={s.noFriendsText}>Start a conversation to see friends here.</Text>
                  </View>
                ) : shareFriends.map((friend) => (
                  <View key={friend.id} style={s.friendCard}>
                    <TouchableOpacity style={s.friendAvatarWrap} onPress={() => { setShareTarget(null); router.push(`/user/${friend.id}` as any); }}>
                      {friend.profile_image ? (
                        <Image source={{ uri: friend.profile_image }} style={s.friendAvatar} />
                      ) : (
                        <View style={s.friendAvatarFallback}>
                          <Text style={s.friendAvatarText}>{String(friend.full_name || friend.username || 'F').slice(0, 1).toUpperCase()}</Text>
                        </View>
                      )}
                    </TouchableOpacity>
                    <Text style={s.friendName} numberOfLines={1}>{friend.full_name || friend.username}</Text>
                    <TouchableOpacity style={s.sendFriendBtn} onPress={() => sendPostToFriend(friend)} disabled={sendingToId === String(friend.id)}>
                      {sendingToId === String(friend.id) ? (
                        <ActivityIndicator size="small" color="#111" />
                      ) : (
                        <Text style={s.sendFriendText}>Send</Text>
                      )}
                    </TouchableOpacity>
                  </View>
                ))}
              </ScrollView>
            )}

            {activeShareSound ? (
              <TouchableOpacity style={s.shareSoundCard} activeOpacity={0.9} onPress={() => shareTarget && openCreateWithSound(shareTarget)}>
                {activeShareSound.audio_artwork_url ? (
                  <Image source={{ uri: activeShareSound.audio_artwork_url }} style={s.shareSoundArtwork} />
                ) : (
                  <View style={s.shareSoundArtworkFallback}>
                    <Ionicons name="musical-notes" size={18} color="#111111" />
                  </View>
                )}
                <View style={s.shareSoundCopy}>
                  <Text style={s.shareSoundEyebrow}>Sound on this post</Text>
                  <Text style={s.shareSoundTitle} numberOfLines={1}>{activeShareSound.audio_title || 'Original sound'}</Text>
                  <Text style={s.shareSoundArtist} numberOfLines={1}>{activeShareSound.audio_artist || 'Flames Up'}</Text>
                </View>
                <View style={s.shareSoundUse}>
                  <Text style={s.shareSoundUseText}>Use this sound</Text>
                  <Ionicons name="arrow-forward" size={15} color="#111111" />
                </View>
              </TouchableOpacity>
            ) : null}

            <View style={s.shareActions}>
              <TouchableOpacity style={s.shareAction} onPress={() => shareTarget && copyPostLink(shareTarget)}>
                <Ionicons name="link-outline" size={22} color="#111" />
                <Text style={s.shareActionText}>Copy link</Text>
              </TouchableOpacity>
              <TouchableOpacity style={s.shareAction} onPress={() => shareTarget && sharePostSystem(shareTarget)}>
                <Ionicons name="share-social-outline" size={22} color="#111" />
                <Text style={s.shareActionText}>More</Text>
              </TouchableOpacity>
              <TouchableOpacity style={s.shareAction} onPress={() => shareTarget && markNotInterested(shareTarget)}>
                <Ionicons name="eye-off-outline" size={22} color="#111" />
                <Text style={s.shareActionText}>Not interested</Text>
              </TouchableOpacity>
              <TouchableOpacity style={s.shareAction} onPress={() => shareTarget && reportPost(shareTarget)}>
                <Ionicons name="flag-outline" size={22} color="#B42318" />
                <Text style={[s.shareActionText, s.reportText]}>Report</Text>
              </TouchableOpacity>
              {activeShareSound ? (
                <TouchableOpacity style={s.shareAction} onPress={() => shareTarget && reportSound(shareTarget)}>
                  <Ionicons name="volume-mute-outline" size={22} color="#B42318" />
                  <Text style={[s.shareActionText, s.reportText]}>Report sound</Text>
                </TouchableOpacity>
              ) : null}
            </View>
          </Pressable>
        </Pressable>
      </Modal>

      <Modal visible={!!commentTarget} transparent animationType="slide" onRequestClose={closeComments}>
        <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={s.commentOverlay}>
          <Pressable style={s.commentBackdrop} onPress={closeComments} />
          <View style={[s.commentSheet, { paddingBottom: Math.max(16, insets.bottom + 10) }]}>
            <View style={s.shareHandle} />
            <View style={s.commentHeader}>
              <View>
                <Text style={s.commentTitle}>Comments</Text>
                <Text style={s.commentSubtitle} numberOfLines={1}>{postTitle(commentTarget || {})}</Text>
              </View>
              <TouchableOpacity style={s.shareClose} onPress={closeComments}>
                <Ionicons name="close" size={20} color="#111" />
              </TouchableOpacity>
            </View>

            {commentsLoading ? (
              <View style={s.commentLoading}>
                <ActivityIndicator color="#111" />
              </View>
            ) : (
              <ScrollView style={s.commentList} contentContainerStyle={s.commentListContent} showsVerticalScrollIndicator={false}>
                {comments.length === 0 ? (
                  <View style={s.emptyComments}>
                    <Ionicons name="chatbubble-outline" size={28} color="#A0A0A0" />
                    <Text style={s.emptyCommentsText}>No comments yet</Text>
                  </View>
                ) : threadedComments.map((comment) => renderCommentItem(comment))}
              </ScrollView>
            )}

            {replyingTo ? (
              <View style={s.replyBanner}>
                <Text style={s.replyBannerText} numberOfLines={1}>Replying to {commentName(replyingTo)}</Text>
                <TouchableOpacity style={s.replyCancel} onPress={() => setReplyingTo(null)}>
                  <Ionicons name="close" size={16} color="#111" />
                </TouchableOpacity>
              </View>
            ) : null}

            <View style={s.commentComposer}>
              <TextInput
                value={commentText}
                onChangeText={setCommentText}
                placeholder={replyingTo ? `Reply to ${commentName(replyingTo)}...` : 'Add a comment...'}
                placeholderTextColor="#8E8E8E"
                style={s.commentInput}
              />
              <TouchableOpacity
                disabled={commentSending || !commentText.trim()}
                style={[s.commentSend, (!commentText.trim() || commentSending) && s.commentSendDisabled]}
                onPress={submitComment}
              >
                {commentSending ? (
                  <ActivityIndicator size="small" color="#111" />
                ) : (
                  <Ionicons name="arrow-up" size={18} color="#111" />
                )}
              </TouchableOpacity>
            </View>
          </View>
        </KeyboardAvoidingView>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#FFF' },

  // Sticky header
  stickyHeader: { backgroundColor: '#FFF', borderBottomWidth: 0.5, borderBottomColor: '#F0F0F0', zIndex: 10 },
  stickyHeaderForYou: { position: 'absolute', left: 0, right: 0, top: 0, backgroundColor: 'transparent', borderBottomWidth: 0, zIndex: 30 },
  homeHeaderRow: { minHeight: 42, flexDirection: 'row', alignItems: 'center', gap: 7, paddingHorizontal: 9, paddingBottom: 6 },
  tabScroller: { flex: 1 },
  hBtn: { width: 34, height: 34, borderRadius: 17, backgroundColor: '#1A1A1A', justifyContent: 'center', alignItems: 'center' },
  hBtnLight: { width: 34, height: 34, borderRadius: 17, backgroundColor: '#F0F0F0', justifyContent: 'center', alignItems: 'center' },
  notificationBadge: {
    position: 'absolute', right: -2, top: -3, minWidth: 17, height: 17, borderRadius: 9,
    backgroundColor: '#DFFF32', borderWidth: 1.4, borderColor: '#111111', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 3,
  },
  notificationBadgeText: { color: '#111111', fontSize: 9, fontWeight: '900', fontVariant: ['tabular-nums'] },
  hBtnGlass: { backgroundColor: 'rgba(0,0,0,0.42)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.24)' },
  hBtnLightGlass: { backgroundColor: 'rgba(0,0,0,0.32)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.24)' },
  forYouPatternLayer: {
    ...StyleSheet.absoluteFillObject,
    zIndex: 0,
    backgroundColor: '#FFFFFF',
    overflow: 'hidden',
  },
  forYouDoodle: {
    position: 'absolute',
  },
  forYouDoodleText: {
    fontWeight: '900',
    letterSpacing: 0,
    textTransform: 'uppercase',
  },
  forYouPatternSoftener: { ...StyleSheet.absoluteFillObject, backgroundColor: '#FFFFFF' },
  forYouExitButton: {
    position: 'absolute', right: 14, zIndex: 60, width: 44, height: 44, borderRadius: 22,
    backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#ECECEC',
    alignItems: 'center', justifyContent: 'center',
    shadowColor: '#000000', shadowOpacity: 0.16, shadowRadius: 12, shadowOffset: { width: 0, height: 4 }, elevation: 4,
  },

  filters: { gap: 6, alignItems: 'center' },
  chip: { minHeight: 34, paddingHorizontal: 14, paddingVertical: 7, borderRadius: 17, backgroundColor: '#F5F5F5', justifyContent: 'center' },
  chipGlass: { backgroundColor: 'rgba(0,0,0,0.32)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.18)' },
  chipOn: { backgroundColor: '#1A1A1A' },
  chipTx: { fontSize: 13, fontWeight: '600', color: '#999' },
  chipTxGlass: { color: 'rgba(255,255,255,0.78)' },
  chipTxOn: { color: '#FFF' },

  // World Board grid
  worldGridContent: { paddingBottom: 100, backgroundColor: '#FFFFFF' },
  worldSection: { marginBottom: 18 },
  worldSectionHeader: { minHeight: 42, flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 12, backgroundColor: '#FFFFFF' },
  worldSectionTitle: { color: '#111111', fontSize: 18, lineHeight: 22, fontWeight: '900' },
  worldSectionLine: { flex: 1, height: StyleSheet.hairlineWidth, backgroundColor: '#D9D9D9' },
  worldGallery: { flexDirection: 'row', flexWrap: 'wrap', backgroundColor: '#FFFFFF' },
  worldTile: { overflow: 'hidden', backgroundColor: '#ECECEC', position: 'relative', borderRadius: 0 },
  worldMedia: { width: '100%', height: '100%' },
  worldTextTile: { flex: 1, backgroundColor: '#F7F4EE', padding: 10, justifyContent: 'space-between' },
  worldTextAuthor: { fontSize: 11, fontWeight: '800', color: '#6F6A60' },
  worldTextContent: { fontSize: 15, lineHeight: 19, fontWeight: '800', color: '#1A1A1A' },

  forYouFeedList: { flex: 1, backgroundColor: 'transparent', zIndex: 1 },
  feedCard: { width: SW, backgroundColor: 'transparent', overflow: 'hidden', position: 'relative' },
  feedMediaFrame: {
    position: 'absolute', borderRadius: 28,
    overflow: 'hidden', backgroundColor: '#F5F5F5', borderWidth: 1, borderColor: '#ECECEC',
  },
  feedMedia: { ...StyleSheet.absoluteFillObject, width: '100%', height: '100%' },
  feedLoadingCover: { ...StyleSheet.absoluteFillObject, backgroundColor: '#111111' },
  feedLoadingScrim: { ...StyleSheet.absoluteFillObject, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(0,0,0,0.16)' },
  feedTextBackdrop: { ...StyleSheet.absoluteFillObject, backgroundColor: '#F4F5F1', justifyContent: 'center', padding: 30 },
  feedTextBackdropContent: { color: '#111', fontSize: 38, lineHeight: 42, fontWeight: '900' },
  feedEditorTextOverlay: { position: 'absolute', zIndex: 6, alignItems: 'center' },
  feedEditorTextOverlayText: {
    color: '#FFFFFF', fontSize: 24, lineHeight: 30, fontWeight: '900', textAlign: 'center',
    textShadowColor: 'rgba(0,0,0,0.62)', textShadowRadius: 10, textShadowOffset: { width: 0, height: 2 },
  },
  feedEditorMediaOverlay: {
    position: 'absolute', zIndex: 6, aspectRatio: 0.74, borderRadius: 18, overflow: 'hidden',
    borderWidth: 1.2, borderColor: 'rgba(255,255,255,0.58)', backgroundColor: '#111111',
  },
  feedScrim: { position: 'absolute', backgroundColor: 'rgba(0,0,0,0.08)' },
  feedTapTarget: { position: 'absolute', zIndex: 5 },
  pausedIndicator: { position: 'absolute', zIndex: 18, width: 72, height: 72, borderRadius: 36, backgroundColor: 'rgba(0,0,0,0.42)', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: 'rgba(255,255,255,0.2)' },
  viewerTop: { position: 'absolute', zIndex: 20, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  viewerAuthor: { flex: 1, minWidth: 0, flexDirection: 'row', alignItems: 'center', gap: 10 },
  viewerAvatarWrap: { width: 62, height: 62, position: 'relative', marginLeft: -4, marginTop: -18 },
  viewerAvatar: { width: 58, height: 58, borderRadius: 29, borderWidth: 2, borderColor: '#FFFFFF' },
  viewerAvatarFallback: { width: 58, height: 58, borderRadius: 29, alignItems: 'center', justifyContent: 'center', backgroundColor: '#FFFFFF', borderWidth: 2, borderColor: '#FFFFFF' },
  viewerAvatarText: { color: '#111111', fontSize: 21, fontWeight: '900' },
  viewerFollowPlus: { position: 'absolute', right: 0, bottom: 2, width: 21, height: 21, borderRadius: 11, backgroundColor: '#DFFF32', borderWidth: 1.5, borderColor: '#111111', alignItems: 'center', justifyContent: 'center' },
  viewerAuthorCopy: { flex: 1, minWidth: 0 },
  viewerAuthorName: { color: '#FFFFFF', fontSize: 13, lineHeight: 17, fontWeight: '900', textShadowColor: 'rgba(0,0,0,0.55)', textShadowRadius: 8, textShadowOffset: { width: 0, height: 1 } },
  viewerAuthorSub: { color: 'rgba(255,255,255,0.72)', fontSize: 11, lineHeight: 14, fontWeight: '700', textShadowColor: 'rgba(0,0,0,0.5)', textShadowRadius: 8, textShadowOffset: { width: 0, height: 1 } },
  viewerChevron: { width: 42, height: 42, borderRadius: 21, alignItems: 'center', justifyContent: 'center' },
  viewerSideIndicator: { position: 'absolute', right: 18, top: '32%', width: 3, height: 118, borderRadius: 3, backgroundColor: 'rgba(255,255,255,0.24)' },
  viewerActionRail: {
    position: 'absolute', zIndex: 22, width: 54, gap: 9, alignItems: 'center',
  },
  viewerRailButton: {
    width: 52, minHeight: 52, borderRadius: 26, alignItems: 'center', justifyContent: 'center',
    backgroundColor: 'rgba(52,52,52,0.58)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.24)',
    shadowColor: '#000000', shadowOpacity: 0.22, shadowRadius: 10, shadowOffset: { width: 0, height: 4 }, elevation: 3,
  },
  viewerRailButtonOn: { backgroundColor: '#DFFF32', borderColor: '#111111' },
  viewerRailLabel: { marginTop: 2, color: '#FFFFFF', fontSize: 9, lineHeight: 11, fontWeight: '900' },
  viewerRailLabelOn: { color: '#111111' },
  viewerBottom: { position: 'absolute', zIndex: 20, alignItems: 'stretch' },
  viewerCaptionWrap: {
    alignSelf: 'flex-start', maxWidth: '78%', marginBottom: 9, borderRadius: 12,
    backgroundColor: 'rgba(0,0,0,0.22)', paddingHorizontal: 10, paddingVertical: 7,
  },
  viewerCaption: {
    color: '#FFFFFF', fontSize: 11, lineHeight: 15, fontWeight: '700',
    textShadowColor: 'rgba(0,0,0,0.52)', textShadowRadius: 8, textShadowOffset: { width: 0, height: 1 },
  },
  viewerCaptionName: { fontWeight: '900' },
  viewerControls: { minHeight: 54, flexDirection: 'row', alignItems: 'center', justifyContent: 'flex-end' },
  viewerActionCluster: { flexDirection: 'row', alignItems: 'center', gap: 8, maxWidth: '100%' },
  viewerMetricButton: { minWidth: 58, height: 42, borderRadius: 21, backgroundColor: 'rgba(48,48,48,0.68)', flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 5, paddingHorizontal: 10 },
  viewerMetricButtonOn: { backgroundColor: 'rgba(255,49,88,0.78)' },
  viewerMetricText: { color: '#FFFFFF', fontSize: 13, fontWeight: '900', fontVariant: ['tabular-nums'] },
  viewerSaveButton: { width: 42, height: 42, borderRadius: 21, backgroundColor: '#DFFF32', borderWidth: 1.5, borderColor: '#111111', alignItems: 'center', justifyContent: 'center' },
  viewerSaveButtonOn: { backgroundColor: '#DFFF32', borderColor: '#111111', transform: [{ scale: 1.06 }] },
  feedTop: { position: 'absolute', left: 16, right: 16, zIndex: 12, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  feedAuthor: { flex: 1, minWidth: 0, flexDirection: 'row', alignItems: 'center', gap: 10 },
  feedAuthorImage: { width: 42, height: 42, borderRadius: 21, borderWidth: 1.4, borderColor: 'rgba(255,255,255,0.72)' },
  feedAuthorFallback: { width: 42, height: 42, borderRadius: 21, backgroundColor: '#F5F2EA', alignItems: 'center', justifyContent: 'center', borderWidth: 1.4, borderColor: 'rgba(255,255,255,0.72)' },
  feedAuthorInitial: { color: '#111', fontSize: 18, fontWeight: '900' },
  feedAuthorCopy: { flex: 1, minWidth: 0 },
  feedAuthorName: { color: '#FFF', fontSize: 15, lineHeight: 18, fontWeight: '900' },
  feedAuthorSub: { color: 'rgba(255,255,255,0.78)', fontSize: 12, lineHeight: 15, fontWeight: '700', marginTop: 1 },
  feedFollowPill: { minHeight: 34, borderRadius: 17, backgroundColor: '#DFFF32', borderWidth: 1.6, borderColor: '#111', paddingHorizontal: 12, flexDirection: 'row', alignItems: 'center', gap: 4 },
  feedFollowText: { color: '#111', fontSize: 12, fontWeight: '900' },
  feedRail: { position: 'absolute', right: 13, bottom: 118, gap: 16, alignItems: 'center' },
  creatorButton: { width: 60, height: 60, borderRadius: 30, backgroundColor: 'rgba(255,255,255,0.18)', alignItems: 'center', justifyContent: 'center', borderWidth: 1.5, borderColor: 'rgba(255,255,255,0.82)' },
  creatorImage: { width: 52, height: 52, borderRadius: 26 },
  creatorFallback: { width: 52, height: 52, borderRadius: 26, backgroundColor: '#F5F2EA', alignItems: 'center', justifyContent: 'center' },
  creatorFallbackText: { color: '#111', fontSize: 25, fontWeight: '900' },
  followPlus: { position: 'absolute', bottom: -7, right: -4, width: 26, height: 26, borderRadius: 13, backgroundColor: '#DFFF32', borderWidth: 2, borderColor: '#111', alignItems: 'center', justifyContent: 'center' },
  railAction: { width: 62, alignItems: 'center' },
  roundAction: { width: 52, height: 52, borderRadius: 26, backgroundColor: 'rgba(0,0,0,0.34)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.22)', alignItems: 'center', justifyContent: 'center' },
  roundActionOn: { backgroundColor: 'rgba(255,255,255,0.92)' },
  actionCount: { marginTop: 5, color: '#FFF', fontSize: 11, lineHeight: 13, fontWeight: '900', backgroundColor: 'rgba(0,0,0,0.34)', borderRadius: 9, overflow: 'hidden', paddingHorizontal: 7, paddingVertical: 2 },
  feedBottom: { position: 'absolute', left: 16, right: 88, gap: 10 },
  feedMeta: { minHeight: 42, justifyContent: 'flex-end' },
  feedHandle: { color: '#FFF', fontSize: 16, lineHeight: 20, fontWeight: '900' },
  feedCaption: { marginTop: 2, color: 'rgba(255,255,255,0.92)', fontSize: 14, lineHeight: 18, fontWeight: '700' },
  feedCta: { alignSelf: 'flex-start', minHeight: 45, paddingHorizontal: 22, borderRadius: 23, borderWidth: 1.8, borderColor: '#101010', backgroundColor: '#DFFF32', justifyContent: 'center' },
  feedCtaText: { color: '#111', fontSize: 17, fontWeight: '900' },
  emptyFeedContent: { flexGrow: 1, paddingBottom: 100 },
  empty: { paddingTop: 100, alignItems: 'center' },
  emptyTx: { fontSize: 14, color: '#CCC', marginTop: 10 },
  shareOverlay: { flex: 1, justifyContent: 'flex-end', backgroundColor: 'rgba(0,0,0,0.36)' },
  shareSheet: { backgroundColor: '#FFF', borderTopLeftRadius: 24, borderTopRightRadius: 24, paddingTop: 10, paddingHorizontal: 16, gap: 14 },
  shareHandle: { alignSelf: 'center', width: 42, height: 5, borderRadius: 3, backgroundColor: '#D7D7D7' },
  shareHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  shareTitle: { color: '#111', fontSize: 22, fontWeight: '900' },
  shareSubtitle: { color: '#6A6A6A', fontSize: 13, fontWeight: '600', marginTop: 2 },
  shareClose: { width: 36, height: 36, borderRadius: 18, backgroundColor: '#F3F3F3', alignItems: 'center', justifyContent: 'center' },
  shareSectionTitle: { color: '#111', fontSize: 15, fontWeight: '900' },
  shareLoading: { height: 116, alignItems: 'center', justifyContent: 'center' },
  friendRail: { gap: 10, paddingRight: 8 },
  noFriendsCard: { width: 220, minHeight: 104, borderRadius: 16, backgroundColor: '#F6F6F4', alignItems: 'center', justifyContent: 'center', padding: 14 },
  noFriendsText: { color: '#646464', textAlign: 'center', fontSize: 13, fontWeight: '700' },
  friendCard: { width: 88, minHeight: 126, borderRadius: 18, backgroundColor: '#F7F7F5', alignItems: 'center', padding: 8, gap: 6 },
  friendAvatarWrap: { width: 54, height: 54, borderRadius: 27 },
  friendAvatar: { width: 54, height: 54, borderRadius: 27 },
  friendAvatarFallback: { width: 54, height: 54, borderRadius: 27, backgroundColor: '#DFFF32', alignItems: 'center', justifyContent: 'center', borderWidth: 1.5, borderColor: '#111' },
  friendAvatarText: { color: '#111', fontSize: 21, fontWeight: '900' },
  friendName: { width: '100%', color: '#111', fontSize: 12, fontWeight: '800', textAlign: 'center' },
  sendFriendBtn: { minWidth: 62, height: 28, borderRadius: 14, backgroundColor: '#DFFF32', borderWidth: 1.5, borderColor: '#111', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 10 },
  sendFriendText: { color: '#111', fontSize: 12, fontWeight: '900' },
  shareSoundCard: {
    minHeight: 74, borderRadius: 18, backgroundColor: '#F7F7F3', borderWidth: 1.2, borderColor: '#E6E6DE',
    flexDirection: 'row', alignItems: 'center', gap: 10, padding: 10,
  },
  shareSoundArtwork: { width: 52, height: 52, borderRadius: 13, backgroundColor: '#EAEAEA' },
  shareSoundArtworkFallback: { width: 52, height: 52, borderRadius: 13, backgroundColor: '#DFFF32', borderWidth: 1.3, borderColor: '#111111', alignItems: 'center', justifyContent: 'center' },
  shareSoundCopy: { flex: 1, minWidth: 0 },
  shareSoundEyebrow: { color: '#7B7B72', fontSize: 10, lineHeight: 12, fontWeight: '900', textTransform: 'uppercase' },
  shareSoundTitle: { color: '#111111', fontSize: 14, lineHeight: 18, fontWeight: '900', marginTop: 2 },
  shareSoundArtist: { color: '#666666', fontSize: 12, lineHeight: 15, fontWeight: '700' },
  shareSoundUse: { minHeight: 34, borderRadius: 17, backgroundColor: '#DFFF32', borderWidth: 1.4, borderColor: '#111111', paddingHorizontal: 10, flexDirection: 'row', alignItems: 'center', gap: 4 },
  shareSoundUseText: { color: '#111111', fontSize: 12, fontWeight: '900' },
  shareActions: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  shareAction: { width: '48%', minHeight: 48, borderRadius: 15, backgroundColor: '#F4F4F2', flexDirection: 'row', alignItems: 'center', gap: 9, paddingHorizontal: 12 },
  shareActionText: { color: '#111', fontSize: 13, fontWeight: '900' },
  reportText: { color: '#B42318' },
  commentOverlay: { flex: 1, justifyContent: 'flex-end' },
  commentBackdrop: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.38)' },
  commentSheet: { maxHeight: '78%', minHeight: 410, backgroundColor: '#FFFFFF', borderTopLeftRadius: 24, borderTopRightRadius: 24, paddingTop: 10, paddingHorizontal: 16, gap: 12 },
  commentHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  commentTitle: { color: '#111', fontSize: 22, fontWeight: '900' },
  commentSubtitle: { color: '#6A6A6A', fontSize: 13, fontWeight: '700', marginTop: 2, maxWidth: SW - 90 },
  commentLoading: { minHeight: 190, alignItems: 'center', justifyContent: 'center' },
  commentList: { flex: 1 },
  commentListContent: { gap: 12, paddingVertical: 4, paddingBottom: 10 },
  emptyComments: { minHeight: 190, alignItems: 'center', justifyContent: 'center', gap: 8 },
  emptyCommentsText: { color: '#8A8A8A', fontSize: 14, fontWeight: '800' },
  commentThread: { gap: 8 },
  commentThreadReply: { marginTop: 0 },
  commentRow: { flexDirection: 'row', alignItems: 'flex-start', gap: 10 },
  commentRowReply: { paddingLeft: 0 },
  commentAvatar: { width: 38, height: 38, borderRadius: 19, backgroundColor: '#EEE' },
  commentAvatarSmall: { width: 30, height: 30, borderRadius: 15 },
  commentAvatarFallback: { width: 38, height: 38, borderRadius: 19, alignItems: 'center', justifyContent: 'center', backgroundColor: '#DFFF32', borderWidth: 1, borderColor: '#111' },
  commentAvatarText: { color: '#111', fontSize: 15, fontWeight: '900' },
  commentBodyColumn: { flex: 1, minWidth: 0, gap: 5 },
  commentBubble: { flex: 1, minWidth: 0, borderRadius: 16, backgroundColor: '#F5F5F3', paddingHorizontal: 12, paddingVertical: 10 },
  commentBubbleReply: { backgroundColor: '#FAFAF8', borderWidth: 1, borderColor: '#ECE8DF' },
  commentName: { color: '#111', fontSize: 13, fontWeight: '900', marginBottom: 3 },
  commentBody: { color: '#222', fontSize: 14, lineHeight: 19, fontWeight: '600' },
  commentActionsRow: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 10, paddingLeft: 4 },
  commentActionPill: { minHeight: 25, flexDirection: 'row', alignItems: 'center', gap: 4 },
  commentActionText: { color: '#666', fontSize: 12, fontWeight: '900' },
  commentActionTextOn: { color: '#16A34A' },
  commentReplies: { marginLeft: 48, paddingLeft: 12, borderLeftWidth: 2, borderLeftColor: '#ECE8DF', gap: 9 },
  replyBanner: { minHeight: 38, borderRadius: 14, backgroundColor: '#F1FFD0', borderWidth: 1, borderColor: '#D7EF75', flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 10, paddingLeft: 13, paddingRight: 8 },
  replyBannerText: { flex: 1, color: '#111', fontSize: 13, fontWeight: '900' },
  replyCancel: { width: 26, height: 26, borderRadius: 13, alignItems: 'center', justifyContent: 'center', backgroundColor: '#FFFFFF' },
  commentComposer: { minHeight: 50, flexDirection: 'row', alignItems: 'center', gap: 8, borderRadius: 25, backgroundColor: '#F3F3F1', paddingLeft: 16, paddingRight: 5 },
  commentInput: { flex: 1, minHeight: 48, color: '#111', fontSize: 15, fontWeight: '700', paddingVertical: 0 },
  commentSend: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#DFFF32', borderWidth: 1.5, borderColor: '#111', alignItems: 'center', justifyContent: 'center' },
  commentSendDisabled: { opacity: 0.45 },
});
