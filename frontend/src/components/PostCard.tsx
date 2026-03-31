import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Image,
  Dimensions,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, borderRadius } from '../utils/theme';
import { formatDistanceToNow } from 'date-fns';
import api from '../api/client';

const { width } = Dimensions.get('window');

interface Post {
  id: string;
  user_id: string;
  user_username: string;
  user_full_name: string;
  user_profile_image?: string;
  content: string;
  image?: string;
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
  const [liked, setLiked] = useState(post.liked_by?.includes(currentUserId));
  const [likesCount, setLikesCount] = useState(post.likes_count);
  const [isLiking, setIsLiking] = useState(false);

  const handleLike = async () => {
    if (isLiking) return;
    setIsLiking(true);
    
    // Optimistic update
    setLiked(!liked);
    setLikesCount(liked ? likesCount - 1 : likesCount + 1);
    
    try {
      await api.post(`/posts/${post.id}/like`);
    } catch (error) {
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
      <TouchableOpacity style={styles.header} onPress={onUserPress} activeOpacity={0.7}>
        <View style={styles.avatar}>
          {post.user_profile_image ? (
            <Image source={{ uri: post.user_profile_image }} style={styles.avatarImage} />
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
        <TouchableOpacity style={styles.moreButton}>
          <Ionicons name="ellipsis-horizontal" size={20} color={colors.textTertiary} />
        </TouchableOpacity>
      </TouchableOpacity>

      {/* Content */}
      <TouchableOpacity onPress={onPress} activeOpacity={0.9}>
        <Text style={styles.content}>{post.content}</Text>
        
        {post.image && (
          <View style={styles.imageContainer}>
            <Image source={{ uri: post.image }} style={styles.postImage} resizeMode="cover" />
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
        <TouchableOpacity style={styles.actionButton} onPress={handleLike}>
          <Ionicons
            name={liked ? 'heart' : 'heart-outline'}
            size={22}
            color={liked ? colors.error : colors.textSecondary}
          />
          {likesCount > 0 && (
            <Text style={[styles.actionText, liked && styles.likedText]}>{likesCount}</Text>
          )}
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.actionButton} onPress={onCommentPress}>
          <Ionicons name="chatbubble-outline" size={20} color={colors.textSecondary} />
          {post.comments_count > 0 && (
            <Text style={styles.actionText}>{post.comments_count}</Text>
          )}
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.actionButton}>
          <Ionicons name="share-outline" size={22} color={colors.textSecondary} />
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.actionButton}>
          <Ionicons name="bookmark-outline" size={20} color={colors.textSecondary} />
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: colors.background,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderLight,
    paddingVertical: spacing.md,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.md,
    marginBottom: spacing.sm,
  },
  avatar: {
    width: 44,
    height: 44,
    borderRadius: 22,
    overflow: 'hidden',
  },
  avatarImage: {
    width: '100%',
    height: '100%',
  },
  avatarPlaceholder: {
    width: '100%',
    height: '100%',
    backgroundColor: colors.primary,
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
    marginLeft: spacing.sm,
  },
  username: {
    fontSize: 15,
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
    color: colors.textTertiary,
  },
  dot: {
    fontSize: 13,
    color: colors.textTertiary,
    marginHorizontal: 4,
  },
  time: {
    fontSize: 13,
    color: colors.textTertiary,
  },
  moreButton: {
    padding: spacing.xs,
  },
  content: {
    fontSize: 15,
    lineHeight: 22,
    color: colors.textPrimary,
    paddingHorizontal: spacing.md,
    marginBottom: spacing.sm,
  },
  imageContainer: {
    marginHorizontal: spacing.md,
    borderRadius: borderRadius.md,
    overflow: 'hidden',
    marginBottom: spacing.sm,
  },
  postImage: {
    width: '100%',
    height: width - spacing.md * 2,
    maxHeight: 400,
  },
  locationRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.md,
    marginBottom: spacing.sm,
  },
  locationText: {
    fontSize: 13,
    color: colors.textTertiary,
    marginLeft: 4,
  },
  actions: {
    flexDirection: 'row',
    paddingHorizontal: spacing.md,
    paddingTop: spacing.xs,
  },
  actionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    marginRight: spacing.xl,
    paddingVertical: spacing.xs,
  },
  actionText: {
    fontSize: 13,
    color: colors.textSecondary,
    marginLeft: 4,
  },
  likedText: {
    color: colors.error,
  },
});
