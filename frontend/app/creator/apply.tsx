import React, { useState, useEffect } from 'react';
import {
  View, Text, StyleSheet, ScrollView, TouchableOpacity, TextInput,
  Alert, ActivityIndicator, KeyboardAvoidingView, Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../../src/utils/theme';
import api from '../../src/api/client';

const CATEGORIES = [
  { id: 'photographer', name: 'Photographer', icon: 'camera-outline' },
  { id: 'artist', name: 'Artist', icon: 'color-palette-outline' },
  { id: 'musician', name: 'Musician', icon: 'musical-notes-outline' },
  { id: 'model', name: 'Model', icon: 'body-outline' },
  { id: 'stylist', name: 'Stylist', icon: 'cut-outline' },
  { id: 'dancer', name: 'Dancer', icon: 'walk-outline' },
  { id: 'influencer', name: 'Influencer', icon: 'star-outline' },
  { id: 'chef', name: 'Chef', icon: 'restaurant-outline' },
  { id: 'filmmaker', name: 'Filmmaker', icon: 'videocam-outline' },
  { id: 'designer', name: 'Designer', icon: 'brush-outline' },
  { id: 'writer', name: 'Writer', icon: 'pencil-outline' },
  { id: 'dj', name: 'DJ', icon: 'headset-outline' },
];

export default function CreatorApplyScreen() {
  const router = useRouter();
  const [category, setCategory] = useState('');
  const [shortBio, setShortBio] = useState('');
  const [city, setCity] = useState('');
  const [instagram, setInstagram] = useState('');
  const [tiktok, setTiktok] = useState('');
  const [website, setWebsite] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [existingStatus, setExistingStatus] = useState<string | null>(null);

  useEffect(() => {
    checkStatus();
  }, []);

  const checkStatus = async () => {
    try {
      const res = await api.get('/creators/me');
      if (res.data?.status) setExistingStatus(res.data.status);
    } catch {}
  };

  const handleSubmit = async () => {
    if (!category) { Alert.alert('Required', 'Please select a category'); return; }
    if (!shortBio.trim()) { Alert.alert('Required', 'Please write a short bio'); return; }

    setIsSubmitting(true);
    try {
      const portfolioLinks = [instagram, tiktok, website].filter(Boolean);
      await api.post('/creators/apply', {
        category, short_bio: shortBio.trim(), city: city.trim(),
        portfolio_links: portfolioLinks,
      });
      Alert.alert(
        'Application Submitted!',
        'Your creator application is under review. We\'ll notify you once approved.',
        [{ text: 'OK', onPress: () => router.back() }]
      );
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.detail || 'Could not submit application');
    } finally {
      setIsSubmitting(false);
    }
  };

  if (existingStatus === 'approved') {
    return (
      <SafeAreaView style={s.container} edges={['top']}>
        <View style={s.header}>
          <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
            <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
          </TouchableOpacity>
          <Text style={s.headerTitle}>Creator Status</Text>
          <View style={{ width: 44 }} />
        </View>
        <View style={s.statusCard}>
          <Ionicons name="checkmark-circle" size={48} color="#16A34A" />
          <Text style={s.statusTitle}>You're a Creator!</Text>
          <Text style={s.statusBody}>Your creator profile is live. Manage it from your profile page.</Text>
        </View>
      </SafeAreaView>
    );
  }

  if (existingStatus === 'pending') {
    return (
      <SafeAreaView style={s.container} edges={['top']}>
        <View style={s.header}>
          <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
            <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
          </TouchableOpacity>
          <Text style={s.headerTitle}>Creator Status</Text>
          <View style={{ width: 44 }} />
        </View>
        <View style={s.statusCard}>
          <Ionicons name="time" size={48} color="#F59E0B" />
          <Text style={s.statusTitle}>Application Pending</Text>
          <Text style={s.statusBody}>Your creator application is being reviewed. We'll get back to you soon!</Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={s.headerTitle}>Become a Creator</Text>
        <View style={{ width: 44 }} />
      </View>

      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
        <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={s.content}>
          <Text style={s.sectionLabel}>SELECT YOUR CATEGORY</Text>
          <View style={s.categoryGrid}>
            {CATEGORIES.map((cat) => (
              <TouchableOpacity
                key={cat.id}
                style={[s.categoryChip, category === cat.id && s.categoryChipActive]}
                onPress={() => setCategory(cat.id)}
              >
                <Ionicons name={cat.icon as any} size={16} color={category === cat.id ? '#FFFFFF' : colors.textSecondary} />
                <Text style={[s.categoryChipText, category === cat.id && { color: '#FFFFFF' }]}>{cat.name}</Text>
              </TouchableOpacity>
            ))}
          </View>

          <Text style={s.sectionLabel}>ABOUT YOU</Text>
          <View style={s.inputCard}>
            <Text style={s.inputLabel}>Short Bio *</Text>
            <TextInput
              style={[s.input, s.inputMultiline]}
              placeholder="Tell us about your work and passion..."
              placeholderTextColor={colors.textHint}
              value={shortBio}
              onChangeText={setShortBio}
              multiline
              numberOfLines={4}
              textAlignVertical="top"
              maxLength={500}
            />
            <Text style={s.charCount}>{shortBio.length}/500</Text>

            <Text style={s.inputLabel}>City</Text>
            <TextInput
              style={s.input}
              placeholder="e.g. New York"
              placeholderTextColor={colors.textHint}
              value={city}
              onChangeText={setCity}
            />
          </View>

          <Text style={s.sectionLabel}>PORTFOLIO LINKS</Text>
          <View style={s.inputCard}>
            <View style={s.linkRow}>
              <Ionicons name="logo-instagram" size={20} color="#E1306C" />
              <TextInput
                style={[s.input, { flex: 1 }]}
                placeholder="Instagram profile URL"
                placeholderTextColor={colors.textHint}
                value={instagram}
                onChangeText={setInstagram}
                autoCapitalize="none"
              />
            </View>
            <View style={s.linkRow}>
              <Ionicons name="logo-tiktok" size={20} color={colors.textPrimary} />
              <TextInput
                style={[s.input, { flex: 1 }]}
                placeholder="TikTok profile URL"
                placeholderTextColor={colors.textHint}
                value={tiktok}
                onChangeText={setTiktok}
                autoCapitalize="none"
              />
            </View>
            <View style={s.linkRow}>
              <Ionicons name="globe-outline" size={20} color={colors.accentPrimary} />
              <TextInput
                style={[s.input, { flex: 1 }]}
                placeholder="Website URL"
                placeholderTextColor={colors.textHint}
                value={website}
                onChangeText={setWebsite}
                autoCapitalize="none"
              />
            </View>
          </View>

          <TouchableOpacity
            style={[s.submitBtn, isSubmitting && { opacity: 0.6 }]}
            onPress={handleSubmit}
            disabled={isSubmitting}
          >
            {isSubmitting ? (
              <ActivityIndicator color="#FFFFFF" />
            ) : (
              <Text style={s.submitBtnText}>Submit Application</Text>
            )}
          </TouchableOpacity>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bgApp },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: colors.borderSubtle },
  backBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 18, fontWeight: '700', color: colors.textPrimary, fontStyle: 'italic' },
  content: { padding: 20, paddingBottom: 60 },
  sectionLabel: { fontSize: 12, fontWeight: '800', color: colors.textHint, letterSpacing: 0.5, marginBottom: 10, marginTop: 16 },
  categoryGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  categoryChip: { flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 14, paddingVertical: 10, borderRadius: 20, backgroundColor: colors.bgCard, borderWidth: 1, borderColor: colors.borderLight },
  categoryChipActive: { backgroundColor: colors.accentPrimary, borderColor: colors.accentPrimary },
  categoryChipText: { fontSize: 13, fontWeight: '600', color: colors.textSecondary },
  inputCard: { backgroundColor: colors.bgCard, borderRadius: 20, padding: 16, borderWidth: 1, borderColor: colors.borderLight },
  inputLabel: { fontSize: 13, fontWeight: '600', color: colors.textPrimary, marginBottom: 6, marginTop: 12 },
  input: { backgroundColor: colors.bgSubtle, borderRadius: 12, paddingHorizontal: 14, paddingVertical: 12, fontSize: 15, color: colors.textPrimary, borderWidth: 1, borderColor: colors.borderLight },
  inputMultiline: { height: 100, textAlignVertical: 'top' },
  charCount: { fontSize: 11, color: colors.textHint, textAlign: 'right', marginTop: 4 },
  linkRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 8 },
  submitBtn: { backgroundColor: colors.accentPrimary, borderRadius: 20, paddingVertical: 16, alignItems: 'center', marginTop: 24 },
  submitBtnText: { fontSize: 16, fontWeight: '700', color: '#FFFFFF' },
  statusCard: { alignItems: 'center', padding: 40, margin: 20, backgroundColor: colors.bgCard, borderRadius: 24, borderWidth: 1, borderColor: colors.borderLight },
  statusTitle: { fontSize: 20, fontWeight: '800', color: colors.textPrimary, marginTop: 16 },
  statusBody: { fontSize: 15, color: colors.textSecondary, textAlign: 'center', marginTop: 8, lineHeight: 22 },
});
