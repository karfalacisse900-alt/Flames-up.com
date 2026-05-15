import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Image,
  Keyboard,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  useWindowDimensions,
  View,
} from 'react-native';
import { CameraType, CameraView, FlashMode, useCameraPermissions } from 'expo-camera';
import * as ImagePicker from 'expo-image-picker';
import { StatusBar } from 'expo-status-bar';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import api from '../src/api/client';
import { uploadImage } from '../src/utils/mediaUpload';
import { useAuthStore } from '../src/store/authStore';
import { colors, hitSlop, spacing } from '../src/utils/theme';
import { STORY_IMAGE_PICKER_QUALITY } from '../src/utils/mediaQuality';
import { useI18n } from '../src/utils/i18n';
import { isPhoneVerificationError, requireVerifiedPhone } from '../src/utils/phoneVerification';

type ToolMode = 'none' | 'text' | 'stickers' | 'color';

type PlacedSticker = {
  emoji: string;
  x: number;
  y: number;
};

const TEXT_COLORS = ['#FFFFFF', '#F8F4EA', '#DFFF32', '#F6A6B7', '#83D89B', '#111111'];
const STICKERS = ['Love', 'Mood', 'NYC', 'Today', 'Fire', 'Real', 'Vibe', 'Glow'];

function dataUriFromBase64(base64?: string, fallbackUri?: string) {
  if (base64) return `data:image/jpeg;base64,${base64}`;
  if (fallbackUri?.startsWith('data:')) return fallbackUri;
  return '';
}

export default function CreateStatusScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { width, height } = useWindowDimensions();
  const { user } = useAuthStore();
  const { t } = useI18n();
  const cameraRef = useRef<CameraView>(null);
  const inputRef = useRef<TextInput>(null);
  const requestedPermissionRef = useRef(false);
  const [cameraPermission, requestCameraPermission] = useCameraPermissions();
  const [cameraFacing, setCameraFacing] = useState<CameraType>('back');
  const [flash, setFlash] = useState<FlashMode>('off');
  const [content, setContent] = useState('');
  const [imageUri, setImageUri] = useState('');
  const [imageData, setImageData] = useState('');
  const [textColor, setTextColor] = useState('#FFFFFF');
  const [textAlign, setTextAlign] = useState<'left' | 'center' | 'right'>('left');
  const [toolMode, setToolMode] = useState<ToolMode>('none');
  const [placedStickers, setPlacedStickers] = useState<PlacedSticker[]>([]);
  const [isCapturing, setIsCapturing] = useState(false);
  const [isPosting, setIsPosting] = useState(false);

  const hasImage = !!imageUri;
  const canPost = !!content.trim() || !!imageData || placedStickers.length > 0;
  const storyFrameHeight = Math.max(520, height - insets.top - insets.bottom - 32);

  useEffect(() => {
    if (!cameraPermission || cameraPermission.granted || requestedPermissionRef.current) return;
    requestedPermissionRef.current = true;
    void requestCameraPermission();
  }, [cameraPermission, requestCameraPermission]);

  const focusText = useCallback(() => {
    setToolMode('text');
    requestAnimationFrame(() => inputRef.current?.focus());
  }, []);

  const cycleTextAlign = useCallback(() => {
    const alignments: Array<'left' | 'center' | 'right'> = ['left', 'center', 'right'];
    setTextAlign((current) => alignments[(alignments.indexOf(current) + 1) % alignments.length]);
  }, []);

  const cycleFlash = useCallback(() => {
    const modes: FlashMode[] = ['off', 'on', 'auto'];
    setFlash((current) => modes[(modes.indexOf(current) + 1) % modes.length]);
  }, []);

  const flipCamera = useCallback(() => {
    setCameraFacing((current) => (current === 'back' ? 'front' : 'back'));
  }, []);

  const capturePhoto = useCallback(async () => {
    if (isCapturing || !cameraRef.current || hasImage) return;
    setIsCapturing(true);
    try {
      const picture = await cameraRef.current.takePictureAsync({
        quality: STORY_IMAGE_PICKER_QUALITY,
        base64: true,
        exif: false,
        skipProcessing: false,
      });
      if (!picture?.uri) return;
      setImageUri(picture.uri);
      setImageData(dataUriFromBase64(picture.base64 || undefined, picture.uri || undefined));
      setToolMode('text');
    } catch {
      Alert.alert('Camera failed', 'Could not take that photo. Please try again.');
    } finally {
      setIsCapturing(false);
    }
  }, [hasImage, isCapturing]);

  const pickImage = useCallback(async () => {
    try {
      const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (status !== 'granted') {
        Alert.alert('Permission needed', 'Please allow access to your photo library.');
        return;
      }
      const result = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ['images'],
        allowsEditing: true,
        aspect: [9, 16],
        quality: STORY_IMAGE_PICKER_QUALITY,
        base64: true,
        preferredAssetRepresentationMode: ImagePicker.UIImagePickerPreferredAssetRepresentationMode.Current,
      });
      if (result.canceled || !result.assets?.[0]) return;
      const asset = result.assets[0];
      setImageUri(asset.uri);
      setImageData(dataUriFromBase64(asset.base64 || undefined, asset.uri || undefined));
      setToolMode('text');
    } catch {
      Alert.alert('Gallery failed', 'Could not open your gallery. Please try again.');
    }
  }, []);

  const addSticker = useCallback((label: string) => {
    const maxX = Math.max(120, width - 170);
    const maxY = Math.max(230, storyFrameHeight - 250);
    setPlacedStickers((current) => [
      ...current,
      {
        emoji: label,
        x: 66 + Math.random() * maxX,
        y: 210 + Math.random() * maxY,
      },
    ]);
    setToolMode('none');
  }, [storyFrameHeight, width]);

  const clearCapture = useCallback(() => {
    setImageUri('');
    setImageData('');
    setToolMode('none');
  }, []);

  const handlePost = useCallback(async () => {
    if (!canPost || isPosting) {
      Alert.alert(t('error'), t('statusEmptyMessage'));
      return;
    }
    if (!requireVerifiedPhone(user, router, 'share stories')) return;
    if (imageUri && !imageData) {
      Alert.alert('Image not ready', 'Please capture or choose the image again.');
      return;
    }
    Keyboard.dismiss();
    setIsPosting(true);
    try {
      const uploadedImage = imageData ? await uploadImage(imageData) : '';
      await api.post('/statuses', {
        content: content.trim(),
        image: uploadedImage || undefined,
        background_color: '#080D10',
        font_style: 'Default',
        text_color: textColor,
        text_align: textAlign,
        font_size: 34,
        stickers: placedStickers.length > 0 ? JSON.stringify(placedStickers) : undefined,
      });
      router.back();
    } catch (error: any) {
      if (isPhoneVerificationError(error)) {
        requireVerifiedPhone(null, router, 'share stories');
      } else {
        Alert.alert(t('error'), error.response?.data?.detail || t('couldNotCreateStatus'));
      }
    } finally {
      setIsPosting(false);
    }
  }, [canPost, content, imageData, imageUri, isPosting, placedStickers, router, t, textAlign, textColor, user]);

  const renderCameraSurface = () => {
    if (!cameraPermission) {
      return (
        <View style={s.permissionState}>
          <ActivityIndicator color="#FFFFFF" />
        </View>
      );
    }

    if (!cameraPermission.granted && !hasImage) {
      return (
        <View style={s.permissionState}>
          <Ionicons name="camera-outline" size={42} color="#FFFFFF" />
          <Text style={s.permissionTitle}>Camera access needed</Text>
          <Text style={s.permissionText}>Allow camera access to create a story directly in Flames.</Text>
          <TouchableOpacity style={s.permissionButton} onPress={requestCameraPermission} activeOpacity={0.84}>
            <Text style={s.permissionButtonText}>Allow camera</Text>
          </TouchableOpacity>
        </View>
      );
    }

    if (hasImage) {
      return <Image source={{ uri: imageUri }} style={s.cameraFill} resizeMode="cover" />;
    }

    return (
      <CameraView
        ref={cameraRef}
        style={s.cameraFill}
        mode="picture"
        facing={cameraFacing}
        flash={flash}
        mirror={cameraFacing === 'front'}
      />
    );
  };

  return (
    <View style={s.root}>
      <StatusBar hidden />
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={s.flex}>
        <View style={[s.cameraFrame, { height: storyFrameHeight }]}>
          {renderCameraSurface()}
          <View style={s.cameraShade} pointerEvents="none" />

          <View style={[s.topControls, { top: insets.top + 18 }]}>
            <TouchableOpacity style={s.circleButton} onPress={() => router.back()} activeOpacity={0.82} accessibilityLabel="Close story editor">
              <Ionicons name="close" size={38} color="#FFFFFF" />
            </TouchableOpacity>
            <TouchableOpacity style={s.flashButton} onPress={cycleFlash} activeOpacity={0.82} accessibilityLabel="Change flash mode">
              <Ionicons name={flash === 'off' ? 'flash-off' : flash === 'on' ? 'flash' : 'sparkles'} size={38} color="#FFFFFF" />
            </TouchableOpacity>
            <TouchableOpacity style={s.circleButton} onPress={flipCamera} activeOpacity={0.82} accessibilityLabel="Switch camera">
              <Ionicons name="settings-outline" size={38} color="#FFFFFF" />
            </TouchableOpacity>
          </View>

          <View style={s.leftTools}>
            <TouchableOpacity style={[s.sideTool, toolMode === 'text' && s.sideToolOn]} onPress={focusText} activeOpacity={0.78}>
              <Text style={s.sideTextTool}>Aa</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.sideTool} onPress={() => setToolMode((mode) => (mode === 'color' ? 'none' : 'color'))} activeOpacity={0.78}>
              <Ionicons name="infinite-outline" size={40} color="#FFFFFF" />
            </TouchableOpacity>
            <TouchableOpacity style={s.sideTool} onPress={cycleTextAlign} activeOpacity={0.78}>
              <Ionicons name="grid-outline" size={35} color="#FFFFFF" />
            </TouchableOpacity>
            <TouchableOpacity style={[s.sideTool, toolMode === 'stickers' && s.sideToolOn]} onPress={() => setToolMode((mode) => (mode === 'stickers' ? 'none' : 'stickers'))} activeOpacity={0.78}>
              <Ionicons name="happy-outline" size={38} color="#FFFFFF" />
            </TouchableOpacity>
            <TouchableOpacity style={s.sideTool} onPress={handlePost} activeOpacity={0.78} disabled={isPosting}>
              {isPosting ? <ActivityIndicator color="#FFFFFF" /> : <Ionicons name="checkmark" size={42} color="#FFFFFF" />}
            </TouchableOpacity>
          </View>

          {placedStickers.map((sticker, index) => (
            <TouchableOpacity
              key={`${sticker.emoji}-${index}`}
              style={[s.placedSticker, { left: sticker.x, top: sticker.y }]}
              activeOpacity={0.8}
              onLongPress={() => setPlacedStickers((current) => current.filter((_, itemIndex) => itemIndex !== index))}
            >
              <Text style={s.placedStickerText}>{sticker.emoji}</Text>
            </TouchableOpacity>
          ))}

          <Pressable style={s.textLayer} onPress={focusText}>
            {(toolMode === 'text' || content.trim()) ? (
              <TextInput
                ref={inputRef}
                value={content}
                onChangeText={(value) => setContent(value.slice(0, 500))}
                placeholder="Aa"
                placeholderTextColor="rgba(255,255,255,0.78)"
                style={[s.storyInput, { color: textColor, textAlign }]}
                multiline
                maxLength={500}
                textAlignVertical="center"
              />
            ) : null}
          </Pressable>

          {toolMode === 'color' ? (
            <View style={s.colorPanel}>
              {TEXT_COLORS.map((color) => (
                <TouchableOpacity
                  key={color}
                  style={[s.colorSwatch, { backgroundColor: color }, textColor === color && s.colorSwatchOn]}
                  onPress={() => setTextColor(color)}
                  activeOpacity={0.8}
                  accessibilityLabel={`Use ${color} text`}
                />
              ))}
            </View>
          ) : null}

          {toolMode === 'stickers' ? (
            <ScrollView horizontal showsHorizontalScrollIndicator={false} style={s.stickerPanel} contentContainerStyle={s.stickerContent}>
              {STICKERS.map((sticker) => (
                <TouchableOpacity key={sticker} style={s.stickerButton} onPress={() => addSticker(sticker)} activeOpacity={0.82}>
                  <Text style={s.stickerText}>{sticker}</Text>
                </TouchableOpacity>
              ))}
            </ScrollView>
          ) : null}

          <View style={[s.bottomControls, { bottom: Math.max(insets.bottom + 16, 30) }]}>
            <TouchableOpacity style={s.galleryButton} onPress={pickImage} activeOpacity={0.82} accessibilityLabel="Open gallery">
              {hasImage ? (
                <Image source={{ uri: imageUri }} style={s.galleryThumb} />
              ) : (
                <Ionicons name="images-outline" size={25} color="#FFFFFF" />
              )}
            </TouchableOpacity>

            <TouchableOpacity
              style={[s.shutterButton, (isCapturing || hasImage) && s.shutterButtonMuted]}
              onPress={hasImage ? clearCapture : capturePhoto}
              activeOpacity={0.82}
              accessibilityLabel={hasImage ? 'Retake story photo' : 'Take story photo'}
              disabled={isCapturing}
            >
              <View style={s.shutterInner}>
                {isCapturing ? <ActivityIndicator color="#FFFFFF" /> : null}
              </View>
            </TouchableOpacity>

            <TouchableOpacity
              style={[s.sendButton, !canPost && s.sendButtonDisabled]}
              onPress={handlePost}
              disabled={!canPost || isPosting}
              activeOpacity={0.84}
              accessibilityLabel="Share story"
            >
              {isPosting ? <ActivityIndicator size="small" color="#FFFFFF" /> : <Ionicons name="arrow-forward" size={30} color="#FFFFFF" />}
            </TouchableOpacity>
          </View>
        </View>
      </KeyboardAvoidingView>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#071015' },
  flex: { flex: 1 },
  cameraFrame: {
    flex: 1,
    marginHorizontal: 0,
    marginTop: 0,
    overflow: 'hidden',
    borderBottomLeftRadius: 42,
    borderBottomRightRadius: 42,
    backgroundColor: '#101417',
  },
  cameraFill: {
    ...StyleSheet.absoluteFillObject,
    width: '100%',
    height: '100%',
  },
  cameraShade: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.08)',
  },
  topControls: {
    position: 'absolute',
    left: 24,
    right: 24,
    zIndex: 10,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  circleButton: {
    width: 58,
    height: 58,
    borderRadius: 29,
    alignItems: 'center',
    justifyContent: 'center',
  },
  flashButton: {
    width: 64,
    height: 64,
    borderRadius: 32,
    alignItems: 'center',
    justifyContent: 'center',
  },
  leftTools: {
    position: 'absolute',
    left: 34,
    top: '41%',
    zIndex: 12,
    gap: 16,
  },
  sideTool: {
    width: 56,
    minHeight: 44,
    alignItems: 'center',
    justifyContent: 'center',
  },
  sideToolOn: {
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.16)',
  },
  sideTextTool: {
    color: '#FFFFFF',
    fontSize: 38,
    lineHeight: 44,
    fontWeight: '300',
  },
  textLayer: {
    position: 'absolute',
    left: 54,
    right: 30,
    top: '38%',
    minHeight: 120,
    zIndex: 8,
  },
  storyInput: {
    minHeight: 92,
    padding: 0,
    color: '#FFFFFF',
    fontSize: 42,
    lineHeight: 50,
    fontWeight: '400',
    textShadowColor: 'rgba(0,0,0,0.34)',
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 8,
  },
  placedSticker: {
    position: 'absolute',
    zIndex: 9,
    paddingHorizontal: 13,
    paddingVertical: 7,
    borderRadius: 999,
    backgroundColor: 'rgba(0,0,0,0.42)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.22)',
  },
  placedStickerText: {
    color: '#FFFFFF',
    fontSize: 18,
    lineHeight: 23,
    fontWeight: '800',
  },
  colorPanel: {
    position: 'absolute',
    left: 100,
    right: 24,
    bottom: 132,
    zIndex: 20,
    minHeight: 54,
    borderRadius: 27,
    paddingHorizontal: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    backgroundColor: 'rgba(5,8,10,0.64)',
  },
  colorSwatch: {
    width: 32,
    height: 32,
    borderRadius: 16,
    borderWidth: 2,
    borderColor: 'rgba(255,255,255,0.35)',
  },
  colorSwatchOn: {
    borderColor: '#FFFFFF',
    transform: [{ scale: 1.13 }],
  },
  stickerPanel: {
    position: 'absolute',
    left: 82,
    right: 18,
    bottom: 132,
    zIndex: 20,
  },
  stickerContent: {
    minHeight: 56,
    alignItems: 'center',
    gap: 10,
    paddingHorizontal: spacing.sm,
  },
  stickerButton: {
    minHeight: 42,
    borderRadius: 21,
    paddingHorizontal: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(5,8,10,0.64)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.16)',
  },
  stickerText: {
    color: '#FFFFFF',
    fontSize: 15,
    lineHeight: 20,
    fontWeight: '800',
  },
  bottomControls: {
    position: 'absolute',
    left: 42,
    right: 42,
    zIndex: 14,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  galleryButton: {
    width: 58,
    height: 58,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
  galleryThumb: {
    width: '100%',
    height: '100%',
  },
  shutterButton: {
    width: 96,
    height: 96,
    borderRadius: 48,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 6,
    borderColor: '#FFFFFF',
    backgroundColor: 'rgba(255,255,255,0.18)',
  },
  shutterButtonMuted: {
    opacity: 0.78,
  },
  shutterInner: {
    width: 76,
    height: 76,
    borderRadius: 38,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(238,238,238,0.92)',
  },
  sendButton: {
    width: 58,
    height: 58,
    borderRadius: 29,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.accentPrimary,
  },
  sendButtonDisabled: {
    opacity: 0.42,
  },
  permissionState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.gutter,
    paddingHorizontal: spacing.xl,
    backgroundColor: '#0C1114',
  },
  permissionTitle: {
    color: '#FFFFFF',
    fontSize: 22,
    lineHeight: 27,
    fontWeight: '800',
    textAlign: 'center',
  },
  permissionText: {
    color: 'rgba(255,255,255,0.72)',
    fontSize: 15,
    lineHeight: 21,
    fontWeight: '600',
    textAlign: 'center',
  },
  permissionButton: {
    minHeight: 46,
    borderRadius: 23,
    paddingHorizontal: spacing.lg,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#FFFFFF',
  },
  permissionButtonText: {
    color: '#071015',
    fontSize: 15,
    lineHeight: 20,
    fontWeight: '800',
  },
});
