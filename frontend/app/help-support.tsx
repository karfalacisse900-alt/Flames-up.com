import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Linking } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../src/utils/theme';

const FAQ_SECTIONS = [
  {
    title: 'Account',
    icon: 'person-outline' as const,
    items: [
      { q: 'I forgot my password', a: 'Tap "Forgot Password" on the login screen. We\'ll send a reset link to your email.' },
      { q: 'I can\'t log in', a: 'Make sure your email and password are correct. If the issue persists, try resetting your password or contact support.' },
      { q: 'I want to delete my account', a: 'Go to Settings > Delete Account. Your data will be removed within 30 days. You can also email support@flames-up.com.' },
    ],
  },
  {
    title: 'Posts',
    icon: 'create-outline' as const,
    items: [
      { q: 'How to create a post', a: 'Tap the + button on the home screen. Add text, photos, or choose a post type (lifestyle, check-in, question).' },
      { q: 'How check-ins work', a: 'When you\'re near a place, you can create a check-in post. Flames-Up verifies your proximity (within 200m) to ensure authentic posts.' },
      { q: 'How to delete my post', a: 'Open your post, tap the three dots menu, and select Delete. This action cannot be undone.' },
    ],
  },
  {
    title: 'Safety',
    icon: 'shield-outline' as const,
    items: [
      { q: 'Report a post or user', a: 'Tap the three dots on any post or profile and select Report. Our moderation team reviews all reports within 24-48 hours.' },
      { q: 'Block someone', a: 'Go to the user\'s profile, tap the three dots, and select Block. Blocked users can\'t see your content or contact you.' },
      { q: 'Community guidelines', a: 'Read our full Community Guidelines in Settings > Community Guidelines. We take community safety seriously.' },
    ],
  },
];

export default function HelpSupportScreen() {
  const router = useRouter();
  const [expandedSection, setExpandedSection] = useState<number | null>(null);
  const [expandedItem, setExpandedItem] = useState<string | null>(null);

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={s.headerTitle}>Help & Support</Text>
        <View style={{ width: 44 }} />
      </View>

      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={s.content}>
        <Text style={s.subtitle}>Need help? We've got you.</Text>

        <Text style={s.sectionLabel}>COMMON TOPICS</Text>

        {FAQ_SECTIONS.map((section, sIdx) => (
          <View key={section.title} style={s.card}>
            <TouchableOpacity
              style={s.sectionHeader}
              onPress={() => setExpandedSection(expandedSection === sIdx ? null : sIdx)}
            >
              <View style={s.sectionIcon}>
                <Ionicons name={section.icon} size={18} color={colors.accentPrimary} />
              </View>
              <Text style={s.sectionTitle}>{section.title}</Text>
              <Ionicons
                name={expandedSection === sIdx ? 'chevron-up' : 'chevron-down'}
                size={18}
                color={colors.textHint}
              />
            </TouchableOpacity>
            {expandedSection === sIdx && section.items.map((item) => (
              <View key={item.q}>
                <TouchableOpacity
                  style={s.faqItem}
                  onPress={() => setExpandedItem(expandedItem === item.q ? null : item.q)}
                >
                  <Text style={s.faqQ}>{item.q}</Text>
                  <Ionicons
                    name={expandedItem === item.q ? 'remove' : 'add'}
                    size={16}
                    color={colors.textHint}
                  />
                </TouchableOpacity>
                {expandedItem === item.q && (
                  <View style={s.faqAnswer}>
                    <Text style={s.faqA}>{item.a}</Text>
                  </View>
                )}
              </View>
            ))}
          </View>
        ))}

        <Text style={s.sectionLabel}>CONTACT SUPPORT</Text>
        <View style={s.card}>
          <TouchableOpacity
            style={s.contactRow}
            onPress={() => Linking.openURL('mailto:support@flames-up.com')}
          >
            <View style={s.sectionIcon}>
              <Ionicons name="mail-outline" size={18} color={colors.accentPrimary} />
            </View>
            <View style={{ flex: 1 }}>
              <Text style={s.contactLabel}>Email</Text>
              <Text style={s.contactValue}>support@flames-up.com</Text>
            </View>
            <Ionicons name="open-outline" size={16} color={colors.textHint} />
          </TouchableOpacity>
          <View style={s.responseNote}>
            <Ionicons name="time-outline" size={14} color={colors.textHint} />
            <Text style={s.responseText}>Response time: 24-72 hours</Text>
          </View>
        </View>

        <View style={s.card}>
          <Text style={s.urgentTitle}>Something urgent or safety-related?</Text>
          <Text style={s.urgentBody}>Include in your email:</Text>
          <View style={s.bulletList}>
            <Text style={s.bullet}>• Your username</Text>
            <Text style={s.bullet}>• Screenshots (if possible)</Text>
            <Text style={s.bullet}>• The post/user link</Text>
          </View>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bgApp },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: colors.borderSubtle },
  backBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 18, fontWeight: '700', color: colors.textPrimary, fontStyle: 'italic' },
  content: { padding: 20, paddingBottom: 60 },
  subtitle: { fontSize: 17, fontWeight: '600', color: colors.textPrimary, marginBottom: 24 },
  sectionLabel: { fontSize: 12, fontWeight: '800', color: colors.textHint, letterSpacing: 0.5, marginBottom: 10, marginTop: 8 },
  card: { backgroundColor: colors.bgCard, borderRadius: 20, marginBottom: 16, borderWidth: 1, borderColor: colors.borderLight, overflow: 'hidden' },
  sectionHeader: { flexDirection: 'row', alignItems: 'center', padding: 16 },
  sectionIcon: { width: 36, height: 36, borderRadius: 12, backgroundColor: colors.accentPrimaryLight, justifyContent: 'center', alignItems: 'center', marginRight: 14 },
  sectionTitle: { flex: 1, fontSize: 16, fontWeight: '600', color: colors.textPrimary },
  faqItem: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 20, paddingVertical: 14, borderTopWidth: 1, borderTopColor: colors.borderSubtle },
  faqQ: { fontSize: 14, fontWeight: '500', color: colors.textPrimary, flex: 1, marginRight: 8 },
  faqAnswer: { paddingHorizontal: 20, paddingBottom: 14, backgroundColor: colors.bgSubtle },
  faqA: { fontSize: 14, color: colors.textSecondary, lineHeight: 21 },
  contactRow: { flexDirection: 'row', alignItems: 'center', padding: 16 },
  contactLabel: { fontSize: 15, fontWeight: '600', color: colors.textPrimary },
  contactValue: { fontSize: 13, color: colors.accentPrimary, marginTop: 2 },
  responseNote: { flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 16, paddingBottom: 14, paddingTop: 4, borderTopWidth: 1, borderTopColor: colors.borderSubtle },
  responseText: { fontSize: 13, color: colors.textHint },
  urgentTitle: { fontSize: 15, fontWeight: '600', color: colors.textPrimary, padding: 16, paddingBottom: 4 },
  urgentBody: { fontSize: 14, color: colors.textSecondary, paddingHorizontal: 16, marginBottom: 8 },
  bulletList: { paddingHorizontal: 20, paddingBottom: 16 },
  bullet: { fontSize: 14, color: colors.textSecondary, lineHeight: 24 },
});
