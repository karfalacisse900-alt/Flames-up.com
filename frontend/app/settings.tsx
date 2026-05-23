import React, { useEffect, useState } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Switch, TextInput, Alert, ScrollView, Linking,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuthStore } from '../src/store/authStore';
import api from '../src/api/client';
import { AppLanguage, LANGUAGE_OPTIONS, useI18n } from '../src/utils/i18n';
import SensitiveScreen from '../src/components/SensitiveScreen';
import { borderRadius, colors, shadows, spacing } from '../src/utils/theme';

export default function SettingsScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user, setUser, logout, updateProfile } = useAuthStore();
  const { language, t } = useI18n();

  const [isPrivate, setIsPrivate] = useState(user?.is_private || false);
  const [selectedLanguage, setSelectedLanguage] = useState<AppLanguage>(language);
  const [showPasswordForm, setShowPasswordForm] = useState(false);
  const [showEmailForm, setShowEmailForm] = useState(false);
  const [oldPassword, setOldPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [newEmail, setNewEmail] = useState(user?.email || '');
  const [emailPassword, setEmailPassword] = useState('');
  const [savingEmail, setSavingEmail] = useState(false);
  const [savingPassword, setSavingPassword] = useState(false);

  useEffect(() => {
    setIsPrivate(!!user?.is_private);
  }, [user?.is_private]);

  useEffect(() => {
    setNewEmail(user?.email || '');
  }, [user?.email]);

  useEffect(() => {
    setSelectedLanguage(language);
  }, [language]);

  const togglePrivacy = async (val: boolean) => {
    const previous = isPrivate;
    setIsPrivate(val);
    try {
      await updateProfile({ is_private: val });
    } catch {
      setIsPrivate(previous);
      Alert.alert(t('error'), t('couldNotUpdatePrivacy'));
    }
  };

  const changeLanguage = async (nextLanguage: AppLanguage) => {
    const previous = selectedLanguage;
    setSelectedLanguage(nextLanguage);
    try {
      await updateProfile({ language: nextLanguage });
    } catch {
      setSelectedLanguage(previous);
      Alert.alert(t('error'), t('couldNotUpdateLanguage'));
    }
  };

  const changePassword = async () => {
    if (!oldPassword || !newPassword) { Alert.alert('Error', 'Fill in both fields'); return; }
    if (newPassword.length < 8) { Alert.alert('Error', 'New password must be at least 8 characters'); return; }
    setSavingPassword(true);
    try {
      await api.put('/users/me/password', { old_password: oldPassword, new_password: newPassword });
      Alert.alert('Done', 'Password updated');
      setShowPasswordForm(false);
      setOldPassword(''); setNewPassword('');
    } catch (error: any) {
      Alert.alert('Error', error?.response?.data?.detail || 'Could not update password');
    } finally {
      setSavingPassword(false);
    }
  };

  const changeEmail = async () => {
    if (!newEmail || !newEmail.includes('@')) { Alert.alert('Error', 'Enter a valid email'); return; }
    if (!emailPassword) { Alert.alert('Verification required', 'Enter your current password to change email.'); return; }
    setSavingEmail(true);
    try {
      const response = await api.put('/users/me/email', { email: newEmail, password: emailPassword });
      setUser(response.data);
      Alert.alert('Done', 'Email updated');
      setShowEmailForm(false);
      setEmailPassword('');
    } catch (error: any) {
      Alert.alert('Error', error?.response?.data?.detail || 'Could not update email');
    } finally {
      setSavingEmail(false);
    }
  };

  const handleLogout = () => {
    Alert.alert('Sign Out', 'Are you sure?', [
      { text: 'Cancel' },
      { text: 'Sign Out', style: 'destructive', onPress: () => { logout(); router.replace('/(auth)/login'); } },
    ]);
  };

  const handleDeleteAccount = () => {
    Alert.alert('Delete Account', 'This will permanently delete your account and all your data. This cannot be undone.', [
      { text: 'Cancel' },
      { text: 'Delete', style: 'destructive', onPress: async () => {
        try {
          await api.delete('/users/me');
          logout();
          router.replace('/(auth)/login');
        } catch { Alert.alert('Error', 'Could not delete account'); }
      }},
    ]);
  };

  return (
    <SensitiveScreen style={s.root} label="Account settings">
      <View style={[s.header, { paddingTop: insets.top }]}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="chevron-back" size={20} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={s.headerTitle}>{t('settings')}</Text>
        <View style={{ width: 40 }} />
      </View>

      <ScrollView style={s.content} showsVerticalScrollIndicator={false}>
        {/* Privacy */}
        <View style={s.section}>
          <Text style={s.sectionTitle}>{t('privacy')}</Text>
          <View style={s.row}>
            <View style={s.rowLeft}>
              <Ionicons name="lock-closed-outline" size={20} color={colors.textPrimary} />
              <View style={s.rowText}>
                <Text style={s.rowLabel}>{t('privateAccount')}</Text>
                <Text style={s.rowSub}>{t('privateAccountDescription')}</Text>
              </View>
            </View>
            <Switch value={isPrivate} onValueChange={togglePrivacy} trackColor={{ false: colors.borderMedium, true: colors.accentPrimary }} thumbColor={colors.textInverse} />
          </View>
        </View>

        {/* Email */}
        <View style={s.section}>
          <Text style={s.sectionTitle}>{t('account')}</Text>
          <TouchableOpacity style={s.row} onPress={() => setShowEmailForm(!showEmailForm)}>
            <View style={s.rowLeft}>
              <Ionicons name="mail-outline" size={20} color={colors.textPrimary} />
              <View>
                <Text style={s.rowLabel}>{t('email')}</Text>
                <Text style={s.rowSub}>{user?.email}</Text>
              </View>
            </View>
            <Ionicons name="chevron-forward" size={16} color={colors.textHint} />
          </TouchableOpacity>
          {showEmailForm && (
            <View style={s.form}>
              <TextInput style={s.input} value={newEmail} onChangeText={setNewEmail} placeholder={t('newEmail')} keyboardType="email-address" autoCapitalize="none" placeholderTextColor={colors.textDisabled} />
              <TextInput style={s.input} value={emailPassword} onChangeText={setEmailPassword} placeholder="Current password" secureTextEntry placeholderTextColor={colors.textDisabled} />
              <Text style={s.formHelp}>We verify this change with your current password.</Text>
              <TouchableOpacity style={s.saveBtn} onPress={changeEmail} disabled={savingEmail}>
                <Text style={s.saveTx}>{savingEmail ? t('saving') : t('updateEmail')}</Text>
              </TouchableOpacity>
            </View>
          )}

          <TouchableOpacity style={s.row} onPress={() => router.push('/verify-phone' as any)}>
            <View style={s.rowLeft}>
              <Ionicons name="call-outline" size={20} color={colors.textPrimary} />
              <View>
                <Text style={s.rowLabel}>Phone</Text>
                <Text style={s.rowSub}>
                  {user?.phone_verified ? `${user?.phone || 'Verified phone'} verified` : 'Verify to post, story, message, and call'}
                </Text>
              </View>
            </View>
            <Ionicons name="chevron-forward" size={16} color={colors.textHint} />
          </TouchableOpacity>

          <TouchableOpacity style={s.row} onPress={() => setShowPasswordForm(!showPasswordForm)}>
            <View style={s.rowLeft}>
              <Ionicons name="key-outline" size={20} color={colors.textPrimary} />
              <Text style={s.rowLabel}>{t('password')}</Text>
            </View>
            <Ionicons name="chevron-forward" size={16} color={colors.textHint} />
          </TouchableOpacity>
          {showPasswordForm && (
            <View style={s.form}>
              <TextInput style={s.input} value={oldPassword} onChangeText={setOldPassword} placeholder="Current password" secureTextEntry placeholderTextColor={colors.textDisabled} />
              <TextInput style={s.input} value={newPassword} onChangeText={setNewPassword} placeholder="New password" secureTextEntry placeholderTextColor={colors.textDisabled} />
              <TouchableOpacity style={s.saveBtn} onPress={changePassword} disabled={savingPassword}>
                <Text style={s.saveTx}>{savingPassword ? 'Saving...' : 'Update Password'}</Text>
              </TouchableOpacity>
            </View>
          )}
        </View>

        {/* Language */}
        <View style={s.section}>
          <Text style={s.sectionTitle}>{t('preferences')}</Text>
          <View style={[s.row, s.languageRow]}>
            <View style={s.rowLeft}>
              <Ionicons name="language-outline" size={20} color={colors.textPrimary} />
              <Text style={s.rowLabel}>{t('language')}</Text>
            </View>
            <View style={s.languageOptions}>
              {LANGUAGE_OPTIONS.map((option) => (
                <TouchableOpacity
                  key={option.code}
                  style={[s.languageChip, selectedLanguage === option.code && s.languageChipOn]}
                  onPress={() => changeLanguage(option.code)}
                  activeOpacity={0.8}
                >
                  <Text style={[s.languageChipText, selectedLanguage === option.code && s.languageChipTextOn]}>
                    {option.nativeLabel}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>
        </View>

        {/* Legal and Safety */}
        <View style={s.section}>
          <Text style={s.sectionTitle}>Legal & Safety</Text>
          <TouchableOpacity style={s.row} onPress={() => router.push('/legal/terms' as any)}>
            <View style={s.rowLeft}>
              <Ionicons name="document-text-outline" size={20} color={colors.textPrimary} />
              <View style={s.rowText}>
                <Text style={s.rowLabel}>Terms of Service</Text>
                <Text style={s.rowSub}>Rules for using Captro</Text>
              </View>
            </View>
            <Ionicons name="chevron-forward" size={16} color={colors.textHint} />
          </TouchableOpacity>
          <TouchableOpacity style={s.row} onPress={() => router.push('/legal/privacy' as any)}>
            <View style={s.rowLeft}>
              <Ionicons name="hand-left-outline" size={20} color={colors.textPrimary} />
              <View style={s.rowText}>
                <Text style={s.rowLabel}>Privacy Policy</Text>
                <Text style={s.rowSub}>How Captro handles data</Text>
              </View>
            </View>
            <Ionicons name="chevron-forward" size={16} color={colors.textHint} />
          </TouchableOpacity>
          <TouchableOpacity style={s.row} onPress={() => router.push('/legal/community-guidelines' as any)}>
            <View style={s.rowLeft}>
              <Ionicons name="people-outline" size={20} color={colors.textPrimary} />
              <View style={s.rowText}>
                <Text style={s.rowLabel}>Community Guidelines</Text>
                <Text style={s.rowSub}>Posting, chat, and safety rules</Text>
              </View>
            </View>
            <Ionicons name="chevron-forward" size={16} color={colors.textHint} />
          </TouchableOpacity>
          <TouchableOpacity style={s.row} onPress={() => router.push('/legal/safety' as any)}>
            <View style={s.rowLeft}>
              <Ionicons name="shield-checkmark-outline" size={20} color={colors.textPrimary} />
              <View style={s.rowText}>
                <Text style={s.rowLabel}>Safety & Reporting</Text>
                <Text style={s.rowSub}>Report, block, and stay safe</Text>
              </View>
            </View>
            <Ionicons name="chevron-forward" size={16} color={colors.textHint} />
          </TouchableOpacity>
          <TouchableOpacity style={[s.row, s.lastRow]} onPress={() => Linking.openURL('mailto:karfalacisse900@gmail.com')}>
            <View style={s.rowLeft}>
              <Ionicons name="mail-outline" size={20} color={colors.textPrimary} />
              <View style={s.rowText}>
                <Text style={s.rowLabel}>Contact support</Text>
                <Text style={s.rowSub}>karfalacisse900@gmail.com</Text>
              </View>
            </View>
            <Ionicons name="open-outline" size={16} color={colors.textHint} />
          </TouchableOpacity>
        </View>

        {/* Sign Out */}
        <TouchableOpacity style={s.logoutBtn} onPress={handleLogout}>
          <Ionicons name="log-out-outline" size={20} color="#EF4444" />
          <Text style={s.logoutTx}>{t('signOut')}</Text>
        </TouchableOpacity>

        {/* Delete Account */}
        <TouchableOpacity style={s.deleteBtn} onPress={handleDeleteAccount}>
          <Ionicons name="trash-outline" size={18} color="#999" />
          <Text style={s.deleteTx}>{t('deleteAccount')}</Text>
        </TouchableOpacity>
      </ScrollView>
    </SensitiveScreen>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.bgApp },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: spacing.md, paddingBottom: spacing.gutter },
  backBtn: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    justifyContent: 'center',
    alignItems: 'center',
    ...shadows.elevation1,
  },
  headerTitle: { fontSize: 18, fontWeight: '600', color: colors.textPrimary },
  content: { flex: 1, paddingHorizontal: spacing.md },

  section: {
    marginBottom: spacing.md,
    padding: spacing.md,
    borderRadius: borderRadius.card,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation1,
  },
  sectionTitle: { fontSize: 12, fontWeight: '600', color: colors.textHint, textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: spacing.sm },
  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: 14, borderBottomWidth: 0.5, borderBottomColor: colors.divider, gap: spacing.gutter },
  lastRow: { borderBottomWidth: 0 },
  rowLeft: { flexDirection: 'row', alignItems: 'center', gap: spacing.gutter, flex: 1 },
  rowText: { flex: 1 },
  rowLabel: { fontSize: 16, fontWeight: '500', color: colors.textPrimary },
  rowSub: { fontSize: 13, color: colors.textSecondary, marginTop: 1 },
  rowValue: { fontSize: 14, color: colors.textSecondary },
  languageRow: { alignItems: 'flex-start' },
  languageOptions: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'flex-end', gap: spacing.sm, flex: 1 },
  languageChip: { paddingHorizontal: 12, paddingVertical: 8, borderRadius: 14, backgroundColor: colors.bgSubtle, borderWidth: 1, borderColor: colors.borderSubtle },
  languageChipOn: { backgroundColor: colors.accentPrimary, borderColor: colors.accentPrimary },
  languageChipText: { fontSize: 13, fontWeight: '500', color: colors.textSecondary },
  languageChipTextOn: { color: colors.textInverse },

  form: { paddingVertical: spacing.gutter, gap: 10 },
  input: { backgroundColor: colors.bgSubtle, borderRadius: borderRadius.md, borderWidth: 1, borderColor: colors.borderSubtle, paddingHorizontal: spacing.md, paddingVertical: 12, fontSize: 15, color: colors.textPrimary },
  formHelp: { fontSize: 12, lineHeight: 17, color: colors.textHint },
  saveBtn: { backgroundColor: colors.accentPrimary, borderRadius: borderRadius.md, paddingVertical: 14, alignItems: 'center' },
  saveTx: { fontSize: 15, fontWeight: '600', color: colors.textInverse },

  logoutBtn: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, marginTop: 20, paddingVertical: 16, borderRadius: 12, backgroundColor: '#FEF2F2' },
  logoutTx: { fontSize: 16, fontWeight: '600', color: '#EF4444' },
  deleteBtn: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, marginTop: 12, marginBottom: 40, paddingVertical: 14 },
  deleteTx: { fontSize: 14, color: '#999' },
});
