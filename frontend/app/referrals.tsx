import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  Share,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, shadows } from '../src/utils/theme';

export default function ReferralsScreen() {
  const router = useRouter();
  const referralCode = 'FLAMES-' + Math.random().toString(36).substring(2, 8).toUpperCase();

  const shareReferral = async () => {
    try {
      await Share.share({ message: `Join me on Flames-Up! Use my code: ${referralCode}` });
    } catch {}
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={styles.title}>Referrals</Text>
        <View style={{ width: 44 }} />
      </View>

      <ScrollView contentContainerStyle={{ padding: 16, alignItems: 'center', paddingTop: 40 }}>
        <View style={styles.giftIcon}>
          <Ionicons name="gift" size={40} color={colors.accentPrimary} />
        </View>
        <Text style={styles.heading}>Invite Friends</Text>
        <Text style={styles.subtitle}>Share Flames-Up with your friends and earn rewards!</Text>

        <View style={styles.codeCard}>
          <Text style={styles.codeLabel}>Your Referral Code</Text>
          <Text style={styles.code}>{referralCode}</Text>
        </View>

        <TouchableOpacity style={styles.shareBtn} onPress={shareReferral}>
          <Ionicons name="share-outline" size={20} color="#FFFFFF" />
          <Text style={styles.shareBtnText}>Share Invite Link</Text>
        </TouchableOpacity>

        <View style={styles.statsRow}>
          <View style={styles.statBox}>
            <Text style={styles.statNum}>0</Text>
            <Text style={styles.statLabel}>Invited</Text>
          </View>
          <View style={styles.statBox}>
            <Text style={styles.statNum}>0</Text>
            <Text style={styles.statLabel}>Joined</Text>
          </View>
          <View style={styles.statBox}>
            <Text style={styles.statNum}>0</Text>
            <Text style={styles.statLabel}>Rewards</Text>
          </View>
        </View>
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
  giftIcon: {
    width: 80, height: 80, borderRadius: 40, backgroundColor: colors.accentPrimaryLight,
    justifyContent: 'center', alignItems: 'center', marginBottom: 20,
  },
  heading: { fontSize: 24, fontWeight: '800', color: colors.textPrimary, fontStyle: 'italic' },
  subtitle: { fontSize: 14, color: colors.textHint, marginTop: 8, textAlign: 'center', lineHeight: 20 },
  codeCard: {
    backgroundColor: colors.bgCard, borderRadius: 20, padding: 24, alignItems: 'center',
    marginTop: 32, width: '100%', borderWidth: 1, borderColor: colors.borderLight, ...shadows.elevation1,
  },
  codeLabel: { fontSize: 12, color: colors.textHint, fontWeight: '600', letterSpacing: 0.5, textTransform: 'uppercase' },
  code: { fontSize: 28, fontWeight: '900', color: colors.accentPrimary, letterSpacing: 3, marginTop: 8 },
  shareBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: colors.accentPrimary,
    paddingHorizontal: 32, paddingVertical: 16, borderRadius: 24, marginTop: 24,
  },
  shareBtnText: { fontSize: 16, fontWeight: '700', color: '#FFFFFF' },
  statsRow: { flexDirection: 'row', gap: 16, marginTop: 32 },
  statBox: {
    flex: 1, backgroundColor: colors.bgCard, borderRadius: 16, padding: 16, alignItems: 'center',
    borderWidth: 1, borderColor: colors.borderSubtle,
  },
  statNum: { fontSize: 24, fontWeight: '800', color: colors.textPrimary },
  statLabel: { fontSize: 12, color: colors.textHint, marginTop: 4 },
});
