import { Image, Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';

import { colors, radius, spacing } from '@/theme';
import type { GovernanceReport } from '@/types';

type Props = {
  report: GovernanceReport;
  onPress: () => void;
};

function formatDate(value?: string) {
  if (!value) return 'Unknown time';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

function statusColor(status: string) {
  if (status === 'resolved') return colors.success;
  if (status === 'dismissed') return colors.muted;
  return colors.warning;
}

export function ReportCard({ report, onPress }: Props) {
  const targetLabel = report.post_id
    ? `Post by @${report.post_author_username || 'unknown'}`
    : `User @${report.target_username || 'unknown'}`;
  const reason = report.reason || report.report_type || 'Reported content';
  const reporter = report.reporter_username || report.reporter_full_name || 'unknown';
  const preview = report.post_content || report.details || 'Open this report to review context and actions.';

  const showImage = Boolean(report.post_image && !report.post_image.startsWith('cfstream:'));

  return (
    <Pressable style={({ pressed }) => [styles.card, pressed && styles.cardPressed]} onPress={onPress}>
      <View style={styles.row}>
        <View style={[styles.statusDot, { backgroundColor: statusColor(report.status) }]} />
        <Text style={styles.status}>{report.status}</Text>
        <Text style={styles.date}>{formatDate(report.created_at)}</Text>
      </View>

      <View style={styles.bodyRow}>
        {showImage ? (
          <Image source={{ uri: report.post_image }} style={styles.thumb} />
        ) : (
          <View style={styles.thumbFallback}>
            <Ionicons color={colors.primary} name={report.post_id ? 'image-outline' : 'person-outline'} size={24} />
          </View>
        )}

        <View style={styles.copy}>
          <Text numberOfLines={1} style={styles.reason}>{reason}</Text>
          <Text numberOfLines={1} style={styles.target}>{targetLabel}</Text>
          <Text numberOfLines={2} style={styles.preview}>{preview}</Text>
          <Text style={styles.reporter}>Reported by @{reporter}</Text>
        </View>

        <Ionicons color={colors.faint} name="chevron-forward" size={20} />
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: {
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.line,
    backgroundColor: colors.surface,
    padding: spacing.md,
    marginBottom: spacing.md,
  },
  cardPressed: {
    opacity: 0.75,
  },
  row: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.sm,
    marginBottom: spacing.md,
  },
  statusDot: {
    width: 9,
    height: 9,
    borderRadius: 9,
  },
  status: {
    color: colors.ink,
    fontSize: 12,
    fontWeight: '900',
    textTransform: 'uppercase',
  },
  date: {
    color: colors.faint,
    fontSize: 12,
    fontWeight: '700',
    marginLeft: 'auto',
  },
  bodyRow: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.md,
  },
  thumb: {
    width: 64,
    height: 64,
    borderRadius: radius.sm,
    backgroundColor: colors.surfaceAlt,
  },
  thumbFallback: {
    alignItems: 'center',
    justifyContent: 'center',
    width: 64,
    height: 64,
    borderRadius: radius.sm,
    backgroundColor: colors.primarySoft,
  },
  copy: {
    flex: 1,
    minWidth: 0,
  },
  reason: {
    color: colors.ink,
    fontSize: 16,
    fontWeight: '900',
    marginBottom: spacing.xs,
  },
  target: {
    color: colors.primary,
    fontSize: 13,
    fontWeight: '800',
    marginBottom: spacing.xs,
  },
  preview: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 18,
  },
  reporter: {
    color: colors.faint,
    fontSize: 12,
    fontWeight: '700',
    marginTop: spacing.sm,
  },
});
