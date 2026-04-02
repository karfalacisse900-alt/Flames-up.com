import React from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../src/utils/theme';

const RULES = [
  {
    icon: 'heart-outline' as const,
    title: 'Be Real',
    body: 'Flames-Up is for real people and real experiences. Fake accounts, spam, and misleading content may be removed.',
  },
  {
    icon: 'hand-left-outline' as const,
    title: 'No Hate or Harassment',
    body: 'We do not allow:\n• Hate speech\n• Threats\n• Bullying\n• Targeted harassment',
  },
  {
    icon: 'shield-outline' as const,
    title: 'No Sexual Content Involving Minors',
    body: 'Any sexual content involving minors will be reported to authorities.',
  },
  {
    icon: 'ban-outline' as const,
    title: 'No Illegal Activity',
    body: 'No promotion of illegal activity, scams, or fraud.',
  },
  {
    icon: 'person-outline' as const,
    title: 'No Impersonation',
    body: 'Do not pretend to be someone else.',
  },
  {
    icon: 'lock-closed-outline' as const,
    title: 'Respect Privacy',
    body: 'Do not post:\n• Private addresses\n• Phone numbers\n• Private conversations\n• Sensitive personal information',
  },
  {
    icon: 'location-outline' as const,
    title: 'Local Posting Integrity',
    body: 'Check-in posts are meant to reflect real presence at a location. Misuse may lead to restrictions.',
  },
];

export default function CommunityGuidelinesScreen() {
  const router = useRouter();

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={s.headerTitle}>Community Guidelines</Text>
        <View style={{ width: 44 }} />
      </View>

      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={s.content}>
        <Text style={s.intro}>
          Flames-Up is a local community app. Respect matters.
        </Text>

        {RULES.map((rule) => (
          <View key={rule.title} style={s.card}>
            <View style={s.cardHeader}>
              <View style={s.iconCircle}>
                <Ionicons name={rule.icon} size={18} color={colors.accentPrimary} />
              </View>
              <Text style={s.cardTitle}>{rule.title}</Text>
            </View>
            <Text style={s.cardBody}>{rule.body}</Text>
          </View>
        ))}

        <View style={s.enforcementCard}>
          <Text style={s.enforcementTitle}>Enforcement</Text>
          <Text style={s.enforcementBody}>We may:</Text>
          <Text style={s.enforcementItem}>• Remove content</Text>
          <Text style={s.enforcementItem}>• Restrict features</Text>
          <Text style={s.enforcementItem}>• Suspend or ban accounts</Text>
          <Text style={[s.enforcementBody, { marginTop: 12 }]}>Appeals can be requested via support.</Text>
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
  intro: { fontSize: 17, fontWeight: '600', color: colors.textPrimary, marginBottom: 20, lineHeight: 24 },
  card: { backgroundColor: colors.bgCard, borderRadius: 20, padding: 20, marginBottom: 12, borderWidth: 1, borderColor: colors.borderLight },
  cardHeader: { flexDirection: 'row', alignItems: 'center', marginBottom: 10 },
  iconCircle: { width: 36, height: 36, borderRadius: 12, backgroundColor: colors.accentPrimaryLight, justifyContent: 'center', alignItems: 'center', marginRight: 12 },
  cardTitle: { fontSize: 16, fontWeight: '700', color: colors.textPrimary },
  cardBody: { fontSize: 14, color: colors.textSecondary, lineHeight: 22 },
  enforcementCard: { backgroundColor: '#FFF7ED', borderRadius: 20, padding: 20, marginTop: 8, borderWidth: 1, borderColor: '#FDBA74' },
  enforcementTitle: { fontSize: 16, fontWeight: '700', color: '#9A3412', marginBottom: 8 },
  enforcementBody: { fontSize: 14, color: '#9A3412', lineHeight: 22 },
  enforcementItem: { fontSize: 14, color: '#9A3412', lineHeight: 24, paddingLeft: 4 },
});
