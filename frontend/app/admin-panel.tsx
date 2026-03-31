import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, shadows } from '../src/utils/theme';

export default function AdminPanelScreen() {
  const router = useRouter();

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={styles.title}>Admin Panel</Text>
        <View style={{ width: 44 }} />
      </View>

      <ScrollView contentContainerStyle={{ padding: 16, gap: 12 }}>
        <View style={styles.statsGrid}>
          {[
            { label: 'Total Users', val: '0', icon: 'people', color: '#6366f1' },
            { label: 'Total Posts', val: '0', icon: 'newspaper', color: '#10b981' },
            { label: 'Reports', val: '0', icon: 'flag', color: '#ef4444' },
            { label: 'Active Now', val: '0', icon: 'pulse', color: '#0ea5e9' },
          ].map((s) => (
            <View key={s.label} style={styles.statCard}>
              <Ionicons name={s.icon as any} size={24} color={s.color} />
              <Text style={styles.statVal}>{s.val}</Text>
              <Text style={styles.statLabel}>{s.label}</Text>
            </View>
          ))}
        </View>

        <Text style={styles.sectionTitle}>Management</Text>
        {[
          { icon: 'people-outline', label: 'User Management' },
          { icon: 'document-text-outline', label: 'Content Moderation' },
          { icon: 'flag-outline', label: 'Reports' },
          { icon: 'megaphone-outline', label: 'Announcements' },
        ].map((item) => (
          <TouchableOpacity key={item.label} style={styles.mgmtRow}>
            <Ionicons name={item.icon as any} size={22} color={colors.textSecondary} />
            <Text style={styles.mgmtText}>{item.label}</Text>
            <View style={{ flex: 1 }} />
            <Ionicons name="chevron-forward" size={18} color={colors.textHint} />
          </TouchableOpacity>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bgApp },
  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 16, paddingVertical: 8, borderBottomWidth: 1, borderBottomColor: colors.borderSubtle,
  },
  backBtn: { width: 44, height: 44, borderRadius: 22, justifyContent: 'center', alignItems: 'center' },
  title: { fontSize: 18, fontWeight: '700', color: colors.textPrimary },
  statsGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 },
  statCard: {
    width: '47%', backgroundColor: colors.bgCard, borderRadius: 16, padding: 16,
    alignItems: 'center', borderWidth: 1, borderColor: colors.borderSubtle, ...shadows.elevation1,
  },
  statVal: { fontSize: 28, fontWeight: '900', color: colors.textPrimary, marginTop: 8 },
  statLabel: { fontSize: 12, color: colors.textHint, marginTop: 4 },
  sectionTitle: { fontSize: 13, fontWeight: '700', color: colors.textHint, letterSpacing: 0.5, textTransform: 'uppercase', marginTop: 12 },
  mgmtRow: {
    flexDirection: 'row', alignItems: 'center', gap: 14, backgroundColor: colors.bgCard,
    padding: 16, borderRadius: 16, borderWidth: 1, borderColor: colors.borderSubtle,
  },
  mgmtText: { fontSize: 16, fontWeight: '500', color: colors.textPrimary },
});
