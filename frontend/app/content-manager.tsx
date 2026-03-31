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

export default function ContentManagerScreen() {
  const router = useRouter();

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={styles.title}>Content Manager</Text>
        <View style={{ width: 44 }} />
      </View>

      <ScrollView contentContainerStyle={{ padding: 16, gap: 12 }}>
        <Text style={styles.sectionTitle}>Your Content</Text>
        {[
          { icon: 'newspaper-outline', label: 'Published Posts', count: '0', color: '#10b981' },
          { icon: 'time-outline', label: 'Drafts', count: '0', color: '#f59e0b' },
          { icon: 'calendar-outline', label: 'Scheduled', count: '0', color: '#0ea5e9' },
          { icon: 'archive-outline', label: 'Archived', count: '0', color: '#8b5cf6' },
        ].map((item) => (
          <TouchableOpacity key={item.label} style={styles.contentRow}>
            <View style={[styles.iconBox, { backgroundColor: item.color + '20' }]}>
              <Ionicons name={item.icon as any} size={22} color={item.color} />
            </View>
            <View style={{ flex: 1 }}>
              <Text style={styles.rowLabel}>{item.label}</Text>
            </View>
            <View style={styles.badge}>
              <Text style={styles.badgeText}>{item.count}</Text>
            </View>
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
  sectionTitle: { fontSize: 13, fontWeight: '700', color: colors.textHint, letterSpacing: 0.5, textTransform: 'uppercase' },
  contentRow: {
    flexDirection: 'row', alignItems: 'center', gap: 14, backgroundColor: colors.bgCard,
    padding: 16, borderRadius: 16, borderWidth: 1, borderColor: colors.borderSubtle, ...shadows.elevation1,
  },
  iconBox: { width: 44, height: 44, borderRadius: 12, justifyContent: 'center', alignItems: 'center' },
  rowLabel: { fontSize: 16, fontWeight: '600', color: colors.textPrimary },
  badge: { backgroundColor: colors.bgSubtle, borderRadius: 12, paddingHorizontal: 10, paddingVertical: 4 },
  badgeText: { fontSize: 14, fontWeight: '700', color: colors.textSecondary },
});
