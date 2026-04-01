import React, { useState, useEffect } from 'react';
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
  Dimensions,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import * as Location from 'expo-location';
import { colors, shadows } from '../src/utils/theme';
import { useAuthStore } from '../src/store/authStore';
import api from '../src/api/client';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const MAX_MEDIA = 10;

const POST_TYPES = [
  { id: 'check_in', label: 'Check-In', icon: 'location', color: '#10B981' },
  { id: 'lifestyle', label: 'Lifestyle', icon: 'sparkles', color: '#6366F1' },
  { id: 'question', label: 'Question', icon: 'help-circle', color: '#F59E0B' },
];

export default function CheckInPostScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{
    placeId?: string;
    placeName?: string;
    placeLat?: string;
    placeLng?: string;
    placePhoto?: string;
  }>();

  const { user } = useAuthStore();
  const [content, setContent] = useState('');
  const [media, setMedia] = useState<{ uri: string; type: string; base64?: string }[]>([]);
  const [isPosting, setIsPosting] = useState(false);
  const [postType, setPostType] = useState<string>(params.placeId ? 'check_in' : 'lifestyle');
  const [isCheckingLocation, setIsCheckingLocation] = useState(false);
  const [proximityVerified, setProximityVerified] = useState(false);
  const [distance, setDistance] = useState<number | null>(null);
  const [userLocation, setUserLocation] = useState<{ lat: number; lng: number } | null>(null);

  // Check proximity on mount if place is provided
  useEffect(() => {
    if (params.placeId && params.placeLat && params.placeLng) {
      verifyProximity();
    }
  }, []);

  const verifyProximity = async () => {
    setIsCheckingLocation(true);
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') {
        Alert.alert('Location Required', 'Please enable location services to check in.');
        setIsCheckingLocation(false);
        return;
      }

      const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High });
      const userLoc = { lat: loc.coords.latitude, lng: loc.coords.longitude };
      setUserLocation(userLoc);

      const response = await api.post('/places/verify-proximity', {
        user_lat: userLoc.lat,
        user_lng: userLoc.lng,
        place_lat: parseFloat(params.placeLat || '0'),
        place_lng: parseFloat(params.placeLng || '0'),
      });

      setProximityVerified(response.data.is_near);
      setDistance(response.data.distance_meters);

      if (!response.data.is_near) {
        // Don't block, just inform
      }
    } catch (error) {
      console.log('Proximity check error:', error);
    } finally {
      setIsCheckingLocation(false);
    }
  };

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
    const result = await ImagePicker.launchCameraAsync({ quality: 0.7, base64: true });
    if (!result.canceled && result.assets[0]) {
      const asset = result.assets[0];
      setMedia((prev) => [
        ...prev,
        { uri: asset.uri, type: 'image', base64: asset.base64 ? `data:image/jpeg;base64,${asset.base64}` : undefined },
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

    // For check-in posts, verify proximity
    if (postType === 'check_in' && params.placeId && !proximityVerified) {
      Alert.alert(
        'Not Near This Place',
        `You need to be within 200 meters of ${params.placeName} to check in.`,
        [
          { text: 'Get Directions', onPress: () => openDirections() },
          { text: 'Post Without Tag', onPress: () => submitPost('lifestyle') },
          { text: 'Cancel', style: 'cancel' },
        ]
      );
      return;
    }

    await submitPost(postType);
  };

  const submitPost = async (type: string) => {
    setIsPosting(true);
    try {
      const imagesList = media.map((m) => m.base64 || m.uri).filter(Boolean);
      const postData: any = {
        content: content.trim(),
        image: imagesList[0] || null,
        images: imagesList.length > 0 ? imagesList : undefined,
        post_type: type,
      };

      // Add place data for check-in posts
      if (type === 'check_in' && params.placeId) {
        postData.place_id = params.placeId;
        postData.place_name = params.placeName;
        postData.place_lat = parseFloat(params.placeLat || '0');
        postData.place_lng = parseFloat(params.placeLng || '0');
        postData.location = params.placeName;
      }

      await api.post('/posts', postData);
      router.back();
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.detail || 'Could not create post');
    } finally {
      setIsPosting(false);
    }
  };

  const openDirections = () => {
    if (params.placeLat && params.placeLng) {
      const url = Platform.select({
        ios: `maps:0,0?q=${params.placeLat},${params.placeLng}`,
        android: `geo:${params.placeLat},${params.placeLng}?q=${params.placeLat},${params.placeLng}(${params.placeName})`,
        default: `https://www.google.com/maps/dir/?api=1&destination=${params.placeLat},${params.placeLng}`,
      });
      if (url) {
        import('react-native').then(({ Linking }) => Linking.openURL(url));
      }
    }
  };

  const getPlaceholder = () => {
    switch (postType) {
      case 'check_in': return `What's happening at ${params.placeName || 'this place'}?`;
      case 'question': return 'Ask a question or request a recommendation...';
      default: return 'Share a tip, thought or update...';
    }
  };

  return (
    <SafeAreaView style={styles.container} edges={['top', 'bottom']}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={{ flex: 1 }}
      >
        {/* Header */}
        <View style={styles.header}>
          <TouchableOpacity onPress={() => router.back()} style={styles.headerBtn}>
            <Ionicons name="close" size={24} color={colors.textPrimary} />
          </TouchableOpacity>
          <Text style={styles.headerTitle}>New Post</Text>
          <TouchableOpacity
            style={[styles.postButton, (!content.trim() && media.length === 0 || isPosting) && { opacity: 0.4 }]}
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

        <ScrollView style={{ flex: 1 }} keyboardShouldPersistTaps="handled">
          {/* Post Type Selector */}
          <View style={styles.typeRow}>
            {POST_TYPES.map((type) => (
              <TouchableOpacity
                key={type.id}
                style={[styles.typeChip, postType === type.id && { backgroundColor: type.color + '18', borderColor: type.color + '50' }]}
                onPress={() => setPostType(type.id)}
              >
                <Ionicons
                  name={type.icon as any}
                  size={16}
                  color={postType === type.id ? type.color : colors.textHint}
                />
                <Text style={[styles.typeChipText, postType === type.id && { color: type.color, fontWeight: '700' }]}>
                  {type.label}
                </Text>
              </TouchableOpacity>
            ))}
          </View>

          {/* Check-In Place Card */}
          {postType === 'check_in' && params.placeName && (
            <View style={styles.placeCard}>
              <View style={styles.placeCardLeft}>
                <View style={styles.placeIcon}>
                  <Ionicons name="location" size={18} color="#10B981" />
                </View>
                <View style={{ flex: 1 }}>
                  <Text style={styles.placeCardName}>{params.placeName}</Text>
                  {isCheckingLocation ? (
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: 2 }}>
                      <ActivityIndicator size="small" color={colors.accentPrimary} />
                      <Text style={styles.placeCardStatus}>Verifying location...</Text>
                    </View>
                  ) : proximityVerified ? (
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 2 }}>
                      <Ionicons name="checkmark-circle" size={14} color="#10B981" />
                      <Text style={[styles.placeCardStatus, { color: '#10B981' }]}>
                        Verified! You're here ({distance ? `${Math.round(distance)}m` : 'nearby'})
                      </Text>
                    </View>
                  ) : distance !== null ? (
                    <View style={{ marginTop: 4 }}>
                      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
                        <Ionicons name="alert-circle" size={14} color="#F59E0B" />
                        <Text style={[styles.placeCardStatus, { color: '#F59E0B' }]}>
                          You're {distance >= 1000 ? `${(distance / 1000).toFixed(1)}km` : `${Math.round(distance)}m`} away
                        </Text>
                      </View>
                      <View style={{ flexDirection: 'row', gap: 8, marginTop: 8 }}>
                        <TouchableOpacity style={styles.directionBtn} onPress={openDirections}>
                          <Ionicons name="navigate" size={12} color={colors.accentPrimary} />
                          <Text style={styles.directionBtnText}>Get Directions</Text>
                        </TouchableOpacity>
                        <TouchableOpacity style={styles.retryBtn} onPress={verifyProximity}>
                          <Ionicons name="refresh" size={12} color={colors.textSecondary} />
                          <Text style={styles.retryBtnText}>Retry</Text>
                        </TouchableOpacity>
                      </View>
                    </View>
                  ) : null}
                </View>
              </View>
            </View>
          )}

          {/* Question banner */}
          {postType === 'question' && (
            <View style={styles.questionBanner}>
              <Ionicons name="help-circle" size={20} color="#F59E0B" />
              <Text style={styles.questionBannerText}>
                Ask a question or request a recommendation from the community
              </Text>
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
              <View style={styles.visibilityRow}>
                <Ionicons name="globe-outline" size={12} color={colors.textSecondary} />
                <Text style={styles.visibilityText}>Everyone</Text>
              </View>
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

          {/* Media Preview */}
          {media.length > 0 && (
            <View style={styles.mediaGrid}>
              {media.map((item, index) => (
                <View key={index} style={styles.mediaItem}>
                  <Image source={{ uri: item.uri }} style={styles.mediaImage} />
                  <TouchableOpacity style={styles.removeMedia} onPress={() => removeMedia(index)}>
                    <Ionicons name="close" size={14} color="#FFFFFF" />
                  </TouchableOpacity>
                </View>
              ))}
              {media.length < MAX_MEDIA && (
                <TouchableOpacity style={styles.addMoreMedia} onPress={pickImages}>
                  <Ionicons name="add" size={24} color={colors.textHint} />
                  <Text style={styles.addMoreText}>Add</Text>
                </TouchableOpacity>
              )}
            </View>
          )}
        </ScrollView>

        {/* Bottom Action Bar */}
        <View style={styles.bottomBar}>
          <TouchableOpacity style={styles.actionBtn} onPress={pickImages}>
            <Ionicons name="image-outline" size={22} color={colors.accentSecondary} />
          </TouchableOpacity>
          <TouchableOpacity style={styles.actionBtn} onPress={takePhoto}>
            <Ionicons name="camera-outline" size={22} color={colors.info} />
          </TouchableOpacity>
          <View style={{ flex: 1 }} />
          <Text style={styles.charCount}>{content.length}/2000</Text>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bgCard },
  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 16, paddingVertical: 12,
    borderBottomWidth: 1, borderBottomColor: colors.borderSubtle,
  },
  headerBtn: { padding: 4 },
  headerTitle: { fontSize: 17, fontWeight: '700', color: colors.textPrimary },
  postButton: {
    backgroundColor: colors.accentPrimary, paddingHorizontal: 20, paddingVertical: 10,
    borderRadius: 20, minWidth: 70, alignItems: 'center',
  },
  postButtonText: { color: '#FFFFFF', fontSize: 14, fontWeight: '700' },
  // Post Type Selector
  typeRow: {
    flexDirection: 'row', paddingHorizontal: 16, paddingVertical: 12, gap: 8,
  },
  typeChip: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6,
    paddingVertical: 10, borderRadius: 16,
    backgroundColor: colors.bgSubtle, borderWidth: 1.5, borderColor: colors.borderLight,
  },
  typeChipText: { fontSize: 13, fontWeight: '600', color: colors.textHint },
  // Place Card
  placeCard: {
    marginHorizontal: 16, marginBottom: 12, padding: 14,
    backgroundColor: '#E8F5E9', borderRadius: 16, borderWidth: 1, borderColor: '#A5D6A7',
  },
  placeCardLeft: { flexDirection: 'row', alignItems: 'flex-start', gap: 12 },
  placeIcon: {
    width: 36, height: 36, borderRadius: 12,
    backgroundColor: '#C8E6C9', justifyContent: 'center', alignItems: 'center',
  },
  placeCardName: { fontSize: 15, fontWeight: '700', color: '#1B5E20' },
  placeCardStatus: { fontSize: 12, color: colors.textSecondary },
  directionBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 4,
    paddingHorizontal: 10, paddingVertical: 6, borderRadius: 12,
    backgroundColor: colors.accentPrimaryLight,
  },
  directionBtnText: { fontSize: 12, fontWeight: '600', color: colors.accentPrimary },
  retryBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 4,
    paddingHorizontal: 10, paddingVertical: 6, borderRadius: 12,
    backgroundColor: colors.bgSubtle,
  },
  retryBtnText: { fontSize: 12, fontWeight: '600', color: colors.textSecondary },
  // Question Banner
  questionBanner: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    marginHorizontal: 16, marginBottom: 12, padding: 12,
    backgroundColor: '#FEF3C7', borderRadius: 14, borderWidth: 1, borderColor: '#FDE68A',
  },
  questionBannerText: { fontSize: 13, color: '#92400E', flex: 1, lineHeight: 18 },
  // User Row
  userRow: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, marginBottom: 12 },
  avatar: { width: 44, height: 44, borderRadius: 22, overflow: 'hidden', marginRight: 12 },
  avatarFallback: {
    width: '100%', height: '100%', backgroundColor: colors.avatarTeal,
    justifyContent: 'center', alignItems: 'center',
  },
  avatarFallbackText: { color: '#FFFFFF', fontSize: 18, fontWeight: '700' },
  userName: { fontSize: 15, fontWeight: '700', color: colors.textPrimary },
  visibilityRow: { flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 2 },
  visibilityText: { fontSize: 12, color: colors.textSecondary, fontWeight: '500' },
  // Content
  contentInput: {
    fontSize: 16, color: colors.textPrimary, lineHeight: 24,
    minHeight: 100, textAlignVertical: 'top', paddingHorizontal: 16, marginBottom: 12,
  },
  // Media
  mediaGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, paddingHorizontal: 16, marginBottom: 16 },
  mediaItem: {
    width: (SCREEN_WIDTH - 32 - 16) / 3, aspectRatio: 1,
    borderRadius: 14, overflow: 'hidden',
  },
  mediaImage: { width: '100%', height: '100%' },
  removeMedia: {
    position: 'absolute', top: 4, right: 4, width: 24, height: 24,
    borderRadius: 12, backgroundColor: 'rgba(0,0,0,0.6)',
    justifyContent: 'center', alignItems: 'center',
  },
  addMoreMedia: {
    width: (SCREEN_WIDTH - 32 - 16) / 3, aspectRatio: 1,
    borderRadius: 14, borderWidth: 2, borderStyle: 'dashed', borderColor: colors.borderLight,
    backgroundColor: colors.bgSubtle, justifyContent: 'center', alignItems: 'center',
  },
  addMoreText: { fontSize: 11, color: colors.textHint, marginTop: 2 },
  // Bottom bar
  bottomBar: {
    flexDirection: 'row', alignItems: 'center',
    paddingHorizontal: 16, paddingVertical: 12,
    borderTopWidth: 1, borderTopColor: colors.borderSubtle, gap: 12,
  },
  actionBtn: { padding: 8 },
  charCount: { fontSize: 12, color: colors.textHint },
});
