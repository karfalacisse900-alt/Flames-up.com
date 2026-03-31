import React, { useState, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  Image,
  Dimensions,
  KeyboardAvoidingView,
  Platform,
  ActivityIndicator,
  Alert,
  ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import { colors } from '../src/utils/theme';
import { useAuthStore } from '../src/store/authStore';
import api from '../src/api/client';

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');

const BG_COLORS = [
  '#6366f1', '#8b5cf6', '#ec4899', '#ef4444',
  '#f59e0b', '#10b981', '#0ea5e9', '#1f2937',
  '#059669', '#7c3aed', '#be185d', '#0284c7',
];

const FONT_SIZES = [20, 28, 36];

export default function CreateStatusScreen() {
  const router = useRouter();
  const { user } = useAuthStore();
  const [content, setContent] = useState('');
  const [image, setImage] = useState<string | null>(null);
  const [imageUri, setImageUri] = useState<string | null>(null);
  const [bgColor, setBgColor] = useState(BG_COLORS[0]);
  const [isPosting, setIsPosting] = useState(false);
  const [fontSizeIdx, setFontSizeIdx] = useState(1);
  const [textAlign, setTextAlign] = useState<'left' | 'center' | 'right'>('center');
  const [showColorPicker, setShowColorPicker] = useState(false);
  const inputRef = useRef<TextInput>(null);

  const pickImage = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      allowsEditing: true,
      aspect: [9, 16],
      quality: 0.7,
      base64: true,
    });
    if (!result.canceled && result.assets[0]) {
      setImageUri(result.assets[0].uri);
      if (result.assets[0].base64) {
        setImage(`data:image/jpeg;base64,${result.assets[0].base64}`);
      }
    }
  };

  const takePhoto = async () => {
    const { status } = await ImagePicker.requestCameraPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Permission needed', 'Camera access is required');
      return;
    }
    const result = await ImagePicker.launchCameraAsync({
      allowsEditing: true,
      aspect: [9, 16],
      quality: 0.7,
      base64: true,
    });
    if (!result.canceled && result.assets[0]) {
      setImageUri(result.assets[0].uri);
      if (result.assets[0].base64) {
        setImage(`data:image/jpeg;base64,${result.assets[0].base64}`);
      }
    }
  };

  const cycleFontSize = () => {
    setFontSizeIdx((prev) => (prev + 1) % FONT_SIZES.length);
  };

  const cycleAlign = () => {
    const aligns: ('left' | 'center' | 'right')[] = ['left', 'center', 'right'];
    const idx = aligns.indexOf(textAlign);
    setTextAlign(aligns[(idx + 1) % aligns.length]);
  };

  const handlePost = async () => {
    if (!content.trim() && !image) {
      Alert.alert('Error', 'Add text or a photo to your story');
      return;
    }
    setIsPosting(true);
    try {
      await api.post('/statuses', {
        content: content.trim(),
        image: image,
        background_color: bgColor,
      });
      router.back();
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.detail || 'Could not create status');
    } finally {
      setIsPosting(false);
    }
  };

  const hasImage = !!imageUri;
  const bgStyle = hasImage ? { backgroundColor: '#000' } : { backgroundColor: bgColor };
  const fontSize = FONT_SIZES[fontSizeIdx];

  return (
    <View style={[styles.container, bgStyle]}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={{ flex: 1 }}
      >
        {/* Background image */}
        {hasImage && (
          <Image
            source={{ uri: imageUri! }}
            style={styles.bgImage}
            resizeMode="cover"
          />
        )}

        {/* Top bar */}
        <SafeAreaView edges={['top']} style={styles.topBar}>
          <TouchableOpacity onPress={() => router.back()} style={styles.topBtn}>
            <Ionicons name="close" size={28} color="#FFFFFF" />
          </TouchableOpacity>

          <View style={styles.topCenter}>
            {!hasImage && (
              <TouchableOpacity onPress={cycleFontSize} style={styles.toolBtn}>
                <Ionicons name="text" size={20} color="#FFFFFF" />
                <Text style={styles.toolLabel}>Aa</Text>
              </TouchableOpacity>
            )}
            <TouchableOpacity onPress={cycleAlign} style={styles.toolBtn}>
              <Ionicons
                name={textAlign === 'left' ? 'reorder-two' : textAlign === 'center' ? 'reorder-three' : 'reorder-four'}
                size={20}
                color="#FFFFFF"
              />
            </TouchableOpacity>
          </View>

          <TouchableOpacity
            style={[styles.shareBtn, ((!content.trim() && !image) || isPosting) && { opacity: 0.4 }]}
            onPress={handlePost}
            disabled={(!content.trim() && !image) || isPosting}
          >
            {isPosting ? (
              <ActivityIndicator size="small" color="#FFFFFF" />
            ) : (
              <View style={styles.shareBtnInner}>
                <Ionicons name="paper-plane" size={16} color="#FFFFFF" />
                <Text style={styles.shareBtnText}>Share</Text>
              </View>
            )}
          </TouchableOpacity>
        </SafeAreaView>

        {/* Center text input */}
        <View style={styles.centerContent}>
          <TextInput
            ref={inputRef}
            style={[
              styles.storyInput,
              { fontSize, textAlign },
              hasImage && styles.storyInputWithImage,
            ]}
            placeholder="Type your story..."
            placeholderTextColor="rgba(255,255,255,0.5)"
            value={content}
            onChangeText={setContent}
            multiline
            maxLength={300}
            autoFocus={!hasImage}
          />
        </View>

        {/* Bottom toolbar */}
        <SafeAreaView edges={['bottom']} style={styles.bottomBar}>
          {/* Color picker row */}
          {showColorPicker && !hasImage && (
            <View style={styles.colorPickerRow}>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8, paddingHorizontal: 16, paddingBottom: 12 }}>
                {BG_COLORS.map((c) => (
                  <TouchableOpacity
                    key={c}
                    style={[
                      styles.colorDot,
                      { backgroundColor: c },
                      bgColor === c && styles.colorDotActive,
                    ]}
                    onPress={() => setBgColor(c)}
                  />
                ))}
              </ScrollView>
            </View>
          )}

          <View style={styles.toolRow}>
            <TouchableOpacity style={styles.bottomBtn} onPress={pickImage}>
              <Ionicons name="image-outline" size={26} color="#FFFFFF" />
              <Text style={styles.bottomLabel}>Gallery</Text>
            </TouchableOpacity>

            <TouchableOpacity style={styles.bottomBtn} onPress={takePhoto}>
              <Ionicons name="camera-outline" size={26} color="#FFFFFF" />
              <Text style={styles.bottomLabel}>Camera</Text>
            </TouchableOpacity>

            {!hasImage && (
              <TouchableOpacity
                style={styles.bottomBtn}
                onPress={() => setShowColorPicker(!showColorPicker)}
              >
                <View style={[styles.colorPreview, { backgroundColor: bgColor }]} />
                <Text style={styles.bottomLabel}>Color</Text>
              </TouchableOpacity>
            )}

            {hasImage && (
              <TouchableOpacity
                style={styles.bottomBtn}
                onPress={() => { setImage(null); setImageUri(null); }}
              >
                <Ionicons name="trash-outline" size={26} color="#FF6B6B" />
                <Text style={[styles.bottomLabel, { color: '#FF6B6B' }]}>Remove</Text>
              </TouchableOpacity>
            )}

            <TouchableOpacity
              style={styles.bottomBtn}
              onPress={() => inputRef.current?.focus()}
            >
              <Ionicons name="text-outline" size={26} color="#FFFFFF" />
              <Text style={styles.bottomLabel}>Text</Text>
            </TouchableOpacity>
          </View>

          {/* Char count */}
          <Text style={styles.charCount}>{content.length}/300</Text>
        </SafeAreaView>
      </KeyboardAvoidingView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  bgImage: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
  },
  // Top bar
  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingBottom: 8,
  },
  topBtn: {
    width: 44,
    height: 44,
    borderRadius: 22,
    justifyContent: 'center',
    alignItems: 'center',
  },
  topCenter: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  toolBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: 'rgba(255,255,255,0.2)',
    borderRadius: 20,
    paddingHorizontal: 14,
    paddingVertical: 8,
  },
  toolLabel: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '700',
  },
  shareBtn: {
    backgroundColor: colors.accentPrimary,
    borderRadius: 24,
    paddingHorizontal: 18,
    paddingVertical: 10,
  },
  shareBtnInner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  shareBtnText: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '700',
  },
  // Center
  centerContent: {
    flex: 1,
    justifyContent: 'center',
    paddingHorizontal: 24,
  },
  storyInput: {
    color: '#FFFFFF',
    fontWeight: '700',
    lineHeight: 44,
    padding: 16,
  },
  storyInputWithImage: {
    backgroundColor: 'rgba(0,0,0,0.35)',
    borderRadius: 16,
  },
  // Bottom bar
  bottomBar: {
    paddingBottom: 8,
  },
  colorPickerRow: {
    marginBottom: 4,
  },
  colorDot: {
    width: 32,
    height: 32,
    borderRadius: 16,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  colorDotActive: {
    borderColor: '#FFFFFF',
    borderWidth: 3,
  },
  toolRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  bottomBtn: {
    alignItems: 'center',
    gap: 4,
  },
  bottomLabel: {
    color: 'rgba(255,255,255,0.7)',
    fontSize: 11,
    fontWeight: '600',
  },
  colorPreview: {
    width: 26,
    height: 26,
    borderRadius: 13,
    borderWidth: 2,
    borderColor: '#FFFFFF',
  },
  charCount: {
    textAlign: 'center',
    color: 'rgba(255,255,255,0.4)',
    fontSize: 12,
    paddingBottom: 4,
  },
});
