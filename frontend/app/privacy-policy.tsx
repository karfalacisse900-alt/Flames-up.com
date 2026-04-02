import React from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Linking } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../src/utils/theme';

const SECTIONS = [
  {
    title: 'Information We Collect',
    body: 'We may collect:\n• Email address and username\n• Profile info (bio, avatar, social links)\n• Posts and comments you create\n• Approximate location (city/borough)\n• Device and usage data (for security/performance)\n• Check-in location data (when you choose to post at a place)',
  },
  {
    title: 'Location Data',
    body: 'Flames-Up uses location data to show nearby content and places. We may store approximate coordinates for:\n\n• Feed personalization\n• Place tagging\n• Map discovery\n\nWe do not sell your location data.\n\nYou can disable location permissions in your device settings, but some features may not work.',
  },
  {
    title: 'How We Use Your Information',
    body: 'We use your data to:\n• Provide the app services\n• Show relevant local posts and places\n• Prevent fraud, spam, and abuse\n• Improve performance and user experience\n• Respond to support requests',
  },
  {
    title: 'Sharing of Information',
    body: 'We may share limited data with service providers for:\n• Hosting and infrastructure (Cloudflare)\n• Analytics and error monitoring\n• Security and abuse prevention\n\nWe do not sell personal data.',
  },
  {
    title: 'Content Visibility',
    body: 'Your posts and profile may be visible to other users depending on privacy settings. Some content may be publicly accessible if shared externally.',
  },
  {
    title: 'Data Retention',
    body: 'We keep your data while your account is active. If you delete your account, we will remove or anonymize your personal data, except where legally required.',
  },
  {
    title: 'Security',
    body: 'We use encryption, access controls, and secure storage practices. However, no system is 100% secure.',
  },
  {
    title: 'Children',
    body: 'Flames-Up is not intended for users under 13. If we learn a user is under 13, we will remove the account.',
  },
  {
    title: 'Your Rights',
    body: 'You may request:\n• A copy of your data\n• Deletion of your account\n• Correction of profile information',
  },
];

export default function PrivacyPolicyScreen() {
  const router = useRouter();

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={s.headerTitle}>Privacy Policy</Text>
        <View style={{ width: 44 }} />
      </View>

      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={s.content}>
        <Text style={s.appTitle}>Privacy Policy — Flames-Up</Text>
        <Text style={s.effectiveDate}>Effective Date: January 1, 2025</Text>
        <Text style={s.intro}>
          Flames-Up ("we", "us", "our") respects your privacy. This Privacy Policy explains what we collect and how we use it.
        </Text>

        {SECTIONS.map((section, idx) => (
          <View key={idx} style={s.card}>
            <Text style={s.sectionTitle}>{section.title}</Text>
            <Text style={s.sectionBody}>{section.body}</Text>
          </View>
        ))}

        <View style={s.contactCard}>
          <Text style={s.contactTitle}>Contact</Text>
          <TouchableOpacity onPress={() => Linking.openURL('mailto:privacy@flames-up.com')}>
            <Text style={s.contactEmail}>privacy@flames-up.com</Text>
          </TouchableOpacity>
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
  appTitle: { fontSize: 20, fontWeight: '800', color: colors.textPrimary, marginBottom: 4 },
  effectiveDate: { fontSize: 13, color: colors.textHint, marginBottom: 16 },
  intro: { fontSize: 15, color: colors.textSecondary, lineHeight: 23, marginBottom: 20 },
  card: { backgroundColor: colors.bgCard, borderRadius: 20, padding: 20, marginBottom: 12, borderWidth: 1, borderColor: colors.borderLight },
  sectionTitle: { fontSize: 16, fontWeight: '700', color: colors.textPrimary, marginBottom: 8 },
  sectionBody: { fontSize: 14, color: colors.textSecondary, lineHeight: 22 },
  contactCard: { backgroundColor: colors.accentPrimaryLight, borderRadius: 20, padding: 20, marginTop: 8, alignItems: 'center' },
  contactTitle: { fontSize: 15, fontWeight: '600', color: colors.textPrimary, marginBottom: 4 },
  contactEmail: { fontSize: 15, fontWeight: '600', color: colors.accentPrimary },
});
