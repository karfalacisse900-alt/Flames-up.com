import React, { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ActivityIndicator,
  TextInput, Dimensions, KeyboardAvoidingView, Platform, Share, Modal,
  ScrollView, StatusBar, PanResponder, Animated as RNAnimated,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useVideoPlayer, VideoView } from 'expo-video';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';
import { isCFStreamVideo, extractStreamUid, getStreamPlaybackInfo } from '../../src/utils/mediaUpload';
import { formatDistanceToNow } from 'date-fns';

const { width: SW, height: SH } = Dimensions.get('window');
const PAD = 4;
const IMG_W = SW - PAD * 2;
const R = 20;
const EDGE_ZONE = 50; // px from screen edge triggers post navigation
const SWIPE_THRESHOLD = SW * 0.2; // 20% of screen width to commit navigation
const EDGE_INDICATOR_W = 5; // width of the edge indicator bar

/* ════════════════════════════════════════════════════════════════════════
   MAIN SCREEN — wraps PostContent with edge-swipe post navigation
   ════════════════════════════════════════════════════════════════════════ */
export default function PostDetailScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { id: postId } = useLocalSearchParams<{ id: string }>();
  const { user } = useAuthStore();

  // Feed context for post-to-post navigation
  const [feedIds, setFeedIds] = useState<string[]>([]);
  const [currentId, setCurrentId] = useState(postId || '');
  const [prevPostData, setPrevPostData] = useState<any>(null);
  const [nextPostData, setNextPostData] = useState<any>(null);
  const [isTransitioning, setIsTransitioning] = useState(false);

  // Edge swipe animation
  const translateX = useRef(new RNAnimated.Value(0)).current;
  const [edgeSwipeActive, setEdgeSwipeActive] = useState<'left' | 'right' | null>(null);
  const edgeIndicatorOpacity = useRef(new RNAnimated.Value(0)).current;

  // Load feed to know prev/next posts
  useEffect(() => {
    loadFeedContext();
  }, []);

  useEffect(() => {
    setCurrentId(postId || '');
  }, [postId]);

  // Preload adjacent posts whenever currentId changes
  useEffect(() => {
    if (feedIds.length > 0 && currentId) {
      preloadAdjacentPosts();
    }
  }, [currentId, feedIds]);

  const loadFeedContext = async () => {
    try {
      const res = await api.get('/posts/feed?limit=50');
      const ids = (res.data || []).map((p: any) => p.id);
      setFeedIds(ids);
    } catch { }
  };

  const preloadAdjacentPosts = async () => {
    const idx = feedIds.indexOf(currentId);
    if (idx === -1) return;
    const prevId = idx > 0 ? feedIds[idx - 1] : null;
    const nextId = idx < feedIds.length - 1 ? feedIds[idx + 1] : null;
    try {
      if (prevId) {
        const r = await api.get(`/posts/${prevId}`);
        setPrevPostData(r.data);
      } else { setPrevPostData(null); }
      if (nextId) {
        const r = await api.get(`/posts/${nextId}`);
        setNextPostData(r.data);
      } else { setNextPostData(null); }
    } catch { }
  };

  const navigateToPost = useCallback((id: string) => {
    setIsTransitioning(true);
    setCurrentId(id);
    // Animate in from the swipe direction
    RNAnimated.spring(translateX, {
      toValue: 0,
      useNativeDriver: true,
      tension: 80,
      friction: 12,
    }).start(() => setIsTransitioning(false));
  }, [translateX]);

  const currentIdx = feedIds.indexOf(currentId);
  const hasPrev = currentIdx > 0;
  const hasNext = currentIdx >= 0 && currentIdx < feedIds.length - 1;

  // ── Edge-swipe PanResponder ──
  const panResponder = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: (evt) => {
      const x = evt.nativeEvent.pageX;
      return x <= EDGE_ZONE || x >= SW - EDGE_ZONE;
    },
    onMoveShouldSetPanResponder: (evt, gs) => {
      const x = evt.nativeEvent.pageX;
      const inEdge = x <= EDGE_ZONE || x >= SW - EDGE_ZONE;
      const isHorizontal = Math.abs(gs.dx) > 10 && Math.abs(gs.dx) > Math.abs(gs.dy) * 1.2;
      // Left edge: only capture if swiping right (to go back)
      if (x <= EDGE_ZONE && gs.dx > 0 && hasPrev && isHorizontal) return true;
      // Right edge: only capture if swiping left (to go next)
      if (x >= SW - EDGE_ZONE && gs.dx < 0 && hasNext && isHorizontal) return true;
      return false;
    },
    onPanResponderGrant: (evt) => {
      const x = evt.nativeEvent.pageX;
      const side = x <= EDGE_ZONE ? 'left' : 'right';
      setEdgeSwipeActive(side);
      RNAnimated.timing(edgeIndicatorOpacity, {
        toValue: 1,
        duration: 150,
        useNativeDriver: true,
      }).start();
    },
    onPanResponderMove: (_, gs) => {
      // Clamp movement based on whether there's a prev/next post
      let dx = gs.dx;
      if (dx > 0 && !hasPrev) dx = dx * 0.2; // resistance
      if (dx < 0 && !hasNext) dx = dx * 0.2; // resistance
      translateX.setValue(dx);
    },
    onPanResponderRelease: (_, gs) => {
      setEdgeSwipeActive(null);
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
      RNAnimated.spring(translateX, {
        toValue: 0,
        useNativeDriver: true,
      }).start();
    },
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

      {/* ── Post position indicator (subtle dots) ── */}
      {feedIds.length > 1 && currentIdx >= 0 && (
        <View style={[s.postNavHint, { bottom: insets.bottom + 6 }]}>
          <Text style={s.postNavText}>
            {currentIdx + 1} / {feedIds.length}
          </Text>
        </View>
      )}
    </View>
  );
}

/* ════════════════════════════════════════════════════════════════════════
   POST CONTENT — the actual post detail view (reusable per-post)
   ════════════════════════════════════════════════════════════════════════ */
function PostContent({ postId, user, router, insets }: {
  postId: string; user: any; router: any; insets: any;
}) {
  const [post, setPost] = useState<any>(null);
  const [comments, setComments] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [newComment, setNewComment] = useState('');
  const [isCommenting, setIsCommenting] = useState(false);
  const [liked, setLiked] = useState(false);
  const [likesCount, setLikesCount] = useState(0);
  const [saved, setSaved] = useState(false);
  const [savedCollection, setSavedCollection] = useState('');
  const [activeImgIdx, setActiveImgIdx] = useState(0);
  const [videoHlsUrl, setVideoHlsUrl] = useState<string | null>(null);
  const [showComments, setShowComments] = useState(false);
  const [imgAspect, setImgAspect] = useState(1.25);
  const [captionExpanded, setCaptionExpanded] = useState(false);
  const [fullscreenVisible, setFullscreenVisible] = useState(false);
  const [saveModalVisible, setSaveModalVisible] = useState(false);
  const [collections, setCollections] = useState<any[]>([]);
  const [newCollectionName, setNewCollectionName] = useState('');
  const [isCreatingCollection, setIsCreatingCollection] = useState(false);

  // Reset state when postId changes (post-to-post navigation)
  useEffect(() => {
    setPost(null);
    setComments([]);
    setIsLoading(true);
    setActiveImgIdx(0);
    setVideoHlsUrl(null);
    setShowComments(false);
    setImgAspect(1.25);
    setCaptionExpanded(false);
    setLiked(false);
    setLikesCount(0);
    setSaved(false);
    if (postId) loadPostData();
  }, [postId]);

  const loadPostData = async () => {
    try {
      const [postRes, commentsRes] = await Promise.all([
        api.get(`/posts/${postId}`),
        api.get(`/posts/${postId}/comments`),
      ]);
      const p = postRes.data;
      setPost(p);
      setComments(commentsRes.data || []);
      setLiked(p.liked_by?.includes(user?.id));
      setLikesCount(p.likes_count || 0);

      try {
        const bm = await api.get(`/bookmarks/check/${postId}`);
        setSaved(bm.data?.saved || false);
        setSavedCollection(bm.data?.collection || '');
      } catch { }
      try {
        const colRes = await api.get('/library/collections');
        setCollections(colRes.data || []);
      } catch { }

      // Resolve video
      const allMedia: string[] = p.images?.length > 0 ? p.images : p.image ? [p.image] : [];
      const mediaTypes: string[] = p.media_types || [];
      let hasVid = false;
      for (let i = 0; i < allMedia.length; i++) {
        if (isCFStreamVideo(allMedia[i]) || mediaTypes[i] === 'video') {
          hasVid = true;
          const uid = extractStreamUid(allMedia[i]);
          if (uid) {
            try {
              const info = await getStreamPlaybackInfo(uid);
              if (info?.hls) setVideoHlsUrl(info.hls);
            } catch { }
          }
        }
      }

      // Image aspect ratio
      const imgUrls = allMedia.filter((u: string) => !isCFStreamVideo(u) && (u.startsWith('http') || u.startsWith('data:')));
      if (imgUrls.length > 0) {
        Image.getSize(imgUrls[0], (w, h) => {
          if (w > 0 && h > 0) setImgAspect(Math.min(Math.max(h / w, 0.6), 1.8));
        }, () => { });
      } else if (hasVid) {
        setImgAspect(1.0);
      }
    } catch (error) {
      console.log('Error loading post:', error);
    } finally {
      setIsLoading(false);
    }
  };

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

  const handleComment = async () => {
    if (!newComment.trim() || isCommenting) return;
    setIsCommenting(true);
    try {
      const res = await api.post(`/posts/${postId}/comments`, { content: newComment.trim() });
      setComments([...comments, res.data]);
      setNewComment('');
    } catch { } finally { setIsCommenting(false); }
  };

  const handleShare = async () => {
    try { await Share.share({ message: post?.content || 'Check this out!' }); } catch { }
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
  const allImages: string[] = post.images?.length > 0
    ? post.images.filter((u: string) => !isCFStreamVideo(u) && (u.startsWith('http') || u.startsWith('data:')))
    : post.image && !isCFStreamVideo(post.image) && (post.image.startsWith('http') || post.image.startsWith('data:'))
      ? [post.image] : [];
  const hasVideo = !!videoHlsUrl;
  const location = post.place_name || post.location || '';
  const tags = [post.post_type, post.category].filter(Boolean);
  const hasCaption = !!post.content?.trim();
  const dynImgH = IMG_W * imgAspect;

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ paddingBottom: insets.bottom + 30 }}
        bounces
        keyboardShouldPersistTaps="handled"
      >
        {/* ═══ IMAGE / VIDEO CARD ═══ */}
        <View style={[s.imageCard, { borderRadius: R }]}>
          {allImages.length > 0 ? (
            allImages.length > 1 ? (
              <ScrollView
                horizontal pagingEnabled showsHorizontalScrollIndicator={false}
                onMomentumScrollEnd={(e) => setActiveImgIdx(Math.round(e.nativeEvent.contentOffset.x / IMG_W))}
                scrollEventThrottle={16}
              >
                {allImages.map((uri: string, i: number) => (
                  <Image key={`img-${i}`} source={{ uri }} style={{ width: IMG_W, height: dynImgH }} resizeMode="cover" />
                ))}
              </ScrollView>
            ) : (
              <Image source={{ uri: allImages[0] }} style={{ width: IMG_W, height: dynImgH }} resizeMode="cover" />
            )
          ) : hasVideo ? (
            <VideoPlayer hlsUrl={videoHlsUrl!} width={IMG_W} height={dynImgH} />
          ) : (
            <View style={[{ width: IMG_W, height: SW }, s.noImgBg]}>
              <Ionicons name="image-outline" size={56} color="#D4D0C8" />
            </View>
          )}

          {/* Floating Back */}
          <TouchableOpacity
            style={[s.floatingBtn, { top: 12, left: 12 }]}
            onPress={() => router.back()}
            activeOpacity={0.8}
          >
            <Ionicons name="chevron-back" size={22} color="#111" />
          </TouchableOpacity>

          {/* Fullscreen toggle */}
          <TouchableOpacity
            style={[s.floatingBtn, { bottom: 14, right: 14 }]}
            onPress={() => setFullscreenVisible(true)}
            activeOpacity={0.8}
          >
            <Ionicons name="expand-outline" size={20} color="#111" />
          </TouchableOpacity>

          {/* Carousel dots */}
          {allImages.length > 1 && (
            <View style={s.dots}>
              {allImages.map((_: string, i: number) => (
                <View key={i} style={[s.dot, activeImgIdx === i && s.dotActive]} />
              ))}
            </View>
          )}
        </View>

        {/* ═══ LOCATION ═══ */}
        {location ? (
          <View style={s.locationRow}>
            <Ionicons name="location-sharp" size={16} color="#E60023" />
            <Text style={s.locationText} numberOfLines={1}>{location}</Text>
          </View>
        ) : null}

        {/* ═══ TAGS ═══ */}
        {tags.length > 0 && (
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.tagsRow}>
            {tags.map((tag, i) => (
              <View key={i} style={s.tagPill}><Text style={s.tagText}>{tag}</Text></View>
            ))}
          </ScrollView>
        )}

        {/* ═══ ENGAGEMENT ROW ═══ */}
        <View style={s.engageRow}>
          <View style={s.engageLeft}>
            <TouchableOpacity onPress={handleLike} style={s.engageIcon}>
              <Ionicons name={liked ? 'heart' : 'heart-outline'} size={26} color={liked ? '#E60023' : '#111'} />
            </TouchableOpacity>
            {likesCount > 0 && <Text style={s.engageCount}>{fmtCount(likesCount)}</Text>}

            <TouchableOpacity style={[s.engageIcon, { marginLeft: 14 }]} onPress={() => setShowComments(!showComments)}>
              <Ionicons name="chatbubble-outline" size={22} color="#111" />
            </TouchableOpacity>
            {comments.length > 0 && <Text style={s.engageCount}>{comments.length}</Text>}

            <TouchableOpacity style={[s.engageIcon, { marginLeft: 14 }]} onPress={handleShare}>
              <Ionicons name="arrow-up-outline" size={24} color="#111" />
            </TouchableOpacity>

            <TouchableOpacity style={[s.engageIcon, { marginLeft: 14 }]}>
              <Ionicons name="ellipsis-horizontal" size={24} color="#111" />
            </TouchableOpacity>
          </View>

          <TouchableOpacity
            style={[s.saveBtn, saved && s.saveBtnSaved]}
            onPress={() => setSaveModalVisible(true)}
            activeOpacity={0.85}
          >
            <Text style={s.saveBtnText}>{saved ? 'Saved' : 'Save'}</Text>
          </TouchableOpacity>
        </View>

        {/* ═══ AUTHOR ═══ */}
        <TouchableOpacity style={s.authorRow} onPress={() => router.push(`/user/${post.user_id}` as any)}>
          {post.user_profile_image ? (
            <Image source={{ uri: post.user_profile_image }} style={s.authorAvatar} />
          ) : (
            <View style={[s.authorAvatar, s.authorAvatarFb]}>
              <Text style={s.authorInit}>{authorName[0].toUpperCase()}</Text>
            </View>
          )}
          <Text style={s.authorName}>{authorName}</Text>
        </TouchableOpacity>

        {/* ═══ CAPTION ═══ */}
        {hasCaption && (
          <TouchableOpacity style={s.captionRow} onPress={() => setCaptionExpanded(!captionExpanded)}>
            <Text style={s.captionText} numberOfLines={captionExpanded ? undefined : 2}>{post.content}</Text>
            {post.content.length > 80 && (
              <View style={{ marginLeft: 8, marginTop: 2 }}>
                <Ionicons name={captionExpanded ? 'chevron-up' : 'chevron-down'} size={20} color="#111" />
              </View>
            )}
          </TouchableOpacity>
        )}

        {/* Timestamp */}
        <View style={s.timeRow}>
          <Text style={s.timeText}>{formatDistanceToNow(new Date(post.created_at), { addSuffix: true })}</Text>
        </View>

        {/* ═══ COMMENT INPUT ═══ */}
        <View style={s.commentInputRow}>
          <View style={s.commentInputAvatar}>
            {user?.profile_image ? (
              <Image source={{ uri: user.profile_image }} style={{ width: 32, height: 32, borderRadius: 16 }} />
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
            <TouchableOpacity onPress={handleComment} disabled={isCommenting} style={{ paddingRight: 4 }}>
              {isCommenting ? <ActivityIndicator size="small" color="#E60023" /> : <Ionicons name="arrow-up-circle" size={30} color="#E60023" />}
            </TouchableOpacity>
          ) : null}
        </View>

        {/* ═══ COMMENTS ═══ */}
        {showComments && comments.length > 0 && (
          <View style={s.commentsList}>
            <Text style={s.commentsHeader}>{comments.length} comment{comments.length !== 1 ? 's' : ''}</Text>
            {comments.map((c) => (
              <View key={c.id} style={s.commentItem}>
                {c.user_profile_image ? (
                  <Image source={{ uri: c.user_profile_image }} style={s.commentAvatar} />
                ) : (
                  <View style={[s.commentAvatar, s.commentAvatarFb]}>
                    <Text style={{ fontSize: 10, fontWeight: '700', color: '#999' }}>{(c.user_full_name || 'U')[0]}</Text>
                  </View>
                )}
                <View style={{ flex: 1 }}>
                  <Text style={s.commentAuthor}>{c.user_full_name || 'User'}</Text>
                  <Text style={s.commentContent}>{c.content}</Text>
                  <Text style={s.commentTime}>{formatDistanceToNow(new Date(c.created_at), { addSuffix: true })}</Text>
                </View>
              </View>
            ))}
          </View>
        )}
        {!showComments && comments.length > 0 && (
          <TouchableOpacity style={s.viewAll} onPress={() => setShowComments(true)}>
            <Text style={s.viewAllText}>View all {comments.length} comment{comments.length !== 1 ? 's' : ''}</Text>
          </TouchableOpacity>
        )}
      </ScrollView>

      {/* ═══ FULLSCREEN MODAL ═══ */}
      <Modal visible={fullscreenVisible} animationType="fade" statusBarTranslucent>
        <View style={s.fsBg}>
          <StatusBar barStyle="light-content" />
          <TouchableOpacity style={[s.fsClose, { top: insets.top + 12 }]} onPress={() => setFullscreenVisible(false)}>
            <Ionicons name="close" size={26} color="#FFF" />
          </TouchableOpacity>
          {hasVideo ? (
            <VideoPlayer hlsUrl={videoHlsUrl!} width={SW} height={SH} />
          ) : allImages.length > 0 ? (
            <ScrollView horizontal pagingEnabled showsHorizontalScrollIndicator={false} contentContainerStyle={{ alignItems: 'center' }}>
              {allImages.map((uri: string, i: number) => (
                <Image key={`fs-${i}`} source={{ uri }} style={{ width: SW, height: SH }} resizeMode="contain" />
              ))}
            </ScrollView>
          ) : null}
        </View>
      </Modal>

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
  const player = useVideoPlayer(hlsUrl, (p) => { p.loop = false; });
  return (
    <View style={{ width, height, overflow: 'hidden' }}>
      <VideoView player={player} style={{ width, height }} contentFit="cover" nativeControls />
    </View>
  );
}

/* ════════════════════════════════════════════════════════════════════════
   STYLES
   ════════════════════════════════════════════════════════════════════════ */
const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#FFF' },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#FFF' },
  goBackBtn: { backgroundColor: '#111', paddingHorizontal: 24, paddingVertical: 12, borderRadius: 24 },

  // Edge indicators
  edgeIndicator: {
    position: 'absolute', top: 0, bottom: 0, width: EDGE_INDICATOR_W,
    zIndex: 50, borderRadius: 2,
  },
  edgeIndicatorLeft: { left: 0, backgroundColor: '#E60023' },
  edgeIndicatorRight: { right: 0, backgroundColor: '#E60023' },

  // Post nav hint
  postNavHint: {
    position: 'absolute', alignSelf: 'center',
    backgroundColor: 'rgba(0,0,0,0.5)', borderRadius: 10,
    paddingHorizontal: 10, paddingVertical: 4, zIndex: 20,
  },
  postNavText: { fontSize: 11, fontWeight: '600', color: '#FFF' },

  // Image card
  imageCard: { marginHorizontal: PAD, overflow: 'hidden', backgroundColor: '#F0ECE4', position: 'relative' },
  noImgBg: { backgroundColor: '#F0ECE4', justifyContent: 'center', alignItems: 'center' },

  floatingBtn: {
    position: 'absolute', width: 44, height: 44, borderRadius: 22,
    backgroundColor: 'rgba(255,255,255,0.92)', justifyContent: 'center', alignItems: 'center',
    shadowColor: '#000', shadowOffset: { width: 0, height: 1 }, shadowOpacity: 0.08, shadowRadius: 4,
    elevation: 3, zIndex: 10,
  },

  dots: { position: 'absolute', bottom: 16, left: 0, right: 0, flexDirection: 'row', justifyContent: 'center', gap: 6 },
  dot: { width: 7, height: 7, borderRadius: 4, backgroundColor: 'rgba(255,255,255,0.45)' },
  dotActive: { backgroundColor: '#FFF', width: 20, borderRadius: 4 },

  locationRow: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingTop: 12, gap: 6 },
  locationText: { fontSize: 14, fontWeight: '600', color: '#444', flex: 1 },

  tagsRow: { paddingHorizontal: 14, paddingTop: 10, paddingBottom: 2, gap: 8 },
  tagPill: { backgroundColor: '#F0ECE4', paddingHorizontal: 16, paddingVertical: 10, borderRadius: 24 },
  tagText: { fontSize: 14, fontWeight: '600', color: '#111' },

  engageRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 14, paddingTop: 12, paddingBottom: 6 },
  engageLeft: { flexDirection: 'row', alignItems: 'center' },
  engageIcon: { padding: 4 },
  engageCount: { fontSize: 15, fontWeight: '700', color: '#111', marginLeft: 3 },
  saveBtn: { backgroundColor: '#E60023', paddingHorizontal: 22, paddingVertical: 12, borderRadius: 24 },
  saveBtnSaved: { backgroundColor: '#111' },
  saveBtnText: { fontSize: 15, fontWeight: '700', color: '#FFF' },

  authorRow: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 8 },
  authorAvatar: { width: 32, height: 32, borderRadius: 16, marginRight: 10 },
  authorAvatarFb: { backgroundColor: '#E8E4DF', justifyContent: 'center', alignItems: 'center' },
  authorInit: { color: '#888', fontSize: 14, fontWeight: '700' },
  authorName: { fontSize: 14, fontWeight: '700', color: '#111' },

  captionRow: { flexDirection: 'row', alignItems: 'flex-start', paddingHorizontal: 16, paddingTop: 2, paddingBottom: 4 },
  captionText: { flex: 1, fontSize: 20, fontWeight: '700', color: '#111', lineHeight: 26, letterSpacing: -0.3 },

  timeRow: { paddingHorizontal: 16, paddingBottom: 8 },
  timeText: { fontSize: 12, color: '#AAA' },

  commentInputRow: {
    flexDirection: 'row', alignItems: 'center', marginHorizontal: 14, marginTop: 4,
    backgroundColor: '#F5F2EC', borderRadius: 28, paddingHorizontal: 6, paddingVertical: 4,
  },
  commentInputAvatar: {
    width: 32, height: 32, borderRadius: 16, backgroundColor: '#E8E4DF',
    justifyContent: 'center', alignItems: 'center', overflow: 'hidden',
  },
  commentInputAvatarText: { color: '#999', fontSize: 12, fontWeight: '700' },
  commentInput: { flex: 1, fontSize: 14, color: '#111', paddingHorizontal: 10, paddingVertical: 10 },

  viewAll: { paddingHorizontal: 16, paddingTop: 6, paddingBottom: 10 },
  viewAllText: { fontSize: 13, color: '#999', fontWeight: '500' },
  commentsList: { paddingHorizontal: 16, paddingTop: 8 },
  commentsHeader: { fontSize: 16, fontWeight: '700', color: '#111', marginBottom: 12 },
  commentItem: { flexDirection: 'row', marginBottom: 14 },
  commentAvatar: { width: 28, height: 28, borderRadius: 14, marginRight: 10, marginTop: 2 },
  commentAvatarFb: { backgroundColor: '#E8E4DF', justifyContent: 'center', alignItems: 'center' },
  commentAuthor: { fontSize: 13, fontWeight: '700', color: '#111' },
  commentContent: { fontSize: 14, color: '#333', lineHeight: 19, marginTop: 1 },
  commentTime: { fontSize: 11, color: '#B0B0B0', marginTop: 3 },

  // Fullscreen
  fsBg: { flex: 1, backgroundColor: '#000', justifyContent: 'center', alignItems: 'center' },
  fsClose: {
    position: 'absolute', left: 16, width: 44, height: 44, borderRadius: 22,
    backgroundColor: 'rgba(255,255,255,0.15)', justifyContent: 'center', alignItems: 'center', zIndex: 10,
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
  quickSaveIcon: { width: 44, height: 44, borderRadius: 14, backgroundColor: '#E60023', justifyContent: 'center', alignItems: 'center' },
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
  createBtn: { backgroundColor: '#E60023', paddingHorizontal: 20, paddingVertical: 12, borderRadius: 20 },
  createBtnText: { fontSize: 14, fontWeight: '700', color: '#FFF' },
  createColBtn: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 14, borderTopWidth: 1, borderTopColor: '#F0EDE7', marginTop: 4 },
  createColText: { fontSize: 15, fontWeight: '600', color: '#111' },
  unsaveBtn: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 14, borderTopWidth: 1, borderTopColor: '#F0EDE7', marginTop: 4 },
  unsaveBtnText: { fontSize: 15, fontWeight: '600', color: '#DC2626' },
});
