import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ActivityIndicator,
  TextInput, Dimensions, KeyboardAvoidingView, Platform, Share,
  ScrollView, StatusBar,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useVideoPlayer, VideoView } from 'expo-video';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';
import { isCFStreamVideo, extractStreamUid, getStreamPlaybackInfo, getStreamEmbedUrl } from '../../src/utils/mediaUpload';
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
  const [activeImgIdx, setActiveImgIdx] = useState(0);
  const [videoHlsUrl, setVideoHlsUrl] = useState<string | null>(null);
  const [videoThumbnail, setVideoThumbnail] = useState<string | null>(null);
  const [showComments, setShowComments] = useState(false);
  const [imgAspect, setImgAspect] = useState(1.25); // default aspect ratio (h/w)
  const [captionExpanded, setCaptionExpanded] = useState(false);

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
      } catch {}

      // Resolve image aspect ratio
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
              if (info?.hls) {
                setVideoHlsUrl(info.hls);
              }
              if (info?.thumbnail) {
                setVideoThumbnail(info.thumbnail);
              }
            } catch (e) {
              console.log('Video info error:', e);
            }
          }
        }
      }

      // Get natural image dimensions for proper aspect ratio
      const imageUrls = allMedia.filter((u: string) => !isCFStreamVideo(u) && (u.startsWith('http') || u.startsWith('data:')));
      if (imageUrls.length > 0) {
        Image.getSize(
          imageUrls[0],
          (w, h) => {
            if (w > 0 && h > 0) {
              const ratio = h / w;
              // Clamp between 0.6 (wide landscape) and 1.8 (very tall portrait)
              const clamped = Math.min(Math.max(ratio, 0.6), 1.8);
              setImgAspect(clamped);
            }
          },
          () => {} // fallback to default aspect
        );
      } else if (hasVideoMedia) {
        setImgAspect(1.0); // 1:1 default for video
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

  const handleSave = async () => {
    const ns = !saved;
    setSaved(ns);
    try {
      if (ns) await api.post('/bookmarks', { post_id: postId, collection: 'saved' });
      else await api.delete(`/bookmarks/${postId}`);
    } catch { setSaved(!ns); }
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

  // ── Not found ──
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
  const tags = [post.post_type, post.category, post.location].filter(Boolean);
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
          {/* ═══════════════════════════════════════════════════
              IMAGE / VIDEO CARD — Dynamic aspect ratio
              ═══════════════════════════════════════════════════ */}
          <View style={[s.imageCard, { borderRadius: RADIUS }]}>
            {allImages.length > 0 ? (
              allImages.length > 1 ? (
                <ScrollView
                  horizontal
                  pagingEnabled
                  showsHorizontalScrollIndicator={false}
                  onMomentumScrollEnd={(e) => setActiveImgIdx(Math.round(e.nativeEvent.contentOffset.x / IMG_WIDTH))}
                >
                  {allImages.map((uri: string, i: number) => (
                    <Image
                      key={`img-${i}`}
                      source={{ uri }}
                      style={{ width: IMG_WIDTH, height: dynamicImgH }}
                      resizeMode="cover"
                    />
                  ))}
                </ScrollView>
              ) : (
                <Image
                  source={{ uri: allImages[0] }}
                  style={{ width: IMG_WIDTH, height: dynamicImgH }}
                  resizeMode="cover"
                />
              )
            ) : hasVideo ? (
              <VideoPlayer hlsUrl={videoHlsUrl!} width={IMG_WIDTH} height={dynamicImgH} thumbnail={videoThumbnail} />
            ) : (
              <View style={[{ width: IMG_WIDTH, height: SCREEN_W }, s.noImgBg]}>
                <Ionicons name="image-outline" size={56} color="#D4D0C8" />
              </View>
            )}

            {/* ── Floating Back Button (white circle, top-left) ── */}
            <TouchableOpacity
              style={[s.floatingBtn, { top: 12, left: 12 }]}
              onPress={() => router.back()}
              activeOpacity={0.8}
            >
              <Ionicons name="chevron-back" size={22} color="#111" />
            </TouchableOpacity>

            {/* ── Floating Visual Search Button (bottom-right) ── */}
            <TouchableOpacity
              style={[s.floatingBtn, { bottom: 14, right: 14 }]}
              activeOpacity={0.8}
            >
              <Ionicons name="scan-outline" size={20} color="#111" />
            </TouchableOpacity>

            {/* ── Carousel Dots ── */}
            {allImages.length > 1 && (
              <View style={s.dots}>
                {allImages.map((_: string, i: number) => (
                  <View key={i} style={[s.dot, activeImgIdx === i && s.dotActive]} />
                ))}
              </View>
            )}
          </View>

          {/* ═══════════════════════════════════════════════════
              TAG PILLS — Horizontal scroll (Pinterest style)
              ═══════════════════════════════════════════════════ */}
          {tags.length > 0 && (
            <ScrollView
              horizontal
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={s.tagsRow}
            >
              {tags.map((tag, i) => (
                <View key={i} style={s.tagPill}>
                  <Text style={s.tagText}>{tag}</Text>
                </View>
              ))}
            </ScrollView>
          )}

          {/* ═══════════════════════════════════════════════════
              ENGAGEMENT ROW — Heart, Comment, Share, More | Save
              ═══════════════════════════════════════════════════ */}
          <View style={s.engageRow}>
            <View style={s.engageLeft}>
              {/* Heart */}
              <TouchableOpacity onPress={handleLike} style={s.engageIcon} activeOpacity={0.7}>
                <Ionicons
                  name={liked ? 'heart' : 'heart-outline'}
                  size={26}
                  color={liked ? '#111' : '#111'}
                />
              </TouchableOpacity>
              {likesCount > 0 && <Text style={s.engageCount}>{formatCount(likesCount)}</Text>}

              {/* Comment */}
              <TouchableOpacity
                style={[s.engageIcon, { marginLeft: 14 }]}
                onPress={() => setShowComments(!showComments)}
                activeOpacity={0.7}
              >
                <Ionicons name="chatbubble-outline" size={22} color="#111" />
              </TouchableOpacity>
              {comments.length > 0 && <Text style={s.engageCount}>{comments.length}</Text>}

              {/* Share */}
              <TouchableOpacity
                style={[s.engageIcon, { marginLeft: 14 }]}
                onPress={handleShare}
                activeOpacity={0.7}
              >
                <Ionicons name="arrow-up-outline" size={24} color="#111" style={{ transform: [{ rotate: '0deg' }] }} />
              </TouchableOpacity>

              {/* More */}
              <TouchableOpacity style={[s.engageIcon, { marginLeft: 14 }]} activeOpacity={0.7}>
                <Ionicons name="ellipsis-horizontal" size={24} color="#111" />
              </TouchableOpacity>
            </View>

            {/* Save Button (red pill) */}
            <TouchableOpacity
              style={[s.saveBtn, saved && s.saveBtnSaved]}
              onPress={handleSave}
              activeOpacity={0.85}
            >
              <Text style={s.saveBtnText}>{saved ? 'Saved' : 'Save'}</Text>
            </TouchableOpacity>
          </View>

          {/* ═══════════════════════════════════════════════════
              AUTHOR ROW — Avatar + Name
              ═══════════════════════════════════════════════════ */}
          <TouchableOpacity
            style={s.authorRow}
            onPress={() => router.push(`/user/${post.user_id}` as any)}
            activeOpacity={0.7}
          >
            {post.user_profile_image ? (
              <Image source={{ uri: post.user_profile_image }} style={s.authorAvatar} />
            ) : (
              <View style={[s.authorAvatar, s.authorAvatarFallback]}>
                <Text style={s.authorAvatarInit}>{authorName[0].toUpperCase()}</Text>
              </View>
            )}
            <Text style={s.authorName}>{authorName}</Text>
          </TouchableOpacity>

          {/* ═══════════════════════════════════════════════════
              CAPTION / TITLE — with expand chevron
              ═══════════════════════════════════════════════════ */}
          {hasCaption && (
            <TouchableOpacity
              style={s.captionRow}
              onPress={() => setCaptionExpanded(!captionExpanded)}
              activeOpacity={0.8}
            >
              <Text
                style={s.captionText}
                numberOfLines={captionExpanded ? undefined : 2}
              >
                {post.content}
              </Text>
              {post.content.length > 80 && (
                <View style={s.captionChevron}>
                  <Ionicons
                    name={captionExpanded ? 'chevron-up' : 'chevron-down'}
                    size={20}
                    color="#111"
                  />
                </View>
              )}
            </TouchableOpacity>
          )}

          {/* ═══════════════════════════════════════════════════
              COMMENT INPUT
              ═══════════════════════════════════════════════════ */}
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
                {isCommenting ? (
                  <ActivityIndicator size="small" color="#E60023" />
                ) : (
                  <Ionicons name="arrow-up-circle" size={30} color="#E60023" />
                )}
              </TouchableOpacity>
            ) : null}
          </View>

          {/* ═══════════════════════════════════════════════════
              COMMENTS LIST
              ═══════════════════════════════════════════════════ */}
          {showComments && comments.length > 0 && (
            <View style={s.commentsList}>
              <Text style={s.commentsHeader}>
                {comments.length} comment{comments.length !== 1 ? 's' : ''}
              </Text>
              {comments.map((c) => (
                <View key={c.id} style={s.commentItem}>
                  {c.user_profile_image ? (
                    <Image source={{ uri: c.user_profile_image }} style={s.commentAvatar} />
                  ) : (
                    <View style={[s.commentAvatar, s.commentAvatarFallback]}>
                      <Text style={{ fontSize: 10, fontWeight: '700', color: '#999' }}>
                        {(c.user_full_name || 'U')[0]}
                      </Text>
                    </View>
                  )}
                  <View style={{ flex: 1 }}>
                    <Text style={s.commentAuthor}>{c.user_full_name || 'User'}</Text>
                    <Text style={s.commentContent}>{c.content}</Text>
                    <Text style={s.commentTime}>
                      {formatDistanceToNow(new Date(c.created_at), { addSuffix: true })}
                    </Text>
                  </View>
                </View>
              ))}
            </View>
          )}

          {!showComments && comments.length > 0 && (
            <TouchableOpacity style={s.viewAllComments} onPress={() => setShowComments(true)}>
              <Text style={s.viewAllCommentsText}>
                View all {comments.length} comment{comments.length !== 1 ? 's' : ''}
              </Text>
            </TouchableOpacity>
          )}
        </ScrollView>
      </KeyboardAvoidingView>
    </View>
  );
}

/* ═══════════════════════════════════════════════════════════════
   VIDEO PLAYER — Cloudflare Stream HLS
   ═══════════════════════════════════════════════════════════════ */
function VideoPlayer({ hlsUrl, width, height, thumbnail }: { hlsUrl: string; width: number; height: number; thumbnail?: string | null }) {
  const player = useVideoPlayer(hlsUrl, (p) => {
    p.loop = false;
  });

  return (
    <View style={{ width, height, backgroundColor: '#000' }}>
      <VideoView
        player={player}
        style={{ width, height }}
        nativeControls
      />
    </View>
  );
}

/* ═══════════════════════════════════════════════════════════════
   STYLES — Pinterest-accurate
   ═══════════════════════════════════════════════════════════════ */
const s = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: '#FFFFFF',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#FFFFFF',
  },
  goBackBtn: {
    backgroundColor: '#111',
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 24,
  },

  /* ── Image Card ── */
  imageCard: {
    marginHorizontal: CONTENT_PAD,
    overflow: 'hidden',
    backgroundColor: '#F0ECE4',
    position: 'relative',
  },
  noImgBg: {
    backgroundColor: '#F0ECE4',
    justifyContent: 'center',
    alignItems: 'center',
  },

  /* ── Floating Buttons (back + visual search) ── */
  floatingBtn: {
    position: 'absolute',
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: 'rgba(255,255,255,0.92)',
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.08,
    shadowRadius: 4,
    elevation: 3,
    zIndex: 10,
  },

  /* ── Carousel Dots ── */
  dots: {
    position: 'absolute',
    bottom: 16,
    left: 0,
    right: 0,
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 6,
  },
  dot: {
    width: 7,
    height: 7,
    borderRadius: 4,
    backgroundColor: 'rgba(255,255,255,0.45)',
  },
  dotActive: {
    backgroundColor: '#FFFFFF',
    width: 20,
    borderRadius: 4,
  },

  /* ── Tag Pills ── */
  tagsRow: {
    paddingHorizontal: 14,
    paddingTop: 14,
    paddingBottom: 2,
    gap: 8,
  },
  tagPill: {
    backgroundColor: '#F0ECE4',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 24,
  },
  tagText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#111',
  },

  /* ── Engagement Row ── */
  engageRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 14,
    paddingTop: 12,
    paddingBottom: 6,
  },
  engageLeft: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  engageIcon: {
    padding: 4,
  },
  engageCount: {
    fontSize: 15,
    fontWeight: '700',
    color: '#111',
    marginLeft: 3,
  },
  saveBtn: {
    backgroundColor: '#E60023',
    paddingHorizontal: 22,
    paddingVertical: 12,
    borderRadius: 24,
  },
  saveBtnSaved: {
    backgroundColor: '#111',
  },
  saveBtnText: {
    fontSize: 15,
    fontWeight: '700',
    color: '#FFFFFF',
  },

  /* ── Author Row ── */
  authorRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  authorAvatar: {
    width: 32,
    height: 32,
    borderRadius: 16,
    marginRight: 10,
  },
  authorAvatarFallback: {
    backgroundColor: '#E8E4DF',
    justifyContent: 'center',
    alignItems: 'center',
  },
  authorAvatarInit: {
    color: '#888',
    fontSize: 14,
    fontWeight: '700',
  },
  authorName: {
    fontSize: 14,
    fontWeight: '700',
    color: '#111',
  },

  /* ── Caption ── */
  captionRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    paddingHorizontal: 16,
    paddingTop: 2,
    paddingBottom: 8,
  },
  captionText: {
    flex: 1,
    fontSize: 20,
    fontWeight: '700',
    color: '#111',
    lineHeight: 26,
    letterSpacing: -0.3,
  },
  captionChevron: {
    marginLeft: 8,
    marginTop: 2,
  },

  /* ── Comment Input ── */
  commentInputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginHorizontal: 14,
    marginTop: 4,
    backgroundColor: '#F5F2EC',
    borderRadius: 28,
    paddingHorizontal: 6,
    paddingVertical: 4,
  },
  commentInputAvatar: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#E8E4DF',
    justifyContent: 'center',
    alignItems: 'center',
    overflow: 'hidden',
  },
  commentInputAvatarText: {
    color: '#999',
    fontSize: 12,
    fontWeight: '700',
  },
  commentInput: {
    flex: 1,
    fontSize: 14,
    color: '#111',
    paddingHorizontal: 10,
    paddingVertical: 10,
  },
  sendBtn: {
    paddingRight: 4,
  },

  /* ── Comments ── */
  viewAllComments: {
    paddingHorizontal: 16,
    paddingTop: 6,
    paddingBottom: 10,
  },
  viewAllCommentsText: {
    fontSize: 13,
    color: '#999',
    fontWeight: '500',
  },
  commentsList: {
    paddingHorizontal: 16,
    paddingTop: 8,
  },
  commentsHeader: {
    fontSize: 16,
    fontWeight: '700',
    color: '#111',
    marginBottom: 12,
  },
  commentItem: {
    flexDirection: 'row',
    marginBottom: 14,
  },
  commentAvatar: {
    width: 28,
    height: 28,
    borderRadius: 14,
    marginRight: 10,
    marginTop: 2,
  },
  commentAvatarFallback: {
    backgroundColor: '#E8E4DF',
    justifyContent: 'center',
    alignItems: 'center',
  },
  commentAuthor: {
    fontSize: 13,
    fontWeight: '700',
    color: '#111',
  },
  commentContent: {
    fontSize: 14,
    color: '#333',
    lineHeight: 19,
    marginTop: 1,
  },
  commentTime: {
    fontSize: 11,
    color: '#B0B0B0',
    marginTop: 3,
  },
});
