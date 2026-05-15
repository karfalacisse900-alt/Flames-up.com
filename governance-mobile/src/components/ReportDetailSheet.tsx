import { useEffect, useMemo, useState, type ReactNode } from 'react';
import {
  ActivityIndicator,
  Alert,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';

import { colors, radius, spacing } from '@/theme';
import type { GovernanceReport } from '@/types';

type Props = {
  loading: boolean;
  report: GovernanceReport | null;
  onBanUser: (userId: string, reason: string) => void;
  onClose: () => void;
  onDismiss: (reportId: string, notes: string) => void;
  onRemovePost: (postId: string, reason: string, deleteStream: boolean) => void;
  onResolve: (reportId: string, notes: string, actionTaken: string) => void;
  onUnbanUser: (userId: string) => void;
};

function display(value?: string) {
  return value && value.trim() ? value : 'Not provided';
}

function hasVideoAsset(report: GovernanceReport) {
  const values = [
    report.post_image,
    ...(report.post_images || []),
    ...(report.post_media_types || []),
  ].filter(Boolean).map(String);
  return values.some((value) => value.includes('video') || value.startsWith('cfstream:'));
}

export function ReportDetailSheet({
  loading,
  report,
  onBanUser,
  onClose,
  onDismiss,
  onRemovePost,
  onResolve,
  onUnbanUser,
}: Props) {
  const [notes, setNotes] = useState('');
  const [reason, setReason] = useState('');

  useEffect(() => {
    if (report) {
      setNotes('');
      setReason(report.reason || 'Governance action');
    }
  }, [report]);

  const targetUserId = useMemo(() => {
    if (!report) return '';
    if (report.reported_type === 'user' || report.report_type === 'user') return report.reported_id || '';
    return report.post_user_id || report.reported_id || '';
  }, [report]);

  if (!report) return null;

  const targetUser = report.post_author_username || report.target_username || 'unknown';
  const targetIsBanned = report.target_status === 'banned';
  const canRemovePost = Boolean(report.post_id);
  const canDeleteVideo = hasVideoAsset(report);
  const disabled = loading;

  return (
    <Modal animationType="slide" visible={Boolean(report)} onRequestClose={onClose}>
      <SafeAreaView style={styles.safeArea}>
        <View style={styles.header}>
          <Pressable style={styles.iconButton} onPress={onClose}>
            <Ionicons color={colors.ink} name="close" size={24} />
          </Pressable>
          <View style={styles.headerCopy}>
            <Text style={styles.eyebrow}>Report detail</Text>
            <Text numberOfLines={1} style={styles.title}>{display(report.reason || report.report_type)}</Text>
          </View>
        </View>

        <ScrollView contentContainerStyle={styles.content}>
          <View style={styles.statusRow}>
            <Badge label={report.status} />
            <Badge label={report.reported_type || report.report_type || 'content'} />
          </View>

          <Section title="Reporter">
            <Field label="Account" value={`@${display(report.reporter_username || report.reporter_full_name)}`} />
            <Field label="Reported at" value={display(report.created_at)} />
          </Section>

          <Section title="Target">
            <Field label="User" value={`@${targetUser}`} />
            <Field label="Status" value={display(report.target_status || report.post_status || 'active')} />
            {report.post_id ? <Field label="Post" value={report.post_id} /> : null}
          </Section>

          <Section title="Context">
            <Text style={styles.bodyText}>{display(report.details)}</Text>
            {report.post_content ? <Text style={styles.postText}>{report.post_content}</Text> : null}
          </Section>

          <Text style={styles.inputLabel}>Moderator notes</Text>
          <TextInput
            multiline
            placeholder="Add what you checked and why."
            placeholderTextColor={colors.faint}
            style={styles.notes}
            value={notes}
            onChangeText={setNotes}
          />

          <Text style={styles.inputLabel}>Action reason</Text>
          <TextInput
            placeholder="Reason shown in audit log"
            placeholderTextColor={colors.faint}
            style={styles.reasonInput}
            value={reason}
            onChangeText={setReason}
          />

          <View style={styles.actions}>
            <ActionButton
              disabled={disabled}
              icon="checkmark-circle-outline"
              label="Resolve"
              tone="success"
              onPress={() => onResolve(report.id, notes, 'resolved')}
            />
            <ActionButton
              disabled={disabled}
              icon="remove-circle-outline"
              label="Dismiss"
              onPress={() => onDismiss(report.id, notes)}
            />
            {canRemovePost ? (
              <ActionButton
                disabled={disabled}
                icon={canDeleteVideo ? 'videocam-off-outline' : 'trash-outline'}
                label={canDeleteVideo ? 'Remove video' : 'Remove post'}
                tone="danger"
                onPress={() => {
                  Alert.alert(
                    canDeleteVideo ? 'Remove this video?' : 'Remove this post?',
                    'This hides the content from user feeds and records the action in the audit log.',
                    [
                      { text: 'Cancel', style: 'cancel' },
                      {
                        text: 'Remove',
                        style: 'destructive',
                        onPress: () => onRemovePost(report.post_id!, reason, canDeleteVideo),
                      },
                    ],
                  );
                }}
              />
            ) : null}
            {targetUserId ? (
              targetIsBanned ? (
                <ActionButton
                  disabled={disabled}
                  icon="person-add-outline"
                  label="Unban user"
                  onPress={() => onUnbanUser(targetUserId)}
                />
              ) : (
                <ActionButton
                  disabled={disabled}
                  icon="ban-outline"
                  label="Ban user"
                  tone="danger"
                  onPress={() => {
                    Alert.alert(
                      'Ban this user?',
                      'Banned users cannot sign in or use authenticated app features.',
                      [
                        { text: 'Cancel', style: 'cancel' },
                        {
                          text: 'Ban',
                          style: 'destructive',
                          onPress: () => onBanUser(targetUserId, reason),
                        },
                      ],
                    );
                  }}
                />
              )
            ) : null}
          </View>
        </ScrollView>

        {loading ? (
          <View style={styles.loadingOverlay}>
            <ActivityIndicator color={colors.surface} />
            <Text style={styles.loadingText}>Saving action</Text>
          </View>
        ) : null}
      </SafeAreaView>
    </Modal>
  );
}

function Section({ children, title }: { children: ReactNode; title: string }) {
  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{title}</Text>
      {children}
    </View>
  );
}

function Field({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.field}>
      <Text style={styles.fieldLabel}>{label}</Text>
      <Text numberOfLines={2} style={styles.fieldValue}>{value}</Text>
    </View>
  );
}

function Badge({ label }: { label: string }) {
  return (
    <View style={styles.badge}>
      <Text style={styles.badgeText}>{label}</Text>
    </View>
  );
}

function ActionButton({
  disabled,
  icon,
  label,
  tone = 'neutral',
  onPress,
}: {
  disabled: boolean;
  icon: keyof typeof Ionicons.glyphMap;
  label: string;
  tone?: 'neutral' | 'success' | 'danger';
  onPress: () => void;
}) {
  const isDanger = tone === 'danger';
  const isSuccess = tone === 'success';
  const color = isDanger ? colors.danger : isSuccess ? colors.success : colors.primary;

  return (
    <Pressable
      disabled={disabled}
      style={({ pressed }) => [
        styles.actionButton,
        isDanger && styles.actionDanger,
        isSuccess && styles.actionSuccess,
        disabled && styles.actionDisabled,
        pressed && !disabled && styles.actionPressed,
      ]}
      onPress={onPress}
    >
      <Ionicons color={color} name={icon} size={20} />
      <Text style={[styles.actionText, { color }]}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.background,
  },
  header: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.md,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.line,
    backgroundColor: colors.surface,
  },
  iconButton: {
    alignItems: 'center',
    justifyContent: 'center',
    width: 42,
    height: 42,
    borderRadius: radius.md,
    backgroundColor: colors.surfaceAlt,
  },
  headerCopy: {
    flex: 1,
    minWidth: 0,
  },
  eyebrow: {
    color: colors.primary,
    fontSize: 12,
    fontWeight: '900',
    textTransform: 'uppercase',
  },
  title: {
    color: colors.ink,
    fontSize: 22,
    fontWeight: '900',
    letterSpacing: 0,
  },
  content: {
    padding: spacing.lg,
    paddingBottom: spacing.xxl,
  },
  statusRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
    marginBottom: spacing.lg,
  },
  badge: {
    borderRadius: radius.sm,
    backgroundColor: colors.primarySoft,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  badgeText: {
    color: colors.primary,
    fontSize: 12,
    fontWeight: '900',
    textTransform: 'uppercase',
  },
  section: {
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.line,
    backgroundColor: colors.surface,
    padding: spacing.lg,
    marginBottom: spacing.md,
  },
  sectionTitle: {
    color: colors.ink,
    fontSize: 18,
    fontWeight: '900',
    marginBottom: spacing.md,
  },
  field: {
    marginBottom: spacing.md,
  },
  fieldLabel: {
    color: colors.faint,
    fontSize: 12,
    fontWeight: '800',
    marginBottom: spacing.xs,
    textTransform: 'uppercase',
  },
  fieldValue: {
    color: colors.ink,
    fontSize: 15,
    fontWeight: '700',
    lineHeight: 20,
  },
  bodyText: {
    color: colors.muted,
    fontSize: 15,
    lineHeight: 22,
  },
  postText: {
    color: colors.ink,
    fontSize: 16,
    fontWeight: '700',
    lineHeight: 23,
    marginTop: spacing.md,
  },
  inputLabel: {
    color: colors.ink,
    fontSize: 13,
    fontWeight: '900',
    marginBottom: spacing.sm,
    marginTop: spacing.md,
  },
  notes: {
    minHeight: 110,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.line,
    backgroundColor: colors.surface,
    color: colors.ink,
    fontSize: 15,
    padding: spacing.md,
    textAlignVertical: 'top',
  },
  reasonInput: {
    minHeight: 50,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.line,
    backgroundColor: colors.surface,
    color: colors.ink,
    fontSize: 15,
    paddingHorizontal: spacing.md,
  },
  actions: {
    gap: spacing.sm,
    marginTop: spacing.lg,
  },
  actionButton: {
    minHeight: 50,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.line,
    backgroundColor: colors.surface,
    alignItems: 'center',
    flexDirection: 'row',
    justifyContent: 'center',
    gap: spacing.sm,
  },
  actionDanger: {
    backgroundColor: colors.dangerSoft,
    borderColor: colors.dangerSoft,
  },
  actionSuccess: {
    backgroundColor: colors.successSoft,
    borderColor: colors.successSoft,
  },
  actionDisabled: {
    opacity: 0.55,
  },
  actionPressed: {
    transform: [{ scale: 0.99 }],
  },
  actionText: {
    fontSize: 15,
    fontWeight: '900',
  },
  loadingOverlay: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(16, 20, 18, 0.58)',
    gap: spacing.sm,
  },
  loadingText: {
    color: colors.surface,
    fontSize: 14,
    fontWeight: '900',
  },
});
