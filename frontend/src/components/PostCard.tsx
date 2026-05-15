import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  useWindowDimensions,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, borderRadius, hitSlop, layout, typography, shadows } from '../utils/theme';
import { formatDistanceToNow } from 'date-fns';
import api from '../api/client';
import MediaPreview from './MediaPreview';
import OptimizedImage from './OptimizedImage';

interface Post {
  id: string;
  user_id: string;
  user_username: string;
  user_full_name: string;
  user_profile_image?: string;
  content: string;
  image?: string;
  media_types?: string[] | string;
  location?: string;
  likes_count: number;
  comments_count: number;
  liked_by: string[];
  created_at: string;
}

interface PostCardProps {
  post: Post;
  currentUserId: string;
  onPress?: () => void;
  onUserPress?: () => void;
  onCommentPress?: () => void;
}

export default function PostCard({
  post,
  currentUserId,
  onPress,
  onUserPress,
  onCommentPress,
}: PostCardProps) {
  const { width } = useWindowDimensions();
  const [liked, setLiked] = useState(post.liked_by?.includes(currentUserId));
  const [likesCount, setLikesCount] = useState(post.likes_count);
  const [isLiking, setIsLiking] = useState(false);

  const handleLike = async () => {
    if (isLiking) return;
    setIsLiking(true);
    const nextLiked = !liked;
    const nextCount = Math.max(0, liked ? likesCount - 1 : likesCount + 1);
    
    // Optimistic update
    setLiked(nextLiked);
    setLikesCount(nextCount);
    
    try {
      const response = await api.post(`/posts/${post.id}/like`, { liked: nextLiked });
      if (typeof response.data?.liked === 'boolean') setLiked(response.data.liked);
      if (Number.isFinite(Number(response.data?.likes_count))) setLikesCount(Number(response.data.likes_count));
    } catch {
      // Revert on error
      setLiked(liked);
      setLikesCount(likesCount);
    } finally {
      setIsLiking(false);
    }
  };

  const timeAgo = formatDistanceToNow(new Date(post.created_at), { addSuffix: true });

  return (
    <View style={styles.container}>
      {/* Header */}
      <TouchableOpacity
        style={styles.header}
        onPress={onUserPress}
        activeOpacity={0.72}
        accessibilityRole="button"
        accessibilityLabel={`Open ${post.user_full_name || post.user_username}'s profile`}
        hitSlop={hitSlop}
      >
        <View style={styles.avatar}>
          {post.user_profile_image ? (
            <OptimizedImage uri={post.user_profile_image} preset="avatar" style={styles.avatarImage} />
          ) : (
            <View style={styles.avatarPlaceholder}>
              <Text style={styles.avatarText}>{post.user_username[0].toUpperCase()}</Text>
            </View>
          )}
        </View>
        <View style={styles.headerInfo}>
          <Text style={styles.username}>{post.user_full_name}</Text>
          <View style={styles.metaRow}>
            <Text style={styles.handle}>@{post.user_username}</Text>
            <Text style={styles.dot}>·</Text>
            <Text style={styles.time}>{timeAgo}</Text>
          </View>
        </View>
        <TouchableOpacity style={styles.moreButton} accessibilityRole="button" accessibilityLabel="More post options" hitSlop={hitSlop}>
          <Ionicons name="ellipsis-horizontal" size={20} color={colors.textHint} />
        </TouchableOpacity>
      </TouchableOpacity>

      {/* Content */}
      <TouchableOpacity onPress={onPress} activeOpacity={0.9}>
        <Text style={styles.content}>{post.content}</Text>
        
        {post.image && (
          <View style={styles.imageContainer}>
            <MediaPreview uri={post.image} mediaTypes={post.media_types} style={[styles.postImage, { height: Math.min(520, Math.round((width - spacing.md * 4) * 1.25)) }]} imagePreset="feed" />
          </View>
        )}
        
        {post.location && (
          <View style={styles.locationRow}>
            <Ionicons name="location-outline" size={14} color={colors.textTertiary} />
            <Text style={styles.locationText}>{post.location}</Text>
          </View>
        )}
      </TouchableOpacity>

      {/* Actions */}
      <View style={styles.actions}>
        <TouchableOpacity style={styles.actionButton} onPress={handleLike} accessibilityRole="button" accessibilityLabel={liked ? 'Unlike post' : 'Like post'} hitSlop={hitSlop}>
          <Ionicons
            name={liked ? 'heart' : 'heart-outline'}
            size={20}
            color={liked ? colors.error : colors.textSecondary}
          />
          {likesCount > 0 && (
            <Text style={[styles.actionText, liked && styles.likedText]}>{likesCount}</Text>
          )}
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.actionButton} onPress={onCommentPress} accessibilityRole="button" accessibilityLabel="Open comments" hitSlop={hitSlop}>
          <Ionicons name="chatbubble-outline" size={18} color={colors.textSecondary} />
          {post.comments_count > 0 && (
            <Text style={styles.actionText}>{post.comments_count}</Text>
          )}
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.actionButton} accessibilityRole="button" accessibilityLabel="Share post" hitSlop={hitSlop}>
          <Ionicons name="share-outline" size={20} color={colors.textSecondary} />
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.actionButton} accessibilityRole="button" accessibilityLabel="Save post" hitSlop={hitSlop}>
          <Ionicons name="bookmark-outline" size={18} color={colors.textSecondary} />
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    borderRadius: borderRadius.card,
    paddingVertical: spacing.md,
    marginHorizontal: spacing.md,
    marginBottom: spacing.md,
    ...shadows.elevation1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.md,
    marginBottom: spacing.xs,
  },
  avatar: {
    width: 44,
    height: 44,
    borderRadius: 22,
    overflow: 'hidden',
    backgroundColor: colors.bgSubtle,
  },
  avatarImage: {
    width: '100%',
    height: '100%',
  },
  avatarPlaceholder: {
    width: '100%',
    height: '100%',
    backgroundColor: colors.accentPrimary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    color: colors.textInverse,
    fontSize: 18,
    fontWeight: '600',
  },
  headerInfo: {
    flex: 1,
    marginLeft: spacing.gutter,
  },
  username: {
    ...typography.body,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 2,
  },
  handle: {
    fontSize: 13,
    color: colors.textHint,
  },
  dot: {
    fontSize: 13,
    color: colors.textHint,
    marginHorizontal: 4,
  },
  time: {
    fontSize: 13,
    color: colors.textHint,
  },
  moreButton: {
    width: layout.minTouchTarget,
    height: layout.minTouchTarget,
    borderRadius: layout.minTouchTarget / 2,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.surfaceSoft,
  },
  content: {
    ...typography.body,
    color: colors.textPrimary,
    paddingHorizontal: spacing.md,
    marginBottom: spacing.gutter,
  },
  imageContainer: {
    marginHorizontal: spacing.md,
    borderRadius: 20,
    overflow: 'hidden',
    marginBottom: spacing.gutter,
    backgroundColor: colors.bgSubtle,
  },
  postImage: {
    width: '100%',
  },
  locationRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.md,
    marginBottom: spacing.sm,
  },
  locationText: {
    fontSize: 13,
    color: colors.textHint,
    marginLeft: 4,
  },
  actions: {
    flexDirection: 'row',
    paddingHorizontal: spacing.md,
    paddingTop: spacing.xs,
    justifyContent: 'space-between',
    gap: spacing.sm,
  },
  actionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    minHeight: layout.minTouchTarget,
    borderRadius: 22,
    paddingHorizontal: spacing.gutter,
    gap: spacing.xs,
    backgroundColor: colors.bgSubtle,
  },
  actionText: {
    fontSize: 12,
    color: colors.textSecondary,
    fontWeight: '500',
  },
  likedText: {
    color: colors.error,
  },
});
