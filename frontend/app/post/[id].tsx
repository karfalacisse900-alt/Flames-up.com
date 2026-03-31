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
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, borderRadius } from '../../src/utils/theme';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';
import { formatDistanceToNow } from 'date-fns';

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
    } catch (error) {
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

  const renderComment = ({ item }: { item: any }) => (
    <View style={styles.commentItem}>
      <TouchableOpacity onPress={() => router.push(`/user/${item.user_id}`)}>
        {item.user_profile_image ? (
          <Image source={{ uri: item.user_profile_image }} style={styles.commentAvatar} />
        ) : (
          <View style={styles.commentAvatarPlaceholder}>
            <Text style={styles.commentAvatarText}>{item.user_username[0].toUpperCase()}</Text>
          </View>
        )}
      </TouchableOpacity>
      <View style={styles.commentContent}>
        <View style={styles.commentBubble}>
          <TouchableOpacity onPress={() => router.push(`/user/${item.user_id}`)}>
            <Text style={styles.commentUsername}>{item.user_full_name}</Text>
          </TouchableOpacity>
          <Text style={styles.commentText}>{item.content}</Text>
        </View>
        <Text style={styles.commentTime}>
          {formatDistanceToNow(new Date(item.created_at), { addSuffix: true })}
        </Text>
      </View>
    </View>
  );

  if (isLoading) {
    return (
      <SafeAreaView style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
      </SafeAreaView>
    );
  }

  if (!post) {
    return (
      <SafeAreaView style={styles.loadingContainer}>
        <Text style={styles.errorText}>Post not found</Text>
      </SafeAreaView>
    );
  }

  const timeAgo = formatDistanceToNow(new Date(post.created_at), { addSuffix: true });

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={24} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>Post</Text>
        <View style={{ width: 24 }} />
      </View>

      <FlatList
        data={comments}
        renderItem={renderComment}
        keyExtractor={(item) => item.id}
        ListHeaderComponent={
          <View>
            {/* Post Content */}
            <View style={styles.postSection}>
              <TouchableOpacity
                style={styles.postHeader}
                onPress={() => router.push(`/user/${post.user_id}`)}
              >
                {post.user_profile_image ? (
                  <Image source={{ uri: post.user_profile_image }} style={styles.avatar} />
                ) : (
                  <View style={styles.avatarPlaceholder}>
                    <Text style={styles.avatarText}>{post.user_username[0].toUpperCase()}</Text>
                  </View>
                )}
                <View>
                  <Text style={styles.userName}>{post.user_full_name}</Text>
                  <Text style={styles.userHandle}>@{post.user_username} · {timeAgo}</Text>
                </View>
              </TouchableOpacity>

              <Text style={styles.postContent}>{post.content}</Text>

              {post.image && (
                <Image source={{ uri: post.image }} style={styles.postImage} resizeMode="cover" />
              )}

              {post.location && (
                <View style={styles.locationRow}>
                  <Ionicons name="location-outline" size={14} color={colors.textTertiary} />
                  <Text style={styles.locationText}>{post.location}</Text>
                </View>
              )}

              {/* Actions */}
              <View style={styles.actions}>
                <TouchableOpacity style={styles.actionButton} onPress={handleLike}>
                  <Ionicons
                    name={liked ? 'heart' : 'heart-outline'}
                    size={24}
                    color={liked ? colors.error : colors.textSecondary}
                  />
                  <Text style={[styles.actionText, liked && styles.likedText]}>{likesCount}</Text>
                </TouchableOpacity>
                <View style={styles.actionButton}>
                  <Ionicons name="chatbubble-outline" size={22} color={colors.textSecondary} />
                  <Text style={styles.actionText}>{comments.length}</Text>
                </View>
              </View>
            </View>

            {/* Comments Header */}
            <View style={styles.commentsHeader}>
              <Text style={styles.commentsTitle}>Comments</Text>
            </View>
          </View>
        }
        ListEmptyComponent={
          <View style={styles.emptyComments}>
            <Text style={styles.emptyText}>No comments yet. Be the first!</Text>
          </View>
        }
        showsVerticalScrollIndicator={false}
      />

      {/* Comment Input */}
      <View style={styles.inputContainer}>
        <TextInput
          style={styles.input}
          placeholder="Write a comment..."
          placeholderTextColor={colors.textTertiary}
          value={newComment}
          onChangeText={setNewComment}
          multiline
          maxLength={500}
        />
        <TouchableOpacity
          style={[styles.sendButton, (!newComment.trim() || isCommenting) && styles.sendButtonDisabled]}
          onPress={handleComment}
          disabled={!newComment.trim() || isCommenting}
        >
          {isCommenting ? (
            <ActivityIndicator size="small" color={colors.textInverse} />
          ) : (
            <Ionicons name="send" size={18} color={colors.textInverse} />
          )}
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.background,
  },
  errorText: {
    fontSize: 16,
    color: colors.textSecondary,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderLight,
  },
  headerTitle: {
    fontSize: 17,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  postSection: {
    padding: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderLight,
  },
  postHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: spacing.md,
  },
  avatar: {
    width: 48,
    height: 48,
    borderRadius: 24,
    marginRight: spacing.sm,
  },
  avatarPlaceholder: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: spacing.sm,
  },
  avatarText: {
    color: colors.textInverse,
    fontSize: 20,
    fontWeight: '600',
  },
  userName: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  userHandle: {
    fontSize: 13,
    color: colors.textSecondary,
  },
  postContent: {
    fontSize: 17,
    lineHeight: 24,
    color: colors.textPrimary,
    marginBottom: spacing.md,
  },
  postImage: {
    width: '100%',
    height: 300,
    borderRadius: borderRadius.md,
    marginBottom: spacing.md,
  },
  locationRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: spacing.md,
  },
  locationText: {
    fontSize: 13,
    color: colors.textTertiary,
    marginLeft: 4,
  },
  actions: {
    flexDirection: 'row',
    paddingTop: spacing.sm,
    borderTopWidth: 1,
    borderTopColor: colors.borderLight,
  },
  actionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    marginRight: spacing.xl,
  },
  actionText: {
    fontSize: 14,
    color: colors.textSecondary,
    marginLeft: 6,
  },
  likedText: {
    color: colors.error,
  },
  commentsHeader: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  commentsTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  commentItem: {
    flexDirection: 'row',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  commentAvatar: {
    width: 36,
    height: 36,
    borderRadius: 18,
  },
  commentAvatarPlaceholder: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  commentAvatarText: {
    color: colors.textInverse,
    fontSize: 14,
    fontWeight: '600',
  },
  commentContent: {
    flex: 1,
    marginLeft: spacing.sm,
  },
  commentBubble: {
    backgroundColor: colors.backgroundSecondary,
    borderRadius: borderRadius.md,
    padding: spacing.sm,
  },
  commentUsername: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.textPrimary,
    marginBottom: 2,
  },
  commentText: {
    fontSize: 14,
    color: colors.textPrimary,
    lineHeight: 20,
  },
  commentTime: {
    fontSize: 11,
    color: colors.textTertiary,
    marginTop: 4,
    marginLeft: spacing.sm,
  },
  emptyComments: {
    paddingVertical: spacing.xl,
    alignItems: 'center',
  },
  emptyText: {
    fontSize: 14,
    color: colors.textTertiary,
  },
  inputContainer: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    padding: spacing.md,
    borderTopWidth: 1,
    borderTopColor: colors.borderLight,
  },
  input: {
    flex: 1,
    backgroundColor: colors.backgroundSecondary,
    borderRadius: borderRadius.lg,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    fontSize: 15,
    color: colors.textPrimary,
    maxHeight: 80,
  },
  sendButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
    marginLeft: spacing.sm,
  },
  sendButtonDisabled: {
    opacity: 0.5,
  },
});
