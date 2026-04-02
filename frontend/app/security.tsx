import React from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Linking } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../src/utils/theme';

const PROTECTIONS = [
  { icon: 'key-outline' as const, title: 'Account login security' },
  { icon: 'person-outline' as const, title: 'Personal profile information' },
  { icon: 'image-outline' as const, title: 'Uploaded media' },
  { icon: 'server-outline' as const, title: 'System integrity and abuse prevention' },
];

const MEASURES = [
  { icon: 'lock-closed-outline' as const, title: 'Secure authentication' },
  { icon: 'finger-print-outline' as const, title: 'Hashed passwords' },
  { icon: 'globe-outline' as const, title: 'Encrypted connections (HTTPS)' },
  { icon: 'speedometer-outline' as const, title: 'Rate limiting and abuse detection' },
  { icon: 'flag-outline' as const, title: 'Content reporting and moderation tools' },
  { icon: 'cloud-outline' as const, title: 'Cloudflare security protections' },
];

export default function SecurityScreen() {
  const router = useRouter();

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={s.headerTitle}>Security</Text>
        <View style={{ width: 44 }} />
      </View>

      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={s.content}>
        <View style={s.heroCard}>
          <View style={s.heroIcon}>
            <Ionicons name="shield-checkmark" size={32} color={colors.accentPrimary} />
          </View>
          <Text style={s.heroTitle}>Security at Flames-Up</Text>
          <Text style={s.heroBody}>We take user security seriously.</Text>
        </View>

        <Text style={s.sectionLabel}>WHAT WE PROTECT</Text>
        <View style={s.card}>
          {PROTECTIONS.map((item) => (
            <View key={item.title} style={s.itemRow}>
              <View style={s.itemIcon}>
                <Ionicons name={item.icon} size={16} color={colors.accentPrimary} />
              </View>
              <Text style={s.itemText}>{item.title}</Text>
            </View>
          ))}
        </View>

        <Text style={s.sectionLabel}>SECURITY MEASURES</Text>
        <View style={s.card}>
          {MEASURES.map((item) => (
            <View key={item.title} style={s.itemRow}>
              <View style={s.itemIcon}>
                <Ionicons name={item.icon} size={16} color={'#16A34A'} />
              </View>
              <Text style={s.itemText}>{item.title}</Text>
            </View>
          ))}
        </View>

        <Text style={s.sectionLabel}>REPORT A SECURITY ISSUE</Text>
        <View style={s.card}>
          <Text style={s.reportBody}>If you find a vulnerability, email:</Text>
          <TouchableOpacity onPress={() => Linking.openURL('mailto:security@flames-up.com')}>
            <Text style={s.reportEmail}>security@flames-up.com</Text>
          </TouchableOpacity>
          <Text style={[s.reportBody, { marginTop: 12 }]}>Please include:</Text>
          <Text style={s.reportItem}>• Steps to reproduce</Text>
          <Text style={s.reportItem}>• Screenshots or logs if possible</Text>
          <View style={s.warningBox}>
            <Ionicons name="warning-outline" size={16} color="#DC2626" />
            <Text style={s.warningText}>We do not tolerate malicious exploitation.</Text>
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
  heroCard: { backgroundColor: colors.accentPrimaryLight, borderRadius: 24, padding: 28, alignItems: 'center', marginBottom: 24 },
  heroIcon: { width: 64, height: 64, borderRadius: 32, backgroundColor: '#FFFFFF', justifyContent: 'center', alignItems: 'center', marginBottom: 12 },
  heroTitle: { fontSize: 20, fontWeight: '800', color: colors.textPrimary, marginBottom: 4 },
  heroBody: { fontSize: 15, color: colors.textSecondary },
  sectionLabel: { fontSize: 12, fontWeight: '800', color: colors.textHint, letterSpacing: 0.5, marginBottom: 10, marginTop: 8 },
  card: { backgroundColor: colors.bgCard, borderRadius: 20, padding: 4, marginBottom: 16, borderWidth: 1, borderColor: colors.borderLight },
  itemRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 14, paddingHorizontal: 16, borderBottomWidth: 1, borderBottomColor: colors.borderSubtle },
  itemIcon: { width: 32, height: 32, borderRadius: 10, backgroundColor: colors.bgSubtle, justifyContent: 'center', alignItems: 'center', marginRight: 12 },
  itemText: { fontSize: 15, color: colors.textPrimary, fontWeight: '500' },
  reportBody: { fontSize: 14, color: colors.textSecondary, lineHeight: 22, paddingHorizontal: 16, paddingTop: 12 },
  reportEmail: { fontSize: 16, fontWeight: '700', color: colors.accentPrimary, paddingHorizontal: 16, paddingTop: 4 },
  reportItem: { fontSize: 14, color: colors.textSecondary, lineHeight: 24, paddingHorizontal: 20 },
  warningBox: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 16, marginHorizontal: 16, marginBottom: 16, padding: 12, borderRadius: 12, backgroundColor: '#FEE2E2' },
  warningText: { fontSize: 13, fontWeight: '600', color: '#DC2626' },
});
