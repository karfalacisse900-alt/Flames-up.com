import React from 'react';
import { Linking, ScrollView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { borderRadius, colors, shadows, spacing } from '../utils/theme';
import {
  LEGAL_DISCLAIMER,
  LEGAL_LAST_UPDATED,
  SUPPORT_EMAIL,
  WEBSITE_DOMAIN,
  LegalPageKey,
  legalPageList,
  legalPages,
} from './legalContent';

type Props = {
  pageKey: LegalPageKey;
};

export default function LegalPageScreen({ pageKey }: Props) {
  const router = useRouter();
  const page = legalPages[pageKey];
  const otherPages = legalPageList.filter((item) => item.key !== page.key);

  return (
    <SafeAreaView style={styles.root} edges={['top']}>
      <View style={styles.header}>
        <TouchableOpacity style={styles.headerButton} onPress={() => router.back()} activeOpacity={0.84}>
          <Ionicons name="chevron-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={styles.headerTitle} numberOfLines={1}>{page.shortTitle}</Text>
        <View style={styles.headerSpacer} />
      </View>

      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.content}>
        <View style={styles.hero}>
          <View style={styles.heroTop}>
            <View style={styles.heroIcon}>
              <Ionicons name={page.icon as any} size={22} color={colors.accentPrimary} />
            </View>
            <View style={styles.heroCopy}>
              <Text style={styles.title}>{page.title}</Text>
              <Text style={styles.updated}>Last updated: {LEGAL_LAST_UPDATED}</Text>
              <Text style={styles.route}>{page.route}</Text>
            </View>
          </View>
          <Text style={styles.summary}>{page.summary}</Text>
          <Text style={styles.domain}>Website/domain: {WEBSITE_DOMAIN}</Text>
        </View>

        {page.sections.map((section) => (
          <View key={section.title} style={styles.card}>
            <Text style={styles.sectionTitle}>{section.title}</Text>
            {section.paragraphs?.map((paragraph, index) => (
              <Text key={`${section.title}-p-${index}`} style={styles.paragraph}>{paragraph}</Text>
            ))}
            {section.bullets?.length ? (
              <View style={styles.bulletList}>
                {section.bullets.map((bullet, index) => (
                  <View key={`${section.title}-b-${index}`} style={styles.bulletRow}>
                    <View style={styles.bulletDot} />
                    <Text style={styles.bulletText}>{bullet}</Text>
                  </View>
                ))}
              </View>
            ) : null}
          </View>
        ))}

        <View style={styles.supportCard}>
          <Text style={styles.supportTitle}>Questions or Requests</Text>
          <Text style={styles.supportBody}>For support, safety, privacy, account deletion, or legal questions, contact Captro support.</Text>
          <TouchableOpacity onPress={() => Linking.openURL(`mailto:${SUPPORT_EMAIL}`)} activeOpacity={0.84}>
            <Text style={styles.supportEmail}>{SUPPORT_EMAIL}</Text>
          </TouchableOpacity>
          <Text style={styles.disclaimer}>{LEGAL_DISCLAIMER}</Text>
        </View>

        <View style={styles.footer}>
          <Text style={styles.footerTitle}>Legal</Text>
          <View style={styles.footerCard}>
            {otherPages.map((target) => (
              <TouchableOpacity
                key={target.key}
                style={styles.footerLink}
                onPress={() => router.push(target.route as any)}
                activeOpacity={0.84}
              >
                <View style={styles.footerIcon}>
                  <Ionicons name={target.icon as any} size={16} color={colors.accentPrimary} />
                </View>
                <View style={styles.footerText}>
                  <Text style={styles.footerLabel}>{target.title}</Text>
                  <Text style={styles.footerRoute}>{target.route}</Text>
                </View>
                <Ionicons name="chevron-forward" size={15} color={colors.textHint} />
              </TouchableOpacity>
            ))}
          </View>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.bgApp },
  header: {
    minHeight: 58,
    paddingHorizontal: spacing.md,
    paddingBottom: spacing.gutter,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderSubtle,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  headerButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    justifyContent: 'center',
    alignItems: 'center',
    ...shadows.elevation1,
  },
  headerTitle: { flex: 1, textAlign: 'center', fontSize: 17, fontWeight: '700', color: colors.textPrimary },
  headerSpacer: { width: 42 },
  content: { padding: spacing.md, paddingBottom: 56, gap: spacing.md },
  hero: {
    padding: spacing.lg,
    borderRadius: borderRadius.card,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation1,
  },
  heroTop: { flexDirection: 'row', gap: spacing.md, alignItems: 'flex-start', marginBottom: spacing.md },
  heroIcon: {
    width: 50,
    height: 50,
    borderRadius: 25,
    backgroundColor: colors.accentPrimaryLight,
    justifyContent: 'center',
    alignItems: 'center',
  },
  heroCopy: { flex: 1 },
  title: { fontSize: 27, lineHeight: 32, fontWeight: '700', color: colors.textPrimary },
  updated: { marginTop: 5, fontSize: 13, fontWeight: '700', color: colors.textHint },
  route: { marginTop: 4, fontSize: 12, fontWeight: '700', color: colors.textHint },
  summary: { fontSize: 15, lineHeight: 23, fontWeight: '500', color: colors.textSecondary },
  domain: { marginTop: spacing.gutter, fontSize: 12, lineHeight: 17, fontWeight: '700', color: colors.textHint },
  card: {
    padding: spacing.lg,
    borderRadius: borderRadius.card,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation1,
  },
  sectionTitle: { fontSize: 18, lineHeight: 24, fontWeight: '700', color: colors.textPrimary, marginBottom: spacing.sm },
  paragraph: { fontSize: 14.5, lineHeight: 23, color: colors.textSecondary, marginTop: 6 },
  bulletList: { gap: 8, marginTop: spacing.sm },
  bulletRow: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.gutter },
  bulletDot: { width: 5, height: 5, borderRadius: 3, backgroundColor: colors.accentPrimary, marginTop: 9 },
  bulletText: { flex: 1, fontSize: 14.5, lineHeight: 23, color: colors.textSecondary },
  supportCard: {
    padding: spacing.lg,
    borderRadius: borderRadius.card,
    backgroundColor: colors.accentPrimaryLight,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
  },
  supportTitle: { fontSize: 17, lineHeight: 23, fontWeight: '700', color: colors.textPrimary },
  supportBody: { marginTop: spacing.sm, fontSize: 14, lineHeight: 22, color: colors.textSecondary },
  supportEmail: { marginTop: spacing.sm, fontSize: 15, lineHeight: 21, fontWeight: '700', color: colors.accentPrimary },
  disclaimer: { marginTop: spacing.gutter, fontSize: 12, lineHeight: 18, fontWeight: '500', color: colors.textHint },
  footer: { gap: spacing.sm },
  footerTitle: { fontSize: 12, lineHeight: 16, fontWeight: '800', color: colors.textHint, textTransform: 'uppercase' },
  footerCard: {
    borderRadius: borderRadius.xl,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    overflow: 'hidden',
  },
  footerLink: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.gutter,
    paddingHorizontal: spacing.md,
    paddingVertical: 13,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.divider,
  },
  footerIcon: {
    width: 34,
    height: 34,
    borderRadius: 17,
    backgroundColor: colors.surfaceSoft,
    justifyContent: 'center',
    alignItems: 'center',
  },
  footerText: { flex: 1 },
  footerLabel: { fontSize: 15, lineHeight: 20, fontWeight: '700', color: colors.textPrimary },
  footerRoute: { marginTop: 2, fontSize: 11.5, lineHeight: 16, fontWeight: '600', color: colors.textHint },
});
