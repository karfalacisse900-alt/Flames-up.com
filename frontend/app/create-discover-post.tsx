import React, { useState } from 'react';
import {
  View, Text, StyleSheet, TextInput, TouchableOpacity, ScrollView,
  KeyboardAvoidingView, Platform, Alert, ActivityIndicator, Image,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import { colors } from '../src/utils/theme';
import api from '../src/api/client';

const CATEGORIES = [
  { id: 'news', label: 'Local News', icon: 'newspaper' },
  { id: 'events', label: 'Event', icon: 'calendar' },
  { id: 'culture', label: 'Culture', icon: 'color-palette' },
  { id: 'food', label: 'Food', icon: 'restaurant' },
  { id: 'lifestyle', label: 'Lifestyle', icon: 'heart' },
  { id: 'tech', label: 'Tech', icon: 'phone-portrait' },
  { id: 'tips', label: 'Tips', icon: 'bulb' },
  { id: 'spotlight', label: 'Spotlight', icon: 'flash' },
];

export default function CreateDiscoverPostScreen() {
  const router = useRouter();
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const [category, setCategory] = useState('');
  const [image, setImage] = useState<string | null>(null);
  const [eventDate, setEventDate] = useState('');
  const [eventLocation, setEventLocation] = useState('');
  const [linkUrl, setLinkUrl] = useState('');
  const [posting, setPosting] = useState(false);

  const pickImage = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({ quality: 0.7, base64: true });
    if (!result.canceled && result.assets[0]) {
      setImage(result.assets[0].base64 ? `data:image/jpeg;base64,${result.assets[0].base64}` : result.assets[0].uri);
    }
  };

  const handlePublish = async () => {
    if (!title.trim() || !content.trim() || !category) {
      Alert.alert('Missing Fields', 'Please fill in title, content and category.'); return;
    }
    setPosting(true);
    try {
      await api.post('/discover/posts', {
        title: title.trim(), content: content.trim(), category,
        image, event_date: eventDate || null, event_location: eventLocation || null,
        link_url: linkUrl || null,
      });
      Alert.alert('Published!', 'Your content is now live on Discover.', [{ text: 'OK', onPress: () => router.back() }]);
    } catch (e: any) {
      Alert.alert('Error', e.response?.data?.detail || 'Could not publish.');
    } finally { setPosting(false); }
  };

  return (
    <SafeAreaView style={s.container} edges={['top', 'bottom']}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : 'height'} style={{ flex: 1 }}>
        <View style={s.header}>
          <TouchableOpacity onPress={() => router.back()} style={s.closeBtn}>
            <Ionicons name="close" size={24} color="#1B4332" />
          </TouchableOpacity>
          <Text style={s.headerTitle}>Create Post</Text>
          <TouchableOpacity style={[s.publishBtn, (!title || !content || !category || posting) && { opacity: 0.4 }]} onPress={handlePublish} disabled={!title || !content || !category || posting}>
            {posting ? <ActivityIndicator color="#FFF" size="small" /> : <Text style={s.publishBtnText}>Publish</Text>}
          </TouchableOpacity>
        </View>

        <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ padding: 16, paddingBottom: 40 }} keyboardShouldPersistTaps="handled">
          {/* Category Selection */}
          <Text style={s.label}>Category</Text>
          <View style={s.catRow}>
            {CATEGORIES.map(c => (
              <TouchableOpacity key={c.id} style={[s.catChip, category === c.id && s.catChipActive]} onPress={() => setCategory(c.id)}>
                <Ionicons name={c.icon as any} size={14} color={category === c.id ? '#FFF' : '#5C4033'} />
                <Text style={[s.catChipText, category === c.id && { color: '#FFF' }]}>{c.label}</Text>
              </TouchableOpacity>
            ))}
          </View>

          {/* Title */}
          <TextInput style={s.titleInput} placeholder="Headline or title..." placeholderTextColor="#9CA3AF" value={title} onChangeText={setTitle} maxLength={150} />

          {/* Cover Image */}
          <TouchableOpacity style={s.imagePicker} onPress={pickImage}>
            {image ? (
              <Image source={{ uri: image }} style={s.imagePreview} />
            ) : (
              <View style={s.imagePickerEmpty}>
                <Ionicons name="image-outline" size={32} color="#9CA3AF" />
                <Text style={s.imagePickerText}>Add cover image</Text>
              </View>
            )}
          </TouchableOpacity>

          {/* Content */}
          <TextInput style={s.contentInput} placeholder="Write your article, news, review, or announcement..." placeholderTextColor="#9CA3AF" value={content} onChangeText={setContent} multiline maxLength={5000} />

          {/* Event Fields (show when events category) */}
          {category === 'events' && (
            <View style={s.eventSection}>
              <Text style={s.sectionLabel}>Event Details</Text>
              <TextInput style={s.input} placeholder="Date & Time (e.g. June 15, 2025 7:00 PM)" placeholderTextColor="#9CA3AF" value={eventDate} onChangeText={setEventDate} />
              <TextInput style={s.input} placeholder="Location name" placeholderTextColor="#9CA3AF" value={eventLocation} onChangeText={setEventLocation} />
            </View>
          )}

          {/* Link */}
          <TextInput style={s.input} placeholder="Add a link (optional)" placeholderTextColor="#9CA3AF" value={linkUrl} onChangeText={setLinkUrl} autoCapitalize="none" />
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FFF' },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: '#F0ECE5' },
  closeBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 17, fontWeight: '700', color: '#1B4332' },
  publishBtn: { paddingHorizontal: 18, paddingVertical: 8, borderRadius: 18, backgroundColor: '#2D6A4F' },
  publishBtnText: { fontSize: 14, fontWeight: '700', color: '#FFF' },
  label: { fontSize: 14, fontWeight: '700', color: '#1B4332', marginBottom: 8 },
  catRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginBottom: 20 },
  catChip: {
    flexDirection: 'row', alignItems: 'center', gap: 5,
    paddingHorizontal: 12, paddingVertical: 8, borderRadius: 16,
    backgroundColor: '#F3F0EB', borderWidth: 1, borderColor: '#E0D5C5',
  },
  catChipActive: { backgroundColor: '#2D6A4F', borderColor: '#2D6A4F' },
  catChipText: { fontSize: 12, fontWeight: '600', color: '#5C4033' },
  titleInput: { fontSize: 22, fontWeight: '800', color: '#1B4332', marginBottom: 16, lineHeight: 30 },
  imagePicker: { marginBottom: 16, borderRadius: 16, overflow: 'hidden' },
  imagePreview: { width: '100%', height: 200, borderRadius: 16 },
  imagePickerEmpty: {
    width: '100%', height: 140, borderRadius: 16, borderWidth: 2, borderStyle: 'dashed',
    borderColor: '#E0D5C5', backgroundColor: '#FAFAF8', justifyContent: 'center', alignItems: 'center',
  },
  imagePickerText: { fontSize: 13, color: '#9CA3AF', marginTop: 4 },
  contentInput: { fontSize: 16, color: '#1B4332', lineHeight: 24, minHeight: 120, textAlignVertical: 'top', marginBottom: 16 },
  eventSection: { marginBottom: 16 },
  sectionLabel: { fontSize: 14, fontWeight: '700', color: '#8B5CF6', marginBottom: 8 },
  input: {
    backgroundColor: '#FAFAF8', borderRadius: 14, borderWidth: 1, borderColor: '#E0D5C5',
    paddingHorizontal: 14, paddingVertical: 12, fontSize: 15, color: '#1B4332', marginBottom: 10,
  },
});
