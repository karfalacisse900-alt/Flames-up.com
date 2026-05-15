import React, { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Image,
  Keyboard,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  Share,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  useWindowDimensions,
  View,
} from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import * as ImagePicker from 'expo-image-picker';
import AsyncStorage from '@react-native-async-storage/async-storage';

import api from '../../src/api/client';
import ReportReasonSheet, { type ReportReason } from '../../src/components/ReportReasonSheet';
import { useAuthStore } from '../../src/store/authStore';
import { cacheDiscoverNotes, cacheDiscoverStories, getCachedDiscover } from '../../src/store/discoverCache';
import { cacheNoteForDetail, cacheNotesForDetail } from '../../src/store/noteDetailCache';
import { useSocialState } from '../../src/store/socialState';
import { colors, hitSlop, layout, shadows, spacing } from '../../src/utils/theme';
import { useI18n } from '../../src/utils/i18n';
import { requireVerifiedPhone } from '../../src/utils/phoneVerification';
import { uploadImageWithBackup } from '../../src/utils/mediaUpload';
import { NOTE_IMAGE_PICKER_QUALITY } from '../../src/utils/mediaQuality';
import { optimizeImageUrl, prefetchImageUrls } from '../../src/utils/optimizedMedia';

type StoryGroup = {
  user_id: string;
  user_username?: string;
  user_full_name?: string;
  user_profile_image?: string;
  has_unviewed?: boolean;
  statuses?: any[];
};

type UserSearchResult = {
  id: string;
  username?: string;
  full_name?: string;
  profile_image?: string;
  bio?: string;
};

type NoteCard = {
  id: string;
  body?: string;
  note_type?: string;
  mood?: string;
  color?: string;
  media_url?: string;
  media_type?: string;
  reactions_count?: number;
  comments_count?: number;
  saves_count?: number;
  shares_count?: number;
  reacted?: boolean;
  saved?: boolean;
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

type NotePhotoDraft = {
  uri: string;
  base64?: string;
  fileName?: string;
  isRemote?: boolean;
};

type GifResult = {
  id: string;
  title: string;
  url: string;
  preview: string;
};

type NoteComment = {
  id: string;
  body: string;
  created_at?: string;
  user?: {
    id?: string;
    username?: string;
    full_name?: string;
    profile_image?: string;
  };
};

const NOTE_DRAFT_PREFIX = 'flames:note-draft:v1:';
const GIPHY_API_KEY = process.env.EXPO_PUBLIC_GIPHY_API_KEY || 'a2puMkHvEAeLT47RL4JZhEdWwUXjXGhR';

function noteDraftKey(userId?: string) {
  return `${NOTE_DRAFT_PREFIX}${userId || 'guest'}`;
}

function displayName(group: StoryGroup) {
  return group.user_full_name || group.user_username || 'Story';
}

function noteAuthor(note: NoteCard) {
  return note.user?.full_name || note.user?.username || 'MIRA';
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

export default function DiscoverScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{ compose?: string }>();
  const insets = useSafeAreaInsets();
  const { width, height } = useWindowDimensions();
  const { user } = useAuthStore();
  const cachedDiscover = getCachedDiscover();
  const followedUserFlags = useSocialState((state) => state.followedUserIds);
  const setUserFollowing = useSocialState((state) => state.setUserFollowing);
  const { t } = useI18n();
  const [loading, setLoading] = useState(cachedDiscover.stories.length === 0);
  const [storyGroups, setStoryGroups] = useState<StoryGroup[]>(() => cachedDiscover.stories);
  const [notes, setNotes] = useState<NoteCard[]>(() => cachedDiscover.notes);
  const [notesLoading, setNotesLoading] = useState(cachedDiscover.notes.length === 0);
  const [postChooserVisible, setPostChooserVisible] = useState(false);
  const [noteComposerVisible, setNoteComposerVisible] = useState(false);
  const [noteDraft, setNoteDraft] = useState('');
  const [notePhoto, setNotePhoto] = useState<NotePhotoDraft | null>(null);
  const [notePosting, setNotePosting] = useState(false);
  const [noteError, setNoteError] = useState('');
  const [draftSavedAt, setDraftSavedAt] = useState<number | null>(null);
  const [gifPickerVisible, setGifPickerVisible] = useState(false);
  const [gifQuery, setGifQuery] = useState('');
  const [gifResults, setGifResults] = useState<GifResult[]>([]);
  const [gifLoading, setGifLoading] = useState(false);
  const [commentSheetVisible, setCommentSheetVisible] = useState(false);
  const [selectedNote, setSelectedNote] = useState<NoteCard | null>(null);
  const [noteComments, setNoteComments] = useState<NoteComment[]>([]);
  const [noteCommentDraft, setNoteCommentDraft] = useState('');
  const [noteCommentLoading, setNoteCommentLoading] = useState(false);
  const [noteCommentPosting, setNoteCommentPosting] = useState(false);
  const [reportTargetNote, setReportTargetNote] = useState<NoteCard | null>(null);
  const [reportSubmitting, setReportSubmitting] = useState(false);
  const [searchVisible, setSearchVisible] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<UserSearchResult[]>([]);
  const [searchLoading, setSearchLoading] = useState(false);
  const isCompactScreen = height < 760;
  const noteCardWidth = Math.min(Math.max(width * (isCompactScreen ? 0.74 : 0.8), 250), isCompactScreen ? 292 : 320);
  const noteCardHeight = Math.round(noteCardWidth * 1.25);

  const loadStories = useCallback(async () => {
    setLoading(true);
    try {
      const response = await api.get('/statuses').catch(() => ({ data: [] }));
      const groups = Array.isArray(response.data) ? response.data : [];
      const visibleGroups = groups.filter((group: StoryGroup) => (
        group?.user_id
        && group.user_id !== user?.id
        && Array.isArray(group.statuses)
        && group.statuses.length > 0
      ));
      cacheDiscoverStories(visibleGroups);
      setStoryGroups(visibleGroups);
    } finally {
      setLoading(false);
    }
  }, [user?.id]);

  const loadNotes = useCallback(async () => {
    setNotesLoading(true);
    try {
      const response = await api.get('/notes', { params: { limit: 14 } }).catch(() => ({ data: [] }));
      const loadedNotes = Array.isArray(response.data) ? response.data.filter((note: NoteCard) => note?.id) : [];
      cacheNotesForDetail(loadedNotes);
      cacheDiscoverNotes(loadedNotes);
      setNotes(loadedNotes);
    } finally {
      setNotesLoading(false);
    }
  }, []);

  const hydrateSavedNoteDraft = useCallback(async () => {
    if (noteDraft.trim() || notePhoto) return;
    try {
      const raw = await AsyncStorage.getItem(noteDraftKey(user?.id));
      if (!raw) return;
      const saved = JSON.parse(raw);
      if (typeof saved.body === 'string') setNoteDraft(saved.body.slice(0, 420));
      if (typeof saved.saved_at === 'number') setDraftSavedAt(saved.saved_at);
      if (saved.photo?.uri) {
        setNotePhoto({
          uri: String(saved.photo.uri),
          base64: saved.photo.base64 ? String(saved.photo.base64) : undefined,
          fileName: saved.photo.fileName ? String(saved.photo.fileName) : undefined,
          isRemote: !!saved.photo.isRemote,
        });
      }
    } catch {
      // Ignore broken local drafts; posting should never be blocked by local storage.
    }
  }, [noteDraft, notePhoto, user?.id]);

  const saveNoteDraft = useCallback(async () => {
    if (!noteDraft.trim() && !notePhoto) return;
    try {
      await AsyncStorage.setItem(noteDraftKey(user?.id), JSON.stringify({
        body: noteDraft.slice(0, 420),
        photo: notePhoto,
        saved_at: Date.now(),
      }));
      setDraftSavedAt(Date.now());
    } catch {
      setNoteError('Could not save draft on this device.');
    }
  }, [noteDraft, notePhoto, user?.id]);

  const loadGifs = useCallback(async (queryValue = gifQuery.trim()) => {
    setGifLoading(true);
    try {
      const query = queryValue.trim();
      const endpoint = query
        ? `https://api.giphy.com/v1/gifs/search?api_key=${encodeURIComponent(GIPHY_API_KEY)}&q=${encodeURIComponent(query)}&limit=24&rating=pg-13`
        : `https://api.giphy.com/v1/gifs/trending?api_key=${encodeURIComponent(GIPHY_API_KEY)}&limit=24&rating=pg-13`;
      const response = await fetch(endpoint);
      const payload = await response.json();
      const items = Array.isArray(payload?.data) ? payload.data : [];
      setGifResults(items.map((item: any) => {
        const image = item?.images || {};
        const url = image.downsized_medium?.url || image.fixed_height?.url || image.original?.url || '';
        const preview = image.fixed_width_small?.url || image.downsized_still?.url || url;
        return {
          id: String(item.id || url),
          title: String(item.title || 'GIF'),
          url,
          preview,
        };
      }).filter((item: GifResult) => item.url && item.preview));
    } catch {
      setGifResults([]);
    } finally {
      setGifLoading(false);
    }
  }, [gifQuery]);

  const patchNote = useCallback((noteId: string, updater: (note: NoteCard) => NoteCard) => {
    setNotes((current) => current.map((note) => (note.id === noteId ? updater(note) : note)));
  }, []);

  const toggleNoteReaction = useCallback(async (note: NoteCard) => {
    if (!user?.id) {
      router.push('/login' as any);
      return;
    }
    const wasReacted = !!note.reacted;
    patchNote(note.id, (current) => ({
      ...current,
      reacted: !wasReacted,
      reactions_count: Math.max(0, Number(current.reactions_count || 0) + (wasReacted ? -1 : 1)),
    }));
    try {
      await api.post(`/notes/${note.id}/interactions`, { kind: 'reaction', value: 'heart' });
    } catch {
      patchNote(note.id, (current) => ({
        ...current,
        reacted: wasReacted,
        reactions_count: Math.max(0, Number(current.reactions_count || 0) + (wasReacted ? 1 : -1)),
      }));
    }
  }, [patchNote, router, user?.id]);

  const openNoteComments = useCallback(async (note: NoteCard) => {
    if (!user?.id) {
      router.push('/login' as any);
      return;
    }
    setSelectedNote(note);
    setNoteComments([]);
    setNoteCommentDraft('');
    setCommentSheetVisible(true);
    setNoteCommentLoading(true);
    try {
      const response = await api.get(`/notes/${note.id}/comments`);
      setNoteComments(Array.isArray(response.data) ? response.data : []);
    } catch {
      setNoteComments([]);
    } finally {
      setNoteCommentLoading(false);
    }
  }, [router, user?.id]);

  const submitNoteComment = useCallback(async () => {
    const body = noteCommentDraft.trim();
    if (!selectedNote?.id || body.length < 1 || noteCommentPosting) return;
    setNoteCommentPosting(true);
    try {
      const response = await api.post(`/notes/${selectedNote.id}/comments`, { body });
      const created: NoteComment = {
        id: response.data?.id || `${Date.now()}`,
        body: response.data?.body || body,
        created_at: response.data?.created_at || new Date().toISOString(),
        user: {
          id: user?.id,
          username: user?.username,
          full_name: user?.full_name,
          profile_image: user?.profile_image,
        },
      };
      setNoteComments((current) => [...current, created]);
      setNoteCommentDraft('');
      patchNote(selectedNote.id, (current) => ({
        ...current,
        comments_count: Number(current.comments_count || 0) + 1,
      }));
    } catch {
      Alert.alert('Comment failed', 'Could not post that comment. Please try again.');
    } finally {
      setNoteCommentPosting(false);
    }
  }, [noteCommentDraft, noteCommentPosting, patchNote, selectedNote?.id, user]);

  const shareNote = useCallback(async (note: NoteCard) => {
    if (!user?.id) {
      router.push('/login' as any);
      return;
    }
    try {
      const message = note.body?.trim()
        ? `${noteAuthor(note)} on MIRA: ${note.body.trim()}`
        : `${noteAuthor(note)} shared a note on MIRA.`;
      await Share.share({ message });
      patchNote(note.id, (current) => ({ ...current, shares_count: Number(current.shares_count || 0) + 1 }));
      await api.post(`/notes/${note.id}/interactions`, { kind: 'share' }).catch(() => undefined);
    } catch {
      // Native share sheets throw when dismissed on some platforms; no user-facing error needed.
    }
  }, [patchNote, router, user?.id]);

  const openNoteDetail = useCallback((note: NoteCard) => {
    cacheNoteForDetail(note);
    const warmUrls = [
      note.media_url ? optimizeImageUrl(note.media_url, 'detail') : '',
      note.user?.profile_image ? optimizeImageUrl(note.user.profile_image, 'avatar') : '',
    ].filter(Boolean);
    if (warmUrls.length) void prefetchImageUrls(warmUrls, 4);
    router.push(`/note/${note.id}` as any);
  }, [router]);

  const reportNote = useCallback((note: NoteCard) => {
    if (!user?.id) {
      router.push('/login' as any);
      return;
    }
    setReportTargetNote(note);
  }, [router, user?.id]);

  const submitNoteReport = useCallback(async (reason: ReportReason) => {
    const note = reportTargetNote;
    if (!note || reportSubmitting) return;
    setReportSubmitting(true);
    try {
      await api.post(`/notes/${note.id}/report`, {
        reason: reason.id,
        details: reason.details,
      });
      setReportTargetNote(null);
      Alert.alert('Reported', 'Thanks. We sent this note to moderation.');
    } catch (error: any) {
      Alert.alert('Report failed', error?.response?.data?.detail || 'Could not report this note.');
    } finally {
      setReportSubmitting(false);
    }
  }, [reportSubmitting, reportTargetNote]);

  const markNoteNotInterested = useCallback((note: NoteCard) => {
    setNotes((current) => current.filter((item) => item.id !== note.id));
    if (selectedNote?.id === note.id) {
      setCommentSheetVisible(false);
      setSelectedNote(null);
    }
  }, [selectedNote?.id]);

  const openNoteMenu = useCallback((note: NoteCard) => {
    Alert.alert('Note options', undefined, [
      { text: 'Not interested', onPress: () => markNoteNotInterested(note) },
      { text: 'Report', style: 'destructive', onPress: () => reportNote(note) },
      { text: 'Cancel', style: 'cancel' },
    ]);
  }, [markNoteNotInterested, reportNote]);

  const toggleNoteAuthorFollow = useCallback(async (note: NoteCard, event?: any) => {
    event?.stopPropagation?.();
    const targetId = String(note.user?.id || '');
    if (!targetId || targetId === user?.id) return;
    if (!user?.id) {
      router.push('/login' as any);
      return;
    }
    const seedFollowing = !!(note.user?.is_following ?? note.user?.following ?? note.user?.followed);
    const wasFollowing = followedUserFlags[targetId] ?? seedFollowing;
    const nextFollowing = !wasFollowing;
    setUserFollowing(targetId, nextFollowing);
    try {
      const response = await api.post(`/users/${targetId}/follow`, { following: nextFollowing });
      if (typeof response.data?.following === 'boolean') {
        setUserFollowing(targetId, !!response.data.following);
      }
    } catch (error: any) {
      setUserFollowing(targetId, wasFollowing);
      Alert.alert('Follow failed', error?.response?.data?.detail || 'Could not follow this user.');
    }
  }, [followedUserFlags, router, setUserFollowing, user?.id]);

  useEffect(() => {
    void loadStories();
  }, [loadStories]);

  useEffect(() => {
    void loadNotes();
  }, [loadNotes]);

  useEffect(() => {
    if (params.compose === 'note') {
      setNoteComposerVisible(true);
      router.setParams({ compose: undefined } as any);
    }
  }, [params.compose, router]);

  useEffect(() => {
    if (noteComposerVisible) void hydrateSavedNoteDraft();
  }, [hydrateSavedNoteDraft, noteComposerVisible]);

  useEffect(() => {
    if (!gifPickerVisible) return;
    const timer = setTimeout(() => {
      void loadGifs(gifQuery);
    }, 220);
    return () => clearTimeout(timer);
  }, [gifPickerVisible, gifQuery, loadGifs]);

  useEffect(() => {
    if (!searchVisible) return;
    const query = searchQuery.trim();
    if (query.length < 2) {
      setSearchResults([]);
      setSearchLoading(false);
      return;
    }
    setSearchLoading(true);
    const timer = setTimeout(async () => {
      try {
        const response = await api.get(`/users/search/${encodeURIComponent(query)}`);
        const people = Array.isArray(response.data) ? response.data : [];
        setSearchResults(people.filter((person: UserSearchResult) => person.id && person.id !== user?.id));
      } catch {
        setSearchResults([]);
      } finally {
        setSearchLoading(false);
      }
    }, 240);
    return () => clearTimeout(timer);
  }, [searchQuery, searchVisible, user?.id]);

  const AvatarCircle = ({
    label,
    ring,
    uri,
  }: {
    label: string;
    ring?: boolean;
    uri?: string;
  }) => (
    <View style={[s.avatarRing, ring && s.avatarRingActive]}>
      {uri ? (
        <Image source={{ uri }} style={s.avatarImage} />
      ) : (
        <View style={s.avatarFallback}>
          <Text style={s.avatarInitial}>{label.slice(0, 1).toUpperCase()}</Text>
        </View>
      )}
    </View>
  );

  const submitNote = useCallback(async () => {
    const body = noteDraft.trim();
    if ((body.length < 2 && !notePhoto) || notePosting) return;
    setNotePosting(true);
    setNoteError('');
    try {
      let mediaUrl = '';
      if (notePhoto?.uri && /^https?:\/\//i.test(notePhoto.uri)) {
        mediaUrl = notePhoto.uri;
      } else if (notePhoto?.base64) {
        const dataUri = notePhoto.base64.startsWith('data:')
          ? notePhoto.base64
          : `data:image/jpeg;base64,${notePhoto.base64}`;
        const uploaded = await uploadImageWithBackup(dataUri, notePhoto.fileName || 'note-photo.jpg');
        mediaUrl = uploaded.url;
      }
      const response = await api.post('/notes', {
        body,
        note_type: 'thought',
        mood: 'soft',
        color: '#F4EBDD',
        media_url: mediaUrl,
      });
      if (response.data?.id) setNotes((current) => [response.data, ...current]);
      setNoteDraft('');
      setNotePhoto(null);
      setDraftSavedAt(null);
      await AsyncStorage.removeItem(noteDraftKey(user?.id)).catch(() => undefined);
      setNoteComposerVisible(false);
    } catch (error: any) {
      setNoteError(error?.response?.data?.detail || 'Could not post note. Try again.');
    } finally {
      setNotePosting(false);
    }
  }, [noteDraft, notePhoto, notePosting, user?.id]);

  const pickNotePhoto = useCallback(async () => {
    try {
      const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (status !== 'granted') {
        Alert.alert('Permission needed', 'Please allow access to your photo library.');
        return;
      }
      const result = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ['images'],
        allowsMultipleSelection: false,
        quality: NOTE_IMAGE_PICKER_QUALITY,
        base64: true,
        selectionLimit: 1,
        preferredAssetRepresentationMode: ImagePicker.UIImagePickerPreferredAssetRepresentationMode.Current,
      });
      if (result.canceled || !result.assets?.[0]) return;
      const asset = result.assets[0];
      setNotePhoto({
        uri: asset.uri,
        base64: asset.base64 || undefined,
        fileName: asset.fileName || 'note-photo.jpg',
      });
      setDraftSavedAt(null);
    } catch {
      Alert.alert('Photo failed', 'Please try selecting the photo again.');
    }
  }, []);

  const openNoteComposer = useCallback(() => {
    if (!user?.id) {
      router.push('/login' as any);
      return;
    }
    setNoteError('');
    setNoteComposerVisible(true);
  }, [router, user]);

  const openCreateChooser = useCallback(() => {
    if (!requireVerifiedPhone(user, router, 'create posts')) return;
    setPostChooserVisible(true);
  }, [router, user]);

  const chooseStandardPost = useCallback(() => {
    setPostChooserVisible(false);
    router.push('/create-post' as any);
  }, [router]);

  const chooseNotePost = useCallback(() => {
    setPostChooserVisible(false);
    openNoteComposer();
  }, [openNoteComposer]);

  return (
    <View style={s.root}>
      <View style={[s.storyPanel, { marginTop: insets.top + 8 }]}>
        <View style={s.storyHeader}>
          <Text style={s.sectionTitle}>Stories</Text>
          <TouchableOpacity
            style={s.storySearchButton}
            activeOpacity={0.84}
            accessibilityLabel="Search users"
            hitSlop={hitSlop}
            onPress={() => setSearchVisible(true)}
          >
            <Ionicons name="search" size={19} color={colors.textPrimary} />
          </TouchableOpacity>
        </View>

        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          bounces={false}
          alwaysBounceHorizontal={false}
          overScrollMode="never"
          contentContainerStyle={s.storyRail}
        >
          <TouchableOpacity
            style={s.storyItem}
            activeOpacity={0.86}
            onPress={() => {
              if (!requireVerifiedPhone(user, router, 'share stories')) return;
              router.push('/create-status' as any);
            }}
          >
            <View>
              <AvatarCircle label={user?.full_name || user?.username || 'Y'} uri={user?.profile_image} />
              <View style={s.addBadge}>
                <Ionicons name="add" size={15} color="#FFFFFF" />
              </View>
            </View>
            <Text style={s.storyName} numberOfLines={1}>{t('yourStory')}</Text>
          </TouchableOpacity>

          {storyGroups.map((group) => {
            const name = displayName(group);
            return (
              <TouchableOpacity
                key={group.user_id}
                style={s.storyItem}
                activeOpacity={0.86}
                onPress={() => router.push({ pathname: '/story-viewer', params: { userId: group.user_id } } as any)}
              >
                <AvatarCircle label={name} uri={group.user_profile_image} ring={group.has_unviewed} />
                <Text style={s.storyName} numberOfLines={1}>{name}</Text>
              </TouchableOpacity>
            );
          })}
        </ScrollView>
      </View>

      <View style={s.notesPanel}>
        <View style={s.notesHeader}>
          <View>
            <Text style={s.sectionTitle}>Notes</Text>
          </View>
          <TouchableOpacity
            style={s.notesCreateButton}
            activeOpacity={0.86}
            onPress={chooseNotePost}
            accessibilityLabel="Create note"
          >
            <Ionicons name="add" size={18} color={colors.textInverse} />
          </TouchableOpacity>
        </View>

        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          bounces={false}
          alwaysBounceHorizontal={false}
          overScrollMode="never"
          decelerationRate="fast"
          snapToAlignment="start"
          snapToInterval={noteCardWidth + spacing.gutter}
          contentContainerStyle={s.notesRail}
        >
          <TouchableOpacity
            style={[s.noteLargeCard, s.noteCreateLargeCard, { width: noteCardWidth, height: noteCardHeight }]}
            activeOpacity={0.86}
            onPress={openNoteComposer}
          >
            <View style={s.noteCreateProfile}>
              {user?.profile_image ? (
                <Image source={{ uri: user.profile_image }} style={s.noteLargeAvatar} />
              ) : (
                <View style={s.noteLargeAvatarFallback}>
                  <Text style={s.noteLargeAvatarText}>{String(user?.full_name || user?.username || 'Y').slice(0, 1).toUpperCase()}</Text>
                </View>
              )}
              <View style={s.noteCreateCopy}>
                <Text style={s.noteLargeAuthor} numberOfLines={1}>{user?.full_name || user?.username || 'Your note'}</Text>
                <Text style={s.noteLargeMeta}>Photo or text</Text>
              </View>
            </View>
            <View style={s.noteCreateCenter}>
              <View style={s.noteCreateIcon}>
                <Ionicons name="add" size={26} color={colors.textInverse} />
              </View>
              <Text style={s.noteCreateTitle}>Create a note</Text>
              <Text style={s.noteCreateText}>Add a photo, write text, or both.</Text>
            </View>
          </TouchableOpacity>

          {notesLoading ? (
            [0, 1, 2].map((item) => (
              <View key={`note-loading-${item}`} style={[s.noteSkeleton, { width: noteCardWidth, height: noteCardHeight }]}>
                <View style={s.noteSkeletonLine} />
                <View style={[s.noteSkeletonLine, s.noteSkeletonShort]} />
              </View>
            ))
          ) : notes.length ? (
            notes.map((note) => {
              const author = noteAuthor(note);
              const hasPhoto = !!note.media_url;
              const authorId = String(note.user?.id || '');
              const noteAuthorFollowing = !!(followedUserFlags[authorId] ?? note.user?.is_following ?? note.user?.following ?? note.user?.followed);
              const canFollowAuthor = !!authorId && authorId !== user?.id;
              return (
                <TouchableOpacity
                  key={note.id}
                  style={[s.noteLargeCard, { width: noteCardWidth, height: noteCardHeight }]}
                  activeOpacity={0.88}
                  onPress={() => openNoteDetail(note)}
                >
                  <View style={s.noteThreadHeader}>
                    <View style={s.noteAvatarWrap}>
                      {note.user?.profile_image ? (
                        <Image source={{ uri: note.user.profile_image }} style={s.noteLargeAvatar} />
                      ) : (
                        <View style={s.noteLargeAvatarFallback}>
                          <Text style={s.noteLargeAvatarText}>{author.slice(0, 1).toUpperCase()}</Text>
                        </View>
                      )}
                      {canFollowAuthor ? (
                        <TouchableOpacity
                          style={[s.noteFollowBadge, noteAuthorFollowing && s.noteFollowBadgeOn]}
                          activeOpacity={0.86}
                          onPress={(event) => toggleNoteAuthorFollow(note, event)}
                          accessibilityLabel={noteAuthorFollowing ? 'Unfollow note author' : 'Follow note author'}
                        >
                          <Ionicons name={noteAuthorFollowing ? 'checkmark' : 'add'} size={12} color="#FFFFFF" />
                        </TouchableOpacity>
                      ) : null}
                    </View>
                    <View style={s.noteThreadAuthorCopy}>
                      <View style={s.noteThreadNameRow}>
                        <Text style={s.noteThreadAuthor} numberOfLines={1}>{author}</Text>
                        <View style={s.noteVerifiedBadge}>
                          <Ionicons name="checkmark" size={12} color="#FFFFFF" />
                        </View>
                        <Text style={s.noteThreadTime}>{noteTime(note.created_at)}</Text>
                      </View>
                    </View>
                    <TouchableOpacity
                      style={s.noteMenuButton}
                      activeOpacity={0.8}
                      onPress={(event) => {
                        event.stopPropagation();
                        openNoteMenu(note);
                      }}
                      accessibilityLabel="Open note options"
                    >
                      <Ionicons name="ellipsis-horizontal" size={24} color={colors.textHint} />
                    </TouchableOpacity>
                  </View>

                  <Text style={[s.noteThreadBody, !hasPhoto && s.noteThreadBodyTextOnly]} numberOfLines={hasPhoto ? 2 : 6}>
                    {note.body || 'New note'}
                    {note.body && note.body.length > 98 ? <Text style={s.noteThreadMore}> more</Text> : null}
                  </Text>

                  {hasPhoto ? (
                    <Image
                      source={{ uri: note.media_url }}
                      style={[s.noteThreadImage, { height: Math.round(noteCardWidth * (isCompactScreen ? 0.58 : 0.62)) }]}
                      resizeMode="cover"
                    />
                  ) : null}

                  <View style={s.noteThreadActions}>
                    <TouchableOpacity
                      style={s.noteThreadAction}
                      activeOpacity={0.76}
                      onPress={(event) => {
                        event.stopPropagation();
                        void toggleNoteReaction(note);
                      }}
                      accessibilityLabel="Like note"
                    >
                      <Ionicons
                        name={note.reacted ? 'heart' : 'heart-outline'}
                        size={21}
                        color={note.reacted ? colors.accentPrimary : colors.textSecondary}
                      />
                      <Text style={s.noteThreadActionText}>{Number(note.reactions_count || 0)}</Text>
                    </TouchableOpacity>
                    <TouchableOpacity
                      style={s.noteThreadAction}
                      activeOpacity={0.76}
                      onPress={(event) => {
                        event.stopPropagation();
                        openNoteDetail(note);
                      }}
                      accessibilityLabel="Open note comments"
                    >
                      <Ionicons name="chatbubble-outline" size={20} color={colors.textSecondary} />
                      <Text style={s.noteThreadActionText}>{Number(note.comments_count || 0)}</Text>
                    </TouchableOpacity>
                    <TouchableOpacity
                      style={s.noteThreadAction}
                      activeOpacity={0.76}
                      onPress={(event) => {
                        event.stopPropagation();
                        void shareNote(note);
                      }}
                      accessibilityLabel="Share note"
                    >
                      <Ionicons name="paper-plane-outline" size={20} color={colors.textSecondary} />
                      <Text style={s.noteThreadActionText}>{Number(note.shares_count || 0)}</Text>
                    </TouchableOpacity>
                  </View>
                </TouchableOpacity>
              );
            })
          ) : (
            <View style={[s.noteEmptyCard, { width: noteCardWidth, height: noteCardHeight }]}>
              <Text style={s.noteEmptyTitle}>No notes yet</Text>
              <Text style={s.noteEmptyText}>Be the first to start the thread.</Text>
            </View>
          )}
        </ScrollView>
      </View>

      <View style={s.body}>
        {loading ? (
          <View style={s.loadingCard}>
            <View style={s.loadingAvatar} />
            <View style={s.loadingLines}>
              <View style={s.loadingLine} />
              <View style={[s.loadingLine, s.loadingLineShort]} />
            </View>
          </View>
        ) : storyGroups.length === 0 ? (
          <View style={s.empty}>
            <View style={s.emptyIcon}>
              <Ionicons name="radio-outline" size={34} color={colors.textHint} />
            </View>
            <Text style={s.emptyTitle}>No stories yet</Text>
            <Text style={s.emptyText}>Stories from other users will show here when they post.</Text>
          </View>
        ) : null}
      </View>

      <Modal visible={searchVisible} animationType="slide" onRequestClose={() => setSearchVisible(false)}>
        <View style={[s.searchRoot, { paddingTop: insets.top + 8 }]}>
          <View style={s.searchHeader}>
            <TouchableOpacity
              style={s.searchClose}
              onPress={() => {
                setSearchVisible(false);
                setSearchQuery('');
                setSearchResults([]);
              }}
              activeOpacity={0.84}
            >
              <Ionicons name="chevron-back" size={30} color={colors.textPrimary} />
            </TouchableOpacity>
            <Text style={s.searchTitle}>Search users</Text>
            <View style={s.searchClose} />
          </View>
          <View style={s.searchInputWrap}>
            <Ionicons name="search" size={19} color={colors.textHint} />
            <TextInput
              value={searchQuery}
              onChangeText={setSearchQuery}
              placeholder="Search username or name"
              placeholderTextColor={colors.textHint}
              style={s.searchInput}
              autoCapitalize="none"
              autoCorrect={false}
              autoFocus
            />
          </View>
          {searchLoading ? (
            <View style={s.searchState}>
              <ActivityIndicator color={colors.textPrimary} />
            </View>
          ) : searchQuery.trim().length < 2 ? (
            <View style={s.searchState}>
              <Text style={s.searchStateTitle}>Find people</Text>
              <Text style={s.searchStateText}>Type at least two letters to search users.</Text>
            </View>
          ) : searchResults.length ? (
            <ScrollView style={s.searchList} keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator={false}>
              {searchResults.map((person) => {
                const name = person.full_name || person.username || 'User';
                return (
                  <TouchableOpacity
                    key={person.id}
                    style={s.userRow}
                    activeOpacity={0.86}
                    onPress={() => {
                      setSearchVisible(false);
                      setSearchQuery('');
                      setSearchResults([]);
                      router.push(`/user/${person.id}` as any);
                    }}
                  >
                    {person.profile_image ? (
                      <Image source={{ uri: person.profile_image }} style={s.userAvatar} />
                    ) : (
                      <View style={s.userAvatarFallback}>
                        <Text style={s.userAvatarText}>{name.slice(0, 1).toUpperCase()}</Text>
                      </View>
                    )}
                    <View style={s.userInfo}>
                      <Text style={s.userName} numberOfLines={1}>{name}</Text>
                      <Text style={s.userHandle} numberOfLines={1}>@{person.username || 'flames'}</Text>
                    </View>
                    <Ionicons name="chevron-forward" size={20} color={colors.textHint} />
                  </TouchableOpacity>
                );
              })}
            </ScrollView>
          ) : (
            <View style={s.searchState}>
              <Text style={s.searchStateTitle}>No users found</Text>
              <Text style={s.searchStateText}>Try another name or username.</Text>
            </View>
          )}
        </View>
      </Modal>

      <Modal visible={commentSheetVisible} animationType="slide" onRequestClose={() => setCommentSheetVisible(false)}>
        <View style={[s.commentRoot, { paddingTop: insets.top + 8 }]}>
          <View style={s.commentHeader}>
            <TouchableOpacity
              style={s.commentClose}
              onPress={() => setCommentSheetVisible(false)}
              activeOpacity={0.84}
              accessibilityLabel="Close comments"
            >
              <Ionicons name="chevron-down" size={28} color={colors.textPrimary} />
            </TouchableOpacity>
            <Text style={s.commentTitle}>Comments</Text>
            <View style={s.commentClose} />
          </View>
          <ScrollView
            style={s.commentList}
            contentContainerStyle={s.commentListContent}
            keyboardShouldPersistTaps="handled"
            showsVerticalScrollIndicator={false}
          >
            {noteCommentLoading ? (
              <View style={s.commentState}>
                <ActivityIndicator color={colors.textPrimary} />
              </View>
            ) : noteComments.length ? (
              noteComments.map((comment) => {
                const name = comment.user?.full_name || comment.user?.username || 'User';
                return (
                  <View key={comment.id} style={s.commentRow}>
                    {comment.user?.profile_image ? (
                      <Image source={{ uri: comment.user.profile_image }} style={s.commentAvatar} />
                    ) : (
                      <View style={s.commentAvatarFallback}>
                        <Text style={s.commentAvatarText}>{name.slice(0, 1).toUpperCase()}</Text>
                      </View>
                    )}
                    <View style={s.commentBubble}>
                      <Text style={s.commentName} numberOfLines={1}>{name}</Text>
                      <Text style={s.commentBody}>{comment.body}</Text>
                    </View>
                  </View>
                );
              })
            ) : (
              <View style={s.commentState}>
                <Text style={s.commentStateTitle}>No comments yet</Text>
                <Text style={s.commentStateText}>Start the conversation.</Text>
              </View>
            )}
          </ScrollView>
          <View style={[s.commentInputBar, { paddingBottom: Math.max(insets.bottom, spacing.sm) }]}>
            <TextInput
              value={noteCommentDraft}
              onChangeText={(value) => setNoteCommentDraft(value.slice(0, 500))}
              placeholder="Add comment..."
              placeholderTextColor={colors.textHint}
              style={s.commentInput}
              multiline
              maxLength={500}
            />
            <TouchableOpacity
              style={[s.commentSend, (!noteCommentDraft.trim() || noteCommentPosting) && s.commentSendDisabled]}
              activeOpacity={0.86}
              disabled={!noteCommentDraft.trim() || noteCommentPosting}
              onPress={submitNoteComment}
              accessibilityLabel="Post comment"
            >
              {noteCommentPosting ? (
                <ActivityIndicator size="small" color={colors.textInverse} />
              ) : (
                <Ionicons name="arrow-up" size={24} color={colors.textInverse} />
              )}
            </TouchableOpacity>
          </View>
        </View>
      </Modal>

      <ReportReasonSheet
        visible={!!reportTargetNote}
        submitting={reportSubmitting}
        onClose={() => {
          if (!reportSubmitting) setReportTargetNote(null);
        }}
        onSelect={submitNoteReport}
      />

      <Modal visible={postChooserVisible} transparent animationType="fade" onRequestClose={() => setPostChooserVisible(false)}>
        <Pressable style={s.postChooserOverlay} onPress={() => setPostChooserVisible(false)}>
          <Pressable style={[s.postChooserSheet, { paddingBottom: Math.max(18, insets.bottom + 12) }]} onPress={() => {}}>
            <View style={s.postChooserHandle} />
            <Text style={s.postChooserTitle}>Create</Text>
            <Text style={s.postChooserSub}>Choose what you want to share.</Text>
            <View style={s.postChooserActions}>
              <TouchableOpacity style={s.postChooserOption} onPress={chooseStandardPost} activeOpacity={0.86}>
                <View style={s.postChooserIcon}>
                  <Ionicons name="images-outline" size={22} color={colors.accentPrimary} />
                </View>
                <View style={s.postChooserCopy}>
                  <Text style={s.postChooserLabel}>Post</Text>
                  <Text style={s.postChooserHint}>Photo, video, carousel, place, or caption.</Text>
                </View>
                <Ionicons name="chevron-forward" size={18} color={colors.textHint} />
              </TouchableOpacity>
              <TouchableOpacity style={s.postChooserOption} onPress={chooseNotePost} activeOpacity={0.86}>
                <View style={s.postChooserIcon}>
                  <Ionicons name="chatbox-ellipses-outline" size={22} color={colors.accentPrimary} />
                </View>
                <View style={s.postChooserCopy}>
                  <Text style={s.postChooserLabel}>Note</Text>
                  <Text style={s.postChooserHint}>Short thought, photo note, or GIF note.</Text>
                </View>
                <Ionicons name="chevron-forward" size={18} color={colors.textHint} />
              </TouchableOpacity>
            </View>
          </Pressable>
        </Pressable>
      </Modal>

      <Modal visible={noteComposerVisible} animationType="slide" onRequestClose={() => setNoteComposerVisible(false)}>
        <KeyboardAvoidingView
          behavior={Platform.OS === 'ios' ? 'padding' : undefined}
          style={[s.composerRoot, { paddingTop: insets.top }]}
        >
          <View style={s.threadComposerHeader}>
            <TouchableOpacity
              onPress={() => {
                if (notePosting) return;
                setNoteComposerVisible(false);
                setNoteError('');
              }}
              activeOpacity={0.84}
            >
              <Text style={s.threadCancelText}>Cancel</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[s.threadSaveButton, (!noteDraft.trim() && !notePhoto) && s.threadSaveButtonDisabled]}
              activeOpacity={0.84}
              disabled={!noteDraft.trim() && !notePhoto}
              onPress={saveNoteDraft}
              accessibilityLabel="Save note draft"
            >
              <Text style={[s.threadSaveText, (!noteDraft.trim() && !notePhoto) && s.threadSaveTextDisabled]}>{draftSavedAt ? 'Saved' : 'Save'}</Text>
            </TouchableOpacity>
          </View>

          <View style={s.threadComposerDivider} />

          <View style={s.threadComposerContent}>
            <View style={s.threadAvatarColumn}>
              {user?.profile_image ? (
                <Image source={{ uri: user.profile_image }} style={s.threadAvatar} />
              ) : (
                <View style={s.threadAvatarFallback}>
                  <Text style={s.threadAvatarText}>{String(user?.full_name || user?.username || 'Y').slice(0, 1).toUpperCase()}</Text>
                </View>
              )}
              <View style={s.threadVerticalLine} />
              <View style={s.threadMiniAvatar}>
                <Text style={s.threadMiniAvatarText}>{String(user?.full_name || user?.username || 'Y').slice(0, 1).toUpperCase()}</Text>
              </View>
            </View>

            <View style={s.threadInputColumn}>
              <View style={s.threadMetaRow}>
                <Text style={s.threadUsername} numberOfLines={1}>{user?.username || user?.full_name || 'yourname'}</Text>
              </View>

              <TextInput
                value={noteDraft}
                onChangeText={(value) => {
                  setNoteDraft(value.slice(0, 420));
                  setDraftSavedAt(null);
                  if (noteError) setNoteError('');
                }}
                placeholder="What's new?"
                placeholderTextColor={colors.textHint}
                style={s.threadInput}
                multiline
                autoFocus
                textAlignVertical="top"
                maxLength={420}
              />

              {notePhoto ? (
                <View style={s.threadPhotoWrap}>
                  <Image source={{ uri: notePhoto.uri }} style={s.threadPhotoPreview} resizeMode="cover" />
                  <TouchableOpacity
                    style={s.threadRemovePhoto}
                    activeOpacity={0.84}
                    onPress={() => {
                      setNotePhoto(null);
                      setDraftSavedAt(null);
                    }}
                  >
                    <Ionicons name="close" size={14} color="#FFFFFF" />
                  </TouchableOpacity>
                </View>
              ) : null}

              <View style={s.threadToolRow}>
                <TouchableOpacity style={s.threadToolButton} activeOpacity={0.72} onPress={pickNotePhoto}>
                  <Ionicons name="image-outline" size={27} color={colors.textHint} />
                </TouchableOpacity>
                <TouchableOpacity
                  style={s.threadToolButton}
                  activeOpacity={0.72}
                  onPress={() => {
                    Keyboard.dismiss();
                    setGifPickerVisible((visible) => !visible);
                    if (!gifPickerVisible && !gifResults.length) void loadGifs('');
                  }}
                >
                  <Text style={s.threadGifText}>GIF</Text>
                </TouchableOpacity>
              </View>

              {gifPickerVisible ? (
                <View style={s.inlineGifPanel}>
                  <View style={s.inlineGifSearchWrap}>
                    <Ionicons name="search" size={17} color={colors.textHint} />
                    <TextInput
                      value={gifQuery}
                      onChangeText={setGifQuery}
                      placeholder="Search GIF"
                      placeholderTextColor={colors.textHint}
                      style={s.inlineGifSearchInput}
                      autoCapitalize="none"
                      autoCorrect={false}
                    />
                    <TouchableOpacity
                      style={s.inlineGifClose}
                      activeOpacity={0.8}
                      onPress={() => setGifPickerVisible(false)}
                      accessibilityLabel="Close GIF picker"
                    >
                      <Ionicons name="close" size={17} color={colors.textHint} />
                    </TouchableOpacity>
                  </View>
                  {gifLoading ? (
                    <View style={s.inlineGifState}>
                      <ActivityIndicator color={colors.textPrimary} />
                    </View>
                  ) : (
                    <ScrollView
                      horizontal
                      showsHorizontalScrollIndicator={false}
                      keyboardShouldPersistTaps="handled"
                      contentContainerStyle={s.inlineGifRail}
                    >
                      {gifResults.map((gif) => (
                        <TouchableOpacity
                          key={gif.id}
                          style={s.inlineGifTile}
                          activeOpacity={0.84}
                          onPress={() => {
                            setNotePhoto({ uri: gif.url, fileName: 'giphy.gif', isRemote: true });
                            setDraftSavedAt(null);
                            setGifPickerVisible(false);
                          }}
                        >
                          <Image source={{ uri: gif.preview }} style={s.gifImage} resizeMode="cover" />
                        </TouchableOpacity>
                      ))}
                      {!gifResults.length ? (
                        <View style={s.inlineGifEmpty}>
                          <Text style={s.inlineGifEmptyText}>No GIFs found</Text>
                        </View>
                      ) : null}
                    </ScrollView>
                  )}
                </View>
              ) : null}

              {noteError ? <Text style={s.threadError}>{noteError}</Text> : null}
            </View>
          </View>

          <View style={s.threadComposerFooter}>
            <View style={s.threadFooterLeft}>
              <TouchableOpacity style={s.threadReplyOptions} activeOpacity={0.8}>
                <Ionicons name="options-outline" size={22} color={colors.textHint} />
                <Text style={s.threadReplyText}>Reply options</Text>
              </TouchableOpacity>
              <TouchableOpacity
                accessibilityLabel="Hide keyboard"
                hitSlop={hitSlop}
                style={s.threadKeyboardButton}
                activeOpacity={0.82}
                onPress={Keyboard.dismiss}
              >
                <Ionicons name="chevron-down" size={20} color={colors.textSecondary} />
              </TouchableOpacity>
            </View>
            <TouchableOpacity
              style={[s.threadPostButton, (noteDraft.trim().length < 2 && !notePhoto) && s.threadPostButtonDisabled]}
              activeOpacity={0.86}
              disabled={(noteDraft.trim().length < 2 && !notePhoto) || notePosting}
              onPress={submitNote}
            >
              <Text style={s.threadPostText}>{notePosting ? 'Posting' : 'Post'}</Text>
            </TouchableOpacity>
          </View>
        </KeyboardAvoidingView>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.bgApp },
  header: {
    minHeight: 88,
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.section,
    paddingBottom: 8,
    backgroundColor: colors.bgApp,
  },
  headerCopy: { flex: 1, minWidth: 0 },
  eyebrow: { color: colors.textHint, fontSize: 12, lineHeight: 16, fontWeight: '700', letterSpacing: 0.6, textTransform: 'uppercase' },
  title: { color: colors.textPrimary, fontSize: 31, lineHeight: 37, fontWeight: '600', letterSpacing: 0 },
  searchButton: {
    width: layout.iconButton,
    height: layout.iconButton,
    borderRadius: layout.iconButton / 2,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  storyPanel: {
    marginHorizontal: spacing.md,
    borderRadius: 24,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    paddingTop: 10,
    paddingBottom: 6,
  },
  storyHeader: {
    minHeight: 34,
    paddingHorizontal: spacing.md,
    paddingBottom: 4,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  storySearchButton: {
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.bgSubtle,
  },
  sectionTitle: { color: colors.textPrimary, fontSize: 18, lineHeight: 23, fontWeight: '600' },
  sectionSubtitle: { marginTop: 1, color: colors.textHint, fontSize: 12, lineHeight: 16, fontWeight: '500' },
  storyRail: { gap: 12, paddingHorizontal: spacing.md, paddingVertical: 2 },
  storyItem: { width: 66, alignItems: 'center' },
  avatarRing: {
    width: 62,
    height: 62,
    borderRadius: 31,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: colors.borderSubtle,
    backgroundColor: colors.surfaceRaised,
  },
  avatarRingActive: { borderColor: colors.accentPrimary },
  avatarImage: { width: 54, height: 54, borderRadius: 27, backgroundColor: colors.bgSubtle },
  avatarFallback: {
    width: 54,
    height: 54,
    borderRadius: 27,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.surfaceRaised,
  },
  avatarInitial: { color: colors.textPrimary, fontSize: 21, fontWeight: '600' },
  addBadge: {
    position: 'absolute',
    right: 1,
    bottom: 1,
    width: 20,
    height: 20,
    borderRadius: 10,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.accentPrimary,
    borderWidth: 2,
    borderColor: colors.bgApp,
  },
  storyName: { marginTop: 4, color: colors.textPrimary, fontSize: 11, lineHeight: 14, fontWeight: '600', textAlign: 'center' },
  notesPanel: {
    marginTop: 8,
    paddingTop: 0,
  },
  notesHeader: {
    paddingHorizontal: spacing.section,
    paddingBottom: 6,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  notesCreateButton: {
    width: 38,
    height: 38,
    borderRadius: 19,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.accentPrimary,
  },
  notesRail: {
    gap: spacing.gutter,
    paddingHorizontal: spacing.section,
    paddingBottom: spacing.xs,
  },
  noteLargeCard: {
    borderRadius: 24,
    borderWidth: 1,
    borderColor: 'rgba(32,54,31,0.10)',
    backgroundColor: colors.surfaceRaised,
    padding: 14,
    gap: 10,
  },
  noteCreateLargeCard: {
    padding: spacing.md,
    justifyContent: 'space-between',
  },
  noteCreateProfile: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  noteCreateCopy: { flex: 1, minWidth: 0 },
  noteCreateCenter: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 8, paddingHorizontal: spacing.md },
  noteCreateIcon: {
    width: 46,
    height: 46,
    borderRadius: 23,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.accentPrimary,
  },
  noteCreateTitle: { color: colors.textPrimary, fontSize: 20, lineHeight: 25, fontWeight: '600', textAlign: 'center' },
  noteCreateText: { color: colors.textSecondary, fontSize: 12, lineHeight: 17, fontWeight: '500', textAlign: 'center' },
  noteCardPhoto: {
    ...StyleSheet.absoluteFillObject,
    width: '100%',
    height: '100%',
    resizeMode: 'cover',
  },
  notePhotoShade: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.20)',
  },
  noteTextShade: {
    backgroundColor: 'rgba(255,255,255,0.08)',
  },
  noteLargeTopRow: {
    position: 'absolute',
    left: spacing.md,
    right: spacing.md,
    top: spacing.md,
    zIndex: 2,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  noteLargeAvatar: { width: 40, height: 40, borderRadius: 20, backgroundColor: colors.bgSubtle },
  noteAvatarWrap: { width: 40, height: 40, borderRadius: 20, position: 'relative' },
  noteFollowBadge: {
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
    borderColor: colors.surfaceRaised,
  },
  noteFollowBadgeOn: { backgroundColor: colors.textPrimary },
  noteLargeAvatarFallback: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.accentPrimaryLight,
  },
  noteLargeAvatarText: { color: colors.textPrimary, fontSize: 16, fontWeight: '600' },
  noteThreadHeader: { flexDirection: 'row', alignItems: 'center', gap: 9 },
  noteThreadAuthorCopy: { flex: 1, minWidth: 0 },
  noteThreadNameRow: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 5, minWidth: 0 },
  noteThreadAuthor: { flex: 1, minWidth: 0, color: colors.textPrimary, fontSize: 17, lineHeight: 22, fontWeight: '700' },
  noteVerifiedBadge: {
    width: 16,
    height: 16,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#3B9CE8',
  },
  noteThreadTime: { flexShrink: 0, color: colors.textHint, fontSize: 15, lineHeight: 20, fontWeight: '600' },
  noteMenuButton: {
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
  },
  noteThreadBody: { color: '#050605', fontSize: 18, lineHeight: 25, fontWeight: '700' },
  noteThreadBodyTextOnly: { flex: 1, textAlignVertical: 'center' },
  noteThreadMore: { color: colors.textHint, fontWeight: '700' },
  noteThreadImage: {
    width: '100%',
    borderRadius: 18,
    backgroundColor: colors.bgSubtle,
  },
  noteThreadActions: {
    marginTop: 'auto',
    minHeight: 36,
    flexShrink: 0,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 6,
  },
  noteThreadAction: { minWidth: 64, minHeight: 34, flexDirection: 'row', alignItems: 'center', gap: 4 },
  noteThreadActionText: { color: colors.textSecondary, fontSize: 15, lineHeight: 20, fontWeight: '600', fontVariant: ['tabular-nums'] },
  noteLargeAuthorCopy: { flex: 1, minWidth: 0 },
  noteLargeAuthor: { color: colors.textPrimary, fontSize: 15, lineHeight: 19, fontWeight: '600' },
  noteLargeMeta: { color: colors.textSecondary, fontSize: 12, lineHeight: 16, fontWeight: '500' },
  noteLargeAuthorOnPhoto: { color: '#FFFFFF', textShadowColor: 'rgba(0,0,0,0.35)', textShadowRadius: 7 },
  noteLargeMetaOnPhoto: { color: 'rgba(255,255,255,0.78)', textShadowColor: 'rgba(0,0,0,0.35)', textShadowRadius: 7 },
  noteLargeBottom: {
    position: 'absolute',
    left: spacing.md,
    right: spacing.md,
    bottom: spacing.md,
    zIndex: 2,
    gap: spacing.gutter,
  },
  noteLargeBody: { color: colors.textPrimary, fontSize: 28, lineHeight: 34, fontWeight: '600' },
  noteLargeBodyOnPhoto: {
    color: '#FFFFFF',
    textShadowColor: 'rgba(0,0,0,0.42)',
    textShadowRadius: 9,
    textShadowOffset: { width: 0, height: 1 },
  },
  noteLargeActions: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: spacing.sm },
  noteLargePill: {
    overflow: 'hidden',
    paddingHorizontal: 11,
    paddingVertical: 7,
    borderRadius: 999,
    backgroundColor: 'rgba(255,255,255,0.62)',
    color: colors.textSecondary,
    fontSize: 12,
    lineHeight: 15,
    fontWeight: '600',
  },
  noteLargePillOnPhoto: { color: '#FFFFFF', backgroundColor: 'rgba(0,0,0,0.30)' },
  noteLargeCounts: { color: colors.textHint, fontSize: 12, lineHeight: 15, fontWeight: '600' },
  noteLargeCountsOnPhoto: { color: 'rgba(255,255,255,0.82)' },
  noteComposerCard: {
    width: 142,
    minHeight: 132,
    borderRadius: 24,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    padding: spacing.md,
    justifyContent: 'space-between',
  },
  noteComposerIcon: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.accentPrimaryLight,
  },
  noteComposerTitle: { color: colors.textPrimary, fontSize: 15, lineHeight: 19, fontWeight: '600' },
  noteComposerText: { color: colors.textHint, fontSize: 12, lineHeight: 16, fontWeight: '500' },
  noteCard: {
    width: 218,
    minHeight: 132,
    borderRadius: 24,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    justifyContent: 'space-between',
  },
  noteTopRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  noteAvatar: { width: 32, height: 32, borderRadius: 16, backgroundColor: colors.bgSubtle },
  noteAvatarFallback: {
    width: 32,
    height: 32,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.72)',
  },
  noteAvatarText: { color: colors.textPrimary, fontSize: 13, fontWeight: '600' },
  noteAuthorCopy: { flex: 1, minWidth: 0 },
  noteAuthor: { color: colors.textPrimary, fontSize: 13, lineHeight: 17, fontWeight: '600' },
  noteMeta: { color: colors.textHint, fontSize: 11, lineHeight: 14, fontWeight: '500' },
  noteBody: { marginTop: spacing.gutter, color: colors.textPrimary, fontSize: 15, lineHeight: 20, fontWeight: '500' },
  noteBottomRow: { marginTop: spacing.gutter, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: spacing.sm },
  notePill: {
    overflow: 'hidden',
    paddingHorizontal: 9,
    paddingVertical: 5,
    borderRadius: 999,
    backgroundColor: 'rgba(255,255,255,0.58)',
    color: colors.textSecondary,
    fontSize: 11,
    lineHeight: 14,
    fontWeight: '600',
  },
  noteCounts: { color: colors.textHint, fontSize: 11, lineHeight: 14, fontWeight: '600' },
  noteSkeleton: {
    width: 188,
    minHeight: 132,
    borderRadius: 24,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    padding: spacing.md,
    justifyContent: 'center',
    gap: spacing.sm,
  },
  noteSkeletonLine: { height: 14, borderRadius: 8, backgroundColor: colors.skeleton },
  noteSkeletonShort: { width: '62%' },
  noteEmptyCard: {
    width: 210,
    minHeight: 132,
    borderRadius: 24,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    padding: spacing.md,
    justifyContent: 'center',
  },
  noteEmptyTitle: { color: colors.textPrimary, fontSize: 16, lineHeight: 21, fontWeight: '600' },
  noteEmptyText: { marginTop: spacing.xs, color: colors.textHint, fontSize: 13, lineHeight: 18, fontWeight: '500' },
  body: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: spacing.xl, paddingBottom: 110 },
  loadingCard: {
    width: '100%',
    maxWidth: 310,
    minHeight: 112,
    borderRadius: 28,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    padding: spacing.md,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
  },
  loadingAvatar: {
    width: 62,
    height: 62,
    borderRadius: 31,
    backgroundColor: colors.bgSubtle,
  },
  loadingLines: { flex: 1, gap: spacing.sm },
  loadingLine: {
    height: 13,
    borderRadius: 7,
    backgroundColor: colors.bgSubtle,
  },
  loadingLineShort: { width: '62%' },
  empty: { alignItems: 'center', padding: spacing.lg, borderRadius: 28, backgroundColor: colors.surfaceRaised, borderWidth: 1, borderColor: colors.borderSubtle },
  emptyIcon: {
    width: 86,
    height: 86,
    borderRadius: 43,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.bgSubtle,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
  },
  emptyTitle: { marginTop: spacing.md, color: colors.textPrimary, fontSize: 22, lineHeight: 28, fontWeight: '600', textAlign: 'center' },
  emptyText: { marginTop: 6, color: colors.textHint, fontSize: 14, lineHeight: 20, fontWeight: '500', textAlign: 'center' },
  searchRoot: { flex: 1, backgroundColor: colors.bgApp },
  searchHeader: {
    minHeight: 58,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
  },
  searchClose: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  searchTitle: { color: colors.textPrimary, fontSize: 19, lineHeight: 24, fontWeight: '600' },
  searchInputWrap: {
    minHeight: 48,
    borderRadius: 18,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginHorizontal: spacing.md,
    paddingHorizontal: spacing.gutter,
  },
  searchInput: { flex: 1, minHeight: 46, color: colors.textPrimary, fontSize: 16, lineHeight: 21, fontWeight: '500' },
  searchState: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: spacing.xl, paddingBottom: 120 },
  searchStateTitle: { color: colors.textPrimary, fontSize: 21, lineHeight: 27, fontWeight: '600', textAlign: 'center' },
  searchStateText: { marginTop: 6, color: colors.textHint, fontSize: 14, lineHeight: 20, fontWeight: '500', textAlign: 'center' },
  searchList: { flex: 1, paddingHorizontal: spacing.md, paddingTop: spacing.md },
  userRow: {
    minHeight: 68,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.gutter,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.borderSubtle,
  },
  userAvatar: { width: 46, height: 46, borderRadius: 23, backgroundColor: colors.bgSubtle },
  userAvatarFallback: {
    width: 46,
    height: 46,
    borderRadius: 23,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
  },
  userAvatarText: { color: colors.textPrimary, fontSize: 17, fontWeight: '600' },
  userInfo: { flex: 1, minWidth: 0 },
  userName: { color: colors.textPrimary, fontSize: 15, lineHeight: 20, fontWeight: '600' },
  userHandle: { color: colors.textHint, fontSize: 12, lineHeight: 16, fontWeight: '500', marginTop: 1 },
  postChooserOverlay: { flex: 1, justifyContent: 'flex-end', backgroundColor: 'rgba(244,245,241,0.62)' },
  postChooserSheet: {
    backgroundColor: colors.bgModal,
    borderTopLeftRadius: 26,
    borderTopRightRadius: 26,
    paddingTop: 10,
    paddingHorizontal: 16,
    gap: 8,
    ...shadows.sheet,
  },
  postChooserHandle: { alignSelf: 'center', width: 42, height: 5, borderRadius: 3, backgroundColor: colors.borderMedium },
  postChooserTitle: { color: colors.textPrimary, fontSize: 22, lineHeight: 27, fontWeight: '700', marginTop: 2 },
  postChooserSub: { color: colors.textSecondary, fontSize: 13, lineHeight: 18, fontWeight: '500', marginBottom: 6 },
  postChooserActions: { gap: 8 },
  postChooserOption: {
    minHeight: 66,
    borderRadius: 18,
    backgroundColor: colors.bgSubtle,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingHorizontal: 12,
  },
  postChooserIcon: {
    width: 42,
    height: 42,
    borderRadius: 21,
    backgroundColor: colors.surfaceRaised,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: colors.borderSubtle,
  },
  postChooserCopy: { flex: 1, minWidth: 0 },
  postChooserLabel: { color: colors.textPrimary, fontSize: 16, lineHeight: 21, fontWeight: '700' },
  postChooserHint: { color: colors.textSecondary, fontSize: 12, lineHeight: 16, fontWeight: '500', marginTop: 1 },
  composerRoot: { flex: 1, backgroundColor: colors.bgApp },
  composerPostButton: {
    minWidth: 68,
    height: 38,
    borderRadius: 19,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.accentPrimary,
    paddingHorizontal: spacing.md,
  },
  composerPostButtonDisabled: { opacity: 0.42 },
  composerPostText: { color: colors.textInverse, fontSize: 14, lineHeight: 18, fontWeight: '600' },
  composerCard: {
    margin: spacing.md,
    borderRadius: 26,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    padding: spacing.md,
  },
  composerPhotoButton: {
    height: 245,
    borderRadius: 24,
    overflow: 'hidden',
    backgroundColor: colors.bgSubtle,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
  },
  composerPhotoPreview: { width: '100%', height: '100%' },
  composerPhotoEmpty: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: spacing.sm },
  composerPhotoText: { color: colors.textHint, fontSize: 14, lineHeight: 18, fontWeight: '600' },
  composerRemovePhoto: {
    alignSelf: 'flex-start',
    minHeight: 34,
    borderRadius: 17,
    marginTop: spacing.sm,
    paddingHorizontal: spacing.gutter,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    backgroundColor: colors.bgSubtle,
  },
  composerRemovePhotoText: { color: colors.textSecondary, fontSize: 13, lineHeight: 17, fontWeight: '600' },
  composerInput: {
    minHeight: 180,
    color: colors.textPrimary,
    fontSize: 18,
    lineHeight: 25,
    fontWeight: '500',
  },
  composerInputWithPhoto: { minHeight: 120, marginTop: spacing.sm },
  composerFooter: { minHeight: 28, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: spacing.md },
  composerCounter: { color: colors.textHint, fontSize: 12, lineHeight: 16, fontWeight: '500' },
  composerError: { flex: 1, color: colors.error, fontSize: 12, lineHeight: 16, fontWeight: '600', textAlign: 'right' },
  commentRoot: {
    flex: 1,
    backgroundColor: colors.bgApp,
  },
  commentHeader: {
    minHeight: 58,
    paddingHorizontal: spacing.md,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  commentClose: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  commentTitle: { color: colors.textPrimary, fontSize: 20, lineHeight: 26, fontWeight: '700' },
  commentList: { flex: 1 },
  commentListContent: { paddingHorizontal: spacing.md, paddingTop: spacing.sm, paddingBottom: spacing.xl },
  commentState: { minHeight: 180, alignItems: 'center', justifyContent: 'center', gap: 4 },
  commentStateTitle: { color: colors.textPrimary, fontSize: 18, lineHeight: 23, fontWeight: '700' },
  commentStateText: { color: colors.textSecondary, fontSize: 14, lineHeight: 19, fontWeight: '500' },
  commentRow: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.sm, marginBottom: spacing.gutter },
  commentAvatar: { width: 34, height: 34, borderRadius: 17, backgroundColor: colors.bgSubtle },
  commentAvatarFallback: {
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.accentPrimaryLight,
  },
  commentAvatarText: { color: colors.textPrimary, fontSize: 13, lineHeight: 17, fontWeight: '700' },
  commentBubble: {
    flex: 1,
    minWidth: 0,
    borderRadius: 18,
    paddingHorizontal: spacing.gutter,
    paddingVertical: spacing.sm,
    backgroundColor: colors.bgCard,
  },
  commentName: { color: colors.textPrimary, fontSize: 13, lineHeight: 17, fontWeight: '700' },
  commentBody: { color: colors.textSecondary, fontSize: 14, lineHeight: 20, fontWeight: '500', marginTop: 2 },
  commentInputBar: {
    paddingTop: spacing.sm,
    paddingHorizontal: spacing.md,
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: spacing.sm,
    backgroundColor: colors.bgApp,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.borderSubtle,
  },
  commentInput: {
    flex: 1,
    minHeight: 48,
    maxHeight: 112,
    borderRadius: 22,
    paddingHorizontal: spacing.md,
    paddingTop: 13,
    paddingBottom: 10,
    color: colors.textPrimary,
    backgroundColor: colors.bgSubtle,
    fontSize: 16,
    lineHeight: 21,
    fontWeight: '500',
  },
  commentSend: {
    width: 48,
    height: 48,
    borderRadius: 24,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.accentPrimary,
  },
  commentSendDisabled: { backgroundColor: colors.textDisabled },
  gifRoot: { flex: 1, backgroundColor: colors.bgApp },
  gifHeader: {
    minHeight: 58,
    paddingHorizontal: spacing.md,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  gifClose: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  gifTitle: { color: colors.textPrimary, fontSize: 20, lineHeight: 26, fontWeight: '800' },
  gifSearchWrap: {
    minHeight: 48,
    marginHorizontal: spacing.md,
    paddingHorizontal: spacing.md,
    borderRadius: 24,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    backgroundColor: colors.bgSubtle,
  },
  gifSearchInput: { flex: 1, color: colors.textPrimary, fontSize: 16, lineHeight: 21, fontWeight: '500' },
  gifState: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  gifGrid: {
    padding: spacing.md,
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
  },
  gifTile: {
    width: '31.8%',
    aspectRatio: 1,
    borderRadius: 14,
    overflow: 'hidden',
    backgroundColor: colors.bgSubtle,
  },
  gifImage: { width: '100%', height: '100%' },
  gifEmpty: { width: '100%', minHeight: 180, alignItems: 'center', justifyContent: 'center', gap: 4 },
  gifEmptyTitle: { color: colors.textPrimary, fontSize: 18, lineHeight: 23, fontWeight: '700' },
  gifEmptyText: { color: colors.textSecondary, fontSize: 14, lineHeight: 19, fontWeight: '500' },
  inlineGifPanel: {
    marginTop: spacing.sm,
    borderRadius: 18,
    paddingVertical: spacing.sm,
    backgroundColor: colors.bgCard,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
  },
  inlineGifSearchWrap: {
    minHeight: 40,
    marginHorizontal: spacing.sm,
    paddingHorizontal: spacing.gutter,
    borderRadius: 20,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    backgroundColor: colors.bgSubtle,
  },
  inlineGifSearchInput: {
    flex: 1,
    minWidth: 0,
    color: colors.textPrimary,
    fontSize: 14,
    lineHeight: 19,
    fontWeight: '600',
    paddingVertical: 0,
  },
  inlineGifClose: { width: 28, height: 28, alignItems: 'center', justifyContent: 'center' },
  inlineGifState: { height: 96, alignItems: 'center', justifyContent: 'center' },
  inlineGifRail: { paddingHorizontal: spacing.sm, paddingTop: spacing.sm, gap: spacing.sm },
  inlineGifTile: {
    width: 82,
    height: 100,
    borderRadius: 14,
    overflow: 'hidden',
    backgroundColor: colors.bgSubtle,
  },
  inlineGifEmpty: { width: 180, height: 90, alignItems: 'center', justifyContent: 'center' },
  inlineGifEmptyText: { color: colors.textHint, fontSize: 13, lineHeight: 18, fontWeight: '600' },
  threadComposerHeader: {
    minHeight: 78,
    paddingHorizontal: spacing.md,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: colors.bgApp,
  },
  threadCancelText: {
    color: colors.textPrimary,
    fontSize: 21,
    lineHeight: 27,
    fontWeight: '600',
  },
  threadSaveButton: {
    minWidth: 72,
    height: 38,
    borderRadius: 19,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: spacing.md,
    backgroundColor: colors.accentPrimary,
  },
  threadSaveButtonDisabled: {
    backgroundColor: colors.bgSubtle,
  },
  threadSaveText: {
    color: colors.textInverse,
    fontSize: 15,
    lineHeight: 20,
    fontWeight: '700',
  },
  threadSaveTextDisabled: {
    color: colors.textHint,
  },
  threadHeaderSpacer: { width: 70, height: 36 },
  threadComposerTitle: {
    position: 'absolute',
    left: 96,
    right: 96,
    textAlign: 'center',
    color: colors.textPrimary,
    fontSize: 22,
    lineHeight: 28,
    fontWeight: '700',
  },
  threadHeaderActions: { flexDirection: 'row', alignItems: 'center', gap: 14 },
  threadHeaderIcon: {
    width: 36,
    height: 36,
    alignItems: 'center',
    justifyContent: 'center',
  },
  threadComposerDivider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.borderSubtle,
  },
  threadComposerContent: {
    flex: 1,
    flexDirection: 'row',
    paddingHorizontal: spacing.md,
    paddingTop: 22,
  },
  threadAvatarColumn: {
    width: 48,
    alignItems: 'center',
  },
  threadAvatar: { width: 44, height: 44, borderRadius: 22, backgroundColor: colors.bgSubtle },
  threadAvatarFallback: {
    width: 44,
    height: 44,
    borderRadius: 22,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.accentPrimaryLight,
  },
  threadAvatarText: { color: colors.textPrimary, fontSize: 17, lineHeight: 22, fontWeight: '700' },
  threadVerticalLine: {
    width: 3,
    flex: 1,
    minHeight: 126,
    marginTop: 12,
    marginBottom: 10,
    borderRadius: 999,
    backgroundColor: colors.borderSubtle,
  },
  threadMiniAvatar: {
    width: 24,
    height: 24,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.bgSubtle,
    opacity: 0.52,
  },
  threadMiniAvatarText: { color: colors.textHint, fontSize: 11, fontWeight: '700' },
  threadInputColumn: {
    flex: 1,
    minWidth: 0,
    paddingLeft: spacing.gutter,
  },
  threadMetaRow: {
    minHeight: 30,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
  },
  threadUsername: {
    maxWidth: '48%',
    color: colors.textPrimary,
    fontSize: 21,
    lineHeight: 27,
    fontWeight: '700',
  },
  threadTopic: {
    flex: 1,
    minWidth: 0,
    color: colors.textHint,
    fontSize: 21,
    lineHeight: 27,
    fontWeight: '600',
  },
  threadInput: {
    minHeight: 70,
    color: colors.textPrimary,
    fontSize: 21,
    lineHeight: 28,
    fontWeight: '400',
    paddingTop: 2,
    paddingBottom: 8,
  },
  threadToolRow: {
    minHeight: 46,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 22,
    marginTop: 8,
  },
  threadToolButton: {
    minWidth: 30,
    minHeight: 36,
    alignItems: 'center',
    justifyContent: 'center',
  },
  threadGifText: {
    color: colors.textHint,
    fontSize: 15,
    lineHeight: 19,
    fontWeight: '800',
    borderWidth: 2,
    borderColor: colors.textHint,
    borderRadius: 6,
    paddingHorizontal: 3,
    paddingVertical: 1,
  },
  threadPhotoWrap: {
    width: '78%',
    aspectRatio: 0.78,
    borderRadius: 18,
    overflow: 'hidden',
    backgroundColor: colors.bgSubtle,
    marginTop: spacing.sm,
  },
  threadPhotoPreview: { width: '100%', height: '100%' },
  threadRemovePhoto: {
    position: 'absolute',
    right: 8,
    top: 8,
    width: 26,
    height: 26,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(0,0,0,0.48)',
  },
  threadAddRow: {
    minHeight: 48,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    marginTop: 12,
  },
  threadGhostAvatar: {
    width: 22,
    height: 22,
    borderRadius: 11,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.bgSubtle,
    opacity: 0.5,
  },
  threadGhostAvatarText: { color: colors.textHint, fontSize: 10, fontWeight: '700' },
  threadAddText: {
    color: colors.textHint,
    fontSize: 20,
    lineHeight: 26,
    fontWeight: '600',
    opacity: 0.45,
  },
  threadError: {
    color: colors.error,
    fontSize: 13,
    lineHeight: 18,
    fontWeight: '600',
    marginTop: spacing.sm,
  },
  threadComposerFooter: {
    minHeight: 86,
    paddingHorizontal: spacing.md,
    paddingBottom: spacing.md,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: colors.bgApp,
  },
  threadFooterLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    flexShrink: 1,
  },
  threadReplyOptions: {
    minHeight: 44,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 9,
    flexShrink: 1,
  },
  threadReplyText: {
    color: colors.textHint,
    fontSize: 16,
    lineHeight: 22,
    fontWeight: '600',
  },
  threadKeyboardButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
  },
  threadPostButton: {
    minWidth: 86,
    height: 48,
    borderRadius: 24,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.accentPrimary,
    paddingHorizontal: spacing.lg,
  },
  threadPostButtonDisabled: {
    backgroundColor: 'rgba(0,0,0,0.26)',
  },
  threadPostText: {
    color: colors.textInverse,
    fontSize: 19,
    lineHeight: 24,
    fontWeight: '700',
  },
});
