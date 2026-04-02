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
  Modal,
  Pressable,
  FlatList,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import { colors } from '../src/utils/theme';
import { useAuthStore } from '../src/store/authStore';
import api from '../src/api/client';

const { width: SW, height: SH } = Dimensions.get('window');

// ─── Design tokens ───────────────────────────────────────────────────────────
const GRADIENTS = [
  ['#6366f1', '#8b5cf6'], ['#ec4899', '#f43f5e'], ['#f59e0b', '#ef4444'],
  ['#10b981', '#059669'], ['#0ea5e9', '#3b82f6'], ['#1f2937', '#111827'],
  ['#7c3aed', '#4f46e5'], ['#be185d', '#9333ea'], ['#0284c7', '#0d9488'],
  ['#dc2626', '#f97316'], ['#16a34a', '#2563eb'], ['#1B4332', '#2D6A4F'],
];

const SOLID_COLORS = [
  '#6366f1', '#8b5cf6', '#ec4899', '#ef4444', '#f59e0b', '#10b981',
  '#0ea5e9', '#1f2937', '#059669', '#7c3aed', '#be185d', '#0284c7',
  '#1B4332', '#2D6A4F', '#000000', '#FFFFFF',
];

const FONTS = [
  { name: 'Default', weight: '700' as const, style: 'normal' as const },
  { name: 'Light', weight: '300' as const, style: 'normal' as const },
  { name: 'Bold', weight: '900' as const, style: 'normal' as const },
  { name: 'Italic', weight: '700' as const, style: 'italic' as const },
  { name: 'Thin', weight: '100' as const, style: 'normal' as const },
];

const FONT_SIZES = [18, 24, 32, 42, 56];

const TEXT_COLORS = [
  '#FFFFFF', '#000000', '#F97316', '#EF4444', '#10B981',
  '#3B82F6', '#8B5CF6', '#F59E0B', '#EC4899', '#6366F1',
];

const STICKERS = [
  '🔥', '❤️', '😂', '🎉', '✨', '💯', '🙌', '👑', '💪', '🎵',
  '📍', '🍕', '☕', '🌟', '🏆', '💬', '🎯', '🚀', '🌈', '⚡',
  '🎶', '💥', '🌻', '🦋', '🍔', '🎸', '🏖️', '🌙', '💫', '🎨',
];

type ToolMode = 'none' | 'text' | 'color' | 'font' | 'sticker' | 'textColor';

export default function CreateStatusScreen() {
  const router = useRouter();
  const { user } = useAuthStore();
  const [content, setContent] = useState('');
  const [image, setImage] = useState<string | null>(null);
  const [imageUri, setImageUri] = useState<string | null>(null);
  const [bgColorIdx, setBgColorIdx] = useState(0);
  const [useGradient, setUseGradient] = useState(true);
  const [isPosting, setIsPosting] = useState(false);
  const [fontIdx, setFontIdx] = useState(0);
  const [fontSizeIdx, setFontSizeIdx] = useState(2);
  const [textAlign, setTextAlign] = useState<'left' | 'center' | 'right'>('center');
  const [textColor, setTextColor] = useState('#FFFFFF');
  const [toolMode, setToolMode] = useState<ToolMode>('none');
  const [placedStickers, setPlacedStickers] = useState<{ emoji: string; x: number; y: number }[]>([]);
  const inputRef = useRef<TextInput>(null);

  const pickImage = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'], allowsEditing: true, aspect: [9, 16], quality: 0.7, base64: true,
    });
    if (!result.canceled && result.assets[0]) {
      setImageUri(result.assets[0].uri);
      if (result.assets[0].base64) setImage(`data:image/jpeg;base64,${result.assets[0].base64}`);
    }
  };

  const takePhoto = async () => {
    const { status } = await ImagePicker.requestCameraPermissionsAsync();
    if (status !== 'granted') { Alert.alert('Permission needed', 'Camera access required'); return; }
    const result = await ImagePicker.launchCameraAsync({
      allowsEditing: true, aspect: [9, 16], quality: 0.7, base64: true,
    });
    if (!result.canceled && result.assets[0]) {
      setImageUri(result.assets[0].uri);
      if (result.assets[0].base64) setImage(`data:image/jpeg;base64,${result.assets[0].base64}`);
    }
  };

  const addSticker = (emoji: string) => {
    setPlacedStickers(prev => [...prev, {
      emoji,
      x: 100 + Math.random() * (SW - 200),
      y: 200 + Math.random() * (SH - 500),
    }]);
    setToolMode('none');
  };

  const handlePost = async () => {
    if (!content.trim() && !image && placedStickers.length === 0) {
      Alert.alert('Error', 'Add text, a photo, or stickers to your story');
      return;
    }
    setIsPosting(true);
    try {
      let uploadedImage = image;
      if (image) {
        try {
          const res = await api.post('/upload/image', { image });
          uploadedImage = res.data?.url || image;
        } catch { /* fallback */ }
      }
      const gradient = useGradient ? GRADIENTS[bgColorIdx] : null;
      await api.post('/statuses', {
        content: content.trim(),
        image: uploadedImage,
        background_color: useGradient ? GRADIENTS[bgColorIdx][0] : SOLID_COLORS[bgColorIdx],
        font_style: FONTS[fontIdx].name,
        text_color: textColor,
        text_align: textAlign,
        font_size: FONT_SIZES[fontSizeIdx],
        stickers: placedStickers.length > 0 ? JSON.stringify(placedStickers) : undefined,
      });
      router.back();
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.detail || 'Could not create status');
    } finally {
      setIsPosting(false);
    }
  };

  const hasImage = !!imageUri;
  const font = FONTS[fontIdx];
  const fontSize = FONT_SIZES[fontSizeIdx];
  const bgGradient = useGradient ? GRADIENTS[bgColorIdx % GRADIENTS.length] : null;
  const bgSolid = !useGradient ? SOLID_COLORS[bgColorIdx % SOLID_COLORS.length] : '#000';
  const bgStyle = hasImage ? { backgroundColor: '#000' } : bgGradient ? { backgroundColor: bgGradient[0] } : { backgroundColor: bgSolid };

  const toggleTool = (mode: ToolMode) => setToolMode(prev => prev === mode ? 'none' : mode);

  return (
    <View style={[s.container, bgStyle]}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : 'height'} style={{ flex: 1 }}>
        {/* Background image */}
        {hasImage && <Image source={{ uri: imageUri! }} style={s.bgImage} resizeMode="cover" />}
        {/* Gradient overlay if not image */}
        {!hasImage && bgGradient && (
          <View style={[s.gradientOverlay, { backgroundColor: bgGradient[1], opacity: 0.6 }]} />
        )}

        {/* Placed stickers */}
        {placedStickers.map((st, i) => (
          <TouchableOpacity
            key={i}
            style={[s.placedSticker, { left: st.x - 24, top: st.y - 24 }]}
            onLongPress={() => setPlacedStickers(prev => prev.filter((_, idx) => idx !== i))}
          >
            <Text style={s.placedStickerText}>{st.emoji}</Text>
          </TouchableOpacity>
        ))}

        {/* ─── Top Bar ─────────────────────────────────────────────── */}
        <SafeAreaView edges={['top']} style={s.topBar}>
          <TouchableOpacity onPress={() => router.back()} style={s.topBtn}>
            <Ionicons name="close" size={28} color="#FFF" />
          </TouchableOpacity>

          <View style={s.topTools}>
            <TouchableOpacity onPress={() => toggleTool('font')} style={[s.pill, toolMode === 'font' && s.pillActive]}>
              <Ionicons name="text" size={16} color="#FFF" />
              <Text style={s.pillText}>Aa</Text>
            </TouchableOpacity>
            <TouchableOpacity onPress={() => toggleTool('textColor')} style={[s.pill, toolMode === 'textColor' && s.pillActive]}>
              <View style={[s.colorDotSmall, { backgroundColor: textColor }]} />
            </TouchableOpacity>
            <TouchableOpacity onPress={() => {
              const aligns: ('left' | 'center' | 'right')[] = ['left', 'center', 'right'];
              setTextAlign(aligns[(aligns.indexOf(textAlign) + 1) % 3]);
            }} style={s.pill}>
              <Ionicons name={textAlign === 'left' ? 'reorder-two' : textAlign === 'center' ? 'reorder-three' : 'reorder-four'} size={16} color="#FFF" />
            </TouchableOpacity>
          </View>

          <TouchableOpacity
            style={[s.shareBtn, ((!content.trim() && !image && placedStickers.length === 0) || isPosting) && { opacity: 0.4 }]}
            onPress={handlePost}
            disabled={(!content.trim() && !image && placedStickers.length === 0) || isPosting}
          >
            {isPosting ? <ActivityIndicator size="small" color="#FFF" /> : (
              <View style={s.shareBtnInner}>
                <Ionicons name="paper-plane" size={14} color="#FFF" />
                <Text style={s.shareBtnText}>Share</Text>
              </View>
            )}
          </TouchableOpacity>
        </SafeAreaView>

        {/* ─── Center Text ─────────────────────────────────────────── */}
        <Pressable style={s.centerContent} onPress={() => inputRef.current?.focus()}>
          <TextInput
            ref={inputRef}
            style={[
              s.storyInput,
              { fontSize, textAlign, color: textColor, fontWeight: font.weight, fontStyle: font.style },
              hasImage && s.storyInputWithImage,
            ]}
            placeholder="Type your story..."
            placeholderTextColor="rgba(255,255,255,0.4)"
            value={content}
            onChangeText={setContent}
            multiline
            maxLength={500}
            autoFocus={!hasImage}
          />
        </Pressable>

        {/* ─── Bottom Toolbar ──────────────────────────────────────── */}
        <SafeAreaView edges={['bottom']} style={s.bottomArea}>
          {/* Expanding panels */}
          {toolMode === 'color' && (
            <View style={s.panel}>
              <View style={s.panelHeader}>
                <TouchableOpacity onPress={() => setUseGradient(true)} style={[s.panelTab, useGradient && s.panelTabActive]}>
                  <Text style={[s.panelTabText, useGradient && { color: '#FFF' }]}>Gradients</Text>
                </TouchableOpacity>
                <TouchableOpacity onPress={() => setUseGradient(false)} style={[s.panelTab, !useGradient && s.panelTabActive]}>
                  <Text style={[s.panelTabText, !useGradient && { color: '#FFF' }]}>Solid</Text>
                </TouchableOpacity>
              </View>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.colorRow}>
                {(useGradient ? GRADIENTS : SOLID_COLORS.map(c => [c, c])).map((c, i) => (
                  <TouchableOpacity
                    key={i}
                    style={[s.colorDot, { backgroundColor: Array.isArray(c) ? c[0] : c }, bgColorIdx === i && s.colorDotActive]}
                    onPress={() => setBgColorIdx(i)}
                  >
                    {Array.isArray(c) && c[0] !== c[1] && (
                      <View style={[s.colorDotHalf, { backgroundColor: c[1] }]} />
                    )}
                  </TouchableOpacity>
                ))}
              </ScrollView>
            </View>
          )}
          {toolMode === 'font' && (
            <View style={s.panel}>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.colorRow}>
                {FONTS.map((f, i) => (
                  <TouchableOpacity key={i} style={[s.fontPill, fontIdx === i && s.fontPillActive]} onPress={() => setFontIdx(i)}>
                    <Text style={[s.fontPillText, { fontWeight: f.weight, fontStyle: f.style }, fontIdx === i && { color: '#FFF' }]}>{f.name}</Text>
                  </TouchableOpacity>
                ))}
              </ScrollView>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.colorRow}>
                {FONT_SIZES.map((sz, i) => (
                  <TouchableOpacity key={i} style={[s.sizePill, fontSizeIdx === i && s.sizePillActive]} onPress={() => setFontSizeIdx(i)}>
                    <Text style={[s.sizePillText, fontSizeIdx === i && { color: '#FFF' }]}>{sz}</Text>
                  </TouchableOpacity>
                ))}
              </ScrollView>
            </View>
          )}
          {toolMode === 'textColor' && (
            <View style={s.panel}>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.colorRow}>
                {TEXT_COLORS.map((c, i) => (
                  <TouchableOpacity
                    key={i}
                    style={[s.textColorDot, { backgroundColor: c }, textColor === c && s.textColorDotActive]}
                    onPress={() => setTextColor(c)}
                  />
                ))}
              </ScrollView>
            </View>
          )}
          {toolMode === 'sticker' && (
            <View style={s.panel}>
              <View style={s.stickerGrid}>
                {STICKERS.map((em, i) => (
                  <TouchableOpacity key={i} style={s.stickerItem} onPress={() => addSticker(em)}>
                    <Text style={s.stickerEmoji}>{em}</Text>
                  </TouchableOpacity>
                ))}
              </View>
            </View>
          )}

          {/* Main toolbar */}
          <View style={s.toolRow}>
            <TouchableOpacity style={s.bottomBtn} onPress={pickImage}>
              <Ionicons name="image-outline" size={24} color="#FFF" />
              <Text style={s.bottomLabel}>Gallery</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.bottomBtn} onPress={takePhoto}>
              <Ionicons name="camera-outline" size={24} color="#FFF" />
              <Text style={s.bottomLabel}>Camera</Text>
            </TouchableOpacity>
            {!hasImage && (
              <TouchableOpacity style={s.bottomBtn} onPress={() => toggleTool('color')}>
                <View style={[s.colorPreview, { backgroundColor: useGradient ? GRADIENTS[bgColorIdx][0] : SOLID_COLORS[bgColorIdx] }]} />
                <Text style={s.bottomLabel}>Color</Text>
              </TouchableOpacity>
            )}
            <TouchableOpacity style={s.bottomBtn} onPress={() => toggleTool('sticker')}>
              <Text style={{ fontSize: 22 }}>😊</Text>
              <Text style={s.bottomLabel}>Sticker</Text>
            </TouchableOpacity>
            {hasImage && (
              <TouchableOpacity style={s.bottomBtn} onPress={() => { setImage(null); setImageUri(null); }}>
                <Ionicons name="trash-outline" size={24} color="#FF6B6B" />
                <Text style={[s.bottomLabel, { color: '#FF6B6B' }]}>Remove</Text>
              </TouchableOpacity>
            )}
          </View>
          <Text style={s.charCount}>{content.length}/500</Text>
        </SafeAreaView>
      </KeyboardAvoidingView>
    </View>
  );
}

const s = StyleSheet.create({
  container: { flex: 1 },
  bgImage: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 },
  gradientOverlay: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 },
  placedSticker: { position: 'absolute', zIndex: 5 },
  placedStickerText: { fontSize: 48 },
  // Top bar
  topBar: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 12, paddingBottom: 4, zIndex: 10 },
  topBtn: { width: 44, height: 44, borderRadius: 22, justifyContent: 'center', alignItems: 'center', backgroundColor: 'rgba(0,0,0,0.25)' },
  topTools: { flexDirection: 'row', gap: 6 },
  pill: { flexDirection: 'row', alignItems: 'center', gap: 4, backgroundColor: 'rgba(255,255,255,0.15)', borderRadius: 20, paddingHorizontal: 12, paddingVertical: 7 },
  pillActive: { backgroundColor: 'rgba(255,255,255,0.35)' },
  pillText: { color: '#FFF', fontSize: 13, fontWeight: '700' },
  colorDotSmall: { width: 18, height: 18, borderRadius: 9, borderWidth: 2, borderColor: '#FFF' },
  shareBtn: { backgroundColor: '#2D6A4F', borderRadius: 22, paddingHorizontal: 16, paddingVertical: 9 },
  shareBtnInner: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  shareBtnText: { color: '#FFF', fontSize: 13, fontWeight: '700' },
  // Center
  centerContent: { flex: 1, justifyContent: 'center', paddingHorizontal: 20, zIndex: 1 },
  storyInput: { lineHeight: 48, padding: 16, textShadowColor: 'rgba(0,0,0,0.3)', textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 3 },
  storyInputWithImage: { backgroundColor: 'rgba(0,0,0,0.35)', borderRadius: 16 },
  // Bottom
  bottomArea: { paddingBottom: 4, zIndex: 10 },
  panel: { backgroundColor: 'rgba(0,0,0,0.5)', borderRadius: 16, marginHorizontal: 12, marginBottom: 8, padding: 12 },
  panelHeader: { flexDirection: 'row', gap: 8, marginBottom: 10 },
  panelTab: { paddingHorizontal: 14, paddingVertical: 5, borderRadius: 14, backgroundColor: 'rgba(255,255,255,0.1)' },
  panelTabActive: { backgroundColor: 'rgba(255,255,255,0.3)' },
  panelTabText: { color: 'rgba(255,255,255,0.6)', fontSize: 12, fontWeight: '600' },
  colorRow: { gap: 8, paddingHorizontal: 4 },
  colorDot: { width: 36, height: 36, borderRadius: 18, borderWidth: 2, borderColor: 'transparent', overflow: 'hidden' },
  colorDotActive: { borderColor: '#FFF', borderWidth: 3 },
  colorDotHalf: { position: 'absolute', bottom: 0, left: 0, right: 0, height: '50%' },
  fontPill: { paddingHorizontal: 16, paddingVertical: 8, borderRadius: 16, backgroundColor: 'rgba(255,255,255,0.1)', marginRight: 4 },
  fontPillActive: { backgroundColor: 'rgba(255,255,255,0.35)' },
  fontPillText: { color: 'rgba(255,255,255,0.7)', fontSize: 14 },
  sizePill: { paddingHorizontal: 14, paddingVertical: 6, borderRadius: 14, backgroundColor: 'rgba(255,255,255,0.1)', marginRight: 4, marginTop: 8 },
  sizePillActive: { backgroundColor: 'rgba(255,255,255,0.35)' },
  sizePillText: { color: 'rgba(255,255,255,0.7)', fontSize: 13, fontWeight: '600' },
  textColorDot: { width: 32, height: 32, borderRadius: 16, borderWidth: 2, borderColor: 'rgba(255,255,255,0.3)' },
  textColorDotActive: { borderColor: '#FFF', borderWidth: 3, transform: [{ scale: 1.15 }] },
  stickerGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 4 },
  stickerItem: { width: (SW - 24 - 40) / 10, alignItems: 'center', paddingVertical: 4 },
  stickerEmoji: { fontSize: 26 },
  // Toolbar
  toolRow: { flexDirection: 'row', justifyContent: 'space-around', paddingHorizontal: 16, paddingVertical: 8 },
  bottomBtn: { alignItems: 'center', gap: 3 },
  bottomLabel: { color: 'rgba(255,255,255,0.7)', fontSize: 10, fontWeight: '600' },
  colorPreview: { width: 24, height: 24, borderRadius: 12, borderWidth: 2, borderColor: '#FFF' },
  charCount: { textAlign: 'center', color: 'rgba(255,255,255,0.35)', fontSize: 11, paddingBottom: 4 },
});
