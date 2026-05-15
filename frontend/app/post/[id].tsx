import React, { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, ActivityIndicator,
  TextInput, Dimensions, KeyboardAvoidingView, Platform, Share, Modal,
  ScrollView, StatusBar, Alert, InteractionManager,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useVideoPlayer, VideoView } from 'expo-video';
import { useAuthStore } from '../../src/store/authStore';
import {
  cachePostCommentsForDetail,
  cachePostForDetail,
  getCachedPostCommentsForDetail,
  getCachedPostForDetail,
} from '../../src/store/postDetailCache';
import { derivePostInteractionState, useSocialState } from '../../src/store/socialState';
import api from '../../src/api/client';
import { getWallet, sendCoinGift } from '../../src/api/wallet';
import { isCFStreamVideo, extractStreamUid, getStreamPlaybackInfo } from '../../src/utils/mediaUpload';
import { parseCreatorEditorOverlays, type CreatorTextOverlay } from '../../src/utils/creatorEditor';
import OptimizedImage from '../../src/components/OptimizedImage';
import MediaPreview from '../../src/components/MediaPreview';
import SaveToCollectionModal from '../../src/components/SaveToCollectionModal';
import { optimizeImageUrl, prefetchImageUrls } from '../../src/utils/optimizedMedia';
import { removePostFromLibrary, savePostToCollection } from '../../src/utils/librarySave';
import { colors } from '../../src/utils/theme';
import { formatDistanceToNow } from 'date-fns';

const { width: SW } = Dimensions.get('window');
const clampNumber = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));
const DETAIL_HEADLINE_FONT_SIZE = clampNumber(Math.round(SW * 0.064), 24, 30);
const DETAIL_CAPTION_FONT_SIZE = clampNumber(Math.round(SW * 0.041), 15, 17);
const DETAIL_EMPTY_CAPTION_FONT_SIZE = clampNumber(Math.round(SW * 0.036), 13, 15);
const UI_BLACK = colors.textPrimary;
const UI_WHITE = colors.surfaceRaised;
const UI_LIME = colors.accentPrimary;
const UI_SURFACE = colors.bgSubtle;
const UI_BORDER = colors.divider;
const UI_MUTED = colors.textSecondary;
const UI_ERROR = colors.error;
const DETAIL_MEDIA_HEIGHT_RATIO = 4 / 3;
type IoniconName = React.ComponentProps<typeof Ionicons>['name'];
type GiftPreset = { id: string; label: string; coins: number; visual: string; icon: IoniconName; tone: string };
const GIFT_PRESETS: GiftPreset[] = [
  { id: 'thumbs_up', label: 'Thumbs Up!', coins: 5, visual: '👍', icon: 'thumbs-up-outline', tone: '#E8F8FF' },
  { id: 'fire', label: 'This is Fire', coins: 10, visual: '🔥', icon: 'flame-outline', tone: '#FFF1D8' },
  { id: 'rose', label: 'Accept this Rose', coins: 15, visual: '🌹', icon: 'gift-outline', tone: '#FFE8EF' },
  { id: 'love', label: 'Love', coins: 25, visual: '💖', icon: 'heart-outline', tone: '#FFEAF7' },
  { id: 'happy_day', label: 'Happy Day', coins: 50, visual: '🌈', icon: 'happy-outline', tone: '#EAF8FF' },
  { id: 'fancy_pearl', label: 'Fancy Pearl', coins: 100, visual: '🦪', icon: 'ellipse-outline', tone: '#F3ECFF' },
  { id: 'first_place', label: '1st Place', coins: 250, visual: '🥇', icon: 'medal-outline', tone: '#FFF2C7' },
  { id: 'lets_ride', label: "Let's ride", coins: 500, visual: '🏎️', icon: 'car-sport-outline', tone: '#FFE9E9' },
  { id: 'gold_medal', label: 'Gold Medal', coins: 1000, visual: '🏅', icon: 'ribbon-outline', tone: '#FFF5CC' },
  { id: 'elite_status', label: 'Elite Status', coins: 1500, visual: '🛩️', icon: 'airplane-outline', tone: '#E8EEF9' },
  { id: 'ice_diamond', label: 'Ice Diamond', coins: 2000, visual: '💎', icon: 'diamond-outline', tone: '#E8FBFF' },
  { id: 'pure_royalty', label: 'Pure Royalty', coins: 3000, visual: '👑', icon: 'sparkles-outline', tone: '#FFF0D7' },
];
const COMMENT_REACTIONS = ['🍋', '🥰', '❤️', '🔥', '😍', '😂', '😭', '🥺'];

function formatGiftCoins(value: number) {
  return Math.max(0, Number(value || 0)).toLocaleString('en-US');
}

function normalizePostMediaTypes(mediaTypes?: string[] | string | null): string[] {
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

function parsePostMediaUris(value: unknown): string[] {
  if (Array.isArray(value)) return value.map((item) => String(item || '').trim()).filter(Boolean);
  if (typeof value === 'string' && value.trim()) {
    try {
      const parsed = JSON.parse(value);
      if (Array.isArray(parsed)) return parsed.map((item) => String(item || '').trim()).filter(Boolean);
    } catch {}
    return [value.trim()];
  }
  return [];
}

function isPostVideoMedia(uri?: string | null, mediaTypes?: string[] | string | null, index = 0): boolean {
  if (!uri) return false;
  if (isCFStreamVideo(uri)) return true;
  if (/^data:video\//i.test(uri)) return true;
  if (/\.(mp4|mov|m4v|webm|m3u8)(\?.*)?$/i.test(uri)) return true;
  if (/\.(jpe?g|png|webp|gif|heic|heif|avif)(\?.*)?$/i.test(uri)) return false;
  const types = normalizePostMediaTypes(mediaTypes);
  if (String(types[index] || '').includes('video')) return true;
  return false;
}

function splitCaptionFallback(value: string): { headline: string; body: string } {
  const normalized = String(value || '').replace(/\r\n/g, '\n').trim();
  if (!normalized) return { headline: '', body: '' };
  const lines = normalized.split('\n').map((line) => line.trim()).filter(Boolean);
  if (lines.length > 1) {
    return { headline: lines[0], body: lines.slice(1).join('\n') };
  }
  const sentenceMatch = normalized.match(/^(.{18,120}?[.!?])\s+(.+)$/);
  if (sentenceMatch) {
    return { headline: sentenceMatch[1].trim(), body: sentenceMatch[2].trim() };
  }
  return { headline: normalized, body: '' };
}

function normalizeCommentRow(comment: any) {
  return {
    ...comment,
    id: String(comment?.id || ''),
    parent_id: comment?.parent_id ? String(comment.parent_id) : null,
    likes_count: Number(comment?.likes_count || 0),
    liked_by_me: !!comment?.liked_by_me,
  };
}

function getCommentName(comment: any) {
  return String(comment?.user_full_name || comment?.user_username || 'User');
}

function insertCommentInThread(existing: any[], incoming: any) {
  const nextComment = normalizeCommentRow(incoming);
  if (!nextComment.parent_id) return [...existing, nextComment];
  const parentIndex = existing.findIndex((item) => String(item.id) === nextComment.parent_id);
  if (parentIndex < 0) return [...existing, nextComment];
  let insertIndex = parentIndex + 1;
  while (insertIndex < existing.length && String(existing[insertIndex]?.parent_id || '') === nextComment.parent_id) {
    insertIndex += 1;
  }
  return [...existing.slice(0, insertIndex), nextComment, ...existing.slice(insertIndex)];
}

/* ════════════════════════════════════════════════════════════════════════
   MAIN SCREEN — wraps PostContent with edge-swipe post navigation
   ════════════════════════════════════════════════════════════════════════ */
export default function PostDetailScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { id: postId } = useLocalSearchParams<{ id: string }>();
  const { user } = useAuthStore();

  return (
    <View style={s.root}>
      <StatusBar barStyle="dark-content" />
      <View style={{ flex: 1 }}>
        <PostContent
          postId={postId || ''}
          user={user}
          router={router}
          insets={insets}
        />
      </View>
    </View>
  );
}

/* ════════════════════════════════════════════════════════════════════════
   POST CONTENT — the actual post detail view (reusable per-post)
   ════════════════════════════════════════════════════════════════════════ */
const PostContent = React.memo(function PostContent({ postId, user, router, insets }: {
  postId: string; user: any; router: any; insets: any;
}) {
  const initialCachedPostRef = useRef<any>(getCachedPostForDetail(postId));
  const initialCachedCommentsRef = useRef<any[] | null>(getCachedPostCommentsForDetail(postId));
  const [post, setPost] = useState<any>(initialCachedPostRef.current);
  const [comments, setComments] = useState<any[]>(initialCachedCommentsRef.current || []);
  const [commentsLoaded, setCommentsLoaded] = useState(!!initialCachedCommentsRef.current?.length);
  const [commentsLoading, setCommentsLoading] = useState(false);
  const [isLoading, setIsLoading] = useState(!initialCachedPostRef.current);
  const [newComment, setNewComment] = useState('');
  const [isCommenting, setIsCommenting] = useState(false);
  const [liked, setLiked] = useState(false);
  const [likesCount, setLikesCount] = useState(0);
  const [saved, setSaved] = useState(false);
  const [savedCount, setSavedCount] = useState(0);
  const [collectionModalVisible, setCollectionModalVisible] = useState(false);
  const [collectionSaving, setCollectionSaving] = useState(false);
  const [activeImgIdx, setActiveImgIdx] = useState(0);
  const [videoHlsUrl, setVideoHlsUrl] = useState<string | null>(null);
  const [captionExpanded, setCaptionExpanded] = useState(false);
  const [commentSheetVisible, setCommentSheetVisible] = useState(false);
  const [replyingTo, setReplyingTo] = useState<any | null>(null);
  const [pendingCommentLikes, setPendingCommentLikes] = useState<Set<string>>(() => new Set());
  const [reportingCommentId, setReportingCommentId] = useState<string | null>(null);
  const [giftSheetVisible, setGiftSheetVisible] = useState(false);
  const [selectedGiftId, setSelectedGiftId] = useState('');
  const [giftBalance, setGiftBalance] = useState<number | null>(null);
  const [giftBalanceLoading, setGiftBalanceLoading] = useState(false);
  const [sendingGiftId, setSendingGiftId] = useState<string | null>(null);
  const [following, setFollowing] = useState(false);
  const [isFollowLoading, setIsFollowLoading] = useState(false);
  const socialPosts = useSocialState((state) => state.posts);
  const followedUserFlags = useSocialState((state) => state.followedUserIds);
  const hydrateSocialPosts = useSocialState((state) => state.hydratePosts);
  const setPostLiked = useSocialState((state) => state.setPostLiked);
  const setPostSaved = useSocialState((state) => state.setPostSaved);
  const setUserFollowing = useSocialState((state) => state.setUserFollowing);
  const videoResolveKeyRef = useRef('');
  const commentSheetInputRef = useRef<TextInput>(null);

  const getLivePostState = useCallback((p: any) => {
    const targetPostId = String(p?.id || postId || '');
    const seed = derivePostInteractionState(p, user?.id);
    const storeSnapshot = useSocialState.getState();
    const live = targetPostId ? storeSnapshot.posts[targetPostId] : undefined;
    const authorId = String(p?.user_id || live?.userId || '');
    const liveFollowing = authorId ? storeSnapshot.followedUserIds[authorId] : undefined;
    return {
      liked: live?.liked ?? seed.liked ?? false,
      likesCount: live?.likesCount ?? seed.likesCount ?? Number(p?.likes_count || p?.likes || 0),
      saved: live?.saved ?? seed.saved ?? false,
      savesCount: live?.savesCount ?? seed.savesCount ?? Number(p?.saves_count || p?.saved_count || p?.saves || 0),
      following: liveFollowing ?? live?.following ?? seed.following ?? false,
    };
  }, [postId, user?.id]);

  const patchLocalPost = useCallback((patch: Record<string, any>) => {
    setPost((prev: any) => {
      if (!prev) return prev;
      const next = { ...prev, ...patch };
      cachePostForDetail(next);
      return next;
    });
  }, []);

  const applyPostState = useCallback((p: any) => {
    if (!p) return;
    hydrateSocialPosts([p], user?.id);
    const live = getLivePostState(p);
    cachePostForDetail(p);
    setPost(p);
    setLiked(live.liked);
    setLikesCount(live.likesCount);
    setSaved(live.saved);
    setSavedCount(live.savesCount);
    setFollowing(live.following);
  }, [getLivePostState, hydrateSocialPosts, user?.id]);

  const resolveVideoFromPost = useCallback(async (p: any) => {
    const imageItems = parsePostMediaUris(p?.images);
    const allMedia: string[] = imageItems.length > 0
      ? imageItems
      : typeof p?.image === 'string' && p.image
        ? [p.image]
        : [];
    const mediaTypes: string[] = p?.media_types || [];
    const videoUri = allMedia.find((uri, index) => isPostVideoMedia(uri, mediaTypes, index));
    if (!videoUri) {
      videoResolveKeyRef.current = '';
      setVideoHlsUrl(null);
      return;
    }
    if (videoResolveKeyRef.current === videoUri) return;
    videoResolveKeyRef.current = videoUri;
    setVideoHlsUrl(null);
    for (let i = 0; i < allMedia.length; i++) {
      if (!isPostVideoMedia(allMedia[i], mediaTypes, i)) continue;
      const uid = extractStreamUid(allMedia[i]);
      if (uid) {
        try {
          const info = await getStreamPlaybackInfo(uid);
          if (info?.hls) setVideoHlsUrl(info.hls);
        } catch { }
        return;
      }
      if (allMedia[i]?.startsWith('http') || allMedia[i]?.startsWith('data:')) {
        setVideoHlsUrl(allMedia[i]);
        return;
      }
    }
  }, []);

  const loadPostData = useCallback(async (seedPost?: any) => {
    if (!postId) return;
    if (!seedPost) setIsLoading(true);
    try {
      const postRes = await api.get(`/posts/${postId}`);
      const p = postRes.data;
      applyPostState(p);
      setIsLoading(false);
      void resolveVideoFromPost(p);
      InteractionManager.runAfterInteractions(() => {
        api.get(`/bookmarks/check/${postId}`).then((bm) => {
          const checkedSaved = bm.data?.saved || false;
          setSaved(checkedSaved);
          setPostSaved(postId, checkedSaved);
          patchLocalPost({ saved: checkedSaved, is_saved: checkedSaved, bookmarked: checkedSaved, is_bookmarked: checkedSaved });
        }).catch(() => undefined);
      });
    } catch (error) {
      if (!seedPost) {
        console.log('Error loading post:', error);
        setPost(null);
      }
    } finally {
      if (!seedPost) setIsLoading(false);
    }
  }, [applyPostState, patchLocalPost, postId, resolveVideoFromPost, setPostSaved]);

  const loadComments = useCallback(async () => {
    if (!postId || commentsLoading || commentsLoaded) return;
    setCommentsLoading(true);
    try {
      const commentsRes = await api.get(`/posts/${postId}/comments`);
      const nextComments = (Array.isArray(commentsRes.data) ? commentsRes.data : []).map(normalizeCommentRow);
      cachePostCommentsForDetail(postId, nextComments);
      setComments(nextComments);
      setCommentsLoaded(true);
    } catch {
      setCommentsLoaded(true);
    } finally {
      setCommentsLoading(false);
    }
  }, [commentsLoaded, commentsLoading, postId]);

  // Reset state when postId changes (post-to-post navigation)
  useEffect(() => {
    let refreshTask: { cancel?: () => void } | null = null;
    const cached = getCachedPostForDetail(postId);
    const cachedComments = getCachedPostCommentsForDetail(postId);
    setComments(cachedComments || []);
    setCommentsLoaded(!!cachedComments && (cachedComments.length > 0 || Number(cached?.comments_count || 0) <= 0));
    setCommentsLoading(false);
    setReplyingTo(null);
    setCommentSheetVisible(false);
    setPendingCommentLikes(new Set());
    setReportingCommentId(null);
    setActiveImgIdx(0);
    setVideoHlsUrl(null);
    videoResolveKeyRef.current = '';
    setCaptionExpanded(false);
    setSaved(false);
    setSavedCount(0);
    setFollowing(false);
    setGiftSheetVisible(false);
    setSelectedGiftId('');
    setGiftBalance(null);
    setGiftBalanceLoading(false);
    setSendingGiftId(null);
    setIsFollowLoading(false);
    if (cached) {
      applyPostState(cached);
      setIsLoading(false);
      void resolveVideoFromPost(cached);
    } else {
      setPost(null);
      setIsLoading(true);
    }
    if (postId) {
      if (cached) {
        refreshTask = InteractionManager.runAfterInteractions(() => {
          void loadPostData(cached);
        });
      } else {
        void loadPostData();
      }
    }
    return () => {
      refreshTask?.cancel?.();
    };
  }, [applyPostState, loadPostData, postId, resolveVideoFromPost]);

  const knownCommentCount = Number(post?.comments_count || 0);

  useEffect(() => {
    if (knownCommentCount <= 0 || commentsLoaded || commentsLoading) return;
    const task = InteractionManager.runAfterInteractions(() => {
      void loadComments();
    });
    return () => task.cancel();
  }, [commentsLoaded, commentsLoading, knownCommentCount, loadComments]);

  useEffect(() => {
    if (!commentSheetVisible) return;
    const handle = setTimeout(() => commentSheetInputRef.current?.focus(), 120);
    return () => clearTimeout(handle);
  }, [commentSheetVisible]);

  // ── Actions ──
  useEffect(() => {
    if (!post) return;
    const live = getLivePostState(post);
    if (liked !== live.liked) setLiked(live.liked);
    if (likesCount !== live.likesCount) setLikesCount(live.likesCount);
    if (saved !== live.saved) setSaved(live.saved);
    if (savedCount !== live.savesCount) setSavedCount(live.savesCount);
    if (following !== live.following) setFollowing(live.following);
  }, [followedUserFlags, following, getLivePostState, liked, likesCount, post, saved, savedCount, socialPosts]);

  const handleLike = async () => {
    if (!user) {
      router.push('/(auth)/login' as any);
      return;
    }
    const live = getLivePostState(post);
    const wasLiked = live.liked;
    const previousCount = live.likesCount;
    const nextLiked = !wasLiked;
    const nextCount = Math.max(0, previousCount + (nextLiked ? 1 : -1));
    setLiked(nextLiked);
    setLikesCount(nextCount);
    setPostLiked(postId, nextLiked, nextCount);
    patchLocalPost({ likes_count: nextCount, liked: nextLiked, liked_by_me: nextLiked });
    try {
      const response = await api.post(`/posts/${postId}/like`, { liked: nextLiked });
      if (typeof response.data?.liked === 'boolean') {
        const serverLiked = !!response.data.liked;
        const serverCount = Number.isFinite(Number(response.data?.likes_count)) ? Number(response.data.likes_count) : nextCount;
        setLiked(serverLiked);
        setLikesCount(serverCount);
        setPostLiked(postId, serverLiked, serverCount);
        patchLocalPost({ likes_count: serverCount, liked: serverLiked, liked_by_me: serverLiked });
      }
    } catch {
      setLiked(wasLiked);
      setLikesCount(previousCount);
      setPostLiked(postId, wasLiked, previousCount);
      patchLocalPost({ likes_count: previousCount, liked: wasLiked, liked_by_me: wasLiked });
    }
  };

  const applySavedState = useCallback((nextSaved: boolean, nextCount: number) => {
    setSaved(nextSaved);
    setSavedCount(nextCount);
    setPostSaved(postId, nextSaved, nextCount);
    patchLocalPost({ saves_count: nextCount, saved: nextSaved, is_saved: nextSaved, bookmarked: nextSaved, is_bookmarked: nextSaved });
  }, [patchLocalPost, postId, setPostSaved]);

  const handleSave = () => {
    if (!user) {
      router.push('/(auth)/login' as any);
      return;
    }
    setCollectionModalVisible(true);
  };

  const saveToCollection = async (collection: string) => {
    if (collectionSaving) return;
    const wasSaved = saved;
    const previousCount = savedCount;
    const nextCount = wasSaved ? previousCount : previousCount + 1;
    setCollectionSaving(true);
    applySavedState(true, nextCount);
    try {
      const response = await savePostToCollection(postId, collection);
      const serverSaved = typeof response?.data?.saved === 'boolean' ? !!response.data.saved : true;
      const serverCount = Number.isFinite(Number(response?.data?.saves_count))
        ? Number(response.data.saves_count)
        : nextCount;
      applySavedState(serverSaved, serverCount);
      setCollectionModalVisible(false);
    } catch {
      applySavedState(wasSaved, previousCount);
      Alert.alert('Save failed', 'Could not save this post to your collection.');
    } finally {
      setCollectionSaving(false);
    }
  };

  const removeFromCollection = async () => {
    if (collectionSaving) return;
    const wasSaved = saved;
    const previousCount = savedCount;
    const nextCount = Math.max(0, previousCount - 1);
    setCollectionSaving(true);
    applySavedState(false, nextCount);
    try {
      const response = await removePostFromLibrary(postId);
      const serverSaved = typeof response?.data?.saved === 'boolean' ? !!response.data.saved : false;
      const serverCount = Number.isFinite(Number(response?.data?.saves_count))
        ? Number(response.data.saves_count)
        : nextCount;
      applySavedState(serverSaved, serverCount);
      setCollectionModalVisible(false);
    } catch {
      applySavedState(wasSaved, previousCount);
      Alert.alert('Save failed', 'Could not remove this post from your library.');
    } finally {
      setCollectionSaving(false);
    }
  };

  const updateCommentById = useCallback((commentId: string, updater: (comment: any) => any) => {
    setComments((prev) => {
      const next = prev.map((item) => String(item.id) === commentId ? normalizeCommentRow(updater(item)) : item);
      cachePostCommentsForDetail(postId, next);
      return next;
    });
  }, [postId]);

  const closeCommentSheet = useCallback(() => {
    setCommentSheetVisible(false);
    setReplyingTo(null);
  }, []);

  const handleComment = async () => {
    if (!newComment.trim() || isCommenting) return;
    if (!user) {
      router.push('/(auth)/login' as any);
      return;
    }
    setIsCommenting(true);
    try {
      const res = await api.post(`/posts/${postId}/comments`, {
        client_request_id: `comment_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`,
        content: newComment.trim(),
        parent_id: replyingTo?.id || undefined,
      });
      setComments((prev) => {
        const next = insertCommentInThread(prev, res.data);
        cachePostCommentsForDetail(postId, next);
        return next;
      });
      setCommentsLoaded(true);
      setPost((prev: any) => prev ? { ...prev, comments_count: Number(prev.comments_count || 0) + 1 } : prev);
      setNewComment('');
      closeCommentSheet();
    } catch { } finally { setIsCommenting(false); }
  };

  const openCommentSheet = (replyTarget?: any) => {
    if (!user) {
      router.push('/(auth)/login' as any);
      return;
    }
    setReplyingTo(replyTarget ? normalizeCommentRow(replyTarget) : null);
    setCommentSheetVisible(true);
    if (!commentsLoaded && !commentsLoading) void loadComments();
  };

  const appendCommentToken = (token: string) => {
    setNewComment((prev) => `${prev}${token}`);
    setTimeout(() => commentSheetInputRef.current?.focus(), 30);
  };

  const handleCommentLike = async (comment: any) => {
    if (!user) {
      router.push('/(auth)/login' as any);
      return;
    }
    const commentId = String(comment?.id || '');
    if (!commentId || pendingCommentLikes.has(commentId)) return;
    const wasLiked = !!comment.liked_by_me;
    const previousCount = Number(comment.likes_count || 0);
    const nextLiked = !wasLiked;
    const nextCount = Math.max(0, previousCount + (nextLiked ? 1 : -1));
    setPendingCommentLikes((prev) => new Set(prev).add(commentId));
    updateCommentById(commentId, (item) => ({ ...item, liked_by_me: nextLiked, likes_count: nextCount }));
    try {
      const response = await api.post(`/comments/${commentId}/like`, { liked: nextLiked });
      updateCommentById(commentId, (item) => ({
        ...item,
        liked_by_me: typeof response.data?.liked === 'boolean' ? !!response.data.liked : nextLiked,
        likes_count: Number.isFinite(Number(response.data?.likes_count)) ? Number(response.data.likes_count) : nextCount,
      }));
    } catch {
      updateCommentById(commentId, (item) => ({ ...item, liked_by_me: wasLiked, likes_count: previousCount }));
    } finally {
      setPendingCommentLikes((prev) => {
        const next = new Set(prev);
        next.delete(commentId);
        return next;
      });
    }
  };

  const submitCommentReport = async (comment: any) => {
    const commentId = String(comment?.id || '');
    if (!commentId || reportingCommentId) return;
    setReportingCommentId(commentId);
    try {
      await api.post('/reports', {
        reported_type: 'comment',
        reported_id: commentId,
        content_id: postId,
        reason: 'Comment reported from World Board details',
        details: JSON.stringify({
          post_id: postId,
          comment_id: commentId,
          comment_user_id: comment?.user_id || '',
          excerpt: String(comment?.content || '').slice(0, 240),
        }),
      });
      Alert.alert('Report sent', 'Thanks. Our moderation team will review this comment.');
    } catch {
      Alert.alert('Report failed', 'Could not report this comment right now.');
    } finally {
      setReportingCommentId(null);
    }
  };

  const handleCommentLongPress = (comment: any) => {
    if (!user) {
      router.push('/(auth)/login' as any);
      return;
    }
    Alert.alert(
      'Report comment?',
      'Send this comment to moderation for review.',
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Report', style: 'destructive', onPress: () => void submitCommentReport(comment) },
      ],
    );
  };

  const handleShare = async () => {
    try { await Share.share({ message: post?.content || 'Check this out!' }); } catch { }
  };

  const openGiftSheet = () => {
    if (!user) {
      router.push('/(auth)/login' as any);
      return;
    }
    if (!post?.user_id || post.user_id === user?.id) {
      Alert.alert('Gift', "You can't send a gift to yourself.");
      return;
    }
    setSelectedGiftId('');
    setGiftSheetVisible(true);
    setGiftBalanceLoading(true);
    getWallet()
      .then((wallet) => setGiftBalance(Number(wallet.balance || 0)))
      .catch(() => setGiftBalance(null))
      .finally(() => setGiftBalanceLoading(false));
  };

  const handleSendGift = async () => {
    const gift = GIFT_PRESETS.find((item) => item.id === selectedGiftId);
    if (!post?.user_id || !gift || sendingGiftId) return;
    setSendingGiftId(gift.id);
    try {
      await sendCoinGift({
        to_user_id: String(post.user_id),
        coins: gift.coins,
        note: `${gift.label} from World Board`,
        post_id: String(post.id || postId || ''),
        gift_type: gift.id,
        client_request_id: `gift_${post.id || postId}_${gift.id}_${Date.now()}`,
      }).then((result: any) => {
        if (Number.isFinite(Number(result?.balance))) setGiftBalance(Number(result.balance));
      });
      setGiftSheetVisible(false);
      Alert.alert('Gift sent', `${gift.label} sent to ${post.user_username || post.user_full_name || 'this creator'}.`);
    } catch (error: any) {
      const code = error?.response?.data?.code;
      if (code === 'COINS_INSUFFICIENT') {
        Alert.alert(
          'Not enough coins',
          'Add coins to your wallet to send this gift.',
          [
            { text: 'Cancel', style: 'cancel' },
            { text: 'Wallet', onPress: () => router.push('/wallet' as any) },
          ],
        );
      } else {
        Alert.alert('Gift failed', error?.response?.data?.detail || 'Could not send this gift right now.');
      }
    } finally {
      setSendingGiftId(null);
    }
  };

  const handleFollow = async () => {
    if (!post?.user_id || post.user_id === user?.id || isFollowLoading) return;
    const userId = String(post.user_id);
    const wasFollowing = getLivePostState(post).following;
    const nextFollowing = !wasFollowing;
    setFollowing(nextFollowing);
    setUserFollowing(userId, nextFollowing);
    patchLocalPost({ is_following: nextFollowing, followed: nextFollowing, following: nextFollowing });
    setIsFollowLoading(true);
    try {
      const response = await api.post(`/users/${post.user_id}/follow`, { following: nextFollowing });
      if (typeof response.data?.following === 'boolean') {
        const serverFollowing = !!response.data.following;
        setFollowing(serverFollowing);
        setUserFollowing(userId, serverFollowing);
        patchLocalPost({ is_following: serverFollowing, followed: serverFollowing, following: serverFollowing });
      }
    } catch (error: any) {
      setFollowing(wasFollowing);
      setUserFollowing(userId, wasFollowing);
      patchLocalPost({ is_following: wasFollowing, followed: wasFollowing, following: wasFollowing });
      Alert.alert('Follow failed', error?.response?.data?.detail || 'Could not follow this creator.');
    } finally {
      setIsFollowLoading(false);
    }
  };

  const fmtCount = (n: number) => !n ? '' : n >= 1000 ? (n / 1000).toFixed(1).replace('.0', '') + 'k' : String(n);
  const scrollContentStyle = useMemo(() => ({ paddingBottom: insets.bottom + 118 }), [insets.bottom]);

  useEffect(() => {
    if (!post) return;
    const mediaItems = parsePostMediaUris(post.images);
    const allMediaItems = mediaItems.length > 0
      ? mediaItems
      : typeof post.image === 'string' && post.image ? [post.image] : [];
    const postImages: string[] = allMediaItems.filter((u: string, i: number) => !isPostVideoMedia(u, post.media_types, i) && (u.startsWith('http') || u.startsWith('data:')));
    if (postImages.length > 0) {
      void prefetchImageUrls(postImages.map((uri) => optimizeImageUrl(uri, 'detail')), 8);
    }
  }, [post?.id, post?.image, post?.images, post?.media_types]);

  // ── Loading / Not Found ──
  if (isLoading) return <View style={s.center}><ActivityIndicator size="large" color={colors.accentPrimary} /></View>;
  if (!post) return (
    <View style={s.center}>
      <Text style={{ color: colors.textSecondary, fontSize: 16, marginBottom: 16 }}>Post not found</Text>
      <TouchableOpacity onPress={() => router.back()} style={s.goBackBtn}>
        <Text style={{ color: '#FFF', fontWeight: '500' }}>Go Back</Text>
      </TouchableOpacity>
    </View>
  );

  // ── Derived values ──
  const authorName = post.user_full_name || post.user_username || 'User';
  const authorInitial = String(authorName).trim().slice(0, 1).toUpperCase() || 'F';
  const postMediaItems = parsePostMediaUris(post.images);
  const allMedia = postMediaItems.length > 0
    ? postMediaItems
    : typeof post.image === 'string' && post.image
      ? [post.image]
      : [];
  const allImages: string[] = allMedia.filter((u: string, i: number) => !isPostVideoMedia(u, post.media_types, i) && (u.startsWith('http') || u.startsWith('data:')));
  const videoUri = allMedia.find((u: string, i: number) => isPostVideoMedia(u, post.media_types, i)) || '';
  const hasVideo = !!videoUri;
  const placeName = String(post.place_name || '').trim();
  const placeAddress = String(post.location || '').trim();
  const hasPlace = !!(placeName || placeAddress);
  const showPlaceAddress = !!(placeAddress && placeAddress.toLowerCase() !== placeName.toLowerCase());
  const caption = String(post.content || '').trim();
  const headline = String(post.title || post.headline || '').trim();
  const fallbackCaptionParts = headline ? { headline: '', body: caption } : splitCaptionFallback(caption);
  const detailTitle = headline || fallbackCaptionParts.headline;
  const detailBody = headline ? caption : fallbackCaptionParts.body;
  const detailTextLength = detailTitle.length + detailBody.length;
  const detailHeadlineSize = detailTitle.length > 42
    ? 21
    : detailTitle.length > 28
      ? 22
      : DETAIL_HEADLINE_FONT_SIZE;
  const detailHeadlineLineHeight = Math.round(detailHeadlineSize * 1.2);
  const mediaW = SW;
  const mediaH = Math.round(mediaW * DETAIL_MEDIA_HEIGHT_RATIO);
  const { filterData, textOverlays } = parseCreatorEditorOverlays(post.editor_overlays);
  const commentCount = Math.max(comments.length, Number(post.comments_count || 0));
  const commentLabel = commentCount === 1 ? '1 comment' : `${commentCount} comments`;
  const timeAgo = post.created_at ? formatDistanceToNow(new Date(post.created_at), { addSuffix: true }) : '';
  const canFollow = !!post.user_id && post.user_id !== user?.id;
  const selectedGift = GIFT_PRESETS.find((gift) => gift.id === selectedGiftId) || null;

  const renderCreatorFilter = (mediaIndex: number) => filterData && (filterData.mediaIndex || 0) === mediaIndex ? (
    <View pointerEvents="none" style={StyleSheet.absoluteFill}>
      <View style={[s.viewerFilterTint, { backgroundColor: filterData.tint, opacity: filterData.tintOpacity }]} />
      {filterData.fadeOpacity ? <View style={[s.viewerFilterFade, { opacity: filterData.fadeOpacity }]} /> : null}
      {filterData.vignetteOpacity ? <View style={[s.viewerFilterVignette, { opacity: filterData.vignetteOpacity }]} /> : null}
      {filterData.grainOpacity ? <View style={[s.viewerFilterGrain, { opacity: filterData.grainOpacity }]} /> : null}
    </View>
  ) : null;
  const renderTextOverlay = (overlay: CreatorTextOverlay, mediaIndex: number) => {
    if ((overlay.mediaIndex || 0) !== mediaIndex) return null;
    const overlayWidth = mediaW * overlay.width;
    const left = Math.max(8, Math.min(mediaW - overlayWidth - 8, overlay.x * mediaW - overlayWidth / 2));
    const top = Math.max(8, Math.min(mediaH - 78, overlay.y * mediaH - overlay.fontSize));
    return (
      <View
        key={overlay.id}
        pointerEvents="none"
        style={[
          s.viewerTextOverlay,
          {
            left,
            top,
            width: overlayWidth,
            opacity: overlay.opacity,
            backgroundColor: overlay.background,
            borderColor: overlay.borderColor || 'transparent',
            borderRadius: overlay.radius,
            paddingHorizontal: overlay.paddingX,
            paddingVertical: overlay.paddingY,
          },
        ]}
      >
        <Text style={[
          s.viewerTextOverlayText,
          {
            color: overlay.color,
            fontSize: overlay.fontSize,
            lineHeight: overlay.fontSize + 5,
            fontWeight: overlay.fontWeight,
            textShadowColor: overlay.shadow ? 'rgba(0,0,0,0.42)' : 'transparent',
            textShadowRadius: overlay.shadow ? 8 : 0,
            textShadowOffset: overlay.shadow ? { width: 0, height: 2 } : { width: 0, height: 0 },
          },
        ]}>{overlay.text}</Text>
      </View>
    );
  };
  const renderEditorLayer = (mediaIndex: number) => (
    // Saved creator editor JSON is rendered here over the responsive media frame.
    <View pointerEvents="box-none" style={StyleSheet.absoluteFill}>
      {renderCreatorFilter(mediaIndex)}
      {textOverlays.map((overlay) => renderTextOverlay(overlay, mediaIndex))}
    </View>
  );

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <View style={[s.detailHeader, { minHeight: insets.top + 58, paddingTop: insets.top }]}>
        <TouchableOpacity style={s.headerIconBtn} onPress={() => router.back()} activeOpacity={0.82}>
          <Ionicons name="chevron-back" size={32} color={UI_BLACK} />
        </TouchableOpacity>
        <TouchableOpacity style={s.headerCreator} onPress={() => router.push(`/user/${post.user_id}` as any)} activeOpacity={0.86}>
          <View style={s.headerAvatarWrap}>
            {post.user_profile_image ? (
              <OptimizedImage uri={post.user_profile_image} preset="avatar" style={s.headerAvatar} />
            ) : (
              <View style={[s.headerAvatar, s.authorAvatarFb]}>
                <Text style={s.headerInitial}>{authorInitial}</Text>
              </View>
            )}
            {canFollow ? (
              <TouchableOpacity
                style={[s.headerFollowPlus, following && s.headerFollowPlusOn]}
                onPress={(event: any) => {
                  event?.stopPropagation?.();
                  handleFollow();
                }}
                activeOpacity={0.86}
                disabled={isFollowLoading}
              >
                {isFollowLoading ? (
                  <ActivityIndicator size="small" color={UI_WHITE} />
                ) : (
                  <Ionicons name={following ? 'checkmark' : 'add'} size={12} color={UI_WHITE} />
                )}
              </TouchableOpacity>
            ) : null}
          </View>
          <Text style={s.headerName} numberOfLines={1}>{post.user_username || authorName}</Text>
        </TouchableOpacity>
        <View style={s.headerActionGroup}>
          {canFollow ? (
            <TouchableOpacity style={s.headerGiftBtn} onPress={openGiftSheet} activeOpacity={0.84}>
              <Ionicons name="gift-outline" size={21} color={UI_BLACK} />
            </TouchableOpacity>
          ) : null}
          <TouchableOpacity style={s.headerIconBtn} onPress={handleShare} activeOpacity={0.82}>
            <Ionicons name="arrow-redo-outline" size={28} color={UI_BLACK} />
          </TouchableOpacity>
        </View>
      </View>
      <ScrollView
        style={s.detailScroll}
        showsVerticalScrollIndicator={false}
        contentContainerStyle={scrollContentStyle}
        directionalLockEnabled
        bounces={false}
        alwaysBounceVertical={false}
        overScrollMode="never"
        keyboardShouldPersistTaps="handled"
      >
        {/* ═══ IMAGE / VIDEO CARD ═══ */}
        <View style={s.imageCard}>
          {allImages.length > 0 ? (
            allImages.length > 1 ? (
              <ScrollView
                horizontal
                pagingEnabled
                directionalLockEnabled
                nestedScrollEnabled
                decelerationRate="fast"
                disableIntervalMomentum
                showsHorizontalScrollIndicator={false}
                onMomentumScrollEnd={(e) => setActiveImgIdx(Math.round(e.nativeEvent.contentOffset.x / mediaW))}
                scrollEventThrottle={16}
              >
                {allImages.map((uri: string, i: number) => (
                  <View key={`img-${i}`} style={{ width: mediaW, height: mediaH }}>
                    <OptimizedImage uri={uri} preset="detail" style={{ width: mediaW, height: mediaH }} resizeMode="cover" priority={i === activeImgIdx ? 'high' : 'normal'} />
                    {renderEditorLayer(i)}
                  </View>
                ))}
              </ScrollView>
            ) : (
              <View style={{ width: mediaW, height: mediaH }}>
                <OptimizedImage uri={allImages[0]} preset="detail" style={{ width: mediaW, height: mediaH }} resizeMode="cover" priority="high" />
                {renderEditorLayer(0)}
              </View>
            )
          ) : hasVideo ? (
            videoHlsUrl ? (
              <VideoPlayer hlsUrl={videoHlsUrl} posterUri={videoUri} width={mediaW} height={mediaH} />
            ) : (
              <View style={[s.videoShell, { width: mediaW, height: mediaH }]}>
                <MediaPreview
                  uri={videoUri}
                  mediaTypes={post.media_types}
                  style={{ width: mediaW, height: mediaH }}
                  resizeMode="cover"
                  showVideoBadge={false}
                  imagePreset="detail"
                  priority="high"
                />
                <View style={s.videoLoadingScrim} pointerEvents="none">
                  <ActivityIndicator color="#FFFFFF" />
                </View>
              </View>
            )
          ) : (
            <View style={[{ width: mediaW, height: mediaH }, s.noImgBg]}>
              <Ionicons name="image-outline" size={56} color="#D4D0C8" />
              <Text style={s.noImgText}>World Board post</Text>
            </View>
          )}

        </View>

        {allImages.length > 1 ? (
          <View style={s.pageDots}>
            {allImages.map((_: string, i: number) => (
              <View key={i} style={[s.dot, activeImgIdx === i && s.dotActive]} />
            ))}
          </View>
        ) : null}

        {/* ═══ LOCATION ═══ */}
        <View style={s.contentSheet}>
        {/* ═══ TAGS ═══ */}
          <TouchableOpacity activeOpacity={0.9} onPress={() => setCaptionExpanded(!captionExpanded)} style={s.captionBlock}>
            {detailTitle ? (
              <Text
                style={[s.headlineText, { fontSize: detailHeadlineSize, lineHeight: detailHeadlineLineHeight }]}
                numberOfLines={captionExpanded ? undefined : 2}
                allowFontScaling={false}
              >
                {detailTitle}
              </Text>
            ) : null}
            {detailBody ? (
              <Text style={s.captionText} numberOfLines={captionExpanded ? undefined : 3} allowFontScaling={false}>{detailBody}</Text>
            ) : null}
            {detailTextLength > 140 ? (
              <View style={s.expandRow}>
                <Text style={s.expandText}>{captionExpanded ? 'Show less' : 'Read more'}</Text>
                <Ionicons name={captionExpanded ? 'chevron-up' : 'chevron-down'} size={16} color="#6D6258" />
              </View>
            ) : null}
          </TouchableOpacity>

          {hasPlace ? (
            <View style={s.locationRow}>
              <Ionicons name="location-outline" size={15} color="#385235" />
              <View style={s.locationCopy}>
                <Text style={s.locationText} numberOfLines={1}>{placeName || placeAddress}</Text>
                {showPlaceAddress ? <Text style={s.locationSubText} numberOfLines={1}>{placeAddress}</Text> : null}
              </View>
            </View>
          ) : null}

          {timeAgo ? <Text style={s.postMetaText} allowFontScaling={false}>{timeAgo}</Text> : null}

          {commentsLoading || comments.length > 0 || commentCount > 0 ? (
            <View style={s.commentsList}>
              <Text style={s.commentsHeader}>{commentLabel}</Text>
              {commentsLoading || (commentCount > 0 && !commentsLoaded) ? (
                <View style={s.commentsLoadingRow}>
                  <ActivityIndicator color={UI_BLACK} />
                </View>
              ) : comments.length > 0 ? (
                comments.map((rawComment) => {
                  const c = normalizeCommentRow(rawComment);
                  const isReply = !!c.parent_id;
                  const commentName = getCommentName(c);
                  const likePending = pendingCommentLikes.has(c.id);
                  return (
                    <TouchableOpacity
                      key={c.id}
                      style={[s.commentItem, isReply && s.commentReplyItem]}
                      activeOpacity={0.88}
                      delayLongPress={420}
                      onLongPress={() => handleCommentLongPress(c)}
                    >
                      {c.user_profile_image ? (
                        <OptimizedImage uri={c.user_profile_image} preset="avatar" style={[s.commentAvatar, isReply && s.commentReplyAvatar]} />
                      ) : (
                        <View style={[s.commentAvatar, s.commentAvatarFb, isReply && s.commentReplyAvatar]}>
                          <Text style={s.commentAvatarText}>{commentName[0]?.toUpperCase() || 'U'}</Text>
                        </View>
                      )}
                      <View style={s.commentBody}>
                        <Text style={s.commentAuthor}>{commentName}</Text>
                        <Text style={s.commentContent}>{c.content}</Text>
                        <View style={s.commentActionRow}>
                          <Text style={s.commentTime}>{formatDistanceToNow(new Date(c.created_at), { addSuffix: true })}</Text>
                          <TouchableOpacity onPress={() => openCommentSheet(c)} activeOpacity={0.82}>
                            <Text style={s.commentActionText}>Reply</Text>
                          </TouchableOpacity>
                        </View>
                      </View>
                      <TouchableOpacity
                        style={s.commentLikeButton}
                        onPress={() => handleCommentLike(c)}
                        disabled={likePending}
                        activeOpacity={0.82}
                      >
                        <Ionicons name={c.liked_by_me ? 'heart' : 'heart-outline'} size={19} color={c.liked_by_me ? UI_ERROR : '#1A1A1A'} />
                        {c.likes_count > 0 ? <Text style={s.commentLikeCount}>{fmtCount(c.likes_count)}</Text> : null}
                      </TouchableOpacity>
                    </TouchableOpacity>
                  );
                })
              ) : null}
            </View>
          ) : null}
        </View>
      </ScrollView>

      {/* ═══ COMMENT / ACTION BAR ═══ */}
      <View style={[s.bottomBar, { paddingBottom: Math.max(insets.bottom, 10) }]}>
        <TouchableOpacity style={s.bottomCommentBox} onPress={() => openCommentSheet()} activeOpacity={0.88}>
          <Text style={s.commentInputPlaceholder}>Add comment...</Text>
        </TouchableOpacity>

        <TouchableOpacity style={s.bottomMetric} onPress={handleLike} activeOpacity={0.84}>
          <Ionicons name={liked ? 'heart' : 'heart-outline'} size={25} color={liked ? UI_ERROR : UI_BLACK} />
          <Text style={s.bottomMetricText}>{fmtCount(likesCount) || '0'}</Text>
        </TouchableOpacity>
        <TouchableOpacity style={s.bottomMetric} onPress={handleSave} activeOpacity={0.84}>
          <Ionicons name={saved ? 'bookmark' : 'bookmark-outline'} size={24} color={saved ? UI_LIME : UI_BLACK} />
          <Text style={s.bottomMetricText}>{fmtCount(savedCount) || '0'}</Text>
        </TouchableOpacity>
      </View>

      <SaveToCollectionModal
        visible={collectionModalVisible}
        saved={saved}
        saving={collectionSaving}
        onClose={() => {
          if (!collectionSaving) setCollectionModalVisible(false);
        }}
        onSave={saveToCollection}
        onUnsave={removeFromCollection}
      />


      <Modal visible={giftSheetVisible} transparent animationType="slide" onRequestClose={() => setGiftSheetVisible(false)}>
        <View style={s.giftSheetBackdrop}>
          <TouchableOpacity style={s.giftSheetDismiss} activeOpacity={1} onPress={() => setGiftSheetVisible(false)} />
          <View style={[s.giftSheet, { paddingBottom: Math.max(insets.bottom + 14, 22) }]}>
            <View style={s.giftSheetHandle} />
            <View style={s.giftSheetHeader}>
              <View style={{ flex: 1, minWidth: 0 }}>
                <Text style={s.giftSheetTitle}>Send gift</Text>
                <Text style={s.giftSheetSubtitle} numberOfLines={1}>Support {authorName}</Text>
              </View>
              <TouchableOpacity style={s.giftSheetClose} onPress={() => setGiftSheetVisible(false)} activeOpacity={0.84}>
                <Ionicons name="close" size={22} color={UI_BLACK} />
              </TouchableOpacity>
            </View>
            <ScrollView style={s.giftScroll} contentContainerStyle={s.giftGrid} showsVerticalScrollIndicator={false}>
              {GIFT_PRESETS.map((gift) => {
                const selected = selectedGiftId === gift.id;
                return (
                  <TouchableOpacity
                    key={gift.id}
                    style={[s.giftCard, selected && s.giftCardSelected]}
                    onPress={() => setSelectedGiftId(gift.id)}
                    activeOpacity={0.86}
                    disabled={!!sendingGiftId}
                  >
                    <View style={[s.giftIconCircle, { backgroundColor: gift.tone }]}>
                      <View style={s.giftIconHighlight} />
                      <Text style={s.giftVisual}>{gift.visual}</Text>
                    </View>
                    <Text style={s.giftLabel} numberOfLines={2}>{gift.label}</Text>
                    <Text style={s.giftCoins}>{formatGiftCoins(gift.coins)} Coins</Text>
                  </TouchableOpacity>
                );
              })}
            </ScrollView>
            <View style={s.giftFooter}>
              <TouchableOpacity style={s.giftRecharge} onPress={() => router.push('/wallet' as any)} activeOpacity={0.84}>
                <Text style={s.giftRechargeText}>Recharge</Text>
                <View style={s.giftCoinBadge}>
                  <Ionicons name="flame" size={15} color="#D79B00" />
                </View>
                <Text style={s.giftBalanceText}>{giftBalanceLoading ? '...' : formatGiftCoins(giftBalance || 0)}</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[s.giftSendButton, (!selectedGift || !!sendingGiftId) && s.giftSendButtonDisabled]}
                onPress={handleSendGift}
                disabled={!selectedGift || !!sendingGiftId}
                activeOpacity={0.86}
              >
                {sendingGiftId ? (
                  <ActivityIndicator color={UI_BLACK} />
                ) : (
                  <Text style={[s.giftSendText, !selectedGift && s.giftSendTextDisabled]}>Send</Text>
                )}
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>

      <Modal visible={commentSheetVisible} transparent animationType="fade" onRequestClose={closeCommentSheet}>
        <KeyboardAvoidingView style={s.commentComposerBackdrop} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
          <TouchableOpacity style={s.commentComposerDismiss} activeOpacity={1} onPress={closeCommentSheet} />
          <View style={[s.commentComposerSheet, { paddingBottom: Math.max(insets.bottom + 12, 16) }]}>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.composerEmojiRow} keyboardShouldPersistTaps="handled">
              {COMMENT_REACTIONS.map((emoji) => (
                <TouchableOpacity key={emoji} onPress={() => appendCommentToken(emoji)} activeOpacity={0.82}>
                  <Text style={s.composerEmoji}>{emoji}</Text>
                </TouchableOpacity>
              ))}
            </ScrollView>
            {replyingTo ? (
              <View style={s.replyTargetBar}>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Text style={s.replyTargetLabel}>Replying to {getCommentName(replyingTo)}</Text>
                  <Text style={s.replyTargetText} numberOfLines={1}>{replyingTo.content}</Text>
                </View>
                <TouchableOpacity style={s.replyTargetClose} onPress={() => setReplyingTo(null)} activeOpacity={0.82}>
                  <Ionicons name="close" size={18} color="#5F5F5F" />
                </TouchableOpacity>
              </View>
            ) : null}
            <View style={s.commentComposerInputRow}>
              {user?.profile_image ? (
                <OptimizedImage uri={user.profile_image} preset="avatar" style={s.composerAvatar} />
              ) : (
                <View style={[s.composerAvatar, s.composerAvatarFallback]}>
                  <Text style={s.composerAvatarText}>{String(user?.full_name || user?.username || 'U').slice(0, 1).toUpperCase()}</Text>
                </View>
              )}
              <View style={s.composerInputBox}>
                <TextInput
                  ref={commentSheetInputRef}
                  style={s.composerInput}
                  value={newComment}
                  onChangeText={setNewComment}
                  placeholder={replyingTo ? `Reply to ${getCommentName(replyingTo)}...` : 'Add comment...'}
                  placeholderTextColor="#9A9A9A"
                  selectionColor="#E85E8B"
                  multiline
                  returnKeyType="send"
                  onSubmitEditing={handleComment}
                />
              </View>
            </View>
            <View style={s.composerToolbar}>
              <TouchableOpacity style={s.composerToolIcon} activeOpacity={0.82}>
                <Ionicons name="image-outline" size={31} color={UI_BLACK} />
              </TouchableOpacity>
              <TouchableOpacity style={s.composerToolIcon} onPress={() => appendCommentToken('😊')} activeOpacity={0.82}>
                <Ionicons name="happy-outline" size={32} color={UI_BLACK} />
              </TouchableOpacity>
              <TouchableOpacity style={s.composerToolIcon} onPress={() => appendCommentToken('@')} activeOpacity={0.82}>
                <Text style={s.composerAtText}>@</Text>
              </TouchableOpacity>
              <View style={{ flex: 1 }} />
              <TouchableOpacity
                style={[s.composerSendBtn, !newComment.trim() && s.composerSendBtnDisabled]}
                onPress={handleComment}
                disabled={!newComment.trim() || isCommenting}
                activeOpacity={0.86}
              >
                {isCommenting ? <ActivityIndicator size="small" color={UI_WHITE} /> : <Ionicons name="arrow-up" size={24} color={newComment.trim() ? UI_WHITE : '#A8A8A8'} />}
              </TouchableOpacity>
            </View>
          </View>
        </KeyboardAvoidingView>
      </Modal>

    </KeyboardAvoidingView>
  );
});

/* ════════════════════════════════════════════════════════════════════════
   VIDEO PLAYER
   ════════════════════════════════════════════════════════════════════════ */
function VideoPlayer({ hlsUrl, posterUri, width, height }: { hlsUrl: string; posterUri?: string; width: number; height: number }) {
  const [firstFrameReady, setFirstFrameReady] = useState(false);
  const player = useVideoPlayer(hlsUrl, (p) => {
    p.loop = true;
    p.muted = false;
    p.volume = 1;
    p.audioMixingMode = 'auto';
    p.allowsExternalPlayback = false;
    p.showNowPlayingNotification = false;
    p.play();
  });

  useEffect(() => {
    setFirstFrameReady(false);
    player.play();
  }, [hlsUrl, player]);

  const togglePlayback = useCallback(() => {
    if (player.playing) {
      player.pause();
    } else {
      player.play();
    }
  }, [player]);

  return (
    <View style={[s.videoShell, { width, height }]}>
      <VideoView
        player={player}
        style={{ width, height }}
        contentFit="cover"
        nativeControls={false}
        allowsFullscreen={false}
        fullscreenOptions={{ enable: false }}
        allowsPictureInPicture={false}
        showsTimecodes={false}
        playsInline
        useExoShutter={false}
        onFirstFrameRender={() => setFirstFrameReady(true)}
      />
      <TouchableOpacity
        style={s.videoTapLayer}
        activeOpacity={1}
        onPress={togglePlayback}
      />
      {!firstFrameReady ? (
        <View style={s.videoLoadingCover} pointerEvents="none">
          {posterUri ? (
            <MediaPreview
              uri={posterUri}
              style={StyleSheet.absoluteFill}
              resizeMode="cover"
              showVideoBadge={false}
              imagePreset="detail"
              priority="high"
            />
          ) : null}
          <View style={s.videoLoadingScrim}>
            <ActivityIndicator color="#FFFFFF" />
          </View>
        </View>
      ) : null}
    </View>
  );
}

/* ════════════════════════════════════════════════════════════════════════
   STYLES
   ════════════════════════════════════════════════════════════════════════ */
const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.bgApp },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: colors.bgApp },
  goBackBtn: { backgroundColor: UI_BLACK, paddingHorizontal: 24, paddingVertical: 12, borderRadius: 24 },

  brandRow: {
    minHeight: 44,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.bgApp,
  },
  brandPill: {
    minWidth: 54,
    minHeight: 24,
    borderRadius: 12,
    backgroundColor: UI_LIME,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 9,
    transform: [{ rotate: '-3deg' }],
  },
  brandText: { color: UI_WHITE, fontSize: 13, lineHeight: 16, fontWeight: '500', fontStyle: 'italic' },
  detailHeader: {
    minHeight: 58,
    paddingHorizontal: 16,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 9,
    backgroundColor: colors.bgApp,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: UI_BORDER,
    zIndex: 30,
  },
  detailScroll: { flex: 1, backgroundColor: colors.bgApp },
  headerIconBtn: { width: 34, height: 42, borderRadius: 17, alignItems: 'center', justifyContent: 'center' },
  headerActionGroup: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  headerGiftBtn: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#FFF64A',
    borderWidth: 1,
    borderColor: '#EFE646',
    alignItems: 'center',
    justifyContent: 'center',
  },
  headerCreator: { flex: 1, minWidth: 0, flexDirection: 'row', alignItems: 'center', gap: 9 },
  headerAvatarWrap: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center', position: 'relative' },
  headerAvatar: { width: 40, height: 40, borderRadius: 20 },
  headerFollowPlus: {
    position: 'absolute',
    right: 0,
    bottom: 1,
    width: 20,
    height: 20,
    borderRadius: 10,
    backgroundColor: UI_LIME,
    borderWidth: 1.4,
    borderColor: UI_WHITE,
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 2,
  },
  headerFollowPlusOn: { backgroundColor: UI_LIME, borderColor: UI_WHITE },
  headerInitial: { color: UI_BLACK, fontSize: 16, fontWeight: '500' },
  headerName: { flex: 1, minWidth: 0, color: UI_BLACK, fontSize: 19, lineHeight: 24, fontWeight: '500' },

  imageCard: {
    overflow: 'hidden',
    backgroundColor: UI_SURFACE,
    position: 'relative',
  },
  noImgBg: { backgroundColor: UI_SURFACE, justifyContent: 'center', alignItems: 'center', gap: 10 },
  noImgText: { color: UI_MUTED, fontSize: 14, fontWeight: '600' },
  videoShell: { overflow: 'hidden', backgroundColor: '#111111', position: 'relative' },
  videoTapLayer: { position: 'absolute', top: 0, bottom: 0, left: 0, right: 0, backgroundColor: 'transparent' },
  videoLoadingCover: { ...StyleSheet.absoluteFillObject, backgroundColor: '#111111' },
  videoLoadingScrim: { ...StyleSheet.absoluteFillObject, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(0,0,0,0.16)' },
  viewerFilterTint: { ...StyleSheet.absoluteFillObject },
  viewerFilterFade: { ...StyleSheet.absoluteFillObject, backgroundColor: '#F7F1E8' },
  viewerFilterVignette: { ...StyleSheet.absoluteFillObject, borderWidth: 34, borderColor: 'rgba(0,0,0,0.72)' },
  viewerFilterGrain: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(255,255,255,0.34)' },
  viewerTextOverlay: { position: 'absolute', zIndex: 8, alignItems: 'center', borderWidth: 1 },
  viewerTextOverlayText: { textAlign: 'center' },
  detailChrome: {
    position: 'absolute',
    top: 12,
    left: 12,
    right: 12,
    zIndex: 12,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  chromeActions: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  floatingBtn: {
    width: 42, height: 42, borderRadius: 21,
    backgroundColor: 'rgba(255,255,255,0.92)', justifyContent: 'center', alignItems: 'center',
    shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.10, shadowRadius: 8,
    elevation: 3,
  },
  pageDots: { minHeight: 28, flexDirection: 'row', justifyContent: 'center', alignItems: 'center', gap: 5 },
  dots: { position: 'absolute', bottom: 16, left: 0, right: 0, flexDirection: 'row', justifyContent: 'center', gap: 6 },
  dot: { width: 7, height: 7, borderRadius: 4, backgroundColor: '#D5D5D5' },
  dotActive: { backgroundColor: UI_BLACK, width: 7, borderRadius: 4 },

  contentSheet: { paddingTop: 4, paddingHorizontal: 16, gap: 8 },
  authorRow: { flexDirection: 'row', alignItems: 'center', minHeight: 48 },
  authorAvatar: { width: 44, height: 44, borderRadius: 22, marginRight: 10 },
  authorAvatarFb: { backgroundColor: UI_SURFACE, justifyContent: 'center', alignItems: 'center' },
  authorInit: { color: UI_BLACK, fontSize: 16, fontWeight: '500' },
  authorMeta: { flex: 1, minWidth: 0 },
  authorName: { fontSize: 16, lineHeight: 20, fontWeight: '500', color: UI_BLACK },
  authorSub: { fontSize: 12, lineHeight: 16, fontWeight: '500', color: '#81766C', marginTop: 1 },
  followBtn: {
    minWidth: 86,
    minHeight: 36,
    borderRadius: 18,
    backgroundColor: '#111111',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 14,
  },
  followBtnOn: { backgroundColor: colors.bgSubtle, borderWidth: 1, borderColor: colors.borderSubtle },
  followText: { color: colors.textInverse, fontSize: 13, fontWeight: '500' },
  followTextOn: { color: colors.textPrimary },

  postMetaText: { color: colors.textHint, fontSize: 13, lineHeight: 18, fontWeight: '500' },
  locationRow: {
    alignSelf: 'flex-start',
    flexDirection: 'row',
    alignItems: 'center',
    maxWidth: '100%',
    gap: 6,
    backgroundColor: colors.accentPrimaryLight,
    borderRadius: 16,
    paddingHorizontal: 11,
    paddingVertical: 7,
  },
  locationCopy: { flexShrink: 1, minWidth: 0 },
  locationText: { fontSize: 13, lineHeight: 17, fontWeight: '600', color: '#385235', flexShrink: 1 },
  locationSubText: { marginTop: 1, fontSize: 11, lineHeight: 14, fontWeight: '500', color: '#7A8573', flexShrink: 1 },
  captionBlock: { gap: 6 },
  headlineText: {
    fontSize: DETAIL_HEADLINE_FONT_SIZE,
    lineHeight: Math.round(DETAIL_HEADLINE_FONT_SIZE * 1.2),
    fontWeight: '800',
    color: UI_BLACK,
  },
  captionText: {
    fontSize: DETAIL_CAPTION_FONT_SIZE,
    lineHeight: Math.round(DETAIL_CAPTION_FONT_SIZE * 1.55),
    fontWeight: '400',
    color: UI_BLACK,
  },
  emptyCaptionText: {
    fontSize: DETAIL_EMPTY_CAPTION_FONT_SIZE,
    lineHeight: Math.round(DETAIL_EMPTY_CAPTION_FONT_SIZE * 1.45),
    fontWeight: '400',
    color: '#8D837A',
  },
  expandRow: { alignSelf: 'flex-start', flexDirection: 'row', alignItems: 'center', gap: 2, paddingTop: 2 },
  expandText: { fontSize: 13, fontWeight: '500', color: '#6D6258' },
  inlineCommentCount: { color: '#111111', fontSize: 20, lineHeight: 28, fontWeight: '500', paddingTop: 14 },

  tagsRow: { gap: 6, paddingRight: 16 },
  tagPill: { backgroundColor: colors.bgSubtle, paddingHorizontal: 9, paddingVertical: 5, borderRadius: 11 },
  tagText: { fontSize: 11, lineHeight: 14, fontWeight: '600', color: colors.textSecondary },
  thoughtBox: {
    minHeight: 56,
    borderRadius: 14,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    gap: 10,
  },
  thoughtInput: { flex: 1, minWidth: 0, fontSize: 20, color: UI_BLACK, paddingVertical: 12, fontWeight: '400' },
  thoughtSendBtn: { width: 32, height: 32, borderRadius: 16, backgroundColor: UI_LIME, borderWidth: 1, borderColor: colors.accentPrimaryHover, alignItems: 'center', justifyContent: 'center' },
  reactionRow: { flexDirection: 'row', alignItems: 'center', gap: 7 },
  reaction: { fontSize: 14 },
  postActionRow: {
    minHeight: 48,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  },
  postActionRight: { flexDirection: 'row', alignItems: 'center', gap: 22 },
  iconStat: { flexDirection: 'row', alignItems: 'center', gap: 7 },
  iconStatText: { color: '#111111', fontSize: 20, fontWeight: '500' },
  iconOnly: { width: 30, height: 30, alignItems: 'center', justifyContent: 'center' },
  actionStrip: { flexDirection: 'row', alignItems: 'center', gap: 8, flexWrap: 'wrap', paddingTop: 2 },
  actionPill: {
    minHeight: 40,
    borderRadius: 20,
    backgroundColor: colors.bgSubtle,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    paddingHorizontal: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  actionPillOn: { backgroundColor: colors.accentPrimaryLight, borderColor: colors.borderMedium },
  actionPillText: { color: colors.textPrimary, fontSize: 13, fontWeight: '500' },
  actionCircle: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: colors.bgSubtle,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    alignItems: 'center',
    justifyContent: 'center',
  },

  commentsPanel: {
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    borderRadius: 22,
    padding: 14,
    gap: 12,
  },
  commentsList: { paddingTop: 12, gap: 2 },
  commentsLoadingRow: { minHeight: 48, alignItems: 'center', justifyContent: 'center' },
  commentsHeader: { fontSize: 19, lineHeight: 25, fontWeight: '500', color: '#111111', marginBottom: 12 },
  commentsHeaderRow: { flexDirection: 'row', alignItems: 'baseline', justifyContent: 'space-between', gap: 12 },
  commentsTitle: { fontSize: 17, lineHeight: 22, fontWeight: '500', color: '#111111' },
  commentsCount: { fontSize: 12, lineHeight: 16, fontWeight: '600', color: '#8A8178' },
  commentItem: { flexDirection: 'row', alignItems: 'flex-start', marginBottom: 12, paddingVertical: 2 },
  commentReplyItem: { marginLeft: 36 },
  commentAvatar: { width: 34, height: 34, borderRadius: 17, marginRight: 9, marginTop: 1 },
  commentReplyAvatar: { width: 28, height: 28, borderRadius: 14, marginRight: 8 },
  commentAvatarFb: { backgroundColor: '#EEE8DF', justifyContent: 'center', alignItems: 'center' },
  commentAvatarText: { fontSize: 12, fontWeight: '700', color: '#8D837A' },
  commentBody: { flex: 1, minWidth: 0 },
  commentNameRow: { flexDirection: 'row', alignItems: 'center', gap: 8, flexWrap: 'wrap' },
  commentAuthor: { fontSize: 13, lineHeight: 17, fontWeight: '600', color: colors.textHint },
  commentContent: { fontSize: 14, color: colors.textStrong, lineHeight: 20, marginTop: 1, fontWeight: '500' },
  commentTime: { fontSize: 11, color: colors.textHint, marginTop: 3, fontWeight: '600' },
  commentActionRow: { flexDirection: 'row', alignItems: 'center', gap: 18, marginTop: 3 },
  commentActionText: { fontSize: 12, lineHeight: 16, fontWeight: '700', color: colors.textHint },
  commentLikeButton: { minWidth: 44, minHeight: 34, flexDirection: 'row', alignItems: 'center', justifyContent: 'flex-end', paddingTop: 0, gap: 4 },
  commentLikeCount: { fontSize: 12, lineHeight: 16, fontWeight: '600', color: colors.textHint, fontVariant: ['tabular-nums'] },
  emptyComments: { minHeight: 58, borderRadius: 16, backgroundColor: colors.bgSubtle, alignItems: 'center', justifyContent: 'center', gap: 6 },
  emptyCommentsText: { fontSize: 13, fontWeight: '600', color: colors.textSecondary },
  viewAll: { alignSelf: 'flex-start', paddingTop: 6, paddingBottom: 10 },
  viewAllText: { fontSize: 13, color: '#999999', fontWeight: '500' },

  bottomBar: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: colors.bgApp,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: UI_BORDER,
    minHeight: 72,
    paddingTop: 8,
    paddingHorizontal: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 9,
  },
  navItem: { width: 42, height: 36, alignItems: 'center', justifyContent: 'center' },
  navCreateBtn: { width: 32, height: 28, borderRadius: 7, backgroundColor: UI_LIME, borderWidth: 1, borderColor: colors.accentPrimaryHover, alignItems: 'center', justifyContent: 'center' },
  bottomCommentBox: {
    flex: 1,
    minWidth: 0,
    height: 42,
    borderRadius: 13,
    backgroundColor: colors.bgSubtle,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
  },
  bottomCommentInput: { flex: 1, minWidth: 0, color: UI_BLACK, fontSize: 16, lineHeight: 21, fontWeight: '400', paddingVertical: 10 },
  bottomSendBtn: { width: 32, height: 32, borderRadius: 16, backgroundColor: UI_LIME, borderWidth: 1, borderColor: colors.accentPrimaryHover, alignItems: 'center', justifyContent: 'center' },
  bottomMetric: { minWidth: 42, minHeight: 40, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 3 },
  bottomMetricText: { color: UI_BLACK, fontSize: 13, lineHeight: 18, fontWeight: '500', fontVariant: ['tabular-nums'] },
  bottomInputShell: {
    flex: 1,
    minHeight: 42,
    borderRadius: 21,
    backgroundColor: colors.bgSubtle,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 7,
    gap: 6,
  },
  commentInputAvatar: {
    width: 32, height: 32, borderRadius: 16, backgroundColor: UI_WHITE,
    justifyContent: 'center', alignItems: 'center', overflow: 'hidden',
  },
  commentInputImage: { width: 32, height: 32, borderRadius: 16 },
  commentInputAvatarText: { color: UI_BLACK, fontSize: 12, fontWeight: '500' },
  commentInput: { flex: 1, fontSize: 16, lineHeight: 21, color: UI_BLACK, paddingHorizontal: 0, paddingVertical: 8, minWidth: 0, fontWeight: '400' },
  commentInputPlaceholder: { color: '#9A9A9A', fontSize: 16, lineHeight: 21, fontWeight: '400' },
  sendBtn: { width: 32, height: 32, borderRadius: 16, backgroundColor: UI_LIME, borderWidth: 1, borderColor: colors.accentPrimaryHover, alignItems: 'center', justifyContent: 'center' },
  bottomIconBtn: {
    width: 38,
    height: 38,
    borderRadius: 19,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    alignItems: 'center',
    justifyContent: 'center',
  },
  productSheetBackdrop: { flex: 1, justifyContent: 'flex-end', backgroundColor: colors.modalScrim },
  productSheetDismiss: { ...StyleSheet.absoluteFillObject },
  productSheet: { backgroundColor: UI_WHITE, borderTopLeftRadius: 24, borderTopRightRadius: 24, paddingTop: 10, paddingHorizontal: 18, gap: 10 },
  productSheetHandle: { alignSelf: 'center', width: 42, height: 5, borderRadius: 3, backgroundColor: colors.borderMedium, marginBottom: 4 },
  productSheetHeader: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  productSheetName: { color: UI_BLACK, fontSize: 22, lineHeight: 28, fontWeight: '500' },
  productSheetCategory: { color: UI_MUTED, fontSize: 13, lineHeight: 17, fontWeight: '600', marginTop: 2 },
  productSheetClose: { width: 38, height: 38, borderRadius: 19, backgroundColor: colors.bgSubtle, alignItems: 'center', justifyContent: 'center' },
  productSheetLine: { color: UI_BLACK, fontSize: 15, lineHeight: 20, fontWeight: '600' },
  productSheetPrice: { color: UI_BLACK, fontSize: 19, lineHeight: 24, fontWeight: '500' },
  productSheetBody: { color: '#333333', fontSize: 14, lineHeight: 20, fontWeight: '500' },
  productLinkButton: {
    minHeight: 40, borderRadius: 20, backgroundColor: UI_LIME, borderWidth: 1, borderColor: colors.accentPrimaryHover,
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, marginTop: 4,
  },
  productLinkText: { color: UI_WHITE, fontSize: 14, fontWeight: '500' },
  giftSheetBackdrop: { flex: 1, justifyContent: 'flex-end', backgroundColor: colors.modalScrim },
  giftSheetDismiss: { ...StyleSheet.absoluteFillObject },
  giftSheet: {
    backgroundColor: UI_WHITE,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    paddingTop: 10,
    paddingHorizontal: 14,
    gap: 12,
    maxHeight: '78%',
  },
  giftSheetHandle: { alignSelf: 'center', width: 42, height: 5, borderRadius: 3, backgroundColor: colors.borderMedium, marginBottom: 3 },
  giftSheetHeader: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  giftSheetTitle: { color: UI_BLACK, fontSize: 22, lineHeight: 27, fontWeight: '700' },
  giftSheetSubtitle: { color: UI_MUTED, fontSize: 13, lineHeight: 17, fontWeight: '500', marginTop: 1 },
  giftSheetClose: { width: 38, height: 38, borderRadius: 19, backgroundColor: colors.bgSubtle, alignItems: 'center', justifyContent: 'center' },
  giftScroll: { maxHeight: 420 },
  giftGrid: { flexDirection: 'row', flexWrap: 'wrap', rowGap: 17, paddingTop: 4, paddingBottom: 4 },
  giftCard: {
    width: (SW - 28) / 4,
    minHeight: 116,
    borderRadius: 16,
    alignItems: 'center',
    paddingHorizontal: 4,
    paddingVertical: 7,
  },
  giftCardSelected: { backgroundColor: '#FFFBE8', borderWidth: 1.3, borderColor: '#111111' },
  giftIconCircle: {
    width: 62,
    height: 62,
    borderRadius: 31,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#000000',
    shadowOpacity: 0.16,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 6 },
    elevation: 4,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.8)',
  },
  giftIconHighlight: { position: 'absolute', top: 7, left: 10, right: 10, height: 18, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.46)' },
  giftVisual: { fontSize: 43, lineHeight: 52, textAlign: 'center', textShadowColor: 'rgba(0,0,0,0.16)', textShadowOffset: { width: 0, height: 2 }, textShadowRadius: 3 },
  giftLabel: { color: UI_BLACK, fontSize: 13, lineHeight: 15, fontWeight: '800', textAlign: 'center', marginTop: 7 },
  giftCoins: { color: '#777777', fontSize: 12, lineHeight: 15, fontWeight: '800', textAlign: 'center', marginTop: 3 },
  giftFooter: {
    minHeight: 64,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    paddingTop: 4,
  },
  giftRecharge: { flex: 1, minHeight: 52, flexDirection: 'row', alignItems: 'center', gap: 8 },
  giftRechargeText: { color: '#E34D73', fontSize: 24, lineHeight: 29, fontWeight: '800' },
  giftCoinBadge: { width: 34, height: 34, borderRadius: 17, backgroundColor: '#FFD95E', borderWidth: 1.2, borderColor: '#E9B735', alignItems: 'center', justifyContent: 'center' },
  giftBalanceText: { color: UI_BLACK, fontSize: 24, lineHeight: 29, fontWeight: '800', fontVariant: ['tabular-nums'] },
  giftSendButton: { minWidth: 118, height: 52, borderRadius: 7, backgroundColor: '#FFF64A', alignItems: 'center', justifyContent: 'center' },
  giftSendButtonDisabled: { backgroundColor: '#EEEEEE' },
  giftSendText: { color: UI_BLACK, fontSize: 22, lineHeight: 27, fontWeight: '800' },
  giftSendTextDisabled: { color: '#808080' },
  commentComposerBackdrop: { flex: 1, justifyContent: 'flex-end', backgroundColor: colors.modalScrim },
  commentComposerDismiss: { ...StyleSheet.absoluteFillObject },
  commentComposerSheet: {
    backgroundColor: UI_WHITE,
    paddingHorizontal: 16,
    paddingTop: 10,
    gap: 8,
  },
  replyTargetBar: {
    minHeight: 48,
    borderRadius: 14,
    backgroundColor: '#F6F6F6',
    borderWidth: 1,
    borderColor: '#E8E8E8',
    paddingHorizontal: 12,
    paddingVertical: 8,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  replyTargetLabel: { color: UI_BLACK, fontSize: 13, lineHeight: 17, fontWeight: '600' },
  replyTargetText: { color: '#8A8A8A', fontSize: 12, lineHeight: 16, fontWeight: '400', marginTop: 1 },
  replyTargetClose: { width: 30, height: 30, borderRadius: 15, alignItems: 'center', justifyContent: 'center', backgroundColor: UI_WHITE },
  commentComposerInputRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  composerAvatar: { width: 32, height: 32, borderRadius: 16, marginTop: 0 },
  composerAvatarFallback: { backgroundColor: '#DDD2C5', alignItems: 'center', justifyContent: 'center' },
  composerAvatarText: { color: UI_BLACK, fontSize: 13, lineHeight: 17, fontWeight: '700' },
  composerInputBox: {
    flex: 1,
    minHeight: 50,
    borderRadius: 25,
    backgroundColor: colors.bgSubtle,
    paddingHorizontal: 14,
    paddingVertical: 8,
  },
  composerInput: {
    minHeight: 34,
    color: UI_BLACK,
    fontSize: 16,
    lineHeight: 21,
    fontWeight: '400',
    textAlignVertical: 'top',
    padding: 0,
  },
  composerToolbar: { minHeight: 42, flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 8 },
  composerToolIcon: { minWidth: 36, height: 38, alignItems: 'center', justifyContent: 'center' },
  composerAtText: { color: UI_BLACK, fontSize: 23, lineHeight: 28, fontWeight: '600' },
  composerSendBtn: {
    width: 50,
    height: 40,
    borderRadius: 20,
    backgroundColor: colors.accentPrimary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  composerSendBtnDisabled: { backgroundColor: colors.textDisabled },
  composerEmojiRow: { gap: 22, paddingHorizontal: 18, paddingBottom: 2, paddingTop: 1 },
  composerEmoji: { fontSize: 25, lineHeight: 32 },
});
