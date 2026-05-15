import React, { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import api from '../src/api/client';
import { colors } from '../src/utils/theme';

const CATEGORIES = [
  { id: 'vibe', label: 'Vibe' },
  { id: 'people', label: 'People' },
];

export default function CreateRecommendationScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const [category, setCategory] = useState('vibe');
  const [title, setTitle] = useState('');
  const [creatorName, setCreatorName] = useState('');
  const [link, setLink] = useState('');
  const [thumbnailUrl, setThumbnailUrl] = useState('');
  const [description, setDescription] = useState('');
  const [tags, setTags] = useState('');
  const [saving, setSaving] = useState(false);

  const canSubmit = title.trim().length > 1 && link.trim().length > 4 && !saving;

  const submit = async () => {
    if (!canSubmit) return;
    setSaving(true);
    try {
      const response = await api.post('/recommendations', {
        title: title.trim(),
        creator_name: creatorName.trim(),
        external_url: link.trim(),
        thumbnail_url: thumbnailUrl.trim(),
        description: description.trim(),
        category,
        tags: tags.split(',').map((tag) => tag.trim()).filter(Boolean),
      });
      const id = response.data?.id;
      if (id) {
        router.replace(`/recommendation/${id}` as any);
      } else {
        router.back();
      }
    } catch (error: any) {
      Alert.alert('Could not submit', error?.response?.data?.detail || 'Check the link and try again.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <SafeAreaView style={styles.safeArea} edges={['top']}>
      <KeyboardAvoidingView style={styles.screen} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
        <View style={styles.header}>
          <TouchableOpacity style={styles.headerBtn} onPress={() => router.back()} activeOpacity={0.75}>
            <Ionicons name="arrow-back" size={30} color={colors.textPrimary} />
          </TouchableOpacity>
          <Text style={styles.headerTitle}>New recommend</Text>
          <View style={styles.headerBtn} />
        </View>

        <ScrollView
          showsVerticalScrollIndicator={false}
          keyboardShouldPersistTaps="handled"
          contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 120 }]}
        >
          <View style={styles.hero}>
            <Ionicons name="link-outline" size={28} color="#111111" />
            <View style={{ flex: 1 }}>
              <Text style={styles.heroTitle}>Share the thing, not the file.</Text>
              <Text style={styles.heroText}>Paste a creator, place, product, video, or community link. Flames Up embeds it when possible and keeps the source hosted outside the app.</Text>
            </View>
          </View>

          <Text style={styles.label}>What is it?</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.categoryRail}>
            {CATEGORIES.map((item) => {
              const active = item.id === category;
              return (
                <TouchableOpacity key={item.id} style={[styles.categoryPill, active && styles.categoryPillOn]} onPress={() => setCategory(item.id)}>
                  <Text style={[styles.categoryText, active && styles.categoryTextOn]}>{item.label}</Text>
                </TouchableOpacity>
              );
            })}
          </ScrollView>

          <View style={styles.fieldGroup}>
            <Text style={styles.label}>Title</Text>
            <TextInput
              value={title}
              onChangeText={setTitle}
              placeholder="Vibe, creator, place, product..."
              placeholderTextColor="#A4A4A4"
              style={styles.input}
            />
          </View>

          <View style={styles.fieldGroup}>
            <Text style={styles.label}>Creator / author / artist</Text>
            <TextInput
              value={creatorName}
              onChangeText={setCreatorName}
              placeholder="Optional"
              placeholderTextColor="#A4A4A4"
              style={styles.input}
            />
          </View>

          <View style={styles.fieldGroup}>
            <Text style={styles.label}>Link</Text>
            <TextInput
              value={link}
              onChangeText={setLink}
              autoCapitalize="none"
              autoCorrect={false}
              keyboardType="url"
              placeholder="https://youtube.com/watch?v=..."
              placeholderTextColor="#A4A4A4"
              style={styles.input}
            />
          </View>

          <View style={styles.fieldGroup}>
            <Text style={styles.label}>Cover image URL</Text>
            <TextInput
              value={thumbnailUrl}
              onChangeText={setThumbnailUrl}
              autoCapitalize="none"
              autoCorrect={false}
              keyboardType="url"
              placeholder="Optional. YouTube thumbnails are automatic."
              placeholderTextColor="#A4A4A4"
              style={styles.input}
            />
          </View>

          <View style={styles.fieldGroup}>
            <Text style={styles.label}>Why do you recommend it?</Text>
            <TextInput
              value={description}
              onChangeText={setDescription}
              multiline
              textAlignVertical="top"
              placeholder="Tell people the vibe, who it is for, or why it is worth opening."
              placeholderTextColor="#A4A4A4"
              style={[styles.input, styles.textarea]}
            />
          </View>

          <View style={styles.fieldGroup}>
            <Text style={styles.label}>Tags</Text>
            <TextInput
              value={tags}
              onChangeText={setTags}
              placeholder="classic, fashion, funny"
              placeholderTextColor="#A4A4A4"
              style={styles.input}
            />
          </View>
        </ScrollView>

        <View style={[styles.bottomBar, { paddingBottom: insets.bottom + 14 }]}>
          <TouchableOpacity disabled={!canSubmit} style={[styles.shareButton, !canSubmit && styles.shareButtonDisabled]} onPress={submit} activeOpacity={0.9}>
            {saving ? <ActivityIndicator color="#FFFFFF" /> : <Text style={styles.shareText}>Share recommend</Text>}
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: { flex: 1, backgroundColor: colors.bgApp },
  screen: { flex: 1, backgroundColor: colors.bgApp },
  header: {
    height: 82,
    borderBottomWidth: 1.5,
    borderBottomColor: colors.textPrimary,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 22,
  },
  headerBtn: { width: 48, height: 48, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 24, fontWeight: '500', color: colors.textPrimary },
  content: { padding: 18, gap: 18 },
  hero: { borderRadius: 22, backgroundColor: '#F4F2EA', borderWidth: 1, borderColor: '#E7E0D0', padding: 16, flexDirection: 'row', gap: 14 },
  heroTitle: { color: '#111111', fontSize: 19, lineHeight: 23, fontWeight: '500' },
  heroText: { color: '#5F5B53', fontSize: 13, lineHeight: 19, fontWeight: '500', marginTop: 5 },
  categoryRail: { gap: 8, paddingBottom: 2 },
  categoryPill: { minHeight: 36, borderRadius: 18, backgroundColor: '#F1F1F1', justifyContent: 'center', paddingHorizontal: 14 },
  categoryPillOn: { backgroundColor: '#111111' },
  categoryText: { color: '#666666', fontSize: 13, fontWeight: '600' },
  categoryTextOn: { color: '#FFFFFF' },
  fieldGroup: { gap: 8 },
  label: { color: '#111111', fontSize: 14, fontWeight: '500' },
  input: {
    minHeight: 54,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#E7E7E7',
    backgroundColor: '#FAFAFA',
    color: '#111111',
    fontSize: 16,
    fontWeight: '500',
    paddingHorizontal: 15,
  },
  textarea: { minHeight: 128, paddingTop: 14, lineHeight: 22 },
  bottomBar: { position: 'absolute', left: 0, right: 0, bottom: 0, paddingHorizontal: 18, paddingTop: 12, backgroundColor: colors.bgApp },
  shareButton: { height: 62, borderRadius: 31, backgroundColor: '#111111', alignItems: 'center', justifyContent: 'center' },
  shareButtonDisabled: { opacity: 0.35 },
  shareText: { color: '#FFFFFF', fontSize: 18, fontWeight: '500' },
});
