import React, { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ActivityIndicator,
  TextInput, Dimensions, KeyboardAvoidingView, Platform, Share, Modal,
  ScrollView, StatusBar, PanResponder, Animated as RNAnimated, Alert,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useVideoPlayer, VideoView } from 'expo-video';
import { useAuthStore } from '../../src/store/authStore';
import { cachePostForDetail, getCachedPostForDetail, getPostDetailFeedContext } from '../../src/store/postDetailCache';
import api from '../../src/api/client';
import { isCFStreamVideo, extractStreamUid, getStreamPlaybackInfo } from '../../src/utils/mediaUpload';
import { formatDistanceToNow } from 'date-fns';

const { width: SW, height: SH } = Dimensions.get('window');
const EDGE_ZONE = 50; // px from screen edge triggers post navigation
const SWIPE_THRESHOLD = SW * 0.2; // 20% of screen width to commit navigation
const EDGE_INDICATOR_W = 5; // width of the edge indicator bar
const UI_BLACK = '#111111';
const UI_WHITE = '#FFFFFF';
const UI_LIME = '#DFFF32';
const UI_SURFACE = '#F5F5F5';
const UI_BORDER = '#ECECEC';
const UI_MUTED = '#777777';
const UI_ERROR = '#E05C7A';
const DETAIL_MEDIA_HEIGHT_RATIO = 4 / 3;

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

/* ════════════════════════════════════════════════════════════════════════
   MAIN SCREEN — wraps PostContent with edge-swipe post navigation
   ════════════════════════════════════════════════════════════════════════ */
export default function PostDetailScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { id: postId } = useLocalSearchParams<{ id: string }>();
  const { user } = useAuthStore();

  // Feed context for post-to-post navigation
  const [feedIds, setFeedIds] = useState<string[]>(() => getPostDetailFeedContext());
  const [currentId, setCurrentId] = useState(postId || '');

  // Edge swipe animation
  const translateX = useRef(new RNAnimated.Value(0)).current;
  const [edgeSwipeActive, setEdgeSwipeActive] = useState<'left' | 'right' | null>(null);
  const edgeIndicatorOpacity = useRef(new RNAnimated.Value(0)).current;
  const swipeStartSideRef = useRef<'left' | 'right' | null>(null);

  useEffect(() => {
    setCurrentId(postId || '');
    const cachedContext = getPostDetailFeedContext();
    if (cachedContext.length) setFeedIds(cachedContext);
  }, [postId]);

  const navigateToPost = useCallback((id: string) => {
    setCurrentId(id);
    // Animate in from the swipe direction
    RNAnimated.spring(translateX, {
      toValue: 0,
      useNativeDriver: true,
      tension: 80,
      friction: 12,
    }).start();
  }, [translateX]);

  const currentIdx = feedIds.indexOf(currentId);
  const hasPrev = currentIdx > 0;
  const hasNext = currentIdx >= 0 && currentIdx < feedIds.length - 1;

  // ── Edge-swipe PanResponder ──
  const panResponder = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => false,
    onMoveShouldSetPanResponder: (evt, gs) => {
      const startX = Number(gs.x0 || evt.nativeEvent.pageX);
      const startedLeft = startX <= EDGE_ZONE;
      const startedRight = startX >= SW - EDGE_ZONE;
      const isHorizontal = Math.abs(gs.dx) > 18 && Math.abs(gs.dx) > Math.abs(gs.dy) * 1.35;
      // Left edge: only capture if swiping right (to go back)
      if (startedLeft && gs.dx > 0 && hasPrev && isHorizontal) {
        swipeStartSideRef.current = 'left';
        return true;
      }
      // Right edge: only capture if swiping left (to go next)
      if (startedRight && gs.dx < 0 && hasNext && isHorizontal) {
        swipeStartSideRef.current = 'right';
        return true;
      }
      return false;
    },
    onPanResponderGrant: (evt, gs) => {
      const startX = Number(gs.x0 || evt.nativeEvent.pageX);
      const side = swipeStartSideRef.current || (startX <= EDGE_ZONE ? 'left' : 'right');
      setEdgeSwipeActive(side);
      RNAnimated.timing(edgeIndicatorOpacity, {
        toValue: 1,
        duration: 150,
        useNativeDriver: true,
      }).start();
    },
    onPanResponderMove: (_, gs) => {
      // Clamp movement based on whether there's a prev/next post
      let dx = swipeStartSideRef.current === 'left' ? Math.max(0, gs.dx) : Math.min(0, gs.dx);
      if (dx > 0 && !hasPrev) dx = dx * 0.2; // resistance
      if (dx < 0 && !hasNext) dx = dx * 0.2; // resistance
      translateX.setValue(dx);
    },
    onPanResponderRelease: (_, gs) => {
      setEdgeSwipeActive(null);
      swipeStartSideRef.current = null;
      RNAnimated.timing(edgeIndicatorOpacity, {
        toValue: 0,
        duration: 200,
        useNativeDriver: true,
      }).start();

      if (gs.dx > SWIPE_THRESHOLD && hasPrev) {
        // Swiped right → go to previous post
        RNAnimated.timing(translateX, {
          toValue: SW,
          duration: 200,
          useNativeDriver: true,
        }).start(() => {
          translateX.setValue(-SW);
          navigateToPost(feedIds[currentIdx - 1]);
        });
      } else if (gs.dx < -SWIPE_THRESHOLD && hasNext) {
        // Swiped left → go to next post
        RNAnimated.timing(translateX, {
          toValue: -SW,
          duration: 200,
          useNativeDriver: true,
        }).start(() => {
          translateX.setValue(SW);
          navigateToPost(feedIds[currentIdx + 1]);
        });
      } else {
        // Snap back
        RNAnimated.spring(translateX, {
          toValue: 0,
          useNativeDriver: true,
          tension: 100,
          friction: 12,
        }).start();
      }
    },
    onPanResponderTerminate: () => {
      setEdgeSwipeActive(null);
      swipeStartSideRef.current = null;
      RNAnimated.spring(translateX, {
        toValue: 0,
        useNativeDriver: true,
      }).start();
    },
    onPanResponderTerminationRequest: () => true,
    onShouldBlockNativeResponder: () => false,
  }), [currentIdx, feedIds, hasPrev, hasNext, translateX, navigateToPost, edgeIndicatorOpacity]);

  return (
    <View style={[s.root, { paddingTop: insets.top }]} {...panResponder.panHandlers}>
      <StatusBar barStyle="dark-content" />

      {/* ── Left edge indicator ── */}
      {hasPrev && (
        <RNAnimated.View style={[s.edgeIndicator, s.edgeIndicatorLeft, {
          opacity: edgeSwipeActive === 'left' ? edgeIndicatorOpacity : 0,
        }]} pointerEvents="none" />
      )}
      {/* ── Right edge indicator ── */}
      {hasNext && (
        <RNAnimated.View style={[s.edgeIndicator, s.edgeIndicatorRight, {
          opacity: edgeSwipeActive === 'right' ? edgeIndicatorOpacity : 0,
        }]} pointerEvents="none" />
      )}

      {/* ── Animated post content ── */}
      <RNAnimated.View style={{ flex: 1, transform: [{ translateX }] }}>
        <PostContent
          postId={currentId}
          user={user}
          router={router}
          insets={insets}
        />
      </RNAnimated.View>

    </View>
  );
}

/* ════════════════════════════════════════════════════════════════════════
   POST CONTENT — the actual post detail view (reusable per-post)
   ════════════════════════════════════════════════════════════════════════ */
function PostContent({ postId, user, router, insets }: {
  postId: string; user: any; router: any; insets: any;
}) {
  const initialCachedPostRef = useRef<any>(getCachedPostForDetail(postId));
  const [post, setPost] = useState<any>(initialCachedPostRef.current);
  const [comments, setComments] = useState<any[]>([]);
  const [commentsLoaded, setCommentsLoaded] = useState(false);
  const [commentsLoading, setCommentsLoading] = useState(false);
  const [isLoading, setIsLoading] = useState(!initialCachedPostRef.current);
  const [newComment, setNewComment] = useState('');
  const [isCommenting, setIsCommenting] = useState(false);
  const [liked, setLiked] = useState(false);
  const [likesCount, setLikesCount] = useState(0);
  const [saved, setSaved] = useState(false);
  const [savedCollection, setSavedCollection] = useState('');
  const [activeImgIdx, setActiveImgIdx] = useState(0);
  const [videoHlsUrl, setVideoHlsUrl] = useState<string | null>(null);
  const [showComments, setShowComments] = useState(false);
  const [captionExpanded, setCaptionExpanded] = useState(false);
  const [saveModalVisible, setSaveModalVisible] = useState(false);
  const [collections, setCollections] = useState<any[]>([]);
  const [collectionsLoaded, setCollectionsLoaded] = useState(false);
  const [newCollectionName, setNewCollectionName] = useState('');
  const [isCreatingCollection, setIsCreatingCollection] = useState(false);
  const [following, setFollowing] = useState(false);
  const [isFollowLoading, setIsFollowLoading] = useState(false);
  const videoResolveKeyRef = useRef('');

  const applyPostState = useCallback((p: any) => {
    if (!p) return;
    cachePostForDetail(p);
    setPost(p);
    setLiked(p.liked_by?.includes(user?.id));
    setLikesCount(p.likes_count || 0);
    setFollowing(!!(p.is_following || p.followed || p.following));
  }, [user?.id]);

  const resolveVideoFromPost = useCallback(async (p: any) => {
    const allMedia: string[] = p?.images?.length > 0 ? p.images : p?.image ? [p.image] : [];
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
      api.get(`/bookmarks/check/${postId}`).then((bm) => {
        setSaved(bm.data?.saved || false);
        setSavedCollection(bm.data?.collection || '');
      }).catch(() => undefined);
    } catch (error) {
      if (!seedPost) {
        console.log('Error loading post:', error);
        setPost(null);
      }
    } finally {
      if (!seedPost) setIsLoading(false);
    }
  }, [applyPostState, postId, resolveVideoFromPost]);

  const loadComments = useCallback(async () => {
    if (!postId || commentsLoading || commentsLoaded) return;
    setCommentsLoading(true);
    try {
      const commentsRes = await api.get(`/posts/${postId}/comments`);
      setComments(commentsRes.data || []);
      setCommentsLoaded(true);
    } catch {
      setCommentsLoaded(true);
    } finally {
      setCommentsLoading(false);
    }
  }, [commentsLoaded, commentsLoading, postId]);

  const loadCollections = useCallback(async () => {
    if (collectionsLoaded) return;
    try {
      const colRes = await api.get('/library/collections');
      setCollections(colRes.data || []);
    } catch { } finally {
      setCollectionsLoaded(true);
    }
  }, [collectionsLoaded]);

  // Reset state when postId changes (post-to-post navigation)
  useEffect(() => {
    const cached = getCachedPostForDetail(postId);
    setComments([]);
    setCommentsLoaded(false);
    setCommentsLoading(false);
    setActiveImgIdx(0);
    setVideoHlsUrl(null);
    videoResolveKeyRef.current = '';
    setShowComments(false);
    setCaptionExpanded(false);
    setSaved(false);
    setSavedCollection('');
    setFollowing(false);
    setIsFollowLoading(false);
    if (cached) {
      applyPostState(cached);
      setIsLoading(false);
      void resolveVideoFromPost(cached);
    } else {
      setPost(null);
      setIsLoading(true);
    }
    if (postId) void loadPostData(cached);
  }, [applyPostState, loadPostData, postId, resolveVideoFromPost]);

  useEffect(() => {
    if (showComments) void loadComments();
  }, [loadComments, showComments]);

  // ── Actions ──
  const handleLike = async () => {
    setLiked(!liked);
    setLikesCount(liked ? likesCount - 1 : likesCount + 1);
    try { await api.post(`/posts/${postId}/like`); }
    catch { setLiked(liked); setLikesCount(likesCount); }
  };

  const handleSaveToCollection = async (collection: string) => {
    setSaved(true); setSavedCollection(collection); setSaveModalVisible(false);
    try { await api.post('/bookmarks', { post_id: postId, collection }); }
    catch { try { await api.post(`/library/save/${postId}`, { collection }); } catch { setSaved(false); } }
  };

  const handleUnsave = async () => {
    setSaved(false); setSavedCollection(''); setSaveModalVisible(false);
    try { await api.delete(`/bookmarks/${postId}`); }
    catch { try { await api.delete(`/library/save/${postId}`); } catch { setSaved(true); } }
  };

  const openSaveModal = () => {
    setSaveModalVisible(true);
    void loadCollections();
  };

  const handleComment = async () => {
    if (!newComment.trim() || isCommenting) return;
    setIsCommenting(true);
    try {
      const res = await api.post(`/posts/${postId}/comments`, { content: newComment.trim() });
      setComments((prev) => [...prev, res.data]);
      setCommentsLoaded(true);
      setPost((prev: any) => prev ? { ...prev, comments_count: Number(prev.comments_count || 0) + 1 } : prev);
      setNewComment('');
    } catch { } finally { setIsCommenting(false); }
  };

  const handleShare = async () => {
    try { await Share.share({ message: post?.content || 'Check this out!' }); } catch { }
  };

  const handleFollow = async () => {
    if (!post?.user_id || post.user_id === user?.id || isFollowLoading) return;
    const wasFollowing = following;
    setFollowing(!wasFollowing);
    setIsFollowLoading(true);
    try {
      const response = await api.post(`/users/${post.user_id}/follow`);
      if (typeof response.data?.following === 'boolean') {
        setFollowing(response.data.following);
      }
    } catch (error: any) {
      setFollowing(wasFollowing);
      Alert.alert('Follow failed', error?.response?.data?.detail || 'Could not follow this creator.');
    } finally {
      setIsFollowLoading(false);
    }
  };

  const fmtCount = (n: number) => !n ? '' : n >= 1000 ? (n / 1000).toFixed(1).replace('.0', '') + 'k' : String(n);

  // ── Loading / Not Found ──
  if (isLoading) return <View style={s.center}><ActivityIndicator size="large" color="#111" /></View>;
  if (!post) return (
    <View style={s.center}>
      <Text style={{ color: '#999', fontSize: 16, marginBottom: 16 }}>Post not found</Text>
      <TouchableOpacity onPress={() => router.back()} style={s.goBackBtn}>
        <Text style={{ color: '#FFF', fontWeight: '700' }}>Go Back</Text>
      </TouchableOpacity>
    </View>
  );

  // ── Derived values ──
  const authorName = post.user_full_name || post.user_username || 'User';
  const authorInitial = String(authorName).trim().slice(0, 1).toUpperCase() || 'F';
  const allImages: string[] = post.images?.length > 0
    ? post.images.filter((u: string, i: number) => !isPostVideoMedia(u, post.media_types, i) && (u.startsWith('http') || u.startsWith('data:')))
    : post.image && !isPostVideoMedia(post.image, post.media_types, 0) && (post.image.startsWith('http') || post.image.startsWith('data:'))
      ? [post.image] : [];
  const hasVideo = !!videoHlsUrl;
  const location = post.place_name || post.location || '';
  const caption = String(post.content || '').trim();
  const headline = String(post.title || post.place_name || '').trim();
  const detailTitle = headline || caption || location || 'World Board post';
  const detailBody = headline ? caption : '';
  const mediaW = SW;
  const mediaH = Math.round(mediaW * DETAIL_MEDIA_HEIGHT_RATIO);
  const commentCount = Math.max(comments.length, Number(post.comments_count || 0));
  const commentLabel = commentCount === 1 ? '1 comment' : `${commentCount} comments`;
  const timeAgo = post.created_at ? formatDistanceToNow(new Date(post.created_at), { addSuffix: true }) : '';
  const canFollow = !!post.user_id && post.user_id !== user?.id;
  const savedCount = Number(post.saves_count || post.saved_count || 0);

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <View style={s.detailHeader}>
        <TouchableOpacity style={s.headerIconBtn} onPress={() => router.back()} activeOpacity={0.82}>
          <Ionicons name="chevron-back" size={32} color={UI_BLACK} />
        </TouchableOpacity>
        <TouchableOpacity style={s.headerCreator} onPress={() => router.push(`/user/${post.user_id}` as any)} activeOpacity={0.86}>
          {post.user_profile_image ? (
            <Image source={{ uri: post.user_profile_image }} style={s.headerAvatar} />
          ) : (
            <View style={[s.headerAvatar, s.authorAvatarFb]}>
              <Text style={s.headerInitial}>{authorInitial}</Text>
            </View>
          )}
          <Text style={s.headerName} numberOfLines={1}>{post.user_username || authorName}</Text>
        </TouchableOpacity>
        {canFollow ? (
          <TouchableOpacity
            style={[s.headerFollowBtn, following && s.headerFollowBtnOn]}
            onPress={handleFollow}
            activeOpacity={0.86}
            disabled={isFollowLoading}
          >
            {isFollowLoading ? (
              <ActivityIndicator size="small" color={UI_BLACK} />
            ) : (
              <Text style={[s.headerFollowText, following && s.headerFollowTextOn]}>{following ? 'Following' : 'Follow'}</Text>
            )}
          </TouchableOpacity>
        ) : null}
        <TouchableOpacity style={s.headerIconBtn} onPress={handleShare} activeOpacity={0.82}>
          <Ionicons name="arrow-redo-outline" size={34} color={UI_BLACK} />
        </TouchableOpacity>
      </View>
      <ScrollView
        style={s.detailScroll}
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ paddingBottom: insets.bottom + 118 }}
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
                horizontal pagingEnabled showsHorizontalScrollIndicator={false}
                onMomentumScrollEnd={(e) => setActiveImgIdx(Math.round(e.nativeEvent.contentOffset.x / mediaW))}
                scrollEventThrottle={16}
              >
                {allImages.map((uri: string, i: number) => (
                  <Image key={`img-${i}`} source={{ uri }} style={{ width: mediaW, height: mediaH }} resizeMode="cover" />
                ))}
              </ScrollView>
            ) : (
              <Image source={{ uri: allImages[0] }} style={{ width: mediaW, height: mediaH }} resizeMode="cover" />
            )
          ) : hasVideo ? (
            <VideoPlayer hlsUrl={videoHlsUrl!} width={mediaW} height={mediaH} />
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
            <Text style={s.headlineText} numberOfLines={captionExpanded ? undefined : 2}>{detailTitle}</Text>
            {detailBody ? (
              <Text style={s.captionText} numberOfLines={captionExpanded ? undefined : 3}>{detailBody}</Text>
            ) : null}
            {(detailTitle.length + detailBody.length) > 140 ? (
              <View style={s.expandRow}>
                <Text style={s.expandText}>{captionExpanded ? 'Show less' : 'Read more'}</Text>
                <Ionicons name={captionExpanded ? 'chevron-up' : 'chevron-down'} size={16} color="#6D6258" />
              </View>
            ) : null}
          </TouchableOpacity>

          {timeAgo ? <Text style={s.postMetaText}>{timeAgo}</Text> : null}

          {!showComments && commentCount > 0 ? (
            <TouchableOpacity style={s.viewAll} onPress={() => setShowComments(true)} activeOpacity={0.82}>
              <Text style={s.viewAllText}>View all {commentLabel}</Text>
            </TouchableOpacity>
          ) : null}
          {showComments ? (
            <View style={s.commentsList}>
              <Text style={s.commentsHeader}>{commentLabel}</Text>
              {commentsLoading ? (
                <View style={s.commentsLoadingRow}>
                  <ActivityIndicator color={UI_BLACK} />
                </View>
              ) : comments.length > 0 ? (
                comments.map((c) => (
                  <View key={c.id} style={s.commentItem}>
                    {c.user_profile_image ? (
                      <Image source={{ uri: c.user_profile_image }} style={s.commentAvatar} />
                    ) : (
                      <View style={[s.commentAvatar, s.commentAvatarFb]}>
                        <Text style={s.commentAvatarText}>{(c.user_full_name || c.user_username || 'U')[0]}</Text>
                      </View>
                    )}
                    <View style={{ flex: 1 }}>
                      <Text style={s.commentAuthor}>{c.user_full_name || c.user_username || 'User'}</Text>
                      <Text style={s.commentContent}>{c.content}</Text>
                      <Text style={s.commentTime}>{formatDistanceToNow(new Date(c.created_at), { addSuffix: true })}</Text>
                    </View>
                  </View>
                ))
              ) : (
                <View style={s.emptyComments}>
                  <Ionicons name="chatbubble-ellipses-outline" size={22} color="#B8B0A7" />
                  <Text style={s.emptyCommentsText}>Be the first to comment.</Text>
                </View>
              )}
            </View>
          ) : null}
        </View>
      </ScrollView>

      {/* ═══ COMMENT / ACTION BAR ═══ */}
      <View style={[s.bottomBar, { paddingBottom: Math.max(insets.bottom, 10) }]}>
        <View style={s.bottomCommentBox}>
          <View style={s.commentInputAvatar}>
            {user?.profile_image ? (
              <Image source={{ uri: user.profile_image }} style={s.commentInputImage} />
            ) : (
              <Text style={s.commentInputAvatarText}>{(user?.full_name || 'U')[0]}</Text>
            )}
          </View>
          <TextInput
            style={s.commentInput}
            placeholder="Add a comment"
            placeholderTextColor="#AEAAA5"
            value={newComment}
            onChangeText={setNewComment}
            returnKeyType="send"
            onSubmitEditing={handleComment}
          />
          {newComment.trim() ? (
            <TouchableOpacity onPress={handleComment} disabled={isCommenting} style={{ paddingRight: 4 }} activeOpacity={0.86}>
              {isCommenting ? <ActivityIndicator size="small" color={UI_BLACK} /> : <Ionicons name="arrow-up-circle" size={30} color={UI_BLACK} />}
            </TouchableOpacity>
          ) : null}
        </View>

        <TouchableOpacity style={s.bottomMetric} onPress={handleLike} activeOpacity={0.84}>
          <Ionicons name={liked ? 'heart' : 'heart-outline'} size={37} color={liked ? UI_ERROR : UI_BLACK} />
          <Text style={s.bottomMetricText}>{fmtCount(likesCount) || '0'}</Text>
        </TouchableOpacity>
        <TouchableOpacity style={s.bottomMetric} onPress={() => setShowComments(!showComments)} activeOpacity={0.84}>
          <Ionicons name="chatbubble-outline" size={36} color={UI_BLACK} />
          <Text style={s.bottomMetricText}>{fmtCount(commentCount) || '0'}</Text>
        </TouchableOpacity>
        <TouchableOpacity style={s.bottomMetric} onPress={openSaveModal} activeOpacity={0.84}>
          <Ionicons name={saved ? 'bookmark' : 'bookmark-outline'} size={36} color={UI_BLACK} />
          <Text style={s.bottomMetricText}>{fmtCount(savedCount) || '0'}</Text>
        </TouchableOpacity>
      </View>

      {/* ═══ SAVE MODAL ═══ */}
      <Modal visible={saveModalVisible} transparent animationType="slide">
        <TouchableOpacity style={s.modalOverlay} activeOpacity={1} onPress={() => setSaveModalVisible(false)}>
          <View />
        </TouchableOpacity>
        <View style={[s.saveModal, { paddingBottom: insets.bottom + 16 }]}>
          <View style={s.modalHandle} />
          <Text style={s.modalTitle}>{saved ? 'Saved to collection' : 'Save to collection'}</Text>

          {!saved && (
            <TouchableOpacity style={s.quickSaveRow} onPress={() => handleSaveToCollection('My Library')}>
              <View style={s.quickSaveIcon}><Ionicons name="bookmark" size={20} color="#FFF" /></View>
              <View style={{ flex: 1 }}>
                <Text style={s.quickSaveTitle}>My Library</Text>
                <Text style={s.quickSaveDesc}>Quick save</Text>
              </View>
              <Ionicons name="chevron-forward" size={20} color="#CCC" />
            </TouchableOpacity>
          )}

          {collections.length > 0 && (
            <View style={s.colSection}>
              <Text style={s.colSectionTitle}>Your Collections</Text>
              {collections.map((col: any, idx: number) => (
                <TouchableOpacity key={idx} style={s.colItem} onPress={() => handleSaveToCollection(col.collection)}>
                  <View style={[s.colIcon, { backgroundColor: ['#F3ECFF', '#FEE2E2', '#DBEAFE', '#D1FAE5'][idx % 4] }]}>
                    <Ionicons name="folder" size={18} color={['#7C3AED', '#DC2626', '#2563EB', '#059669'][idx % 4]} />
                  </View>
                  <View style={{ flex: 1 }}>
                    <Text style={s.colName}>{col.collection}</Text>
                    <Text style={s.colCount}>{col.count} item{col.count !== 1 ? 's' : ''}</Text>
                  </View>
                  {savedCollection === col.collection && <Ionicons name="checkmark-circle" size={22} color="#059669" />}
                </TouchableOpacity>
              ))}
            </View>
          )}

          {isCreatingCollection ? (
            <View style={s.newColRow}>
              <TextInput style={s.newColInput} placeholder="Collection name" placeholderTextColor="#CCC" value={newCollectionName} onChangeText={setNewCollectionName} autoFocus />
              <TouchableOpacity style={[s.createBtn, !newCollectionName.trim() && { opacity: 0.4 }]} disabled={!newCollectionName.trim()} onPress={() => { if (newCollectionName.trim()) { handleSaveToCollection(newCollectionName.trim()); setNewCollectionName(''); setIsCreatingCollection(false); } }}>
                <Text style={s.createBtnText}>Save</Text>
              </TouchableOpacity>
            </View>
          ) : (
            <TouchableOpacity style={s.createColBtn} onPress={() => setIsCreatingCollection(true)}>
              <Ionicons name="add-circle-outline" size={22} color="#111" />
              <Text style={s.createColText}>Create collection</Text>
            </TouchableOpacity>
          )}

          {saved && (
            <TouchableOpacity style={s.unsaveBtn} onPress={handleUnsave}>
              <Ionicons name="bookmark-outline" size={20} color="#DC2626" />
              <Text style={s.unsaveBtnText}>Remove from saved</Text>
            </TouchableOpacity>
          )}
        </View>
      </Modal>
    </KeyboardAvoidingView>
  );
}

/* ════════════════════════════════════════════════════════════════════════
   VIDEO PLAYER
   ════════════════════════════════════════════════════════════════════════ */
function VideoPlayer({ hlsUrl, width, height }: { hlsUrl: string; width: number; height: number }) {
  const [firstFrameReady, setFirstFrameReady] = useState(false);
  const tapTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastTapRef = useRef<{ time: number; side: 'left' | 'right' | null }>({ time: 0, side: null });
  const player = useVideoPlayer(hlsUrl, (p) => {
    p.loop = false;
    p.muted = false;
    p.volume = 1;
    p.audioMixingMode = 'auto';
    p.allowsExternalPlayback = false;
    p.showNowPlayingNotification = false;
    p.play();
  });

  const clearTapTimer = useCallback(() => {
    if (tapTimerRef.current) {
      clearTimeout(tapTimerRef.current);
      tapTimerRef.current = null;
    }
  }, []);

  useEffect(() => {
    setFirstFrameReady(false);
    lastTapRef.current = { time: 0, side: null };
    clearTapTimer();
    player.play();
    return clearTapTimer;
  }, [clearTapTimer, hlsUrl, player]);

  const togglePlayback = useCallback(() => {
    if (player.playing) {
      player.pause();
    } else {
      player.play();
    }
  }, [player]);

  const handleTap = useCallback((x: number) => {
    const side = x < width / 2 ? 'left' : 'right';
    const now = Date.now();
    const previousTap = lastTapRef.current;

    if (previousTap.side === side && now - previousTap.time < 280) {
      clearTapTimer();
      player.seekBy(side === 'left' ? -10 : 10);
      lastTapRef.current = { time: 0, side: null };
      return;
    }

    lastTapRef.current = { time: now, side };
    clearTapTimer();
    tapTimerRef.current = setTimeout(() => {
      togglePlayback();
      lastTapRef.current = { time: 0, side: null };
      tapTimerRef.current = null;
    }, 240);
  }, [clearTapTimer, player, togglePlayback, width]);

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
        onPress={(event) => handleTap(event.nativeEvent.locationX + EDGE_ZONE)}
      />
      {!firstFrameReady ? (
        <View style={s.videoLoadingCover} pointerEvents="none">
          <ActivityIndicator color="#FFFFFF" />
        </View>
      ) : null}
    </View>
  );
}

/* ════════════════════════════════════════════════════════════════════════
   STYLES
   ════════════════════════════════════════════════════════════════════════ */
const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: UI_WHITE },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: UI_WHITE },
  goBackBtn: { backgroundColor: UI_BLACK, paddingHorizontal: 24, paddingVertical: 12, borderRadius: 24 },

  // Edge indicators
  edgeIndicator: {
    position: 'absolute', top: 0, bottom: 0, width: EDGE_INDICATOR_W,
    zIndex: 50, borderRadius: 2,
  },
  edgeIndicatorLeft: { left: 0, backgroundColor: UI_LIME },
  edgeIndicatorRight: { right: 0, backgroundColor: UI_LIME },

  // Post nav hint
  postNavHint: {
    position: 'absolute', alignSelf: 'center',
    backgroundColor: 'rgba(0,0,0,0.5)', borderRadius: 10,
    paddingHorizontal: 10, paddingVertical: 4, zIndex: 20,
  },
  postNavText: { fontSize: 11, fontWeight: '600', color: '#FFF' },

  brandRow: {
    minHeight: 44,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: UI_WHITE,
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
  brandText: { color: UI_BLACK, fontSize: 13, lineHeight: 16, fontWeight: '900', fontStyle: 'italic' },
  detailHeader: {
    minHeight: 72,
    paddingHorizontal: 18,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    backgroundColor: UI_WHITE,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: UI_BORDER,
    zIndex: 30,
  },
  detailScroll: { flex: 1, backgroundColor: UI_WHITE },
  headerIconBtn: { width: 34, height: 42, borderRadius: 17, alignItems: 'center', justifyContent: 'center' },
  headerCreator: { flex: 1, minWidth: 0, flexDirection: 'row', alignItems: 'center', gap: 10 },
  headerAvatar: { width: 44, height: 44, borderRadius: 22 },
  headerInitial: { color: UI_BLACK, fontSize: 16, fontWeight: '900' },
  headerName: { flex: 1, minWidth: 0, color: UI_BLACK, fontSize: 21, fontWeight: '900' },
  headerFollowBtn: {
    minWidth: 96,
    minHeight: 46,
    borderRadius: 10,
    backgroundColor: UI_LIME,
    borderWidth: 1.2,
    borderColor: UI_BLACK,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 14,
  },
  headerFollowBtnOn: { backgroundColor: UI_WHITE, borderWidth: 1, borderColor: UI_BORDER },
  headerFollowText: { color: UI_BLACK, fontSize: 18, fontWeight: '900' },
  headerFollowTextOn: { color: UI_BLACK },

  imageCard: {
    overflow: 'hidden',
    backgroundColor: UI_SURFACE,
    position: 'relative',
  },
  noImgBg: { backgroundColor: UI_SURFACE, justifyContent: 'center', alignItems: 'center', gap: 10 },
  noImgText: { color: UI_MUTED, fontSize: 14, fontWeight: '800' },
  videoShell: { overflow: 'hidden', backgroundColor: '#111111', position: 'relative' },
  videoTapLayer: { position: 'absolute', top: 0, bottom: 0, left: EDGE_ZONE, right: EDGE_ZONE, backgroundColor: 'transparent' },
  videoLoadingCover: { ...StyleSheet.absoluteFillObject, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(0,0,0,0.16)' },
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

  contentSheet: { paddingTop: 2, paddingHorizontal: 18, gap: 9 },
  authorRow: { flexDirection: 'row', alignItems: 'center', minHeight: 48 },
  authorAvatar: { width: 44, height: 44, borderRadius: 22, marginRight: 10 },
  authorAvatarFb: { backgroundColor: UI_SURFACE, justifyContent: 'center', alignItems: 'center' },
  authorInit: { color: UI_BLACK, fontSize: 16, fontWeight: '900' },
  authorMeta: { flex: 1, minWidth: 0 },
  authorName: { fontSize: 16, lineHeight: 20, fontWeight: '900', color: UI_BLACK },
  authorSub: { fontSize: 12, lineHeight: 16, fontWeight: '700', color: '#81766C', marginTop: 1 },
  followBtn: {
    minWidth: 86,
    minHeight: 36,
    borderRadius: 18,
    backgroundColor: '#111111',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 14,
  },
  followBtnOn: { backgroundColor: '#F4EFE8', borderWidth: 1, borderColor: '#D9D0C6' },
  followText: { color: '#FFFFFF', fontSize: 13, fontWeight: '900' },
  followTextOn: { color: '#111111' },

  postMetaText: { color: '#999999', fontSize: 17, lineHeight: 23, fontWeight: '800' },
  locationRow: {
    alignSelf: 'flex-start',
    flexDirection: 'row',
    alignItems: 'center',
    maxWidth: '100%',
    gap: 6,
    backgroundColor: '#FFF5F4',
    borderRadius: 16,
    paddingHorizontal: 11,
    paddingVertical: 7,
  },
  locationText: { fontSize: 13, lineHeight: 17, fontWeight: '800', color: '#7A2E29', flexShrink: 1 },
  captionBlock: { gap: 7 },
  headlineText: { fontSize: 25, lineHeight: 33, fontWeight: '900', color: UI_BLACK },
  captionText: { fontSize: 21, lineHeight: 30, fontWeight: '700', color: UI_BLACK },
  emptyCaptionText: { fontSize: 15, lineHeight: 22, fontWeight: '700', color: '#8D837A' },
  expandRow: { alignSelf: 'flex-start', flexDirection: 'row', alignItems: 'center', gap: 2, paddingTop: 2 },
  expandText: { fontSize: 13, fontWeight: '900', color: '#6D6258' },
  inlineCommentCount: { color: '#111111', fontSize: 20, lineHeight: 28, fontWeight: '900', paddingTop: 14 },

  tagsRow: { gap: 6, paddingRight: 16 },
  tagPill: { backgroundColor: '#F4EFE8', paddingHorizontal: 9, paddingVertical: 5, borderRadius: 11 },
  tagText: { fontSize: 11, lineHeight: 14, fontWeight: '800', color: '#4B4038' },
  thoughtBox: {
    minHeight: 56,
    borderRadius: 14,
    backgroundColor: '#F2F2F2',
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    gap: 10,
  },
  thoughtInput: { flex: 1, minWidth: 0, fontSize: 20, color: UI_BLACK, paddingVertical: 12, fontWeight: '800' },
  thoughtSendBtn: { width: 34, height: 34, borderRadius: 17, backgroundColor: UI_LIME, borderWidth: 1.2, borderColor: UI_BLACK, alignItems: 'center', justifyContent: 'center' },
  reactionRow: { flexDirection: 'row', alignItems: 'center', gap: 7 },
  reaction: { fontSize: 14 },
  postActionRow: {
    minHeight: 48,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  },
  savedAction: { flexDirection: 'row', alignItems: 'center', gap: 4, minWidth: 0, flexShrink: 1 },
  savedActionText: { color: '#111111', fontSize: 18, lineHeight: 22, fontWeight: '800' },
  postActionRight: { flexDirection: 'row', alignItems: 'center', gap: 22 },
  iconStat: { flexDirection: 'row', alignItems: 'center', gap: 7 },
  iconStatText: { color: '#111111', fontSize: 20, fontWeight: '900' },
  iconOnly: { width: 30, height: 30, alignItems: 'center', justifyContent: 'center' },
  actionStrip: { flexDirection: 'row', alignItems: 'center', gap: 8, flexWrap: 'wrap', paddingTop: 2 },
  actionPill: {
    minHeight: 40,
    borderRadius: 20,
    backgroundColor: '#F7F3EE',
    borderWidth: 1,
    borderColor: '#EEE5DD',
    paddingHorizontal: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  actionPillOn: { backgroundColor: '#FFF2F1', borderColor: '#F5C9C6' },
  actionPillText: { color: '#111111', fontSize: 13, fontWeight: '900' },
  actionCircle: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: '#F7F3EE',
    borderWidth: 1,
    borderColor: '#EEE5DD',
    alignItems: 'center',
    justifyContent: 'center',
  },

  commentsPanel: {
    backgroundColor: '#FDFBF8',
    borderWidth: 1,
    borderColor: '#EEE6DE',
    borderRadius: 22,
    padding: 14,
    gap: 12,
  },
  commentsList: { paddingTop: 8 },
  commentsLoadingRow: { minHeight: 64, alignItems: 'center', justifyContent: 'center' },
  commentsHeader: { fontSize: 16, fontWeight: '700', color: '#111111', marginBottom: 12 },
  commentsHeaderRow: { flexDirection: 'row', alignItems: 'baseline', justifyContent: 'space-between', gap: 12 },
  commentsTitle: { fontSize: 17, lineHeight: 22, fontWeight: '900', color: '#111111' },
  commentsCount: { fontSize: 12, lineHeight: 16, fontWeight: '800', color: '#8A8178' },
  commentItem: { flexDirection: 'row', marginBottom: 14 },
  commentAvatar: { width: 28, height: 28, borderRadius: 14, marginRight: 10, marginTop: 2 },
  commentAvatarFb: { backgroundColor: '#EEE8DF', justifyContent: 'center', alignItems: 'center' },
  commentAvatarText: { fontSize: 10, fontWeight: '700', color: '#999999' },
  commentNameRow: { flexDirection: 'row', alignItems: 'center', gap: 8, flexWrap: 'wrap' },
  commentAuthor: { fontSize: 13, fontWeight: '700', color: '#111111' },
  commentContent: { fontSize: 14, color: '#333333', lineHeight: 19, marginTop: 1 },
  commentTime: { fontSize: 11, color: '#B0B0B0', marginTop: 3 },
  emptyComments: { minHeight: 58, borderRadius: 16, backgroundColor: '#F7F3EE', alignItems: 'center', justifyContent: 'center', gap: 6 },
  emptyCommentsText: { fontSize: 13, fontWeight: '800', color: '#81766C' },
  viewAll: { alignSelf: 'flex-start', paddingTop: 6, paddingBottom: 10 },
  viewAllText: { fontSize: 13, color: '#999999', fontWeight: '500' },

  bottomBar: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: UI_WHITE,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: UI_BORDER,
    minHeight: 84,
    paddingTop: 12,
    paddingHorizontal: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
  },
  navItem: { width: 42, height: 36, alignItems: 'center', justifyContent: 'center' },
  navCreateBtn: { width: 34, height: 28, borderRadius: 7, backgroundColor: UI_LIME, borderWidth: 1.2, borderColor: UI_BLACK, alignItems: 'center', justifyContent: 'center' },
  bottomCommentBox: {
    flex: 1,
    minWidth: 0,
    minHeight: 46,
    borderRadius: 28,
    backgroundColor: UI_SURFACE,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 6,
    paddingVertical: 4,
  },
  bottomCommentInput: { flex: 1, minWidth: 0, color: UI_BLACK, fontSize: 20, lineHeight: 24, fontWeight: '800', paddingVertical: 12 },
  bottomSendBtn: { width: 34, height: 34, borderRadius: 17, backgroundColor: UI_LIME, borderWidth: 1.2, borderColor: UI_BLACK, alignItems: 'center', justifyContent: 'center' },
  bottomMetric: { minWidth: 52, minHeight: 48, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 4 },
  bottomMetricText: { color: UI_BLACK, fontSize: 18, lineHeight: 24, fontWeight: '900', fontVariant: ['tabular-nums'] },
  bottomInputShell: {
    flex: 1,
    minHeight: 46,
    borderRadius: 23,
    backgroundColor: '#F4EFE8',
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
  commentInputAvatarText: { color: UI_BLACK, fontSize: 12, fontWeight: '700' },
  commentInput: { flex: 1, fontSize: 14, color: UI_BLACK, paddingHorizontal: 10, paddingVertical: 10, minWidth: 0 },
  sendBtn: { width: 32, height: 32, borderRadius: 16, backgroundColor: UI_LIME, borderWidth: 1.2, borderColor: UI_BLACK, alignItems: 'center', justifyContent: 'center' },
  bottomIconBtn: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: '#FFFFFF',
    borderWidth: 1,
    borderColor: '#EEE5DD',
    alignItems: 'center',
    justifyContent: 'center',
  },

  // Save modal
  modalOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.4)' },
  saveModal: {
    backgroundColor: '#FFF', borderTopLeftRadius: 24, borderTopRightRadius: 24,
    paddingHorizontal: 20, paddingTop: 12, maxHeight: SH * 0.6,
  },
  modalHandle: { width: 40, height: 4, borderRadius: 2, backgroundColor: '#E0DDD8', alignSelf: 'center', marginBottom: 16 },
  modalTitle: { fontSize: 18, fontWeight: '800', color: '#111', marginBottom: 16 },

  quickSaveRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 14, gap: 12, borderBottomWidth: 1, borderBottomColor: '#F0EDE7' },
  quickSaveIcon: { width: 44, height: 44, borderRadius: 14, backgroundColor: UI_BLACK, justifyContent: 'center', alignItems: 'center' },
  quickSaveTitle: { fontSize: 16, fontWeight: '700', color: '#111' },
  quickSaveDesc: { fontSize: 13, color: '#999', marginTop: 1 },

  colSection: { paddingTop: 12 },
  colSectionTitle: { fontSize: 12, fontWeight: '700', color: '#999', letterSpacing: 1, textTransform: 'uppercase', marginBottom: 10 },
  colItem: { flexDirection: 'row', alignItems: 'center', paddingVertical: 12, gap: 12, borderBottomWidth: 1, borderBottomColor: '#F5F2EC' },
  colIcon: { width: 40, height: 40, borderRadius: 12, justifyContent: 'center', alignItems: 'center' },
  colName: { fontSize: 15, fontWeight: '600', color: '#111' },
  colCount: { fontSize: 12, color: '#999', marginTop: 1 },

  newColRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 12 },
  newColInput: { flex: 1, backgroundColor: '#F5F2EC', borderRadius: 14, paddingHorizontal: 14, paddingVertical: 12, fontSize: 15, color: '#111' },
  createBtn: { backgroundColor: UI_BLACK, paddingHorizontal: 20, paddingVertical: 12, borderRadius: 20 },
  createBtnText: { fontSize: 14, fontWeight: '700', color: '#FFF' },
  createColBtn: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 14, borderTopWidth: 1, borderTopColor: '#F0EDE7', marginTop: 4 },
  createColText: { fontSize: 15, fontWeight: '600', color: '#111' },
  unsaveBtn: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 14, borderTopWidth: 1, borderTopColor: '#F0EDE7', marginTop: 4 },
  unsaveBtnText: { fontSize: 15, fontWeight: '600', color: '#DC2626' },
});
