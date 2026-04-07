import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ActivityIndicator,
  TextInput, Dimensions, KeyboardAvoidingView, Platform, Share, Modal,
  ScrollView, StatusBar, FlatList, Animated,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useVideoPlayer, VideoView } from 'expo-video';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';
import { isCFStreamVideo, extractStreamUid, getStreamPlaybackInfo } from '../../src/utils/mediaUpload';
import { formatDistanceToNow } from 'date-fns';

const { width: SCREEN_W, height: SCREEN_H } = Dimensions.get('window');
const CONTENT_PAD = 4;
const IMG_WIDTH = SCREEN_W - CONTENT_PAD * 2;
const RADIUS = 20;

export default function PostDetailScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { id: postId } = useLocalSearchParams<{ id: string }>();
  const { user } = useAuthStore();

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
  const [videoThumbnail, setVideoThumbnail] = useState<string | null>(null);
  const [showComments, setShowComments] = useState(false);
  const [imgAspect, setImgAspect] = useState(1.25);
  const [captionExpanded, setCaptionExpanded] = useState(false);

  // Fullscreen modal
  const [fullscreenVisible, setFullscreenVisible] = useState(false);

  // Save modal
  const [saveModalVisible, setSaveModalVisible] = useState(false);
  const [collections, setCollections] = useState<any[]>([]);
  const [newCollectionName, setNewCollectionName] = useState('');
  const [isCreatingCollection, setIsCreatingCollection] = useState(false);

  useEffect(() => { if (postId) loadPostData(); }, [postId]);

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
      } catch {}

      // Load collections
      try {
        const colRes = await api.get('/library/collections');
        setCollections(colRes.data || []);
      } catch {}

      // Resolve video info
      const allMedia: string[] = p.images?.length > 0 ? p.images : p.image ? [p.image] : [];
      const mediaTypes: string[] = p.media_types || [];
      let hasVideoMedia = false;

      for (let i = 0; i < allMedia.length; i++) {
        if (isCFStreamVideo(allMedia[i]) || mediaTypes[i] === 'video') {
          hasVideoMedia = true;
          const uid = extractStreamUid(allMedia[i]);
          if (uid) {
            try {
              const info = await getStreamPlaybackInfo(uid);
              if (info?.hls) setVideoHlsUrl(info.hls);
              if (info?.thumbnail) setVideoThumbnail(info.thumbnail);
            } catch (e) { console.log('Video info error:', e); }
          }
        }
      }

      // Get natural image dimensions
      const imageUrls = allMedia.filter((u: string) => !isCFStreamVideo(u) && (u.startsWith('http') || u.startsWith('data:')));
      if (imageUrls.length > 0) {
        Image.getSize(imageUrls[0], (w, h) => {
          if (w > 0 && h > 0) {
            const ratio = h / w;
            setImgAspect(Math.min(Math.max(ratio, 0.6), 1.8));
          }
        }, () => {});
      } else if (hasVideoMedia) {
        setImgAspect(1.0);
      }
    } catch (error) {
      console.log('Error loading post:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleLike = async () => {
    setLiked(!liked);
    setLikesCount(liked ? likesCount - 1 : likesCount + 1);
    try { await api.post(`/posts/${postId}/like`); }
    catch { setLiked(liked); setLikesCount(likesCount); }
  };

  const handleSaveToCollection = async (collection: string) => {
    setSaved(true);
    setSavedCollection(collection);
    setSaveModalVisible(false);
    try {
      await api.post('/bookmarks', { post_id: postId, collection });
    } catch {
      // Try library endpoint as fallback
      try {
        await api.post(`/library/save/${postId}`, { collection });
      } catch { setSaved(false); }
    }
  };

  const handleUnsave = async () => {
    setSaved(false);
    setSavedCollection('');
    setSaveModalVisible(false);
    try {
      await api.delete(`/bookmarks/${postId}`);
    } catch {
      try { await api.delete(`/library/save/${postId}`); }
      catch { setSaved(true); }
    }
  };

  const handleSavePress = () => {
    if (saved) {
      // Show modal with option to unsave
      setSaveModalVisible(true);
    } else {
      setSaveModalVisible(true);
    }
  };

  const handleComment = async () => {
    if (!newComment.trim() || isCommenting) return;
    setIsCommenting(true);
    try {
      const res = await api.post(`/posts/${postId}/comments`, { content: newComment.trim() });
      setComments([...comments, res.data]);
      setNewComment('');
    } catch {} finally { setIsCommenting(false); }
  };

  const handleShare = async () => {
    try { await Share.share({ message: post?.content || 'Check this out on Flames-Up!' }); } catch {}
  };

  const formatCount = (n: number) => {
    if (!n) return '';
    if (n >= 1000) return (n / 1000).toFixed(1).replace('.0', '') + 'k';
    return String(n);
  };

  // ── Loading state ──
  if (isLoading) {
    return (
      <View style={s.loadingContainer}>
        <StatusBar barStyle="dark-content" />
        <ActivityIndicator size="large" color="#111" />
      </View>
    );
  }

  if (!post) {
    return (
      <View style={s.loadingContainer}>
        <StatusBar barStyle="dark-content" />
        <Text style={{ color: '#999', fontSize: 16, marginBottom: 16 }}>Post not found</Text>
        <TouchableOpacity onPress={() => router.back()} style={s.goBackBtn}>
          <Text style={{ color: '#FFF', fontWeight: '700' }}>Go Back</Text>
        </TouchableOpacity>
      </View>
    );
  }

  const authorName = post.user_full_name || post.user_username || 'User';
  const allImages: string[] = post.images?.length > 0
    ? post.images.filter((u: string) => !isCFStreamVideo(u) && (u.startsWith('http') || u.startsWith('data:')))
    : post.image && !isCFStreamVideo(post.image) && (post.image.startsWith('http') || post.image.startsWith('data:'))
      ? [post.image] : [];
  const hasVideo = !!videoHlsUrl;
  const locationName = post.place_name || post.location || '';
  const tags = [post.post_type, post.category].filter(Boolean);
  const hasCaption = !!post.content?.trim();
  const dynamicImgH = IMG_WIDTH * imgAspect;

  return (
    <View style={[s.root, { paddingTop: insets.top }]}>
      <StatusBar barStyle="dark-content" />
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView
          showsVerticalScrollIndicator={false}
          contentContainerStyle={{ paddingBottom: insets.bottom + 30 }}
          bounces
          keyboardShouldPersistTaps="handled"
        >
          {/* ═══ IMAGE / VIDEO CARD ═══ */}
          <TouchableOpacity
            activeOpacity={0.95}
            onPress={() => setFullscreenVisible(true)}
            style={[s.imageCard, { borderRadius: RADIUS }]}
          >
            {allImages.length > 0 ? (
              allImages.length > 1 ? (
                <ScrollView
                  horizontal pagingEnabled showsHorizontalScrollIndicator={false}
                  onMomentumScrollEnd={(e) => setActiveImgIdx(Math.round(e.nativeEvent.contentOffset.x / IMG_WIDTH))}
                >
                  {allImages.map((uri: string, i: number) => (
                    <Image key={`img-${i}`} source={{ uri }} style={{ width: IMG_WIDTH, height: dynamicImgH }} resizeMode="cover" />
                  ))}
                </ScrollView>
              ) : (
                <Image source={{ uri: allImages[0] }} style={{ width: IMG_WIDTH, height: dynamicImgH }} resizeMode="cover" />
              )
            ) : hasVideo ? (
              <VideoPlayer hlsUrl={videoHlsUrl!} width={IMG_WIDTH} height={dynamicImgH} />
            ) : (
              <View style={[{ width: IMG_WIDTH, height: SCREEN_W }, s.noImgBg]}>
                <Ionicons name="image-outline" size={56} color="#D4D0C8" />
              </View>
            )}

            {/* Floating Back Button */}
            <TouchableOpacity
              style={[s.floatingBtn, { top: 12, left: 12 }]}
              onPress={(e) => { e.stopPropagation?.(); router.back(); }}
              activeOpacity={0.8}
            >
              <Ionicons name="chevron-back" size={22} color="#111" />
            </TouchableOpacity>

            {/* Fullscreen hint */}
            <TouchableOpacity
              style={[s.floatingBtn, { bottom: 14, right: 14 }]}
              onPress={(e) => { e.stopPropagation?.(); setFullscreenVisible(true); }}
              activeOpacity={0.8}
            >
              <Ionicons name="expand-outline" size={20} color="#111" />
            </TouchableOpacity>

            {/* Carousel Dots */}
            {allImages.length > 1 && (
              <View style={s.dots}>
                {allImages.map((_: string, i: number) => (
                  <View key={i} style={[s.dot, activeImgIdx === i && s.dotActive]} />
                ))}
              </View>
            )}
          </TouchableOpacity>

          {/* ═══ LOCATION PILL ═══ */}
          {locationName ? (
            <View style={s.locationRow}>
              <Ionicons name="location-sharp" size={16} color="#E60023" />
              <Text style={s.locationText} numberOfLines={1}>{locationName}</Text>
            </View>
          ) : null}

          {/* ═══ TAG PILLS ═══ */}
          {tags.length > 0 && (
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.tagsRow}>
              {tags.map((tag, i) => (
                <View key={i} style={s.tagPill}>
                  <Text style={s.tagText}>{tag}</Text>
                </View>
              ))}
            </ScrollView>
          )}

          {/* ═══ ENGAGEMENT ROW ═══ */}
          <View style={s.engageRow}>
            <View style={s.engageLeft}>
              <TouchableOpacity onPress={handleLike} style={s.engageIcon} activeOpacity={0.7}>
                <Ionicons name={liked ? 'heart' : 'heart-outline'} size={26} color={liked ? '#E60023' : '#111'} />
              </TouchableOpacity>
              {likesCount > 0 && <Text style={s.engageCount}>{formatCount(likesCount)}</Text>}

              <TouchableOpacity style={[s.engageIcon, { marginLeft: 14 }]} onPress={() => setShowComments(!showComments)} activeOpacity={0.7}>
                <Ionicons name="chatbubble-outline" size={22} color="#111" />
              </TouchableOpacity>
              {comments.length > 0 && <Text style={s.engageCount}>{comments.length}</Text>}

              <TouchableOpacity style={[s.engageIcon, { marginLeft: 14 }]} onPress={handleShare} activeOpacity={0.7}>
                <Ionicons name="arrow-up-outline" size={24} color="#111" />
              </TouchableOpacity>

              <TouchableOpacity style={[s.engageIcon, { marginLeft: 14 }]} activeOpacity={0.7}>
                <Ionicons name="ellipsis-horizontal" size={24} color="#111" />
              </TouchableOpacity>
            </View>

            {/* Save Button (red pill) */}
            <TouchableOpacity
              style={[s.saveBtn, saved && s.saveBtnSaved]}
              onPress={handleSavePress}
              activeOpacity={0.85}
            >
              <Text style={s.saveBtnText}>{saved ? 'Saved' : 'Save'}</Text>
            </TouchableOpacity>
          </View>

          {/* ═══ AUTHOR ROW ═══ */}
          <TouchableOpacity style={s.authorRow} onPress={() => router.push(`/user/${post.user_id}` as any)} activeOpacity={0.7}>
            {post.user_profile_image ? (
              <Image source={{ uri: post.user_profile_image }} style={s.authorAvatar} />
            ) : (
              <View style={[s.authorAvatar, s.authorAvatarFallback]}>
                <Text style={s.authorAvatarInit}>{authorName[0].toUpperCase()}</Text>
              </View>
            )}
            <Text style={s.authorName}>{authorName}</Text>
          </TouchableOpacity>

          {/* ═══ CAPTION ═══ */}
          {hasCaption && (
            <TouchableOpacity style={s.captionRow} onPress={() => setCaptionExpanded(!captionExpanded)} activeOpacity={0.8}>
              <Text style={s.captionText} numberOfLines={captionExpanded ? undefined : 2}>
                {post.content}
              </Text>
              {post.content.length > 80 && (
                <View style={s.captionChevron}>
                  <Ionicons name={captionExpanded ? 'chevron-up' : 'chevron-down'} size={20} color="#111" />
                </View>
              )}
            </TouchableOpacity>
          )}

          {/* ═══ TIME STAMP ═══ */}
          <View style={s.timeRow}>
            <Text style={s.timeText}>
              {formatDistanceToNow(new Date(post.created_at), { addSuffix: true })}
            </Text>
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
              <TouchableOpacity onPress={handleComment} disabled={isCommenting} style={s.sendBtn}>
                {isCommenting ? <ActivityIndicator size="small" color="#E60023" /> : <Ionicons name="arrow-up-circle" size={30} color="#E60023" />}
              </TouchableOpacity>
            ) : null}
          </View>

          {/* ═══ COMMENTS LIST ═══ */}
          {showComments && comments.length > 0 && (
            <View style={s.commentsList}>
              <Text style={s.commentsHeader}>{comments.length} comment{comments.length !== 1 ? 's' : ''}</Text>
              {comments.map((c) => (
                <View key={c.id} style={s.commentItem}>
                  {c.user_profile_image ? (
                    <Image source={{ uri: c.user_profile_image }} style={s.commentAvatar} />
                  ) : (
                    <View style={[s.commentAvatar, s.commentAvatarFallback]}>
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
            <TouchableOpacity style={s.viewAllComments} onPress={() => setShowComments(true)}>
              <Text style={s.viewAllCommentsText}>View all {comments.length} comment{comments.length !== 1 ? 's' : ''}</Text>
            </TouchableOpacity>
          )}
        </ScrollView>
      </KeyboardAvoidingView>

      {/* ═══════════════════════════════════════════════════
          FULLSCREEN MODAL
          ═══════════════════════════════════════════════════ */}
      <Modal visible={fullscreenVisible} animationType="fade" statusBarTranslucent>
        <View style={s.fullscreenBg}>
          <StatusBar barStyle="light-content" />
          <TouchableOpacity
            style={[s.fullscreenClose, { top: insets.top + 12 }]}
            onPress={() => setFullscreenVisible(false)}
            activeOpacity={0.8}
          >
            <Ionicons name="close" size={26} color="#FFF" />
          </TouchableOpacity>

          {hasVideo ? (
            <VideoPlayer hlsUrl={videoHlsUrl!} width={SCREEN_W} height={SCREEN_H} />
          ) : allImages.length > 0 ? (
            <ScrollView
              horizontal pagingEnabled
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={{ alignItems: 'center' }}
            >
              {allImages.map((uri: string, i: number) => (
                <Image
                  key={`fs-${i}`}
                  source={{ uri }}
                  style={{ width: SCREEN_W, height: SCREEN_H }}
                  resizeMode="contain"
                />
              ))}
            </ScrollView>
          ) : null}
        </View>
      </Modal>

      {/* ═══════════════════════════════════════════════════
          SAVE TO COLLECTION MODAL (Pinterest-style bottom sheet)
          ═══════════════════════════════════════════════════ */}
      <Modal visible={saveModalVisible} transparent animationType="slide">
        <TouchableOpacity
          style={s.modalOverlay}
          activeOpacity={1}
          onPress={() => setSaveModalVisible(false)}
        >
          <View />
        </TouchableOpacity>
        <View style={[s.saveModal, { paddingBottom: insets.bottom + 16 }]}>
          {/* Drag handle */}
          <View style={s.modalHandle} />
          <Text style={s.modalTitle}>{saved ? 'Saved to collection' : 'Save to collection'}</Text>

          {/* Quick save */}
          {!saved && (
            <TouchableOpacity
              style={s.quickSaveRow}
              onPress={() => handleSaveToCollection('My Library')}
              activeOpacity={0.8}
            >
              <View style={s.quickSaveIcon}>
                <Ionicons name="bookmark" size={20} color="#FFF" />
              </View>
              <View style={{ flex: 1 }}>
                <Text style={s.quickSaveTitle}>My Library</Text>
                <Text style={s.quickSaveDesc}>Quick save</Text>
              </View>
              <Ionicons name="chevron-forward" size={20} color="#CCC" />
            </TouchableOpacity>
          )}

          {/* Existing collections */}
          {collections.length > 0 && (
            <View style={s.collectionsSection}>
              <Text style={s.collectionsSectionTitle}>Your Collections</Text>
              {collections.map((col: any, idx: number) => (
                <TouchableOpacity
                  key={idx}
                  style={s.collectionItem}
                  onPress={() => handleSaveToCollection(col.collection)}
                  activeOpacity={0.8}
                >
                  <View style={[s.collectionIcon, { backgroundColor: ['#F3ECFF', '#FEE2E2', '#DBEAFE', '#D1FAE5'][idx % 4] }]}>
                    <Ionicons name="folder" size={18} color={['#7C3AED', '#DC2626', '#2563EB', '#059669'][idx % 4]} />
                  </View>
                  <View style={{ flex: 1 }}>
                    <Text style={s.collectionName}>{col.collection}</Text>
                    <Text style={s.collectionCount}>{col.count} item{col.count !== 1 ? 's' : ''}</Text>
                  </View>
                  {savedCollection === col.collection && <Ionicons name="checkmark-circle" size={22} color="#059669" />}
                </TouchableOpacity>
              ))}
            </View>
          )}

          {/* Create new collection */}
          {isCreatingCollection ? (
            <View style={s.newCollectionRow}>
              <TextInput
                style={s.newCollectionInput}
                placeholder="Collection name"
                placeholderTextColor="#CCC"
                value={newCollectionName}
                onChangeText={setNewCollectionName}
                autoFocus
              />
              <TouchableOpacity
                style={[s.createColBtn, !newCollectionName.trim() && { opacity: 0.4 }]}
                onPress={() => {
                  if (newCollectionName.trim()) {
                    handleSaveToCollection(newCollectionName.trim());
                    setNewCollectionName('');
                    setIsCreatingCollection(false);
                  }
                }}
                disabled={!newCollectionName.trim()}
              >
                <Text style={s.createColBtnText}>Save</Text>
              </TouchableOpacity>
            </View>
          ) : (
            <TouchableOpacity
              style={s.createCollectionBtn}
              onPress={() => setIsCreatingCollection(true)}
              activeOpacity={0.8}
            >
              <Ionicons name="add-circle-outline" size={22} color="#111" />
              <Text style={s.createCollectionText}>Create collection</Text>
            </TouchableOpacity>
          )}

          {/* Unsave option */}
          {saved && (
            <TouchableOpacity style={s.unsaveBtn} onPress={handleUnsave} activeOpacity={0.8}>
              <Ionicons name="bookmark-outline" size={20} color="#DC2626" />
              <Text style={s.unsaveBtnText}>Remove from saved</Text>
            </TouchableOpacity>
          )}
        </View>
      </Modal>
    </View>
  );
}

/* ═══════════════════════════════════════════════════════════════
   VIDEO PLAYER
   ═══════════════════════════════════════════════════════════════ */
function VideoPlayer({ hlsUrl, width, height }: { hlsUrl: string; width: number; height: number }) {
  const player = useVideoPlayer(hlsUrl, (p) => {
    p.loop = false;
  });

  return (
    <View style={{ width, height, backgroundColor: '#000' }}>
      <VideoView player={player} style={{ width, height }} nativeControls />
    </View>
  );
}

/* ═══════════════════════════════════════════════════════════════
   STYLES
   ═══════════════════════════════════════════════════════════════ */
const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#FFFFFF' },
  loadingContainer: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#FFFFFF' },
  goBackBtn: { backgroundColor: '#111', paddingHorizontal: 24, paddingVertical: 12, borderRadius: 24 },

  imageCard: { marginHorizontal: CONTENT_PAD, overflow: 'hidden', backgroundColor: '#F0ECE4', position: 'relative' },
  noImgBg: { backgroundColor: '#F0ECE4', justifyContent: 'center', alignItems: 'center' },

  floatingBtn: {
    position: 'absolute', width: 44, height: 44, borderRadius: 22,
    backgroundColor: 'rgba(255,255,255,0.92)', justifyContent: 'center', alignItems: 'center',
    shadowColor: '#000', shadowOffset: { width: 0, height: 1 }, shadowOpacity: 0.08, shadowRadius: 4, elevation: 3, zIndex: 10,
  },

  dots: { position: 'absolute', bottom: 16, left: 0, right: 0, flexDirection: 'row', justifyContent: 'center', gap: 6 },
  dot: { width: 7, height: 7, borderRadius: 4, backgroundColor: 'rgba(255,255,255,0.45)' },
  dotActive: { backgroundColor: '#FFFFFF', width: 20, borderRadius: 4 },

  // Location
  locationRow: {
    flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingTop: 12, gap: 6,
  },
  locationText: { fontSize: 14, fontWeight: '600', color: '#444', flex: 1 },

  // Tags
  tagsRow: { paddingHorizontal: 14, paddingTop: 10, paddingBottom: 2, gap: 8 },
  tagPill: { backgroundColor: '#F0ECE4', paddingHorizontal: 16, paddingVertical: 10, borderRadius: 24 },
  tagText: { fontSize: 14, fontWeight: '600', color: '#111' },

  // Engagement
  engageRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 14, paddingTop: 12, paddingBottom: 6 },
  engageLeft: { flexDirection: 'row', alignItems: 'center' },
  engageIcon: { padding: 4 },
  engageCount: { fontSize: 15, fontWeight: '700', color: '#111', marginLeft: 3 },
  saveBtn: { backgroundColor: '#E60023', paddingHorizontal: 22, paddingVertical: 12, borderRadius: 24 },
  saveBtnSaved: { backgroundColor: '#111' },
  saveBtnText: { fontSize: 15, fontWeight: '700', color: '#FFFFFF' },

  // Author
  authorRow: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 8 },
  authorAvatar: { width: 32, height: 32, borderRadius: 16, marginRight: 10 },
  authorAvatarFallback: { backgroundColor: '#E8E4DF', justifyContent: 'center', alignItems: 'center' },
  authorAvatarInit: { color: '#888', fontSize: 14, fontWeight: '700' },
  authorName: { fontSize: 14, fontWeight: '700', color: '#111' },

  // Caption
  captionRow: { flexDirection: 'row', alignItems: 'flex-start', paddingHorizontal: 16, paddingTop: 2, paddingBottom: 4 },
  captionText: { flex: 1, fontSize: 20, fontWeight: '700', color: '#111', lineHeight: 26, letterSpacing: -0.3 },
  captionChevron: { marginLeft: 8, marginTop: 2 },

  // Timestamp
  timeRow: { paddingHorizontal: 16, paddingBottom: 8 },
  timeText: { fontSize: 12, color: '#AAA' },

  // Comment Input
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
  sendBtn: { paddingRight: 4 },

  // Comments
  viewAllComments: { paddingHorizontal: 16, paddingTop: 6, paddingBottom: 10 },
  viewAllCommentsText: { fontSize: 13, color: '#999', fontWeight: '500' },
  commentsList: { paddingHorizontal: 16, paddingTop: 8 },
  commentsHeader: { fontSize: 16, fontWeight: '700', color: '#111', marginBottom: 12 },
  commentItem: { flexDirection: 'row', marginBottom: 14 },
  commentAvatar: { width: 28, height: 28, borderRadius: 14, marginRight: 10, marginTop: 2 },
  commentAvatarFallback: { backgroundColor: '#E8E4DF', justifyContent: 'center', alignItems: 'center' },
  commentAuthor: { fontSize: 13, fontWeight: '700', color: '#111' },
  commentContent: { fontSize: 14, color: '#333', lineHeight: 19, marginTop: 1 },
  commentTime: { fontSize: 11, color: '#B0B0B0', marginTop: 3 },

  // Fullscreen
  fullscreenBg: { flex: 1, backgroundColor: '#000', justifyContent: 'center', alignItems: 'center' },
  fullscreenClose: {
    position: 'absolute', left: 16, width: 44, height: 44, borderRadius: 22,
    backgroundColor: 'rgba(255,255,255,0.15)', justifyContent: 'center', alignItems: 'center', zIndex: 10,
  },

  // Save Modal
  modalOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.4)' },
  saveModal: {
    backgroundColor: '#FFF', borderTopLeftRadius: 24, borderTopRightRadius: 24,
    paddingHorizontal: 20, paddingTop: 12, maxHeight: SCREEN_H * 0.6,
  },
  modalHandle: {
    width: 40, height: 4, borderRadius: 2, backgroundColor: '#E0DDD8',
    alignSelf: 'center', marginBottom: 16,
  },
  modalTitle: { fontSize: 18, fontWeight: '800', color: '#111', marginBottom: 16 },

  quickSaveRow: {
    flexDirection: 'row', alignItems: 'center', paddingVertical: 14, gap: 12,
    borderBottomWidth: 1, borderBottomColor: '#F0EDE7',
  },
  quickSaveIcon: {
    width: 44, height: 44, borderRadius: 14, backgroundColor: '#E60023',
    justifyContent: 'center', alignItems: 'center',
  },
  quickSaveTitle: { fontSize: 16, fontWeight: '700', color: '#111' },
  quickSaveDesc: { fontSize: 13, color: '#999', marginTop: 1 },

  collectionsSection: { paddingTop: 12 },
  collectionsSectionTitle: { fontSize: 12, fontWeight: '700', color: '#999', letterSpacing: 1, textTransform: 'uppercase', marginBottom: 10 },
  collectionItem: {
    flexDirection: 'row', alignItems: 'center', paddingVertical: 12, gap: 12,
    borderBottomWidth: 1, borderBottomColor: '#F5F2EC',
  },
  collectionIcon: {
    width: 40, height: 40, borderRadius: 12, justifyContent: 'center', alignItems: 'center',
  },
  collectionName: { fontSize: 15, fontWeight: '600', color: '#111' },
  collectionCount: { fontSize: 12, color: '#999', marginTop: 1 },

  newCollectionRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 12 },
  newCollectionInput: {
    flex: 1, backgroundColor: '#F5F2EC', borderRadius: 14,
    paddingHorizontal: 14, paddingVertical: 12, fontSize: 15, color: '#111',
  },
  createColBtn: { backgroundColor: '#E60023', paddingHorizontal: 20, paddingVertical: 12, borderRadius: 20 },
  createColBtnText: { fontSize: 14, fontWeight: '700', color: '#FFF' },

  createCollectionBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    paddingVertical: 14, borderTopWidth: 1, borderTopColor: '#F0EDE7', marginTop: 4,
  },
  createCollectionText: { fontSize: 15, fontWeight: '600', color: '#111' },

  unsaveBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    paddingVertical: 14, borderTopWidth: 1, borderTopColor: '#F0EDE7', marginTop: 4,
  },
  unsaveBtnText: { fontSize: 15, fontWeight: '600', color: '#DC2626' },
});
