import { FlatList, Pressable, RefreshControl, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';

import { ReportCard } from '@/components/ReportCard';
import { colors, radius, spacing } from '@/theme';
import type { AdminUser, FilterStatus, GovernanceReport, GovernanceStats } from '@/types';

type Props = {
  admin: AdminUser | null;
  error: string;
  reports: GovernanceReport[];
  refreshing: boolean;
  stats: GovernanceStats;
  status: FilterStatus;
  onLogout: () => void;
  onOpenReport: (report: GovernanceReport) => void;
  onRefresh: () => void;
  onStatusChange: (status: FilterStatus) => void;
};

const filters: Array<{ label: string; value: FilterStatus }> = [
  { label: 'Pending', value: 'pending' },
  { label: 'Resolved', value: 'resolved' },
  { label: 'Dismissed', value: 'dismissed' },
  { label: 'All', value: 'all' },
];

export function GovernanceDashboard({
  admin,
  error,
  reports,
  refreshing,
  stats,
  status,
  onLogout,
  onOpenReport,
  onRefresh,
  onStatusChange,
}: Props) {
  const displayName = admin?.full_name || admin?.username || 'Admin';

  return (
    <SafeAreaView edges={['top']} style={styles.safeArea}>
      <FlatList
        data={reports}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.content}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            tintColor={colors.primary}
            onRefresh={onRefresh}
          />
        }
        ListHeaderComponent={
          <View style={styles.headerBlock}>
            <View style={styles.topbar}>
              <View>
                <Text style={styles.eyebrow}>Flames-Up</Text>
                <Text style={styles.title}>Governance</Text>
                <Text style={styles.subtitle}>Signed in as {displayName}</Text>
              </View>
              <Pressable style={styles.logoutButton} onPress={onLogout}>
                <Ionicons color={colors.primary} name="log-out-outline" size={22} />
              </Pressable>
            </View>

            <View style={styles.statsGrid}>
              <StatItem label="Pending" value={stats.pending_reports} tone="warning" />
              <StatItem label="Banned" value={stats.banned_users} tone="danger" />
              <StatItem label="Removed" value={stats.removed_posts} tone="danger" />
              <StatItem label="Active users" value={stats.active_users} tone="success" />
            </View>

            <View style={styles.filters}>
              {filters.map((filter) => {
                const active = status === filter.value;
                return (
                  <Pressable
                    key={filter.value}
                    style={[styles.filter, active && styles.filterActive]}
                    onPress={() => onStatusChange(filter.value)}
                  >
                    <Text style={[styles.filterText, active && styles.filterTextActive]}>
                      {filter.label}
                    </Text>
                  </Pressable>
                );
              })}
            </View>

            {error ? <Text style={styles.error}>{error}</Text> : null}
            <Text style={styles.sectionTitle}>Report queue</Text>
          </View>
        }
        ListEmptyComponent={
          <View style={styles.empty}>
            <Ionicons color={colors.faint} name="shield-checkmark-outline" size={34} />
            <Text style={styles.emptyTitle}>No reports here</Text>
            <Text style={styles.emptyText}>Pull to refresh or switch filters.</Text>
          </View>
        }
        renderItem={({ item }) => (
          <ReportCard report={item} onPress={() => onOpenReport(item)} />
        )}
      />
    </SafeAreaView>
  );
}

function StatItem({ label, value, tone }: { label: string; value: number; tone: 'warning' | 'danger' | 'success' }) {
  const toneStyle = tone === 'danger' ? styles.statDanger : tone === 'warning' ? styles.statWarning : styles.statSuccess;

  return (
    <View style={styles.statItem}>
      <Text style={[styles.statValue, toneStyle]}>{value}</Text>
      <Text style={styles.statLabel}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.xxl,
  },
  headerBlock: {
    paddingTop: spacing.md,
  },
  topbar: {
    alignItems: 'flex-start',
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: spacing.xl,
  },
  eyebrow: {
    color: colors.primary,
    fontSize: 13,
    fontWeight: '800',
    letterSpacing: 0,
    textTransform: 'uppercase',
  },
  title: {
    color: colors.ink,
    fontSize: 38,
    fontWeight: '900',
    letterSpacing: 0,
    marginTop: spacing.xs,
  },
  subtitle: {
    color: colors.muted,
    fontSize: 14,
    fontWeight: '600',
    marginTop: spacing.xs,
  },
  logoutButton: {
    alignItems: 'center',
    justifyContent: 'center',
    width: 44,
    height: 44,
    borderRadius: radius.md,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.line,
  },
  statsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
    marginBottom: spacing.lg,
  },
  statItem: {
    flexBasis: '48%',
    flexGrow: 1,
    minHeight: 82,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.line,
    backgroundColor: colors.surface,
    padding: spacing.md,
    justifyContent: 'center',
  },
  statValue: {
    fontSize: 28,
    fontWeight: '900',
    letterSpacing: 0,
  },
  statWarning: {
    color: colors.warning,
  },
  statDanger: {
    color: colors.danger,
  },
  statSuccess: {
    color: colors.success,
  },
  statLabel: {
    color: colors.muted,
    fontSize: 13,
    fontWeight: '700',
    marginTop: spacing.xs,
  },
  filters: {
    flexDirection: 'row',
    gap: spacing.sm,
    marginBottom: spacing.lg,
  },
  filter: {
    minHeight: 40,
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.line,
    backgroundColor: colors.surface,
  },
  filterActive: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  filterText: {
    color: colors.muted,
    fontSize: 12,
    fontWeight: '800',
  },
  filterTextActive: {
    color: colors.surface,
  },
  error: {
    color: colors.danger,
    fontSize: 13,
    fontWeight: '700',
    lineHeight: 18,
    marginBottom: spacing.md,
  },
  sectionTitle: {
    color: colors.ink,
    fontSize: 20,
    fontWeight: '900',
    marginBottom: spacing.md,
  },
  empty: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: spacing.xxl,
  },
  emptyTitle: {
    color: colors.ink,
    fontSize: 18,
    fontWeight: '900',
    marginTop: spacing.md,
  },
  emptyText: {
    color: colors.muted,
    fontSize: 14,
    marginTop: spacing.xs,
  },
});
