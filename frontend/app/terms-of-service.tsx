import React from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Linking } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../src/utils/theme';

const SECTIONS = [
  {
    title: 'Eligibility',
    body: 'You must be at least 13 years old to use Flames-Up. If you are under 18, you must have permission from a parent/guardian.',
  },
  {
    title: 'Accounts',
    body: 'You are responsible for keeping your account secure. Do not share your password.',
  },
  {
    title: 'User Content',
    body: 'You own the content you post, but you give Flames-Up a license to host, display, and distribute it within the app to provide the service.\n\nYou must have the rights to upload any content you post.',
  },
  {
    title: 'Prohibited Conduct',
    body: 'You agree not to:\n• Harass or threaten others\n• Post hate speech or illegal content\n• Impersonate others\n• Spam or manipulate engagement\n• Attempt to hack or abuse the platform',
  },
  {
    title: 'Moderation',
    body: 'We may remove content or accounts that violate rules. We are not required to provide warnings.',
  },
  {
    title: 'No Guarantee',
    body: 'Flames-Up is provided "as is". We do not guarantee uninterrupted service.',
  },
  {
    title: 'Limitation of Liability',
    body: 'Flames-Up is not responsible for:\n• User-generated content\n• Real-world meetups\n• Disputes between users\n• Losses caused by service interruptions',
  },
  {
    title: 'Termination',
    body: 'We may suspend or terminate accounts that violate these Terms.',
  },
  {
    title: 'Changes',
    body: 'We may update these Terms. Continued use means acceptance.',
  },
];

export default function TermsOfServiceScreen() {
  const router = useRouter();

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={s.headerTitle}>Terms of Service</Text>
        <View style={{ width: 44 }} />
      </View>

      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={s.content}>
        <Text style={s.appTitle}>Terms of Service — Flames-Up</Text>
        <Text style={s.effectiveDate}>Effective Date: January 1, 2025</Text>
        <Text style={s.intro}>By using Flames-Up, you agree to these Terms.</Text>

        {SECTIONS.map((section, idx) => (
          <View key={idx} style={s.card}>
            <Text style={s.sectionTitle}>{section.title}</Text>
            <Text style={s.sectionBody}>{section.body}</Text>
          </View>
        ))}

        <View style={s.contactCard}>
          <Text style={s.contactTitle}>Contact</Text>
          <TouchableOpacity onPress={() => Linking.openURL('mailto:support@flames-up.com')}>
            <Text style={s.contactEmail}>support@flames-up.com</Text>
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
