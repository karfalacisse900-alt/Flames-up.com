import React, { useState } from 'react';
import {
  View, Text, StyleSheet, TextInput, TouchableOpacity, ScrollView,
  KeyboardAvoidingView, Platform, Alert, ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../src/utils/theme';
import api from '../src/api/client';

const CATEGORIES = [
  { id: 'food', label: 'Food & Drink', icon: 'restaurant' },
  { id: 'culture', label: 'Culture & Arts', icon: 'color-palette' },
  { id: 'news', label: 'Local News', icon: 'newspaper' },
  { id: 'events', label: 'Events', icon: 'calendar' },
  { id: 'lifestyle', label: 'Lifestyle', icon: 'heart' },
  { id: 'tech', label: 'Tech & Digital', icon: 'phone-portrait' },
  { id: 'health', label: 'Health & Wellness', icon: 'fitness' },
  { id: 'education', label: 'Education', icon: 'school' },
];

export default function PublisherApplyScreen() {
  const router = useRouter();
  const [step, setStep] = useState(1);
  const [loading, setLoading] = useState(false);
  const [form, setForm] = useState({
    business_name: '', category: '', about: '', phone: '', website: '',
    social_instagram: '', social_twitter: '', social_tiktok: '',
    address: '', city: '', why_publish: '',
  });

  const update = (key: string, val: string) => setForm(prev => ({ ...prev, [key]: val }));

  const handleSubmit = async () => {
    if (!form.business_name || !form.category || !form.about || !form.phone || !form.why_publish) {
      Alert.alert('Missing Info', 'Please fill in all required fields.'); return;
    }
    setLoading(true);
    try {
      await api.post('/publisher/apply', form);
      Alert.alert('Application Submitted!', 'We will review your application and notify you once approved.', [
        { text: 'OK', onPress: () => router.back() },
      ]);
    } catch (e: any) {
      Alert.alert('Error', e.response?.data?.detail || 'Could not submit application.');
    } finally { setLoading(false); }
  };

  const renderInput = (label: string, key: string, placeholder: string, opts: any = {}) => (
    <View style={s.field}>
      <Text style={s.label}>{label} {opts.required && <Text style={{ color: '#EF4444' }}>*</Text>}</Text>
      <TextInput
        style={[s.input, opts.multiline && s.textArea]}
        placeholder={placeholder}
        placeholderTextColor="#9CA3AF"
        value={(form as any)[key]}
        onChangeText={(v) => update(key, v)}
        multiline={opts.multiline}
        numberOfLines={opts.multiline ? 4 : 1}
        keyboardType={opts.keyboard || 'default'}
        autoCapitalize={opts.noCapitalize ? 'none' : 'sentences'}
      />
    </View>
  );

  return (
    <SafeAreaView style={s.container} edges={['top', 'bottom']}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : 'height'} style={{ flex: 1 }}>
        {/* Header */}
        <View style={s.header}>
          <TouchableOpacity onPress={() => router.back()} style={s.backBtn}>
            <Ionicons name="arrow-back" size={22} color="#1B4332" />
          </TouchableOpacity>
          <Text style={s.headerTitle}>Become a Publisher</Text>
          <View style={{ width: 44 }} />
        </View>

        {/* Progress */}
        <View style={s.progress}>
          {[1, 2, 3].map(i => (
            <View key={i} style={[s.progressDot, step >= i && s.progressDotActive]} />
          ))}
        </View>

        <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ padding: 16, paddingBottom: 40 }} keyboardShouldPersistTaps="handled">
          {step === 1 && (
            <>
              <Text style={s.stepTitle}>About You & Your Brand</Text>
              <Text style={s.stepDesc}>Tell us about what you want to publish on Flames-Up.</Text>
              {renderInput('Publisher / Business Name', 'business_name', 'e.g. NYC Food Guide, Bronx Daily News...', { required: true })}
              <View style={s.field}>
                <Text style={s.label}>Category <Text style={{ color: '#EF4444' }}>*</Text></Text>
                <View style={s.catGrid}>
                  {CATEGORIES.map(c => (
                    <TouchableOpacity key={c.id}
                      style={[s.catChip, form.category === c.id && s.catChipActive]}
                      onPress={() => update('category', c.id)}>
                      <Ionicons name={c.icon as any} size={16} color={form.category === c.id ? '#FFF' : '#5C4033'} />
                      <Text style={[s.catChipText, form.category === c.id && { color: '#FFF' }]}>{c.label}</Text>
                    </TouchableOpacity>
                  ))}
                </View>
              </View>
              {renderInput('About', 'about', 'Describe what you publish, your expertise, your audience...', { required: true, multiline: true })}
              <TouchableOpacity style={s.nextBtn} onPress={() => { if (!form.business_name || !form.category || !form.about) { Alert.alert('Required', 'Fill in name, category and about.'); return; } setStep(2); }}>
                <Text style={s.nextBtnText}>Continue</Text>
                <Ionicons name="arrow-forward" size={18} color="#FFF" />
              </TouchableOpacity>
            </>
          )}

          {step === 2 && (
            <>
              <Text style={s.stepTitle}>Contact & Social</Text>
              <Text style={s.stepDesc}>How can people and our team reach you?</Text>
              {renderInput('Phone Number', 'phone', '+1 (555) 000-0000', { required: true, keyboard: 'phone-pad' })}
              {renderInput('Website (optional)', 'website', 'https://...', { noCapitalize: true })}
              {renderInput('Instagram (optional)', 'social_instagram', '@youraccount', { noCapitalize: true })}
              {renderInput('Twitter / X (optional)', 'social_twitter', '@youraccount', { noCapitalize: true })}
              {renderInput('TikTok (optional)', 'social_tiktok', '@youraccount', { noCapitalize: true })}
              <View style={{ flexDirection: 'row', gap: 10 }}>
                <TouchableOpacity style={s.backStepBtn} onPress={() => setStep(1)}>
                  <Ionicons name="arrow-back" size={18} color="#2D6A4F" />
                  <Text style={s.backStepText}>Back</Text>
                </TouchableOpacity>
                <TouchableOpacity style={[s.nextBtn, { flex: 1 }]} onPress={() => { if (!form.phone) { Alert.alert('Required', 'Phone number is required.'); return; } setStep(3); }}>
                  <Text style={s.nextBtnText}>Continue</Text>
                  <Ionicons name="arrow-forward" size={18} color="#FFF" />
                </TouchableOpacity>
              </View>
            </>
          )}

          {step === 3 && (
            <>
              <Text style={s.stepTitle}>Location & Motivation</Text>
              <Text style={s.stepDesc}>Last step — tell us where you're based and why you want to publish.</Text>
              {renderInput('Address (optional)', 'address', 'Street address...')}
              {renderInput('City', 'city', 'New York, NY')}
              {renderInput('Why do you want to publish?', 'why_publish', 'What kind of content will you share? Why should the community trust you?', { required: true, multiline: true })}
              <View style={{ flexDirection: 'row', gap: 10 }}>
                <TouchableOpacity style={s.backStepBtn} onPress={() => setStep(2)}>
                  <Ionicons name="arrow-back" size={18} color="#2D6A4F" />
                  <Text style={s.backStepText}>Back</Text>
                </TouchableOpacity>
                <TouchableOpacity style={[s.submitBtn, { flex: 1 }]} onPress={handleSubmit} disabled={loading}>
                  {loading ? <ActivityIndicator color="#FFF" /> : (
                    <><Ionicons name="checkmark-circle" size={18} color="#FFF" /><Text style={s.submitBtnText}>Submit Application</Text></>
                  )}
                </TouchableOpacity>
              </View>
            </>
          )}
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FAFAF8' },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingVertical: 12 },
  backBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 18, fontWeight: '700', color: '#1B4332' },
  progress: { flexDirection: 'row', justifyContent: 'center', gap: 8, paddingVertical: 8 },
  progressDot: { width: 32, height: 4, borderRadius: 2, backgroundColor: '#E0D5C5' },
  progressDotActive: { backgroundColor: '#2D6A4F' },
  stepTitle: { fontSize: 22, fontWeight: '800', color: '#1B4332', marginBottom: 4 },
  stepDesc: { fontSize: 14, color: '#6B7280', marginBottom: 20, lineHeight: 20 },
  field: { marginBottom: 18 },
  label: { fontSize: 14, fontWeight: '700', color: '#1B4332', marginBottom: 6 },
  input: {
    backgroundColor: '#FFF', borderRadius: 14, borderWidth: 1, borderColor: '#E0D5C5',
    paddingHorizontal: 14, paddingVertical: 12, fontSize: 15, color: '#1B4332',
  },
  textArea: { minHeight: 100, textAlignVertical: 'top' },
  catGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  catChip: {
    flexDirection: 'row', alignItems: 'center', gap: 5,
    paddingHorizontal: 12, paddingVertical: 8, borderRadius: 16,
    backgroundColor: '#F3F0EB', borderWidth: 1, borderColor: '#E0D5C5',
  },
  catChipActive: { backgroundColor: '#2D6A4F', borderColor: '#2D6A4F' },
  catChipText: { fontSize: 12, fontWeight: '600', color: '#5C4033' },
  nextBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8,
    paddingVertical: 14, borderRadius: 20, backgroundColor: '#2D6A4F', marginTop: 8,
  },
  nextBtnText: { fontSize: 15, fontWeight: '700', color: '#FFF' },
  backStepBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 4,
    paddingVertical: 14, paddingHorizontal: 20, borderRadius: 20,
    backgroundColor: '#E8F5E9', borderWidth: 1, borderColor: '#A5D6A7', marginTop: 8,
  },
  backStepText: { fontSize: 14, fontWeight: '600', color: '#2D6A4F' },
  submitBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8,
    paddingVertical: 14, borderRadius: 20, backgroundColor: '#10B981', marginTop: 8,
  },
  submitBtnText: { fontSize: 15, fontWeight: '700', color: '#FFF' },
});
