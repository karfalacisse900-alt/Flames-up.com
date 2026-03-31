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
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import { colors, spacing, borderRadius } from '../src/utils/theme';
import { useAuthStore } from '../src/store/authStore';
import api from '../src/api/client';

export default function CreatePostScreen() {
  const router = useRouter();
  const { user } = useAuthStore();
  const [content, setContent] = useState('');
  const [image, setImage] = useState<string | null>(null);
  const [location, setLocation] = useState('');
  const [isPosting, setIsPosting] = useState(false);

  const pickImage = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsEditing: true,
      aspect: [4, 3],
      quality: 0.7,
      base64: true,
    });

    if (!result.canceled && result.assets[0].base64) {
      setImage(`data:image/jpeg;base64,${result.assets[0].base64}`);
    }
  };

  const handlePost = async () => {
    if (!content.trim()) {
      Alert.alert('Error', 'Please write something');
      return;
    }

    setIsPosting(true);
    try {
      await api.post('/posts', {
        content: content.trim(),
        image: image,
        location: location.trim() || null,
      });
      router.back();
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.detail || 'Could not create post');
    } finally {
      setIsPosting(false);
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.keyboardView}
      >
        {/* Header */}
        <View style={styles.header}>
          <TouchableOpacity onPress={() => router.back()}>
            <Text style={styles.cancelText}>Cancel</Text>
          </TouchableOpacity>
          <Text style={styles.headerTitle}>New Post</Text>
          <TouchableOpacity
            style={[styles.postButton, (!content.trim() || isPosting) && styles.postButtonDisabled]}
            onPress={handlePost}
            disabled={!content.trim() || isPosting}
          >
            {isPosting ? (
              <ActivityIndicator size="small" color={colors.textInverse} />
            ) : (
              <Text style={styles.postButtonText}>Post</Text>
            )}
          </TouchableOpacity>
        </View>

        <ScrollView style={styles.content} keyboardShouldPersistTaps="handled">
          {/* User Info */}
          <View style={styles.userRow}>
            {user?.profile_image ? (
              <Image source={{ uri: user.profile_image }} style={styles.avatar} />
            ) : (
              <View style={styles.avatarPlaceholder}>
                <Text style={styles.avatarText}>{user?.username[0].toUpperCase()}</Text>
              </View>
            )}
            <View>
              <Text style={styles.userName}>{user?.full_name}</Text>
              <Text style={styles.userHandle}>@{user?.username}</Text>
            </View>
          </View>

          {/* Content Input */}
          <TextInput
            style={styles.input}
            placeholder="What's on your mind?"
            placeholderTextColor={colors.textTertiary}
            value={content}
            onChangeText={setContent}
            multiline
            maxLength={500}
            autoFocus
          />

          {/* Image Preview */}
          {image && (
            <View style={styles.imagePreview}>
              <Image source={{ uri: image }} style={styles.previewImage} />
              <TouchableOpacity
                style={styles.removeImageButton}
                onPress={() => setImage(null)}
              >
                <Ionicons name="close-circle" size={28} color={colors.textInverse} />
              </TouchableOpacity>
            </View>
          )}

          {/* Location Input */}
          <View style={styles.locationContainer}>
            <Ionicons name="location-outline" size={20} color={colors.textTertiary} />
            <TextInput
              style={styles.locationInput}
              placeholder="Add location (optional)"
              placeholderTextColor={colors.textTertiary}
              value={location}
              onChangeText={setLocation}
            />
          </View>
        </ScrollView>

        {/* Bottom Actions */}
        <View style={styles.bottomActions}>
          <TouchableOpacity style={styles.actionButton} onPress={pickImage}>
            <Ionicons name="image-outline" size={24} color={colors.primary} />
            <Text style={styles.actionText}>Photo</Text>
          </TouchableOpacity>
          <Text style={styles.charCount}>{content.length}/500</Text>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  keyboardView: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderLight,
  },
  cancelText: {
    fontSize: 16,
    color: colors.textSecondary,
  },
  headerTitle: {
    fontSize: 17,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  postButton: {
    backgroundColor: colors.primary,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.xs,
    borderRadius: borderRadius.full,
    minWidth: 60,
    alignItems: 'center',
  },
  postButtonDisabled: {
    opacity: 0.5,
  },
  postButtonText: {
    color: colors.textInverse,
    fontSize: 15,
    fontWeight: '600',
  },
  content: {
    flex: 1,
    padding: spacing.md,
  },
  userRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: spacing.md,
  },
  avatar: {
    width: 44,
    height: 44,
    borderRadius: 22,
    marginRight: spacing.sm,
  },
  avatarPlaceholder: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: spacing.sm,
  },
  avatarText: {
    color: colors.textInverse,
    fontSize: 18,
    fontWeight: '600',
  },
  userName: {
    fontSize: 15,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  userHandle: {
    fontSize: 13,
    color: colors.textSecondary,
  },
  input: {
    fontSize: 17,
    color: colors.textPrimary,
    lineHeight: 24,
    minHeight: 100,
    textAlignVertical: 'top',
  },
  imagePreview: {
    marginTop: spacing.md,
    borderRadius: borderRadius.md,
    overflow: 'hidden',
    position: 'relative',
  },
  previewImage: {
    width: '100%',
    height: 200,
    borderRadius: borderRadius.md,
  },
  removeImageButton: {
    position: 'absolute',
    top: spacing.sm,
    right: spacing.sm,
  },
  locationContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: spacing.md,
    paddingTop: spacing.md,
    borderTopWidth: 1,
    borderTopColor: colors.borderLight,
  },
  locationInput: {
    flex: 1,
    fontSize: 15,
    color: colors.textPrimary,
    marginLeft: spacing.sm,
  },
  bottomActions: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderTopWidth: 1,
    borderTopColor: colors.borderLight,
  },
  actionButton: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  actionText: {
    fontSize: 14,
    color: colors.primary,
    marginLeft: spacing.xs,
    fontWeight: '500',
  },
  charCount: {
    fontSize: 13,
    color: colors.textTertiary,
  },
});
