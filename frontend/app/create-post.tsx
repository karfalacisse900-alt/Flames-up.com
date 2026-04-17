import React, { useState } from 'react';
import {
  View, Text, StyleSheet, TextInput, TouchableOpacity, Image, ScrollView,
  KeyboardAvoidingView, Platform, ActivityIndicator, Alert, Dimensions,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import * as Location from 'expo-location';
import { useAuthStore } from '../src/store/authStore';
import api from '../src/api/client';
import { uploadImage, getVideoUploadUrl, uploadVideoToStream } from '../src/utils/mediaUpload';

const { width: SW } = Dimensions.get('window');

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

export default function CreatePostScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();
  const params = useLocalSearchParams<{ place_id?: string; place_name?: string }>();

  const [media, setMedia] = useState<{ uri: string; type: 'image' | 'video'; base64?: string; width?: number; height?: number }[]>([]);
  const [caption, setCaption] = useState('');
  const [category, setCategory] = useState<string | null>(null);
  const [format, setFormat] = useState('auto');
  const [detectedFormat, setDetectedFormat] = useState('');
  const [placeTag, setPlaceTag] = useState(params.place_name || '');
  const [placeId, setPlaceId] = useState(params.place_id || '');
  const [isPosting, setIsPosting] = useState(false);
  const [uploadStep, setUploadStep] = useState('');

  // Auto-attach place tag if coming from a place detail page
  const hasPlacePreset = !!(params.place_name);

  const pickMedia = async () => {
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Permission needed', 'Please allow access to your photo library');
      return;
    }
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images', 'videos'],
      allowsMultipleSelection: true,
      quality: 0.7,
      base64: true,
      selectionLimit: 6,
    });
    if (!result.canceled && result.assets) {
      const newMedia = result.assets.map(a => ({
        uri: a.uri,
        type: (a.type === 'video' ? 'video' : 'image') as 'image' | 'video',
        base64: a.base64 || undefined,
        width: a.width || 0,
        height: a.height || 0,
      }));
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
  };

  const takePhoto = async () => {
    const perm = await ImagePicker.requestCameraPermissionsAsync();
    if (!perm.granted) return;
    const result = await ImagePicker.launchCameraAsync({
      quality: 0.8,
      base64: true,
    });
    if (!result.canceled && result.assets?.[0]) {
      const a = result.assets[0];
      const newItem = {
        uri: a.uri,
        type: (a.type === 'video' ? 'video' : 'image') as 'image' | 'video',
        base64: a.base64 || undefined,
        width: a.width || 0,
        height: a.height || 0,
      };
      const updated = [...media, newItem].slice(0, 6);
      setMedia(updated);

      // Auto-detect format
      if (newItem.type === 'image' && newItem.width && newItem.height && !detectedFormat) {
        setDetectedFormat(detectFormat(newItem.width, newItem.height));
      }
    }
  };

  const removeMedia = (idx: number) => {
    setMedia(prev => prev.filter((_, i) => i !== idx));
  };

  // Auto-detect location on mount
  useEffect(() => { detectLocation(); }, []);

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
        const parts = [addr.name, city].filter(Boolean);
        setPlaceTag(parts.join(', '));
      }
    } catch {}
  };

  const canPost = media.length > 0;

  const handlePost = async () => {
    if (!canPost || isPosting) return;
    setIsPosting(true);
    try {
      const uploadedUrls: string[] = [];
      const mediaTypes: string[] = [];

      for (let i = 0; i < media.length; i++) {
        const m = media[i];
        if (m.type === 'video') {
          setUploadStep(`Uploading video ${i + 1}...`);
          const info = await getVideoUploadUrl();
          if (info) {
            const ok = await uploadVideoToStream(info.uploadUrl, m.uri);
            if (ok) {
              uploadedUrls.push(`cfstream:${info.videoUid}`);
              mediaTypes.push('video');
            }
          }
        } else if (m.base64) {
          setUploadStep(`Uploading image ${i + 1}...`);
          const b64 = m.base64.startsWith('data:') ? m.base64 : `data:image/jpeg;base64,${m.base64}`;
          const url = await uploadImage(b64);
          if (url) {
            uploadedUrls.push(url);
            mediaTypes.push('image');
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
      await api.post('/posts', {
        content: caption || '',
        image: uploadedUrls[0],
        images: uploadedUrls,
        media_types: mediaTypes,
        post_type: category || 'general',
        category: category || '',
        format: finalFormat,
        location: placeTag || '',
        place_id: placeId || '',
        place_name: placeTag || '',
      });

      router.replace('/(tabs)/home' as any);
    } catch (error) {
      console.log('Post error:', error);
      Alert.alert('Error', 'Failed to create post');
    } finally {
      setIsPosting(false);
      setUploadStep('');
    }
  };

  return (
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
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FAFAF8' },

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
  mediaImage: { width: '100%', height: '100%', resizeMode: 'contain' },
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
  sectionLabel: { fontSize: 14, fontWeight: '700', color: '#1A1A1A', marginBottom: 10 },
  required: { color: '#DC2626', fontWeight: '600' },
  optional: { color: '#BBB', fontWeight: '400', fontSize: 12 },
  detectedHint: { color: '#059669', fontWeight: '500', fontSize: 12 },

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
