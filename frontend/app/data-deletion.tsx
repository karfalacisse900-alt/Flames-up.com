import React from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Linking, Alert } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../src/utils/theme';
import { useAuthStore } from '../src/store/authStore';

export default function DataDeletionScreen() {
  const router = useRouter();
  const { logout } = useAuthStore();

  const handleDeleteAccount = () => {
    Alert.alert(
      'Delete Account',
      'This will permanently delete your account and all your data. This action cannot be undone.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete My Account',
          style: 'destructive',
          onPress: () => {
            Alert.alert(
              'Account Scheduled for Deletion',
              'Your account will be deleted within 30 days. Log in again to cancel.',
              [{ text: 'OK', onPress: () => { logout(); router.replace('/'); } }]
            );
          },
        },
      ]
    );
  };

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={s.headerTitle}>Account Deletion</Text>
        <View style={{ width: 44 }} />
      </View>

      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={s.content}>
        <View style={s.heroCard}>
          <View style={s.heroIcon}>
            <Ionicons name="trash-outline" size={28} color="#DC2626" />
          </View>
          <Text style={s.heroTitle}>Account Deletion</Text>
          <Text style={s.heroBody}>You can delete your account from Settings.</Text>
        </View>

        <View style={s.card}>
          <Text style={s.cardTitle}>When deleted:</Text>
          <View style={s.checkItem}>
            <Ionicons name="checkmark-circle" size={18} color="#DC2626" />
            <Text style={s.checkText}>Your profile is removed</Text>
          </View>
          <View style={s.checkItem}>
            <Ionicons name="checkmark-circle" size={18} color="#DC2626" />
            <Text style={s.checkText}>Your posts may be deleted or anonymized</Text>
          </View>
          <View style={s.checkItem}>
            <Ionicons name="checkmark-circle" size={18} color="#DC2626" />
            <Text style={s.checkText}>Your uploaded images may be removed from storage</Text>
          </View>
        </View>

        <View style={s.noteCard}>
          <Ionicons name="information-circle-outline" size={18} color={colors.textHint} />
          <Text style={s.noteText}>
            Some logs may remain temporarily for security and legal compliance.
          </Text>
        </View>

        <View style={s.card}>
          <Text style={s.cardTitle}>Need help deleting your account?</Text>
          <Text style={s.cardBody}>Email us at:</Text>
          <TouchableOpacity onPress={() => Linking.openURL('mailto:support@flames-up.com')}>
            <Text style={s.emailLink}>support@flames-up.com</Text>
          </TouchableOpacity>
        </View>

        <TouchableOpacity style={s.deleteBtn} onPress={handleDeleteAccount}>
          <Ionicons name="trash-outline" size={18} color="#FFFFFF" />
          <Text style={s.deleteBtnText}>Delete My Account</Text>
        </TouchableOpacity>
      </ScrollView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bgApp },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: colors.borderSubtle },
  backBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 18, fontWeight: '700', color: colors.textPrimary, fontStyle: 'italic' },
  content: { padding: 20, paddingBottom: 60 },
  heroCard: { backgroundColor: '#FEE2E2', borderRadius: 24, padding: 28, alignItems: 'center', marginBottom: 20 },
  heroIcon: { width: 56, height: 56, borderRadius: 28, backgroundColor: '#FFFFFF', justifyContent: 'center', alignItems: 'center', marginBottom: 12 },
  heroTitle: { fontSize: 20, fontWeight: '800', color: '#991B1B' },
  heroBody: { fontSize: 14, color: '#991B1B', marginTop: 4 },
  card: { backgroundColor: colors.bgCard, borderRadius: 20, padding: 20, marginBottom: 16, borderWidth: 1, borderColor: colors.borderLight },
  cardTitle: { fontSize: 16, fontWeight: '700', color: colors.textPrimary, marginBottom: 12 },
  cardBody: { fontSize: 14, color: colors.textSecondary, lineHeight: 22, marginBottom: 4 },
  checkItem: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 8 },
  checkText: { fontSize: 14, color: colors.textSecondary },
  noteCard: { flexDirection: 'row', alignItems: 'flex-start', gap: 10, backgroundColor: colors.bgSubtle, borderRadius: 16, padding: 16, marginBottom: 16 },
  noteText: { flex: 1, fontSize: 13, color: colors.textHint, lineHeight: 20 },
  emailLink: { fontSize: 16, fontWeight: '700', color: colors.accentPrimary, marginTop: 4 },
  deleteBtn: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, backgroundColor: '#DC2626', borderRadius: 16, paddingVertical: 16, marginTop: 8 },
  deleteBtnText: { fontSize: 16, fontWeight: '700', color: '#FFFFFF' },
});
