import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Image,
  ActivityIndicator,
  TextInput,
  FlatList,
  Dimensions,
  KeyboardAvoidingView,
  Platform,
  Share,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, borderRadius, shadows } from '../../src/utils/theme';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';
import { formatDistanceToNow } from 'date-fns';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const PHOTO_RATIO = 4 / 5;

export default function PostDetailScreen() {
  const router = useRouter();
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

  useEffect(() => {
    loadPostData();
  }, [postId]);

  const loadPostData = async () => {
    try {
      const [postRes, commentsRes] = await Promise.all([
        api.get(`/posts/${postId}`),
        api.get(`/posts/${postId}/comments`),
      ]);
      setPost(postRes.data);
      setComments(commentsRes.data);
      setLiked(postRes.data.liked_by?.includes(user?.id));
      setLikesCount(postRes.data.likes_count);
    } catch (error) {
      console.log('Error loading post:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleLike = async () => {
    setLiked(!liked);
    setLikesCount(liked ? likesCount - 1 : likesCount + 1);
    try {
      await api.post(`/posts/${postId}/like`);
    } catch {
      setLiked(liked);
      setLikesCount(likesCount);
    }
  };

  const handleComment = async () => {
    if (!newComment.trim() || isCommenting) return;
    setIsCommenting(true);
    try {
      const response = await api.post(`/posts/${postId}/comments`, {
        content: newComment.trim(),
      });
      setComments([...comments, response.data]);
      setNewComment('');
    } catch (error) {
      console.log('Error posting comment:', error);
    } finally {
      setIsCommenting(false);
    }
  };

  const handleShare = async () => {
    try {
      await Share.share({ message: post?.content || 'Check out this post on Flames-Up!' });
    } catch {}
  };

  if (isLoading) {
    return (
      <SafeAreaView style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.accentPrimary} />
      </SafeAreaView>
    );
  }

  if (!post) {
    return (
      <SafeAreaView style={styles.loadingContainer}>
        <Text style={styles.errorText}>Post not found</Text>
        <TouchableOpacity onPress={() => router.back()} style={{ marginTop: 16 }}>
          <Text style={{ color: colors.accentPrimary, fontWeight: '600' }}>Go Back</Text>
        </TouchableOpacity>
      </SafeAreaView>
    );
  }

  const timeAgo = formatDistanceToNow(new Date(post.created_at), { addSuffix: true });
  const authorName = post.user_full_name || post.user_username || 'User';
  const allImages: string[] = post.images?.length > 0 ? post.images : post.image ? [post.image] : [];

  return (
    <View style={styles.container}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={{ flex: 1 }}
        keyboardVerticalOffset={0}
      >
        <FlatList
          data={comments}
          keyExtractor={(item) => item.id}
          ListHeaderComponent={
            <View>
              {/* Full-bleed image or carousel with back button overlay */}
              {allImages.length > 0 ? (
                <View style={styles.imageContainer}>
                  {allImages.length > 1 ? (
                    <View>
                      <FlatList
                        data={allImages}
                        horizontal
                        pagingEnabled
                        showsHorizontalScrollIndicator={false}
                        onMomentumScrollEnd={(e) => {
                          setActiveImgIdx(Math.round(e.nativeEvent.contentOffset.x / SCREEN_WIDTH));
                        }}
                        keyExtractor={(_, i) => `detail-img-${i}`}
                        renderItem={({ item: imgUri }) => (
                          <Image
                            source={{ uri: imgUri }}
                            style={styles.heroImage}
                            resizeMode="cover"
                          />
                        )}
                      />
                      <View style={styles.carouselDotsContainer}>
                        {allImages.map((_: string, i: number) => (
                          <View
                            key={i}
                            style={[styles.carouselDot, activeImgIdx === i && styles.carouselDotActive]}
                          />
                        ))}
                      </View>
                    </View>
                  ) : (
                    <Image
                      source={{ uri: allImages[0] }}
                      style={styles.heroImage}
                      resizeMode="cover"
                    />
                  )}
                  <TouchableOpacity style={styles.backBtnOverlay} onPress={() => router.back()}>
                    <Ionicons name="arrow-back" size={22} color="#FFFFFF" />
                  </TouchableOpacity>
                  {allImages.length > 1 && (
                    <View style={styles.imageCounter}>
                      <Text style={styles.imageCounterText}>{activeImgIdx + 1}/{allImages.length}</Text>
                    </View>
                  )}
                </View>
              ) : (
                <SafeAreaView edges={['top']}>
                  <View style={styles.headerNoImage}>
                    <TouchableOpacity onPress={() => router.back()} style={styles.backBtnFlat}>
                      <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
                    </TouchableOpacity>
                  </View>
                </SafeAreaView>
              )}

              {/* Content Section */}
              <View style={styles.contentSection}>
                {/* Author Row */}
                <TouchableOpacity
                  style={styles.authorRow}
                  onPress={() => router.push(`/user/${post.user_id}`)}
                  activeOpacity={0.7}
                >
                  <View style={styles.authorAvatar}>
                    {post.user_profile_image ? (
                      <Image source={{ uri: post.user_profile_image }} style={styles.authorAvatarImg} />
                    ) : (
                      <View style={styles.authorAvatarFallback}>
                        <Text style={styles.authorAvatarText}>
                          {authorName[0].toUpperCase()}
                        </Text>
                      </View>
                    )}
                  </View>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.authorName}>{authorName}</Text>
                    <Text style={styles.timeText}>{timeAgo}</Text>
                  </View>
                  <TouchableOpacity style={styles.followBtn}>
                    <Text style={styles.followBtnText}>Follow</Text>
                  </TouchableOpacity>
                </TouchableOpacity>

                {/* Caption */}
                <Text style={styles.caption}>{post.content}</Text>

                {/* Location */}
                {post.location && (
                  <View style={styles.locationRow}>
                    <Ionicons name="location-outline" size={14} color={colors.textHint} />
                    <Text style={styles.locationText}>{post.location}</Text>
                  </View>
                )}

                {/* Action Row */}
                <View style={styles.actionsRow}>
                  <View style={styles.actionsLeft}>
                    <TouchableOpacity onPress={handleLike} style={styles.actionBtn}>
                      <Ionicons
                        name={liked ? 'heart' : 'heart-outline'}
                        size={26}
                        color={liked ? '#ED4956' : colors.textPrimary}
                      />
                    </TouchableOpacity>
                    <TouchableOpacity style={styles.actionBtn}>
                      <Ionicons name="chatbubble-outline" size={24} color={colors.textPrimary} />
                    </TouchableOpacity>
                    <TouchableOpacity style={styles.actionBtn} onPress={handleShare}>
                      <Ionicons name="paper-plane-outline" size={24} color={colors.textPrimary} />
                    </TouchableOpacity>
                  </View>
                  <TouchableOpacity onPress={() => setSaved(!saved)} style={styles.actionBtn}>
                    <Ionicons
                      name={saved ? 'bookmark' : 'bookmark-outline'}
                      size={24}
                      color={colors.textPrimary}
                    />
                  </TouchableOpacity>
                </View>

                {/* Like count */}
                {likesCount > 0 && (
                  <Text style={styles.likesText}>
                    {likesCount} {likesCount === 1 ? 'like' : 'likes'}
                  </Text>
                )}

                {/* Comments header */}
                <View style={styles.commentsHeader}>
                  <Text style={styles.commentsTitle}>Comments ({comments.length})</Text>
                </View>
              </View>
            </View>
          }
          renderItem={({ item }) => (
            <View style={styles.commentItem}>
              <TouchableOpacity onPress={() => router.push(`/user/${item.user_id}`)}>
                {item.user_profile_image ? (
                  <Image source={{ uri: item.user_profile_image }} style={styles.commentAvatar} />
                ) : (
                  <View style={styles.commentAvatarFallback}>
                    <Text style={styles.commentAvatarText}>
                      {(item.user_username || 'U')[0].toUpperCase()}
                    </Text>
                  </View>
                )}
              </TouchableOpacity>
              <View style={styles.commentBody}>
                <Text style={styles.commentText}>
                  <Text style={styles.commentUsername}>{item.user_full_name} </Text>
                  {item.content}
                </Text>
                <Text style={styles.commentTime}>
                  {formatDistanceToNow(new Date(item.created_at), { addSuffix: true })}
                </Text>
              </View>
            </View>
          )}
          ListEmptyComponent={
            <View style={styles.emptyComments}>
              <Ionicons name="chatbubble-outline" size={36} color={colors.textHint} />
              <Text style={styles.emptyText}>No comments yet</Text>
              <Text style={styles.emptySubtext}>Start the conversation</Text>
            </View>
          }
          showsVerticalScrollIndicator={false}
          contentContainerStyle={{ paddingBottom: 80 }}
        />

        {/* Comment Input */}
        <View style={styles.inputBar}>
          <View style={styles.inputAvatar}>
            {user?.profile_image ? (
              <Image source={{ uri: user.profile_image }} style={{ width: '100%', height: '100%' }} />
            ) : (
              <Text style={styles.inputAvatarText}>
                {(user?.full_name || 'U')[0].toUpperCase()}
              </Text>
            )}
          </View>
          <TextInput
            style={styles.commentInput}
            placeholder="Add a comment..."
            placeholderTextColor={colors.textHint}
            value={newComment}
            onChangeText={setNewComment}
            multiline
            maxLength={500}
          />
          <TouchableOpacity
            onPress={handleComment}
            disabled={!newComment.trim() || isCommenting}
            style={{ padding: 8 }}
          >
            {isCommenting ? (
              <ActivityIndicator size="small" color={colors.accentPrimary} />
            ) : (
              <Text
                style={[
                  styles.postCommentBtn,
                  !newComment.trim() && { opacity: 0.3 },
                ]}
              >
                Post
              </Text>
            )}
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#FFFFFF',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.bgApp,
  },
  errorText: {
    fontSize: 16,
    color: colors.textSecondary,
  },
  // Image hero
  imageContainer: {
    width: SCREEN_WIDTH,
    height: SCREEN_WIDTH / PHOTO_RATIO,
  },
  heroImage: {
    width: SCREEN_WIDTH,
    height: SCREEN_WIDTH / PHOTO_RATIO,
  },
  backBtnOverlay: {
    position: 'absolute',
    top: 50,
    left: 16,
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(0,0,0,0.45)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  carouselDotsContainer: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 5,
    paddingVertical: 10,
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
  },
  carouselDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: 'rgba(255,255,255,0.5)',
  },
  carouselDotActive: {
    backgroundColor: '#FFFFFF',
    width: 18,
    borderRadius: 3,
  },
  imageCounter: {
    position: 'absolute',
    top: 56,
    right: 16,
    backgroundColor: 'rgba(0,0,0,0.55)',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 12,
  },
  imageCounterText: {
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: '700',
  },
  headerNoImage: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderSubtle,
  },
  backBtnFlat: {
    width: 44,
    height: 44,
    borderRadius: 22,
    justifyContent: 'center',
    alignItems: 'center',
  },
  // Content
  contentSection: {
    paddingHorizontal: 16,
    paddingTop: 16,
  },
  authorRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 14,
  },
  authorAvatar: {
    width: 44,
    height: 44,
    borderRadius: 22,
    overflow: 'hidden',
    marginRight: 12,
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  authorAvatarImg: {
    width: '100%',
    height: '100%',
  },
  authorAvatarFallback: {
    width: '100%',
    height: '100%',
    backgroundColor: colors.avatarTeal,
    justifyContent: 'center',
    alignItems: 'center',
  },
  authorAvatarText: {
    color: '#FFFFFF',
    fontSize: 18,
    fontWeight: '700',
  },
  authorName: {
    fontSize: 15,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  timeText: {
    fontSize: 12,
    color: colors.textHint,
    marginTop: 2,
  },
  followBtn: {
    backgroundColor: colors.accentPrimary,
    paddingHorizontal: 18,
    paddingVertical: 8,
    borderRadius: 18,
  },
  followBtnText: {
    fontSize: 13,
    fontWeight: '700',
    color: '#FFFFFF',
  },
  caption: {
    fontSize: 16,
    color: colors.textPrimary,
    lineHeight: 24,
    marginBottom: 12,
  },
  locationRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 12,
    gap: 4,
  },
  locationText: {
    fontSize: 13,
    color: colors.textHint,
  },
  // Actions
  actionsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 8,
    borderTopWidth: 1,
    borderTopColor: colors.borderSubtle,
  },
  actionsLeft: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  actionBtn: {
    paddingRight: 16,
    paddingVertical: 4,
  },
  likesText: {
    fontSize: 14,
    fontWeight: '700',
    color: colors.textPrimary,
    marginBottom: 12,
  },
  // Comments
  commentsHeader: {
    paddingTop: 8,
    paddingBottom: 8,
    borderTopWidth: 1,
    borderTopColor: colors.borderSubtle,
  },
  commentsTitle: {
    fontSize: 15,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  commentItem: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  commentAvatar: {
    width: 32,
    height: 32,
    borderRadius: 16,
  },
  commentAvatarFallback: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: colors.avatarTeal,
    justifyContent: 'center',
    alignItems: 'center',
  },
  commentAvatarText: {
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: '700',
  },
  commentBody: {
    flex: 1,
    marginLeft: 10,
  },
  commentText: {
    fontSize: 14,
    color: colors.textPrimary,
    lineHeight: 20,
  },
  commentUsername: {
    fontWeight: '700',
  },
  commentTime: {
    fontSize: 11,
    color: colors.textHint,
    marginTop: 4,
  },
  emptyComments: {
    alignItems: 'center',
    paddingVertical: 40,
  },
  emptyText: {
    fontSize: 15,
    fontWeight: '600',
    color: colors.textPrimary,
    marginTop: 10,
  },
  emptySubtext: {
    fontSize: 13,
    color: colors.textHint,
    marginTop: 4,
  },
  // Input bar
  inputBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderTopWidth: 1,
    borderTopColor: colors.borderSubtle,
    backgroundColor: '#FFFFFF',
  },
  inputAvatar: {
    width: 32,
    height: 32,
    borderRadius: 16,
    overflow: 'hidden',
    backgroundColor: colors.avatarTeal,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 10,
  },
  inputAvatarText: {
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: '700',
  },
  commentInput: {
    flex: 1,
    fontSize: 14,
    color: colors.textPrimary,
    maxHeight: 80,
    paddingVertical: 8,
  },
  postCommentBtn: {
    fontSize: 14,
    fontWeight: '700',
    color: colors.accentPrimary,
  },
});
