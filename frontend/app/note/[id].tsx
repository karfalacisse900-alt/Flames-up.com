import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  InteractionManager,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  Share,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  useWindowDimensions,
  View,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import api from '../../src/api/client';
import ReportReasonSheet, { type ReportReason } from '../../src/components/ReportReasonSheet';
import OptimizedImage from '../../src/components/OptimizedImage';
import { useAuthStore } from '../../src/store/authStore';
import {
  cacheNoteCommentsForDetail,
  cacheNoteForDetail,
  getCachedNoteCommentsForDetail,
  getCachedNoteForDetail,
} from '../../src/store/noteDetailCache';
import { useSocialState } from '../../src/store/socialState';
import { colors, spacing } from '../../src/utils/theme';

type NoteDetail = {
  id: string;
  body?: string;
  media_url?: string;
  views_count?: number;
  reactions_count?: number;
  comments_count?: number;
  shares_count?: number;
  reacted?: boolean;
  created_at?: string;
  user?: {
    id?: string;
    username?: string;
    full_name?: string;
    profile_image?: string;
    followed?: boolean;
    is_following?: boolean;
    following?: boolean;
  };
};

type NoteComment = {
  id: string;
  body: string;
  parent_id?: string;
  created_at?: string;
  likes_count?: number;
  reactions_count?: number;
  liked_by_me?: boolean;
  user?: {
    id?: string;
    username?: string;
    full_name?: string;
    profile_image?: string;
  };
};

type ThreadedNoteComment = NoteComment & { replies: NoteComment[] };

function noteAuthor(note?: NoteDetail | null) {
  return note?.user?.username || note?.user?.full_name || 'mira';
}

function displayName(comment?: NoteComment | null) {
  return comment?.user?.username || comment?.user?.full_name || 'user';
}

function noteTime(value?: string) {
  if (!value) return 'now';
  const timestamp = new Date(value).getTime();
  if (!Number.isFinite(timestamp)) return 'now';
  const minutes = Math.max(0, Math.floor((Date.now() - timestamp) / 60000));
  if (minutes < 1) return 'now';
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h`;
  return `${Math.floor(hours / 24)}d`;
}

function formatCompactCount(value?: number) {
  const count = Math.max(0, Number(value || 0));
  if (count >= 1_000_000) return `${(count / 1_000_000).toFixed(count >= 10_000_000 ? 0 : 1).replace('.0', '')}M`;
  if (count >= 1_000) return `${(count / 1_000).toFixed(count >= 10_000 ? 0 : 1).replace('.0', '')}K`;
  return `${count}`;
}

function buildCommentThreads(items: NoteComment[]): ThreadedNoteComment[] {
  const ids = new Set(items.map((item) => String(item.id || '')));
  const repliesByParent = new Map<string, NoteComment[]>();
  const topLevel: NoteComment[] = [];

  items.forEach((item) => {
    const parentId = String(item.parent_id || '');
    if (parentId && ids.has(parentId)) {
      const bucket = repliesByParent.get(parentId) || [];
      bucket.push(item);
      repliesByParent.set(parentId, bucket);
    } else {
      topLevel.push(item);
    }
  });

  return topLevel.map((item) => ({
    ...item,
    replies: repliesByParent.get(String(item.id || '')) || [],
  }));
}

export default function NoteDetailScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { width } = useWindowDimensions();
  const { id } = useLocalSearchParams<{ id: string }>();
  const { user } = useAuthStore();
  const followedUserFlags = useSocialState((state) => state.followedUserIds);
  const setUserFollowing = useSocialState((state) => state.setUserFollowing);
  const inputRef = useRef<TextInput>(null);
  const noteId = String(id || '');
  const initialCachedNoteRef = useRef<NoteDetail | null>(getCachedNoteForDetail(noteId));
  const initialCachedCommentsRef = useRef<NoteComment[] | null>(getCachedNoteCommentsForDetail(noteId));
  const [note, setNote] = useState<NoteDetail | null>(initialCachedNoteRef.current);
  const [comments, setComments] = useState<NoteComment[]>(initialCachedCommentsRef.current || []);
  const [loading, setLoading] = useState(!initialCachedNoteRef.current);
  const [commentsLoading, setCommentsLoading] = useState(!initialCachedCommentsRef.current);
  const [commentDraft, setCommentDraft] = useState('');
  const [commentPosting, setCommentPosting] = useState(false);
  const [replyingToComment, setReplyingToComment] = useState<NoteComment | null>(null);
  const [expandedReplyIds, setExpandedReplyIds] = useState<Set<string>>(new Set());
  const [reportSheetVisible, setReportSheetVisible] = useState(false);
  const [reportSubmitting, setReportSubmitting] = useState(false);

  const mediaWidth = Math.min(width - spacing.md * 2, 430);
  const mediaHeight = Math.round(mediaWidth * 0.76);
  const threadedComments = useMemo(() => buildCommentThreads(comments), [comments]);
  const noteAuthorId = String(note?.user?.id || '');
  const noteAuthorFollowing = !!(
    followedUserFlags[noteAuthorId]
    ?? note?.user?.is_following
    ?? note?.user?.following
    ?? note?.user?.followed
  );
  const canFollowAuthor = !!noteAuthorId && noteAuthorId !== user?.id;

  const loadNote = useCallback(async () => {
    if (!noteId) return;
    if (!getCachedNoteForDetail(noteId)) setLoading(true);
    try {
      const response = await api.get(`/notes/${noteId}`);
      const nextNote = response.data || null;
      if (nextNote) cacheNoteForDetail(nextNote);
      setNote(nextNote);
    } catch {
      if (!getCachedNoteForDetail(noteId)) setNote(null);
    } finally {
      setLoading(false);
    }
  }, [noteId]);

  const loadComments = useCallback(async () => {
    if (!noteId) return;
    setCommentsLoading(true);
    try {
      const response = await api.get(`/notes/${noteId}/comments`);
      const nextComments = Array.isArray(response.data) ? response.data : [];
      cacheNoteCommentsForDetail(noteId, nextComments);
      setComments(nextComments);
    } catch {
      setComments([]);
    } finally {
      setCommentsLoading(false);
    }
  }, [noteId]);

  useEffect(() => {
    let noteTask: { cancel?: () => void } | null = null;
    let commentsTask: { cancel?: () => void } | null = null;
    const cached = getCachedNoteForDetail(noteId);
    const cachedComments = getCachedNoteCommentsForDetail(noteId);
    if (cached) {
      setNote(cached);
      setLoading(false);
    }
    setComments(cachedComments || []);
    setCommentsLoading(!cachedComments);
    if (cached) {
      noteTask = InteractionManager.runAfterInteractions(() => {
        void loadNote();
      });
    } else {
      void loadNote();
    }
    commentsTask = InteractionManager.runAfterInteractions(() => {
      void loadComments();
    });
    return () => {
      noteTask?.cancel?.();
      commentsTask?.cancel?.();
    };
  }, [loadComments, loadNote, noteId]);

  const toggleLike = useCallback(async () => {
    if (!note) return;
    const wasReacted = !!note.reacted;
    setNote((current) => current ? {
      ...current,
      reacted: !wasReacted,
      reactions_count: Math.max(0, Number(current.reactions_count || 0) + (wasReacted ? -1 : 1)),
    } : current);
    try {
      await api.post(`/notes/${note.id}/interactions`, { kind: 'reaction', value: 'heart' });
    } catch {
      setNote((current) => current ? {
        ...current,
        reacted: wasReacted,
        reactions_count: Math.max(0, Number(current.reactions_count || 0) + (wasReacted ? 1 : -1)),
      } : current);
    }
  }, [note]);

  const shareNote = useCallback(async () => {
    if (!note) return;
    try {
      const message = note.body?.trim()
        ? `${noteAuthor(note)} on MIRA: ${note.body.trim()}`
        : `${noteAuthor(note)} shared a note on MIRA.`;
      await Share.share({ message });
      setNote((current) => current ? { ...current, shares_count: Number(current.shares_count || 0) + 1 } : current);
      await api.post(`/notes/${note.id}/interactions`, { kind: 'share' }).catch(() => undefined);
    } catch {
      // The native share sheet can reject when dismissed.
    }
  }, [note]);

  const postComment = useCallback(async () => {
    const body = commentDraft.trim();
    if (!noteId || body.length < 1 || commentPosting) return;
    const parentId = replyingToComment?.parent_id || replyingToComment?.id || '';
    setCommentPosting(true);
    try {
      const response = await api.post(`/notes/${noteId}/comments`, {
        body,
        parent_id: parentId || undefined,
      });
      const created: NoteComment = {
        id: response.data?.id || `${Date.now()}`,
        body: response.data?.body || body,
        parent_id: parentId,
        created_at: response.data?.created_at || new Date().toISOString(),
        user: {
          id: user?.id,
          username: user?.username,
          full_name: user?.full_name,
          profile_image: user?.profile_image,
        },
      };
      setComments((current) => {
        const next = [...current, created];
        cacheNoteCommentsForDetail(noteId, next);
        return next;
      });
      setCommentDraft('');
      setReplyingToComment(null);
      if (parentId) setExpandedReplyIds((current) => new Set(current).add(parentId));
      setNote((current) => current ? { ...current, comments_count: Number(current.comments_count || 0) + 1 } : current);
    } catch {
      Alert.alert('Reply failed', 'Could not post that reply. Please try again.');
    } finally {
      setCommentPosting(false);
    }
  }, [commentDraft, commentPosting, noteId, replyingToComment?.id, user]);

  const reportNote = useCallback(async (reason: ReportReason) => {
    if (!note || reportSubmitting) return;
    if (!user?.id) {
      router.push('/login' as any);
      return;
    }
    setReportSubmitting(true);
    try {
      await api.post(`/notes/${note.id}/report`, {
        reason: reason.id,
        details: reason.details,
      });
      setReportSheetVisible(false);
      Alert.alert('Reported', 'Thanks. We sent this note to moderation.');
    } catch (error: any) {
      Alert.alert('Report failed', error?.response?.data?.detail || 'Could not report this note.');
    } finally {
      setReportSubmitting(false);
    }
  }, [note, reportSubmitting, router, user?.id]);

  const markNoteNotInterested = useCallback(() => {
    Alert.alert('Hidden', 'We will show fewer notes like this.');
    router.back();
  }, [router]);

  const openNoteMenu = useCallback(() => {
    Alert.alert('Note options', undefined, [
      { text: 'Not interested', onPress: markNoteNotInterested },
      { text: 'Report', style: 'destructive', onPress: () => setReportSheetVisible(true) },
      { text: 'Cancel', style: 'cancel' },
    ]);
  }, [markNoteNotInterested]);

  const toggleNoteAuthorFollow = useCallback(async () => {
    const targetId = noteAuthorId;
    if (!targetId || targetId === user?.id) return;
    if (!user?.id) {
      router.push('/login' as any);
      return;
    }

    const wasFollowing = noteAuthorFollowing;
    const nextFollowing = !wasFollowing;
    setUserFollowing(targetId, nextFollowing);
    setNote((current) => current ? {
      ...current,
      user: current.user ? {
        ...current.user,
        followed: nextFollowing,
        following: nextFollowing,
        is_following: nextFollowing,
      } : current.user,
    } : current);

    try {
      const response = await api.post(`/users/${targetId}/follow`, { following: nextFollowing });
      if (typeof response.data?.following === 'boolean') {
        const serverFollowing = !!response.data.following;
        setUserFollowing(targetId, serverFollowing);
        setNote((current) => current ? {
          ...current,
          user: current.user ? {
            ...current.user,
            followed: serverFollowing,
            following: serverFollowing,
            is_following: serverFollowing,
          } : current.user,
        } : current);
      }
    } catch (error: any) {
      setUserFollowing(targetId, wasFollowing);
      setNote((current) => current ? {
        ...current,
        user: current.user ? {
          ...current.user,
          followed: wasFollowing,
          following: wasFollowing,
          is_following: wasFollowing,
        } : current.user,
      } : current);
      Alert.alert('Follow failed', error?.response?.data?.detail || 'Could not follow this user.');
    }
  }, [noteAuthorFollowing, noteAuthorId, router, setUserFollowing, user?.id]);

  const toggleCommentLike = useCallback(async (comment: NoteComment) => {
    const commentId = String(comment.id || '');
    if (!commentId) return;
    const wasLiked = !!comment.liked_by_me;
    const previousCount = Number(comment.likes_count || comment.reactions_count || 0);
    const optimisticCount = Math.max(0, previousCount + (wasLiked ? -1 : 1));
    setComments((current) => {
      const next = current.map((item) => {
        if (String(item.id) !== commentId) return item;
        return {
          ...item,
          liked_by_me: !wasLiked,
          likes_count: optimisticCount,
        };
      });
      cacheNoteCommentsForDetail(noteId, next);
      return next;
    });
    try {
      const response = await api.post(`/note-comments/${commentId}/like`, { liked: !wasLiked });
      setComments((current) => {
        const next = current.map((item) => (
          String(item.id) === commentId
            ? { ...item, liked_by_me: !!response.data?.liked, likes_count: Number(response.data?.likes_count ?? optimisticCount) }
            : item
        ));
        cacheNoteCommentsForDetail(noteId, next);
        return next;
      });
    } catch {
      setComments((current) => {
        const next = current.map((item) => (
          String(item.id) === commentId
            ? { ...item, liked_by_me: wasLiked, likes_count: previousCount }
            : item
        ));
        cacheNoteCommentsForDetail(noteId, next);
        return next;
      });
    }
  }, [noteId]);

  const startReply = useCallback((comment: NoteComment) => {
    setReplyingToComment(comment);
    requestAnimationFrame(() => inputRef.current?.focus());
  }, []);

  const toggleReplies = useCallback((commentId: string) => {
    setExpandedReplyIds((current) => {
      const next = new Set(current);
      if (next.has(commentId)) next.delete(commentId);
      else next.add(commentId);
      return next;
    });
  }, []);

  if (loading && !note) {
    return (
      <View style={[s.root, s.center, { paddingTop: insets.top }]}>
        <ActivityIndicator color={colors.textPrimary} />
      </View>
    );
  }

  if (!note) {
    return (
      <View style={[s.root, s.center, { paddingTop: insets.top }]}>
        <Text style={s.emptyTitle}>Note not found</Text>
        <TouchableOpacity style={s.emptyButton} onPress={() => router.back()} activeOpacity={0.86}>
          <Text style={s.emptyButtonText}>Go back</Text>
        </TouchableOpacity>
      </View>
    );
  }

  const author = noteAuthor(note);

  return (
    <KeyboardAvoidingView
      style={s.root}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      keyboardVerticalOffset={0}
    >
      <View style={[s.header, { paddingTop: insets.top + 6 }]}>
        <TouchableOpacity style={s.headerButton} onPress={() => router.back()} activeOpacity={0.84}>
          <Ionicons name="chevron-back" size={30} color={colors.textPrimary} />
        </TouchableOpacity>
        <View style={s.headerActions}>
          <TouchableOpacity style={s.headerButton} onPress={openNoteMenu} activeOpacity={0.84} accessibilityLabel="More note actions">
            <Ionicons name="ellipsis-horizontal" size={24} color={colors.textPrimary} />
          </TouchableOpacity>
        </View>
      </View>

      <ScrollView
        style={s.scroll}
        contentContainerStyle={[s.content, { paddingBottom: Math.max(insets.bottom, spacing.md) + 104 }]}
        showsVerticalScrollIndicator={false}
      >
        <View style={s.threadPost}>
          <View style={s.threadAuthorRow}>
            <View style={s.avatarWrap}>
              {note.user?.profile_image ? (
                <OptimizedImage uri={note.user.profile_image} preset="avatar" style={s.avatar} />
              ) : (
                <View style={s.avatarFallback}>
                  <Text style={s.avatarText}>{author.slice(0, 1).toUpperCase()}</Text>
                </View>
              )}
              {canFollowAuthor ? (
                <TouchableOpacity
                  style={[s.followBadge, noteAuthorFollowing && s.followBadgeOn]}
                  onPress={toggleNoteAuthorFollow}
                  activeOpacity={0.86}
                  accessibilityLabel={noteAuthorFollowing ? 'Unfollow note author' : 'Follow note author'}
                >
                  <Ionicons name={noteAuthorFollowing ? 'checkmark' : 'add'} size={12} color="#FFFFFF" />
                </TouchableOpacity>
              ) : null}
            </View>
            <View style={s.authorCopy}>
              <Text style={s.authorName} numberOfLines={1}>{author}</Text>
              <Text style={s.metaText}>{noteTime(note.created_at)}</Text>
            </View>
          </View>

          {note.body ? <Text style={s.bodyText}>{note.body}</Text> : null}

          {note.media_url ? (
            <OptimizedImage
              uri={note.media_url}
              preset="detail"
              style={[s.media, { height: mediaHeight }]}
              resizeMode="cover"
              priority="high"
            />
          ) : null}

          <View style={s.threadActionRow}>
            <TouchableOpacity style={s.threadAction} onPress={toggleLike} activeOpacity={0.78}>
              <Ionicons name={note.reacted ? 'heart' : 'heart-outline'} size={23} color={note.reacted ? colors.accentPrimary : colors.textSecondary} />
              <Text style={s.threadActionText}>{formatCompactCount(note.reactions_count)}</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.threadAction} onPress={() => inputRef.current?.focus()} activeOpacity={0.78}>
              <Ionicons name="chatbubble-outline" size={22} color={colors.textSecondary} />
              <Text style={s.threadActionText}>{formatCompactCount(note.comments_count || comments.length)}</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.threadAction} onPress={shareNote} activeOpacity={0.78}>
              <Ionicons name="paper-plane-outline" size={22} color={colors.textSecondary} />
              <Text style={s.threadActionText}>{formatCompactCount(note.shares_count)}</Text>
            </TouchableOpacity>
          </View>
        </View>

        <View style={s.commentsSection}>
          {commentsLoading ? (
            <View style={s.commentState}>
              <ActivityIndicator color={colors.textPrimary} />
            </View>
          ) : threadedComments.length ? (
            threadedComments.map((comment) => {
              const name = displayName(comment);
              const commentId = String(comment.id || '');
              const replies = comment.replies || [];
              const repliesExpanded = expandedReplyIds.has(commentId);
              return (
                <View key={comment.id} style={s.commentRow}>
                  {comment.user?.profile_image ? (
                    <OptimizedImage uri={comment.user.profile_image} preset="avatar" style={s.commentAvatar} />
                  ) : (
                    <View style={s.commentAvatarFallback}>
                      <Text style={s.commentAvatarText}>{name.slice(0, 1).toUpperCase()}</Text>
                    </View>
                  )}
                  <View style={s.commentCopy}>
                    <Text style={s.commentName} numberOfLines={1}>{name}</Text>
                    <Text style={s.commentBody}>{comment.body}</Text>
                    <View style={s.commentMetaRow}>
                      <View style={s.commentLeftMeta}>
                        <Text style={s.commentTime}>{noteTime(comment.created_at)}</Text>
                        <TouchableOpacity onPress={() => startReply(comment)} activeOpacity={0.75}>
                          <Text style={s.commentReplyText}>Reply</Text>
                        </TouchableOpacity>
                      </View>
                      <TouchableOpacity style={s.commentLikeButton} onPress={() => toggleCommentLike(comment)} activeOpacity={0.75}>
                        <Ionicons name={comment.liked_by_me ? 'heart' : 'heart-outline'} size={24} color={comment.liked_by_me ? colors.accentPrimary : colors.textSecondary} />
                        <Text style={[s.commentLikeCount, comment.liked_by_me && s.commentActionTextOn]}>
                          {formatCompactCount(comment.likes_count ?? comment.reactions_count)}
                        </Text>
                      </TouchableOpacity>
                    </View>
                    {replies.length ? (
                      <>
                        <TouchableOpacity
                          style={s.viewRepliesRow}
                          activeOpacity={0.76}
                          onPress={() => toggleReplies(commentId)}
                        >
                          <View style={s.viewRepliesLine} />
                          <Text style={s.viewRepliesText}>
                            {repliesExpanded ? 'Hide replies' : `View ${replies.length} ${replies.length === 1 ? 'reply' : 'replies'}`}
                          </Text>
                          <Ionicons name={repliesExpanded ? 'chevron-up' : 'chevron-down'} size={18} color={colors.textHint} />
                        </TouchableOpacity>
                        {repliesExpanded ? (
                          <View style={s.nestedReplies}>
                            {replies.map((reply) => {
                              const replyName = displayName(reply);
                              return (
                                <View key={reply.id} style={s.nestedReplyRow}>
                                  {reply.user?.profile_image ? (
                                    <OptimizedImage uri={reply.user.profile_image} preset="avatar" style={s.nestedReplyAvatar} />
                                  ) : (
                                    <View style={s.nestedReplyAvatarFallback}>
                                      <Text style={s.nestedReplyAvatarText}>{replyName.slice(0, 1).toUpperCase()}</Text>
                                    </View>
                                  )}
                                  <View style={s.nestedReplyCopy}>
                                    <Text style={s.commentName} numberOfLines={1}>{replyName}</Text>
                                    <Text style={s.nestedReplyBody}>{reply.body}</Text>
                                    <View style={s.commentMetaRow}>
                                      <View style={s.commentLeftMeta}>
                                        <Text style={s.commentTime}>{noteTime(reply.created_at)}</Text>
                                        <TouchableOpacity onPress={() => startReply(comment)} activeOpacity={0.75}>
                                          <Text style={s.commentReplyText}>Reply</Text>
                                        </TouchableOpacity>
                                      </View>
                                      <TouchableOpacity style={s.commentLikeButton} onPress={() => toggleCommentLike(reply)} activeOpacity={0.75}>
                                        <Ionicons name={reply.liked_by_me ? 'heart' : 'heart-outline'} size={21} color={reply.liked_by_me ? colors.accentPrimary : colors.textSecondary} />
                                        <Text style={[s.commentLikeCount, reply.liked_by_me && s.commentActionTextOn]}>
                                          {formatCompactCount(reply.likes_count ?? reply.reactions_count)}
                                        </Text>
                                      </TouchableOpacity>
                                    </View>
                                  </View>
                                </View>
                              );
                            })}
                          </View>
                        ) : null}
                      </>
                    ) : null}
                  </View>
                </View>
              );
            })
          ) : (
            <View style={s.commentState}>
              <Text style={s.commentEmptyTitle}>No replies yet</Text>
              <Text style={s.commentEmptyText}>Be first to reply.</Text>
            </View>
          )}
        </View>
      </ScrollView>

      <View style={[s.inputBar, { paddingBottom: Math.max(insets.bottom, spacing.sm) }]}>
        {replyingToComment ? (
          <View style={s.replyingBanner}>
            <Text style={s.replyingText} numberOfLines={1}>Replying to {displayName(replyingToComment)}</Text>
            <TouchableOpacity style={s.replyingCancel} onPress={() => setReplyingToComment(null)} activeOpacity={0.8}>
              <Ionicons name="close" size={16} color={colors.textSecondary} />
            </TouchableOpacity>
          </View>
        ) : null}
        <View style={s.replyPill}>
          {user?.profile_image ? (
            <OptimizedImage uri={user.profile_image} preset="avatar" style={s.replyAvatar} />
          ) : (
            <View style={s.replyAvatarFallback}>
              <Text style={s.replyAvatarText}>{(user?.username || user?.full_name || 'U').slice(0, 1).toUpperCase()}</Text>
            </View>
          )}
          <TextInput
            ref={inputRef}
            value={commentDraft}
            onChangeText={(value) => setCommentDraft(value.slice(0, 500))}
            placeholder="Add your reply..."
            placeholderTextColor={colors.textHint}
            style={s.input}
            multiline
            maxLength={500}
          />
          <TouchableOpacity style={s.replyIconButton} activeOpacity={0.78} accessibilityLabel="Add image">
            <Ionicons name="image-outline" size={27} color={colors.textPrimary} />
          </TouchableOpacity>
          <TouchableOpacity style={s.replyGifButton} activeOpacity={0.78} accessibilityLabel="Add GIF">
            <Text style={s.replyGifText}>GIF</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[s.replyIconButton, (!commentDraft.trim() || commentPosting) && s.replyIconButtonDisabled]}
            activeOpacity={0.86}
            disabled={!commentDraft.trim() || commentPosting}
            onPress={postComment}
            accessibilityLabel="Post reply"
          >
            {commentPosting ? (
              <ActivityIndicator size="small" color={colors.textPrimary} />
            ) : (
              <Ionicons name="arrow-up" size={28} color={commentDraft.trim() ? colors.textPrimary : colors.textHint} />
            )}
          </TouchableOpacity>
        </View>
      </View>

      <ReportReasonSheet
        visible={reportSheetVisible}
        submitting={reportSubmitting}
        onClose={() => {
          if (!reportSubmitting) setReportSheetVisible(false);
        }}
        onSelect={reportNote}
      />
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.bgApp },
  center: { alignItems: 'center', justifyContent: 'center', paddingHorizontal: spacing.lg, gap: spacing.md },
  header: {
    minHeight: 58,
    paddingHorizontal: spacing.sm,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: colors.bgApp,
  },
  headerButton: { width: 42, height: 42, alignItems: 'center', justifyContent: 'center' },
  headerActions: { flexDirection: 'row', alignItems: 'center' },
  scroll: { flex: 1 },
  content: { paddingHorizontal: spacing.md, paddingTop: spacing.sm },
  threadPost: {
    gap: spacing.sm,
    paddingBottom: spacing.sm,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.borderSubtle,
  },
  threadAuthorRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  avatarWrap: { width: 40, height: 40, borderRadius: 20, position: 'relative' },
  avatar: { width: 40, height: 40, borderRadius: 20, backgroundColor: colors.bgSubtle },
  followBadge: {
    position: 'absolute',
    right: -3,
    bottom: -4,
    width: 19,
    height: 19,
    borderRadius: 10,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.accentPrimary,
    borderWidth: 2,
    borderColor: colors.bgApp,
  },
  followBadgeOn: { backgroundColor: colors.textPrimary },
  avatarFallback: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.accentPrimaryLight,
  },
  avatarText: { color: colors.textPrimary, fontSize: 14, lineHeight: 18, fontWeight: '700' },
  authorCopy: { flex: 1, minWidth: 0, flexDirection: 'row', alignItems: 'center', gap: 7 },
  authorName: { color: colors.textPrimary, fontSize: 15, lineHeight: 20, fontWeight: '700', maxWidth: '72%' },
  metaText: { color: colors.textHint, fontSize: 13, lineHeight: 18, fontWeight: '500' },
  bodyText: { color: colors.textPrimary, fontSize: 16, lineHeight: 22, fontWeight: '500', letterSpacing: 0 },
  media: {
    width: '100%',
    borderRadius: 16,
    backgroundColor: colors.bgSubtle,
  },
  threadActionRow: {
    minHeight: 38,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-start',
    gap: 24,
  },
  threadAction: { minHeight: 38, flexDirection: 'row', alignItems: 'center', gap: 6 },
  threadActionText: { color: colors.textSecondary, fontSize: 14, lineHeight: 19, fontWeight: '500', fontVariant: ['tabular-nums'] },
  commentsSection: {
    paddingTop: spacing.xs,
  },
  commentState: { minHeight: 130, alignItems: 'center', justifyContent: 'center', gap: 4 },
  commentEmptyTitle: { color: colors.textPrimary, fontSize: 17, lineHeight: 22, fontWeight: '700' },
  commentEmptyText: { color: colors.textSecondary, fontSize: 14, lineHeight: 19, fontWeight: '500' },
  commentRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 9,
    paddingVertical: 11,
  },
  commentAvatar: { width: 34, height: 34, borderRadius: 17, backgroundColor: colors.bgSubtle },
  commentAvatarFallback: {
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.accentPrimaryLight,
  },
  commentAvatarText: { color: colors.textPrimary, fontSize: 12, lineHeight: 16, fontWeight: '700' },
  commentCopy: { flex: 1, minWidth: 0, gap: 3 },
  commentName: { color: colors.textHint, fontSize: 13, lineHeight: 17, fontWeight: '600', maxWidth: '82%' },
  commentTime: { color: colors.textHint, fontSize: 11, lineHeight: 15, fontWeight: '600' },
  commentBody: { color: colors.textStrong, fontSize: 14, lineHeight: 20, fontWeight: '500' },
  commentMetaRow: {
    minHeight: 28,
    marginTop: 2,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: spacing.gutter,
  },
  commentLeftMeta: { flexDirection: 'row', alignItems: 'center', gap: spacing.lg },
  commentReplyText: { color: colors.textHint, fontSize: 12, lineHeight: 16, fontWeight: '700' },
  commentLikeButton: { minHeight: 30, minWidth: 44, flexDirection: 'row', alignItems: 'center', justifyContent: 'flex-end', gap: 4 },
  commentLikeCount: { color: colors.textHint, fontSize: 12, lineHeight: 16, fontWeight: '600', fontVariant: ['tabular-nums'] },
  commentActionTextOn: { color: colors.accentPrimary },
  viewRepliesRow: { marginTop: 2, flexDirection: 'row', alignItems: 'center', gap: 8, minHeight: 28 },
  viewRepliesLine: { width: 32, height: StyleSheet.hairlineWidth, backgroundColor: colors.textDisabled },
  viewRepliesText: { color: colors.textHint, fontSize: 13, lineHeight: 17, fontWeight: '700' },
  nestedReplies: { marginTop: spacing.xs, gap: spacing.gutter },
  nestedReplyRow: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.sm },
  nestedReplyAvatar: { width: 30, height: 30, borderRadius: 15, backgroundColor: colors.bgSubtle },
  nestedReplyAvatarFallback: {
    width: 30,
    height: 30,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.bgSubtle,
  },
  nestedReplyAvatarText: { color: colors.textPrimary, fontSize: 11, lineHeight: 14, fontWeight: '800' },
  nestedReplyCopy: { flex: 1, minWidth: 0, gap: 2 },
  nestedReplyBody: { color: colors.textStrong, fontSize: 13, lineHeight: 18, fontWeight: '500' },
  inputBar: {
    paddingTop: spacing.sm,
    paddingHorizontal: spacing.md,
    backgroundColor: 'transparent',
  },
  replyingBanner: {
    minHeight: 34,
    borderRadius: 17,
    paddingLeft: 13,
    paddingRight: 6,
    marginBottom: 6,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: colors.bgCard,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
  },
  replyingText: { flex: 1, color: colors.textSecondary, fontSize: 13, lineHeight: 17, fontWeight: '600' },
  replyingCancel: { width: 28, height: 28, borderRadius: 14, alignItems: 'center', justifyContent: 'center' },
  replyPill: {
    minHeight: 50,
    borderRadius: 25,
    paddingLeft: 8,
    paddingRight: 8,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: colors.bgSubtle,
  },
  replyAvatar: { width: 32, height: 32, borderRadius: 16, backgroundColor: colors.bgCard },
  replyAvatarFallback: {
    width: 32,
    height: 32,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.accentPrimaryLight,
  },
  replyAvatarText: { color: colors.textPrimary, fontSize: 13, lineHeight: 17, fontWeight: '800' },
  input: {
    flex: 1,
    minHeight: 38,
    maxHeight: 96,
    paddingTop: 9,
    paddingBottom: 7,
    color: colors.textPrimary,
    fontSize: 16,
    lineHeight: 21,
    fontWeight: '600',
  },
  replyIconButton: { width: 36, height: 40, alignItems: 'center', justifyContent: 'center' },
  replyIconButtonDisabled: { opacity: 0.58 },
  replyGifButton: {
    width: 36,
    height: 32,
    borderRadius: 10,
    borderWidth: 2,
    borderColor: colors.textPrimary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  replyGifText: { color: colors.textPrimary, fontSize: 14, lineHeight: 18, fontWeight: '900' },
  emptyTitle: { color: colors.textPrimary, fontSize: 21, lineHeight: 27, fontWeight: '700' },
  emptyButton: { minHeight: 44, borderRadius: 22, paddingHorizontal: spacing.lg, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.accentPrimary },
  emptyButtonText: { color: colors.textInverse, fontSize: 15, lineHeight: 20, fontWeight: '700' },
});
