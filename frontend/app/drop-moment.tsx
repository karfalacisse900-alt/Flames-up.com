import React, { useState, useRef } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, TextInput,
  ActivityIndicator, KeyboardAvoidingView, Platform, Alert, Dimensions,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import * as Location from 'expo-location';
import { useAuthStore } from '../src/store/authStore';
import api from '../src/api/client';
import { uploadImage, getVideoUploadUrl, uploadVideoToStream } from '../src/utils/mediaUpload';

const { width: SW } = Dimensions.get('window');

export default function DropMomentScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();

  const [media, setMedia] = useState<{ uri: string; type: 'image' | 'video'; base64?: string } | null>(null);
  const [caption, setCaption] = useState('');
  const [location, setLocation] = useState('');
  const [isPosting, setIsPosting] = useState(false);
  const [step, setStep] = useState<'capture' | 'compose'>('capture');
  const [uploadProgress, setUploadProgress] = useState('');

  const takePhoto = async () => {
    const perm = await ImagePicker.requestCameraPermissionsAsync();
    if (!perm.granted) {
      Alert.alert('Camera access needed', 'Allow camera access to drop a moment.');
      return;
    }
    const result = await ImagePicker.launchCameraAsync({
      quality: 0.85,
      base64: true,
      allowsEditing: true,
      aspect: [4, 5],
    });
    if (!result.canceled && result.assets?.[0]) {
      const asset = result.assets[0];
      setMedia({
        uri: asset.uri,
        type: asset.type === 'video' ? 'video' : 'image',
        base64: asset.base64 || undefined,
      });
      setStep('compose');
    }
  };

  const pickFromGallery = async () => {
    const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!perm.granted) return;
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images', 'videos'],
      quality: 0.85,
      base64: true,
      allowsEditing: true,
    });
    if (!result.canceled && result.assets?.[0]) {
      const asset = result.assets[0];
      setMedia({
        uri: asset.uri,
        type: asset.type === 'video' ? 'video' : 'image',
        base64: asset.base64 || undefined,
      });
      setStep('compose');
    }
  };

  const detectLocation = async () => {
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') return;
      const loc = await Location.getCurrentPositionAsync({});
      const [addr] = await Location.reverseGeocodeAsync({
        latitude: loc.coords.latitude,
        longitude: loc.coords.longitude,
      });
      if (addr) {
        const parts = [addr.name, addr.city, addr.region].filter(Boolean);
        setLocation(parts.join(', '));
      }
    } catch (err) {
      console.log('Location detect error:', err);
    }
  };

  const handlePost = async () => {
    if (!media || isPosting) return;
    setIsPosting(true);
    try {
      let imageUrl = '';
      let videoUid = '';

      if (media.type === 'video') {
        setUploadProgress('Getting upload URL...');
        const uploadInfo = await getVideoUploadUrl();
        if (uploadInfo) {
          setUploadProgress('Uploading video to Stream...');
          const success = await uploadVideoToStream(uploadInfo.uploadUrl, media.uri);
          if (success) {
            videoUid = uploadInfo.videoUid;
            imageUrl = `cfstream:${videoUid}`;
          }
        }
      } else if (media.base64) {
        setUploadProgress('Uploading image...');
        imageUrl = await uploadImage(media.base64.startsWith('data:') ? media.base64 : `data:image/jpeg;base64,${media.base64}`);
      }

      if (!imageUrl) {
        Alert.alert('Upload failed', 'Could not upload media. Please try again.');
        setIsPosting(false);
        return;
      }

      setUploadProgress('Creating post...');
      await api.post('/posts', {
        content: caption || '📍 Dropped a moment',
        image: imageUrl,
        images: [imageUrl],
        media_types: [media.type],
        post_type: 'moment',
        location: location || '',
      });

      router.replace('/(tabs)/home' as any);
    } catch (error) {
      console.log('Post error:', error);
      Alert.alert('Error', 'Failed to create post');
    } finally {
      setIsPosting(false);
      setUploadProgress('');
    }
  };

  // Step 1: Capture
  if (step === 'capture') {
    return (
      <View style={[s.container, { paddingTop: insets.top }]}>
        {/* Header */}
        <View style={s.captureHeader}>
          <TouchableOpacity style={s.closeBtn} onPress={() => router.back()}>
            <Ionicons name="close" size={24} color="#FFF" />
          </TouchableOpacity>
          <Text style={s.captureTitle}>Drop a Moment</Text>
          <View style={{ width: 40 }} />
        </View>

        {/* Center prompt */}
        <View style={s.captureBody}>
          <View style={s.captureIcon}>
            <Ionicons name="flame" size={48} color="#F97316" />
          </View>
          <Text style={s.captureHeadline}>What's happening?</Text>
          <Text style={s.captureSub}>Capture this moment and share it with the world</Text>
        </View>

        {/* Action buttons */}
        <View style={[s.captureActions, { paddingBottom: insets.bottom + 20 }]}>
          <TouchableOpacity style={s.captureBtn} onPress={takePhoto}>
            <View style={s.captureBtnIconWrap}>
              <Ionicons name="camera" size={28} color="#FFF" />
            </View>
            <Text style={s.captureBtnText}>Take Photo</Text>
            <Text style={s.captureBtnSub}>Open camera</Text>
          </TouchableOpacity>

          <TouchableOpacity style={s.captureBtn} onPress={pickFromGallery}>
            <View style={[s.captureBtnIconWrap, { backgroundColor: '#7C3AED' }]}>
              <Ionicons name="images" size={28} color="#FFF" />
            </View>
            <Text style={s.captureBtnText}>Gallery</Text>
            <Text style={s.captureBtnSub}>Choose existing</Text>
          </TouchableOpacity>

          <TouchableOpacity style={s.captureBtn} onPress={() => {
            setStep('compose');
          }}>
            <View style={[s.captureBtnIconWrap, { backgroundColor: '#0EA5E9' }]}>
              <Ionicons name="text" size={28} color="#FFF" />
            </View>
            <Text style={s.captureBtnText}>Text Only</Text>
            <Text style={s.captureBtnSub}>Write something</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  // Step 2: Compose
  return (
    <KeyboardAvoidingView
      style={[s.container, { backgroundColor: '#FAFAF8' }]}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      <View style={{ flex: 1, paddingTop: insets.top }}>
        {/* Header */}
        <View style={s.composeHeader}>
          <TouchableOpacity onPress={() => { setStep('capture'); setMedia(null); }}>
            <Ionicons name="arrow-back" size={22} color="#1A1A1A" />
          </TouchableOpacity>
          <Text style={s.composeTitle}>New Moment</Text>
          <TouchableOpacity
            style={[s.postBtn, (!media && !caption.trim()) && s.postBtnDisabled]}
            onPress={handlePost}
            disabled={isPosting || (!media && !caption.trim())}
          >
            {isPosting ? (
              <ActivityIndicator size="small" color="#FFF" />
            ) : (
              <Text style={s.postBtnText}>Drop</Text>
            )}
          </TouchableOpacity>
        </View>

        {/* Upload progress */}
        {isPosting && uploadProgress ? (
          <View style={s.progressBar}>
            <ActivityIndicator size="small" color="#F97316" />
            <Text style={s.progressText}>{uploadProgress}</Text>
          </View>
        ) : null}

        {/* Media preview */}
        {media ? (
          <View style={s.mediaPreview}>
            <Image source={{ uri: media.uri }} style={s.mediaImage} resizeMode="cover" />
            {media.type === 'video' && (
              <View style={s.videoBadge}>
                <Ionicons name="videocam" size={14} color="#FFF" />
                <Text style={s.videoBadgeText}>Video</Text>
              </View>
            )}
            <TouchableOpacity style={s.mediaRemove} onPress={() => { setMedia(null); setStep('capture'); }}>
              <Ionicons name="close" size={16} color="#FFF" />
            </TouchableOpacity>
          </View>
        ) : null}

        {/* Caption */}
        <View style={s.captionArea}>
          <View style={s.captionRow}>
            <View style={s.composeAvatar}>
              {user?.profile_image ? (
                <Image source={{ uri: user.profile_image }} style={{ width: '100%', height: '100%', borderRadius: 20 }} />
              ) : (
                <Text style={s.composeAvatarText}>{(user?.full_name || 'U')[0]}</Text>
              )}
            </View>
            <TextInput
              style={s.captionInput}
              placeholder="What's happening right now?"
              placeholderTextColor="#BBB"
              value={caption}
              onChangeText={setCaption}
              multiline
              maxLength={500}
              autoFocus={!media}
            />
          </View>
        </View>

        {/* Location pill */}
        <View style={s.optionsRow}>
          <TouchableOpacity style={s.locPill} onPress={detectLocation}>
            <Ionicons name="location-outline" size={16} color={location ? '#DC2626' : '#999'} />
            <Text style={[s.locPillText, location && { color: '#1A1A1A' }]}>
              {location || 'Add location'}
            </Text>
          </TouchableOpacity>
          {!media && (
            <TouchableOpacity style={s.addMediaBtn} onPress={pickFromGallery}>
              <Ionicons name="image-outline" size={18} color="#7C3AED" />
            </TouchableOpacity>
          )}
        </View>
      </View>
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0A0A0A' },

  // Capture step
  captureHeader: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 16, paddingVertical: 12,
  },
  closeBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: 'rgba(255,255,255,0.1)', justifyContent: 'center', alignItems: 'center' },
  captureTitle: { fontSize: 17, fontWeight: '700', color: '#FFF' },

  captureBody: { flex: 1, justifyContent: 'center', alignItems: 'center', paddingHorizontal: 40 },
  captureIcon: {
    width: 96, height: 96, borderRadius: 48,
    backgroundColor: 'rgba(249,115,22,0.12)', justifyContent: 'center', alignItems: 'center', marginBottom: 24,
  },
  captureHeadline: { fontSize: 26, fontWeight: '800', color: '#FFF', marginBottom: 8, textAlign: 'center' },
  captureSub: { fontSize: 15, color: 'rgba(255,255,255,0.5)', textAlign: 'center', lineHeight: 22 },

  captureActions: { flexDirection: 'row', justifyContent: 'space-around', paddingHorizontal: 20 },
  captureBtn: { alignItems: 'center', gap: 8 },
  captureBtnIconWrap: {
    width: 64, height: 64, borderRadius: 32,
    backgroundColor: '#F97316', justifyContent: 'center', alignItems: 'center',
  },
  captureBtnText: { fontSize: 13, fontWeight: '700', color: '#FFF' },
  captureBtnSub: { fontSize: 11, color: 'rgba(255,255,255,0.4)' },

  // Compose step
  composeHeader: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 16, paddingVertical: 12,
    borderBottomWidth: 1, borderBottomColor: '#ECEAE3',
  },
  composeTitle: { fontSize: 17, fontWeight: '700', color: '#1A1A1A' },
  postBtn: {
    backgroundColor: '#F97316', paddingHorizontal: 20, paddingVertical: 10, borderRadius: 20, minWidth: 70, alignItems: 'center',
  },
  postBtnDisabled: { opacity: 0.4 },
  postBtnText: { color: '#FFF', fontSize: 14, fontWeight: '700' },

  // Progress
  progressBar: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    paddingHorizontal: 16, paddingVertical: 8,
    backgroundColor: '#FFF7ED',
  },
  progressText: { fontSize: 13, color: '#F97316', fontWeight: '500' },

  // Media preview
  mediaPreview: {
    width: SW, height: SW * 0.65, backgroundColor: '#0A0A0A', position: 'relative',
  },
  mediaImage: { width: '100%', height: '100%' },
  videoBadge: {
    position: 'absolute', bottom: 12, left: 12,
    flexDirection: 'row', alignItems: 'center', gap: 4,
    backgroundColor: 'rgba(0,0,0,0.6)', paddingHorizontal: 8, paddingVertical: 4, borderRadius: 10,
  },
  videoBadgeText: { fontSize: 11, fontWeight: '600', color: '#FFF' },
  mediaRemove: {
    position: 'absolute', top: 12, right: 12,
    width: 32, height: 32, borderRadius: 16,
    backgroundColor: 'rgba(0,0,0,0.5)', justifyContent: 'center', alignItems: 'center',
  },

  // Caption
  captionArea: { paddingHorizontal: 16, paddingTop: 16 },
  captionRow: { flexDirection: 'row', alignItems: 'flex-start' },
  composeAvatar: {
    width: 40, height: 40, borderRadius: 20, overflow: 'hidden',
    backgroundColor: '#50C8A8', justifyContent: 'center', alignItems: 'center', marginRight: 12,
  },
  composeAvatarText: { color: '#FFF', fontSize: 16, fontWeight: '700' },
  captionInput: {
    flex: 1, fontSize: 17, color: '#1A1A1A', lineHeight: 24,
    minHeight: 80, textAlignVertical: 'top',
  },

  // Options
  optionsRow: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    paddingHorizontal: 16, paddingTop: 12,
  },
  locPill: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    backgroundColor: '#F5F0EB', paddingHorizontal: 12, paddingVertical: 8, borderRadius: 16,
  },
  locPillText: { fontSize: 13, fontWeight: '500', color: '#999' },
  addMediaBtn: {
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: '#F3ECFF', justifyContent: 'center', alignItems: 'center',
  },
});
