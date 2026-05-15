import React from 'react';
import { StyleProp, StyleSheet, Text, TouchableOpacity, View, ViewStyle } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { appFontFamily } from '../utils/typography';
import { borderRadius, colors, layout, shadows, spacing } from '../utils/theme';

type SkeletonBlockProps = {
  width?: ViewStyle['width'];
  height?: ViewStyle['height'];
  radius?: number;
  style?: StyleProp<ViewStyle>;
};

export function SkeletonBlock({ width = '100%', height = 16, radius = borderRadius.md, style }: SkeletonBlockProps) {
  return <View style={[s.skeleton, { width, height, borderRadius: radius }, style]} />;
}

export function NotificationSkeletonList({ count = 6 }: { count?: number }) {
  return (
    <View style={s.skeletonList}>
      {Array.from({ length: count }).map((_, index) => (
        <View key={`notification-skeleton-${index}`} style={s.skeletonRow}>
          <SkeletonBlock width={46} height={46} radius={23} />
          <View style={s.skeletonTextStack}>
            <SkeletonBlock width="44%" height={14} radius={7} />
            <SkeletonBlock width="82%" height={12} radius={6} />
            <SkeletonBlock width="24%" height={10} radius={5} />
          </View>
        </View>
      ))}
    </View>
  );
}

type EmptyStateProps = {
  icon: keyof typeof Ionicons.glyphMap;
  title: string;
  body: string;
  actionLabel?: string;
  onAction?: () => void;
  style?: StyleProp<ViewStyle>;
};

export function EmptyState({ icon, title, body, actionLabel, onAction, style }: EmptyStateProps) {
  return (
    <View style={[s.empty, style]}>
      <View style={s.emptyIcon}>
        <Ionicons name={icon} size={31} color={colors.accentPrimary} />
      </View>
      <Text style={s.emptyTitle}>{title}</Text>
      <Text style={s.emptyBody}>{body}</Text>
      {actionLabel && onAction ? (
        <TouchableOpacity style={s.emptyAction} onPress={onAction} activeOpacity={0.86}>
          <Text style={s.emptyActionText}>{actionLabel}</Text>
        </TouchableOpacity>
      ) : null}
    </View>
  );
}

const s = StyleSheet.create({
  skeleton: {
    backgroundColor: colors.skeleton,
  },
  skeletonList: {
    paddingHorizontal: spacing.md,
    paddingTop: spacing.md,
    gap: spacing.sm,
  },
  skeletonRow: {
    minHeight: 78,
    borderRadius: borderRadius.xl,
    backgroundColor: colors.surfaceRaised,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.gutter,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
  },
  skeletonTextStack: {
    flex: 1,
    gap: spacing.sm,
  },
  empty: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.xxl,
  },
  emptyIcon: {
    width: 72,
    height: 72,
    borderRadius: 36,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.emptyIconBg,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation1,
  },
  emptyTitle: {
    marginTop: spacing.md,
    color: colors.textPrimary,
    fontFamily: appFontFamily,
    fontSize: 18,
    lineHeight: 24,
    fontWeight: '600',
    textAlign: 'center',
  },
  emptyBody: {
    marginTop: spacing.xs,
    maxWidth: 280,
    color: colors.textSecondary,
    fontFamily: appFontFamily,
    fontSize: 14,
    lineHeight: 20,
    fontWeight: '400',
    textAlign: 'center',
  },
  emptyAction: {
    minHeight: layout.minTouchTarget,
    marginTop: spacing.md,
    borderRadius: borderRadius.full,
    backgroundColor: colors.accentPrimary,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: spacing.section,
  },
  emptyActionText: {
    color: colors.textInverse,
    fontFamily: appFontFamily,
    fontSize: 14,
    lineHeight: 18,
    fontWeight: '600',
  },
});
