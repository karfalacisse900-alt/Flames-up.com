import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  Image,
  ScrollView,
  KeyboardAvoidingView,
  Platform,
  ActivityIndicator,
  Alert,
  FlatList,
  Dimensions,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import { colors, spacing, borderRadius, shadows } from '../src/utils/theme';
import { useAuthStore } from '../src/store/authStore';
import api from '../src/api/client';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const MAX_MEDIA = 10;

export default function CreatePostScreen() {
  const router = useRouter();
  const { user } = useAuthStore();
  const [content, setContent] = useState('');
  const [media, setMedia] = useState<{ uri: string; type: string; base64?: string }[]>([]);
  const [location, setLocation] = useState('');
  const [isPosting, setIsPosting] = useState(false);
  const [visibility, setVisibility] = useState('Everyone');
  const [postType, setPostType] = useState<'lifestyle' | 'check_in' | 'question'>('lifestyle');

  const POST_TYPES = [
    { id: 'lifestyle' as const, label: 'Lifestyle', icon: 'sparkles' as const, color: '#6366F1' },
    { id: 'check_in' as const, label: 'Check-In', icon: 'location' as const, color: '#10B981' },
    { id: 'question' as const, label: 'Question', icon: 'help-circle' as const, color: '#F59E0B' },
  ];

  const pickImages = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images', 'videos'],
      allowsMultipleSelection: true,
      quality: 0.7,
      base64: true,
      selectionLimit: MAX_MEDIA - media.length,
    });

    if (!result.canceled && result.assets) {
      const newMedia = result.assets.map((asset) => ({
        uri: asset.uri,
        type: asset.type || 'image',
        base64: asset.base64 ? `data:image/jpeg;base64,${asset.base64}` : undefined,
      }));
      setMedia((prev) => [...prev, ...newMedia].slice(0, MAX_MEDIA));
    }
  };

  const takePhoto = async () => {
    const { status } = await ImagePicker.requestCameraPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Permission needed', 'Camera access is required to take photos');
      return;
    }

    const result = await ImagePicker.launchCameraAsync({
      quality: 0.7,
      base64: true,
    });

    if (!result.canceled && result.assets[0]) {
      const asset = result.assets[0];
      setMedia((prev) => [
        ...prev,
        {
          uri: asset.uri,
          type: 'image',
          base64: asset.base64 ? `data:image/jpeg;base64,${asset.base64}` : undefined,
        },
      ].slice(0, MAX_MEDIA));
    }
  };

  const removeMedia = (index: number) => {
    setMedia((prev) => prev.filter((_, i) => i !== index));
  };

  const handlePost = async () => {
    if (!content.trim() && media.length === 0) {
      Alert.alert('Error', 'Please write something or add media');
      return;
    }

    setIsPosting(true);
    try {
      // Upload images to Cloudflare Images
      const uploadedUrls: string[] = [];
      const mediaTypesList: string[] = [];
      for (const m of media) {
        const imageData = m.base64 || m.uri;
        if (imageData) {
          try {
            const res = await api.post('/upload/image', { image: imageData });
            uploadedUrls.push(res.data?.url || imageData);
          } catch {
            uploadedUrls.push(imageData); // fallback to base64
          }
        }
        mediaTypesList.push(m.type || 'image');
      }
      
      await api.post('/posts', {
        content: content.trim(),
        image: uploadedUrls[0] || null,
        images: uploadedUrls.length > 0 ? uploadedUrls : undefined,
        media_types: mediaTypesList.length > 0 ? mediaTypesList : undefined,
        location: location.trim() || null,
        post_type: postType,
      });
      router.back();
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.detail || 'Could not create post');
    } finally {
      setIsPosting(false);
    }
  };

  const getPlaceholder = () => {
    switch (postType) {
      case 'question': return 'Ask a question or request a recommendation...';
      case 'check_in': return 'What\'s happening at this spot?';
      default: return 'Share a tip, thought or update with the community...';
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={{ flex: 1 }}
      >
        {/* Header */}
        <View style={styles.header}>
          <TouchableOpacity onPress={() => router.back()} style={styles.headerLeft}>
            <Ionicons name="close" size={24} color={colors.textPrimary} />
          </TouchableOpacity>
          <Text style={styles.headerTitle}>Create Post</Text>
          <TouchableOpacity
            style={[styles.postButton, (!content.trim() && media.length === 0 || isPosting) && styles.postButtonDisabled]}
            onPress={handlePost}
            disabled={(!content.trim() && media.length === 0) || isPosting}
          >
            {isPosting ? (
              <ActivityIndicator size="small" color="#FFFFFF" />
            ) : (
              <Text style={styles.postButtonText}>Post</Text>
            )}
          </TouchableOpacity>
        </View>

        <ScrollView style={styles.scrollContent} keyboardShouldPersistTaps="handled">
          {/* Post Type Selector */}
          <View style={styles.typeRow}>
            {POST_TYPES.map((type) => (
              <TouchableOpacity
                key={type.id}
                style={[
                  styles.typeChip,
                  postType === type.id && { backgroundColor: type.color + '18', borderColor: type.color + '50' },
                ]}
                onPress={() => setPostType(type.id)}
              >
                <Ionicons
                  name={type.icon}
                  size={15}
                  color={postType === type.id ? type.color : colors.textHint}
                />
                <Text style={[styles.typeChipText, postType === type.id && { color: type.color, fontWeight: '700' }]}>
                  {type.label}
                </Text>
              </TouchableOpacity>
            ))}
          </View>

          {/* Question hint */}
          {postType === 'question' && (
            <View style={styles.hintBanner}>
              <Ionicons name="help-circle" size={18} color="#F59E0B" />
              <Text style={styles.hintBannerText}>Ask the community for recommendations or tips</Text>
            </View>
          )}

          {/* User row */}
          <View style={styles.userRow}>
            <View style={styles.avatar}>
              {user?.profile_image ? (
                <Image source={{ uri: user.profile_image }} style={{ width: '100%', height: '100%' }} />
              ) : (
                <View style={styles.avatarFallback}>
                  <Text style={styles.avatarFallbackText}>
                    {(user?.full_name || 'U')[0].toUpperCase()}
                  </Text>
                </View>
              )}
            </View>
            <View>
              <Text style={styles.userName}>{user?.full_name}</Text>
              <TouchableOpacity style={styles.visibilityRow}>
                <Ionicons name="globe-outline" size={12} color={colors.textSecondary} />
                <Text style={styles.visibilityText}>{visibility}</Text>
                <Ionicons name="chevron-down" size={12} color={colors.textSecondary} />
              </TouchableOpacity>
            </View>
          </View>

          {/* Content Input */}
          <TextInput
            style={styles.contentInput}
            placeholder={getPlaceholder()}
            placeholderTextColor={colors.textHint}
            value={content}
            onChangeText={setContent}
            multiline
            maxLength={2000}
            autoFocus
          />

          {/* Media Preview Grid */}
          {media.length > 0 && (
            <View style={styles.mediaGrid}>
              {media.map((item, index) => (
                <View key={index} style={styles.mediaItem}>
                  <Image source={{ uri: item.uri }} style={styles.mediaImage} />
                  {item.type === 'video' && (
                    <View style={styles.videoOverlay}>
                      <Ionicons name="play" size={24} color="#FFFFFF" />
                    </View>
                  )}
                  <TouchableOpacity
                    style={styles.removeMedia}
                    onPress={() => removeMedia(index)}
                  >
                    <Ionicons name="close" size={14} color="#FFFFFF" />
                  </TouchableOpacity>
                </View>
              ))}
              {media.length < MAX_MEDIA && (
                <TouchableOpacity style={styles.addMoreMedia} onPress={pickImages}>
                  <Ionicons name="add" size={24} color={colors.fashionHint} />
                  <Text style={styles.addMoreText}>+More</Text>
                </TouchableOpacity>
              )}
            </View>
          )}

          {/* Location */}
          <View style={styles.locationRow}>
            <Ionicons name="location-outline" size={20} color={colors.textHint} />
            <TextInput
              style={styles.locationInput}
              placeholder="Add location (optional)"
              placeholderTextColor={colors.textHint}
              value={location}
              onChangeText={setLocation}
            />
          </View>
        </ScrollView>

        {/* Bottom Action Bar */}
        <View style={styles.bottomBar}>
          <TouchableOpacity style={styles.actionBtn} onPress={pickImages}>
            <Ionicons name="image-outline" size={24} color={colors.accentSecondary} />
          </TouchableOpacity>
          <TouchableOpacity style={styles.actionBtn} onPress={takePhoto}>
            <Ionicons name="camera-outline" size={24} color={colors.info} />
          </TouchableOpacity>
          <TouchableOpacity style={styles.actionBtn}>
            <Ionicons name="document-outline" size={24} color={colors.warning} />
          </TouchableOpacity>
          <View style={{ flex: 1 }} />
          <Text style={styles.charCount}>{content.length}/2000</Text>
          <TouchableOpacity>
            <Ionicons name="ellipsis-horizontal" size={22} color={colors.textHint} />
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bgCard,
  },
  // Header
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderSubtle,
  },
  headerLeft: {
    padding: 4,
  },
  headerTitle: {
    fontSize: 17,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  postButton: {
    backgroundColor: colors.accentPrimary,
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 20,
    minWidth: 70,
    alignItems: 'center',
  },
  postButtonDisabled: {
    opacity: 0.4,
  },
  postButtonText: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '700',
  },
  // Content
  scrollContent: {
    flex: 1,
    padding: 16,
  },
  typeRow: {
    flexDirection: 'row' as const,
    gap: 8,
    marginBottom: 16,
  },
  typeChip: {
    flex: 1,
    flexDirection: 'row' as const,
    alignItems: 'center' as const,
    justifyContent: 'center' as const,
    gap: 5,
    paddingVertical: 10,
    borderRadius: 16,
    backgroundColor: colors.bgSubtle,
    borderWidth: 1.5,
    borderColor: colors.borderLight,
  },
  typeChipText: {
    fontSize: 12,
    fontWeight: '600' as const,
    color: colors.textHint,
  },
  hintBanner: {
    flexDirection: 'row' as const,
    alignItems: 'center' as const,
    gap: 8,
    marginBottom: 12,
    padding: 10,
    backgroundColor: '#FEF3C7',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#FDE68A',
  },
  hintBannerText: {
    fontSize: 12,
    color: '#92400E',
    flex: 1,
    lineHeight: 17,
  },
  userRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 20,
  },
  avatar: {
    width: 48,
    height: 48,
    borderRadius: 24,
    overflow: 'hidden',
    marginRight: 12,
  },
  avatarFallback: {
    width: '100%',
    height: '100%',
    backgroundColor: colors.avatarTeal,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarFallbackText: {
    color: '#FFFFFF',
    fontSize: 20,
    fontWeight: '700',
  },
  userName: {
    fontSize: 16,
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
  contentInput: {
    fontSize: 17,
    color: colors.textPrimary,
    lineHeight: 26,
    minHeight: 120,
    textAlignVertical: 'top',
  },
  // Media Grid
  mediaGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginTop: 16,
  },
  mediaItem: {
    width: (SCREEN_WIDTH - 32 - 16) / 3,
    aspectRatio: 1,
    borderRadius: 16,
    overflow: 'hidden',
  },
  mediaImage: {
    width: '100%',
    height: '100%',
  },
  videoOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.3)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  removeMedia: {
    position: 'absolute',
    top: 4,
    right: 4,
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: 'rgba(0,0,0,0.6)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  addMoreMedia: {
    width: (SCREEN_WIDTH - 32 - 16) / 3,
    aspectRatio: 1,
    borderRadius: 16,
    borderWidth: 2,
    borderStyle: 'dashed',
    borderColor: colors.fashionBorder,
    backgroundColor: colors.fashionCard,
    justifyContent: 'center',
    alignItems: 'center',
  },
  addMoreText: {
    fontSize: 10,
    color: colors.fashionHint,
    marginTop: 4,
  },
  // Location
  locationRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 20,
    paddingTop: 16,
    borderTopWidth: 1,
    borderTopColor: colors.borderSubtle,
  },
  locationInput: {
    flex: 1,
    fontSize: 15,
    color: colors.textPrimary,
    marginLeft: 8,
  },
  // Bottom Bar
  bottomBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderTopWidth: 1,
    borderTopColor: colors.borderSubtle,
    gap: 8,
  },
  actionBtn: {
    padding: 8,
  },
  charCount: {
    fontSize: 13,
    color: colors.textHint,
    marginRight: 8,
  },
});
