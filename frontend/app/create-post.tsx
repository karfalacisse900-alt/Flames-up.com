import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  View, Text, StyleSheet, TextInput, TouchableOpacity, Image, ScrollView,
  KeyboardAvoidingView, Platform, ActivityIndicator, Alert, Dimensions,
  Modal, PanResponder,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import * as Location from 'expo-location';
import { ResizeMode, Video } from 'expo-av';
import { useAuthStore } from '../src/store/authStore';
import api from '../src/api/client';
import { mirrorPostToSupabase } from '../src/api/supabaseData';
import { uploadImageWithBackup, uploadVideoWithBackup } from '../src/utils/mediaUpload';
import { processMediaBatch, type ProcessedMediaAsset } from '../src/utils/mediaProcessing';
import { HD_VIDEO_EXPORT_PRESET, HD_VIDEO_QUALITY, POST_IMAGE_PICKER_QUALITY } from '../src/utils/mediaQuality';
import {
  CREATOR_FILTER_PRESETS,
  TEXT_COLORS,
  TEXT_STYLE_PRESETS,
  buildCreatorEditorOverlays,
  clampNumber as clampEditorNumber,
  createTextOverlayFromPreset,
  filterOverlayFromPreset,
  sanitizeTextOverlay,
  type CreatorFilterOverlay,
  type CreatorTextOverlay,
  type CreatorTextType,
} from '../src/utils/creatorEditor';
import { isPhoneVerificationError, requireVerifiedPhone } from '../src/utils/phoneVerification';
import { borderRadius, colors, layout, shadows, spacing } from '../src/utils/theme';

const { width: SW, height: SH } = Dimensions.get('window');

const CATEGORIES = [
  { id: 'food',      label: 'Food',      icon: 'restaurant-outline', color: '#F59E0B' },
  { id: 'fashion',   label: 'Fashion',   icon: 'shirt-outline',      color: '#EC4899' },
  { id: 'culture',   label: 'Culture',   icon: 'color-palette-outline', color: '#8B5CF6' },
  { id: 'street',    label: 'Street',    icon: 'musical-notes-outline', color: '#10B981' },
  { id: 'nightlife', label: 'Nightlife', icon: 'moon-outline',       color: '#6366F1' },
  { id: 'city_life', label: 'City Life', icon: 'business-outline',   color: '#0EA5E9' },
];

type PostAudience = 'public' | 'followers' | 'friends' | 'private';
type StudioPanel = 'filters' | 'text' | 'tags' | null;
type FilterPresetId = 'original' | typeof CREATOR_FILTER_PRESETS[number]['id'];

const AUDIENCE_OPTIONS: { id: PostAudience; label: string; sub: string; icon: keyof typeof Ionicons.glyphMap }[] = [
  { id: 'public', label: 'Public', sub: 'Anyone can see this post.', icon: 'earth-outline' },
  { id: 'followers', label: 'Followers', sub: 'Only people who follow you can see it.', icon: 'people-outline' },
  { id: 'friends', label: 'Friends', sub: 'Only approved friends can see it.', icon: 'people-circle-outline' },
  { id: 'private', label: 'Only me', sub: 'Keep this post private to your account.', icon: 'lock-closed-outline' },
];

function clamp(value: number, min: number, max: number) {
  if (!Number.isFinite(value)) return min;
  return Math.max(min, Math.min(max, value));
}

function clampUnit(value: number) {
  return clamp(value, 0.04, 0.96);
}

// Detect best format from image dimensions
function detectFormat(width: number, height: number): string {
  if (width <= 0 || height <= 0) return 'auto';
  const ratio = height / width;
  const formats = [
    { id: '1:1',  ratio: 1 },
    { id: '4:5',  ratio: 5 / 4 },
    { id: '3:4',  ratio: 4 / 3 },
    { id: '2:3',  ratio: 3 / 2 },
    { id: '9:16', ratio: 16 / 9 },
  ];
  let bestMatch = formats[0];
  let bestDiff = Math.abs(ratio - formats[0].ratio);
  for (const f of formats) {
    const diff = Math.abs(ratio - f.ratio);
    if (diff < bestDiff) { bestDiff = diff; bestMatch = f; }
  }
  return bestMatch.id;
}

type StudioMediaItem = {
  uri: string;
  type: 'image' | 'video';
  base64?: string;
  width?: number;
  height?: number;
  mimeType?: string;
  fileName?: string | null;
  fileSize?: number;
};

type TaggedPostUser = {
  id: string;
  username?: string;
  full_name?: string;
  profile_image?: string;
  bio?: string;
};

export default function CreatePostScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();
  const params = useLocalSearchParams<{
    place_id?: string;
    place_name?: string;
  }>();

  const [media, setMedia] = useState<StudioMediaItem[]>([]);
  const [headline, setHeadline] = useState('');
  const [caption, setCaption] = useState('');
  const [category, setCategory] = useState<string | null>(null);
  const format = 'auto';
  const [detectedFormat, setDetectedFormat] = useState('');
  const [placeTag, setPlaceTag] = useState(params.place_name || '');
  const [placeAddress, setPlaceAddress] = useState('');
  const [placeId] = useState(params.place_id || '');
  const [isPosting, setIsPosting] = useState(false);
  const [uploadStep, setUploadStep] = useState('');
  const [previewVisible, setPreviewVisible] = useState(false);
  const [postPreviewVisible, setPostPreviewVisible] = useState(false);
  const [studioPanel, setStudioPanel] = useState<StudioPanel>(null);
  const [activeFilter, setActiveFilter] = useState<FilterPresetId>('original');
  const [filterIntensity, setFilterIntensity] = useState(75);
  const [intensityTrackWidth, setIntensityTrackWidth] = useState(1);
  const [textOverlays, setTextOverlays] = useState<CreatorTextOverlay[]>([]);
  const [selectedTextId, setSelectedTextId] = useState('');
  const [overlayTextDraft, setOverlayTextDraft] = useState<CreatorTextOverlay | null>(null);
  const [textOverlayVisible, setTextOverlayVisible] = useState(false);
  const [studioFrameSize, setStudioFrameSize] = useState({ width: 0, height: 0 });
  const [audience, setAudience] = useState<PostAudience>('public');
  const [audienceVisible, setAudienceVisible] = useState(false);
  const [tagUserVisible, setTagUserVisible] = useState(false);
  const [tagUserQuery, setTagUserQuery] = useState('');
  const [tagUserResults, setTagUserResults] = useState<TaggedPostUser[]>([]);
  const [taggedUsers, setTaggedUsers] = useState<Record<string, TaggedPostUser>>({});
  const [tagUserLoading, setTagUserLoading] = useState(false);
  const [placePickerVisible, setPlacePickerVisible] = useState(false);
  const [placeDraftName, setPlaceDraftName] = useState(params.place_name || '');
  const [placeDraftAddress, setPlaceDraftAddress] = useState('');

  // Auto-attach place tag if coming from a place detail page
  const audienceMeta = AUDIENCE_OPTIONS.find((item) => item.id === audience) || AUDIENCE_OPTIONS[0];
  const taggedUserList = useMemo(() => Object.values(taggedUsers), [taggedUsers]);
  const placeDisplay = [placeTag, placeAddress]
    .map((value) => String(value || '').trim())
    .filter((value, index, arr) => value && arr.indexOf(value) === index)
    .join(' · ');
  const pickerOpenedRef = useRef(false);
  const selectedTextIdRef = useRef(selectedTextId);
  const textDragStartRef = useRef({ x: 0.5, y: 0.18 });

  useEffect(() => {
    selectedTextIdRef.current = selectedTextId;
  }, [selectedTextId]);

  const textPanResponder = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: (_, gesture) => Math.abs(gesture.dx) > 2 || Math.abs(gesture.dy) > 2,
    onPanResponderGrant: () => {
      const active = textOverlays.find((item) => item.id === selectedTextIdRef.current);
      textDragStartRef.current = active ? { x: active.x, y: active.y } : { x: 0.5, y: 0.18 };
    },
    onPanResponderMove: (_, gesture) => {
      const width = studioFrameSize.width || SW;
      const height = studioFrameSize.height || Math.max(360, SH * 0.58);
      const activeId = selectedTextIdRef.current;
      setTextOverlays((prev) => prev.map((item) => item.id === activeId ? {
        ...item,
        x: clampUnit(textDragStartRef.current.x + gesture.dx / width),
        y: clampUnit(textDragStartRef.current.y + gesture.dy / height),
      } : item));
    },
  }), [studioFrameSize.height, studioFrameSize.width, textOverlays]);

  const addProcessedMediaAssets = useCallback((processedAssets: ProcessedMediaAsset[]) => {
    const newMedia = processedAssets.map((a) => ({
      uri: a.uri,
      type: a.type === 'video' ? 'video' : 'image',
      base64: a.base64,
      width: a.width || 0,
      height: a.height || 0,
      mimeType: a.mimeType,
      fileName: a.fileName,
      fileSize: a.fileSize,
    })) as StudioMediaItem[];
    setMedia((prev) => {
      const updated = [...prev, ...newMedia].slice(0, 6);
      const firstImg = updated.find(m => m.type === 'image' && m.width && m.height);
      if (firstImg && firstImg.width && firstImg.height) {
        setDetectedFormat(detectFormat(firstImg.width, firstImg.height));
      }
      return updated;
    });
  }, []);

  const pickMedia = useCallback(async () => {
    try {
      const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (status !== 'granted') {
        Alert.alert('Permission needed', 'Please allow access to your photo library');
        return;
      }
      const result = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ['images', 'videos'],
        allowsMultipleSelection: true,
        quality: POST_IMAGE_PICKER_QUALITY,
        base64: true,
        selectionLimit: 6,
        videoExportPreset: HD_VIDEO_EXPORT_PRESET,
        videoQuality: HD_VIDEO_QUALITY,
        preferredAssetRepresentationMode: ImagePicker.UIImagePickerPreferredAssetRepresentationMode.Current,
      });
      if (!result.canceled && result.assets) {
        setUploadStep('Preparing media...');
        const processedAssets = await processMediaBatch(result.assets, 'quality');
        addProcessedMediaAssets(processedAssets);
      }
    } catch (error) {
      console.log('Media picker error:', error);
      Alert.alert('Media selection failed', 'Please try selecting media again.');
    } finally {
      setUploadStep('');
    }
  }, [addProcessedMediaAssets]);

  const pickSingleMediaItem = async (): Promise<StudioMediaItem | null> => {
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Permission needed', 'Please allow access to your photo library');
      return null;
    }

    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images', 'videos'],
      allowsMultipleSelection: false,
      quality: POST_IMAGE_PICKER_QUALITY,
      base64: true,
      selectionLimit: 1,
      videoExportPreset: HD_VIDEO_EXPORT_PRESET,
      videoQuality: HD_VIDEO_QUALITY,
      preferredAssetRepresentationMode: ImagePicker.UIImagePickerPreferredAssetRepresentationMode.Current,
    });

    if (result.canceled || !result.assets?.[0]) return null;
    setUploadStep('Preparing media...');
    const [asset] = await processMediaBatch([result.assets[0]], 'quality');
    return {
      uri: asset.uri,
      type: asset.type === 'video' ? 'video' : 'image',
      base64: asset.base64,
      width: asset.width || 0,
      height: asset.height || 0,
      mimeType: asset.mimeType,
      fileName: asset.fileName,
      fileSize: asset.fileSize,
    };
  };

  const replaceMedia = async () => {
    try {
      const nextItem = await pickSingleMediaItem();
      if (!nextItem) return;
      setMedia((prev) => [nextItem, ...prev.slice(1, 6)]);
      if (nextItem.type === 'image' && nextItem.width && nextItem.height) {
        setDetectedFormat(detectFormat(nextItem.width, nextItem.height));
      }
    } catch (error) {
      console.log('Replace media error:', error);
      Alert.alert('Change failed', 'Please try choosing that media again.');
    } finally {
      setUploadStep('');
    }
  };

  useEffect(() => {
    if (media.length === 0 && !pickerOpenedRef.current) {
      pickerOpenedRef.current = true;
      void pickMedia();
    }
  }, [media.length, pickMedia]);

  const openTextOverlay = (overlay: CreatorTextOverlay) => {
    setSelectedTextId(overlay.id);
    setOverlayTextDraft(overlay);
    setTextOverlayVisible(true);
  };

  const addTextDirectly = (presetId = 'minimal_black') => {
    const preset = TEXT_STYLE_PRESETS.find((item) => item.id === presetId) || TEXT_STYLE_PRESETS[0];
    const next = createTextOverlayFromPreset(preset);
    setTextOverlays((prev) => [...prev, next].slice(-12));
    setSelectedTextId(next.id);
    setOverlayTextDraft(next);
    setTextOverlayVisible(false);
  };

  const saveTextOverlay = () => {
    const sanitized = sanitizeTextOverlay(overlayTextDraft);
    if (sanitized) {
      setTextOverlays((prev) => prev.some((item) => item.id === sanitized.id)
        ? prev.map((item) => item.id === sanitized.id ? sanitized : item)
        : [...prev, sanitized]);
      setSelectedTextId(sanitized.id);
    }
    setTextOverlayVisible(false);
  };

  const updateSelectedText = (updater: (overlay: CreatorTextOverlay) => CreatorTextOverlay | null) => {
    const activeId = selectedTextId;
    if (!activeId) return;
    setTextOverlays((prev) => prev.map((item) => {
      if (item.id !== activeId) return item;
      const updated = updater(item);
      return updated ? sanitizeTextOverlay(updated) || item : item;
    }));
  };

  const deleteSelectedText = () => {
    if (!selectedTextId) return;
    setTextOverlays((prev) => prev.filter((item) => item.id !== selectedTextId));
    setSelectedTextId('');
    setOverlayTextDraft(null);
    setTextOverlayVisible(false);
  };

  const loadTagUsers = useCallback(async (query = '') => {
    setTagUserLoading(true);
    try {
      const trimmed = query.trim();
      const response = trimmed
        ? await api.get(`/users/search/${encodeURIComponent(trimmed)}`)
        : await api.get('/discover/suggested-users');
      const people = Array.isArray(response.data) ? response.data : [];
      setTagUserResults(people.filter((person: TaggedPostUser) => person.id && person.id !== user?.id));
    } catch {
      setTagUserResults([]);
    } finally {
      setTagUserLoading(false);
    }
  }, [user?.id]);

  useEffect(() => {
    if (!tagUserVisible) return;
    const timer = setTimeout(() => {
      void loadTagUsers(tagUserQuery);
    }, 220);
    return () => clearTimeout(timer);
  }, [loadTagUsers, tagUserQuery, tagUserVisible]);

  const openTagUserPicker = () => {
    setTagUserVisible(true);
    setTagUserQuery('');
    void loadTagUsers('');
  };

  const toggleTaggedUser = (person: TaggedPostUser) => {
    if (!person.id) return;
    setTaggedUsers((prev) => {
      const next = { ...prev };
      if (next[person.id]) delete next[person.id];
      else next[person.id] = person;
      return next;
    });
  };

  const takePhoto = async () => {
    try {
      const perm = await ImagePicker.requestCameraPermissionsAsync();
      if (!perm.granted) return;
      const result = await ImagePicker.launchCameraAsync({
        quality: POST_IMAGE_PICKER_QUALITY,
        base64: true,
        mediaTypes: ['images', 'videos'],
        videoExportPreset: HD_VIDEO_EXPORT_PRESET,
        videoQuality: HD_VIDEO_QUALITY,
        videoMaxDuration: 45,
      });
      if (!result.canceled && result.assets?.[0]) {
        setUploadStep('Preparing media...');
        const [processedAsset] = await processMediaBatch([result.assets[0]], 'quality');
        const newItem = {
          uri: processedAsset.uri,
          type: processedAsset.type === 'video' ? 'video' : 'image',
          base64: processedAsset.base64,
          width: processedAsset.width || 0,
          height: processedAsset.height || 0,
          mimeType: processedAsset.mimeType,
          fileName: processedAsset.fileName,
          fileSize: processedAsset.fileSize,
        } as StudioMediaItem;
        const updated = [...media, newItem].slice(0, 6);
        setMedia(updated);

        // Auto-detect format
        if (newItem.type === 'image' && newItem.width && newItem.height && !detectedFormat) {
          setDetectedFormat(detectFormat(newItem.width, newItem.height));
        }
      }
    } catch (error) {
      console.log('Camera capture error:', error);
      Alert.alert('Camera processing failed', 'Please try again.');
    } finally {
      setUploadStep('');
    }
  };

  const openPlacePicker = () => {
    setPlaceDraftName(placeTag);
    setPlaceDraftAddress(placeAddress);
    setPlacePickerVisible(true);
  };

  const savePlaceDraft = () => {
    const cleanName = placeDraftName.trim();
    const cleanAddress = placeDraftAddress.trim();
    if (!cleanName && !cleanAddress) {
      setPlaceTag('');
      setPlaceAddress('');
      setPlacePickerVisible(false);
      return;
    }
    setPlaceTag(cleanName || cleanAddress);
    setPlaceAddress(cleanAddress);
    setPlacePickerVisible(false);
  };

  const detectLocation = async () => {
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') return;
      const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
      const [addr] = await Location.reverseGeocodeAsync({
        latitude: loc.coords.latitude,
        longitude: loc.coords.longitude,
      });
      if (addr) {
        const city = addr.city || addr.subregion || '';
        const region = addr.region || '';
        const streetParts = [addr.name, addr.street].filter(Boolean);
        const streetLine = Array.from(new Set(streetParts)).join(' ');
        const addressLine = [streetLine, city, region, addr.postalCode].filter(Boolean).join(', ');
        const parts = [city, region].filter(Boolean);
        // Also add state/area context for filtering (e.g. "Bronx, New York")
        const nycBoroughs = ['bronx', 'brooklyn', 'queens', 'manhattan', 'staten island'];
        const cityLower = city.toLowerCase();
        let tag = parts.join(', ');
        if (nycBoroughs.some(b => cityLower.includes(b)) || region.toLowerCase().includes('new york')) {
          tag = `${city}, NYC, New York`;
        }
        setPlaceDraftName(tag);
        setPlaceDraftAddress(addressLine || tag);
      }
    } catch {}
  };

  const canPost = media.length > 0;
  const primaryMedia = media[0];
  const selectedFilterPreset = CREATOR_FILTER_PRESETS.find((item) => item.id === activeFilter) || null;
  const filterData: CreatorFilterOverlay | null = filterOverlayFromPreset(selectedFilterPreset, filterIntensity);
  const selectedTextOverlay = textOverlays.find((item) => item.id === selectedTextId) || null;

  const handlePost = async () => {
    if (!canPost || isPosting) return;
    if (!requireVerifiedPhone(user, router, 'create posts')) return;
    setIsPosting(true);
    try {
      const uploadedUrls: string[] = [];
      const mediaTypes: string[] = [];
      const mediaBackupIds: string[] = [];

      for (let i = 0; i < media.length; i++) {
        const m = media[i];
        if (m.type === 'video') {
          setUploadStep(`Uploading and backing up video ${i + 1}...`);
          const uploaded = await uploadVideoWithBackup(m.uri, m.mimeType || 'video/mp4', m.fileName || `video-${i + 1}.mp4`, m.fileSize);
          if (uploaded?.url) {
            uploadedUrls.push(uploaded.url);
            mediaTypes.push('video');
            if (uploaded.backupId) mediaBackupIds.push(uploaded.backupId);
          }
        } else if (m.base64) {
          setUploadStep(`Uploading and backing up image ${i + 1}...`);
          const b64 = m.base64.startsWith('data:') ? m.base64 : `data:image/jpeg;base64,${m.base64}`;
          const uploaded = await uploadImageWithBackup(b64, m.fileName || `image-${i + 1}.jpg`);
          if (uploaded.url) {
            uploadedUrls.push(uploaded.url);
            mediaTypes.push('image');
            if (uploaded.backupId) mediaBackupIds.push(uploaded.backupId);
          }
        }
      }

      if (uploadedUrls.length === 0) {
        Alert.alert('Upload failed', 'Could not upload media');
        setIsPosting(false);
        return;
      }

      setUploadStep('Creating post...');
      const finalFormat = format === 'auto' ? (detectedFormat || '1:1') : format;
      const mediaDimensions = media.map((item) => {
        const width = Math.max(0, Math.round(Number(item.width || 0)));
        const height = Math.max(0, Math.round(Number(item.height || 0)));
        return {
          width,
          height,
          ratio: width > 0 && height > 0 ? Number((width / height).toFixed(4)) : 0,
          format: detectFormat(width, height),
          type: item.type,
        };
      });
      // Creator editor data is saved as typed JSON records in posts.editor_overlays.
      const editorOverlays = buildCreatorEditorOverlays(filterData, textOverlays);
      const taggedUserPayload = taggedUserList.map((person) => ({
        id: person.id,
        username: person.username || '',
        full_name: person.full_name || '',
        profile_image: person.profile_image || '',
      }));
      const postPayload = {
        client_request_id: `post_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`,
        title: headline.trim(),
        content: caption || '',
        image: uploadedUrls[0],
        images: uploadedUrls,
        media_types: mediaTypes,
        media_backup_ids: mediaBackupIds,
        media_dimensions: mediaDimensions,
        editor_overlays: editorOverlays,
        post_type: category || 'general',
        category: category || '',
        format: finalFormat,
        visibility: audience,
        location: placeAddress || placeTag || '',
        place_id: placeId || '',
        place_name: placeTag || placeAddress || '',
        tagged_users: taggedUserPayload,
        audio_provider: '',
        audio_track_id: '',
        audio_title: '',
        audio_artist: '',
        audio_artwork_url: '',
        audio_stream_url: '',
        audio_start_time: 0,
        audio_duration: 0,
      };
      const response = await api.post('/posts', postPayload);
      await mirrorPostToSupabase(response.data, postPayload).catch(() => undefined);

      router.replace('/(tabs)/home' as any);
    } catch (error) {
      console.log('Post error:', error);
      if (isPhoneVerificationError(error)) {
        requireVerifiedPhone(null, router, 'create posts');
      } else {
        Alert.alert('Error', 'Failed to create post');
      }
    } finally {
      setIsPosting(false);
      setUploadStep('');
    }
  };

  const renderStudioMedia = (mode: 'editor' | 'preview' = 'editor') => {
    const previewFrameWidth = Math.min(320, SW - 56);
    const previewFrameHeight = Math.min(430, SH * 0.56);
    const frameWidth = mode === 'preview'
      ? previewFrameWidth
      : (studioFrameSize.width || SW);
    const frameHeight = mode === 'preview'
      ? previewFrameHeight
      : (studioFrameSize.height || Math.max(360, SH * 0.58));
    const textScale = mode === 'preview' ? 0.62 : 1;

    const renderCreatorFilter = () => filterData ? (
      <View pointerEvents="none" style={StyleSheet.absoluteFill}>
        <View style={[s.filterTint, { backgroundColor: filterData.tint, opacity: filterData.tintOpacity }]} />
        {filterData.fadeOpacity ? <View style={[s.filterFadeLayer, { opacity: filterData.fadeOpacity }]} /> : null}
        {filterData.vignetteOpacity ? <View style={[s.filterVignetteLayer, { opacity: filterData.vignetteOpacity }]} /> : null}
        {filterData.grainOpacity ? <View style={[s.filterGrainLayer, { opacity: filterData.grainOpacity }]} /> : null}
      </View>
    ) : null;

    const renderTextOverlay = (overlay: CreatorTextOverlay) => {
      const overlayWidth = frameWidth * overlay.width;
      const left = clamp((overlay.x * frameWidth) - overlayWidth / 2, 8, Math.max(8, frameWidth - overlayWidth - 8));
      const top = clamp((overlay.y * frameHeight) - (overlay.fontSize * textScale), 8, Math.max(8, frameHeight - 72));
      const selected = selectedTextId === overlay.id;
      return (
        <TouchableOpacity
          key={overlay.id}
          disabled={mode === 'preview'}
          activeOpacity={0.88}
          onPressIn={() => setSelectedTextId(overlay.id)}
          onPress={() => openTextOverlay(overlay)}
          style={[
            s.studioTextOverlay,
            selected && s.studioTextOverlaySelected,
            {
              width: overlayWidth,
              left,
              top,
              opacity: overlay.opacity,
              backgroundColor: overlay.background,
              borderColor: overlay.borderColor || 'transparent',
              borderRadius: overlay.radius,
              paddingHorizontal: overlay.paddingX,
              paddingVertical: overlay.paddingY,
            },
          ]}
          {...(mode === 'editor' ? textPanResponder.panHandlers : {})}
        >
          <Text
            style={[
              s.studioTextOverlayText,
              {
                color: overlay.color,
                fontSize: Math.max(10, overlay.fontSize * textScale),
                lineHeight: Math.max(13, (overlay.fontSize + 5) * textScale),
                fontWeight: overlay.fontWeight,
                textShadowColor: overlay.shadow ? 'rgba(0,0,0,0.42)' : 'transparent',
                textShadowRadius: overlay.shadow ? 8 : 0,
                textShadowOffset: overlay.shadow ? { width: 0, height: 2 } : { width: 0, height: 0 },
              },
            ]}
          >
            {overlay.text}
          </Text>
        </TouchableOpacity>
      );
    };

    return (
      <View
        style={mode === 'preview' ? s.previewMediaFrame : s.studioMediaFrame}
        onLayout={mode === 'editor' ? (event) => {
          const { width, height } = event.nativeEvent.layout;
          if (width && height && (Math.abs(width - studioFrameSize.width) > 1 || Math.abs(height - studioFrameSize.height) > 1)) {
            setStudioFrameSize({ width, height });
          }
        } : undefined}
      >
        {primaryMedia ? (
          <>
            {primaryMedia.type === 'video' ? (
              <Video
                source={{ uri: primaryMedia.uri }}
                style={s.studioMedia}
                resizeMode={ResizeMode.COVER}
                shouldPlay={mode === 'editor'}
                isLooping
                isMuted={mode === 'editor'}
                useNativeControls={mode === 'preview'}
              />
            ) : (
              <Image source={{ uri: primaryMedia.uri }} style={s.studioMedia} resizeMode="cover" />
            )}
            {renderCreatorFilter()}
            {textOverlays.map(renderTextOverlay)}
            {primaryMedia.type === 'video' ? (
              <View style={s.studioVideoBadge}>
                <Ionicons name="play" size={13} color="#111" />
                <Text style={s.studioVideoText}>Video</Text>
              </View>
            ) : null}
          </>
        ) : (
          <View style={s.studioEmptyCanvas}>
            <Ionicons name="images-outline" size={42} color="rgba(255,255,255,0.72)" />
            <Text style={s.studioEmptyTitle}>Start with a photo or video</Text>
            <View style={s.studioEmptyActions}>
              <TouchableOpacity style={s.studioEmptyButton} onPress={pickMedia}>
                <Ionicons name="images" size={18} color="#111" />
                <Text style={s.studioEmptyButtonText}>Gallery</Text>
              </TouchableOpacity>
              <TouchableOpacity style={s.studioEmptyButtonDark} onPress={takePhoto}>
                <Ionicons name="camera" size={18} color="#FFF" />
                <Text style={s.studioEmptyButtonTextDark}>Camera</Text>
              </TouchableOpacity>
            </View>
          </View>
        )}
      </View>
    );
  };

  const renderPickerFallbackScreen = () => (
    <View style={s.pickerRoot}>
      <View style={[s.pickerHeader, { paddingTop: insets.top + 2 }]}>
        <TouchableOpacity style={s.pickerIconButton} onPress={() => router.back()} activeOpacity={0.82}>
          <Ionicons name="close" size={32} color="#FFFFFF" />
        </TouchableOpacity>
        <Text style={s.pickerTitle}>Create post</Text>
        <View style={s.pickerIconButton} />
      </View>

      <View style={s.pickerBody}>
        {uploadStep ? (
          <View style={s.pickerLoading}>
            <ActivityIndicator color="#FFF93F" />
            <Text style={s.pickerLoadingText}>{uploadStep}</Text>
          </View>
        ) : null}
        <TouchableOpacity style={s.pickerCameraButton} onPress={takePhoto} activeOpacity={0.86}>
          <Ionicons name="camera" size={30} color="#FFFFFF" />
          <Text style={s.pickerCameraText}>Camera</Text>
        </TouchableOpacity>
        <TouchableOpacity style={s.pickerGalleryButton} onPress={pickMedia} activeOpacity={0.86}>
          <Text style={s.pickerGalleryText}>Open gallery</Text>
        </TouchableOpacity>
      </View>
    </View>
  );

  const renderStudioThumbnails = () => (
    <View style={s.studioThumbWrap}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.studioThumbStrip}>
        {media.map((item, index) => (
          <TouchableOpacity key={`${item.uri}-${index}`} style={[s.studioThumbTile, index === 0 && s.studioThumbTileOn]} onPress={() => index === 0 ? replaceMedia() : undefined} activeOpacity={0.84}>
            {item.type === 'video' ? (
              <Video source={{ uri: item.uri }} style={s.studioThumbMedia} resizeMode={ResizeMode.COVER} shouldPlay={false} isMuted />
            ) : (
              <Image source={{ uri: item.uri }} style={s.studioThumbMedia} resizeMode="cover" />
            )}
          </TouchableOpacity>
        ))}
        <TouchableOpacity style={s.studioAddThumb} onPress={pickMedia} activeOpacity={0.84}>
          <Ionicons name="add" size={35} color="#FFFFFF" />
        </TouchableOpacity>
      </ScrollView>
    </View>
  );

  const renderStudioToolsPanel = () => {
    if (!studioPanel) return null;
    if (studioPanel === 'filters') {
      return (
        <View style={s.creatorPanel}>
          <View style={s.panelTitleRow}>
            <Text style={s.panelTitle}>Filters</Text>
            <TouchableOpacity onPress={() => setActiveFilter('original')} style={s.panelResetBtn} activeOpacity={0.84}>
              <Text style={s.panelResetText}>Original</Text>
            </TouchableOpacity>
          </View>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.filterPresetStrip}>
            {CREATOR_FILTER_PRESETS.map((item) => {
              const active = activeFilter === item.id;
              return (
                <TouchableOpacity key={item.id} style={s.filterPresetItem} onPress={() => setActiveFilter(item.id)} activeOpacity={0.84}>
                  <View style={[s.filterPreviewThumb, active && s.filterPreviewThumbOn]}>
                    {primaryMedia?.type === 'image' ? <Image source={{ uri: primaryMedia.uri }} style={s.filterPreviewImage} resizeMode="cover" /> : null}
                    <View style={[s.filterTint, { backgroundColor: item.tint, opacity: item.tintOpacity }]} />
                  </View>
                  <Text style={[s.filterPresetName, active && s.filterPresetNameOn]} numberOfLines={1}>{item.name}</Text>
                </TouchableOpacity>
              );
            })}
          </ScrollView>
          <View style={s.intensityRow}>
            <Text style={s.intensityLabel}>Intensity</Text>
            <Text style={s.intensityValue}>{activeFilter === 'original' ? '0%' : `${filterIntensity}%`}</Text>
          </View>
          <TouchableOpacity
            style={s.intensityTrack}
            activeOpacity={0.9}
            onLayout={(event) => setIntensityTrackWidth(Math.max(1, event.nativeEvent.layout.width))}
            onPress={(event) => {
              const next = Math.round(clampEditorNumber(event.nativeEvent.locationX / intensityTrackWidth, 0, 1, 0.75) * 100);
              setFilterIntensity(next);
            }}
          >
            <View style={[s.intensityFill, { width: `${activeFilter === 'original' ? 0 : filterIntensity}%` }]} />
            <View style={[s.intensityKnob, { left: `${activeFilter === 'original' ? 0 : filterIntensity}%` }]} />
          </TouchableOpacity>
        </View>
      );
    }
    if (studioPanel === 'text') {
      return (
        <View style={s.creatorPanel}>
          <View style={s.panelTitleRow}>
            <Text style={s.panelTitle}>Text overlays</Text>
            <Text style={s.panelSubtle}>{textOverlays.length}/12</Text>
          </View>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.textPresetStrip}>
            {TEXT_STYLE_PRESETS.map((item) => (
              <TouchableOpacity key={item.id} style={s.textPresetChip} onPress={() => addTextDirectly(item.id)} activeOpacity={0.84}>
                <Text style={s.textPresetName}>{item.name}</Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
          {selectedTextOverlay ? (
            <View style={s.selectedEditorRow}>
              <TouchableOpacity style={s.miniActionBtn} onPress={() => updateSelectedText((item) => ({ ...item, fontSize: Math.max(12, item.fontSize - 2) }))}>
                <Ionicons name="remove" size={18} color="#FFF" />
              </TouchableOpacity>
              <TouchableOpacity style={s.selectedEditorMain} onPress={() => openTextOverlay(selectedTextOverlay)} activeOpacity={0.84}>
                <Text style={s.selectedEditorTitle} numberOfLines={1}>{selectedTextOverlay.text}</Text>
                <Text style={s.selectedEditorSub}>Tap to edit text, color, card, and shadow</Text>
              </TouchableOpacity>
              <TouchableOpacity style={s.miniActionBtn} onPress={() => updateSelectedText((item) => ({ ...item, fontSize: Math.min(42, item.fontSize + 2) }))}>
                <Ionicons name="add" size={18} color="#FFF" />
              </TouchableOpacity>
              <TouchableOpacity style={s.miniDangerBtn} onPress={deleteSelectedText}>
                <Ionicons name="trash-outline" size={18} color="#FFF" />
              </TouchableOpacity>
            </View>
          ) : (
            <Text style={s.panelHelp}>Choose a text style to add it, then drag it on the photo.</Text>
          )}
        </View>
      );
    }
    return (
      <View style={s.studioToolPanel}>
        {CATEGORIES.map((item) => {
          const active = category === item.id;
          return (
            <TouchableOpacity key={item.id} style={[s.studioPanelChip, active && s.studioPanelChipOn]} onPress={() => setCategory(active ? null : item.id)} activeOpacity={0.84}>
              <Ionicons name={item.icon as any} size={18} color={active ? '#111' : '#FFF'} />
              <Text style={[s.studioPanelChipText, active && s.studioPanelChipTextOn]}>{item.label}</Text>
            </TouchableOpacity>
          );
        })}
      </View>
    );
  };

  if (media.length === 0) {
    return renderPickerFallbackScreen();
  }

  return (
    <>
      <KeyboardAvoidingView style={s.studioRoot} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
        <View style={[s.studioTopBar, { paddingTop: insets.top + 2 }]}>
          <TouchableOpacity style={s.studioBackButton} onPress={() => { pickerOpenedRef.current = false; setMedia([]); }} activeOpacity={0.82}>
            <Ionicons name="chevron-back" size={32} color="#FFF" />
          </TouchableOpacity>
          <View style={s.studioTopCenterSpacer} />
          <View style={s.studioCircleGhost} />
        </View>

        {isPosting && uploadStep ? (
          <View style={s.studioProgress}>
            <ActivityIndicator size="small" color={colors.accentPrimary} />
            <Text style={s.studioProgressText}>{uploadStep}</Text>
          </View>
        ) : null}

        <View style={s.studioStage}>
          {renderStudioMedia()}
        </View>

          {renderStudioThumbnails()}

          <View style={[s.studioEditFooter, { paddingBottom: Math.max(14, insets.bottom + 8) }]}>
            <View style={s.studioEditTools}>
            <TouchableOpacity
              style={[s.studioEditTool, studioPanel === 'text' && s.studioEditToolOn]}
              onPress={() => {
                if (studioPanel !== 'text' && textOverlays.length === 0) addTextDirectly();
                setStudioPanel((panel) => panel === 'text' ? null : 'text');
              }}
            >
              <Ionicons name="text" size={24} color="#FFF" />
              <Text style={s.studioEditToolText}>Text</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[s.studioEditTool, studioPanel === 'filters' && s.studioEditToolOn]} onPress={() => setStudioPanel((panel) => panel === 'filters' ? null : 'filters')}>
              <Ionicons name="aperture" size={24} color="#FFF" />
              <Text style={s.studioEditToolText}>Filters</Text>
            </TouchableOpacity>
          </View>

          {renderStudioToolsPanel()}

          <TouchableOpacity disabled={!canPost} style={[s.studioNextButton, !canPost && s.studioDisabled]} onPress={() => setPreviewVisible(true)}>
            <Text style={s.studioNextText}>Next</Text>
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>

      <Modal visible={previewVisible} animationType="fade" onRequestClose={() => setPreviewVisible(false)}>
        <View style={[s.shareRoot, { paddingTop: insets.top + 2, paddingBottom: Math.max(18, insets.bottom + 10) }]}>
          <View style={s.shareHeader}>
            <TouchableOpacity style={s.shareBack} onPress={() => setPreviewVisible(false)}>
              <Ionicons name="chevron-back" size={32} color="#111" />
            </TouchableOpacity>
            <TouchableOpacity style={s.shareTitleButton} onPress={() => setPostPreviewVisible(true)} activeOpacity={0.84}>
              <Text style={s.shareTitle}>Preview</Text>
              <Ionicons name="eye-outline" size={18} color={colors.textHint} />
            </TouchableOpacity>
          </View>

          <ScrollView contentContainerStyle={s.shareContent} showsVerticalScrollIndicator={false}>
            <View style={s.shareMediaStrip}>
              <View style={s.shareCoverTile}>
                {primaryMedia ? (
                  primaryMedia.type === 'video' ? (
                    <Video source={{ uri: primaryMedia.uri }} style={s.shareCoverMedia} resizeMode={ResizeMode.COVER} shouldPlay={false} isMuted />
                  ) : (
                    <Image source={{ uri: primaryMedia.uri }} style={s.shareCoverMedia} resizeMode="cover" />
                  )
                ) : null}
                <View style={s.shareCoverBadge}>
                  <Text style={s.shareCoverBadgeText}>Cover</Text>
                </View>
              </View>
              <TouchableOpacity style={s.shareAddTile} onPress={pickMedia} activeOpacity={0.84}>
                <Ionicons name="add" size={36} color="#8D8D8D" />
              </TouchableOpacity>
            </View>

            <TextInput
              style={s.shareHeadlineInput}
              placeholder="Add a catchy headline"
              placeholderTextColor="#A0A0A0"
              value={headline}
              onChangeText={setHeadline}
              maxLength={80}
              allowFontScaling={false}
            />

            <TextInput
              style={s.shareCaptionInput}
              placeholder="Write caption with details to get more views."
              placeholderTextColor="#A0A0A0"
              value={caption}
              onChangeText={setCaption}
              multiline
              maxLength={500}
              allowFontScaling={false}
            />

            <View style={s.shareSpacer} />

            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.shareChipRow} keyboardShouldPersistTaps="handled">
              <TouchableOpacity style={s.shareChip} activeOpacity={0.84} onPress={openPlacePicker}>
                <Ionicons name="location-outline" size={18} color="#111" />
                <Text style={s.shareChipText}>Places</Text>
              </TouchableOpacity>
              <TouchableOpacity style={s.shareIconChip} activeOpacity={0.84} onPress={openTagUserPicker}>
                <Text style={s.shareAtText}>@</Text>
              </TouchableOpacity>
              <TouchableOpacity style={s.shareIconChip} activeOpacity={0.84} onPress={() => setCaption((text) => `${text}#`)}>
                <Text style={s.shareHashText}>#</Text>
              </TouchableOpacity>
            </ScrollView>

            {taggedUserList.length ? (
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.taggedUserRail}>
                {taggedUserList.map((person) => (
                  <TouchableOpacity key={person.id} style={s.taggedUserChip} onPress={() => toggleTaggedUser(person)} activeOpacity={0.84}>
                    <Text style={s.taggedUserChipText} numberOfLines={1}>@{person.username || person.full_name || 'user'}</Text>
                    <Ionicons name="close" size={14} color="#111" />
                  </TouchableOpacity>
                ))}
              </ScrollView>
            ) : null}

            <TouchableOpacity style={s.shareOption} onPress={openPlacePicker}>
              <Ionicons name="location-outline" size={26} color="#111" />
              <View style={s.shareOptionCopy}>
                <Text style={s.shareOptionTitle}>{placeDisplay ? 'Place added' : 'Add Location'}</Text>
                {placeDisplay ? <Text style={s.shareOptionSub} numberOfLines={1}>{placeDisplay}</Text> : null}
              </View>
              <Ionicons name="chevron-forward" size={24} color="#9A9A9A" />
            </TouchableOpacity>

            <TouchableOpacity style={s.shareOption} onPress={() => setAudienceVisible(true)}>
              <Text style={s.shareMoreDots}>...</Text>
              <View style={s.shareOptionCopy}>
                <Text style={s.shareOptionTitle}>Who can see this post</Text>
                <Text style={s.shareOptionSub}>{audienceMeta.label}</Text>
              </View>
              <Ionicons name="chevron-forward" size={24} color="#9A9A9A" />
            </TouchableOpacity>

          </ScrollView>

          {audienceVisible ? (
            <View style={s.shareAudienceOverlay}>
              <TouchableOpacity style={s.audienceDismiss} activeOpacity={1} onPress={() => setAudienceVisible(false)} />
              <View style={[s.audienceSheet, { paddingBottom: Math.max(18, insets.bottom + 10) }]}>
                <View style={s.audienceHandle} />
                <Text style={s.audienceTitle}>Who can see this post</Text>
                <Text style={s.audienceSub}>Choose the audience before you share.</Text>
                {AUDIENCE_OPTIONS.map((option) => {
                  const active = audience === option.id;
                  return (
                    <TouchableOpacity key={option.id} style={[s.audienceOption, active && s.audienceOptionOn]} onPress={() => { setAudience(option.id); setAudienceVisible(false); }}>
                      <View style={[s.audienceIcon, active && s.audienceIconOn]}>
                        <Ionicons name={option.icon as any} size={22} color={active ? '#111' : '#FFF'} />
                      </View>
                      <View style={s.audienceCopy}>
                        <Text style={s.audienceLabel}>{option.label}</Text>
                        <Text style={s.audienceOptionSub}>{option.sub}</Text>
                      </View>
                      <Ionicons name={active ? 'checkmark-circle' : 'ellipse-outline'} size={22} color={active ? colors.accentPrimary : '#8A8A8A'} />
                    </TouchableOpacity>
                  );
                })}
              </View>
            </View>
          ) : null}

          <TouchableOpacity style={[s.shareSubmitButton, (!canPost || isPosting) && s.studioDisabled]} disabled={!canPost || isPosting} onPress={handlePost}>
            {isPosting ? <ActivityIndicator color="#111" /> : <Text style={s.shareSubmitText}>Post</Text>}
          </TouchableOpacity>
        </View>
      </Modal>

      <Modal visible={postPreviewVisible} animationType="fade" onRequestClose={() => setPostPreviewVisible(false)}>
        <View style={[s.postPreviewRoot, { paddingTop: insets.top + 8, paddingBottom: Math.max(16, insets.bottom + 10) }]}>
          <View style={s.previewTopBar}>
            <TouchableOpacity style={s.previewClose} onPress={() => setPostPreviewVisible(false)} activeOpacity={0.84}>
              <Ionicons name="close" size={22} color="#FFFFFF" />
            </TouchableOpacity>
            <Text style={s.previewTitle}>Post preview</Text>
            <TouchableOpacity style={s.previewPostButton} onPress={() => setPostPreviewVisible(false)} activeOpacity={0.84}>
              <Text style={s.previewPostText}>Done</Text>
            </TouchableOpacity>
          </View>
          <View style={s.previewPhone}>
            <View style={s.previewMediaCenter}>{renderStudioMedia('preview')}</View>
            <View style={s.previewOverlay}>
              <View style={s.previewAuthorRow}>
                {user?.profile_image ? (
                  <Image source={{ uri: user.profile_image }} style={s.previewAvatar} />
                ) : (
                  <View style={s.previewAvatarFallback}>
                    <Text style={s.previewAvatarText}>{String(user?.full_name || user?.username || 'F').slice(0, 1).toUpperCase()}</Text>
                  </View>
                )}
                <View style={{ flex: 1 }}>
                  <Text style={s.previewAuthorName} numberOfLines={1}>{user?.username || user?.full_name || 'You'}</Text>
                  {placeDisplay ? <Text style={s.previewAuthorSub} numberOfLines={1}>{placeDisplay}</Text> : null}
                </View>
              </View>
              {headline.trim() ? <Text style={s.previewHeadline} numberOfLines={2}>{headline.trim()}</Text> : null}
              {caption.trim() ? <Text style={s.previewCaption} numberOfLines={4}>{caption.trim()}</Text> : null}
            </View>
          </View>
        </View>
      </Modal>

      <Modal visible={placePickerVisible} transparent animationType="slide" onRequestClose={() => setPlacePickerVisible(false)}>
        <KeyboardAvoidingView style={s.placeBackdrop} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
          <TouchableOpacity style={s.placeBackdropDismiss} activeOpacity={1} onPress={() => setPlacePickerVisible(false)} />
          <View style={[s.placeSheet, { paddingBottom: Math.max(18, insets.bottom + 12) }]}>
            <View style={s.audienceHandle} />
            <Text style={s.placeTitle}>Add place</Text>
            <Text style={s.placeSub}>Add a place name and address so it shows on your post details.</Text>
            <TextInput
              value={placeDraftName}
              onChangeText={setPlaceDraftName}
              placeholder="Place name"
              placeholderTextColor={colors.textHint}
              style={s.placeInput}
              maxLength={120}
            />
            <TextInput
              value={placeDraftAddress}
              onChangeText={setPlaceDraftAddress}
              placeholder="Address or neighborhood"
              placeholderTextColor={colors.textHint}
              style={[s.placeInput, s.placeAddressInput]}
              multiline
              maxLength={180}
            />
            <TouchableOpacity style={s.placeDetectButton} onPress={detectLocation} activeOpacity={0.84}>
              <Ionicons name="navigate-outline" size={18} color={colors.textPrimary} />
              <Text style={s.placeDetectText}>Use current location</Text>
            </TouchableOpacity>
            <View style={s.placeActions}>
              <TouchableOpacity style={s.placeCancelButton} onPress={() => setPlacePickerVisible(false)} activeOpacity={0.84}>
                <Text style={s.placeCancelText}>Cancel</Text>
              </TouchableOpacity>
              <TouchableOpacity style={s.placeSaveButton} onPress={savePlaceDraft} activeOpacity={0.84}>
                <Text style={s.placeSaveText}>Save place</Text>
              </TouchableOpacity>
            </View>
          </View>
        </KeyboardAvoidingView>
      </Modal>

      <Modal visible={textOverlayVisible} transparent animationType="fade" onRequestClose={() => setTextOverlayVisible(false)}>
        <KeyboardAvoidingView style={s.textOverlayBackdrop} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
          <TouchableOpacity style={s.textOverlayDismiss} activeOpacity={1} onPress={() => setTextOverlayVisible(false)} />
          <View style={s.textOverlaySheet}>
            <Text style={s.textOverlayTitle}>Add text</Text>
            <TextInput
              value={overlayTextDraft?.text || ''}
              onChangeText={(text) => setOverlayTextDraft((prev) => prev ? { ...prev, text } : prev)}
              placeholder="Type on your post"
              placeholderTextColor="rgba(255,255,255,0.45)"
              style={s.textOverlayInput}
              autoFocus
              multiline
              maxLength={140}
            />
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.textTypeStrip}>
              {(['title', 'subtitle', 'label', 'price', 'rating', 'note'] as CreatorTextType[]).map((type) => (
                <TouchableOpacity
                  key={type}
                  style={[s.textTypeChip, overlayTextDraft?.textType === type && s.textTypeChipOn]}
                  onPress={() => setOverlayTextDraft((prev) => prev ? { ...prev, textType: type } : prev)}
                  activeOpacity={0.84}
                >
                  <Text style={[s.textTypeChipText, overlayTextDraft?.textType === type && s.textTypeChipTextOn]}>{type}</Text>
                </TouchableOpacity>
              ))}
            </ScrollView>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.textTypeStrip}>
              {TEXT_STYLE_PRESETS.map((preset) => (
                <TouchableOpacity
                  key={preset.id}
                  style={[s.textStyleChip, overlayTextDraft?.presetId === preset.id && s.textStyleChipOn]}
                  onPress={() => setOverlayTextDraft((prev) => prev ? {
                    ...prev,
                    textType: preset.textType,
                    width: preset.width,
                    fontSize: preset.fontSize,
                    fontWeight: preset.fontWeight,
                    color: preset.color,
                    background: preset.background,
                    borderColor: preset.borderColor,
                    shadow: preset.shadow,
                    radius: preset.radius,
                    paddingX: preset.paddingX,
                    paddingY: preset.paddingY,
                    presetId: preset.id,
                  } : prev)}
                  activeOpacity={0.84}
                >
                  <Text style={[s.textStyleChipText, overlayTextDraft?.presetId === preset.id && s.textStyleChipTextOn]}>{preset.name}</Text>
                </TouchableOpacity>
              ))}
            </ScrollView>
            <View style={s.textColorRow}>
              {TEXT_COLORS.map((color) => (
                <TouchableOpacity
                  key={color}
                  style={[s.textColorSwatch, { backgroundColor: color }, overlayTextDraft?.color === color && s.textColorSwatchOn]}
                  onPress={() => setOverlayTextDraft((prev) => prev ? { ...prev, color } : prev)}
                  activeOpacity={0.84}
                />
              ))}
              <TouchableOpacity
                style={[s.shadowToggle, overlayTextDraft?.shadow && s.shadowToggleOn]}
                onPress={() => setOverlayTextDraft((prev) => prev ? { ...prev, shadow: !prev.shadow } : prev)}
                activeOpacity={0.84}
              >
                <Text style={[s.shadowToggleText, overlayTextDraft?.shadow && s.shadowToggleTextOn]}>Shadow</Text>
              </TouchableOpacity>
            </View>
            <View style={s.textOverlayActions}>
              <TouchableOpacity style={s.textOverlayCancel} onPress={deleteSelectedText}>
                <Text style={s.textOverlayCancelText}>Delete</Text>
              </TouchableOpacity>
              <TouchableOpacity style={s.textOverlayDone} onPress={saveTextOverlay}>
                <Text style={s.textOverlayDoneText}>Done</Text>
              </TouchableOpacity>
            </View>
          </View>
        </KeyboardAvoidingView>
      </Modal>

      <Modal visible={tagUserVisible} animationType="slide" onRequestClose={() => setTagUserVisible(false)}>
        <View style={[s.tagUserRoot, { paddingTop: insets.top + 2 }]}>
          <View style={s.tagUserHeader}>
            <TouchableOpacity style={s.tagUserClose} onPress={() => setTagUserVisible(false)} activeOpacity={0.84}>
              <Ionicons name="chevron-back" size={30} color="#111" />
            </TouchableOpacity>
            <Text style={s.tagUserTitle}>Tag people</Text>
            <TouchableOpacity style={s.tagUserDone} onPress={() => setTagUserVisible(false)} activeOpacity={0.84}>
              <Text style={s.tagUserDoneText}>Done</Text>
            </TouchableOpacity>
          </View>
          <View style={s.tagUserSearchWrap}>
            <Ionicons name="search" size={18} color="#777" />
            <TextInput
              value={tagUserQuery}
              onChangeText={setTagUserQuery}
              placeholder="Search people"
              placeholderTextColor="#9A9A9A"
              style={s.tagUserSearchInput}
              autoCapitalize="none"
            />
          </View>
          {taggedUserList.length ? (
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.tagUserSelectedRail}>
              {taggedUserList.map((person) => (
                <TouchableOpacity key={person.id} style={s.tagUserSelectedChip} onPress={() => toggleTaggedUser(person)} activeOpacity={0.84}>
                  <Text style={s.tagUserSelectedText} numberOfLines={1}>{person.full_name || person.username}</Text>
                  <Ionicons name="close" size={14} color="#111" />
                </TouchableOpacity>
              ))}
            </ScrollView>
          ) : null}
          {tagUserLoading ? (
            <View style={s.tagUserLoading}>
              <ActivityIndicator color="#111" />
            </View>
          ) : (
            <ScrollView style={s.tagUserList} showsVerticalScrollIndicator={false} keyboardShouldPersistTaps="handled">
              {tagUserResults.map((person) => {
                const selected = !!taggedUsers[person.id];
                return (
                  <TouchableOpacity key={person.id} style={s.tagUserRow} onPress={() => toggleTaggedUser(person)} activeOpacity={0.84}>
                    {person.profile_image ? (
                      <Image source={{ uri: person.profile_image }} style={s.tagUserAvatar} />
                    ) : (
                      <View style={s.tagUserAvatarFallback}>
                        <Text style={s.tagUserAvatarText}>{String(person.full_name || person.username || 'F').slice(0, 1).toUpperCase()}</Text>
                      </View>
                    )}
                    <View style={s.tagUserInfo}>
                      <Text style={s.tagUserName} numberOfLines={1}>{person.full_name || person.username}</Text>
                      <Text style={s.tagUserHandle} numberOfLines={1}>@{person.username || 'flames'}</Text>
                    </View>
                    <View style={[s.tagUserPick, selected && s.tagUserPickOn]}>
                      {selected ? <Ionicons name="checkmark" size={17} color="#111" /> : null}
                    </View>
                  </TouchableOpacity>
                );
              })}
              {!tagUserResults.length ? <Text style={s.tagUserEmpty}>No people found</Text> : null}
            </ScrollView>
          )}
          <View style={{ height: Math.max(insets.bottom, 14) }} />
        </View>
      </Modal>

      <Modal visible={audienceVisible && !previewVisible} transparent animationType="slide" onRequestClose={() => setAudienceVisible(false)}>
        <View style={s.audienceBackdrop}>
          <TouchableOpacity style={s.audienceDismiss} activeOpacity={1} onPress={() => setAudienceVisible(false)} />
          <View style={[s.audienceSheet, { paddingBottom: Math.max(18, insets.bottom + 10) }]}>
            <View style={s.audienceHandle} />
            <Text style={s.audienceTitle}>Choose audience</Text>
            <Text style={s.audienceSub}>Control who can see this post after you share it.</Text>
            {AUDIENCE_OPTIONS.map((option) => {
              const active = audience === option.id;
              return (
                <TouchableOpacity key={option.id} style={[s.audienceOption, active && s.audienceOptionOn]} onPress={() => { setAudience(option.id); setAudienceVisible(false); }}>
                  <View style={[s.audienceIcon, active && s.audienceIconOn]}>
                    <Ionicons name={option.icon as any} size={22} color={active ? '#111' : '#FFF'} />
                  </View>
                  <View style={s.audienceCopy}>
                    <Text style={s.audienceLabel}>{option.label}</Text>
                    <Text style={s.audienceOptionSub}>{option.sub}</Text>
                  </View>
                  <Ionicons name={active ? 'checkmark-circle' : 'ellipse-outline'} size={22} color={active ? colors.accentPrimary : '#8A8A8A'} />
                </TouchableOpacity>
              );
            })}
          </View>
        </View>
      </Modal>

    </>
  );

}
const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bgApp },
  pickerRoot: { flex: 1, backgroundColor: '#000000' },
  pickerHeader: {
    minHeight: 58,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
  },
  pickerIconButton: { width: layout.iconButton, height: layout.iconButton, alignItems: 'center', justifyContent: 'center' },
  pickerTitle: { color: '#FFFFFF', fontSize: 17, lineHeight: 22, fontWeight: '500' },
  pickerBody: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: spacing.gutter, paddingHorizontal: spacing.lg },
  pickerLoading: { alignItems: 'center', justifyContent: 'center', gap: 10, marginBottom: 8 },
  pickerLoadingText: { color: '#FFFFFF', fontSize: 14, lineHeight: 18, fontWeight: '500' },
  pickerCameraButton: {
    width: '100%',
    maxWidth: 260,
    height: 48,
    borderRadius: borderRadius.md,
    backgroundColor: '#191919',
    borderWidth: 1,
    borderColor: '#2B2B2B',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  pickerCameraText: { color: '#FFFFFF', fontSize: 16, lineHeight: 20, fontWeight: '500' },
  pickerGalleryButton: {
    minWidth: 156,
    minHeight: 40,
    borderRadius: 20,
    backgroundColor: colors.accentPrimary,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 18,
  },
  pickerGalleryText: { color: colors.textInverse, fontSize: 13, lineHeight: 17, fontWeight: '500' },
  studioRoot: { flex: 1, backgroundColor: '#070806' },
  studioTopBar: {
    minHeight: 54, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: spacing.md, zIndex: 20,
  },
  studioBackButton: { width: layout.iconButton, height: layout.iconButton, alignItems: 'flex-start', justifyContent: 'center' },
  studioTopCenterSpacer: { flex: 1 },
  studioCircle: {
    width: 42, height: 42, borderRadius: 21, backgroundColor: 'rgba(255,255,255,0.14)',
    alignItems: 'center', justifyContent: 'center',
  },
  studioCircleGhost: { width: 40, height: 40 },
  studioTopSound: {
    flex: 1, maxWidth: 188, minHeight: 38, borderRadius: 19, backgroundColor: 'rgba(255,255,255,0.10)',
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)', flexDirection: 'row', alignItems: 'center',
    gap: 6, paddingHorizontal: 8,
  },
  studioTopSoundArt: { width: 24, height: 24, borderRadius: 7, backgroundColor: '#333' },
  studioTopSoundArtFallback: { width: 24, height: 24, borderRadius: 7, backgroundColor: 'rgba(255,255,255,0.13)', alignItems: 'center', justifyContent: 'center' },
  studioTopSoundCopy: { flex: 1, minWidth: 0 },
  studioTopSoundTitle: { color: '#FFF', fontSize: 12, lineHeight: 14, fontWeight: '500' },
  studioTopSoundSub: { color: 'rgba(255,255,255,0.55)', fontSize: 9, lineHeight: 11, fontWeight: '600', marginTop: 1 },
  studioTopSoundPlus: { width: 24, height: 24, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.13)', alignItems: 'center', justifyContent: 'center' },
  studioUndoGroup: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  studioSmallCircle: {
    width: 36, height: 36, borderRadius: 18, backgroundColor: 'rgba(255,255,255,0.14)',
    alignItems: 'center', justifyContent: 'center',
  },
  studioSmallCircleDisabled: { opacity: 0.36 },
  studioTitleWrap: { flex: 1, minWidth: 0, alignItems: 'center' },
  studioTitle: { color: '#FFFFFF', fontSize: 17, lineHeight: 21, fontWeight: '500' },
  studioSubtitle: { color: 'rgba(255,255,255,0.56)', fontSize: 11, lineHeight: 14, fontWeight: '600', marginTop: 1 },
  studioTopActions: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  studioPreviewButton: {
    height: 38, borderRadius: 19, backgroundColor: '#FFFFFF', flexDirection: 'row',
    alignItems: 'center', gap: 6, paddingHorizontal: 13,
  },
  studioPreviewText: { color: colors.textPrimary, fontSize: 12, fontWeight: '500' },
  studioPostButton: {
    minWidth: 58, height: 36, borderRadius: 18, backgroundColor: colors.accentPrimary,
    borderWidth: 1, borderColor: colors.accentPrimaryHover, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 14,
  },
  studioPostText: { color: colors.textInverse, fontSize: 13, fontWeight: '500' },
  studioShareButton: {
    minWidth: 68, height: 36, borderRadius: 18, backgroundColor: colors.accentPrimary,
    borderWidth: 1, borderColor: colors.accentPrimaryHover, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 14,
  },
  studioShareText: { color: colors.textInverse, fontSize: 13, fontWeight: '500' },
  studioDisabled: { opacity: 0.4 },
  studioProgress: {
    marginHorizontal: 14, minHeight: 38, borderRadius: 19, backgroundColor: 'rgba(223,255,50,0.12)',
    borderWidth: 1, borderColor: 'rgba(223,255,50,0.24)', flexDirection: 'row', alignItems: 'center',
    gap: 8, paddingHorizontal: 12,
  },
  studioProgressText: { color: '#FFFFFF', fontSize: 12, fontWeight: '600' },
  studioStage: { flex: 1, minHeight: 230, justifyContent: 'center', position: 'relative' },
  studioMediaFrame: {
    width: '100%',
    height: Math.min(SH * 0.66, SW * 1.333),
    overflow: 'hidden',
    backgroundColor: '#11120F',
    position: 'relative',
  },
  studioMedia: { width: '100%', height: '100%' },
  studioTextOverlay: {
    position: 'absolute', alignItems: 'center', borderWidth: 1, zIndex: 12,
  },
  studioTextOverlaySelected: { borderColor: '#FFF93F' },
  studioTextOverlayText: {
    color: '#FFFFFF', fontSize: 28, lineHeight: 34, fontWeight: '500', textAlign: 'center',
  },
  filterTint: { ...StyleSheet.absoluteFillObject },
  filterFadeLayer: { ...StyleSheet.absoluteFillObject, backgroundColor: '#F7F1E8' },
  filterVignetteLayer: {
    ...StyleSheet.absoluteFillObject,
    borderWidth: 34,
    borderColor: 'rgba(0,0,0,0.72)',
  },
  filterGrainLayer: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(255,255,255,0.34)',
  },  studioVideoBadge: {
    position: 'absolute', left: 12, top: 12, minHeight: 30, borderRadius: 15,
    backgroundColor: 'rgba(255,255,255,0.86)', flexDirection: 'row', alignItems: 'center',
    gap: 5, paddingHorizontal: 10,
  },
  studioVideoText: { color: '#111', fontSize: 12, fontWeight: '500' },
  studioEmptyCanvas: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 14, padding: 24 },
  studioEmptyTitle: { color: '#FFF', fontSize: 17, fontWeight: '500' },
  studioEmptyActions: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  studioEmptyButton: {
    minHeight: 40, borderRadius: 20, backgroundColor: colors.accentPrimary, borderWidth: 1, borderColor: colors.accentPrimaryHover,
    flexDirection: 'row', alignItems: 'center', gap: 7, paddingHorizontal: 15,
  },
  studioEmptyButtonDark: {
    height: 42, borderRadius: 21, backgroundColor: 'rgba(255,255,255,0.14)', borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.18)', flexDirection: 'row', alignItems: 'center', gap: 7, paddingHorizontal: 15,
  },
  studioEmptyButtonText: { color: colors.textInverse, fontSize: 13, fontWeight: '500' },
  studioEmptyButtonTextDark: { color: '#FFF', fontSize: 13, fontWeight: '500' },
  studioSoundPill: {
    position: 'absolute', left: 14, bottom: 14, right: 84, minHeight: 42, borderRadius: 21,
    backgroundColor: 'rgba(255,255,255,0.86)', flexDirection: 'row', alignItems: 'center',
    gap: 7, paddingHorizontal: 10,
  },
  studioSoundArt: { width: 28, height: 28, borderRadius: 14, backgroundColor: '#DDD' },
  studioSoundText: { flex: 1, minWidth: 0, color: '#111', fontSize: 12, fontWeight: '500' },
  studioPanel: {
    backgroundColor: '#141512', borderTopLeftRadius: borderRadius.sheet, borderTopRightRadius: borderRadius.sheet,
    paddingTop: 10, paddingHorizontal: spacing.gutter, gap: spacing.gutter,
  },
  studioPanelHandle: { alignSelf: 'center', width: 42, height: 4, borderRadius: 4, backgroundColor: 'rgba(255,255,255,0.24)', marginBottom: 2 },
  studioToolRail: { position: 'absolute', right: 12, top: 18, gap: 12, zIndex: 15 },
  studioToolRailButton: {
    width: 52, minHeight: 52, borderRadius: 17, backgroundColor: 'rgba(0,0,0,0.42)',
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.16)', alignItems: 'center', justifyContent: 'center', gap: 4,
  },
  studioToolRailText: { color: '#FFFFFF', fontSize: 10, lineHeight: 12, fontWeight: '500' },
  studioComposerRow: {
    minHeight: 70, borderRadius: 22, backgroundColor: 'rgba(255,255,255,0.08)',
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.10)', flexDirection: 'row', alignItems: 'flex-start',
    gap: 10, paddingHorizontal: 11, paddingVertical: 10,
  },
  studioComposerAvatar: { width: 36, height: 36, borderRadius: 18, backgroundColor: '#333' },
  studioComposerAvatarFallback: {
    width: 36, height: 36, borderRadius: 18, backgroundColor: colors.accentPrimaryLight,
    borderWidth: 1, borderColor: colors.borderSubtle, alignItems: 'center', justifyContent: 'center',
  },
  studioComposerAvatarText: { color: '#111', fontSize: 15, fontWeight: '500' },
  studioComposerInput: {
    flex: 1, minHeight: 48, maxHeight: 94, color: '#FFFFFF', fontSize: 14,
    lineHeight: 19, fontWeight: '500', padding: 0, textAlignVertical: 'top',
  },
  studioEditFooter: {
    backgroundColor: '#070806',
    paddingTop: spacing.sm,
    paddingHorizontal: spacing.gutter,
    gap: spacing.sm,
  },
  studioEditTools: { minHeight: 52, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: spacing.sm },
  studioEditTool: {
    flex: 1,
    minWidth: 54,
    minHeight: layout.minTouchTarget,
    borderRadius: borderRadius.md,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 3,
  },
  studioEditToolOn: { backgroundColor: 'rgba(255,255,255,0.09)' },
  studioEditToolText: { color: '#FFFFFF', fontSize: 10, lineHeight: 12, fontWeight: '500', textAlign: 'center' },
  studioEditPanel: {
    borderRadius: borderRadius.xl, backgroundColor: '#161915', borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    padding: spacing.gutter, gap: spacing.gutter,
  },
  studioEditPanelHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  studioEditPanelTitle: { color: '#FFFFFF', fontSize: 15, fontWeight: '500' },
  studioEditPanelClose: { width: 30, height: 30, borderRadius: 15, backgroundColor: 'rgba(255,255,255,0.08)', alignItems: 'center', justifyContent: 'center' },
  studioEditModeRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  studioEditModeChip: {
    flex: 1, minHeight: layout.minTouchTarget, borderRadius: 22, backgroundColor: '#242720',
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 7,
  },
  studioEditModeChipOn: { backgroundColor: colors.accentPrimary },
  studioEditModeText: { color: '#FFFFFF', fontSize: 13, fontWeight: '500' },
  studioEditModeTextOn: { color: '#FFFFFF' },
  studioClipRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  studioClipChip: {
    height: 32, borderRadius: 16, backgroundColor: '#202024', borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)', justifyContent: 'center', paddingHorizontal: 13,
  },
  studioClipChipOn: { backgroundColor: '#4B5CF6', borderColor: '#4B5CF6' },
  studioClipText: { color: 'rgba(255,255,255,0.72)', fontSize: 12, fontWeight: '500' },
  studioClipTextOn: { color: '#FFFFFF' },
  studioNextButton: {
    width: '100%',
    height: 46,
    borderRadius: 23,
    backgroundColor: colors.accentPrimary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  studioNextText: { color: colors.textInverse, fontSize: 15, lineHeight: 19, fontWeight: '500' },
  studioThumbWrap: { minHeight: 50, alignItems: 'center', justifyContent: 'center' },
  studioThumbStrip: { alignItems: 'center', gap: 8, paddingHorizontal: 12 },
  studioThumbTile: {
    width: 42,
    height: 42,
    borderRadius: 7,
    overflow: 'hidden',
    backgroundColor: '#202020',
    borderWidth: 1.5,
    borderColor: 'transparent',
  },
  studioThumbTileOn: { borderColor: '#FFFFFF' },
  studioThumbMedia: { width: '100%', height: '100%' },
  studioAddThumb: {
    width: 42,
    height: 42,
    borderRadius: 7,
    backgroundColor: '#2A2A2A',
    alignItems: 'center',
    justifyContent: 'center',
  },
  studioToolPanel: { minHeight: 44, flexDirection: 'row', alignItems: 'center', gap: 8 },
  creatorPanel: {
    borderRadius: borderRadius.lg,
    backgroundColor: '#11130F',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)',
    padding: spacing.sm,
    gap: spacing.sm,
  },
  panelTitleRow: { minHeight: 22, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 8 },
  panelTitle: { color: '#FFFFFF', fontSize: 12, fontWeight: '500' },
  panelSubtle: { color: 'rgba(255,255,255,0.54)', fontSize: 10, fontWeight: '600' },
  panelHelp: { color: 'rgba(255,255,255,0.58)', fontSize: 11, lineHeight: 15, fontWeight: '500' },
  panelResetBtn: { height: 24, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.10)', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 9 },
  panelResetText: { color: '#FFFFFF', fontSize: 10, fontWeight: '500' },
  filterPresetStrip: { gap: 7, paddingRight: 6 },
  filterPresetItem: { width: 54, gap: 4, alignItems: 'center' },
  filterPreviewThumb: { width: 50, height: 60, borderRadius: 8, overflow: 'hidden', backgroundColor: '#2A2A2A', borderWidth: 1.2, borderColor: 'transparent' },
  filterPreviewThumbOn: { borderColor: colors.accentPrimary },
  filterPreviewImage: { width: '100%', height: '100%' },
  filterPresetName: { color: 'rgba(255,255,255,0.62)', fontSize: 9, fontWeight: '600', textAlign: 'center' },
  filterPresetNameOn: { color: '#FFFFFF' },
  intensityRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  intensityLabel: { color: '#FFFFFF', fontSize: 11, fontWeight: '500' },
  intensityValue: { color: '#FFFFFF', fontSize: 11, fontWeight: '500' },
  intensityTrack: { height: 22, borderRadius: 11, backgroundColor: 'rgba(255,255,255,0.12)', justifyContent: 'center', overflow: 'hidden' },
  intensityFill: { position: 'absolute', left: 0, top: 0, bottom: 0, backgroundColor: colors.accentPrimary },
  intensityKnob: { position: 'absolute', width: 14, height: 14, borderRadius: 7, backgroundColor: '#FFFFFF', borderWidth: 1.2, borderColor: colors.textPrimary, marginLeft: -7 },
  textPresetStrip: { gap: 7, paddingRight: 6 },
  textPresetChip: { minHeight: 28, borderRadius: 14, backgroundColor: 'rgba(255,255,255,0.10)', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 10 },
  textPresetName: { color: '#FFFFFF', fontSize: 10, fontWeight: '500' },
  selectedEditorRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  selectedEditorMain: { flex: 1, minHeight: 38, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.08)', justifyContent: 'center', paddingHorizontal: 10 },
  selectedEditorTitle: { color: '#FFFFFF', fontSize: 12, fontWeight: '500' },
  selectedEditorSub: { color: 'rgba(255,255,255,0.54)', fontSize: 9, fontWeight: '500', marginTop: 1 },
  miniActionBtn: { width: 30, height: 30, borderRadius: 15, backgroundColor: 'rgba(255,255,255,0.12)', alignItems: 'center', justifyContent: 'center' },
  miniDangerBtn: { width: 30, height: 30, borderRadius: 15, backgroundColor: '#B42318', alignItems: 'center', justifyContent: 'center' },  studioPanelChip: {
    minHeight: layout.minTouchTarget,
    borderRadius: 22,
    backgroundColor: '#1F1F1F',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.10)',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingHorizontal: 12,
  },
  studioPanelChipOn: { backgroundColor: colors.accentPrimary, borderColor: colors.accentPrimaryHover },
  studioPanelChipText: { color: '#FFFFFF', fontSize: 12, lineHeight: 16, fontWeight: '500' },
  studioPanelChipTextOn: { color: colors.textInverse },
  filterDot: { width: 16, height: 16, borderRadius: 8, borderWidth: 1, borderColor: 'rgba(0,0,0,0.18)' },
  studioFilterTabs: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  studioFilterTab: { height: 36, borderRadius: 18, backgroundColor: 'rgba(0,0,0,0.28)', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 14 },
  studioFilterTabOn: { height: 36, borderRadius: 18, backgroundColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 16 },
  studioFilterTabText: { color: '#FFFFFF', fontSize: 12, fontWeight: '500', textTransform: 'uppercase' },
  studioFilterTabTextOn: { color: '#111111', fontSize: 12, fontWeight: '500', textTransform: 'uppercase' },
  studioFilterStrip: { gap: 9, paddingRight: 12 },
  filterItem: { width: 58, alignItems: 'center', gap: 5 },
  filterThumb: { width: 56, height: 68, borderRadius: 10, overflow: 'hidden', backgroundColor: '#111', borderWidth: 1.5, borderColor: 'transparent' },
  filterThumbOn: { borderColor: '#FFFFFF' },
  filterThumbImage: { width: '100%', height: '100%' },
  filterThumbFallback: { flex: 1, backgroundColor: '#333' },
  filterAddThumb: {
    width: 56, height: 68, borderRadius: 10, borderWidth: 1.5, borderColor: 'rgba(255,255,255,0.22)',
    borderStyle: 'dashed', alignItems: 'center', justifyContent: 'center',
  },
  filterName: { color: 'rgba(255,255,255,0.56)', fontSize: 11, fontWeight: '600' },
  filterNameOn: { color: '#FFFFFF' },
  studioQuickRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  studioQuickChip: {
    flex: 1, minHeight: 38, borderRadius: 19, backgroundColor: '#FFFFFF',
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, paddingHorizontal: 9,
  },
  studioQuickText: { color: '#111', fontSize: 12, fontWeight: '500' },
  simpleStudioActions: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  simpleStudioAction: {
    flex: 1, minHeight: 46, borderRadius: 23, backgroundColor: '#FFFFFF',
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 7,
    paddingHorizontal: 12,
  },
  simpleStudioActionText: { color: '#111', fontSize: 13, fontWeight: '500' },
  studioCaptionInput: {
    minHeight: 48, maxHeight: 74, borderRadius: 18, backgroundColor: 'rgba(255,255,255,0.08)',
    color: '#FFFFFF', fontSize: 14, lineHeight: 19, fontWeight: '500', paddingHorizontal: 13, paddingVertical: 10,
    textAlignVertical: 'top',
  },
  studioCategoryRow: { gap: 8, paddingRight: 12 },
  studioCategoryChip: {
    minHeight: 34, borderRadius: 17, backgroundColor: 'rgba(255,255,255,0.08)', flexDirection: 'row',
    alignItems: 'center', gap: 5, paddingHorizontal: 11,
  },
  studioCategoryText: { color: '#FFF', fontSize: 12, fontWeight: '600' },
  studioCategoryTextOn: { color: '#FFF' },
  studioDurationRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  studioDurationChip: {
    height: 32, borderRadius: 16, backgroundColor: 'rgba(255,255,255,0.09)',
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: 13,
  },
  studioDurationChipOn: { backgroundColor: colors.accentPrimary },
  studioDurationText: { color: '#FFF', fontSize: 12, fontWeight: '500' },
  studioDurationTextOn: { color: '#FFF' },
  studioToolBar: { minHeight: 42, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-around' },
  studioTool: { width: 44, height: 38, borderRadius: 18, alignItems: 'center', justifyContent: 'center' },
  studioToolOn: { backgroundColor: 'rgba(255,255,255,0.12)' },
  simpleStudioFooter: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  simpleFooterButton: {
    flex: 1, minHeight: 48, borderRadius: 24, backgroundColor: 'rgba(255,255,255,0.10)',
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.16)',
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8,
  },
  simpleFooterButtonText: { color: '#FFF', fontSize: 14, fontWeight: '500' },
  simpleFooterPost: {
    flex: 1, minHeight: 44, borderRadius: 22, backgroundColor: colors.accentPrimary,
    borderWidth: 1, borderColor: colors.accentPrimaryHover, alignItems: 'center', justifyContent: 'center',
  },
  simpleFooterPostText: { color: '#FFF', fontSize: 14, fontWeight: '500' },
  postPreviewRoot: { flex: 1, backgroundColor: '#050505', paddingHorizontal: 16, gap: 14 },
  previewTopBar: { minHeight: 48, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  previewClose: { width: 42, height: 42, borderRadius: 21, backgroundColor: 'rgba(255,255,255,0.12)', alignItems: 'center', justifyContent: 'center' },
  previewTitle: { color: '#FFFFFF', fontSize: 17, fontWeight: '500' },
  previewPostButton: { height: 36, borderRadius: 18, backgroundColor: colors.accentPrimary, borderWidth: 1, borderColor: colors.accentPrimaryHover, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 14 },
  previewPostText: { color: '#FFF', fontSize: 13, fontWeight: '500' },
  previewPhone: { flex: 1, borderRadius: 30, overflow: 'hidden', backgroundColor: '#111', position: 'relative' },
  previewMediaCenter: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingBottom: 112 },
  previewMediaFrame: {
    width: Math.min(320, SW - 56),
    height: Math.min(430, SH * 0.56),
    borderRadius: 24,
    overflow: 'hidden',
    backgroundColor: '#111',
    position: 'relative',
  },
  previewOverlay: { position: 'absolute', left: 16, right: 16, bottom: 18, gap: 10 },
  previewAuthorRow: { flexDirection: 'row', alignItems: 'center', gap: 9 },
  previewAvatar: { width: 42, height: 42, borderRadius: 21 },
  previewAvatarFallback: { width: 42, height: 42, borderRadius: 21, backgroundColor: colors.accentPrimaryLight, borderWidth: 1, borderColor: colors.borderSubtle, alignItems: 'center', justifyContent: 'center' },
  previewAvatarText: { color: colors.textPrimary, fontSize: 18, fontWeight: '500' },
  previewAuthorName: { color: '#FFF', fontSize: 16, fontWeight: '500' },
  previewAuthorSub: { color: 'rgba(255,255,255,0.72)', fontSize: 12, fontWeight: '500' },
  previewHeadline: { color: '#FFFFFF', fontSize: 20, lineHeight: 25, fontWeight: '700' },
  previewCaption: { color: '#FFF', fontSize: 14, lineHeight: 19, fontWeight: '500' },
  previewSoundBar: { minHeight: 38, borderRadius: 19, backgroundColor: 'rgba(255,255,255,0.86)', flexDirection: 'row', alignItems: 'center', gap: 7, paddingHorizontal: 11 },
  previewSoundText: { flex: 1, color: '#111', fontSize: 12, fontWeight: '500' },
  previewEditButton: { height: 48, borderRadius: 24, backgroundColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center' },
  previewEditText: { color: '#111', fontSize: 14, fontWeight: '500' },
  shareRoot: { flex: 1, backgroundColor: colors.bgCard },
  shareHeader: {
    minHeight: 58,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 18,
  },
  shareBack: { width: layout.iconButton, height: layout.iconButton, alignItems: 'flex-start', justifyContent: 'center' },
  shareTitleButton: { minHeight: 44, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, paddingHorizontal: 8 },
  shareTitle: { color: colors.textPrimary, fontSize: 19, lineHeight: 25, fontWeight: '600' },
  shareContent: { minHeight: SH - 140, paddingHorizontal: spacing.md, paddingTop: spacing.md, paddingBottom: 108 },
  shareMediaStrip: { flexDirection: 'row', alignItems: 'center', gap: spacing.gutter, marginBottom: spacing.lg },
  shareCoverTile: {
    width: 88,
    height: 88,
    borderRadius: borderRadius.md,
    overflow: 'hidden',
    backgroundColor: colors.bgSubtle,
    position: 'relative',
  },
  shareCoverMedia: { width: '100%', height: '100%' },
  shareCoverBadge: {
    position: 'absolute',
    left: 8,
    bottom: 8,
    borderRadius: 5,
    backgroundColor: 'rgba(0,0,0,0.58)',
    paddingHorizontal: 7,
    paddingVertical: 3,
  },
  shareCoverBadgeText: { color: '#FFFFFF', fontSize: 14, lineHeight: 18, fontWeight: '600' },
  shareAddTile: {
    width: 88,
    height: 88,
    borderRadius: borderRadius.md,
    backgroundColor: colors.bgSubtle,
    alignItems: 'center',
    justifyContent: 'center',
  },
  shareHeadlineInput: {
    minHeight: 48,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.borderSubtle,
    color: colors.textPrimary,
    fontSize: 20,
    lineHeight: 26,
    fontWeight: '600',
    paddingVertical: spacing.sm,
  },
  shareCaptionInput: {
    minHeight: 112,
    color: colors.textPrimary,
    fontSize: 15,
    lineHeight: 22,
    fontWeight: '400',
    textAlignVertical: 'top',
    paddingTop: spacing.gutter,
    paddingBottom: spacing.gutter,
  },
  shareSpacer: { flexGrow: 1, minHeight: Math.max(120, SH * 0.14) },
  shareChipRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingBottom: spacing.gutter,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.borderSubtle,
  },
  shareChip: {
    minHeight: layout.minTouchTarget,
    borderRadius: borderRadius.md,
    backgroundColor: colors.bgSubtle,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: spacing.gutter,
  },
  shareChipText: { color: colors.textPrimary, fontSize: 14, lineHeight: 18, fontWeight: '500' },
  shareIconChip: {
    width: 44,
    minHeight: layout.minTouchTarget,
    borderRadius: borderRadius.md,
    backgroundColor: colors.bgSubtle,
    alignItems: 'center',
    justifyContent: 'center',
  },
  shareAtText: { color: colors.textPrimary, fontSize: 22, lineHeight: 27, fontWeight: '600' },
  shareHashText: { color: colors.textPrimary, fontSize: 23, lineHeight: 28, fontWeight: '600' },
  taggedUserRail: { gap: 8, paddingTop: 10, paddingBottom: 2 },
  taggedUserChip: {
    height: 30,
    borderRadius: 15,
    backgroundColor: colors.accentPrimary,
    borderWidth: 1,
    borderColor: colors.accentPrimaryHover,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    paddingHorizontal: 10,
  },
  taggedUserChipText: { maxWidth: 130, color: colors.textInverse, fontSize: 12, lineHeight: 15, fontWeight: '500' },
  sharePillRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 20, paddingBottom: 22 },
  shareMiniPill: {
    minHeight: 44, borderRadius: 15, backgroundColor: '#F1F2F6', flexDirection: 'row',
    alignItems: 'center', gap: 8, paddingHorizontal: 14,
  },
  shareMiniText: { color: '#111', fontSize: 18, fontWeight: '500' },
  shareOption: {
    minHeight: 60,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.borderSubtle,
  },
  shareOptionCopy: { flex: 1, minWidth: 0 },
  shareOptionTitle: { color: colors.textPrimary, fontSize: 16, lineHeight: 21, fontWeight: '500' },
  shareOptionSub: { color: colors.textHint, fontSize: 12, lineHeight: 16, fontWeight: '500', marginTop: 1 },
  shareMoreDots: { width: 34, color: colors.textPrimary, fontSize: 24, lineHeight: 24, fontWeight: '500' },
  shareValue: { color: colors.textHint, fontSize: 16, fontWeight: '500' },
  shareDivider: { height: 12, backgroundColor: colors.bgSubtle, marginTop: 4 },
  shareSwitch: { width: 62, height: 38, borderRadius: 19, backgroundColor: '#686D78' },
  placeBackdrop: { flex: 1, justifyContent: 'flex-end', backgroundColor: 'rgba(255,255,255,0.72)' },
  placeBackdropDismiss: { ...StyleSheet.absoluteFillObject },
  placeSheet: {
    borderTopLeftRadius: 28,
    borderTopRightRadius: 28,
    backgroundColor: colors.bgCard,
    paddingHorizontal: spacing.md,
    paddingTop: 10,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation2,
  },
  placeTitle: { color: colors.textPrimary, fontSize: 22, lineHeight: 28, fontWeight: '600', marginTop: 8 },
  placeSub: { color: colors.textHint, fontSize: 13, lineHeight: 19, fontWeight: '500', marginTop: 4, marginBottom: spacing.md },
  placeInput: {
    minHeight: 48,
    borderRadius: 16,
    backgroundColor: colors.bgSubtle,
    color: colors.textPrimary,
    fontSize: 15,
    lineHeight: 20,
    fontWeight: '500',
    paddingHorizontal: 14,
    paddingVertical: 12,
    marginBottom: spacing.sm,
  },
  placeAddressInput: { minHeight: 76, textAlignVertical: 'top' },
  placeDetectButton: {
    minHeight: 44,
    borderRadius: 22,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 7,
    marginTop: 2,
  },
  placeDetectText: { color: colors.textPrimary, fontSize: 14, fontWeight: '600' },
  placeActions: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginTop: spacing.md },
  placeCancelButton: {
    flex: 1,
    minHeight: 46,
    borderRadius: 23,
    backgroundColor: colors.bgSubtle,
    alignItems: 'center',
    justifyContent: 'center',
  },
  placeCancelText: { color: colors.textSecondary, fontSize: 14, fontWeight: '600' },
  placeSaveButton: {
    flex: 1,
    minHeight: 46,
    borderRadius: 23,
    backgroundColor: colors.accentPrimary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  placeSaveText: { color: colors.textInverse, fontSize: 14, fontWeight: '700' },
  shareSubmitButton: {
    position: 'absolute', left: spacing.md, right: spacing.md, bottom: 18, height: 48, borderRadius: 24,
    backgroundColor: colors.accentPrimary, alignItems: 'center', justifyContent: 'center',
    ...shadows.elevation1,
  },
  shareSubmitText: { color: colors.textInverse, fontSize: 16, lineHeight: 21, fontWeight: '600' },
  textOverlayBackdrop: { flex: 1, justifyContent: 'flex-end', backgroundColor: colors.modalScrim },
  textOverlayDismiss: { ...StyleSheet.absoluteFillObject },
  textOverlaySheet: {
    margin: spacing.gutter, borderRadius: borderRadius.sheet, backgroundColor: '#11130F', borderWidth: 1, borderColor: 'rgba(255,255,255,0.10)',
    padding: spacing.gutter, gap: spacing.gutter,
  },
  textOverlayTitle: { color: '#FFFFFF', fontSize: 17, lineHeight: 22, fontWeight: '500' },
  textOverlayInput: {
    minHeight: 82, borderRadius: borderRadius.lg, backgroundColor: '#1F221C', color: '#FFFFFF',
    fontSize: 17, lineHeight: 23, fontWeight: '500', paddingHorizontal: 12, paddingVertical: 10,
    textAlignVertical: 'top',
  },
  textTypeStrip: { gap: 7, paddingRight: 7 },
  textTypeChip: { height: 30, borderRadius: 15, backgroundColor: '#242832', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 10 },
  textTypeChipOn: { backgroundColor: colors.accentPrimary },
  textTypeChipText: { color: '#FFFFFF', fontSize: 11, fontWeight: '500', textTransform: 'capitalize' },
  textTypeChipTextOn: { color: '#FFFFFF' },
  textStyleChip: { minHeight: 32, borderRadius: 11, backgroundColor: '#242832', borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 10 },
  textStyleChipOn: { backgroundColor: colors.surfaceTint, borderColor: colors.accentPrimary },
  textStyleChipText: { color: '#FFFFFF', fontSize: 11, fontWeight: '500' },
  textStyleChipTextOn: { color: '#111111' },
  textColorRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  textColorSwatch: { width: 28, height: 28, borderRadius: 14, borderWidth: 2, borderColor: 'rgba(255,255,255,0.18)' },
  textColorSwatchOn: { borderColor: colors.accentPrimary },
  shadowToggle: { height: 30, borderRadius: 15, backgroundColor: '#242832', justifyContent: 'center', paddingHorizontal: 12 },
  shadowToggleOn: { backgroundColor: colors.accentPrimary },
  shadowToggleText: { color: '#FFFFFF', fontSize: 11, fontWeight: '500' },
  shadowToggleTextOn: { color: '#FFFFFF' },
  textOverlayActions: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  textOverlayCancel: {
    flex: 1, height: 42, borderRadius: 21, backgroundColor: '#242832', alignItems: 'center', justifyContent: 'center',
  },
  textOverlayCancelText: { color: '#FFFFFF', fontSize: 13, fontWeight: '500' },
  textOverlayDone: {
    flex: 1, minHeight: 40, borderRadius: 20, backgroundColor: colors.accentPrimary, borderWidth: 1, borderColor: colors.accentPrimaryHover,
    alignItems: 'center', justifyContent: 'center',
  },
  textOverlayDoneText: { color: colors.textInverse, fontSize: 13, fontWeight: '500' },
  shareAudienceOverlay: { ...StyleSheet.absoluteFillObject, justifyContent: 'flex-end', backgroundColor: colors.modalScrim, zIndex: 40 },
  audienceBackdrop: { flex: 1, justifyContent: 'flex-end', backgroundColor: colors.modalScrim },
  audienceDismiss: { ...StyleSheet.absoluteFillObject },
  audienceSheet: {
    backgroundColor: '#111318', borderTopLeftRadius: 28, borderTopRightRadius: 28,
    paddingTop: 10, paddingHorizontal: 16, gap: 10,
  },
  audienceHandle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: 'rgba(255,255,255,0.22)', marginBottom: 8 },
  audienceTitle: { color: '#FFFFFF', fontSize: 22, fontWeight: '500' },
  audienceSub: { color: 'rgba(255,255,255,0.62)', fontSize: 14, lineHeight: 19, fontWeight: '500', marginBottom: 4 },
  audienceOption: {
    minHeight: 72, borderRadius: 20, backgroundColor: '#1D2027', borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)', flexDirection: 'row', alignItems: 'center', gap: 12, padding: 12,
  },
  audienceOptionOn: { borderColor: colors.accentPrimary, backgroundColor: '#22261E' },
  audienceIcon: { width: 44, height: 44, borderRadius: 22, backgroundColor: '#30343D', alignItems: 'center', justifyContent: 'center' },
  audienceIconOn: { backgroundColor: colors.accentPrimary, borderWidth: 1.2, borderColor: colors.accentPrimaryHover },
  audienceCopy: { flex: 1, minWidth: 0 },
  audienceLabel: { color: '#FFFFFF', fontSize: 16, fontWeight: '500' },
  audienceOptionSub: { color: 'rgba(255,255,255,0.58)', fontSize: 12, lineHeight: 16, fontWeight: '500', marginTop: 2 },
  tagUserRoot: { flex: 1, backgroundColor: colors.bgApp },
  tagUserHeader: {
    minHeight: 58,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 14,
  },
  tagUserClose: { width: 44, height: 44, alignItems: 'flex-start', justifyContent: 'center' },
  tagUserTitle: { color: '#111111', fontSize: 19, lineHeight: 24, fontWeight: '500' },
  tagUserDone: {
    minWidth: 58,
    height: 34,
    borderRadius: 17,
    backgroundColor: '#FFF93F',
    borderWidth: 1,
    borderColor: '#111111',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 12,
  },
  tagUserDoneText: { color: '#111111', fontSize: 13, fontWeight: '500' },
  tagUserSearchWrap: {
    minHeight: 44,
    borderRadius: 12,
    backgroundColor: '#F2F2F2',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginHorizontal: 16,
    paddingHorizontal: 12,
  },
  tagUserSearchInput: { flex: 1, minHeight: 42, color: '#111111', fontSize: 15, fontWeight: '600' },
  tagUserSelectedRail: { gap: 8, paddingHorizontal: 16, paddingTop: 12, paddingBottom: 2 },
  tagUserSelectedChip: {
    height: 32,
    borderRadius: 16,
    backgroundColor: '#FFF93F',
    borderWidth: 1,
    borderColor: '#111111',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 10,
  },
  tagUserSelectedText: { maxWidth: 126, color: '#111111', fontSize: 12, fontWeight: '500' },
  tagUserLoading: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  tagUserList: { flex: 1, paddingHorizontal: 16, paddingTop: 10 },
  tagUserRow: {
    minHeight: 66,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#EDEDED',
  },
  tagUserAvatar: { width: 44, height: 44, borderRadius: 22, backgroundColor: '#E6E6E6' },
  tagUserAvatarFallback: { width: 44, height: 44, borderRadius: 22, backgroundColor: '#111111', alignItems: 'center', justifyContent: 'center' },
  tagUserAvatarText: { color: '#FFFFFF', fontSize: 16, fontWeight: '500' },
  tagUserInfo: { flex: 1, minWidth: 0 },
  tagUserName: { color: '#111111', fontSize: 15, lineHeight: 19, fontWeight: '500' },
  tagUserHandle: { color: '#8A8A8A', fontSize: 12, lineHeight: 15, fontWeight: '500', marginTop: 1 },
  tagUserPick: { width: 24, height: 24, borderRadius: 12, borderWidth: 1.5, borderColor: '#C7C7C7', alignItems: 'center', justifyContent: 'center' },
  tagUserPickOn: { backgroundColor: '#FFF93F', borderColor: '#111111' },
  tagUserEmpty: { color: '#8A8A8A', fontSize: 14, fontWeight: '600', textAlign: 'center', paddingTop: 44 },

  // Header
  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 16, paddingVertical: 10,
    borderBottomWidth: 1, borderBottomColor: '#F0EDE7',
  },
  closeBtn: { width: 44, height: 44, borderRadius: 22, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 17, fontWeight: '500', color: '#1A1A1A' },
  postBtn: {
    backgroundColor: '#1A1A1A', paddingHorizontal: 22, paddingVertical: 10,
    borderRadius: 20, minWidth: 72, alignItems: 'center',
  },
  postBtnDisabled: { opacity: 0.3 },
  postBtnText: { fontSize: 14, fontWeight: '500', color: '#FFF' },

  // Progress
  progressBar: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    paddingHorizontal: 16, paddingVertical: 8, backgroundColor: '#FFF7ED',
  },
  progressText: { fontSize: 13, color: '#F97316', fontWeight: '500' },

  // Media
  mediaSection: { paddingVertical: 16 },
  mediaScroll: { paddingHorizontal: 16, gap: 10 },
  mediaThumb: { width: 120, height: 160, borderRadius: 14, overflow: 'hidden', position: 'relative', backgroundColor: '#000' },
  mediaImage: { width: '100%', height: '100%', resizeMode: 'cover' },
  videoBadge: {
    position: 'absolute', top: 8, left: 8,
    backgroundColor: 'rgba(0,0,0,0.6)', borderRadius: 8,
    paddingHorizontal: 6, paddingVertical: 3,
  },
  mediaRemove: {
    position: 'absolute', top: 6, right: 6,
    width: 24, height: 24, borderRadius: 12,
    backgroundColor: 'rgba(0,0,0,0.5)', justifyContent: 'center', alignItems: 'center',
  },
  addMore: {
    width: 120, height: 160, borderRadius: 14,
    borderWidth: 2, borderColor: '#E8E4DF', borderStyle: 'dashed',
    justifyContent: 'center', alignItems: 'center',
  },

  mediaEmpty: { alignItems: 'center', paddingVertical: 20 },
  mediaActions: { flexDirection: 'row', gap: 24, marginBottom: 12 },
  mediaActionBtn: { alignItems: 'center', gap: 8 },
  mediaActionIcon: {
    width: 64, height: 64, borderRadius: 20,
    justifyContent: 'center', alignItems: 'center',
  },
  mediaActionLabel: { fontSize: 13, fontWeight: '600', color: '#666' },
  mediaHint: { fontSize: 13, color: '#BBB' },

  // Sections
  section: { paddingHorizontal: 16, paddingTop: 16 },
  sectionHeaderRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 },
  sectionLabel: { fontSize: 14, fontWeight: '500', color: '#1A1A1A', marginBottom: 10 },
  required: { color: '#DC2626', fontWeight: '600' },
  optional: { color: '#BBB', fontWeight: '400', fontSize: 12 },
  detectedHint: { color: '#059669', fontWeight: '500', fontSize: 12 },

  clipControls: { flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: 8 },
  clipLabel: { color: '#777', fontSize: 11, fontWeight: '600' },
  clipInput: {
    width: 48, height: 30, borderRadius: 10, backgroundColor: '#F5F5F2', textAlign: 'center',
    color: '#111', fontSize: 13, fontWeight: '500', paddingVertical: 0,
  },
  durationRow: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 8, marginTop: 10 },
  durationChip: { height: 34, minWidth: 50, borderRadius: 17, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#E8E4DF', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 12 },
  durationChipOn: { backgroundColor: '#111', borderColor: '#111' },
  durationText: { color: '#555', fontSize: 12, fontWeight: '500' },
  durationTextOn: { color: '#FFF' },

  // Format
  formatChip: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    paddingHorizontal: 14, paddingVertical: 10,
    borderRadius: 16, borderWidth: 1.5, borderColor: '#E8E4DF',
    backgroundColor: '#FFF',
  },
  formatChipActive: { backgroundColor: '#111', borderColor: '#111' },
  formatChipDetected: { borderColor: '#059669', borderWidth: 2 },
  formatLabel: { fontSize: 13, fontWeight: '600', color: '#666' },

  // Category
  catGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  catChip: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    paddingHorizontal: 14, paddingVertical: 10,
    borderRadius: 16, borderWidth: 1.5, borderColor: '#E8E4DF',
    backgroundColor: '#FFF',
  },
  catLabel: { fontSize: 13, fontWeight: '600', color: '#666' },

  // Caption
  captionInput: {
    backgroundColor: '#FFF', borderRadius: 16, borderWidth: 1, borderColor: '#F0EDE7',
    paddingHorizontal: 16, paddingVertical: 14,
    fontSize: 15, color: '#1A1A1A', lineHeight: 22, minHeight: 80,
    textAlignVertical: 'top',
  },

  // Place
  placePill: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: '#FFF', borderRadius: 16, borderWidth: 1, borderColor: '#F0EDE7',
    paddingHorizontal: 16, paddingVertical: 14,
  },
  placePillActive: { borderColor: '#FECACA', backgroundColor: '#FFF5F5' },
  placeText: { flex: 1, fontSize: 14, color: '#BBB', fontWeight: '500' },
});
