import React, { useState, useEffect } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ActivityIndicator,
  TextInput, FlatList, Dimensions, KeyboardAvoidingView, Platform, Share,
  ScrollView,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useVideoPlayer, VideoView } from 'expo-video';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';
import { isCFStreamVideo, extractStreamUid, getStreamPlaybackInfo } from '../../src/utils/mediaUpload';
import { formatDistanceToNow } from 'date-fns';

const { width: SW } = Dimensions.get('window');
const IMG_W = SW - 8;
const IMG_H = SW * 1.2;
const RADIUS = 24;

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
  const [showAllComments, setShowAllComments] = useState(false);

  useEffect(() => { loadPostData(); }, [postId]);

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

      // Resolve video
      const allMedia: string[] = p.images?.length > 0 ? p.images : p.image ? [p.image] : [];
      const mediaTypes: string[] = p.media_types || [];
      for (let i = 0; i < allMedia.length; i++) {
        if (isCFStreamVideo(allMedia[i]) || mediaTypes[i] === 'video') {
          const uid = extractStreamUid(allMedia[i]);
          if (uid) {
            const info = await getStreamPlaybackInfo(uid);
            if (info?.hls) setVideoHlsUrl(info.hls);
          }
        }
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

  if (isLoading) {
    return <View style={s.center}><ActivityIndicator size="large" color="#000" /></View>;
  }
  if (!post) {
    return (
      <View style={s.center}>
        <Text style={{ color: '#999', fontSize: 16, marginBottom: 16 }}>Post not found</Text>
        <TouchableOpacity onPress={() => router.back()} style={s.goBackBtn}>
          <Text style={{ color: '#FFF', fontWeight: '700', fontSize: 14 }}>Go Back</Text>
        </TouchableOpacity>
      </View>
    );
  }

  const authorName = post.user_full_name || post.user_username || 'User';
  const allImages: string[] = post.images?.length > 0
    ? post.images.filter((u: string) => !isCFStreamVideo(u))
    : post.image && !isCFStreamVideo(post.image) ? [post.image] : [];
  const hasVideo = videoHlsUrl;
  const tags = [post.post_type, post.location].filter(Boolean);

  const formatCount = (n: number) => {
    if (n >= 1000) return (n / 1000).toFixed(1).replace('.0', '') + 'k';
    return String(n);
  };

  return (
    <View style={[s.root, { paddingTop: insets.top }]}>
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView
          showsVerticalScrollIndicator={false}
          contentContainerStyle={{ paddingBottom: 30 }}
          bounces
        >
          {/* ═══ IMAGE CARD ═══ */}
          <View style={s.imageCard}>
            {allImages.length > 0 ? (
              allImages.length > 1 ? (
                <FlatList
                  data={allImages}
                  horizontal
                  pagingEnabled
                  showsHorizontalScrollIndicator={false}
                  onMomentumScrollEnd={(e) => setActiveImgIdx(Math.round(e.nativeEvent.contentOffset.x / IMG_W))}
                  keyExtractor={(_, i) => `img-${i}`}
                  renderItem={({ item: uri }) => (
                    <Image source={{ uri }} style={s.heroImg} resizeMode="cover" />
                  )}
                />
              ) : (
                <Image source={{ uri: allImages[0] }} style={s.heroImg} resizeMode="cover" />
              )
            ) : hasVideo ? (
              <StreamPlayer hlsUrl={videoHlsUrl!} />
            ) : (
              <View style={[s.heroImg, s.noImgBg]}>
                <Ionicons name="image-outline" size={56} color="#D4D0C8" />
              </View>
            )}

            {/* Back button - white circle */}
            <TouchableOpacity
              style={[s.backBtn, { top: 14, left: 14 }]}
              onPress={() => router.back()}
              activeOpacity={0.8}
            >
              <Ionicons name="chevron-back" size={22} color="#000" />
            </TouchableOpacity>

            {/* Carousel dots */}
            {allImages.length > 1 && (
              <View style={s.dots}>
                {allImages.map((_: string, i: number) => (
                  <View key={i} style={[s.dot, activeImgIdx === i && s.dotOn]} />
                ))}
              </View>
            )}
          </View>

          {/* ═══ TAG PILLS ═══ */}
          {tags.length > 0 && (
            <ScrollView
              horizontal
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={s.tagsScroll}
            >
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
              <TouchableOpacity onPress={handleLike} style={s.iconBtn} activeOpacity={0.7}>
                <Ionicons
                  name={liked ? 'heart' : 'heart-outline'}
                  size={24}
                  color={liked ? '#ED4956' : '#111'}
                />
              </TouchableOpacity>
              {likesCount > 0 && <Text style={s.countText}>{formatCount(likesCount)}</Text>}

              <TouchableOpacity style={[s.iconBtn, { marginLeft: 12 }]} onPress={() => setShowAllComments(!showAllComments)} activeOpacity={0.7}>
                <Ionicons name="chatbubble-outline" size={21} color="#111" />
              </TouchableOpacity>
              {comments.length > 0 && <Text style={s.countText}>{comments.length}</Text>}

              <TouchableOpacity style={[s.iconBtn, { marginLeft: 12 }]} onPress={handleShare} activeOpacity={0.7}>
                <Ionicons name="arrow-up-outline" size={24} color="#111" />
              </TouchableOpacity>

              <TouchableOpacity style={[s.iconBtn, { marginLeft: 12 }]} activeOpacity={0.7}>
                <Ionicons name="ellipsis-horizontal" size={22} color="#111" />
              </TouchableOpacity>
            </View>

            <TouchableOpacity
              style={[s.saveBtn, saved && s.saveBtnSaved]}
              onPress={handleSave}
              activeOpacity={0.85}
            >
              <Text style={s.saveBtnText}>{saved ? 'Saved' : 'Save'}</Text>
            </TouchableOpacity>
          </View>

          {/* ═══ CAPTION ═══ */}
          {post.content ? (
            <Text style={s.caption}>{post.content}</Text>
          ) : null}

          {/* ═══ AUTHOR ROW ═══ */}
          <TouchableOpacity
            style={s.authorRow}
            onPress={() => router.push(`/user/${post.user_id}` as any)}
            activeOpacity={0.7}
          >
            {post.user_profile_image ? (
              <Image source={{ uri: post.user_profile_image }} style={s.authorAv} />
            ) : (
              <View style={[s.authorAv, s.authorAvFb]}>
                <Text style={s.authorAvInit}>{authorName[0].toUpperCase()}</Text>
              </View>
            )}
            <Text style={s.authorName}>{authorName}</Text>
          </TouchableOpacity>

          {/* ═══ COMMENT INPUT ═══ */}
          <View style={s.commentInputRow}>
            <View style={s.commentInputAv}>
              {user?.profile_image ? (
                <Image source={{ uri: user.profile_image }} style={{ width: 32, height: 32, borderRadius: 16 }} />
              ) : (
                <Text style={s.commentInputAvText}>{(user?.full_name || 'U')[0]}</Text>
              )}
            </View>
            <TextInput
              style={s.commentInput}
              placeholder="Add a comment"
              placeholderTextColor="#B0B0B0"
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
                  <Ionicons name="arrow-up-circle" size={28} color="#E60023" />
                )}
              </TouchableOpacity>
            ) : null}
          </View>

          {/* ═══ COMMENTS LIST ═══ */}
          {showAllComments && comments.length > 0 && (
            <View style={s.commentsList}>
              {comments.map((c) => (
                <View key={c.id} style={s.commentRow}>
                  {c.user_profile_image ? (
                    <Image source={{ uri: c.user_profile_image }} style={s.commentAv} />
                  ) : (
                    <View style={[s.commentAv, { backgroundColor: '#DDD', justifyContent: 'center', alignItems: 'center' }]}>
                      <Text style={{ fontSize: 10, fontWeight: '700', color: '#888' }}>{(c.user_full_name || 'U')[0]}</Text>
                    </View>
                  )}
                  <View style={{ flex: 1 }}>
                    <Text style={s.commentName}>{c.user_full_name}</Text>
                    <Text style={s.commentBody}>{c.content}</Text>
                    <Text style={s.commentAge}>
                      {formatDistanceToNow(new Date(c.created_at), { addSuffix: true })}
                    </Text>
                  </View>
                </View>
              ))}
            </View>
          )}

          {!showAllComments && comments.length > 0 && (
            <TouchableOpacity style={s.viewAll} onPress={() => setShowAllComments(true)}>
              <Text style={s.viewAllText}>View all {comments.length} comment{comments.length !== 1 ? 's' : ''}</Text>
            </TouchableOpacity>
          )}
        </ScrollView>
      </KeyboardAvoidingView>
    </View>
  );
}

function StreamPlayer({ hlsUrl }: { hlsUrl: string }) {
  const player = useVideoPlayer(hlsUrl, (p) => { p.loop = false; });
  return <VideoView player={player} style={s.heroImg} nativeControls />;
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#FFFFFF' },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#FFF' },
  goBackBtn: { backgroundColor: '#111', paddingHorizontal: 24, paddingVertical: 12, borderRadius: 24 },

  /* ── Image Card ── */
  imageCard: {
    marginHorizontal: 4,
    borderRadius: RADIUS,
    overflow: 'hidden',
    backgroundColor: '#F0ECE4',
  },
  heroImg: {
    width: IMG_W,
    height: IMG_H,
  },
  noImgBg: { backgroundColor: '#F0ECE4', justifyContent: 'center', alignItems: 'center' },

  backBtn: {
    position: 'absolute',
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: '#FFFFFF',
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.10,
    shadowRadius: 6,
    elevation: 4,
  },

  dots: {
    position: 'absolute', bottom: 16, left: 0, right: 0,
    flexDirection: 'row', justifyContent: 'center', gap: 6,
  },
  dot: { width: 7, height: 7, borderRadius: 4, backgroundColor: 'rgba(255,255,255,0.45)' },
  dotOn: { backgroundColor: '#FFF', width: 20, borderRadius: 4 },

  /* ── Tag pills ── */
  tagsScroll: { paddingHorizontal: 16, paddingTop: 16, paddingBottom: 4, gap: 8 },
  tagPill: {
    backgroundColor: '#F0ECE4',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 24,
  },
  tagText: {
    fontSize: 14,
    fontWeight: '500',
    color: '#111',
  },

  /* ── Engagement row ── */
  engageRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingTop: 14,
    paddingBottom: 8,
  },
  engageLeft: { flexDirection: 'row', alignItems: 'center' },
  iconBtn: { padding: 4 },
  countText: {
    fontSize: 15,
    fontWeight: '600',
    color: '#111',
    marginLeft: 3,
  },

  saveBtn: {
    backgroundColor: '#E60023',
    paddingHorizontal: 22,
    paddingVertical: 12,
    borderRadius: 24,
  },
  saveBtnSaved: { backgroundColor: '#111' },
  saveBtnText: {
    fontSize: 15,
    fontWeight: '700',
    color: '#FFFFFF',
  },

  /* ── Caption ── */
  caption: {
    fontSize: 15,
    color: '#111',
    lineHeight: 22,
    paddingHorizontal: 18,
    paddingTop: 4,
    paddingBottom: 6,
  },

  /* ── Author row ── */
  authorRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 18,
    paddingVertical: 8,
  },
  authorAv: {
    width: 32,
    height: 32,
    borderRadius: 16,
    marginRight: 10,
  },
  authorAvFb: { backgroundColor: '#9370DB', justifyContent: 'center', alignItems: 'center' },
  authorAvInit: { color: '#FFF', fontSize: 14, fontWeight: '700' },
  authorName: { fontSize: 14, fontWeight: '600', color: '#111' },

  /* ── Comment input ── */
  commentInputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginHorizontal: 16,
    marginTop: 6,
    backgroundColor: '#F5F2EC',
    borderRadius: 28,
    paddingHorizontal: 6,
    paddingVertical: 4,
  },
  commentInputAv: {
    width: 32, height: 32, borderRadius: 16,
    backgroundColor: '#9370DB', justifyContent: 'center', alignItems: 'center',
    overflow: 'hidden',
  },
  commentInputAvText: { color: '#FFF', fontSize: 12, fontWeight: '700' },
  commentInput: {
    flex: 1, fontSize: 14, color: '#111',
    paddingHorizontal: 10, paddingVertical: 10,
  },
  sendBtn: { paddingRight: 4 },

  /* ── View all ── */
  viewAll: { paddingHorizontal: 18, paddingTop: 4, paddingBottom: 10 },
  viewAllText: { fontSize: 13, color: '#999', fontWeight: '500' },

  /* ── Comments list ── */
  commentsList: { paddingHorizontal: 18, paddingTop: 4 },
  commentRow: { flexDirection: 'row', marginBottom: 14 },
  commentAv: { width: 28, height: 28, borderRadius: 14, marginRight: 10, marginTop: 2 },
  commentName: { fontSize: 13, fontWeight: '700', color: '#111' },
  commentBody: { fontSize: 14, color: '#333', lineHeight: 19, marginTop: 1 },
  commentAge: { fontSize: 11, color: '#B0B0B0', marginTop: 3 },
});
