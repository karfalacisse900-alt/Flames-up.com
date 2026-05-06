import React, { useEffect, useMemo, useRef, useState } from 'react';
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
import { Audio, ResizeMode, Video } from 'expo-av';
import { useAuthStore } from '../src/store/authStore';
import api from '../src/api/client';
import { uploadImageWithBackup, uploadVideoWithBackup } from '../src/utils/mediaUpload';
import { processMediaBatch } from '../src/utils/mediaProcessing';
import { isPhoneVerificationError, requireVerifiedPhone } from '../src/utils/phoneVerification';
import {
  AudiusTrack,
  SelectedPostSound,
  getFavoriteAudiusTracks,
  getAudiusTrackStream,
  getAudiusTrendingTracks,
  searchAudiusTracks,
  toggleFavoriteAudiusTrack,
} from '../src/utils/music';

const { width: SW, height: SH } = Dimensions.get('window');

const CATEGORIES = [
  { id: 'food',      label: 'Food',      icon: 'restaurant-outline', color: '#F59E0B' },
  { id: 'fashion',   label: 'Fashion',   icon: 'shirt-outline',      color: '#EC4899' },
  { id: 'culture',   label: 'Culture',   icon: 'color-palette-outline', color: '#8B5CF6' },
  { id: 'street',    label: 'Street',    icon: 'musical-notes-outline', color: '#10B981' },
  { id: 'nightlife', label: 'Nightlife', icon: 'moon-outline',       color: '#6366F1' },
  { id: 'city_life', label: 'City Life', icon: 'business-outline',   color: '#0EA5E9' },
];

const FORMATS = [
  { id: 'auto', label: 'Auto', ratio: 0, icon: 'sparkles-outline' },
  { id: '1:1',  label: 'Square', ratio: 1,      icon: 'square-outline' },
  { id: '4:5',  label: '4:5',    ratio: 5 / 4,  icon: 'phone-portrait-outline' },
  { id: '2:3',  label: '2:3',    ratio: 3 / 2,  icon: 'tablet-portrait-outline' },
  { id: '9:16', label: '9:16',   ratio: 16 / 9, icon: 'resize-outline' },
];

const CLIP_DURATIONS = [5, 10, 15, 30];

type PostAudience = 'public' | 'followers' | 'friends' | 'private';

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

function paramText(value?: string | string[]) {
  return Array.isArray(value) ? value[0] : value || '';
}

// Detect best format from image dimensions
function detectFormat(width: number, height: number): string {
  if (width <= 0 || height <= 0) return 'auto';
  const ratio = height / width;
  const formats = [
    { id: '1:1',  ratio: 1 },
    { id: '4:5',  ratio: 5 / 4 },
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

export default function CreatePostScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();
  const params = useLocalSearchParams<{
    place_id?: string;
    place_name?: string;
    audio_provider?: string;
    audio_track_id?: string;
    audio_title?: string;
    audio_artist?: string;
    audio_artwork_url?: string;
    audio_stream_url?: string;
    audio_start_time?: string;
    audio_duration?: string;
  }>();

  const [media, setMedia] = useState<StudioMediaItem[]>([]);
  const [caption, setCaption] = useState('');
  const [category, setCategory] = useState<string | null>(null);
  const [format, setFormat] = useState('auto');
  const [detectedFormat, setDetectedFormat] = useState('');
  const [placeTag, setPlaceTag] = useState(params.place_name || '');
  const [placeId, setPlaceId] = useState(params.place_id || '');
  const [isPosting, setIsPosting] = useState(false);
  const [uploadStep, setUploadStep] = useState('');
  const [musicVisible, setMusicVisible] = useState(false);
  const [musicTab, setMusicTab] = useState<'trending' | 'search' | 'favorites'>('trending');
  const [musicQuery, setMusicQuery] = useState('');
  const [musicTracks, setMusicTracks] = useState<AudiusTrack[]>([]);
  const [favoriteTracks, setFavoriteTracks] = useState<AudiusTrack[]>([]);
  const [musicLoading, setMusicLoading] = useState(false);
  const [musicError, setMusicError] = useState('');
  const [playingTrackId, setPlayingTrackId] = useState('');
  const [previewSound, setPreviewSound] = useState<Audio.Sound | null>(null);
  const [previewVisible, setPreviewVisible] = useState(false);
  const [fitMode, setFitMode] = useState<'cover' | 'contain'>('cover');
  const [editPanelVisible, setEditPanelVisible] = useState(false);
  const [textOverlay, setTextOverlay] = useState('');
  const [overlayTextDraft, setOverlayTextDraft] = useState('');
  const [textOverlayVisible, setTextOverlayVisible] = useState(false);
  const [textOverlayPosition, setTextOverlayPosition] = useState({ x: 0.5, y: 0.42 });
  const [overlayMediaPosition, setOverlayMediaPosition] = useState({ x: 0.72, y: 0.62 });
  const [studioFrameSize, setStudioFrameSize] = useState({ width: 0, height: 0 });
  const [audience, setAudience] = useState<PostAudience>('public');
  const [audienceVisible, setAudienceVisible] = useState(false);
  const [selectedSound, setSelectedSound] = useState<SelectedPostSound | null>(() => {
    const provider = paramText(params.audio_provider);
    const trackId = paramText(params.audio_track_id);
    if (provider !== 'audius' || !trackId) return null;
    return {
      audio_provider: 'audius',
      audio_track_id: trackId,
      audio_title: paramText(params.audio_title) || 'Original sound',
      audio_artist: paramText(params.audio_artist) || 'Audius artist',
      audio_artwork_url: paramText(params.audio_artwork_url),
      audio_stream_url: paramText(params.audio_stream_url),
      audio_start_time: Number(paramText(params.audio_start_time) || 0),
      audio_duration: Number(paramText(params.audio_duration) || 15),
    };
  });

  // Auto-attach place tag if coming from a place detail page
  const hasPlacePreset = !!(params.place_name);
  const audienceMeta = AUDIENCE_OPTIONS.find((item) => item.id === audience) || AUDIENCE_OPTIONS[0];
  const textPositionRef = useRef(textOverlayPosition);
  const overlayPositionRef = useRef(overlayMediaPosition);
  const textDragStartRef = useRef(textOverlayPosition);
  const overlayDragStartRef = useRef(overlayMediaPosition);

  useEffect(() => {
    textPositionRef.current = textOverlayPosition;
  }, [textOverlayPosition]);

  useEffect(() => {
    overlayPositionRef.current = overlayMediaPosition;
  }, [overlayMediaPosition]);

  const textPanResponder = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: (_, gesture) => Math.abs(gesture.dx) > 2 || Math.abs(gesture.dy) > 2,
    onPanResponderGrant: () => {
      textDragStartRef.current = textPositionRef.current;
    },
    onPanResponderMove: (_, gesture) => {
      const width = studioFrameSize.width || SW;
      const height = studioFrameSize.height || Math.max(360, SH * 0.58);
      setTextOverlayPosition({
        x: clampUnit(textDragStartRef.current.x + gesture.dx / width),
        y: clampUnit(textDragStartRef.current.y + gesture.dy / height),
      });
    },
  }), [studioFrameSize.height, studioFrameSize.width]);

  const overlayPanResponder = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: (_, gesture) => Math.abs(gesture.dx) > 2 || Math.abs(gesture.dy) > 2,
    onPanResponderGrant: () => {
      overlayDragStartRef.current = overlayPositionRef.current;
    },
    onPanResponderMove: (_, gesture) => {
      const width = studioFrameSize.width || SW;
      const height = studioFrameSize.height || Math.max(360, SH * 0.58);
      setOverlayMediaPosition({
        x: clampUnit(overlayDragStartRef.current.x + gesture.dx / width),
        y: clampUnit(overlayDragStartRef.current.y + gesture.dy / height),
      });
    },
  }), [studioFrameSize.height, studioFrameSize.width]);

  const stopPreview = async () => {
    if (previewSound) {
      await previewSound.stopAsync().catch(() => undefined);
      await previewSound.unloadAsync().catch(() => undefined);
    }
    setPreviewSound(null);
    setPlayingTrackId('');
  };

  const refreshFavoriteTracks = async () => {
    const tracks = await getFavoriteAudiusTracks();
    setFavoriteTracks(tracks);
    return tracks;
  };

  const loadTrendingMusic = async () => {
    setMusicLoading(true);
    setMusicError('');
    try {
      const tracks = await getAudiusTrendingTracks(50);
      setMusicTracks(tracks);
    } catch (error: any) {
      setMusicTracks([]);
      setMusicError(error?.response?.data?.detail || 'Could not load trending music.');
    } finally {
      setMusicLoading(false);
    }
  };

  const searchMusic = async (query: string) => {
    setMusicLoading(true);
    setMusicError('');
    try {
      const tracks = await searchAudiusTracks(query, 50);
      setMusicTracks(tracks);
    } catch (error: any) {
      setMusicTracks([]);
      setMusicError(error?.response?.data?.detail || 'Could not search music right now.');
    } finally {
      setMusicLoading(false);
    }
  };

  const openMusicPicker = () => {
    setMusicVisible(true);
    setMusicTab('trending');
    if (musicTracks.length === 0) {
      loadTrendingMusic();
    }
  };

  const isFavoriteTrack = (track: AudiusTrack) => favoriteTracks.some((item) => item.id === track.id);

  const toggleFavoriteTrack = async (track: AudiusTrack) => {
    const result = await toggleFavoriteAudiusTrack(track);
    setFavoriteTracks(result.favorites);
    if (musicTab === 'favorites') setMusicTracks(result.favorites);
  };

  const previewTrack = async (track: AudiusTrack) => {
    try {
      if (playingTrackId === track.id) {
        await stopPreview();
        return;
      }
      await stopPreview();
      await Audio.setAudioModeAsync({ playsInSilentModeIOS: true }).catch(() => undefined);
      const streamTrack = track.stream_url ? track : await getAudiusTrackStream(track.id);
      if (!streamTrack.stream_url) throw new Error('No stream URL');
      const { sound } = await Audio.Sound.createAsync(
        { uri: streamTrack.stream_url },
        { shouldPlay: true, positionMillis: 0, volume: 0.85 }
      );
      sound.setOnPlaybackStatusUpdate((status: any) => {
        if (status?.didJustFinish) {
          setPlayingTrackId('');
        }
      });
      setPreviewSound(sound);
      setPlayingTrackId(track.id);
    } catch (error: any) {
      Alert.alert('Preview failed', error?.response?.data?.detail || 'Could not play this sound.');
    }
  };

  const useTrack = async (track: AudiusTrack) => {
    try {
      const streamTrack = track.stream_url ? track : await getAudiusTrackStream(track.id);
      if (!streamTrack.stream_url) throw new Error('No stream URL');
      setSelectedSound({
        audio_provider: 'audius',
        audio_track_id: streamTrack.id,
        audio_title: streamTrack.title,
        audio_artist: streamTrack.artist,
        audio_artwork_url: streamTrack.artwork_url,
        audio_stream_url: streamTrack.stream_url,
        audio_start_time: 0,
        audio_duration: 15,
      });
      await stopPreview();
      setMusicVisible(false);
    } catch (error: any) {
      Alert.alert('Sound unavailable', error?.response?.data?.detail || 'Could not attach this sound.');
    }
  };

  const setClipDuration = (duration: number) => {
    setSelectedSound((prev) => prev ? { ...prev, audio_duration: duration } : prev);
  };

  const setClipStart = (value: string) => {
    const start = Math.max(0, Math.min(60 * 60 * 6, Math.round(Number(value.replace(/\D/g, '')) || 0)));
    setSelectedSound((prev) => prev ? { ...prev, audio_start_time: start } : prev);
  };

  useEffect(() => {
    return () => {
      previewSound?.unloadAsync().catch(() => undefined);
    };
  }, [previewSound]);

  useEffect(() => {
    refreshFavoriteTracks();
  }, []);

  useEffect(() => {
    if (!musicVisible) return;
    if (musicTab === 'trending') {
      loadTrendingMusic();
      return;
    }
    if (musicTab === 'favorites') {
      refreshFavoriteTracks().then(setMusicTracks);
      return;
    }
    const q = musicQuery.trim();
    if (q.length < 2) {
      setMusicTracks([]);
      setMusicError('');
      return;
    }
    const handle = setTimeout(() => searchMusic(q), 450);
    return () => clearTimeout(handle);
  }, [musicVisible, musicTab, musicQuery]);

  const pickMedia = async () => {
    try {
      const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (status !== 'granted') {
        Alert.alert('Permission needed', 'Please allow access to your photo library');
        return;
      }
      const result = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ['images', 'videos'],
        allowsMultipleSelection: true,
        quality: 0.9,
        base64: false,
        selectionLimit: 6,
        videoExportPreset: ImagePicker.VideoExportPreset.H264_1280x720,
        videoQuality: ImagePicker.UIImagePickerControllerQualityType.Medium,
        preferredAssetRepresentationMode: ImagePicker.UIImagePickerPreferredAssetRepresentationMode.Compatible,
      });
      if (!result.canceled && result.assets) {
        setUploadStep('Optimizing media...');
        const processedAssets = await processMediaBatch(result.assets, 'balanced');
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
        const updated = [...media, ...newMedia].slice(0, 6);
        setMedia(updated);

        // Auto-detect format from first image
        const firstImg = updated.find(m => m.type === 'image' && m.width && m.height);
        if (firstImg && firstImg.width && firstImg.height) {
          const detected = detectFormat(firstImg.width, firstImg.height);
          setDetectedFormat(detected);
          if (format === 'auto') {
            // Keep auto mode, detected format will be used during post creation
          }
        }
      }
    } catch (error) {
      console.log('Media picker error:', error);
      Alert.alert('Media processing failed', 'Please try selecting media again.');
    } finally {
      setUploadStep('');
    }
  };

  const pickSingleMediaItem = async (): Promise<StudioMediaItem | null> => {
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Permission needed', 'Please allow access to your photo library');
      return null;
    }

    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images', 'videos'],
      allowsMultipleSelection: false,
      quality: 0.9,
      base64: false,
      selectionLimit: 1,
      videoExportPreset: ImagePicker.VideoExportPreset.H264_1280x720,
      videoQuality: ImagePicker.UIImagePickerControllerQualityType.Medium,
      preferredAssetRepresentationMode: ImagePicker.UIImagePickerPreferredAssetRepresentationMode.Compatible,
    });

    if (result.canceled || !result.assets?.[0]) return null;
    setUploadStep('Optimizing media...');
    const [asset] = await processMediaBatch([result.assets[0]], 'balanced');
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

  const addOverlayMedia = async () => {
    try {
      const overlay = await pickSingleMediaItem();
      if (!overlay) return;
      setMedia((prev) => {
        if (prev.length === 0) return [overlay];
        const next = [...prev];
        next[1] = overlay;
        return next.slice(0, 6);
      });
      setOverlayMediaPosition({ x: 0.72, y: 0.62 });
    } catch (error) {
      console.log('Overlay media error:', error);
      Alert.alert('Overlay failed', 'Please try choosing that media again.');
    } finally {
      setUploadStep('');
    }
  };

  const openTextOverlay = () => {
    setOverlayTextDraft(textOverlay);
    setTextOverlayVisible(true);
  };

  const saveTextOverlay = () => {
    setTextOverlay(overlayTextDraft.trim());
    setTextOverlayVisible(false);
  };

  const takePhoto = async () => {
    try {
      const perm = await ImagePicker.requestCameraPermissionsAsync();
      if (!perm.granted) return;
      const result = await ImagePicker.launchCameraAsync({
        quality: 0.85,
        base64: false,
        mediaTypes: ['images', 'videos'],
        videoQuality: ImagePicker.UIImagePickerControllerQualityType.Medium,
        videoMaxDuration: 45,
      });
      if (!result.canceled && result.assets?.[0]) {
        setUploadStep('Optimizing media...');
        const [processedAsset] = await processMediaBatch([result.assets[0]], 'balanced');
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

  const removeMedia = (idx: number) => {
    setMedia(prev => prev.filter((_, i) => i !== idx));
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
        const parts = [city, region].filter(Boolean);
        // Also add state/area context for filtering (e.g. "Bronx, New York")
        const nycBoroughs = ['bronx', 'brooklyn', 'queens', 'manhattan', 'staten island'];
        const cityLower = city.toLowerCase();
        let tag = parts.join(', ');
        if (nycBoroughs.some(b => cityLower.includes(b)) || region.toLowerCase().includes('new york')) {
          tag = `${city}, NYC, New York`;
        }
        setPlaceTag(tag);
      }
    } catch {}
  };

  const canPost = media.length > 0;
  const primaryMedia = media[0];
  const overlayMedia = media[1];

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
          const uploaded = await uploadVideoWithBackup(m.uri, m.mimeType || 'video/mp4', m.fileName || `video-${i + 1}.mp4`);
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
      const editorOverlays = [
        textOverlay.trim() ? {
          type: 'text',
          text: textOverlay.trim(),
          x: Number(textOverlayPosition.x.toFixed(4)),
          y: Number(textOverlayPosition.y.toFixed(4)),
          width: 0.78,
        } : null,
        overlayMedia ? {
          type: 'media',
          media_index: 1,
          x: Number(overlayMediaPosition.x.toFixed(4)),
          y: Number(overlayMediaPosition.y.toFixed(4)),
          width: 0.32,
        } : null,
      ].filter(Boolean);
      await api.post('/posts', {
        content: caption || '',
        image: uploadedUrls[0],
        images: uploadedUrls,
        media_types: mediaTypes,
        media_backup_ids: mediaBackupIds,
        editor_overlays: editorOverlays,
        post_type: category || 'general',
        category: category || '',
        format: finalFormat,
        visibility: audience,
        location: placeTag || '',
        place_id: placeId || '',
        place_name: placeTag || '',
        ...(selectedSound ? selectedSound : {}),
      });

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
    const frameWidth = mode === 'preview'
      ? Math.min(220, SW * 0.52)
      : (studioFrameSize.width || SW);
    const frameHeight = mode === 'preview'
      ? Math.min(180, SW * 0.43)
      : (studioFrameSize.height || Math.max(360, SH * 0.58));
    const overlayWidth = Math.min(mode === 'preview' ? 74 : 132, Math.max(66, frameWidth * 0.32));
    const overlayHeight = Math.round(overlayWidth * 1.34);
    const textWidth = Math.min(frameWidth - 18, Math.max(140, frameWidth * 0.78));
    const overlayLeft = clamp((overlayMediaPosition.x * frameWidth) - overlayWidth / 2, 8, Math.max(8, frameWidth - overlayWidth - 8));
    const overlayTop = clamp((overlayMediaPosition.y * frameHeight) - overlayHeight / 2, 8, Math.max(8, frameHeight - overlayHeight - 8));
    const textLeft = clamp((textOverlayPosition.x * frameWidth) - textWidth / 2, 8, Math.max(8, frameWidth - textWidth - 8));
    const textTop = clamp((textOverlayPosition.y * frameHeight) - 28, 8, Math.max(8, frameHeight - 78));

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
                resizeMode={fitMode === 'contain' ? ResizeMode.CONTAIN : ResizeMode.COVER}
                shouldPlay={mode === 'editor'}
                isLooping
                isMuted={mode === 'editor'}
                useNativeControls={mode === 'preview'}
              />
            ) : (
              <Image source={{ uri: primaryMedia.uri }} style={s.studioMedia} resizeMode={fitMode} />
            )}
            {overlayMedia ? (
              <View
                style={[s.studioOverlayMediaFrame, { width: overlayWidth, height: overlayHeight, left: overlayLeft, top: overlayTop }]}
                {...(mode === 'editor' ? overlayPanResponder.panHandlers : {})}
              >
                {overlayMedia.type === 'video' ? (
                  <Video
                    source={{ uri: overlayMedia.uri }}
                    style={s.studioOverlayMedia}
                    resizeMode={ResizeMode.COVER}
                    shouldPlay={mode === 'editor'}
                    isLooping
                    isMuted
                  />
                ) : (
                  <Image source={{ uri: overlayMedia.uri }} style={s.studioOverlayMedia} resizeMode="cover" />
                )}
                {mode === 'editor' ? (
                  <TouchableOpacity style={s.studioOverlayRemove} onPress={() => removeMedia(1)}>
                    <Ionicons name="close" size={14} color="#FFF" />
                  </TouchableOpacity>
                ) : null}
              </View>
            ) : null}
            {textOverlay ? (
              <TouchableOpacity
                disabled={mode === 'preview'}
                activeOpacity={0.88}
                style={[s.studioTextOverlay, { width: textWidth, left: textLeft, top: textTop }]}
                onPress={openTextOverlay}
                {...(mode === 'editor' ? textPanResponder.panHandlers : {})}
              >
                <Text style={s.studioTextOverlayText}>{textOverlay}</Text>
              </TouchableOpacity>
            ) : null}
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

  return (
    <>
      <KeyboardAvoidingView style={s.studioRoot} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
        <View style={[s.studioTopBar, { paddingTop: insets.top + 8 }]}>
          <TouchableOpacity style={s.studioCircle} onPress={() => router.back()}>
            <Ionicons name="close" size={26} color="#FFF" />
          </TouchableOpacity>
          <TouchableOpacity style={s.studioTopSound} onPress={openMusicPicker} activeOpacity={0.88}>
            {selectedSound?.audio_artwork_url ? (
              <Image source={{ uri: selectedSound.audio_artwork_url }} style={s.studioTopSoundArt} />
            ) : (
              <View style={s.studioTopSoundArtFallback}>
                <Ionicons name="musical-notes" size={16} color="#FFF" />
              </View>
            )}
            <View style={s.studioTopSoundCopy}>
              <Text style={s.studioTopSoundTitle} numberOfLines={1}>{selectedSound ? selectedSound.audio_title : 'Add audio'}</Text>
              <Text style={s.studioTopSoundSub} numberOfLines={1}>{selectedSound ? selectedSound.audio_artist : 'Suggested sound'}</Text>
            </View>
            <View style={s.studioTopSoundPlus}>
              <Ionicons name={selectedSound ? 'checkmark' : 'add'} size={22} color="#FFF" />
            </View>
          </TouchableOpacity>
          <View style={s.studioCircleGhost} />
        </View>

        {isPosting && uploadStep ? (
          <View style={s.studioProgress}>
            <ActivityIndicator size="small" color="#DFFF32" />
            <Text style={s.studioProgressText}>{uploadStep}</Text>
          </View>
        ) : null}

        <View style={s.studioStage}>
          {renderStudioMedia()}
          {selectedSound ? (
            <TouchableOpacity style={s.studioSoundPill} onPress={openMusicPicker}>
              {selectedSound.audio_artwork_url ? <Image source={{ uri: selectedSound.audio_artwork_url }} style={s.studioSoundArt} /> : null}
              <Ionicons name="musical-notes" size={14} color="#111" />
              <Text style={s.studioSoundText} numberOfLines={1}>{selectedSound.audio_title}</Text>
            </TouchableOpacity>
          ) : null}
        </View>

        <View style={[s.studioEditFooter, { paddingBottom: Math.max(14, insets.bottom + 8) }]}>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.studioEditTools}>
            <TouchableOpacity style={s.studioEditTool} onPress={openMusicPicker}>
              <Ionicons name="musical-notes-outline" size={24} color="#FFF" />
              <Text style={s.studioEditToolText}>Audio</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.studioEditTool} onPress={openTextOverlay}>
              <Ionicons name="text-outline" size={24} color="#FFF" />
              <Text style={s.studioEditToolText}>Text</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.studioEditTool} onPress={addOverlayMedia}>
              <Ionicons name="copy-outline" size={24} color="#FFF" />
              <Text style={s.studioEditToolText}>Overlay</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.studioEditTool} onPress={replaceMedia}>
              <Ionicons name="images-outline" size={24} color="#FFF" />
              <Text style={s.studioEditToolText}>Media</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[s.studioEditTool, editPanelVisible && s.studioEditToolOn]} onPress={() => setEditPanelVisible((value) => !value)}>
              <Ionicons name="options-outline" size={24} color="#FFF" />
              <Text style={s.studioEditToolText}>Edit</Text>
            </TouchableOpacity>
          </ScrollView>

          {editPanelVisible ? (
            <View style={s.studioEditPanel}>
              <View style={s.studioEditPanelHeader}>
                <Text style={s.studioEditPanelTitle}>Edit media</Text>
                <TouchableOpacity style={s.studioEditPanelClose} onPress={() => setEditPanelVisible(false)}>
                  <Ionicons name="chevron-down" size={18} color="#FFFFFF" />
                </TouchableOpacity>
              </View>
              <View style={s.studioEditModeRow}>
                <TouchableOpacity style={[s.studioEditModeChip, fitMode === 'cover' && s.studioEditModeChipOn]} onPress={() => setFitMode('cover')}>
                  <Ionicons name="expand-outline" size={17} color={fitMode === 'cover' ? '#111' : '#FFF'} />
                  <Text style={[s.studioEditModeText, fitMode === 'cover' && s.studioEditModeTextOn]}>Fill</Text>
                </TouchableOpacity>
                <TouchableOpacity style={[s.studioEditModeChip, fitMode === 'contain' && s.studioEditModeChipOn]} onPress={() => setFitMode('contain')}>
                  <Ionicons name="contract-outline" size={17} color={fitMode === 'contain' ? '#111' : '#FFF'} />
                  <Text style={[s.studioEditModeText, fitMode === 'contain' && s.studioEditModeTextOn]}>Fit</Text>
                </TouchableOpacity>
                <TouchableOpacity style={s.studioEditModeChip} onPress={replaceMedia}>
                  <Ionicons name="swap-horizontal-outline" size={17} color="#FFF" />
                  <Text style={s.studioEditModeText}>Change</Text>
                </TouchableOpacity>
              </View>
            </View>
          ) : null}

          {selectedSound ? (
            <View style={s.studioClipRow}>
              {CLIP_DURATIONS.map((duration) => (
                <TouchableOpacity key={duration} style={[s.studioClipChip, selectedSound.audio_duration === duration && s.studioClipChipOn]} onPress={() => setClipDuration(duration)}>
                  <Text style={[s.studioClipText, selectedSound.audio_duration === duration && s.studioClipTextOn]}>{duration}s</Text>
                </TouchableOpacity>
              ))}
            </View>
          ) : null}

          <TouchableOpacity disabled={!canPost} style={[s.studioNextButton, !canPost && s.studioDisabled]} onPress={() => setPreviewVisible(true)}>
            <Text style={s.studioNextText}>Next</Text>
            <Ionicons name="arrow-forward" size={22} color="#FFF" />
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>

      <Modal visible={previewVisible} animationType="fade" onRequestClose={() => setPreviewVisible(false)}>
        <View style={[s.shareRoot, { paddingTop: insets.top + 8, paddingBottom: Math.max(18, insets.bottom + 10) }]}>
          <View style={s.shareHeader}>
            <TouchableOpacity style={s.shareBack} onPress={() => setPreviewVisible(false)}>
              <Ionicons name="chevron-back" size={28} color="#111" />
            </TouchableOpacity>
            <Text style={s.shareTitle}>New post</Text>
            <View style={s.shareBack} />
          </View>

          <ScrollView contentContainerStyle={s.shareContent} showsVerticalScrollIndicator={false}>
            <View style={s.sharePreviewRow}>
              <View style={s.shareThumb}>
                {renderStudioMedia('preview')}
              </View>
            </View>

            <TextInput
              style={s.shareCaptionInput}
              placeholder="Add a caption..."
              placeholderTextColor="#757B86"
              value={caption}
              onChangeText={setCaption}
              multiline
              maxLength={500}
            />

            <TouchableOpacity style={s.shareOption}>
              <Ionicons name="person-add-outline" size={30} color="#111" />
              <Text style={s.shareOptionTitle}>Tag people</Text>
              <Ionicons name="chevron-forward" size={24} color="#71717A" />
            </TouchableOpacity>
            <TouchableOpacity style={s.shareOption} onPress={detectLocation}>
              <Ionicons name="location-outline" size={30} color="#111" />
              <View style={s.shareOptionCopy}>
                <Text style={s.shareOptionTitle}>Add location</Text>
                {placeTag ? <Text style={s.shareOptionSub} numberOfLines={1}>{placeTag}</Text> : null}
              </View>
              <Ionicons name="chevron-forward" size={24} color="#71717A" />
            </TouchableOpacity>
            <View style={s.shareDivider} />

            <TouchableOpacity style={s.shareOption} onPress={() => setAudienceVisible(true)}>
              <Ionicons name={audienceMeta.icon as any} size={30} color="#111" />
              <Text style={s.shareOptionTitle}>Audience</Text>
              <Text style={s.shareValue}>{audienceMeta.label}</Text>
              <Ionicons name="chevron-forward" size={24} color="#71717A" />
            </TouchableOpacity>
          </ScrollView>

          <TouchableOpacity style={[s.shareSubmitButton, (!canPost || isPosting) && s.studioDisabled]} disabled={!canPost || isPosting} onPress={handlePost}>
            {isPosting ? <ActivityIndicator color="#FFF" /> : <Text style={s.shareSubmitText}>Share</Text>}
          </TouchableOpacity>
        </View>
      </Modal>

      <Modal visible={textOverlayVisible} transparent animationType="fade" onRequestClose={() => setTextOverlayVisible(false)}>
        <KeyboardAvoidingView style={s.textOverlayBackdrop} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
          <TouchableOpacity style={s.textOverlayDismiss} activeOpacity={1} onPress={() => setTextOverlayVisible(false)} />
          <View style={s.textOverlaySheet}>
            <Text style={s.textOverlayTitle}>Add text</Text>
            <TextInput
              value={overlayTextDraft}
              onChangeText={setOverlayTextDraft}
              placeholder="Type on your post"
              placeholderTextColor="rgba(255,255,255,0.45)"
              style={s.textOverlayInput}
              autoFocus
              multiline
              maxLength={90}
            />
            <View style={s.textOverlayActions}>
              <TouchableOpacity style={s.textOverlayCancel} onPress={() => setTextOverlayVisible(false)}>
                <Text style={s.textOverlayCancelText}>Cancel</Text>
              </TouchableOpacity>
              <TouchableOpacity style={s.textOverlayDone} onPress={saveTextOverlay}>
                <Text style={s.textOverlayDoneText}>Done</Text>
              </TouchableOpacity>
            </View>
          </View>
        </KeyboardAvoidingView>
      </Modal>

      <Modal visible={audienceVisible} transparent animationType="slide" onRequestClose={() => setAudienceVisible(false)}>
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
                  <Ionicons name={active ? 'checkmark-circle' : 'ellipse-outline'} size={22} color={active ? '#DFFF32' : '#8A8A8A'} />
                </TouchableOpacity>
              );
            })}
          </View>
        </View>
      </Modal>

      <Modal visible={musicVisible} animationType="slide" onRequestClose={async () => { await stopPreview(); setMusicVisible(false); }}>
        <View style={[s.musicModal, { paddingTop: insets.top + 8 }]}>
          <View style={s.musicHeader}>
            <TouchableOpacity style={s.musicClose} onPress={async () => { await stopPreview(); setMusicVisible(false); }}>
              <Ionicons name="chevron-down" size={22} color="#111" />
            </TouchableOpacity>
            <Text style={s.musicTitle}>Add Music</Text>
            <View style={s.musicClose} />
          </View>

          <View style={s.musicSearchWrap}>
            <Ionicons name="search" size={18} color="#777" />
            <TextInput
              value={musicQuery}
              onChangeText={(text) => { setMusicQuery(text); setMusicTab(text.trim().length > 0 ? 'search' : 'trending'); }}
              placeholder="Search songs or artists"
              placeholderTextColor="#9A9A9A"
              style={s.musicSearchInput}
              returnKeyType="search"
              onSubmitEditing={() => musicQuery.trim().length >= 2 && searchMusic(musicQuery)}
            />
            {musicQuery ? (
              <TouchableOpacity onPress={() => { setMusicQuery(''); setMusicTab('trending'); }}>
                <Ionicons name="close-circle" size={18} color="#AAA" />
              </TouchableOpacity>
            ) : null}
          </View>

          <View style={s.musicTabs}>
            <TouchableOpacity style={[s.musicTab, musicTab === 'trending' && s.musicTabOn]} onPress={() => { setMusicTab('trending'); setMusicQuery(''); }}>
              <Text style={[s.musicTabText, musicTab === 'trending' && s.musicTabTextOn]}>Trending</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[s.musicTab, musicTab === 'search' && s.musicTabOn]} onPress={() => setMusicTab('search')}>
              <Text style={[s.musicTabText, musicTab === 'search' && s.musicTabTextOn]}>Search</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[s.musicTab, musicTab === 'favorites' && s.musicTabOn]} onPress={() => setMusicTab('favorites')}>
              <Text style={[s.musicTabText, musicTab === 'favorites' && s.musicTabTextOn]}>Favorites</Text>
            </TouchableOpacity>
          </View>

          {musicLoading ? (
            <View style={s.musicState}>
              <ActivityIndicator color="#111" />
              <Text style={s.musicStateText}>Loading sounds...</Text>
            </View>
          ) : musicError ? (
            <View style={s.musicState}>
              <Ionicons name="warning-outline" size={26} color="#B42318" />
              <Text style={s.musicStateText}>{musicError}</Text>
              <TouchableOpacity style={s.musicRetry} onPress={() => musicTab === 'trending' ? loadTrendingMusic() : searchMusic(musicQuery)}>
                <Text style={s.musicRetryText}>Try again</Text>
              </TouchableOpacity>
            </View>
          ) : (
            <ScrollView contentContainerStyle={[s.musicList, { paddingBottom: insets.bottom + 24 }]} showsVerticalScrollIndicator={false}>
              {musicTracks.length === 0 ? (
                <View style={s.musicState}>
                  <Ionicons name="musical-notes-outline" size={30} color="#B0B0B0" />
                  <Text style={s.musicStateText}>{musicTab === 'favorites' ? 'Favorite sounds will appear here.' : musicTab === 'search' ? 'Search for a song or artist.' : 'No trending sounds found.'}</Text>
                </View>
              ) : musicTracks.map((track) => {
                const favorited = isFavoriteTrack(track);
                return (
                  <View key={track.id} style={s.trackRow}>
                    {track.artwork_url ? (
                      <Image source={{ uri: track.artwork_url }} style={s.trackArt} />
                    ) : (
                      <View style={s.trackArtFallback}>
                        <Ionicons name="musical-note" size={20} color="#111" />
                      </View>
                    )}
                    <View style={s.trackCopy}>
                      <Text style={s.trackTitle} numberOfLines={1}>{track.title}</Text>
                      <Text style={s.trackArtist} numberOfLines={1}>{track.artist}</Text>
                    </View>
                    <TouchableOpacity style={[s.favoriteSoundButton, favorited && s.favoriteSoundButtonOn]} onPress={() => toggleFavoriteTrack(track)}>
                      <Ionicons name={favorited ? 'star' : 'star-outline'} size={17} color={favorited ? '#111' : '#777'} />
                    </TouchableOpacity>
                    <TouchableOpacity style={s.previewButton} onPress={() => previewTrack(track)}>
                      <Ionicons name={playingTrackId === track.id ? 'pause' : 'play'} size={16} color="#111" />
                    </TouchableOpacity>
                    <TouchableOpacity style={s.useSoundButton} onPress={() => useTrack(track)}>
                      <Text style={s.useSoundText}>Use</Text>
                    </TouchableOpacity>
                  </View>
                );
              })}
            </ScrollView>
          )}
        </View>
      </Modal>
    </>
  );

  return (
    <>
    <KeyboardAvoidingView
      style={s.container}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      <View style={{ flex: 1, paddingTop: insets.top }}>
        {/* Header */}
        <View style={s.header}>
          <TouchableOpacity onPress={() => router.back()} style={s.closeBtn}>
            <Ionicons name="close" size={22} color="#1A1A1A" />
          </TouchableOpacity>
          <Text style={s.headerTitle}>New Post</Text>
          <TouchableOpacity
            style={[s.postBtn, !canPost && s.postBtnDisabled]}
            disabled={!canPost || isPosting}
            onPress={handlePost}
          >
            {isPosting ? (
              <ActivityIndicator size="small" color="#FFF" />
            ) : (
              <Text style={s.postBtnText}>Post</Text>
            )}
          </TouchableOpacity>
        </View>

        {/* Upload progress */}
        {isPosting && uploadStep ? (
          <View style={s.progressBar}>
            <ActivityIndicator size="small" color="#F97316" />
            <Text style={s.progressText}>{uploadStep}</Text>
          </View>
        ) : null}

        <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingBottom: 40 }}>
          {/* Media Section */}
          <View style={s.mediaSection}>
            {media.length > 0 ? (
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.mediaScroll}>
                {media.map((m, idx) => (
                  <View key={idx} style={s.mediaThumb}>
                    <Image source={{ uri: m.uri }} style={s.mediaImage} />
                    {m.type === 'video' && (
                      <View style={s.videoBadge}>
                        <Ionicons name="videocam" size={12} color="#FFF" />
                      </View>
                    )}
                    <TouchableOpacity style={s.mediaRemove} onPress={() => removeMedia(idx)}>
                      <Ionicons name="close" size={14} color="#FFF" />
                    </TouchableOpacity>
                  </View>
                ))}
                {media.length < 6 && (
                  <TouchableOpacity style={s.addMore} onPress={pickMedia}>
                    <Ionicons name="add" size={24} color="#999" />
                  </TouchableOpacity>
                )}
              </ScrollView>
            ) : (
              <View style={s.mediaEmpty}>
                <View style={s.mediaActions}>
                  <TouchableOpacity style={s.mediaActionBtn} onPress={pickMedia}>
                    <View style={[s.mediaActionIcon, { backgroundColor: '#F3ECFF' }]}>
                      <Ionicons name="images" size={26} color="#7C3AED" />
                    </View>
                    <Text style={s.mediaActionLabel}>Gallery</Text>
                  </TouchableOpacity>
                  <TouchableOpacity style={s.mediaActionBtn} onPress={takePhoto}>
                    <View style={[s.mediaActionIcon, { backgroundColor: '#FEE2E2' }]}>
                      <Ionicons name="camera" size={26} color="#DC2626" />
                    </View>
                    <Text style={s.mediaActionLabel}>Camera</Text>
                  </TouchableOpacity>
                </View>
                <Text style={s.mediaHint}>Add a photo or video to post</Text>
              </View>
            )}
          </View>

          {/* Studio Music */}
          <View style={s.section}>
            <View style={s.sectionHeaderRow}>
              <Text style={s.sectionLabel}>Sound <Text style={s.optional}>(optional)</Text></Text>
              {selectedSound ? (
                <TouchableOpacity onPress={() => setSelectedSound(null)}>
                  <Text style={s.removeSoundText}>Remove</Text>
                </TouchableOpacity>
              ) : null}
            </View>
            {selectedSound ? (
              <View style={s.selectedSoundCard}>
                {selectedSound!.audio_artwork_url ? (
                  <Image source={{ uri: selectedSound!.audio_artwork_url }} style={s.selectedSoundArt} />
                ) : (
                  <View style={s.selectedSoundArtFallback}>
                    <Ionicons name="musical-notes" size={22} color="#111" />
                  </View>
                )}
                <View style={s.selectedSoundCopy}>
                  <Text style={s.selectedSoundTitle} numberOfLines={1}>{selectedSound!.audio_title}</Text>
                  <Text style={s.selectedSoundArtist} numberOfLines={1}>{selectedSound!.audio_artist}</Text>
                  <View style={s.clipControls}>
                    <Text style={s.clipLabel}>Start</Text>
                    <TextInput
                      value={String(selectedSound!.audio_start_time)}
                      onChangeText={setClipStart}
                      keyboardType="number-pad"
                      style={s.clipInput}
                    />
                    <Text style={s.clipLabel}>sec</Text>
                  </View>
                </View>
              </View>
            ) : (
              <TouchableOpacity style={s.addMusicButton} onPress={openMusicPicker}>
                <View style={s.addMusicIcon}>
                  <Ionicons name="musical-notes" size={20} color="#111" />
                </View>
                <View style={{ flex: 1 }}>
                  <Text style={s.addMusicTitle}>Add Music</Text>
                  <Text style={s.addMusicSubtitle}>Search Audius tracks or use weekly trending sounds</Text>
                </View>
                <Ionicons name="chevron-forward" size={18} color="#777" />
              </TouchableOpacity>
            )}
            {selectedSound ? (
              <View style={s.durationRow}>
                {CLIP_DURATIONS.map((duration) => {
                  const active = selectedSound!.audio_duration === duration;
                  return (
                    <TouchableOpacity key={duration} style={[s.durationChip, active && s.durationChipOn]} onPress={() => setClipDuration(duration)}>
                      <Text style={[s.durationText, active && s.durationTextOn]}>{duration}s</Text>
                    </TouchableOpacity>
                  );
                })}
                <TouchableOpacity style={s.changeSoundButton} onPress={openMusicPicker}>
                  <Text style={s.changeSoundText}>Change sound</Text>
                </TouchableOpacity>
              </View>
            ) : null}
          </View>

          {/* Category Selection (Optional) */}
          <View style={s.section}>
            <Text style={s.sectionLabel}>Category <Text style={s.optional}>(optional)</Text></Text>
            <View style={s.catGrid}>
              {CATEGORIES.map(cat => {
                const active = category === cat.id;
                return (
                  <TouchableOpacity
                    key={cat.id}
                    style={[s.catChip, active && { backgroundColor: cat.color, borderColor: cat.color }]}
                    onPress={() => setCategory(active ? null : cat.id)}
                  >
                    <Ionicons name={cat.icon as any} size={16} color={active ? '#FFF' : cat.color} />
                    <Text style={[s.catLabel, active && { color: '#FFF' }]}>{cat.label}</Text>
                  </TouchableOpacity>
                );
              })}
            </View>
          </View>

          {/* Format Selection (Optional — auto by default) */}
          {media.length > 0 && (
            <View style={s.section}>
              <Text style={s.sectionLabel}>
                Format <Text style={s.optional}>(optional)</Text>
                {format === 'auto' && detectedFormat ? (
                  <Text style={s.detectedHint}> — detected: {detectedFormat}</Text>
                ) : null}
              </Text>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8 }}>
                {FORMATS.map(f => {
                  const active = format === f.id;
                  const isDetected = format === 'auto' && detectedFormat === f.id;
                  return (
                    <TouchableOpacity
                      key={f.id}
                      style={[
                        s.formatChip,
                        active && s.formatChipActive,
                        isDetected && !active && s.formatChipDetected,
                      ]}
                      onPress={() => setFormat(f.id)}
                    >
                      <Ionicons name={f.icon as any} size={16} color={active ? '#FFF' : '#666'} />
                      <Text style={[s.formatLabel, active && { color: '#FFF' }]}>{f.label}</Text>
                    </TouchableOpacity>
                  );
                })}
              </ScrollView>
            </View>
          )}

          {/* Caption (Optional) */}
          <View style={s.section}>
            <Text style={s.sectionLabel}>Caption <Text style={s.optional}>(optional)</Text></Text>
            <TextInput
              style={s.captionInput}
              placeholder="Say something about this..."
              placeholderTextColor="#CCC"
              value={caption}
              onChangeText={setCaption}
              multiline
              maxLength={500}
            />
          </View>

          {/* Place Tag (Optional) */}
          <View style={s.section}>
            <Text style={s.sectionLabel}>
              Place {hasPlacePreset ? '' : <Text style={s.optional}>(optional)</Text>}
            </Text>
            <TouchableOpacity
              style={[s.placePill, placeTag ? s.placePillActive : null]}
              onPress={detectLocation}
            >
              <Ionicons name="location-outline" size={18} color={placeTag ? '#DC2626' : '#999'} />
              <Text style={[s.placeText, placeTag && { color: '#1A1A1A' }]}>
                {placeTag || 'Tap to detect location'}
              </Text>
              {placeTag ? (
                <TouchableOpacity onPress={() => { setPlaceTag(''); setPlaceId(''); }}>
                  <Ionicons name="close-circle" size={18} color="#CCC" />
                </TouchableOpacity>
              ) : null}
            </TouchableOpacity>
          </View>
        </ScrollView>
      </View>
    </KeyboardAvoidingView>

    <Modal visible={musicVisible} animationType="slide" onRequestClose={async () => { await stopPreview(); setMusicVisible(false); }}>
      <View style={[s.musicModal, { paddingTop: insets.top + 8 }]}>
        <View style={s.musicHeader}>
          <TouchableOpacity style={s.musicClose} onPress={async () => { await stopPreview(); setMusicVisible(false); }}>
            <Ionicons name="chevron-down" size={22} color="#111" />
          </TouchableOpacity>
          <Text style={s.musicTitle}>Add Music</Text>
          <View style={s.musicClose} />
        </View>

        <View style={s.musicSearchWrap}>
          <Ionicons name="search" size={18} color="#777" />
          <TextInput
            value={musicQuery}
            onChangeText={(text) => { setMusicQuery(text); setMusicTab(text.trim().length > 0 ? 'search' : 'trending'); }}
            placeholder="Search songs or artists"
            placeholderTextColor="#9A9A9A"
            style={s.musicSearchInput}
            returnKeyType="search"
            onSubmitEditing={() => musicQuery.trim().length >= 2 && searchMusic(musicQuery)}
          />
          {musicQuery ? (
            <TouchableOpacity onPress={() => { setMusicQuery(''); setMusicTab('trending'); }}>
              <Ionicons name="close-circle" size={18} color="#AAA" />
            </TouchableOpacity>
          ) : null}
        </View>

        <View style={s.musicTabs}>
          <TouchableOpacity style={[s.musicTab, musicTab === 'trending' && s.musicTabOn]} onPress={() => { setMusicTab('trending'); setMusicQuery(''); }}>
            <Text style={[s.musicTabText, musicTab === 'trending' && s.musicTabTextOn]}>Trending</Text>
          </TouchableOpacity>
          <TouchableOpacity style={[s.musicTab, musicTab === 'search' && s.musicTabOn]} onPress={() => setMusicTab('search')}>
            <Text style={[s.musicTabText, musicTab === 'search' && s.musicTabTextOn]}>Search</Text>
          </TouchableOpacity>
        </View>

        {musicLoading ? (
          <View style={s.musicState}>
            <ActivityIndicator color="#111" />
            <Text style={s.musicStateText}>Loading sounds...</Text>
          </View>
        ) : musicError ? (
          <View style={s.musicState}>
            <Ionicons name="warning-outline" size={26} color="#B42318" />
            <Text style={s.musicStateText}>{musicError}</Text>
            <TouchableOpacity style={s.musicRetry} onPress={() => musicTab === 'trending' ? loadTrendingMusic() : searchMusic(musicQuery)}>
              <Text style={s.musicRetryText}>Try again</Text>
            </TouchableOpacity>
          </View>
        ) : (
          <ScrollView contentContainerStyle={[s.musicList, { paddingBottom: insets.bottom + 24 }]} showsVerticalScrollIndicator={false}>
            {musicTracks.length === 0 ? (
              <View style={s.musicState}>
                <Ionicons name="musical-notes-outline" size={30} color="#B0B0B0" />
                <Text style={s.musicStateText}>{musicTab === 'search' ? 'Search for a song or artist.' : 'No trending sounds found.'}</Text>
              </View>
            ) : musicTracks.map((track) => (
              <View key={track.id} style={s.trackRow}>
                {track.artwork_url ? (
                  <Image source={{ uri: track.artwork_url }} style={s.trackArt} />
                ) : (
                  <View style={s.trackArtFallback}>
                    <Ionicons name="musical-note" size={20} color="#111" />
                  </View>
                )}
                <View style={s.trackCopy}>
                  <Text style={s.trackTitle} numberOfLines={1}>{track.title}</Text>
                  <Text style={s.trackArtist} numberOfLines={1}>{track.artist}</Text>
                </View>
                <TouchableOpacity style={s.previewButton} onPress={() => previewTrack(track)}>
                  <Ionicons name={playingTrackId === track.id ? 'pause' : 'play'} size={16} color="#111" />
                </TouchableOpacity>
                <TouchableOpacity style={s.useSoundButton} onPress={() => useTrack(track)}>
                  <Text style={s.useSoundText}>Use this sound</Text>
                </TouchableOpacity>
              </View>
            ))}
          </ScrollView>
        )}
      </View>
    </Modal>
    </>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FAFAF8' },
  studioRoot: { flex: 1, backgroundColor: '#050505' },
  studioTopBar: {
    minHeight: 66, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 14, gap: 10, zIndex: 20,
  },
  studioCircle: {
    width: 42, height: 42, borderRadius: 21, backgroundColor: 'rgba(255,255,255,0.16)',
    alignItems: 'center', justifyContent: 'center',
  },
  studioCircleGhost: { width: 42, height: 42 },
  studioTopSound: {
    flex: 1, maxWidth: 250, minHeight: 54, borderRadius: 27, backgroundColor: 'rgba(255,255,255,0.12)',
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)', flexDirection: 'row', alignItems: 'center',
    gap: 9, paddingHorizontal: 10,
  },
  studioTopSoundArt: { width: 36, height: 36, borderRadius: 10, backgroundColor: '#333' },
  studioTopSoundArtFallback: { width: 36, height: 36, borderRadius: 10, backgroundColor: 'rgba(255,255,255,0.13)', alignItems: 'center', justifyContent: 'center' },
  studioTopSoundCopy: { flex: 1, minWidth: 0 },
  studioTopSoundTitle: { color: '#FFF', fontSize: 14, lineHeight: 17, fontWeight: '900' },
  studioTopSoundSub: { color: 'rgba(255,255,255,0.55)', fontSize: 12, lineHeight: 15, fontWeight: '800', marginTop: 1 },
  studioTopSoundPlus: { width: 36, height: 36, borderRadius: 18, backgroundColor: 'rgba(255,255,255,0.13)', alignItems: 'center', justifyContent: 'center' },
  studioUndoGroup: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  studioSmallCircle: {
    width: 36, height: 36, borderRadius: 18, backgroundColor: 'rgba(255,255,255,0.14)',
    alignItems: 'center', justifyContent: 'center',
  },
  studioSmallCircleDisabled: { opacity: 0.36 },
  studioTitleWrap: { flex: 1, minWidth: 0, alignItems: 'center' },
  studioTitle: { color: '#FFFFFF', fontSize: 17, lineHeight: 21, fontWeight: '900' },
  studioSubtitle: { color: 'rgba(255,255,255,0.56)', fontSize: 11, lineHeight: 14, fontWeight: '800', marginTop: 1 },
  studioTopActions: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  studioPreviewButton: {
    height: 38, borderRadius: 19, backgroundColor: '#FFFFFF', flexDirection: 'row',
    alignItems: 'center', gap: 6, paddingHorizontal: 13,
  },
  studioPreviewText: { color: '#111', fontSize: 12, fontWeight: '900' },
  studioPostButton: {
    minWidth: 62, height: 38, borderRadius: 19, backgroundColor: '#DFFF32',
    borderWidth: 1.5, borderColor: '#111', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 16,
  },
  studioPostText: { color: '#111', fontSize: 13, fontWeight: '900' },
  studioShareButton: {
    minWidth: 72, height: 38, borderRadius: 19, backgroundColor: '#DFFF32',
    borderWidth: 1.5, borderColor: '#111', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 15,
  },
  studioShareText: { color: '#111', fontSize: 13, fontWeight: '900' },
  studioDisabled: { opacity: 0.4 },
  studioProgress: {
    marginHorizontal: 14, minHeight: 38, borderRadius: 19, backgroundColor: 'rgba(223,255,50,0.12)',
    borderWidth: 1, borderColor: 'rgba(223,255,50,0.24)', flexDirection: 'row', alignItems: 'center',
    gap: 8, paddingHorizontal: 12,
  },
  studioProgressText: { color: '#DFFF32', fontSize: 12, fontWeight: '800' },
  studioStage: { flex: 1, minHeight: 260, justifyContent: 'center', position: 'relative' },
  studioMediaFrame: {
    flex: 1, minHeight: 260, borderRadius: 24, marginHorizontal: 0, marginTop: 8, marginBottom: 8,
    overflow: 'hidden', backgroundColor: '#111111', position: 'relative',
  },
  studioMedia: { width: '100%', height: '100%' },
  studioOverlayMediaFrame: {
    position: 'absolute', borderRadius: 18,
    overflow: 'hidden', backgroundColor: '#111', borderWidth: 2, borderColor: 'rgba(255,255,255,0.78)',
  },
  studioOverlayMedia: { width: '100%', height: '100%' },
  studioOverlayRemove: {
    position: 'absolute', right: 6, top: 6, width: 24, height: 24, borderRadius: 12,
    backgroundColor: 'rgba(0,0,0,0.58)', alignItems: 'center', justifyContent: 'center',
  },
  studioTextOverlay: {
    position: 'absolute', alignItems: 'center',
  },
  studioTextOverlayText: {
    color: '#FFFFFF', fontSize: 28, lineHeight: 34, fontWeight: '900', textAlign: 'center',
    textShadowColor: 'rgba(0,0,0,0.62)', textShadowRadius: 10, textShadowOffset: { width: 0, height: 2 },
  },
  filterTint: { ...StyleSheet.absoluteFillObject },
  studioVideoBadge: {
    position: 'absolute', left: 12, top: 12, minHeight: 30, borderRadius: 15,
    backgroundColor: 'rgba(255,255,255,0.86)', flexDirection: 'row', alignItems: 'center',
    gap: 5, paddingHorizontal: 10,
  },
  studioVideoText: { color: '#111', fontSize: 12, fontWeight: '900' },
  studioEmptyCanvas: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 14, padding: 24 },
  studioEmptyTitle: { color: '#FFF', fontSize: 17, fontWeight: '900' },
  studioEmptyActions: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  studioEmptyButton: {
    height: 42, borderRadius: 21, backgroundColor: '#DFFF32', borderWidth: 1.5, borderColor: '#111',
    flexDirection: 'row', alignItems: 'center', gap: 7, paddingHorizontal: 15,
  },
  studioEmptyButtonDark: {
    height: 42, borderRadius: 21, backgroundColor: 'rgba(255,255,255,0.14)', borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.18)', flexDirection: 'row', alignItems: 'center', gap: 7, paddingHorizontal: 15,
  },
  studioEmptyButtonText: { color: '#111', fontSize: 13, fontWeight: '900' },
  studioEmptyButtonTextDark: { color: '#FFF', fontSize: 13, fontWeight: '900' },
  studioSoundPill: {
    position: 'absolute', left: 14, bottom: 14, right: 84, minHeight: 42, borderRadius: 21,
    backgroundColor: 'rgba(255,255,255,0.86)', flexDirection: 'row', alignItems: 'center',
    gap: 7, paddingHorizontal: 10,
  },
  studioSoundArt: { width: 28, height: 28, borderRadius: 14, backgroundColor: '#DDD' },
  studioSoundText: { flex: 1, minWidth: 0, color: '#111', fontSize: 12, fontWeight: '900' },
  studioPanel: {
    backgroundColor: '#171719', borderTopLeftRadius: 28, borderTopRightRadius: 28,
    paddingTop: 10, paddingHorizontal: 12, gap: 10,
  },
  studioPanelHandle: { alignSelf: 'center', width: 42, height: 4, borderRadius: 4, backgroundColor: 'rgba(255,255,255,0.24)', marginBottom: 2 },
  studioToolRail: { position: 'absolute', right: 12, top: 18, gap: 12, zIndex: 15 },
  studioToolRailButton: {
    width: 58, minHeight: 58, borderRadius: 18, backgroundColor: 'rgba(0,0,0,0.42)',
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.16)', alignItems: 'center', justifyContent: 'center', gap: 4,
  },
  studioToolRailText: { color: '#FFFFFF', fontSize: 10, lineHeight: 12, fontWeight: '900' },
  studioComposerRow: {
    minHeight: 70, borderRadius: 22, backgroundColor: 'rgba(255,255,255,0.08)',
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.10)', flexDirection: 'row', alignItems: 'flex-start',
    gap: 10, paddingHorizontal: 11, paddingVertical: 10,
  },
  studioComposerAvatar: { width: 36, height: 36, borderRadius: 18, backgroundColor: '#333' },
  studioComposerAvatarFallback: {
    width: 36, height: 36, borderRadius: 18, backgroundColor: '#DFFF32',
    borderWidth: 1.4, borderColor: '#111', alignItems: 'center', justifyContent: 'center',
  },
  studioComposerAvatarText: { color: '#111', fontSize: 15, fontWeight: '900' },
  studioComposerInput: {
    flex: 1, minHeight: 48, maxHeight: 94, color: '#FFFFFF', fontSize: 14,
    lineHeight: 19, fontWeight: '700', padding: 0, textAlignVertical: 'top',
  },
  studioMusicRow: {
    minHeight: 54, borderRadius: 20, backgroundColor: '#FFFFFF', flexDirection: 'row',
    alignItems: 'center', gap: 10, paddingHorizontal: 10,
  },
  studioMusicIconWrap: {
    width: 34, height: 34, borderRadius: 17, backgroundColor: '#DFFF32',
    borderWidth: 1.4, borderColor: '#111', alignItems: 'center', justifyContent: 'center',
  },
  studioMusicCopy: { flex: 1, minWidth: 0 },
  studioMusicTitle: { color: '#111', fontSize: 14, fontWeight: '900' },
  studioMusicSub: { color: '#666', fontSize: 11, lineHeight: 14, fontWeight: '700', marginTop: 1 },
  studioMusicAction: { color: '#111', fontSize: 12, fontWeight: '900' },
  studioEditFooter: {
    backgroundColor: '#080B10', borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.06)',
    paddingTop: 14, paddingHorizontal: 14, gap: 14,
  },
  studioEditTools: { gap: 12, paddingRight: 14 },
  studioEditTool: {
    width: 86, height: 78, borderRadius: 18, backgroundColor: '#202024',
    alignItems: 'center', justifyContent: 'center', gap: 7,
  },
  studioEditToolOn: { backgroundColor: '#34343A', borderWidth: 1, borderColor: 'rgba(255,255,255,0.16)' },
  studioEditToolText: { color: '#FFFFFF', fontSize: 14, lineHeight: 17, fontWeight: '900' },
  studioEditPanel: {
    borderRadius: 22, backgroundColor: '#171A20', borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    padding: 12, gap: 12,
  },
  studioEditPanelHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  studioEditPanelTitle: { color: '#FFFFFF', fontSize: 15, fontWeight: '900' },
  studioEditPanelClose: { width: 30, height: 30, borderRadius: 15, backgroundColor: 'rgba(255,255,255,0.08)', alignItems: 'center', justifyContent: 'center' },
  studioEditModeRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  studioEditModeChip: {
    flex: 1, minHeight: 42, borderRadius: 21, backgroundColor: '#262A31',
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 7,
  },
  studioEditModeChipOn: { backgroundColor: '#DFFF32' },
  studioEditModeText: { color: '#FFFFFF', fontSize: 13, fontWeight: '900' },
  studioEditModeTextOn: { color: '#111111' },
  studioClipRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  studioClipChip: {
    height: 32, borderRadius: 16, backgroundColor: '#202024', borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)', justifyContent: 'center', paddingHorizontal: 13,
  },
  studioClipChipOn: { backgroundColor: '#4B5CF6', borderColor: '#4B5CF6' },
  studioClipText: { color: 'rgba(255,255,255,0.72)', fontSize: 12, fontWeight: '900' },
  studioClipTextOn: { color: '#FFFFFF' },
  studioNextButton: {
    alignSelf: 'flex-end', minWidth: 150, height: 58, borderRadius: 29, backgroundColor: '#4B5CF6',
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, paddingHorizontal: 22,
  },
  studioNextText: { color: '#FFFFFF', fontSize: 19, fontWeight: '900' },
  studioFilterTabs: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  studioFilterTab: { height: 36, borderRadius: 18, backgroundColor: 'rgba(0,0,0,0.28)', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 14 },
  studioFilterTabOn: { height: 36, borderRadius: 18, backgroundColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 16 },
  studioFilterTabText: { color: '#FFFFFF', fontSize: 12, fontWeight: '900', textTransform: 'uppercase' },
  studioFilterTabTextOn: { color: '#111111', fontSize: 12, fontWeight: '900', textTransform: 'uppercase' },
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
  filterName: { color: 'rgba(255,255,255,0.56)', fontSize: 11, fontWeight: '800' },
  filterNameOn: { color: '#FFFFFF' },
  studioQuickRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  studioQuickChip: {
    flex: 1, minHeight: 38, borderRadius: 19, backgroundColor: '#FFFFFF',
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, paddingHorizontal: 9,
  },
  studioQuickText: { color: '#111', fontSize: 12, fontWeight: '900' },
  simpleStudioActions: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  simpleStudioAction: {
    flex: 1, minHeight: 46, borderRadius: 23, backgroundColor: '#FFFFFF',
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 7,
    paddingHorizontal: 12,
  },
  simpleStudioActionText: { color: '#111', fontSize: 13, fontWeight: '900' },
  studioCaptionInput: {
    minHeight: 48, maxHeight: 74, borderRadius: 18, backgroundColor: 'rgba(255,255,255,0.08)',
    color: '#FFFFFF', fontSize: 14, lineHeight: 19, fontWeight: '700', paddingHorizontal: 13, paddingVertical: 10,
    textAlignVertical: 'top',
  },
  studioCategoryRow: { gap: 8, paddingRight: 12 },
  studioCategoryChip: {
    minHeight: 34, borderRadius: 17, backgroundColor: 'rgba(255,255,255,0.08)', flexDirection: 'row',
    alignItems: 'center', gap: 5, paddingHorizontal: 11,
  },
  studioCategoryText: { color: '#FFF', fontSize: 12, fontWeight: '800' },
  studioCategoryTextOn: { color: '#FFF' },
  studioDurationRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  studioDurationChip: {
    height: 32, borderRadius: 16, backgroundColor: 'rgba(255,255,255,0.09)',
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: 13,
  },
  studioDurationChipOn: { backgroundColor: '#DFFF32' },
  studioDurationText: { color: '#FFF', fontSize: 12, fontWeight: '900' },
  studioDurationTextOn: { color: '#111' },
  studioToolBar: { minHeight: 42, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-around' },
  studioTool: { width: 44, height: 38, borderRadius: 18, alignItems: 'center', justifyContent: 'center' },
  studioToolOn: { backgroundColor: 'rgba(255,255,255,0.12)' },
  simpleStudioFooter: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  simpleFooterButton: {
    flex: 1, minHeight: 48, borderRadius: 24, backgroundColor: 'rgba(255,255,255,0.10)',
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.16)',
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8,
  },
  simpleFooterButtonText: { color: '#FFF', fontSize: 14, fontWeight: '900' },
  simpleFooterPost: {
    flex: 1, minHeight: 48, borderRadius: 24, backgroundColor: '#DFFF32',
    borderWidth: 1.5, borderColor: '#111', alignItems: 'center', justifyContent: 'center',
  },
  simpleFooterPostText: { color: '#111', fontSize: 14, fontWeight: '900' },
  postPreviewRoot: { flex: 1, backgroundColor: '#050505', paddingHorizontal: 16, gap: 14 },
  previewTopBar: { minHeight: 48, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  previewClose: { width: 42, height: 42, borderRadius: 21, backgroundColor: 'rgba(255,255,255,0.12)', alignItems: 'center', justifyContent: 'center' },
  previewTitle: { color: '#FFFFFF', fontSize: 17, fontWeight: '900' },
  previewPostButton: { height: 38, borderRadius: 19, backgroundColor: '#DFFF32', borderWidth: 1.5, borderColor: '#111', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 16 },
  previewPostText: { color: '#111', fontSize: 13, fontWeight: '900' },
  previewPhone: { flex: 1, borderRadius: 30, overflow: 'hidden', backgroundColor: '#111', position: 'relative' },
  previewMediaFrame: { flex: 1, overflow: 'hidden', backgroundColor: '#111', position: 'relative' },
  previewOverlay: { position: 'absolute', left: 16, right: 16, bottom: 18, gap: 10 },
  previewAuthorRow: { flexDirection: 'row', alignItems: 'center', gap: 9 },
  previewAvatar: { width: 42, height: 42, borderRadius: 21 },
  previewAvatarFallback: { width: 42, height: 42, borderRadius: 21, backgroundColor: '#DFFF32', borderWidth: 1.5, borderColor: '#111', alignItems: 'center', justifyContent: 'center' },
  previewAvatarText: { color: '#111', fontSize: 18, fontWeight: '900' },
  previewAuthorName: { color: '#FFF', fontSize: 16, fontWeight: '900' },
  previewAuthorSub: { color: 'rgba(255,255,255,0.72)', fontSize: 12, fontWeight: '700' },
  previewCaption: { color: '#FFF', fontSize: 14, lineHeight: 19, fontWeight: '700' },
  previewSoundBar: { minHeight: 38, borderRadius: 19, backgroundColor: 'rgba(255,255,255,0.86)', flexDirection: 'row', alignItems: 'center', gap: 7, paddingHorizontal: 11 },
  previewSoundText: { flex: 1, color: '#111', fontSize: 12, fontWeight: '900' },
  previewEditButton: { height: 48, borderRadius: 24, backgroundColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center' },
  previewEditText: { color: '#111', fontSize: 14, fontWeight: '900' },
  shareRoot: { flex: 1, backgroundColor: '#FFFFFF' },
  shareHeader: {
    minHeight: 64, borderBottomWidth: 1, borderBottomColor: '#ECECF0',
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16,
  },
  shareBack: { width: 48, height: 48, alignItems: 'center', justifyContent: 'center' },
  shareTitle: { color: '#0E1018', fontSize: 23, lineHeight: 28, fontWeight: '900' },
  shareContent: { paddingBottom: 112 },
  sharePreviewRow: { minHeight: 120, alignItems: 'center', justifyContent: 'center', paddingTop: 14 },
  shareThumb: {
    width: Math.min(220, SW * 0.52), height: Math.min(180, SW * 0.43), borderRadius: 20,
    overflow: 'hidden', backgroundColor: '#050505',
  },
  shareCaptionInput: {
    minHeight: 138, paddingHorizontal: 20, paddingTop: 22, paddingBottom: 12,
    color: '#111827', fontSize: 24, lineHeight: 31, fontWeight: '800', textAlignVertical: 'top',
  },
  sharePillRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 20, paddingBottom: 22 },
  shareMiniPill: {
    minHeight: 44, borderRadius: 15, backgroundColor: '#F1F2F6', flexDirection: 'row',
    alignItems: 'center', gap: 8, paddingHorizontal: 14,
  },
  shareMiniText: { color: '#111', fontSize: 18, fontWeight: '900' },
  shareOption: {
    minHeight: 76, flexDirection: 'row', alignItems: 'center', gap: 16,
    paddingHorizontal: 22, borderTopWidth: 1, borderTopColor: '#F2F2F5',
  },
  shareOptionCopy: { flex: 1, minWidth: 0 },
  shareOptionTitle: { flex: 1, color: '#111', fontSize: 23, lineHeight: 28, fontWeight: '900' },
  shareOptionSub: { color: '#6B7280', fontSize: 16, lineHeight: 20, fontWeight: '700', marginTop: 2 },
  shareValue: { color: '#6B7280', fontSize: 20, fontWeight: '800' },
  shareDivider: { height: 12, backgroundColor: '#F2F2F6', marginTop: 4 },
  shareSwitch: { width: 62, height: 38, borderRadius: 19, backgroundColor: '#686D78' },
  shareSubmitButton: {
    position: 'absolute', left: 20, right: 20, bottom: 24, height: 62, borderRadius: 17,
    backgroundColor: '#4B5CF6', alignItems: 'center', justifyContent: 'center',
  },
  shareSubmitText: { color: '#FFF', fontSize: 20, fontWeight: '900' },
  textOverlayBackdrop: { flex: 1, justifyContent: 'flex-end', backgroundColor: 'rgba(0,0,0,0.52)' },
  textOverlayDismiss: { ...StyleSheet.absoluteFillObject },
  textOverlaySheet: {
    margin: 14, borderRadius: 26, backgroundColor: '#111318', borderWidth: 1, borderColor: 'rgba(255,255,255,0.12)',
    padding: 16, gap: 14,
  },
  textOverlayTitle: { color: '#FFFFFF', fontSize: 20, fontWeight: '900' },
  textOverlayInput: {
    minHeight: 112, borderRadius: 18, backgroundColor: '#1D2027', color: '#FFFFFF',
    fontSize: 22, lineHeight: 28, fontWeight: '800', paddingHorizontal: 14, paddingVertical: 12,
    textAlignVertical: 'top',
  },
  textOverlayActions: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  textOverlayCancel: {
    flex: 1, height: 50, borderRadius: 25, backgroundColor: '#242832', alignItems: 'center', justifyContent: 'center',
  },
  textOverlayCancelText: { color: '#FFFFFF', fontSize: 15, fontWeight: '900' },
  textOverlayDone: {
    flex: 1, height: 50, borderRadius: 25, backgroundColor: '#DFFF32', borderWidth: 1.5, borderColor: '#111',
    alignItems: 'center', justifyContent: 'center',
  },
  textOverlayDoneText: { color: '#111111', fontSize: 15, fontWeight: '900' },
  audienceBackdrop: { flex: 1, justifyContent: 'flex-end', backgroundColor: 'rgba(0,0,0,0.38)' },
  audienceDismiss: { ...StyleSheet.absoluteFillObject },
  audienceSheet: {
    backgroundColor: '#111318', borderTopLeftRadius: 28, borderTopRightRadius: 28,
    paddingTop: 10, paddingHorizontal: 16, gap: 10,
  },
  audienceHandle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: 'rgba(255,255,255,0.22)', marginBottom: 8 },
  audienceTitle: { color: '#FFFFFF', fontSize: 22, fontWeight: '900' },
  audienceSub: { color: 'rgba(255,255,255,0.62)', fontSize: 14, lineHeight: 19, fontWeight: '700', marginBottom: 4 },
  audienceOption: {
    minHeight: 72, borderRadius: 20, backgroundColor: '#1D2027', borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)', flexDirection: 'row', alignItems: 'center', gap: 12, padding: 12,
  },
  audienceOptionOn: { borderColor: '#DFFF32', backgroundColor: '#22261E' },
  audienceIcon: { width: 44, height: 44, borderRadius: 22, backgroundColor: '#30343D', alignItems: 'center', justifyContent: 'center' },
  audienceIconOn: { backgroundColor: '#DFFF32', borderWidth: 1.4, borderColor: '#111111' },
  audienceCopy: { flex: 1, minWidth: 0 },
  audienceLabel: { color: '#FFFFFF', fontSize: 16, fontWeight: '900' },
  audienceOptionSub: { color: 'rgba(255,255,255,0.58)', fontSize: 12, lineHeight: 16, fontWeight: '700', marginTop: 2 },

  // Header
  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 16, paddingVertical: 10,
    borderBottomWidth: 1, borderBottomColor: '#F0EDE7',
  },
  closeBtn: { width: 44, height: 44, borderRadius: 22, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 17, fontWeight: '700', color: '#1A1A1A' },
  postBtn: {
    backgroundColor: '#1A1A1A', paddingHorizontal: 22, paddingVertical: 10,
    borderRadius: 20, minWidth: 72, alignItems: 'center',
  },
  postBtnDisabled: { opacity: 0.3 },
  postBtnText: { fontSize: 14, fontWeight: '700', color: '#FFF' },

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
  sectionLabel: { fontSize: 14, fontWeight: '700', color: '#1A1A1A', marginBottom: 10 },
  required: { color: '#DC2626', fontWeight: '600' },
  optional: { color: '#BBB', fontWeight: '400', fontSize: 12 },
  detectedHint: { color: '#059669', fontWeight: '500', fontSize: 12 },

  // Music studio
  addMusicButton: {
    minHeight: 74, borderRadius: 18, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#F0EDE7',
    flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 14, paddingVertical: 12,
  },
  addMusicIcon: {
    width: 44, height: 44, borderRadius: 22, backgroundColor: '#DFFF32', borderWidth: 1.5, borderColor: '#111',
    alignItems: 'center', justifyContent: 'center',
  },
  addMusicTitle: { color: '#111', fontSize: 15, fontWeight: '900' },
  addMusicSubtitle: { color: '#777', fontSize: 12, lineHeight: 16, fontWeight: '600', marginTop: 2 },
  removeSoundText: { color: '#B42318', fontSize: 12, fontWeight: '900' },
  selectedSoundCard: {
    minHeight: 82, borderRadius: 18, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#F0EDE7',
    flexDirection: 'row', alignItems: 'center', gap: 12, padding: 12,
  },
  selectedSoundArt: { width: 58, height: 58, borderRadius: 12, backgroundColor: '#EEE' },
  selectedSoundArtFallback: { width: 58, height: 58, borderRadius: 12, backgroundColor: '#DFFF32', alignItems: 'center', justifyContent: 'center' },
  selectedSoundCopy: { flex: 1, minWidth: 0 },
  selectedSoundTitle: { color: '#111', fontSize: 15, fontWeight: '900' },
  selectedSoundArtist: { color: '#777', fontSize: 12, fontWeight: '700', marginTop: 2 },
  clipControls: { flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: 8 },
  clipLabel: { color: '#777', fontSize: 11, fontWeight: '800' },
  clipInput: {
    width: 48, height: 30, borderRadius: 10, backgroundColor: '#F5F5F2', textAlign: 'center',
    color: '#111', fontSize: 13, fontWeight: '900', paddingVertical: 0,
  },
  durationRow: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 8, marginTop: 10 },
  durationChip: { height: 34, minWidth: 50, borderRadius: 17, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#E8E4DF', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 12 },
  durationChipOn: { backgroundColor: '#111', borderColor: '#111' },
  durationText: { color: '#555', fontSize: 12, fontWeight: '900' },
  durationTextOn: { color: '#FFF' },
  changeSoundButton: { height: 34, borderRadius: 17, backgroundColor: '#DFFF32', borderWidth: 1.5, borderColor: '#111', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 14 },
  changeSoundText: { color: '#111', fontSize: 12, fontWeight: '900' },

  musicModal: { flex: 1, backgroundColor: '#FAFAF8' },
  musicHeader: { minHeight: 52, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 14 },
  musicClose: { width: 42, height: 42, borderRadius: 21, alignItems: 'center', justifyContent: 'center' },
  musicTitle: { color: '#111', fontSize: 19, fontWeight: '900' },
  musicSearchWrap: {
    minHeight: 50, marginHorizontal: 16, borderRadius: 18, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#F0EDE7',
    flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 14,
  },
  musicSearchInput: { flex: 1, height: 48, color: '#111', fontSize: 15, fontWeight: '700', paddingVertical: 0 },
  musicTabs: { flexDirection: 'row', gap: 8, paddingHorizontal: 16, paddingVertical: 12 },
  musicTab: { height: 36, borderRadius: 18, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#EEEAE2', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 16 },
  musicTabOn: { backgroundColor: '#111', borderColor: '#111' },
  musicTabText: { color: '#777', fontSize: 13, fontWeight: '900' },
  musicTabTextOn: { color: '#FFF' },
  musicList: { paddingHorizontal: 16, gap: 10 },
  musicState: { minHeight: 220, alignItems: 'center', justifyContent: 'center', gap: 10, paddingHorizontal: 28 },
  musicStateText: { color: '#777', textAlign: 'center', fontSize: 14, fontWeight: '700' },
  musicRetry: { height: 38, borderRadius: 19, backgroundColor: '#111', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 18 },
  musicRetryText: { color: '#FFF', fontSize: 13, fontWeight: '900' },
  trackRow: {
    minHeight: 76, borderRadius: 18, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#F0EDE7',
    flexDirection: 'row', alignItems: 'center', gap: 10, padding: 10,
  },
  trackArt: { width: 54, height: 54, borderRadius: 13, backgroundColor: '#EEE' },
  trackArtFallback: { width: 54, height: 54, borderRadius: 13, backgroundColor: '#DFFF32', alignItems: 'center', justifyContent: 'center' },
  trackCopy: { flex: 1, minWidth: 0 },
  trackTitle: { color: '#111', fontSize: 14, fontWeight: '900' },
  trackArtist: { color: '#777', fontSize: 12, fontWeight: '700', marginTop: 2 },
  previewButton: { width: 36, height: 36, borderRadius: 18, backgroundColor: '#F1F1EF', alignItems: 'center', justifyContent: 'center' },
  favoriteSoundButton: { width: 36, height: 36, borderRadius: 18, backgroundColor: '#F1F1EF', alignItems: 'center', justifyContent: 'center' },
  favoriteSoundButtonOn: { backgroundColor: '#DFFF32', borderWidth: 1.4, borderColor: '#111' },
  useSoundButton: { minHeight: 36, borderRadius: 18, backgroundColor: '#DFFF32', borderWidth: 1.5, borderColor: '#111', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 12 },
  useSoundText: { color: '#111', fontSize: 12, fontWeight: '900' },

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
