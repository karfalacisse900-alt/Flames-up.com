import React, { useState, useEffect } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ActivityIndicator,
  TextInput, FlatList, Dimensions, KeyboardAvoidingView, Platform, Share,
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useVideoPlayer, VideoView } from 'expo-video';
import { colors } from '../../src/utils/theme';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';
import { isCFStreamVideo, extractStreamUid, getStreamPlaybackInfo } from '../../src/utils/mediaUpload';
import { formatDistanceToNow } from 'date-fns';

const { width: SW } = Dimensions.get('window');

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

      // Check bookmark status
      try {
        const bm = await api.get(`/bookmarks/check/${postId}`);
        setSaved(bm.data?.saved || false);
      } catch {}

      // Resolve CF Stream video URLs
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
    const newSaved = !saved;
    setSaved(newSaved);
    try {
      if (newSaved) {
        await api.post('/bookmarks', { post_id: postId, collection: 'saved' });
      } else {
        await api.delete(`/bookmarks/${postId}`);
      }
    } catch { setSaved(!newSaved); }
  };

  const handleComment = async () => {
    if (!newComment.trim() || isCommenting) return;
    setIsCommenting(true);
    try {
      const response = await api.post(`/posts/${postId}/comments`, { content: newComment.trim() });
      setComments([...comments, response.data]);
      setNewComment('');
    } catch {} finally { setIsCommenting(false); }
  };

  const handleShare = async () => {
    try { await Share.share({ message: post?.content || 'Check this out on Flames-Up!' }); } catch {}
  };

  if (isLoading) {
    return (
      <View style={s.loadWrap}>
        <ActivityIndicator size="large" color="#1A1A1A" />
      </View>
    );
  }
  if (!post) {
    return (
      <View style={s.loadWrap}>
        <Text style={s.errorText}>Post not found</Text>
        <TouchableOpacity onPress={() => router.back()} style={{ marginTop: 16 }}>
          <Text style={{ color: colors.accentPrimary, fontWeight: '600' }}>Go Back</Text>
        </TouchableOpacity>
      </View>
    );
  }

  const timeAgo = formatDistanceToNow(new Date(post.created_at), { addSuffix: true });
  const authorName = post.user_full_name || post.user_username || 'User';
  const allImages: string[] = post.images?.length > 0
    ? post.images.filter((u: string) => !isCFStreamVideo(u))
    : post.image && !isCFStreamVideo(post.image) ? [post.image] : [];
  const mediaTypes: string[] = post.media_types || [];
  const hasVideo = videoHlsUrl || mediaTypes.includes('video');
  const isCheckin = post.is_verified_checkin || post.post_type === 'check_in';

  return (
    <View style={s.container}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={{ flex: 1 }}
        keyboardVerticalOffset={0}
      >
        <FlatList
          data={comments}
          keyExtractor={(item) => item.id}
          showsVerticalScrollIndicator={false}
          contentContainerStyle={{ paddingBottom: 90 }}
          ListHeaderComponent={
            <View>
              {/* Hero Media Area */}
              {allImages.length > 0 ? (
                <View style={s.heroWrap}>
                  {allImages.length > 1 ? (
                    <FlatList
                      data={allImages}
                      horizontal
                      pagingEnabled
                      showsHorizontalScrollIndicator={false}
                      onMomentumScrollEnd={(e) => setActiveImgIdx(Math.round(e.nativeEvent.contentOffset.x / SW))}
                      keyExtractor={(_, i) => `img-${i}`}
                      renderItem={({ item: imgUri }) => (
                        <Image source={{ uri: imgUri }} style={s.heroImage} resizeMode="cover" />
                      )}
                    />
                  ) : (
                    <Image source={{ uri: allImages[0] }} style={s.heroImage} resizeMode="cover" />
                  )}

                  {/* Gradient overlay at top for buttons */}
                  <View style={s.heroGradientTop} />

                  {/* Back button */}
                  <TouchableOpacity style={[s.navBtn, { top: insets.top + 8, left: 16 }]} onPress={() => router.back()}>
                    <Ionicons name="arrow-back" size={20} color="#FFF" />
                  </TouchableOpacity>

                  {/* Share button */}
                  <TouchableOpacity style={[s.navBtn, { top: insets.top + 8, right: 16 }]} onPress={handleShare}>
                    <Ionicons name="share-outline" size={18} color="#FFF" />
                  </TouchableOpacity>

                  {/* Carousel dots */}
                  {allImages.length > 1 && (
                    <View style={s.dotsRow}>
                      {allImages.map((_: string, i: number) => (
                        <View key={i} style={[s.dot, activeImgIdx === i && s.dotActive]} />
                      ))}
                    </View>
                  )}

                  {/* Image counter */}
                  {allImages.length > 1 && (
                    <View style={s.counter}>
                      <Text style={s.counterText}>{activeImgIdx + 1}/{allImages.length}</Text>
                    </View>
                  )}
                </View>
              ) : hasVideo && videoHlsUrl ? (
                <View style={s.heroWrap}>
                  <StreamVideoPlayer hlsUrl={videoHlsUrl} />
                  <View style={s.heroGradientTop} />
                  <TouchableOpacity style={[s.navBtn, { top: insets.top + 8, left: 16 }]} onPress={() => router.back()}>
                    <Ionicons name="arrow-back" size={20} color="#FFF" />
                  </TouchableOpacity>
                </View>
              ) : (
                <SafeAreaView edges={['top']}>
                  <View style={s.headerFlat}>
                    <TouchableOpacity onPress={() => router.back()} style={s.backBtnFlat}>
                      <Ionicons name="arrow-back" size={22} color="#1A1A1A" />
                    </TouchableOpacity>
                    <TouchableOpacity onPress={handleShare} style={s.backBtnFlat}>
                      <Ionicons name="share-outline" size={20} color="#1A1A1A" />
                    </TouchableOpacity>
                  </View>
                </SafeAreaView>
              )}

              {/* Content Section */}
              <View style={s.content}>
                {/* Author Row */}
                <TouchableOpacity style={s.authorRow} onPress={() => router.push(`/user/${post.user_id}` as any)} activeOpacity={0.7}>
                  <View style={s.avatarWrap}>
                    {post.user_profile_image ? (
                      <Image source={{ uri: post.user_profile_image }} style={s.avatarImg} />
                    ) : (
                      <View style={s.avatarFallback}>
                        <Text style={s.avatarInit}>{authorName[0].toUpperCase()}</Text>
                      </View>
                    )}
                  </View>
                  <View style={{ flex: 1 }}>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
                      <Text style={s.authorName}>{authorName}</Text>
                      {post.is_creator ? (
                        <View style={s.creatorBadge}>
                          <Ionicons name="flame" size={10} color="#F97316" />
                        </View>
                      ) : null}
                    </View>
                    <Text style={s.timeText}>{timeAgo}</Text>
                  </View>
                  <TouchableOpacity style={s.followBtn}>
                    <Text style={s.followBtnText}>Follow</Text>
                  </TouchableOpacity>
                </TouchableOpacity>

                {/* Post type badge */}
                {isCheckin && (
                  <View style={s.checkinBadge}>
                    <Ionicons name="checkmark-circle" size={14} color="#10B981" />
                    <Text style={s.checkinText}>Verified Check-In</Text>
                    {post.place_name ? <Text style={s.checkinPlace}>{post.place_name}</Text> : null}
                  </View>
                )}
                {post.post_type === 'question' && (
                  <View style={[s.checkinBadge, { backgroundColor: '#FEF3C7', borderColor: '#FDE68A' }]}>
                    <Ionicons name="help-circle" size={14} color="#D97706" />
                    <Text style={[s.checkinText, { color: '#D97706' }]}>Question</Text>
                  </View>
                )}

                {/* Caption */}
                <Text style={s.caption}>{post.content}</Text>

                {/* Location */}
                {post.location ? (
                  <View style={s.locRow}>
                    <Ionicons name="location" size={13} color="#DC2626" />
                    <Text style={s.locText}>{post.location}</Text>
                  </View>
                ) : null}

                {/* Engagement Row */}
                <View style={s.engageRow}>
                  <View style={s.engageLeft}>
                    <TouchableOpacity onPress={handleLike} style={s.engageBtn}>
                      <Ionicons name={liked ? 'heart' : 'heart-outline'} size={24} color={liked ? '#ED4956' : '#1A1A1A'} />
                      {likesCount > 0 && <Text style={s.engageCount}>{likesCount}</Text>}
                    </TouchableOpacity>
                    <TouchableOpacity style={s.engageBtn}>
                      <Ionicons name="chatbubble-outline" size={22} color="#1A1A1A" />
                      {comments.length > 0 && <Text style={s.engageCount}>{comments.length}</Text>}
                    </TouchableOpacity>
                    <TouchableOpacity style={s.engageBtn} onPress={handleShare}>
                      <Ionicons name="paper-plane-outline" size={22} color="#1A1A1A" />
                    </TouchableOpacity>
                  </View>
                  <TouchableOpacity onPress={handleSave} style={s.engageBtn}>
                    <Ionicons name={saved ? 'bookmark' : 'bookmark-outline'} size={22} color={saved ? '#D97706' : '#1A1A1A'} />
                  </TouchableOpacity>
                </View>

                {/* Comments header */}
                <View style={s.commentsHeader}>
                  <Text style={s.commentsTitle}>Comments</Text>
                  <Text style={s.commentsCount}>{comments.length}</Text>
                </View>
              </View>
            </View>
          }
          renderItem={({ item }) => (
            <View style={s.commentItem}>
              <TouchableOpacity onPress={() => router.push(`/user/${item.user_id}` as any)}>
                {item.user_profile_image ? (
                  <Image source={{ uri: item.user_profile_image }} style={s.commentAv} />
                ) : (
                  <View style={[s.commentAv, s.commentAvFb]}>
                    <Text style={s.commentAvInit}>{(item.user_username || 'U')[0].toUpperCase()}</Text>
                  </View>
                )}
              </TouchableOpacity>
              <View style={s.commentBody}>
                <View style={s.commentBubble}>
                  <Text style={s.commentUsername}>{item.user_full_name}</Text>
                  <Text style={s.commentText}>{item.content}</Text>
                </View>
                <Text style={s.commentTime}>
                  {formatDistanceToNow(new Date(item.created_at), { addSuffix: true })}
                </Text>
              </View>
            </View>
          )}
          ListEmptyComponent={
            <View style={s.emptyComments}>
              <Ionicons name="chatbubble-outline" size={32} color="#DDD" />
              <Text style={s.emptyTitle}>No comments yet</Text>
              <Text style={s.emptySub}>Start the conversation</Text>
            </View>
          }
        />

        {/* Comment Input Bar */}
        <View style={[s.inputBar, { paddingBottom: Math.max(insets.bottom, 12) }]}>
          <View style={s.inputAvatar}>
            {user?.profile_image ? (
              <Image source={{ uri: user.profile_image }} style={{ width: '100%', height: '100%', borderRadius: 16 }} />
            ) : (
              <Text style={s.inputAvatarText}>{(user?.full_name || 'U')[0].toUpperCase()}</Text>
            )}
          </View>
          <View style={s.inputWrap}>
            <TextInput
              style={s.commentInput}
              placeholder="Write a comment..."
              placeholderTextColor="#BBB"
              value={newComment}
              onChangeText={setNewComment}
              multiline
              maxLength={500}
            />
          </View>
          <TouchableOpacity onPress={handleComment} disabled={!newComment.trim() || isCommenting} style={s.sendBtn}>
            {isCommenting ? (
              <ActivityIndicator size="small" color="#FFF" />
            ) : (
              <Ionicons name="send" size={16} color={newComment.trim() ? '#FFF' : 'rgba(255,255,255,0.4)'} />
            )}
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>
    </View>
  );
}

// Stream Video Player Component
function StreamVideoPlayer({ hlsUrl }: { hlsUrl: string }) {
  const player = useVideoPlayer(hlsUrl, (p) => {
    p.loop = false;
  });

  return (
    <VideoView
      player={player}
      style={s.heroImage}
      allowsFullscreen
      allowsPictureInPicture
    />
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FFFFFF' },
  loadWrap: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#FAFAF8' },
  errorText: { fontSize: 16, color: '#999' },

  // Hero
  heroWrap: { width: SW, height: SW * 1.1, backgroundColor: '#0A0A0A', position: 'relative' },
  heroImage: { width: SW, height: SW * 1.1 },
  heroGradientTop: {
    position: 'absolute', top: 0, left: 0, right: 0, height: 120,
    backgroundColor: 'transparent',
  },
  navBtn: {
    position: 'absolute', width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(0,0,0,0.35)', justifyContent: 'center', alignItems: 'center',
  },
  dotsRow: {
    position: 'absolute', bottom: 16, left: 0, right: 0,
    flexDirection: 'row', justifyContent: 'center', gap: 5,
  },
  dot: { width: 6, height: 6, borderRadius: 3, backgroundColor: 'rgba(255,255,255,0.4)' },
  dotActive: { backgroundColor: '#FFF', width: 20, borderRadius: 3 },
  counter: {
    position: 'absolute', top: 56, right: 16,
    backgroundColor: 'rgba(0,0,0,0.5)', paddingHorizontal: 10, paddingVertical: 4, borderRadius: 12,
  },
  counterText: { color: '#FFF', fontSize: 12, fontWeight: '700' },

  // Flat header (no image)
  headerFlat: {
    flexDirection: 'row', justifyContent: 'space-between',
    paddingHorizontal: 16, paddingVertical: 8,
    borderBottomWidth: 1, borderBottomColor: '#ECEAE3',
  },
  backBtnFlat: { width: 44, height: 44, borderRadius: 22, justifyContent: 'center', alignItems: 'center' },

  // Content
  content: { paddingHorizontal: 20, paddingTop: 20 },

  // Author
  authorRow: { flexDirection: 'row', alignItems: 'center', marginBottom: 16 },
  avatarWrap: {
    width: 48, height: 48, borderRadius: 24, overflow: 'hidden', marginRight: 12,
    borderWidth: 2, borderColor: '#F0EDE7',
  },
  avatarImg: { width: '100%', height: '100%' },
  avatarFallback: {
    width: '100%', height: '100%', backgroundColor: '#50C8A8',
    justifyContent: 'center', alignItems: 'center',
  },
  avatarInit: { color: '#FFF', fontSize: 18, fontWeight: '700' },
  authorName: { fontSize: 16, fontWeight: '800', color: '#1A1A1A', letterSpacing: -0.3 },
  creatorBadge: {
    width: 18, height: 18, borderRadius: 9,
    backgroundColor: '#FFF7ED', justifyContent: 'center', alignItems: 'center',
  },
  timeText: { fontSize: 12, color: '#AAA', marginTop: 2 },
  followBtn: {
    backgroundColor: '#1A1A1A', paddingHorizontal: 20, paddingVertical: 9, borderRadius: 20,
  },
  followBtnText: { fontSize: 13, fontWeight: '700', color: '#FFF' },

  // Post type badges
  checkinBadge: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    backgroundColor: '#ECFDF5', borderWidth: 1, borderColor: '#D1FAE5',
    paddingHorizontal: 12, paddingVertical: 6, borderRadius: 12,
    alignSelf: 'flex-start', marginBottom: 14,
  },
  checkinText: { fontSize: 12, fontWeight: '700', color: '#10B981' },
  checkinPlace: { fontSize: 12, color: '#059669', marginLeft: 4 },

  // Caption
  caption: { fontSize: 17, color: '#1A1A1A', lineHeight: 26, letterSpacing: -0.2, marginBottom: 14 },

  // Location
  locRow: { flexDirection: 'row', alignItems: 'center', gap: 5, marginBottom: 16 },
  locText: { fontSize: 13, color: '#999', fontWeight: '500' },

  // Engagement
  engageRow: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingVertical: 14, borderTopWidth: 1, borderBottomWidth: 1,
    borderColor: '#F0EDE7',
  },
  engageLeft: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  engageBtn: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 8, paddingVertical: 4 },
  engageCount: { fontSize: 13, fontWeight: '700', color: '#1A1A1A' },

  // Comments
  commentsHeader: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingTop: 16, paddingBottom: 8,
  },
  commentsTitle: { fontSize: 16, fontWeight: '800', color: '#1A1A1A' },
  commentsCount: {
    fontSize: 12, fontWeight: '700', color: '#999',
    backgroundColor: '#F5F0EB', paddingHorizontal: 8, paddingVertical: 3, borderRadius: 10,
  },
  commentItem: { flexDirection: 'row', paddingHorizontal: 20, paddingVertical: 6 },
  commentAv: { width: 32, height: 32, borderRadius: 16 },
  commentAvFb: { backgroundColor: '#50C8A8', justifyContent: 'center', alignItems: 'center' },
  commentAvInit: { color: '#FFF', fontSize: 12, fontWeight: '700' },
  commentBody: { flex: 1, marginLeft: 10 },
  commentBubble: {
    backgroundColor: '#F5F2EC', borderRadius: 14, paddingHorizontal: 12, paddingVertical: 8,
    borderTopLeftRadius: 4,
  },
  commentUsername: { fontSize: 13, fontWeight: '700', color: '#1A1A1A', marginBottom: 2 },
  commentText: { fontSize: 14, color: '#333', lineHeight: 20 },
  commentTime: { fontSize: 11, color: '#BBB', marginTop: 4, marginLeft: 4 },
  emptyComments: { alignItems: 'center', paddingVertical: 40 },
  emptyTitle: { fontSize: 15, fontWeight: '700', color: '#1A1A1A', marginTop: 10 },
  emptySub: { fontSize: 13, color: '#AAA', marginTop: 4 },

  // Input bar
  inputBar: {
    flexDirection: 'row', alignItems: 'center',
    paddingHorizontal: 16, paddingTop: 10,
    backgroundColor: '#FFF', borderTopWidth: 1, borderTopColor: '#F0EDE7',
  },
  inputAvatar: {
    width: 32, height: 32, borderRadius: 16, overflow: 'hidden',
    backgroundColor: '#50C8A8', justifyContent: 'center', alignItems: 'center', marginRight: 10,
  },
  inputAvatarText: { color: '#FFF', fontSize: 12, fontWeight: '700' },
  inputWrap: {
    flex: 1, backgroundColor: '#F5F2EC', borderRadius: 20,
    paddingHorizontal: 14, minHeight: 38, justifyContent: 'center',
  },
  commentInput: { fontSize: 14, color: '#1A1A1A', maxHeight: 80, paddingVertical: 8 },
  sendBtn: {
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: '#1A1A1A', justifyContent: 'center', alignItems: 'center', marginLeft: 8,
  },
});
