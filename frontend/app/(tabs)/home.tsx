import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, FlatList,
  Animated, Dimensions, ScrollView, Image, Alert, Share,
  Modal, Pressable, ActivityIndicator, Platform, TextInput, KeyboardAvoidingView,
  InteractionManager,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useFocusEffect, useNavigation, useRouter } from 'expo-router';
import { useIsFocused } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { StatusBar } from 'expo-status-bar';
import * as NavigationBar from 'expo-navigation-bar';
import { Audio, ResizeMode, Video } from 'expo-av';
import { useAuthStore } from '../../src/store/authStore';
import { useNotificationStore } from '../../src/store/notificationStore';
import { cacheHomePosts, getCachedHomePosts } from '../../src/store/feedCache';
import { cachePostForDetail, cachePostsForDetail } from '../../src/store/postDetailCache';
import { derivePostInteractionState, useSocialState } from '../../src/store/socialState';
import api, { API_URL } from '../../src/api/client';
import { rankFeed, RecommendationItem } from '../../src/recommendation';
import { requireVerifiedPhone } from '../../src/utils/phoneVerification';
import MediaPreview from '../../src/components/MediaPreview';
import SaveToCollectionModal from '../../src/components/SaveToCollectionModal';
import { borderRadius, colors, shadows, spacing } from '../../src/utils/theme';
import { extractStreamUid, getStreamPlaybackInfo, isCFStreamVideo } from '../../src/utils/mediaUpload';
import { getAudiusTrackStream, soundFromPost } from '../../src/utils/music';
import { prefetchPostMedia } from '../../src/utils/optimizedMedia';
import { removePostFromLibrary, savePostToCollection } from '../../src/utils/librarySave';
import { scoreFeedItem } from '../../modules/mira-performance';

const { width: SW, height: SH } = Dimensions.get('window');

const HOME_TABS = [
  { id: 'world', label: 'World Board' },
  { id: 'main', label: 'Main' },
] as const;

const MAIN_SURFACE = '#FFFFFF';
const MAIN_SUBTLE = '#FAFAF8';
const MAIN_BORDER = 'rgba(18,24,16,0.055)';
const MAIN_MUTED = '#8A9187';
const MAIN_GREEN = '#20361F';
const HOME_FEED_LIMIT = 36;

type HomeTabId = 'world' | 'foryou' | 'main';

const WORLD_BOARD_SECTIONS = [
  { label: 'Trending', kind: 'trending' },
  { label: 'Fresh', kind: 'fresh' },
  { label: 'Latest', kind: 'latest' },
  { label: 'Explore More', kind: 'explore' },
] as const;

function engagementScore(post: any): number {
  const createdAt = Date.parse(post?.created_at || '');
  const ageHours = Number.isFinite(createdAt)
    ? Math.max(0, (Date.now() - createdAt) / 3600000)
    : 999;
  return scoreFeedItem(
    Number(post?.likes_count || 0),
    Number(post?.comments_count || 0),
    Number(post?.saves_count || 0),
    Number(post?.shares_count || 0),
    Number(post?.views_count || 0),
    ageHours,
    !!(post?.is_following || post?.following || post?.followed),
    hasAnyVideoMedia(post),
  );
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

function getPostMediaItems(post: any): { uri: string; index: number; mediaType?: string }[] {
  const mediaTypes = normalizeMediaTypes(post?.media_types);
  const rawItems = [
    typeof post?.image === 'string' ? post.image : '',
    ...parsePostImages(post?.images),
  ].filter((uri) => (
    uri
    && (uri.startsWith('http') || uri.startsWith('data:') || uri.startsWith('cfstream:'))
  ));

  const seen = new Set<string>();
  const items: { uri: string; index: number; mediaType?: string }[] = [];
  rawItems.forEach((uri, rawIndex) => {
    if (seen.has(uri)) return;
    seen.add(uri);
    items.push({ uri, index: rawIndex, mediaType: mediaTypes[rawIndex] });
  });
  return items;
}

function hasAnyVideoMedia(post: any): boolean {
  return getPostMediaItems(post).some((item) => isVideoMediaAt(item.uri, post?.media_types, item.index));
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

function parseMediaDimensions(value: unknown): any[] {
  if (Array.isArray(value)) return value;
  if (typeof value === 'string' && value.trim()) {
    try {
      const parsed = JSON.parse(value);
      return Array.isArray(parsed) ? parsed : [];
    } catch {}
  }
  return [];
}

function ratioFromFormat(value: unknown): number {
  const text = String(value || '').toLowerCase();
  if (text.includes('4:5')) return 4 / 5;
  if (text.includes('3:4')) return 3 / 4;
  if (text.includes('9:16')) return 9 / 16;
  if (text.includes('1:1')) return 1;
  return 0;
}

function clampMediaRatio(value: number): number {
  if (!Number.isFinite(value) || value <= 0) return 3 / 4;
  return Math.max(9 / 16, Math.min(1, value));
}

function mainPostAspectRatio(post: any, mediaUri: string): number {
  const mediaList = [
    typeof post?.image === 'string' ? post.image : '',
    ...parsePostImages(post?.images),
  ].filter(Boolean);
  const mediaIndex = Math.max(0, mediaList.findIndex((uri) => uri === mediaUri));
  const dimensions = parseMediaDimensions(post?.media_dimensions);
  const mediaDimension = dimensions[mediaIndex] || dimensions[0] || null;
  if (mediaDimension) {
    const width = Number(mediaDimension.width || 0);
    const height = Number(mediaDimension.height || 0);
    const ratio = Number(mediaDimension.ratio || 0) || (width > 0 && height > 0 ? width / height : 0);
    if (ratio > 0) return clampMediaRatio(ratio);
    const formatRatio = ratioFromFormat(mediaDimension.format);
    if (formatRatio > 0) return formatRatio;
  }

  const explicitWidth = Number(post?.media_width || post?.image_width || post?.width || 0);
  const explicitHeight = Number(post?.media_height || post?.image_height || post?.height || 0);
  if (explicitWidth > 0 && explicitHeight > 0) {
    const ratio = explicitWidth / explicitHeight;
    if (ratio > 0.5 && ratio < 1.25) return clampMediaRatio(ratio);
  }

  const rawRatio = Number(post?.aspect_ratio || post?.media_aspect_ratio || 0);
  if (rawRatio > 0.5 && rawRatio < 1.25) return clampMediaRatio(rawRatio);

  const formatRatio = ratioFromFormat(`${post?.format || ''} ${post?.media_aspect || ''} ${post?.orientation || ''}`);
  if (formatRatio > 0) return formatRatio;

  return 3 / 4;
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
            <MediaPreview uri={uri} mediaTypes={mediaTypes} style={s.feedMedia} resizeMode="cover" showVideoBadge={false} imagePreset="feed" priority={active ? 'high' : 'normal'} />
            <View style={s.feedLoadingScrim}>
              <ActivityIndicator color="#FFFFFF" />
            </View>
          </View>
        ) : null}
      </View>
    );
  }

  return <MediaPreview uri={uri} mediaTypes={mediaTypes} style={s.feedMedia} resizeMode="cover" showVideoBadge={false} imagePreset="feed" priority={active ? 'high' : 'normal'} />;
}

function MainFeedMedia({ active, mediaTypes, uri }: { active: boolean; mediaTypes?: string[] | string | null; uri: string }) {
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
    if (!active) {
      videoRef.current.pauseAsync?.().catch?.(() => undefined);
      videoRef.current.setIsMutedAsync?.(true).catch?.(() => undefined);
      return;
    }
    videoRef.current.setIsMutedAsync?.(false).catch?.(() => undefined);
    videoRef.current.playAsync?.().catch?.(() => undefined);
  }, [active, playbackUri, video]);

  useEffect(() => () => {
    videoRef.current?.pauseAsync?.().catch?.(() => undefined);
  }, []);

  if (video && playbackUri) {
    return (
      <View style={s.mainMedia}>
        <Video
          ref={videoRef}
          source={{ uri: playbackUri }}
          style={s.mainMedia}
          resizeMode={ResizeMode.COVER}
          shouldPlay={active}
          isLooping
          isMuted={!active}
          volume={active ? 1 : 0}
          progressUpdateIntervalMillis={250}
          onLoadStart={() => setReady(false)}
          onLoad={() => setReady(true)}
          onReadyForDisplay={() => setReady(true)}
        />
        {!ready ? (
          <View pointerEvents="none" style={s.mainLoadingCover}>
            <MediaPreview uri={uri} mediaTypes={mediaTypes} style={s.mainMedia} resizeMode="cover" showVideoBadge={false} imagePreset="feed" priority={active ? 'high' : 'normal'} />
            <View style={s.feedLoadingScrim}>
              <ActivityIndicator color="#FFFFFF" />
            </View>
          </View>
        ) : null}
      </View>
    );
  }

  return <MediaPreview uri={uri} mediaTypes={mediaTypes} style={s.mainMedia} resizeMode="cover" showVideoBadge={false} imagePreset="feed" priority={active ? 'high' : 'normal'} />;
}

function MainPostMediaCarousel({
  active,
  mediaItems,
  onOpen,
  post,
}: {
  active: boolean;
  mediaItems: { uri: string; index: number; mediaType?: string }[];
  onOpen: () => void;
  post: any;
}) {
  const [activeIndex, setActiveIndex] = useState(0);
  const activeItem = mediaItems[Math.min(activeIndex, Math.max(0, mediaItems.length - 1))] || mediaItems[0];
  const mediaAspectRatio = mainPostAspectRatio(post, activeItem?.uri || '');
  const pageWidth = Math.max(1, SW);

  const handleCarouselScrollEnd = useCallback((event: any) => {
    const x = Number(event?.nativeEvent?.contentOffset?.x || 0);
    const nextIndex = Math.round(x / pageWidth);
    setActiveIndex(Math.max(0, Math.min(mediaItems.length - 1, nextIndex)));
  }, [mediaItems.length, pageWidth]);

  if (!mediaItems.length) {
    return (
      <TouchableOpacity
        style={[s.mainMediaFrame, { aspectRatio: 3 / 4 }]}
        activeOpacity={0.94}
        onPress={onOpen}
      >
        <View style={s.mainTextOnly}>
          <Text style={s.mainTextOnlyTitle} numberOfLines={6}>{postTitle(post)}</Text>
        </View>
      </TouchableOpacity>
    );
  }

  return (
    <View style={[s.mainMediaFrame, { aspectRatio: mediaAspectRatio }]}>
      <ScrollView
        horizontal
        pagingEnabled
        nestedScrollEnabled
        bounces={false}
        showsHorizontalScrollIndicator={false}
        onMomentumScrollEnd={handleCarouselScrollEnd}
        scrollEventThrottle={16}
      >
        {mediaItems.map((item, index) => {
          const itemIsVideo = isVideoMediaAt(item.uri, post?.media_types, item.index);
          return (
            <TouchableOpacity
              key={`${item.uri}-${item.index}`}
              style={[s.mainCarouselPage, { width: pageWidth }]}
              activeOpacity={0.94}
              onPress={onOpen}
            >
              <MainFeedMedia
                active={active && activeIndex === index}
                uri={item.uri}
                mediaTypes={item.mediaType ? [item.mediaType] : undefined}
              />
              {itemIsVideo && !(active && activeIndex === index) ? (
                <View pointerEvents="none" style={s.mainVideoBadge}>
                  <Ionicons name="play" size={19} color="#FFFFFF" />
                </View>
              ) : null}
            </TouchableOpacity>
          );
        })}
      </ScrollView>
      {mediaItems.length > 1 ? (
        <View pointerEvents="none" style={s.mainCarouselDots}>
          {mediaItems.map((item, index) => (
            <View
              key={`main-dot-${item.index}-${index}`}
              style={[s.mainCarouselDot, index === activeIndex && s.mainCarouselDotOn]}
            />
          ))}
        </View>
      ) : null}
    </View>
  );
}

function ForYouDoodleBackground() {
  return <View pointerEvents="none" style={s.forYouPatternLayer} />;
}

async function setAndroidNavigationBarImmersive(enabled: boolean) {
  if (Platform.OS !== 'android') return;
  try {
    if (enabled) {
      await NavigationBar.setPositionAsync('absolute').catch(() => undefined);
      await NavigationBar.setBackgroundColorAsync('#00000000').catch(() => undefined);
      await NavigationBar.setBehaviorAsync('overlay-swipe').catch(() => undefined);
      await NavigationBar.setVisibilityAsync('hidden');
    } else {
      await NavigationBar.setVisibilityAsync('visible');
      await NavigationBar.setBehaviorAsync('inset-swipe').catch(() => undefined);
      await NavigationBar.setPositionAsync('relative').catch(() => undefined);
      await NavigationBar.setBackgroundColorAsync(colors.bgNav).catch(() => undefined);
      await NavigationBar.setButtonStyleAsync('dark').catch(() => undefined);
    }
  } catch {
    // Some Android builds expose limited system UI controls; keep Main usable if hiding fails.
  }
}

export default function HomeScreen() {
  const router = useRouter();
  const navigation = useNavigation();
  const insets = useSafeAreaInsets();
  const isFocused = useIsFocused();
  const { user } = useAuthStore();
  const [filter, setFilter] = useState<HomeTabId>('main');
  const [posts, setPosts] = useState<any[]>(() => getCachedHomePosts());
  const [pausedPostIds, setPausedPostIds] = useState<Set<string>>(new Set());
  const [activeForYouPostId, setActiveForYouPostId] = useState('');
  const [activeMainPostId, setActiveMainPostId] = useState('');
  const [mainExitVisible, setMainExitVisible] = useState(true);
  const socialPosts = useSocialState((state) => state.posts);
  const followedUserFlags = useSocialState((state) => state.followedUserIds);
  const hydrateSocialPosts = useSocialState((state) => state.hydratePosts);
  const setPostLiked = useSocialState((state) => state.setPostLiked);
  const setPostSaved = useSocialState((state) => state.setPostSaved);
  const setUserFollowing = useSocialState((state) => state.setUserFollowing);
  const [shareTarget, setShareTarget] = useState<any | null>(null);
  const [collectionTarget, setCollectionTarget] = useState<any | null>(null);
  const [postChooserVisible, setPostChooserVisible] = useState(false);
  const [collectionSaving, setCollectionSaving] = useState(false);
  const [shareFriends, setShareFriends] = useState<any[]>([]);
  const [isShareLoading, setIsShareLoading] = useState(false);
  const [sendingToId, setSendingToId] = useState<string | null>(null);
  const [commentTarget, setCommentTarget] = useState<any | null>(null);
  const [comments, setComments] = useState<any[]>([]);
  const [commentText, setCommentText] = useState('');
  const [replyingTo, setReplyingTo] = useState<any | null>(null);
  const [commentsLoading, setCommentsLoading] = useState(false);
  const [commentSending, setCommentSending] = useState(false);
  const unreadNotifications = useNotificationStore((state) => state.unreadCount);
  const setUnreadNotifications = useNotificationStore((state) => state.setUnreadCount);
  const refreshUnreadNotifications = useNotificationStore((state) => state.refreshUnreadCount);
  const mainImmersive = isFocused && filter === 'main';
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
  const likedPostIds = useMemo(() => new Set(Object.entries(socialPosts).filter(([, value]) => value.liked).map(([id]) => id)), [socialPosts]);
  const savedPostIds = useMemo(() => new Set(Object.entries(socialPosts).filter(([, value]) => value.saved).map(([id]) => id)), [socialPosts]);
  const followedUserIds = useMemo(() => new Set(Object.entries(followedUserFlags).filter(([, value]) => value).map(([id]) => id)), [followedUserFlags]);
  const feedAudioRef = useRef<Audio.Sound | null>(null);
  const feedAudioKeyRef = useRef('');
  const feedAudioRunIdRef = useRef(0);
  const mainScrollYRef = useRef(0);
  const mainScrollDownRef = useRef(0);
  const mainScrollUpRef = useRef(0);
  const mainExitVisibleRef = useRef(true);
  const mainHeaderAnim = useRef(new Animated.Value(1)).current;
  const forYouViewabilityConfig = useRef({ itemVisiblePercentThreshold: 58, minimumViewTime: 40 }).current;
  const onForYouViewableItemsChanged = useRef(({ viewableItems }: { viewableItems: { item?: any; isViewable?: boolean }[] }) => {
    const visible = viewableItems.find((entry) => entry.isViewable && entry.item?.id);
    if (visible?.item?.id) setActiveForYouPostId(String(visible.item.id));
  }).current;
  const mainViewabilityConfig = useRef({ itemVisiblePercentThreshold: 60, minimumViewTime: 80 }).current;
  const onMainViewableItemsChanged = useRef(({ viewableItems }: { viewableItems: { item?: any; isViewable?: boolean }[] }) => {
    const visibleVideo = viewableItems.find((entry) => {
      if (!entry.isViewable || !entry.item?.id) return false;
      return hasAnyVideoMedia(entry.item);
    });
    setActiveMainPostId(visibleVideo?.item?.id ? String(visibleVideo.item.id) : '');
  }).current;

  const setMainExitVisibility = useCallback((visible: boolean) => {
    if (mainExitVisibleRef.current === visible) return;
    mainExitVisibleRef.current = visible;
    setMainExitVisible(visible);
  }, []);

  const handleMainScroll = useCallback((event: any) => {
    const y = Math.max(0, Number(event?.nativeEvent?.contentOffset?.y || 0));
    const delta = y - mainScrollYRef.current;
    mainScrollYRef.current = y;
    if (Math.abs(delta) < 1.5) return;

    if (delta > 0) {
      mainScrollDownRef.current += delta;
      mainScrollUpRef.current = 0;
    } else {
      mainScrollUpRef.current += Math.abs(delta);
      mainScrollDownRef.current = 0;
    }

    if (mainExitVisibleRef.current && y > 84 && mainScrollDownRef.current > 30) {
      setMainExitVisibility(false);
      mainScrollDownRef.current = 0;
    } else if (!mainExitVisibleRef.current && (y < 18 || mainScrollUpRef.current > 66)) {
      setMainExitVisibility(true);
      mainScrollUpRef.current = 0;
    }
  }, [setMainExitVisibility]);

  useEffect(() => {
    if (filter !== 'main') return;
    mainScrollYRef.current = 0;
    mainScrollDownRef.current = 0;
    mainScrollUpRef.current = 0;
    mainExitVisibleRef.current = true;
    setMainExitVisible(true);
  }, [filter]);

  useEffect(() => {
    Animated.timing(mainHeaderAnim, {
      toValue: mainExitVisible ? 1 : 0,
      duration: mainExitVisible ? 190 : 145,
      useNativeDriver: true,
    }).start();
  }, [mainExitVisible, mainHeaderAnim]);

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
          backgroundColor: colors.bgNav,
          borderTopColor: colors.borderSubtle,
          borderTopWidth: 1,
          height: Platform.OS === 'ios' ? 88 : 64,
          paddingTop: 8,
          paddingBottom: Platform.OS === 'ios' ? 28 : 8,
          elevation: 0,
          shadowOpacity: 0,
        };
    navigation.setOptions({ tabBarStyle });
  }, [filter, navigation]);

  useEffect(() => {
    void setAndroidNavigationBarImmersive(mainImmersive);
    return () => {
      if (mainImmersive) void setAndroidNavigationBarImmersive(false);
    };
  }, [mainImmersive]);

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
    const response = await fetch(`${API_URL}/api/posts/world-board?limit=${HOME_FEED_LIMIT}`);
    if (!response.ok) return [];
    const data = await response.json();
    return Array.isArray(data) ? data : [];
  }, []);

  const getLivePostState = useCallback((post: any) => {
    const postId = String(post?.id || post?.post_id || '');
    const seed = derivePostInteractionState(post, user?.id);
    const storeSnapshot = useSocialState.getState();
    const live = postId ? storeSnapshot.posts[postId] : undefined;
    const userId = String(post?.user_id || live?.userId || '');
    const following = userId ? storeSnapshot.followedUserIds[userId] : undefined;
    return {
      liked: live?.liked ?? seed.liked ?? false,
      likesCount: live?.likesCount ?? seed.likesCount ?? Number(post?.likes_count || post?.likes || 0),
      saved: live?.saved ?? seed.saved ?? false,
      savesCount: live?.savesCount ?? seed.savesCount ?? Number(post?.saves_count || post?.saved_count || post?.saves || 0),
      following: following ?? live?.following ?? seed.following ?? false,
    };
  }, [user?.id]);

  const withLivePostState = useCallback((post: any) => {
    const live = getLivePostState(post);
    const likedBy = Array.isArray(post?.liked_by) ? post.liked_by.map(String) : [];
    const currentUserId = user?.id ? String(user.id) : '';
    const nextLikedBy = currentUserId
      ? live.liked
        ? Array.from(new Set([...likedBy, currentUserId]))
        : likedBy.filter((id: string) => id !== currentUserId)
      : likedBy;

    return {
      ...post,
      liked_by: nextLikedBy,
      liked: live.liked,
      liked_by_me: live.liked,
      likes_count: live.likesCount,
      saved: live.saved,
      is_saved: live.saved,
      bookmarked: live.saved,
      is_bookmarked: live.saved,
      saves_count: live.savesCount,
      is_following: live.following,
      followed: live.following,
      following: live.following,
    };
  }, [getLivePostState, user?.id]);

  const loadData = useCallback(async () => {
    let raw: any[] = [];
    try {
      const r = await api.get('/posts/feed', { params: { limit: HOME_FEED_LIMIT } });
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
    hydrateSocialPosts(ranked, user?.id);
    cachePostsForDetail(ranked);
    cacheHomePosts(ranked);
    setPosts(ranked);
  }, [hydrateSocialPosts, loadPublicWorldBoard, rankPosts, user?.id]);

  const loadUnreadNotifications = useCallback(async () => {
    if (!user?.id) {
      setUnreadNotifications(0);
      return;
    }
    await refreshUnreadNotifications();
  }, [refreshUnreadNotifications, setUnreadNotifications, user?.id]);

  useEffect(() => { loadData(); }, [loadData]);

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
    const warmItems = filter === 'foryou' ? forYouItems.slice(0, 6) : boardItems.slice(0, filter === 'world' ? 10 : 8);
    const task = InteractionManager.runAfterInteractions(() => {
      void prefetchPostMedia(warmItems, filter === 'world' ? 'thumb' : 'feed', filter === 'world' ? 14 : 10);
    });
    return () => task.cancel();
  }, [boardItems, filter, forYouItems]);

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

  useEffect(() => {
    if (filter !== 'main' || !isFocused) setActiveMainPostId('');
  }, [filter, isFocused]);

  const WORLD_GAP = 1;
  const WORLD_TILE_WIDTH = Math.floor((SW - WORLD_GAP * 2) / 3);
  const WORLD_TILE_LAST_WIDTH = SW - WORLD_GAP * 2 - WORLD_TILE_WIDTH * 2;
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
    const livePost = withLivePostState(post);
    cachePostForDetail(livePost);
    void prefetchPostMedia([livePost], 'detail', 8);
    router.push(`/post/${post.id}` as any);
  }, [router, withLivePostState]);

  const openCreatePost = () => {
    if (!requireVerifiedPhone(user, router, 'create posts')) return;
    setPostChooserVisible(true);
  };

  const chooseStandardPost = () => {
    setPostChooserVisible(false);
    router.push('/create-post' as any);
  };

  const chooseNotePost = () => {
    setPostChooserVisible(false);
    router.push({ pathname: '/discover', params: { compose: 'note' } } as any);
  };

  const followUser = async (post: any) => {
    if (!user) {
      router.push('/(auth)/login' as any);
      return;
    }
    if (!post?.user_id || post.user_id === user.id) return;

    const userId = String(post.user_id);
    const wasFollowing = getLivePostState(post).following;
    const nextFollowing = !wasFollowing;
    setUserFollowing(userId, nextFollowing);
    setPosts((prev) => prev.map((item) => (
      String(item.user_id) === userId
        ? { ...item, is_following: nextFollowing, followed: nextFollowing, following: nextFollowing }
        : item
    )));

    try {
      const response = await api.post(`/users/${post.user_id}/follow`, { following: nextFollowing });
      if (typeof response.data?.following === 'boolean') {
        const serverFollowing = !!response.data.following;
        setUserFollowing(userId, serverFollowing);
        setPosts((prev) => prev.map((item) => (
          String(item.user_id) === userId
            ? { ...item, is_following: serverFollowing, followed: serverFollowing, following: serverFollowing }
            : item
        )));
      }
    } catch (error: any) {
      setUserFollowing(userId, wasFollowing);
      setPosts((prev) => prev.map((item) => (
        String(item.user_id) === userId
          ? { ...item, is_following: wasFollowing, followed: wasFollowing, following: wasFollowing }
          : item
      )));
      Alert.alert('Follow failed', error?.response?.data?.detail || 'Could not follow this user.');
    }
  };

  const toggleLike = async (post: any) => {
    if (!user) {
      router.push('/(auth)/login' as any);
      return;
    }

    const postId = String(post.id);
    const live = getLivePostState(post);
    const wasLiked = live.liked;
    const previousCount = live.likesCount;
    const nextLiked = !wasLiked;
    const nextCount = Math.max(0, previousCount + (nextLiked ? 1 : -1));
    setPostLiked(postId, nextLiked, nextCount);
    setPosts((prev) => prev.map((item) => (
      String(item.id) === postId
        ? withLivePostState({ ...item, likes_count: nextCount, liked: nextLiked, liked_by_me: nextLiked })
        : item
    )));

    try {
      const response = await api.post(`/posts/${post.id}/like`, { liked: nextLiked });
      if (typeof response.data?.liked === 'boolean') {
        const serverLiked = !!response.data.liked;
        const serverCount = Number.isFinite(Number(response.data?.likes_count))
          ? Number(response.data.likes_count)
          : nextCount;
        setPostLiked(postId, serverLiked, serverCount);
        setPosts((prev) => prev.map((item) => (
          String(item.id) === postId
            ? withLivePostState({ ...item, likes_count: serverCount, liked: serverLiked, liked_by_me: serverLiked })
            : item
        )));
      }
    } catch (error: any) {
      setPostLiked(postId, wasLiked, previousCount);
      setPosts((prev) => prev.map((item) => (
        String(item.id) === postId
          ? withLivePostState({ ...item, likes_count: previousCount, liked: wasLiked, liked_by_me: wasLiked })
          : item
      )));
      Alert.alert('Like failed', error?.response?.data?.detail || 'Could not update this like.');
    }
  };

  const applySavedState = useCallback((postId: string, nextSaved: boolean, nextCount: number) => {
    setPostSaved(postId, nextSaved, nextCount);
    setPosts((prev) => prev.map((item) => (
      String(item.id) === postId
        ? withLivePostState({ ...item, saves_count: nextCount, saved: nextSaved, is_saved: nextSaved, bookmarked: nextSaved, is_bookmarked: nextSaved })
        : item
    )));
  }, [setPostSaved]);

  const toggleSave = (post: any) => {
    if (!user) {
      router.push('/(auth)/login' as any);
      return;
    }
    setCollectionTarget(post);
  };

  const saveCollectionTarget = async (collection: string) => {
    if (!collectionTarget || collectionSaving) return;

    const postId = String(collectionTarget.id);
    const live = getLivePostState(collectionTarget);
    const wasSaved = live.saved;
    const previousCount = live.savesCount;
    const nextCount = wasSaved ? previousCount : previousCount + 1;
    setCollectionSaving(true);
    applySavedState(postId, true, nextCount);

    try {
      const response = await savePostToCollection(postId, collection);
      const serverSaved = typeof response?.data?.saved === 'boolean' ? !!response.data.saved : true;
      const serverCount = Number.isFinite(Number(response?.data?.saves_count))
        ? Number(response.data.saves_count)
        : nextCount;
      applySavedState(postId, serverSaved, serverCount);
      setCollectionTarget(null);
    } catch (error: any) {
      applySavedState(postId, wasSaved, previousCount);
      Alert.alert('Save failed', error?.response?.data?.detail || 'Could not update this save.');
    } finally {
      setCollectionSaving(false);
    }
  };

  const removeCollectionTarget = async () => {
    if (!collectionTarget || collectionSaving) return;

    const postId = String(collectionTarget.id);
    const live = getLivePostState(collectionTarget);
    const wasSaved = live.saved;
    const previousCount = live.savesCount;
    const nextCount = Math.max(0, previousCount - 1);
    setCollectionSaving(true);
    applySavedState(postId, false, nextCount);

    try {
      const response = await removePostFromLibrary(postId);
      const serverSaved = typeof response?.data?.saved === 'boolean' ? !!response.data.saved : false;
      const serverCount = Number.isFinite(Number(response?.data?.saves_count))
        ? Number(response.data.saves_count)
        : nextCount;
      applySavedState(postId, serverSaved, serverCount);
      setCollectionTarget(null);
    } catch (error: any) {
      applySavedState(postId, wasSaved, previousCount);
      Alert.alert('Save failed', error?.response?.data?.detail || 'Could not remove this post from your library.');
    } finally {
      setCollectionSaving(false);
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
    const submitPostReport = async (reason: string, details: string) => {
      try {
        await api.post('/reports', {
          reported_type: 'post',
          reported_id: post.id,
          report_type: 'post',
          content_id: post.id,
          reason,
          details,
        });
        Alert.alert('Reported', 'Thanks. We sent this to moderation.');
        setShareTarget(null);
      } catch (error: any) {
        Alert.alert('Report failed', error?.response?.data?.detail || 'Could not report this post.');
      }
    };
    Alert.alert(
      'Report this post?',
      'This sends a report to Flames moderation.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Spam or scam',
          onPress: () => submitPostReport('spam', 'User reported spam or scam from the share menu.'),
        },
        {
          text: 'Private info',
          onPress: () => submitPostReport('private_personal_information', 'User reported private personal information.'),
        },
        {
          text: 'Copyright',
          onPress: () => submitPostReport('copyright_issue', 'User reported stolen or copyrighted content.'),
        },
        {
          text: 'Other',
          style: 'destructive',
          onPress: () => submitPostReport('other', 'User reported this post from the share menu.'),
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
        client_request_id: `comment_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`,
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
      const response = await api.post(`/comments/${commentId}/like`, { liked: !wasLiked });
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
    const submitCommentReport = async (reason: string) => {
      try {
        await api.post('/reports', {
          reported_type: 'comment',
          reported_id: comment.id,
          report_type: 'comment',
          content_id: comment.post_id || commentTarget?.id,
          reason,
          details: String(comment.content || '').slice(0, 500),
        });
        Alert.alert('Reported', 'Thanks. We sent this to moderation.');
      } catch (error: any) {
        Alert.alert('Report failed', error?.response?.data?.detail || 'Could not report this comment.');
      }
    };
    Alert.alert(
      'Report this comment?',
      'This sends the comment to Flames moderation.',
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Harassment', onPress: () => submitCommentReport('harassment') },
        { text: 'Private info', onPress: () => submitCommentReport('private_personal_information') },
        {
          text: 'Other',
          style: 'destructive',
          onPress: () => submitCommentReport('other'),
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
    const live = getLivePostState(p);
    const isLiked = live.liked;
    const isPaused = pausedPostIds.has(String(p.id));
    const isActive = filter === 'foryou' && String(p.id) === activeForYouPostId;
    const isFollowing = live.following;
    const canFollow = !!p.user_id && p.user_id !== user?.id;
    const authorName = p.user_full_name || p.user_username || 'Flames';
    const authorSubtitle = p.category || p.post_type || p.place_name || 'Main';
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
                <MediaPreview uri={overlayUri} mediaTypes={p.media_types} style={s.feedMedia} resizeMode="cover" showVideoBadge={false} imagePreset="feed" />
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
                  <Ionicons name={isFollowing ? 'checkmark' : 'add'} size={12} color="#FFFFFF" />
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
            <Ionicons name={isLiked ? 'flame' : 'flame-outline'} size={18} color="#FFFFFF" />
            <Text style={[s.viewerRailLabel, isLiked && s.viewerRailLabelOn]}>{formatCompactCount(live.likesCount)}</Text>
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

  const renderMainPost = ({ item: p }: { item: any }) => {
    const mediaItems = getPostMediaItems(p);
    const live = getLivePostState(p);
    const isLiked = live.liked;
    const isSaved = live.saved;
    const isFollowing = live.following;
    const canFollow = !!p.user_id && p.user_id !== user?.id;
    const authorName = p.user_full_name || p.user_username || 'Flames';
    const isActiveMainPost = isFocused && filter === 'main' && String(p.id) === activeMainPostId;

    return (
      <View style={s.mainPostCard}>
        <View style={s.mainPostHeader}>
          <TouchableOpacity
            style={s.mainAuthor}
            activeOpacity={0.86}
            disabled={!p.user_id}
            onPress={() => p.user_id && router.push(`/user/${p.user_id}` as any)}
          >
            <View style={s.mainAvatarWrap}>
              {p.user_profile_image ? (
                <Image source={{ uri: p.user_profile_image }} style={s.mainAvatar} />
              ) : (
                <View style={s.mainAvatarFallback}>
                  <Text style={s.mainAvatarInitial}>{avatarInitial(p)}</Text>
                </View>
              )}
              {canFollow ? (
                <TouchableOpacity style={s.mainFollowPlus} activeOpacity={0.9} onPress={(event: any) => { event?.stopPropagation?.(); followUser(p); }}>
                  <Ionicons name={isFollowing ? 'checkmark' : 'add'} size={12} color="#FFFFFF" />
                </TouchableOpacity>
              ) : null}
            </View>
            <View style={s.mainAuthorCopy}>
              <Text style={s.mainAuthorName} numberOfLines={1}>{authorName}</Text>
            </View>
          </TouchableOpacity>
        </View>

        <MainPostMediaCarousel
          active={isActiveMainPost}
          mediaItems={mediaItems}
          onOpen={() => openPostDetail(p)}
          post={p}
        />

        <View style={s.mainActionRow}>
          <View style={s.mainIconActions}>
            <TouchableOpacity style={s.mainIconButton} activeOpacity={0.8} onPress={() => toggleLike(p)}>
              <Ionicons name={isLiked ? 'heart' : 'heart-outline'} size={21} color={isLiked ? '#D84862' : colors.textSecondary} />
              <Text style={s.mainActionCount}>{formatCompactCount(live.likesCount)}</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.mainIconButton} activeOpacity={0.8} onPress={() => toggleSave(p)}>
              <Ionicons name={isSaved ? 'bookmark' : 'bookmark-outline'} size={20} color={isSaved ? '#151813' : MAIN_MUTED} />
              <Text style={s.mainActionCount}>{formatCompactCount(live.savesCount)}</Text>
            </TouchableOpacity>
          </View>

          <View style={s.mainCtaActions}>
            <TouchableOpacity style={s.mainViewButton} activeOpacity={0.86} onPress={() => openPostDetail(p)}>
              <Ionicons name="eye-outline" size={15} color="#30352E" />
              <Text style={s.mainViewText}>View</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.mainShareButton} activeOpacity={0.86} onPress={() => openShareSheet(p)}>
              <Ionicons name="paper-plane-outline" size={15} color="#FFFFFF" />
              <Text style={s.mainShareText}>Share</Text>
            </TouchableOpacity>
          </View>
        </View>

      </View>
    );
  };

  const renderWorldTile = ({ item: p, index }: { item: any; index: number }) => {
    const mediaUri = getPrimaryMediaUri(p);
    const isLastColumn = (index + 1) % 3 === 0;
    const tileWidth = isLastColumn ? WORLD_TILE_LAST_WIDTH : WORLD_TILE_WIDTH;

    return (
      <TouchableOpacity
        style={[
          s.worldTile,
          {
            width: tileWidth,
            height: WORLD_TILE_HEIGHT,
            marginRight: isLastColumn ? 0 : WORLD_GAP,
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
            imagePreset="thumb"
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

  const mainFeedExtraData = useMemo(() => ({
    activeMainPostId,
    followedUserIds,
    likedPostIds,
    savedPostIds,
    socialPosts,
  }), [activeMainPostId, followedUserIds, likedPostIds, savedPostIds, socialPosts]);

  const activeCollectionState = collectionTarget ? getLivePostState(collectionTarget) : null;

  return (
    <View style={s.root}>
      <StatusBar hidden={mainImmersive} animated />
      {/* STICKY HEADER — stays fixed at top */}
      <View style={[s.stickyHeader, (filter === 'foryou' || filter === 'main') && { display: 'none' }, { paddingTop: insets.top }]}>
        <View style={s.homeHeaderRow}>
          <View style={s.tabRail}>
            {HOME_TABS.map(f => (
              <TouchableOpacity key={f.id} style={[s.chip, filter === f.id && s.chipOn]} onPress={() => setFilter(f.id)} activeOpacity={0.86}>
                <Text style={[s.chipTx, filter === f.id && s.chipTxOn]}>{f.label}</Text>
              </TouchableOpacity>
            ))}
          </View>
          <TouchableOpacity style={s.hBtn} onPress={openCreatePost} activeOpacity={0.86}>
            <Ionicons name="add" size={19} color="#FFFFFF" />
          </TouchableOpacity>
          <TouchableOpacity style={s.hBtnLight} activeOpacity={0.86} onPress={() => { setUnreadNotifications(0); router.push('/notifications' as any); }}>
            <Ionicons name="notifications-outline" size={18} color={colors.accentPrimary} />
            {unreadNotifications > 0 ? (
              <View style={s.notificationBadge}>
                <Text style={s.notificationBadgeText}>{unreadNotifications > 9 ? '9+' : unreadNotifications}</Text>
              </View>
            ) : null}
          </TouchableOpacity>
        </View>
      </View>

      {filter === 'foryou' ? <ForYouDoodleBackground /> : null}

      {filter === 'main' ? (
        <Animated.View
          pointerEvents={mainExitVisible ? 'auto' : 'none'}
          style={[
            s.mainTopBar,
            s.mainTopBarFloating,
            { paddingTop: Math.max(insets.top - 2, 0) },
            {
              opacity: mainHeaderAnim,
              transform: [{
                translateY: mainHeaderAnim.interpolate({
                  inputRange: [0, 1],
                  outputRange: [-(insets.top + 56), 0],
                }),
              }],
            },
          ]}
        >
          <Text style={s.mainTopTitle}>Main</Text>
          <View style={s.mainTopActions}>
            <TouchableOpacity style={s.mainTopButton} onPress={chooseStandardPost} activeOpacity={0.86}>
              <Ionicons name="add" size={20} color={colors.textPrimary} />
            </TouchableOpacity>
            <TouchableOpacity style={s.mainTopButton} activeOpacity={0.86} onPress={() => { setUnreadNotifications(0); router.push('/notifications' as any); }}>
              <Ionicons name="notifications-outline" size={19} color={colors.textPrimary} />
              {unreadNotifications > 0 ? (
                <View style={s.notificationBadge}>
                  <Text style={s.notificationBadgeText}>{unreadNotifications > 9 ? '9+' : unreadNotifications}</Text>
                </View>
              ) : null}
            </TouchableOpacity>
          </View>
        </Animated.View>
      ) : null}

      <FlatList
        key="main-feed"
        data={boardItems}
        keyExtractor={(p) => `main-${p.id}`}
        renderItem={renderMainPost}
        style={s.mainFeedList}
        showsVerticalScrollIndicator={false}
        onScroll={handleMainScroll}
        scrollEventThrottle={16}
        contentContainerStyle={[
          s.mainFeedContent,
          boardItems.length === 0 && s.emptyFeedContent,
        ]}
        ListHeaderComponent={(
          <View
            pointerEvents="none"
            style={{ height: insets.top + 46 }}
          />
        )}
        initialNumToRender={2}
        maxToRenderPerBatch={2}
        updateCellsBatchingPeriod={48}
        windowSize={4}
        removeClippedSubviews={Platform.OS !== 'web'}
        viewabilityConfig={mainViewabilityConfig}
        onViewableItemsChanged={onMainViewableItemsChanged}
        extraData={mainFeedExtraData}
        ListEmptyComponent={(
          <View style={s.empty}>
            <Ionicons name="albums-outline" size={40} color="#DDD" />
            <Text style={s.emptyTx}>No posts in Main yet</Text>
          </View>
        )}
      />

      <SaveToCollectionModal
        visible={!!collectionTarget}
        saved={!!activeCollectionState?.saved}
        saving={collectionSaving}
        onClose={() => {
          if (!collectionSaving) setCollectionTarget(null);
        }}
        onSave={saveCollectionTarget}
        onUnsave={removeCollectionTarget}
      />

      <Modal visible={postChooserVisible} transparent animationType="fade" onRequestClose={() => setPostChooserVisible(false)}>
        <Pressable style={s.postChooserOverlay} onPress={() => setPostChooserVisible(false)}>
          <Pressable style={[s.postChooserSheet, { paddingBottom: Math.max(18, insets.bottom + 12) }]} onPress={() => {}}>
            <View style={s.shareHandle} />
            <Text style={s.postChooserTitle}>Create</Text>
            <Text style={s.postChooserSub}>Choose what you want to share.</Text>
            <View style={s.postChooserActions}>
              <TouchableOpacity style={s.postChooserOption} onPress={chooseStandardPost} activeOpacity={0.86}>
                <View style={s.postChooserIcon}>
                  <Ionicons name="images-outline" size={22} color={colors.accentPrimary} />
                </View>
                <View style={s.postChooserCopy}>
                  <Text style={s.postChooserLabel}>Post</Text>
                  <Text style={s.postChooserHint}>Photo, video, carousel, place, or caption.</Text>
                </View>
                <Ionicons name="chevron-forward" size={18} color={colors.textHint} />
              </TouchableOpacity>
              <TouchableOpacity style={s.postChooserOption} onPress={chooseNotePost} activeOpacity={0.86}>
                <View style={s.postChooserIcon}>
                  <Ionicons name="chatbox-ellipses-outline" size={22} color={colors.accentPrimary} />
                </View>
                <View style={s.postChooserCopy}>
                  <Text style={s.postChooserLabel}>Note</Text>
                  <Text style={s.postChooserHint}>Short thought, photo note, or GIF note.</Text>
                </View>
                <Ionicons name="chevron-forward" size={18} color={colors.textHint} />
              </TouchableOpacity>
            </View>
          </Pressable>
        </Pressable>
      </Modal>

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
                        <ActivityIndicator size="small" color="#FFFFFF" />
                      ) : (
                        <Text style={s.sendFriendText}>Send</Text>
                      )}
                    </TouchableOpacity>
                  </View>
                ))}
              </ScrollView>
            )}

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
                  <ActivityIndicator size="small" color="#FFFFFF" />
                ) : (
                  <Ionicons name="arrow-up" size={17} color="#FFFFFF" />
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
  root: { flex: 1, backgroundColor: colors.bgApp },

  // Sticky header
  stickyHeader: { backgroundColor: colors.bgNav, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: colors.divider, zIndex: 10 },
  stickyHeaderForYou: { position: 'absolute', left: 0, right: 0, top: 0, backgroundColor: 'transparent', borderBottomWidth: 0, zIndex: 30 },
  homeHeaderRow: { minHeight: 48, flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 14, paddingBottom: 4 },
  tabRail: { flex: 1, minWidth: 0, flexDirection: 'row', gap: 8, alignItems: 'center' },
  hBtn: {
    width: 38, height: 38, borderRadius: 19, backgroundColor: colors.accentPrimary,
    justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: colors.accentPrimaryHover,
    ...shadows.elevation1,
  },
  hBtnLight: { width: 38, height: 38, borderRadius: 19, backgroundColor: colors.surfaceRaised, justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: colors.borderSubtle, ...shadows.elevation1 },
  notificationBadge: {
    position: 'absolute', right: -2, top: -3, minWidth: 16, height: 16, borderRadius: 8,
    backgroundColor: colors.accentPrimary, borderWidth: 1.2, borderColor: colors.bgNav, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 3,
  },
  notificationBadgeText: { color: '#FFFFFF', fontSize: 9, fontWeight: '500', fontVariant: ['tabular-nums'] },
  hBtnGlass: { backgroundColor: 'rgba(0,0,0,0.42)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.24)' },
  hBtnLightGlass: { backgroundColor: 'rgba(0,0,0,0.32)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.24)' },
  forYouPatternLayer: {
    ...StyleSheet.absoluteFillObject,
    zIndex: 0,
    backgroundColor: colors.bgApp,
    overflow: 'hidden',
  },
  forYouDoodle: {
    position: 'absolute',
  },
  forYouDoodleText: {
    fontWeight: '500',
    letterSpacing: 0,
    textTransform: 'uppercase',
  },
  forYouPatternSoftener: { ...StyleSheet.absoluteFillObject, backgroundColor: colors.bgApp },
  forYouExitButton: {
    position: 'absolute', right: 14, zIndex: 60, width: 44, height: 44, borderRadius: 22,
    backgroundColor: colors.surfaceRaised, borderWidth: 1, borderColor: colors.borderSubtle,
    alignItems: 'center', justifyContent: 'center',
    ...shadows.floating,
  },
  forYouExitButtonHidden: {
    opacity: 0,
    transform: [{ translateY: -12 }],
  },

  filters: { gap: 6, alignItems: 'center' },
  chip: {
    flex: 1, minWidth: 0, minHeight: 34, paddingHorizontal: 9, paddingVertical: 5, borderRadius: 17,
    backgroundColor: colors.bgSubtle, justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: colors.borderSubtle,
  },
  chipGlass: { backgroundColor: 'rgba(0,0,0,0.32)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.18)' },
  chipOn: { backgroundColor: colors.accentPrimary, borderColor: colors.accentPrimaryHover },
  chipTx: { fontSize: 13, fontWeight: '500', color: colors.textSecondary },
  chipTxGlass: { color: 'rgba(255,255,255,0.78)' },
  chipTxOn: { color: colors.textInverse },

  // Main feed
  mainTopBar: {
    backgroundColor: MAIN_SURFACE,
    paddingHorizontal: 16,
    paddingBottom: 6,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: MAIN_BORDER,
  },
  mainTopBarFloating: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 40,
  },
  mainTopTitle: { color: '#151813', fontSize: 21, lineHeight: 26, fontWeight: '600' },
  mainTopActions: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  mainTopButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: MAIN_SUBTLE,
    borderWidth: 1,
    borderColor: MAIN_BORDER,
    alignItems: 'center',
    justifyContent: 'center',
  },
  mainFeedList: { flex: 1, backgroundColor: MAIN_SURFACE },
  mainFeedContent: {
    paddingTop: 0,
    paddingHorizontal: 0,
    paddingBottom: 118,
    backgroundColor: MAIN_SURFACE,
  },
  mainPostCard: {
    backgroundColor: MAIN_SURFACE,
    borderRadius: 0,
    overflow: 'hidden',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: 'rgba(18,24,16,0.075)',
    paddingBottom: 10,
  },
  mainPostHeader: {
    minHeight: 64, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    gap: 12, paddingHorizontal: 17, paddingTop: 12, paddingBottom: 8, backgroundColor: MAIN_SURFACE,
  },
  mainAuthor: { flex: 1, minWidth: 0, flexDirection: 'row', alignItems: 'center', gap: 10 },
  mainAvatarWrap: { width: 46, height: 46, position: 'relative', justifyContent: 'center' },
  mainAvatar: { width: 42, height: 42, borderRadius: 21, backgroundColor: MAIN_SUBTLE },
  mainAvatarFallback: {
    width: 42, height: 42, borderRadius: 21, backgroundColor: MAIN_SUBTLE,
    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: MAIN_BORDER,
  },
  mainAvatarInitial: { color: '#151813', fontSize: 17, fontWeight: '500' },
  mainFollowPlus: {
    position: 'absolute', right: 0, bottom: 1, width: 20, height: 20, borderRadius: 10,
    backgroundColor: MAIN_GREEN, borderWidth: 2, borderColor: MAIN_SURFACE, alignItems: 'center', justifyContent: 'center',
  },
  mainAuthorCopy: { flex: 1, minWidth: 0 },
  mainAuthorName: { color: '#151813', fontSize: 16, lineHeight: 21, fontWeight: '600' },
  mainFollowButton: {
    minWidth: 88, height: 38, borderRadius: 19, borderWidth: 1, borderColor: colors.borderSubtle,
    backgroundColor: MAIN_SURFACE, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 16,
  },
  mainFollowButtonOn: { backgroundColor: MAIN_SUBTLE },
  mainFollowText: { color: colors.textPrimary, fontSize: 15, fontWeight: '500' },
  mainFollowTextOn: { color: colors.textSecondary },
  mainMediaFrame: { width: '100%', backgroundColor: '#F6F6F2', overflow: 'hidden', position: 'relative' },
  mainCarouselPage: { width: SW, height: '100%', backgroundColor: MAIN_SUBTLE },
  mainCarouselDots: {
    position: 'absolute', bottom: 12, left: 0, right: 0, flexDirection: 'row',
    alignItems: 'center', justifyContent: 'center', gap: 6,
  },
  mainCarouselDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: 'rgba(255,255,255,0.62)' },
  mainCarouselDotOn: { width: 16, backgroundColor: '#FFFFFF' },
  mainMedia: { width: '100%', height: '100%' },
  mainLoadingCover: { ...StyleSheet.absoluteFillObject, backgroundColor: '#F3F3EF' },
  mainTextOnly: { flex: 1, justifyContent: 'center', padding: 24, backgroundColor: '#FAF6EE' },
  mainTextOnlyTitle: { color: '#151813', fontSize: 23, lineHeight: 30, fontWeight: '600' },
  mainVideoBadge: {
    position: 'absolute', left: 16, top: 16, width: 44, height: 44, borderRadius: 22,
    backgroundColor: 'rgba(0,0,0,0.35)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.5)',
    alignItems: 'center', justifyContent: 'center',
  },
  mainActionRow: {
    minHeight: 58,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: spacing.sm,
    paddingHorizontal: 18,
    paddingTop: 9,
    paddingBottom: 8,
    backgroundColor: MAIN_SURFACE,
  },
  mainIconActions: { flexDirection: 'row', alignItems: 'center', gap: 16 },
  mainIconButton: {
    minHeight: 42,
    borderRadius: 21,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 2,
    backgroundColor: 'transparent',
  },
  mainActionCount: { color: MAIN_MUTED, fontSize: 13, fontWeight: '500', fontVariant: ['tabular-nums'] },
  mainCtaActions: { flex: 1, minWidth: 0, flexDirection: 'row', justifyContent: 'flex-end', gap: 10 },
  mainViewButton: {
    minWidth: 74, height: 38, borderRadius: 19, borderWidth: 1, borderColor: MAIN_BORDER,
    backgroundColor: MAIN_SURFACE, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, paddingHorizontal: 12,
  },
  mainViewText: { color: '#30352E', fontSize: 13, fontWeight: '600' },
  mainShareButton: {
    minWidth: 88, height: 38, borderRadius: 19, borderWidth: 0,
    backgroundColor: MAIN_GREEN, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, paddingHorizontal: 14,
  },
  mainShareText: { color: '#FFFFFF', fontSize: 13, fontWeight: '600' },

  // World Board grid
  worldGridContent: { paddingBottom: 100, backgroundColor: '#30342D' },
  worldSection: { marginBottom: 6, backgroundColor: '#30342D' },
  worldSectionHeader: { minHeight: 34, flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 14, backgroundColor: colors.bgApp },
  worldSectionTitle: { color: colors.textPrimary, fontSize: 18, lineHeight: 23, fontWeight: '600' },
  worldSectionLine: { flex: 1, height: StyleSheet.hairlineWidth, backgroundColor: colors.borderSubtle },
  worldGallery: { flexDirection: 'row', flexWrap: 'wrap', backgroundColor: '#30342D' },
  worldTile: { overflow: 'hidden', backgroundColor: colors.bgSubtle, position: 'relative', borderRadius: 2 },
  worldMedia: { width: '100%', height: '100%' },
  worldTextTile: { flex: 1, backgroundColor: colors.surfaceTint, padding: 10, justifyContent: 'space-between' },
  worldTextAuthor: { fontSize: 11, fontWeight: '500', color: colors.textHint },
  worldTextContent: { fontSize: 15, lineHeight: 20, fontWeight: '500', color: colors.textPrimary },

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
  feedTextBackdropContent: { color: '#111', fontSize: 28, lineHeight: 34, fontWeight: '600' },
  feedEditorTextOverlay: { position: 'absolute', zIndex: 6, alignItems: 'center' },
  feedEditorTextOverlayText: {
    color: '#FFFFFF', fontSize: 24, lineHeight: 30, fontWeight: '700', textAlign: 'center',
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
  viewerAvatarText: { color: '#111111', fontSize: 21, fontWeight: '500' },
  viewerFollowPlus: { position: 'absolute', right: 0, bottom: 2, width: 20, height: 20, borderRadius: 10, backgroundColor: colors.accentPrimary, borderWidth: 1.4, borderColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center' },
  viewerAuthorCopy: { flex: 1, minWidth: 0 },
  viewerAuthorName: { color: '#FFFFFF', fontSize: 13, lineHeight: 17, fontWeight: '500', textShadowColor: 'rgba(0,0,0,0.55)', textShadowRadius: 8, textShadowOffset: { width: 0, height: 1 } },
  viewerAuthorSub: { color: 'rgba(255,255,255,0.72)', fontSize: 11, lineHeight: 14, fontWeight: '500', textShadowColor: 'rgba(0,0,0,0.5)', textShadowRadius: 8, textShadowOffset: { width: 0, height: 1 } },
  viewerChevron: { width: 42, height: 42, borderRadius: 21, alignItems: 'center', justifyContent: 'center' },
  viewerSideIndicator: { position: 'absolute', right: -12, top: '32%', width: 0, height: 0, opacity: 0 },
  viewerActionRail: {
    position: 'absolute', zIndex: 22, width: 48, gap: 8, alignItems: 'center',
  },
  viewerRailButton: {
    width: 46, minHeight: 46, borderRadius: 23, alignItems: 'center', justifyContent: 'center',
    backgroundColor: 'rgba(52,52,52,0.58)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.24)',
    shadowColor: '#000000', shadowOpacity: 0.22, shadowRadius: 10, shadowOffset: { width: 0, height: 4 }, elevation: 3,
  },
  viewerRailButtonOn: { backgroundColor: colors.accentPrimary, borderColor: 'rgba(255,255,255,0.42)' },
  viewerRailLabel: { marginTop: 2, color: '#FFFFFF', fontSize: 9, lineHeight: 11, fontWeight: '500' },
  viewerRailLabelOn: { color: '#FFFFFF' },
  viewerBottom: { position: 'absolute', zIndex: 20, alignItems: 'stretch' },
  viewerCaptionWrap: {
    alignSelf: 'flex-start', maxWidth: '78%', marginBottom: 9, borderRadius: 12,
    backgroundColor: 'rgba(0,0,0,0.22)', paddingHorizontal: 10, paddingVertical: 7,
  },
  viewerCaption: {
    color: '#FFFFFF', fontSize: 11, lineHeight: 15, fontWeight: '400',
    textShadowColor: 'rgba(0,0,0,0.52)', textShadowRadius: 8, textShadowOffset: { width: 0, height: 1 },
  },
  viewerCaptionName: { fontWeight: '500' },
  viewerControls: { minHeight: 54, flexDirection: 'row', alignItems: 'center', justifyContent: 'flex-end' },
  viewerActionCluster: { flexDirection: 'row', alignItems: 'center', gap: 8, maxWidth: '100%' },
  viewerMetricButton: { minWidth: 58, height: 42, borderRadius: 21, backgroundColor: 'rgba(48,48,48,0.68)', flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 5, paddingHorizontal: 10 },
  viewerMetricButtonOn: { backgroundColor: 'rgba(255,49,88,0.78)' },
  viewerMetricText: { color: '#FFFFFF', fontSize: 13, fontWeight: '500', fontVariant: ['tabular-nums'] },
  viewerSaveButton: { width: 38, height: 38, borderRadius: 19, backgroundColor: colors.accentPrimary, borderWidth: 1.2, borderColor: colors.accentPrimaryHover, alignItems: 'center', justifyContent: 'center' },
  viewerSaveButtonOn: { backgroundColor: colors.accentPrimary, borderColor: 'rgba(255,255,255,0.56)', transform: [{ scale: 1.03 }] },
  feedTop: { position: 'absolute', left: 16, right: 16, zIndex: 12, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  feedAuthor: { flex: 1, minWidth: 0, flexDirection: 'row', alignItems: 'center', gap: 10 },
  feedAuthorImage: { width: 42, height: 42, borderRadius: 21, borderWidth: 1.4, borderColor: 'rgba(255,255,255,0.72)' },
  feedAuthorFallback: { width: 42, height: 42, borderRadius: 21, backgroundColor: '#F5F2EA', alignItems: 'center', justifyContent: 'center', borderWidth: 1.4, borderColor: 'rgba(255,255,255,0.72)' },
  feedAuthorInitial: { color: '#111', fontSize: 18, fontWeight: '500' },
  feedAuthorCopy: { flex: 1, minWidth: 0 },
  feedAuthorName: { color: '#FFF', fontSize: 15, lineHeight: 18, fontWeight: '500' },
  feedAuthorSub: { color: 'rgba(255,255,255,0.78)', fontSize: 12, lineHeight: 15, fontWeight: '500', marginTop: 1 },
  feedFollowPill: { minHeight: 32, borderRadius: 16, backgroundColor: colors.accentPrimary, borderWidth: 1.2, borderColor: 'rgba(255,255,255,0.28)', paddingHorizontal: 11, flexDirection: 'row', alignItems: 'center', gap: 4 },
  feedFollowText: { color: '#FFFFFF', fontSize: 12, fontWeight: '500' },
  feedRail: { position: 'absolute', right: 13, bottom: 118, gap: 16, alignItems: 'center' },
  creatorButton: { width: 60, height: 60, borderRadius: 30, backgroundColor: 'rgba(255,255,255,0.18)', alignItems: 'center', justifyContent: 'center', borderWidth: 1.5, borderColor: 'rgba(255,255,255,0.82)' },
  creatorImage: { width: 52, height: 52, borderRadius: 26 },
  creatorFallback: { width: 52, height: 52, borderRadius: 26, backgroundColor: '#F5F2EA', alignItems: 'center', justifyContent: 'center' },
  creatorFallbackText: { color: '#111', fontSize: 25, fontWeight: '500' },
  followPlus: { position: 'absolute', bottom: -7, right: -4, width: 24, height: 24, borderRadius: 12, backgroundColor: colors.accentPrimary, borderWidth: 2, borderColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center' },
  railAction: { width: 62, alignItems: 'center' },
  roundAction: { width: 52, height: 52, borderRadius: 26, backgroundColor: 'rgba(0,0,0,0.34)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.22)', alignItems: 'center', justifyContent: 'center' },
  roundActionOn: { backgroundColor: 'rgba(255,255,255,0.92)' },
  actionCount: { marginTop: 5, color: '#FFF', fontSize: 11, lineHeight: 13, fontWeight: '500', backgroundColor: 'rgba(0,0,0,0.34)', borderRadius: 9, overflow: 'hidden', paddingHorizontal: 7, paddingVertical: 2 },
  feedBottom: { position: 'absolute', left: 16, right: 88, gap: 10 },
  feedMeta: { minHeight: 42, justifyContent: 'flex-end' },
  feedHandle: { color: '#FFF', fontSize: 16, lineHeight: 20, fontWeight: '500' },
  feedCaption: { marginTop: 2, color: 'rgba(255,255,255,0.92)', fontSize: 14, lineHeight: 18, fontWeight: '400' },
  feedCta: { alignSelf: 'flex-start', minHeight: 38, paddingHorizontal: 16, borderRadius: 19, borderWidth: 1.2, borderColor: 'rgba(255,255,255,0.26)', backgroundColor: colors.accentPrimary, justifyContent: 'center' },
  feedCtaText: { color: '#FFFFFF', fontSize: 14, fontWeight: '500' },
  emptyFeedContent: { flexGrow: 1, paddingBottom: 100 },
  empty: { paddingTop: 100, alignItems: 'center' },
  emptyTx: { fontSize: 14, color: colors.textHint, marginTop: 10, fontWeight: '500' },
  postChooserOverlay: { flex: 1, justifyContent: 'flex-end', backgroundColor: 'rgba(244,245,241,0.62)' },
  postChooserSheet: { backgroundColor: colors.bgModal, borderTopLeftRadius: 26, borderTopRightRadius: 26, paddingTop: 10, paddingHorizontal: 16, gap: 8, ...shadows.sheet },
  postChooserTitle: { color: colors.textPrimary, fontSize: 22, lineHeight: 27, fontWeight: '700', marginTop: 2 },
  postChooserSub: { color: colors.textSecondary, fontSize: 13, lineHeight: 18, fontWeight: '500', marginBottom: 6 },
  postChooserActions: { gap: 8 },
  postChooserOption: { minHeight: 66, borderRadius: 18, backgroundColor: colors.bgSubtle, borderWidth: 1, borderColor: colors.borderSubtle, flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 12 },
  postChooserIcon: { width: 42, height: 42, borderRadius: 21, backgroundColor: colors.surfaceRaised, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: colors.borderSubtle },
  postChooserCopy: { flex: 1, minWidth: 0 },
  postChooserLabel: { color: colors.textPrimary, fontSize: 16, lineHeight: 21, fontWeight: '700' },
  postChooserHint: { color: colors.textSecondary, fontSize: 12, lineHeight: 16, fontWeight: '500', marginTop: 1 },
  shareOverlay: { flex: 1, justifyContent: 'flex-end', backgroundColor: colors.modalScrim },
  shareSheet: { backgroundColor: colors.bgModal, borderTopLeftRadius: 28, borderTopRightRadius: 28, paddingTop: 10, paddingHorizontal: 16, gap: 14, ...shadows.sheet },
  shareHandle: { alignSelf: 'center', width: 42, height: 5, borderRadius: 3, backgroundColor: colors.borderMedium },
  shareHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  shareTitle: { color: colors.textPrimary, fontSize: 22, fontWeight: '500' },
  shareSubtitle: { color: colors.textSecondary, fontSize: 13, fontWeight: '500', marginTop: 2 },
  shareClose: { width: 36, height: 36, borderRadius: 18, backgroundColor: colors.bgSubtle, alignItems: 'center', justifyContent: 'center' },
  shareSectionTitle: { color: colors.textPrimary, fontSize: 15, fontWeight: '500' },
  shareLoading: { height: 116, alignItems: 'center', justifyContent: 'center' },
  friendRail: { gap: 10, paddingRight: 8 },
  noFriendsCard: { width: 220, minHeight: 104, borderRadius: 18, backgroundColor: colors.bgSubtle, alignItems: 'center', justifyContent: 'center', padding: 14 },
  noFriendsText: { color: colors.textSecondary, textAlign: 'center', fontSize: 13, fontWeight: '500' },
  friendCard: { width: 88, minHeight: 126, borderRadius: 18, backgroundColor: colors.surfaceRaised, borderWidth: 1, borderColor: colors.borderSubtle, alignItems: 'center', padding: 8, gap: 6, ...shadows.elevation1 },
  friendAvatarWrap: { width: 54, height: 54, borderRadius: 27 },
  friendAvatar: { width: 54, height: 54, borderRadius: 27 },
  friendAvatarFallback: { width: 54, height: 54, borderRadius: 27, backgroundColor: colors.accentPrimaryLight, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: colors.borderSubtle },
  friendAvatarText: { color: colors.textPrimary, fontSize: 21, fontWeight: '500' },
  friendName: { width: '100%', color: colors.textPrimary, fontSize: 12, fontWeight: '600', textAlign: 'center' },
  sendFriendBtn: { minWidth: 58, height: 28, borderRadius: 14, backgroundColor: colors.accentPrimary, borderWidth: 1, borderColor: colors.accentPrimaryHover, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 10 },
  sendFriendText: { color: '#FFFFFF', fontSize: 12, fontWeight: '500' },
  shareActions: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  shareAction: { width: '48%', minHeight: 48, borderRadius: 16, backgroundColor: colors.bgSubtle, flexDirection: 'row', alignItems: 'center', gap: 9, paddingHorizontal: 12 },
  shareActionText: { color: colors.textPrimary, fontSize: 13, fontWeight: '500' },
  reportText: { color: '#B42318' },
  commentOverlay: { flex: 1, justifyContent: 'flex-end' },
  commentBackdrop: { ...StyleSheet.absoluteFillObject, backgroundColor: colors.modalScrim },
  commentSheet: { maxHeight: '78%', minHeight: 410, backgroundColor: colors.bgModal, borderTopLeftRadius: 28, borderTopRightRadius: 28, paddingTop: 10, paddingHorizontal: 16, gap: 12, ...shadows.sheet },
  commentHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  commentTitle: { color: colors.textPrimary, fontSize: 22, fontWeight: '500' },
  commentSubtitle: { color: colors.textSecondary, fontSize: 13, fontWeight: '500', marginTop: 2, maxWidth: SW - 90 },
  commentLoading: { minHeight: 190, alignItems: 'center', justifyContent: 'center' },
  commentList: { flex: 1 },
  commentListContent: { gap: 12, paddingVertical: 4, paddingBottom: 10 },
  emptyComments: { minHeight: 190, alignItems: 'center', justifyContent: 'center', gap: 8 },
  emptyCommentsText: { color: colors.textHint, fontSize: 14, fontWeight: '600' },
  commentThread: { gap: 8 },
  commentThreadReply: { marginTop: 0 },
  commentRow: { flexDirection: 'row', alignItems: 'flex-start', gap: 10 },
  commentRowReply: { paddingLeft: 0 },
  commentAvatar: { width: 38, height: 38, borderRadius: 19, backgroundColor: '#EEE' },
  commentAvatarSmall: { width: 30, height: 30, borderRadius: 15 },
  commentAvatarFallback: { width: 38, height: 38, borderRadius: 19, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.accentPrimaryLight, borderWidth: 1, borderColor: colors.borderSubtle },
  commentAvatarText: { color: colors.textPrimary, fontSize: 15, fontWeight: '500' },
  commentBodyColumn: { flex: 1, minWidth: 0, gap: 5 },
  commentBubble: { flex: 1, minWidth: 0, borderRadius: 17, backgroundColor: colors.bgSubtle, paddingHorizontal: 12, paddingVertical: 10 },
  commentBubbleReply: { backgroundColor: colors.surfaceRaised, borderWidth: 1, borderColor: colors.borderSubtle },
  commentName: { color: colors.textPrimary, fontSize: 13, fontWeight: '500', marginBottom: 3 },
  commentBody: { color: colors.textPrimary, fontSize: 14, lineHeight: 19, fontWeight: '400' },
  commentActionsRow: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 10, paddingLeft: 4 },
  commentActionPill: { minHeight: 25, flexDirection: 'row', alignItems: 'center', gap: 4 },
  commentActionText: { color: colors.textSecondary, fontSize: 12, fontWeight: '500' },
  commentActionTextOn: { color: colors.accentPrimary },
  commentReplies: { marginLeft: 48, paddingLeft: 12, borderLeftWidth: 2, borderLeftColor: '#ECE8DF', gap: 9 },
  replyBanner: { minHeight: 38, borderRadius: 16, backgroundColor: colors.accentPrimaryLight, borderWidth: 1, borderColor: colors.borderMedium, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 10, paddingLeft: 13, paddingRight: 8 },
  replyBannerText: { flex: 1, color: colors.textPrimary, fontSize: 13, fontWeight: '500' },
  replyCancel: { width: 26, height: 26, borderRadius: 13, alignItems: 'center', justifyContent: 'center', backgroundColor: '#FFFFFF' },
  commentComposer: { minHeight: 50, flexDirection: 'row', alignItems: 'center', gap: 8, borderRadius: 25, backgroundColor: colors.bgSubtle, paddingLeft: 16, paddingRight: 5 },
  commentInput: { flex: 1, minHeight: 48, color: colors.textPrimary, fontSize: 15, fontWeight: '400', paddingVertical: 0 },
  commentSend: { width: 38, height: 38, borderRadius: 19, backgroundColor: colors.accentPrimary, borderWidth: 1, borderColor: colors.accentPrimaryHover, alignItems: 'center', justifyContent: 'center' },
  commentSendDisabled: { opacity: 0.45 },
});
