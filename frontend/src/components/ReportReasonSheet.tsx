import React from 'react';
import {
  ActivityIndicator,
  Modal,
  Pressable,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { borderRadius, colors, shadows, spacing } from '../utils/theme';

export type ReportReason = {
  id: string;
  label: string;
  details: string;
};

const DEFAULT_REASONS: ReportReason[] = [
  { id: 'not_interested', label: "I just don't like it", details: "Reporter said they don't like this content." },
  { id: 'bullying_or_unwanted_contact', label: 'Bullying or unwanted contact', details: 'Bullying, harassment, or unwanted contact.' },
  { id: 'self_harm_or_eating_disorders', label: 'Suicide, self-injury or eating disorders', details: 'Self-harm, suicide, or eating disorder concern.' },
  { id: 'violence_hate_or_exploitation', label: 'Violence, hate or exploitation', details: 'Violence, hate, exploitation, or dangerous behavior.' },
  { id: 'restricted_items', label: 'Selling or promoting restricted items', details: 'Restricted item sale or promotion.' },
  { id: 'nudity_or_sexual_activity', label: 'Nudity or sexual activity', details: 'Nudity, sexual content, or intimate imagery concern.' },
];

type ReportReasonSheetProps = {
  visible: boolean;
  submitting?: boolean;
  reasons?: ReportReason[];
  onClose: () => void;
  onSelect: (reason: ReportReason) => void;
};

export default function ReportReasonSheet({
  visible,
  submitting = false,
  reasons = DEFAULT_REASONS,
  onClose,
  onSelect,
}: ReportReasonSheetProps) {
  const insets = useSafeAreaInsets();

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <View style={styles.root}>
        <Pressable style={styles.backdrop} onPress={submitting ? undefined : onClose} />
        <View style={[styles.sheet, { paddingBottom: Math.max(insets.bottom + 18, 28) }]}>
          <View style={styles.handle} />
          <Text style={styles.title}>Report</Text>
          <View style={styles.divider} />

          <View style={styles.intro}>
            <Text style={styles.heading}>Why are you reporting this?</Text>
            <Text style={styles.subheading}>
              Your report is anonymous. If someone is in immediate danger, call the local emergency services - don't wait.
            </Text>
          </View>

          <View style={styles.reasonList}>
            {reasons.map((reason) => (
              <TouchableOpacity
                key={reason.id}
                style={styles.reasonRow}
                activeOpacity={0.72}
                disabled={submitting}
                onPress={() => onSelect(reason)}
              >
                <Text style={styles.reasonText}>{reason.label}</Text>
                {submitting ? (
                  <ActivityIndicator size="small" color={colors.textHint} />
                ) : (
                  <Ionicons name="chevron-forward" size={25} color={colors.textHint} />
                )}
              </TouchableOpacity>
            ))}
          </View>

          <View style={styles.footer}>
            <View style={styles.footerIcon}>
              <Ionicons name="document-text-outline" size={29} color={colors.textPrimary} />
            </View>
            <View style={styles.footerCopy}>
              <Text style={styles.footerText}>
                In the US, you can create a detailed report for something that contains intimate imagery.
              </Text>
              <Text style={styles.footerLink}>Fill in form</Text>
            </View>
          </View>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    justifyContent: 'flex-end',
  },
  backdrop: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(9,14,13,0.72)',
  },
  sheet: {
    maxHeight: '88%',
    borderTopLeftRadius: 34,
    borderTopRightRadius: 34,
    backgroundColor: colors.bgModal,
    paddingTop: spacing.gutter,
    ...shadows.sheet,
  },
  handle: {
    alignSelf: 'center',
    width: 44,
    height: 4,
    borderRadius: 2,
    backgroundColor: colors.textHint,
    opacity: 0.76,
  },
  title: {
    marginTop: 28,
    marginBottom: 22,
    color: colors.textStrong,
    fontSize: 26,
    lineHeight: 31,
    fontWeight: '800',
    textAlign: 'center',
  },
  divider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.borderSubtle,
  },
  intro: {
    paddingHorizontal: spacing.xl,
    paddingTop: 38,
    paddingBottom: 24,
    alignItems: 'center',
  },
  heading: {
    color: colors.textStrong,
    fontSize: 27,
    lineHeight: 33,
    fontWeight: '900',
    textAlign: 'center',
    letterSpacing: 0,
  },
  subheading: {
    marginTop: spacing.gutter,
    color: colors.textSecondary,
    fontSize: 19,
    lineHeight: 26,
    fontWeight: '650' as any,
    textAlign: 'center',
  },
  reasonList: {
    paddingHorizontal: spacing.section,
  },
  reasonRow: {
    minHeight: 70,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: spacing.md,
  },
  reasonText: {
    flex: 1,
    color: colors.textStrong,
    fontSize: 21,
    lineHeight: 27,
    fontWeight: '760' as any,
  },
  footer: {
    marginTop: spacing.lg,
    paddingHorizontal: spacing.section,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
  },
  footerIcon: {
    width: 54,
    height: 54,
    borderRadius: borderRadius.full,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
  },
  footerCopy: {
    flex: 1,
    minWidth: 0,
  },
  footerText: {
    color: colors.textStrong,
    fontSize: 16,
    lineHeight: 20,
    fontWeight: '700',
  },
  footerLink: {
    marginTop: 4,
    color: '#526BFF',
    fontSize: 17,
    lineHeight: 22,
    fontWeight: '800',
  },
});
