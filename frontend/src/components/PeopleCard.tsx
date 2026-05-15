import React from 'react';
import { Alert, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { PeopleProfile, compactNumber, reportPeopleProfile, togglePeopleInteraction } from '../utils/recommendFeatures';
import { colors, hitSlop, layout, typography } from '../utils/theme';
import OptimizedImage from './OptimizedImage';

type Props = {
  profile: PeopleProfile;
  onChanged?: (profile: PeopleProfile) => void;
};

export default function PeopleCard({ profile, onChanged }: Props) {
  const router = useRouter();

  const interact = async (kind: 'follow' | 'save') => {
    try {
      const result = await togglePeopleInteraction(profile.id, kind);
      const countKey = kind === 'follow' ? 'followers_count' : 'saves_count';
      const activeKey = kind === 'follow' ? 'followed' : 'saved';
      onChanged?.({
        ...profile,
        [activeKey]: result.active,
        [countKey]: Math.max(0, Number((profile as any)[countKey] || 0) + (result.active ? 1 : -1)),
      } as PeopleProfile);
    } catch (error: any) {
      Alert.alert('Not updated', error?.response?.data?.detail || 'Try again in a moment.');
    }
  };

  const report = () => {
    Alert.alert('Report profile?', 'Use this for wrong info, impersonation, spam, or unsafe content.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Report',
        style: 'destructive',
        onPress: async () => {
          try {
            await reportPeopleProfile(profile.id);
            Alert.alert('Reported', 'Thanks. Admin will review it.');
          } catch (error: any) {
            Alert.alert('Report failed', error?.response?.data?.detail || 'Could not report this profile.');
          }
        },
      },
    ]);
  };

  return (
    <TouchableOpacity style={styles.card} activeOpacity={0.9} onPress={() => router.push(`/people/${encodeURIComponent(profile.id)}` as any)}>
      {profile.profile_image ? (
        <OptimizedImage uri={profile.profile_image} preset="feed" style={styles.image} />
      ) : (
        <View style={[styles.image, styles.fallback]}>
          <Text style={styles.initial}>{profile.name[0]?.toUpperCase() || 'P'}</Text>
        </View>
      )}
      <View style={styles.copy}>
        <View style={styles.titleRow}>
          <View style={{ flex: 1, minWidth: 0 }}>
            <Text style={styles.name} numberOfLines={1}>{profile.name}</Text>
            <Text style={styles.role} numberOfLines={1}>{profile.role}{profile.city ? ` · ${profile.city}` : ''}</Text>
          </View>
          <TouchableOpacity style={styles.iconBtn} onPress={report} accessibilityRole="button" accessibilityLabel="Report profile" hitSlop={hitSlop}>
            <Ionicons name="flag-outline" size={16} color={colors.textPrimary} />
          </TouchableOpacity>
        </View>
        <Text style={styles.bio} numberOfLines={2}>{profile.bio || profile.known_for || 'Interesting person to follow.'}</Text>
        {profile.known_for ? <Text style={styles.known} numberOfLines={1}>Known for {profile.known_for}</Text> : null}
        <View style={styles.actions}>
          <TouchableOpacity style={[styles.followBtn, profile.followed && styles.followBtnOn]} onPress={() => interact('follow')} accessibilityRole="button" accessibilityLabel={profile.followed ? 'Unfollow profile' : 'Follow profile'}>
            <Ionicons name={profile.followed ? 'checkmark' : 'add'} size={15} color={colors.textInverse} />
            <Text style={[styles.followText, profile.followed && styles.followTextOn]}>{profile.followed ? 'Following' : 'Follow'}</Text>
          </TouchableOpacity>
          <TouchableOpacity style={[styles.saveBtn, profile.saved && styles.saveBtnOn]} onPress={() => interact('save')} accessibilityRole="button" accessibilityLabel={profile.saved ? 'Remove saved profile' : 'Save profile'}>
            <Ionicons name={profile.saved ? 'bookmark' : 'bookmark-outline'} size={14} color={profile.saved ? colors.textInverse : colors.textPrimary} />
            <Text style={[styles.saveText, profile.saved && styles.saveTextOn]}>{compactNumber(profile.saves_count)}</Text>
          </TouchableOpacity>
        </View>
      </View>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  card: { minHeight: 154, borderRadius: 22, backgroundColor: colors.bgCard, borderWidth: 1, borderColor: colors.borderSubtle, overflow: 'hidden', flexDirection: 'row' },
  image: { width: 116, height: '100%', minHeight: 154, backgroundColor: colors.bgSubtle },
  fallback: { alignItems: 'center', justifyContent: 'center', backgroundColor: colors.accentPrimaryLight },
  initial: { color: colors.textPrimary, fontSize: 32, fontWeight: '500' },
  copy: { flex: 1, padding: 14, gap: 8 },
  titleRow: { flexDirection: 'row', alignItems: 'flex-start', gap: 8 },
  name: { color: colors.textPrimary, fontSize: 18, lineHeight: 23, fontWeight: '600' },
  role: { color: colors.textHint, fontSize: 12, fontWeight: '500', marginTop: 2, textTransform: 'capitalize' },
  iconBtn: { width: 34, height: 34, borderRadius: 17, backgroundColor: colors.bgSubtle, alignItems: 'center', justifyContent: 'center' },
  bio: { ...typography.bodySmall, color: colors.textSecondary },
  known: { color: colors.accentPrimary, fontSize: 11, fontWeight: '500' },
  actions: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 'auto' },
  followBtn: { minHeight: 38, borderRadius: 19, backgroundColor: colors.accentPrimary, borderWidth: 1, borderColor: colors.accentPrimaryHover, flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 12 },
  followBtnOn: { backgroundColor: colors.textPrimary },
  followText: { color: colors.textInverse, fontSize: 12, fontWeight: '600' },
  followTextOn: { color: colors.textInverse },
  saveBtn: { minHeight: 38, borderRadius: 19, backgroundColor: colors.bgSubtle, flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 10 },
  saveBtnOn: { backgroundColor: colors.accentPrimary, borderWidth: 1, borderColor: colors.accentPrimaryHover },
  saveText: { color: colors.textPrimary, fontSize: 12, fontWeight: '500' },
  saveTextOn: { color: colors.textInverse },
});
