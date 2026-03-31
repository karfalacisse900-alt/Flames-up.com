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

function HubCard({ icon, iconColor, title, desc, onPress }: any) {
  return (
    <TouchableOpacity style={hubStyles.card} onPress={onPress} activeOpacity={0.8}>
      <View style={[hubStyles.iconBox, { backgroundColor: iconColor + '20' }]}>
        <Ionicons name={icon} size={24} color={iconColor} />
      </View>
      <View style={{ flex: 1 }}>
        <Text style={hubStyles.title}>{title}</Text>
        <Text style={hubStyles.desc}>{desc}</Text>
      </View>
      <Ionicons name="chevron-forward" size={18} color={colors.textHint} />
    </TouchableOpacity>
  );
}

const hubStyles = StyleSheet.create({
  card: {
    flexDirection: 'row', alignItems: 'center', gap: 14, backgroundColor: colors.bgCard,
    padding: 16, borderRadius: 16, borderWidth: 1, borderColor: colors.borderSubtle, ...shadows.elevation1,
  },
  iconBox: { width: 48, height: 48, borderRadius: 14, justifyContent: 'center', alignItems: 'center' },
  title: { fontSize: 16, fontWeight: '700', color: colors.textPrimary },
  desc: { fontSize: 12, color: colors.textHint, marginTop: 2 },
});

export default function CreatorHubScreen() {
  const router = useRouter();

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>Creator Hub</Text>
        <View style={{ width: 44 }} />
      </View>

      <ScrollView contentContainerStyle={{ padding: 16, gap: 12 }}>
        <Text style={styles.sectionTitle}>Creator Tools</Text>
        <HubCard icon="analytics-outline" iconColor="#6366f1" title="Analytics" desc="View your content performance" />
        <HubCard icon="trending-up-outline" iconColor="#10b981" title="Growth" desc="Tips to grow your audience" />
        <HubCard icon="cash-outline" iconColor="#f59e0b" title="Monetization" desc="Earn from your content" />
        <HubCard icon="color-palette-outline" iconColor="#ec4899" title="Brand Kit" desc="Manage your visual identity" />
        <HubCard icon="calendar-outline" iconColor="#0ea5e9" title="Content Calendar" desc="Plan and schedule posts" />
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
  headerTitle: { fontSize: 18, fontWeight: '700', color: colors.textPrimary },
  sectionTitle: { fontSize: 13, fontWeight: '700', color: colors.textHint, letterSpacing: 0.5, textTransform: 'uppercase', marginBottom: 4 },
});
