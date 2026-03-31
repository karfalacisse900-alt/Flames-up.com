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

const COLORS = [
  '#6366f1',
  '#8b5cf6',
  '#ec4899',
  '#ef4444',
  '#f59e0b',
  '#10b981',
  '#3b82f6',
  '#1f2937',
];

export default function CreateStatusScreen() {
  const router = useRouter();
  const { user } = useAuthStore();
  const [content, setContent] = useState('');
  const [image, setImage] = useState<string | null>(null);
  const [backgroundColor, setBackgroundColor] = useState(COLORS[0]);
  const [isPosting, setIsPosting] = useState(false);

  const pickImage = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsEditing: true,
      aspect: [9, 16],
      quality: 0.7,
      base64: true,
    });

    if (!result.canceled && result.assets[0].base64) {
      setImage(`data:image/jpeg;base64,${result.assets[0].base64}`);
    }
  };

  const handlePost = async () => {
    if (!content.trim() && !image) {
      Alert.alert('Error', 'Please add content or an image');
      return;
    }

    setIsPosting(true);
    try {
      await api.post('/statuses', {
        content: content.trim(),
        image: image,
        background_color: backgroundColor,
      });
      router.back();
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.detail || 'Could not create status');
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
            <Ionicons name="close" size={28} color={colors.textPrimary} />
          </TouchableOpacity>
          <Text style={styles.headerTitle}>Add Status</Text>
          <TouchableOpacity
            style={[styles.postButton, ((!content.trim() && !image) || isPosting) && styles.postButtonDisabled]}
            onPress={handlePost}
            disabled={(!content.trim() && !image) || isPosting}
          >
            {isPosting ? (
              <ActivityIndicator size="small" color={colors.textInverse} />
            ) : (
              <Text style={styles.postButtonText}>Share</Text>
            )}
          </TouchableOpacity>
        </View>

        {/* Preview */}
        <View style={[styles.preview, { backgroundColor: image ? '#000' : backgroundColor }]}>
          {image ? (
            <Image source={{ uri: image }} style={styles.previewImage} resizeMode="contain" />
          ) : (
            <TextInput
              style={styles.previewText}
              placeholder="Type something..."
              placeholderTextColor="rgba(255,255,255,0.5)"
              value={content}
              onChangeText={setContent}
              multiline
              textAlign="center"
              maxLength={200}
            />
          )}
        </View>

        {/* Bottom Controls */}
        <View style={styles.bottomControls}>
          {!image && (
            <View style={styles.colorPicker}>
              <Text style={styles.colorLabel}>Background</Text>
              <ScrollView horizontal showsHorizontalScrollIndicator={false}>
                {COLORS.map((color) => (
                  <TouchableOpacity
                    key={color}
                    style={[
                      styles.colorOption,
                      { backgroundColor: color },
                      backgroundColor === color && styles.colorOptionSelected,
                    ]}
                    onPress={() => setBackgroundColor(color)}
                  />
                ))}
              </ScrollView>
            </View>
          )}

          <View style={styles.actions}>
            <TouchableOpacity style={styles.actionButton} onPress={pickImage}>
              <Ionicons name="image-outline" size={24} color={colors.textPrimary} />
              <Text style={styles.actionText}>{image ? 'Change' : 'Add'} Photo</Text>
            </TouchableOpacity>
            {image && (
              <TouchableOpacity style={styles.actionButton} onPress={() => setImage(null)}>
                <Ionicons name="trash-outline" size={24} color={colors.error} />
                <Text style={[styles.actionText, { color: colors.error }]}>Remove</Text>
              </TouchableOpacity>
            )}
          </View>
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
    minWidth: 70,
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
  preview: {
    flex: 1,
    margin: spacing.md,
    borderRadius: borderRadius.xl,
    justifyContent: 'center',
    alignItems: 'center',
    overflow: 'hidden',
  },
  previewImage: {
    width: '100%',
    height: '100%',
  },
  previewText: {
    color: 'white',
    fontSize: 24,
    fontWeight: '600',
    textAlign: 'center',
    padding: spacing.xl,
    width: '100%',
  },
  bottomControls: {
    padding: spacing.md,
  },
  colorPicker: {
    marginBottom: spacing.md,
  },
  colorLabel: {
    fontSize: 14,
    fontWeight: '500',
    color: colors.textSecondary,
    marginBottom: spacing.sm,
  },
  colorOption: {
    width: 36,
    height: 36,
    borderRadius: 18,
    marginRight: spacing.sm,
  },
  colorOptionSelected: {
    borderWidth: 3,
    borderColor: colors.textPrimary,
  },
  actions: {
    flexDirection: 'row',
    justifyContent: 'center',
  },
  actionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  actionText: {
    fontSize: 14,
    color: colors.textPrimary,
    marginLeft: spacing.xs,
    fontWeight: '500',
  },
});
