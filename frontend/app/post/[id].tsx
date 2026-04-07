import React, { useState, useEffect } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ActivityIndicator,
  TextInput, FlatList, Dimensions, KeyboardAvoidingView, Platform, Share, Linking,
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
const IMG_RADIUS = 20;

export default function PostDetailScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { id: postId } = useLocalSearchParams<{ id: string }>();
  const { user } = useAuthStore();

  const [post, setPost] = useState<any>(null);
  const [comments, setComments] = useState<any[]>([]);
  const [relatedPosts, setRelatedPosts] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [newComment, setNewComment] = useState('');
  const [isCommenting, setIsCommenting] = useState(false);
  const [liked, setLiked] = useState(false);
  const [likesCount, setLikesCount] = useState(0);
  const [saved, setSaved] = useState(false);
  const [activeImgIdx, setActiveImgIdx] = useState(0);
  const [videoHlsUrl, setVideoHlsUrl] = useState<string | null>(null);
  const [showComments, setShowComments] = useState(false);

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

      // Load related posts
      try {
        const feed = await api.get('/posts/feed', { params: { limit: 12 } });
        const all = Array.isArray(feed.data) ? feed.data : [];
        setRelatedPosts(all.filter((fp: any) => fp.id !== postId && (fp.image || fp.images?.[0])).slice(0, 6));
      } catch {}

      // Resolve CF Stream video
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

  if (isLoading) return <View style={s.loadWrap}><ActivityIndicator size="large" color="#1A1A1A" /></View>;
  if (!post) return (
    <View style={s.loadWrap}>
      <Text style={{ color: '#999', fontSize: 16 }}>Post not found</Text>
      <TouchableOpacity onPress={() => router.back()} style={{ marginTop: 16 }}>
        <Text style={{ color: '#DC2626', fontWeight: '600' }}>Go Back</Text>
      </TouchableOpacity>
    </View>
  );

  const timeAgo = formatDistanceToNow(new Date(post.created_at), { addSuffix: true });
  const authorName = post.user_full_name || post.user_username || 'User';
  const allImages: string[] = post.images?.length > 0
    ? post.images.filter((u: string) => !isCFStreamVideo(u))
    : post.image && !isCFStreamVideo(post.image) ? [post.image] : [];
  const hasVideo = videoHlsUrl || (post.media_types || []).includes('video');
  const postTags = [post.post_type, post.location].filter(Boolean);

  return (
    <View style={[s.container, { paddingTop: insets.top }]}>
      <FlatList
        data={showComments ? comments : []}
        keyExtractor={(item) => item.id}
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ paddingBottom: 100 }}
        ListHeaderComponent={
          <View>
            {/* === HERO IMAGE === */}
            <View style={s.imageWrap}>
              {allImages.length > 0 ? (
                allImages.length > 1 ? (
                  <FlatList
                    data={allImages}
                    horizontal pagingEnabled
                    showsHorizontalScrollIndicator={false}
                    onMomentumScrollEnd={(e) => setActiveImgIdx(Math.round(e.nativeEvent.contentOffset.x / (SW - 24)))}
                    keyExtractor={(_, i) => `img-${i}`}
                    renderItem={({ item: uri }) => (
                      <Image source={{ uri }} style={s.heroImg} resizeMode="cover" />
                    )}
                  />
                ) : (
                  <Image source={{ uri: allImages[0] }} style={s.heroImg} resizeMode="cover" />
                )
              ) : hasVideo && videoHlsUrl ? (
                <StreamVideoPlayer hlsUrl={videoHlsUrl} />
              ) : (
                <View style={[s.heroImg, { backgroundColor: '#E8E4DF', justifyContent: 'center', alignItems: 'center' }]}>
                  <Ionicons name="image-outline" size={48} color="#CCC" />
                </View>
              )}

              {/* Back button */}
              <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
                <Ionicons name="chevron-back" size={20} color="#1A1A1A" />
              </TouchableOpacity>

              {/* Image dots */}
              {allImages.length > 1 && (
                <View style={s.dotsRow}>
                  {allImages.map((_: string, i: number) => (
                    <View key={i} style={[s.dot, activeImgIdx === i && s.dotActive]} />
                  ))}
                </View>
              )}
            </View>

            {/* === TAG PILLS === */}
            {postTags.length > 0 && (
              <View style={s.tagsRow}>
                {postTags.map((tag, i) => (
                  <View key={i} style={s.tagPill}>
                    <Text style={s.tagText}>{tag}</Text>
                  </View>
                ))}
              </View>
            )}

            {/* === ENGAGEMENT BAR === */}
            <View style={s.engageBar}>
              <View style={s.engageLeft}>
                <TouchableOpacity onPress={handleLike} style={s.engageBtn}>
                  <Ionicons name={liked ? 'heart' : 'heart-outline'} size={22} color={liked ? '#ED4956' : '#1A1A1A'} />
                  {likesCount > 0 && <Text style={s.engageCount}>{likesCount}</Text>}
                </TouchableOpacity>
                <TouchableOpacity style={s.engageBtn} onPress={() => setShowComments(!showComments)}>
                  <Ionicons name="chatbubble-outline" size={20} color="#1A1A1A" />
                  {comments.length > 0 && <Text style={s.engageCount}>{comments.length}</Text>}
                </TouchableOpacity>
                <TouchableOpacity style={s.engageBtn} onPress={handleShare}>
                  <Ionicons name="arrow-up-outline" size={22} color="#1A1A1A" />
                </TouchableOpacity>
                <TouchableOpacity style={s.engageBtn}>
                  <Ionicons name="ellipsis-horizontal" size={20} color="#1A1A1A" />
                </TouchableOpacity>
              </View>
              <TouchableOpacity style={[s.saveBtn, saved && s.saveBtnActive]} onPress={handleSave}>
                <Ionicons name={saved ? 'bookmark' : 'bookmark-outline'} size={16} color={saved ? '#FFF' : '#FFF'} />
                <Text style={s.saveBtnText}>{saved ? 'Saved' : 'Save'}</Text>
              </TouchableOpacity>
            </View>

            {/* === CAPTION === */}
            {post.content ? (
              <View style={s.captionWrap}>
                <Text style={s.captionText}>{post.content}</Text>
              </View>
            ) : null}

            {/* === AUTHOR ROW === */}
            <TouchableOpacity style={s.authorRow} onPress={() => router.push(`/user/${post.user_id}` as any)} activeOpacity={0.7}>
              {post.user_profile_image ? (
                <Image source={{ uri: post.user_profile_image }} style={s.authorAvatar} />
              ) : (
                <View style={[s.authorAvatar, s.authorAvatarFb]}>
                  <Text style={s.authorAvatarInit}>{authorName[0].toUpperCase()}</Text>
                </View>
              )}
              <View style={{ flex: 1 }}>
                <Text style={s.authorName}>{authorName}</Text>
                <Text style={s.authorTime}>{timeAgo}</Text>
              </View>
              <TouchableOpacity style={s.followBtn}>
                <Text style={s.followBtnText}>Follow</Text>
              </TouchableOpacity>
            </TouchableOpacity>

            {/* === LOCATION === */}
            {post.location ? (
              <View style={s.locationRow}>
                <Ionicons name="location" size={14} color="#DC2626" />
                <Text style={s.locationText}>{post.location}</Text>
              </View>
            ) : null}

            {/* === COMMENT INPUT === */}
            <View style={s.commentInput}>
              <View style={s.commentAvatar}>
                {user?.profile_image ? (
                  <Image source={{ uri: user.profile_image }} style={{ width: '100%', height: '100%', borderRadius: 14 }} />
                ) : (
                  <Text style={s.commentAvatarText}>{(user?.full_name || 'U')[0]}</Text>
                )}
              </View>
              <TextInput
                style={s.commentTextInput}
                placeholder="Add a comment..."
                placeholderTextColor="#CCC"
                value={newComment}
                onChangeText={setNewComment}
              />
              {newComment.trim() ? (
                <TouchableOpacity onPress={handleComment} disabled={isCommenting}>
                  {isCommenting ? (
                    <ActivityIndicator size="small" color="#DC2626" />
                  ) : (
                    <Ionicons name="send" size={18} color="#DC2626" />
                  )}
                </TouchableOpacity>
              ) : null}
            </View>

            {/* === COMMENTS TOGGLE === */}
            {comments.length > 0 && !showComments && (
              <TouchableOpacity style={s.showComments} onPress={() => setShowComments(true)}>
                <Text style={s.showCommentsText}>View all {comments.length} comments</Text>
              </TouchableOpacity>
            )}

            {/* === MORE TO EXPLORE === */}
            {relatedPosts.length > 0 && !showComments && (
              <View style={s.relatedSection}>
                <Text style={s.relatedTitle}>More to explore</Text>
                <View style={s.relatedGrid}>
                  {relatedPosts.map((rp: any) => (
                    <TouchableOpacity
                      key={rp.id}
                      style={s.relatedCard}
                      activeOpacity={0.9}
                      onPress={() => router.push(`/post/${rp.id}` as any)}
                    >
                      <Image source={{ uri: rp.image || rp.images?.[0] }} style={s.relatedImg} />
                    </TouchableOpacity>
                  ))}
                </View>
              </View>
            )}
          </View>
        }
        renderItem={({ item }) => (
          <View style={s.commentItem}>
            {item.user_profile_image ? (
              <Image source={{ uri: item.user_profile_image }} style={s.commentItemAvatar} />
            ) : (
              <View style={[s.commentItemAvatar, { backgroundColor: '#50C8A8', justifyContent: 'center', alignItems: 'center' }]}>
                <Text style={{ color: '#FFF', fontSize: 10, fontWeight: '700' }}>{(item.user_full_name || 'U')[0]}</Text>
              </View>
            )}
            <View style={s.commentBubble}>
              <Text style={s.commentAuthor}>{item.user_full_name}</Text>
              <Text style={s.commentContent}>{item.content}</Text>
              <Text style={s.commentTime}>{formatDistanceToNow(new Date(item.created_at), { addSuffix: true })}</Text>
            </View>
          </View>
        )}
      />
    </View>
  );
}

function StreamVideoPlayer({ hlsUrl }: { hlsUrl: string }) {
  const player = useVideoPlayer(hlsUrl, (p) => { p.loop = false; });
  return <VideoView player={player} style={s.heroImg} allowsFullscreen allowsPictureInPicture />;
}

const RELATED_W = (SW - 36 - 8) / 3;

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FFF' },
  loadWrap: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#FFF' },

  // Hero image
  imageWrap: {
    marginHorizontal: 12, borderRadius: IMG_RADIUS, overflow: 'hidden',
    position: 'relative', backgroundColor: '#F5F0EB',
  },
  heroImg: { width: SW - 24, height: SW * 1.15, borderRadius: IMG_RADIUS },
  backBtn: {
    position: 'absolute', top: 12, left: 12,
    width: 38, height: 38, borderRadius: 19,
    backgroundColor: 'rgba(255,255,255,0.92)',
    justifyContent: 'center', alignItems: 'center',
  },
  dotsRow: {
    position: 'absolute', bottom: 14, left: 0, right: 0,
    flexDirection: 'row', justifyContent: 'center', gap: 5,
  },
  dot: { width: 6, height: 6, borderRadius: 3, backgroundColor: 'rgba(255,255,255,0.4)' },
  dotActive: { backgroundColor: '#FFF', width: 18, borderRadius: 3 },

  // Tags
  tagsRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, paddingHorizontal: 16, paddingTop: 14 },
  tagPill: {
    backgroundColor: '#F5F0EB', paddingHorizontal: 12, paddingVertical: 6, borderRadius: 16,
  },
  tagText: { fontSize: 12, fontWeight: '600', color: '#666' },

  // Engagement
  engageBar: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 16, paddingTop: 12, paddingBottom: 6,
  },
  engageLeft: { flexDirection: 'row', alignItems: 'center', gap: 2 },
  engageBtn: { flexDirection: 'row', alignItems: 'center', gap: 3, paddingHorizontal: 8, paddingVertical: 6 },
  engageCount: { fontSize: 13, fontWeight: '700', color: '#1A1A1A' },
  saveBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 5,
    backgroundColor: '#1A1A1A', paddingHorizontal: 16, paddingVertical: 9, borderRadius: 20,
  },
  saveBtnActive: { backgroundColor: '#DC2626' },
  saveBtnText: { fontSize: 13, fontWeight: '700', color: '#FFF' },

  // Caption
  captionWrap: { paddingHorizontal: 16, paddingTop: 6, paddingBottom: 2 },
  captionText: { fontSize: 15, color: '#1A1A1A', lineHeight: 22 },

  // Author
  authorRow: {
    flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16,
    paddingVertical: 12,
  },
  authorAvatar: { width: 40, height: 40, borderRadius: 20, marginRight: 10 },
  authorAvatarFb: { backgroundColor: '#50C8A8', justifyContent: 'center', alignItems: 'center' },
  authorAvatarInit: { color: '#FFF', fontSize: 16, fontWeight: '700' },
  authorName: { fontSize: 14, fontWeight: '700', color: '#1A1A1A' },
  authorTime: { fontSize: 12, color: '#AAA', marginTop: 1 },
  followBtn: {
    backgroundColor: '#F5F0EB', paddingHorizontal: 18, paddingVertical: 8, borderRadius: 18,
  },
  followBtnText: { fontSize: 13, fontWeight: '700', color: '#1A1A1A' },

  // Location
  locationRow: {
    flexDirection: 'row', alignItems: 'center', gap: 5,
    paddingHorizontal: 16, paddingBottom: 10,
  },
  locationText: { fontSize: 13, color: '#999', fontWeight: '500' },

  // Comment input
  commentInput: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    marginHorizontal: 16, marginTop: 4, marginBottom: 8,
    backgroundColor: '#F8F6F2', borderRadius: 24,
    paddingHorizontal: 6, paddingVertical: 4,
  },
  commentAvatar: {
    width: 28, height: 28, borderRadius: 14, overflow: 'hidden',
    backgroundColor: '#50C8A8', justifyContent: 'center', alignItems: 'center',
  },
  commentAvatarText: { color: '#FFF', fontSize: 11, fontWeight: '700' },
  commentTextInput: { flex: 1, fontSize: 14, color: '#1A1A1A', paddingVertical: 8 },

  // Show comments
  showComments: { paddingHorizontal: 16, paddingBottom: 12 },
  showCommentsText: { fontSize: 13, fontWeight: '600', color: '#999' },

  // Comments
  commentItem: { flexDirection: 'row', paddingHorizontal: 16, paddingVertical: 6 },
  commentItemAvatar: { width: 28, height: 28, borderRadius: 14, marginRight: 8 },
  commentBubble: { flex: 1, backgroundColor: '#F8F6F2', borderRadius: 14, paddingHorizontal: 12, paddingVertical: 8, borderTopLeftRadius: 4 },
  commentAuthor: { fontSize: 12, fontWeight: '700', color: '#1A1A1A', marginBottom: 2 },
  commentContent: { fontSize: 14, color: '#333', lineHeight: 19 },
  commentTime: { fontSize: 10, color: '#BBB', marginTop: 4 },

  // Related
  relatedSection: { paddingHorizontal: 16, paddingTop: 16 },
  relatedTitle: { fontSize: 16, fontWeight: '800', color: '#1A1A1A', marginBottom: 12 },
  relatedGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 4 },
  relatedCard: { width: RELATED_W, height: RELATED_W * 1.3, borderRadius: 12, overflow: 'hidden' },
  relatedImg: { width: '100%', height: '100%' },
});
