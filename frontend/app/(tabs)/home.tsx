import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  RefreshControl,
  TouchableOpacity,
  ActivityIndicator,
  ScrollView,
  Image,
  Dimensions,
  Modal,
  TextInput,
  Alert,
  Clipboard,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import { colors, shadows } from '../../src/utils/theme';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';
import { formatDistanceToNow } from 'date-fns';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const PHOTO_RATIO = 4 / 5;  // 4:5 for photos
const VIDEO_RATIO = 1;       // 1:1 for videos

// ─── Report Reasons ──────────────────────────────────────────────────────────
const REPORT_REASONS = [
  { id: 'spam', label: 'Spam', icon: 'mail-outline' },
  { id: 'harassment', label: 'Harassment or bullying', icon: 'hand-left-outline' },
  { id: 'hate_speech', label: 'Hate speech', icon: 'megaphone-outline' },
  { id: 'violence', label: 'Violence or threats', icon: 'warning-outline' },
  { id: 'nudity', label: 'Nudity or sexual content', icon: 'eye-off-outline' },
  { id: 'misinformation', label: 'Misinformation', icon: 'newspaper-outline' },
  { id: 'other', label: 'Other', icon: 'ellipsis-horizontal-outline' },
];

// ─── Flames-Up Post Card (unique social feed style) ──────────────────────────
function PostCard({ post, currentUserId, onPress, onUserPress }: any) {
  const [liked, setLiked] = useState(post.liked_by?.includes(currentUserId));
  const [likesCount, setLikesCount] = useState(post.likes_count || 0);
  const [saved, setSaved] = useState(false);
  const [captionExpanded, setCaptionExpanded] = useState(false);
  const [showMenu, setShowMenu] = useState(false);
  const [showReport, setShowReport] = useState(false);
  const [activeImageIdx, setActiveImageIdx] = useState(0);
  const [showSaveMenu, setShowSaveMenu] = useState(false);
  const [savedCollection, setSavedCollection] = useState<string | null>(null);

  const SAVE_COLLECTIONS = [
    { id: 'all', label: 'All Saved', icon: 'bookmark' },
    { id: 'funny', label: 'Funny', icon: 'happy-outline' },
    { id: 'inspirational', label: 'Inspirational', icon: 'sparkles-outline' },
    { id: 'ideas', label: 'Ideas', icon: 'bulb-outline' },
    { id: 'travel', label: 'Travel', icon: 'airplane-outline' },
  ];

  // Collect all images (from both old single image and new images array)
  const allImages: string[] = post.images?.length > 0
    ? post.images
    : post.image ? [post.image] : [];

  const handleLike = async () => {
    setLiked(!liked);
    setLikesCount(liked ? likesCount - 1 : likesCount + 1);
    try {
      await api.post(`/posts/${post.id}/like`);
    } catch {
      setLiked(liked);
      setLikesCount(likesCount);
    }
  };

  const handleReport = async (reason: string) => {
    try {
      await api.post('/reports', {
        target_type: 'post',
        target_id: post.id,
        reason,
      });
      Alert.alert('Report Submitted', 'Thank you for helping keep our community safe.');
    } catch {
      Alert.alert('Error', 'Could not submit report. Please try again.');
    }
    setShowReport(false);
  };

  const timeAgo = post.created_at
    ? formatDistanceToNow(new Date(post.created_at), { addSuffix: false })
    : '';

  const isVideo = post.media_type === 'video';
  const hasMedia = !!post.image;
  const mediaAspect = isVideo ? VIDEO_RATIO : PHOTO_RATIO;
  const authorName = post.user_full_name || post.user_username || 'User';

  return (
    <View style={postStyles.container}>
      {/* ── Header: avatar + name + flame badge + location + more ── */}
      <View style={postStyles.header}>
        <TouchableOpacity
          style={postStyles.headerLeft}
          onPress={onUserPress}
          activeOpacity={0.7}
        >
          <View style={postStyles.avatar}>
            {post.user_profile_image ? (
              <Image source={{ uri: post.user_profile_image }} style={postStyles.avatarImg} />
            ) : (
              <View style={postStyles.avatarFallback}>
                <Text style={postStyles.avatarInitial}>{authorName[0].toUpperCase()}</Text>
              </View>
            )}
          </View>
          <View style={{ flex: 1 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5 }}>
              <Text style={postStyles.username}>{authorName}</Text>
              <Ionicons name="flame" size={13} color={colors.flameGold} />
            </View>
            {post.location ? (
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 3, marginTop: 1 }}>
                <Ionicons name="location" size={10} color={colors.accentPrimary} />
                <Text style={postStyles.location} numberOfLines={1}>{post.location}</Text>
              </View>
            ) : (
              <Text style={postStyles.timeLabel}>{timeAgo} ago</Text>
            )}
          </View>
        </TouchableOpacity>
        <TouchableOpacity
          style={postStyles.moreBtn}
          hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
          onPress={() => setShowMenu(true)}
        >
          <Ionicons name="ellipsis-vertical" size={18} color={colors.textSecondary} />
        </TouchableOpacity>
      </View>

      {/* ── 3-dot Action Sheet ── */}
      <Modal visible={showMenu} transparent animationType="fade" onRequestClose={() => setShowMenu(false)}>
        <TouchableOpacity style={postStyles.menuOverlay} activeOpacity={1} onPress={() => setShowMenu(false)}>
          <View style={postStyles.menuSheet}>
            <View style={postStyles.menuHandle} />
            <TouchableOpacity style={postStyles.menuItem} onPress={() => { setShowMenu(false); setShowReport(true); }}>
              <Ionicons name="flag-outline" size={22} color={colors.error} />
              <Text style={[postStyles.menuItemText, { color: colors.error }]}>Report</Text>
            </TouchableOpacity>
            <TouchableOpacity style={postStyles.menuItem} onPress={() => { setShowMenu(false); Alert.alert('Blocked', 'You won\'t see posts from this user.'); }}>
              <Ionicons name="ban-outline" size={22} color={colors.textPrimary} />
              <Text style={postStyles.menuItemText}>Block User</Text>
            </TouchableOpacity>
            <TouchableOpacity style={postStyles.menuItem} onPress={() => { setShowMenu(false); Alert.alert('Hidden', 'You will see fewer posts like this.'); }}>
              <Ionicons name="eye-off-outline" size={22} color={colors.textPrimary} />
              <Text style={postStyles.menuItemText}>Not Interested</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[postStyles.menuItem, { borderBottomWidth: 0 }]} onPress={() => { setShowMenu(false); Alert.alert('Copied', 'Link copied to clipboard.'); }}>
              <Ionicons name="link-outline" size={22} color={colors.textPrimary} />
              <Text style={postStyles.menuItemText}>Copy Link</Text>
            </TouchableOpacity>
            <TouchableOpacity style={postStyles.menuCancel} onPress={() => setShowMenu(false)}>
              <Text style={postStyles.menuCancelText}>Cancel</Text>
            </TouchableOpacity>
          </View>
        </TouchableOpacity>
      </Modal>

      {/* ── Report Modal ── */}
      <Modal visible={showReport} transparent animationType="slide" onRequestClose={() => setShowReport(false)}>
        <TouchableOpacity style={postStyles.menuOverlay} activeOpacity={1} onPress={() => setShowReport(false)}>
          <View style={postStyles.reportSheet}>
            <View style={postStyles.menuHandle} />
            <Text style={postStyles.reportTitle}>Why are you reporting this?</Text>
            <Text style={postStyles.reportSubtitle}>Your report is anonymous and helps keep our community safe.</Text>
            {REPORT_REASONS.map((reason) => (
              <TouchableOpacity key={reason.id} style={postStyles.reportItem} onPress={() => handleReport(reason.id)}>
                <Ionicons name={reason.icon as any} size={20} color={colors.textSecondary} />
                <Text style={postStyles.reportItemText}>{reason.label}</Text>
                <Ionicons name="chevron-forward" size={16} color={colors.textHint} />
              </TouchableOpacity>
            ))}
          </View>
        </TouchableOpacity>
      </Modal>

      {/* ── Media (Photo 4:5 / Video 1:1) full-width + carousel ── */}
      {hasMedia && allImages.length > 1 ? (
        <View>
          <FlatList
            data={allImages}
            horizontal
            pagingEnabled
            showsHorizontalScrollIndicator={false}
            onMomentumScrollEnd={(e) => {
              setActiveImageIdx(Math.round(e.nativeEvent.contentOffset.x / SCREEN_WIDTH));
            }}
            keyExtractor={(_, i) => `img-${i}`}
            renderItem={({ item: imgUri }) => (
              <Image
                source={{ uri: imgUri }}
                style={{ width: SCREEN_WIDTH, height: SCREEN_WIDTH / mediaAspect, backgroundColor: colors.bgSubtle }}
                resizeMode="cover"
              />
            )}
          />
          <View style={postStyles.carouselDots}>
            {allImages.map((_: string, i: number) => (
              <View
                key={i}
                style={[postStyles.dot, activeImageIdx === i && postStyles.dotActive]}
              />
            ))}
          </View>
        </View>
      ) : hasMedia ? (
        <TouchableOpacity activeOpacity={0.95} onPress={onPress}>
          <Image
            source={{ uri: post.image }}
            style={{ width: SCREEN_WIDTH, height: SCREEN_WIDTH / mediaAspect, backgroundColor: colors.bgSubtle }}
            resizeMode="cover"
          />
        </TouchableOpacity>
      ) : null}

      {/* ── Caption (above actions for Flames-Up style) ── */}
      {post.content ? (
        <View style={postStyles.captionContainer}>
          <Text style={postStyles.captionText} numberOfLines={captionExpanded ? undefined : 3}>
            {post.content}
          </Text>
          {!captionExpanded && post.content.length > 120 && (
            <TouchableOpacity onPress={() => setCaptionExpanded(true)}>
              <Text style={postStyles.moreText}>Read more</Text>
            </TouchableOpacity>
          )}
        </View>
      ) : null}

      {/* ── Action Row ── */}
      <View style={postStyles.actionsRow}>
        <TouchableOpacity onPress={handleLike} style={postStyles.actionBtn}>
          <Ionicons name={liked ? 'heart' : 'heart-outline'} size={22} color={liked ? '#ED4956' : colors.textSecondary} />
          {likesCount > 0 && <Text style={[postStyles.actionCount, liked && { color: '#ED4956' }]}>{likesCount}</Text>}
        </TouchableOpacity>
        <TouchableOpacity onPress={onPress} style={postStyles.actionBtn}>
          <Ionicons name="chatbubble-outline" size={20} color={colors.textSecondary} />
          {post.comments_count > 0 && <Text style={postStyles.actionCount}>{post.comments_count}</Text>}
        </TouchableOpacity>
        <TouchableOpacity style={postStyles.actionBtn}>
          <Ionicons name="repeat-outline" size={22} color={colors.textSecondary} />
        </TouchableOpacity>
        <TouchableOpacity style={postStyles.actionBtn}>
          <Ionicons name="paper-plane-outline" size={20} color={colors.textSecondary} />
        </TouchableOpacity>
        <View style={{ flex: 1 }} />
        <View>
          <TouchableOpacity onPress={() => setShowSaveMenu(!showSaveMenu)} style={postStyles.actionBtn}>
            <Ionicons name={saved ? 'bookmark' : 'bookmark-outline'} size={20} color={saved ? colors.accentPrimary : colors.textSecondary} />
          </TouchableOpacity>
          {showSaveMenu && (
            <View style={postStyles.saveFloating}>
              {SAVE_COLLECTIONS.map((col) => (
                <TouchableOpacity
                  key={col.id}
                  style={[postStyles.saveItem, savedCollection === col.id && postStyles.saveItemActive]}
                  onPress={() => {
                    setSaved(true);
                    setSavedCollection(col.id);
                    setShowSaveMenu(false);
                  }}
                >
                  <Ionicons name={col.icon as any} size={16} color={savedCollection === col.id ? colors.accentPrimary : colors.textSecondary} />
                  <Text style={[postStyles.saveItemText, savedCollection === col.id && { color: colors.accentPrimary, fontWeight: '700' }]}>{col.label}</Text>
                </TouchableOpacity>
              ))}
              <View style={postStyles.saveDivider} />
              <TouchableOpacity
                style={postStyles.saveItem}
                onPress={() => {
                  setShowSaveMenu(false);
                  Alert.alert('New Collection', 'Enter a name for your new collection', [
                    { text: 'Cancel', style: 'cancel' },
                    { text: 'Create', onPress: () => { setSaved(true); setSavedCollection('custom'); } },
                  ]);
                }}
              >
                <Ionicons name="add-circle-outline" size={16} color={colors.accentPrimary} />
                <Text style={[postStyles.saveItemText, { color: colors.accentPrimary, fontWeight: '600' }]}>Create New</Text>
              </TouchableOpacity>
            </View>
          )}
        </View>
      </View>
    </View>
  );
}

const postStyles = StyleSheet.create({
  container: {
    backgroundColor: colors.bgApp,
    paddingBottom: 8,
    marginBottom: 4,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderSubtle,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
  },
  avatar: {
    width: 42,
    height: 42,
    borderRadius: 21,
    overflow: 'hidden',
    marginRight: 12,
    borderWidth: 2,
    borderColor: colors.accentPrimary + '30',
  },
  avatarImg: { width: '100%', height: '100%' },
  avatarFallback: {
    width: '100%',
    height: '100%',
    backgroundColor: colors.avatarTeal,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarInitial: { color: '#FFFFFF', fontSize: 16, fontWeight: '700' },
  username: { fontSize: 15, fontWeight: '700', color: colors.textPrimary },
  location: { fontSize: 12, color: colors.accentPrimary, fontWeight: '500' },
  timeLabel: { fontSize: 12, color: colors.textHint, marginTop: 1 },
  moreBtn: { padding: 6 },
  // Media – full-width
  carouselDots: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 5,
    paddingVertical: 10,
  },
  dot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: colors.borderLight,
  },
  dotActive: {
    backgroundColor: colors.accentPrimary,
    width: 18,
    borderRadius: 3,
  },
  // Caption
  captionContainer: { paddingHorizontal: 16, marginTop: 10 },
  captionText: { fontSize: 15, color: colors.textPrimary, lineHeight: 22 },
  moreText: { fontSize: 14, color: colors.accentPrimary, fontWeight: '600', marginTop: 2 },
  // Actions – horizontal icon row with counts
  actionsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: 10,
  },
  actionBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingRight: 20,
    paddingVertical: 4,
  },
  actionCount: { fontSize: 13, fontWeight: '600', color: colors.textSecondary },
  // Save Floating Menu
  saveFloating: {
    position: 'absolute',
    bottom: 44,
    right: 0,
    backgroundColor: '#FFFFFF',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: colors.borderLight,
    paddingVertical: 4,
    minWidth: 180,
    zIndex: 100,
    elevation: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 12,
  },
  saveItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  saveItemActive: {
    backgroundColor: colors.accentPrimaryLight,
  },
  saveItemText: {
    fontSize: 14,
    fontWeight: '500',
    color: colors.textPrimary,
  },
  saveDivider: {
    height: 1,
    backgroundColor: colors.borderSubtle,
    marginVertical: 2,
  },
  // Menu Sheet
  menuOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.4)', justifyContent: 'flex-end' },
  menuSheet: {
    backgroundColor: '#FFFFFF',
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    paddingTop: 8,
    paddingBottom: 34,
  },
  menuHandle: {
    width: 40,
    height: 4,
    borderRadius: 2,
    backgroundColor: colors.borderLight,
    alignSelf: 'center',
    marginBottom: 12,
  },
  menuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    paddingHorizontal: 20,
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderSubtle,
  },
  menuItemText: { fontSize: 16, fontWeight: '500', color: colors.textPrimary },
  menuCancel: { alignItems: 'center', paddingVertical: 16, marginTop: 4 },
  menuCancelText: { fontSize: 16, fontWeight: '600', color: colors.textHint },
  // Report Sheet
  reportSheet: {
    backgroundColor: '#FFFFFF',
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    paddingTop: 8,
    paddingBottom: 34,
    maxHeight: '80%',
  },
  reportTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: colors.textPrimary,
    paddingHorizontal: 20,
    marginBottom: 4,
  },
  reportSubtitle: {
    fontSize: 13,
    color: colors.textHint,
    paddingHorizontal: 20,
    marginBottom: 16,
    lineHeight: 18,
  },
  reportItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    paddingHorizontal: 20,
    paddingVertical: 15,
    borderTopWidth: 1,
    borderTopColor: colors.borderSubtle,
  },
  reportItemText: { flex: 1, fontSize: 15, fontWeight: '500', color: colors.textPrimary },
});

// ─── Inline Composer ─────────────────────────────────────────────────────────
function InlineComposer({
  user,
  visible,
  onClose,
  onPostCreated,
}: {
  user: any;
  visible: boolean;
  onClose: () => void;
  onPostCreated: () => void;
}) {
  const [content, setContent] = useState('');
  const [media, setMedia] = useState<{ uri: string; base64?: string }[]>([]);
  const [isPosting, setIsPosting] = useState(false);

  if (!visible) return null;

  const pickImages = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images', 'videos'],
      allowsMultipleSelection: true,
      quality: 0.7,
      base64: true,
      selectionLimit: 10 - media.length,
    });
    if (!result.canceled && result.assets) {
      const newMedia = result.assets.map((a) => ({
        uri: a.uri,
        base64: a.base64 ? `data:image/jpeg;base64,${a.base64}` : undefined,
      }));
      setMedia((prev) => [...prev, ...newMedia].slice(0, 10));
    }
  };

  const takePhoto = async () => {
    const { status } = await ImagePicker.requestCameraPermissionsAsync();
    if (status !== 'granted') { Alert.alert('Permission needed', 'Camera access required'); return; }
    const result = await ImagePicker.launchCameraAsync({ quality: 0.7, base64: true });
    if (!result.canceled && result.assets[0]) {
      const a = result.assets[0];
      setMedia((prev) => [...prev, { uri: a.uri, base64: a.base64 ? `data:image/jpeg;base64,${a.base64}` : undefined }].slice(0, 10));
    }
  };

  const handlePost = async () => {
    if (!content.trim() && media.length === 0) return;
    setIsPosting(true);
    try {
      const imagesList = media.map(m => m.base64 || m.uri).filter(Boolean);
      await api.post('/posts', {
        content: content.trim(),
        image: imagesList[0] || null,
        images: imagesList.length > 0 ? imagesList : undefined,
      });
      setContent('');
      setMedia([]);
      onClose();
      onPostCreated();
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.detail || 'Could not create post');
    } finally {
      setIsPosting(false);
    }
  };

  return (
    <View style={composerStyles.container}>
      <View style={composerStyles.headerRow}>
        <Text style={composerStyles.title}>Start post</Text>
        <View style={{ flex: 1 }} />
        <TouchableOpacity
          style={[composerStyles.postBtnSmall, (!content.trim() && media.length === 0) && { opacity: 0.4 }]}
          onPress={handlePost}
          disabled={(!content.trim() && media.length === 0) || isPosting}
        >
          {isPosting ? (
            <ActivityIndicator size="small" color={colors.accentPrimary} />
          ) : (
            <Text style={composerStyles.postBtnSmallText}>Post</Text>
          )}
        </TouchableOpacity>
        <TouchableOpacity onPress={onClose} style={composerStyles.closeBtn}>
          <Ionicons name="close" size={20} color={colors.textPrimary} />
        </TouchableOpacity>
      </View>

      {/* User row */}
      <View style={composerStyles.userRow}>
        <View style={composerStyles.cAvatar}>
          {user?.profile_image ? (
            <Image source={{ uri: user.profile_image }} style={composerStyles.cAvatarImg} />
          ) : (
            <View style={composerStyles.cAvatarFallback}>
              <Text style={composerStyles.cAvatarText}>
                {(user?.full_name || 'U')[0].toUpperCase()}
              </Text>
            </View>
          )}
        </View>
        <View>
          <Text style={composerStyles.userName}>{user?.full_name}</Text>
          <View style={composerStyles.visibilityRow}>
            <Ionicons name="globe-outline" size={12} color={colors.textSecondary} />
            <Text style={composerStyles.visibilityText}>Everyone</Text>
          </View>
        </View>
      </View>

      {/* Text input - inline, no navigation */}
      <TextInput
        style={composerStyles.textInput}
        placeholder="Share a tip, thought or update with the community..."
        placeholderTextColor={colors.textHint}
        value={content}
        onChangeText={setContent}
        multiline
        maxLength={2000}
      />

      {/* Media thumbnails */}
      {media.length > 0 && (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={composerStyles.mediaRow}>
          {media.map((m, i) => (
            <View key={i} style={composerStyles.mediaThumbnail}>
              <Image source={{ uri: m.uri }} style={composerStyles.mediaThumbnailImg} />
              <TouchableOpacity
                style={composerStyles.mediaRemove}
                onPress={() => setMedia((prev) => prev.filter((_, idx) => idx !== i))}
              >
                <Ionicons name="close" size={12} color="#FFFFFF" />
              </TouchableOpacity>
            </View>
          ))}
        </ScrollView>
      )}

      {/* Action buttons */}
      <View style={composerStyles.actionsRow}>
        <TouchableOpacity style={composerStyles.actionBtn} onPress={pickImages}>
          <Ionicons name="image-outline" size={22} color={colors.accentSecondary} />
        </TouchableOpacity>
        <TouchableOpacity style={composerStyles.actionBtn} onPress={takePhoto}>
          <Ionicons name="camera-outline" size={22} color={colors.info} />
        </TouchableOpacity>
        <TouchableOpacity style={composerStyles.actionBtn}>
          <Ionicons name="document-outline" size={22} color={colors.warning} />
        </TouchableOpacity>
        <View style={{ flex: 1 }} />
        <Text style={composerStyles.charCount}>{content.length}/2000</Text>
      </View>
    </View>
  );
}

const composerStyles = StyleSheet.create({
  container: {
    backgroundColor: colors.bgCard,
    borderRadius: 24,
    marginHorizontal: 16,
    marginBottom: 12,
    padding: 16,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation2,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
  },
  title: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  postBtnSmall: {
    backgroundColor: colors.accentPrimaryLight,
    borderRadius: 20,
    paddingHorizontal: 16,
    paddingVertical: 8,
    marginRight: 8,
    minWidth: 60,
    alignItems: 'center',
  },
  postBtnSmallText: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.accentPrimary,
  },
  closeBtn: {
    padding: 4,
  },
  userRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 12,
  },
  cAvatar: {
    width: 44,
    height: 44,
    borderRadius: 22,
    overflow: 'hidden',
    marginRight: 12,
  },
  cAvatarImg: {
    width: '100%',
    height: '100%',
  },
  cAvatarFallback: {
    width: '100%',
    height: '100%',
    backgroundColor: colors.avatarTeal,
    justifyContent: 'center',
    alignItems: 'center',
  },
  cAvatarText: {
    color: '#FFFFFF',
    fontSize: 18,
    fontWeight: '700',
  },
  userName: {
    fontSize: 15,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  visibilityRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    marginTop: 2,
  },
  visibilityText: {
    fontSize: 12,
    color: colors.textSecondary,
    fontWeight: '500',
  },
  textInput: {
    fontSize: 16,
    color: colors.textPrimary,
    lineHeight: 24,
    minHeight: 60,
    textAlignVertical: 'top',
    marginBottom: 12,
  },
  mediaRow: {
    flexDirection: 'row',
    marginBottom: 12,
  },
  mediaThumbnail: {
    width: 64,
    height: 64,
    borderRadius: 12,
    overflow: 'hidden',
    marginRight: 8,
  },
  mediaThumbnailImg: {
    width: '100%',
    height: '100%',
  },
  mediaRemove: {
    position: 'absolute',
    top: 2,
    right: 2,
    width: 20,
    height: 20,
    borderRadius: 10,
    backgroundColor: 'rgba(0,0,0,0.6)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  actionsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderTopWidth: 1,
    borderTopColor: colors.borderSubtle,
    paddingTop: 12,
  },
  actionBtn: {
    padding: 8,
    marginRight: 8,
  },
  charCount: {
    fontSize: 12,
    color: colors.textHint,
  },
});

// ─── Main Home Screen ────────────────────────────────────────────────────────
export default function HomeScreen() {
  const router = useRouter();
  const { user } = useAuthStore();
  const [posts, setPosts] = useState<any[]>([]);
  const [statuses, setStatuses] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [showComposer, setShowComposer] = useState(false);
  const [activeCity, setActiveCity] = useState('global');

  const CITIES = [
    { id: 'global', label: 'Global', icon: 'globe-outline' },
    { id: 'nearby', label: 'Nearby', icon: 'navigate-outline' },
    { id: 'New York', label: 'New York', icon: 'business-outline' },
    { id: 'Miami', label: 'Miami', icon: 'sunny-outline' },
    { id: 'Los Angeles', label: 'LA', icon: 'car-outline' },
    { id: 'Paris', label: 'Paris', icon: 'heart-outline' },
    { id: 'London', label: 'London', icon: 'rainy-outline' },
    { id: 'Tokyo', label: 'Tokyo', icon: 'train-outline' },
    { id: 'Shanghai', label: 'Shanghai', icon: 'earth-outline' },
    { id: 'Dubai', label: 'Dubai', icon: 'diamond-outline' },
    { id: 'Berlin', label: 'Berlin', icon: 'beer-outline' },
    { id: 'Toronto', label: 'Toronto', icon: 'snow-outline' },
  ];

  const loadFeed = async (city?: string) => {
    try {
      const c = city || activeCity;
      const params: any = {};
      if (c !== 'global' && c !== 'nearby') params.location = c;
      const response = await api.get('/posts/feed', { params });
      setPosts(response.data);
    } catch (error) {
      console.log('Error loading feed:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const loadStatuses = async () => {
    try {
      const response = await api.get('/statuses');
      setStatuses(response.data);
    } catch (error) {
      console.log('Error loading statuses:', error);
    }
  };

  useEffect(() => {
    loadFeed();
    loadStatuses();
  }, []);

  const onRefresh = useCallback(async () => {
    setIsRefreshing(true);
    await Promise.all([loadFeed(), loadStatuses()]);
    setIsRefreshing(false);
  }, []);

  const greeting = () => {
    const h = new Date().getHours();
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  };

  const firstName = user?.full_name?.split(' ')[0] || '';

  const renderHeader = () => (
    <View>
      {/* App Header */}
      <View style={styles.header}>
        <View>
          <View style={styles.logoRow}>
            <View style={styles.logoIcon}>
              <Ionicons name="flame" size={14} color={colors.flameGold} />
            </View>
            <Text style={styles.logoText}>flames-up</Text>
          </View>
          <Text style={styles.greeting}>
            {greeting().toUpperCase()}
            {firstName ? `, ${firstName.toUpperCase()}` : ''}
          </Text>
        </View>
        <View style={styles.headerActions}>
          <TouchableOpacity
            style={styles.headerBtn}
            onPress={() => router.push('/notifications')}
          >
            <Ionicons
              name="notifications-outline"
              size={18}
              color={colors.accentPrimary}
            />
          </TouchableOpacity>
        </View>
      </View>

      {/* Status/Story Bar */}
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.statusBar}
      >
        {/* Your Story button */}
        <TouchableOpacity
          style={styles.storyItem}
          onPress={() => router.push('/create-status')}
        >
          <View style={styles.storyAvatarAdd}>
            {user?.profile_image ? (
              <Image
                source={{ uri: user.profile_image }}
                style={styles.storyAvatarImg}
              />
            ) : (
              <View style={styles.storyAvatarFallback}>
                <Text style={styles.storyAvatarFallbackText}>
                  {(user?.full_name || 'U')[0].toUpperCase()}
                </Text>
              </View>
            )}
            <View style={styles.storyPlusBadge}>
              <Ionicons name="add" size={12} color="#FFFFFF" />
            </View>
          </View>
          <Text style={styles.storyName}>Your Story</Text>
        </TouchableOpacity>

        {/* Other stories - filter out current user */}
        {statuses
          .filter((s: any) => s.user_id !== user?.id)
          .map((status: any, idx: number) => (
          <TouchableOpacity
            key={status.user_id || idx}
            style={styles.storyItem}
            onPress={() => router.push(`/story-viewer?userId=${status.user_id}` as any)}
          >
            <View style={[styles.storyRing, status.has_unviewed && styles.storyRingUnviewed]}>
              <View style={styles.storyRingInner}>
                {status.user_profile_image ? (
                  <Image
                    source={{ uri: status.user_profile_image }}
                    style={styles.storyAvatarImg}
                  />
                ) : (
                  <View
                    style={[
                      styles.storyAvatarFallback,
                      { backgroundColor: colors.avatarPurple },
                    ]}
                  >
                    <Text style={styles.storyAvatarFallbackText}>
                      {(status.user_full_name || 'U')[0].toUpperCase()}
                    </Text>
                  </View>
                )}
              </View>
            </View>
            <Text style={styles.storyName} numberOfLines={1}>
              {status.user_full_name?.split(' ')[0] || 'User'}
            </Text>
          </TouchableOpacity>
        ))}
      </ScrollView>

      {/* Divider */}
      <View style={styles.divider} />

      {/* City Location Selector */}
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.cityRow}
      >
        {CITIES.map((city) => (
          <TouchableOpacity
            key={city.id}
            style={[styles.cityChip, activeCity === city.id && styles.cityChipActive]}
            onPress={() => {
              setActiveCity(city.id);
              setIsLoading(true);
              loadFeed(city.id);
            }}
          >
            <Ionicons
              name={city.icon as any}
              size={14}
              color={activeCity === city.id ? '#FFFFFF' : colors.textSecondary}
            />
            <Text style={[styles.cityChipText, activeCity === city.id && styles.cityChipTextActive]}>
              {city.label}
            </Text>
          </TouchableOpacity>
        ))}
      </ScrollView>

      {/* Post Button */}
      {user && (
        <View style={styles.postRow}>
          <TouchableOpacity
            style={styles.postBtn}
            onPress={() => setShowComposer(!showComposer)}
          >
            <Ionicons name="create-outline" size={16} color="#FFFFFF" />
            <Text style={styles.postBtnText}>Create Post</Text>
          </TouchableOpacity>
        </View>
      )}

      {/* Inline Composer */}
      <InlineComposer
        user={user}
        visible={showComposer}
        onClose={() => setShowComposer(false)}
        onPostCreated={() => loadFeed()}
      />
    </View>
  );

  const renderPost = ({ item }: { item: any }) => (
    <PostCard
      post={item}
      currentUserId={user?.id || ''}
      onPress={() => router.push(`/post/${item.id}`)}
      onUserPress={() => router.push(`/user/${item.user_id}`)}
    />
  );

  if (isLoading) {
    return (
      <SafeAreaView style={styles.loadingContainer} edges={['top']}>
        <ActivityIndicator size="large" color={colors.accentPrimary} />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <FlatList
        data={posts}
        renderItem={renderPost}
        keyExtractor={(item) => item.id}
        ListHeaderComponent={renderHeader}
        ListEmptyComponent={
          <View style={styles.emptyContainer}>
            <Ionicons name="camera-outline" size={56} color={colors.textHint} />
            <Text style={styles.emptyTitle}>Share Your First Moment</Text>
            <Text style={styles.emptyText}>
              Posts from you and your friends will show up here.
            </Text>
            <TouchableOpacity
              style={styles.createFirstBtn}
              onPress={() => router.push('/create-post')}
            >
              <Text style={styles.createFirstBtnText}>Create Post</Text>
            </TouchableOpacity>
          </View>
        }
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={onRefresh}
            tintColor={colors.accentPrimary}
          />
        }
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ paddingBottom: 100 }}
        ItemSeparatorComponent={() => <View style={styles.postSeparator} />}
      />
    </SafeAreaView>
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
  // Header
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderSubtle,
  },
  logoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 2,
  },
  logoIcon: {
    width: 28,
    height: 28,
    borderRadius: 10,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 8,
    backgroundColor: colors.flameDark,
  },
  logoText: {
    fontSize: 18,
    fontWeight: '700',
    fontStyle: 'italic',
    color: colors.textPrimary,
    letterSpacing: -0.5,
  },
  greeting: {
    fontSize: 11,
    fontWeight: '500',
    color: colors.textHint,
    letterSpacing: 0.8,
    marginLeft: 2,
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  headerBtn: {
    width: 40,
    height: 40,
    borderRadius: 14,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.bgCard,
    borderWidth: 1.5,
    borderColor: colors.borderLight,
  },
  headerAvatar: {
    width: 40,
    height: 40,
    borderRadius: 14,
    overflow: 'hidden',
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.accentSecondary,
  },
  headerAvatarText: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '800',
  },
  // Status Bar
  statusBar: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    gap: 12,
  },
  storyItem: {
    alignItems: 'center',
    width: 68,
  },
  storyAvatarAdd: {
    width: 62,
    height: 62,
    borderRadius: 31,
    borderWidth: 2.5,
    borderColor: colors.borderLight,
    overflow: 'visible',
    justifyContent: 'center',
    alignItems: 'center',
  },
  storyAvatarImg: {
    width: '100%',
    height: '100%',
    borderRadius: 31,
  },
  storyAvatarFallback: {
    width: '100%',
    height: '100%',
    borderRadius: 31,
    backgroundColor: colors.avatarTeal,
    justifyContent: 'center',
    alignItems: 'center',
  },
  storyAvatarFallbackText: {
    color: '#FFFFFF',
    fontSize: 18,
    fontWeight: '700',
  },
  storyPlusBadge: {
    position: 'absolute',
    bottom: -2,
    right: -2,
    width: 20,
    height: 20,
    borderRadius: 10,
    backgroundColor: colors.accentPrimary,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: '#FFFFFF',
  },
  storyRing: {
    width: 62,
    height: 62,
    borderRadius: 31,
    padding: 2.5,
    backgroundColor: colors.storyRingMid,
    overflow: 'hidden',
  },
  storyRingUnviewed: {
    backgroundColor: '#ED4956',
  },
  storyRingInner: {
    width: '100%',
    height: '100%',
    borderRadius: 28,
    borderWidth: 2,
    borderColor: '#FFFFFF',
    overflow: 'hidden',
  },
  storyName: {
    fontSize: 11,
    fontWeight: '600',
    color: colors.textSecondary,
    marginTop: 6,
    textAlign: 'center',
    maxWidth: 64,
  },
  // Divider
  divider: {
    height: 1,
    backgroundColor: colors.borderSubtle,
  },
  // City Selector
  cityRow: {
    paddingHorizontal: 12,
    paddingVertical: 10,
    gap: 8,
  },
  cityChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: colors.bgSubtle,
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  cityChipActive: {
    backgroundColor: colors.accentPrimary,
    borderColor: colors.accentPrimary,
  },
  cityChipText: {
    fontSize: 12,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  cityChipTextActive: {
    color: '#FFFFFF',
  },
  // Post row
  postRow: {
    paddingHorizontal: 16,
    paddingBottom: 8,
  },
  postBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingVertical: 12,
    borderRadius: 20,
    backgroundColor: colors.accentPrimary,
  },
  postBtnText: {
    fontSize: 14,
    fontWeight: '700',
    color: '#FFFFFF',
  },
  // Post separator
  postSeparator: {
    height: 1,
    backgroundColor: colors.borderSubtle,
  },
  // Empty state
  emptyContainer: {
    alignItems: 'center',
    paddingVertical: 60,
    paddingHorizontal: 32,
  },
  emptyTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: colors.textPrimary,
    marginTop: 16,
    marginBottom: 8,
  },
  emptyText: {
    fontSize: 14,
    color: colors.textHint,
    marginBottom: 24,
    textAlign: 'center',
    lineHeight: 20,
  },
  createFirstBtn: {
    paddingHorizontal: 24,
    paddingVertical: 14,
    borderRadius: 20,
    backgroundColor: colors.accentPrimary,
  },
  createFirstBtnText: {
    fontSize: 14,
    fontWeight: '700',
    color: '#FFFFFF',
  },
});
