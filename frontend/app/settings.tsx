import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Alert,
  Switch,
  Modal,
  Linking,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, shadows } from '../src/utils/theme';
import { useAuthStore } from '../src/store/authStore';

const LANGUAGES = [
  { code: 'en', name: 'English' },
  { code: 'es', name: 'Espa\u00f1ol' },
  { code: 'fr', name: 'Fran\u00e7ais' },
  { code: 'de', name: 'Deutsch' },
  { code: 'pt', name: 'Portugu\u00eas' },
  { code: 'ja', name: '\u65e5\u672c\u8a9e' },
  { code: 'zh', name: '\u4e2d\u6587' },
  { code: 'ar', name: '\u0627\u0644\u0639\u0631\u0628\u064a\u0629' },
];

function SettingRow({ icon, label, value, onPress, danger, toggle, toggleValue, onToggle }: any) {
  return (
    <TouchableOpacity style={s.settingRow} onPress={onPress} disabled={!!toggle}>
      <View style={[s.settingIcon, danger && { backgroundColor: '#FEE2E2' }]}> 
        <Ionicons name={icon} size={18} color={danger ? '#DC2626' : colors.accentPrimary} />
      </View>
      <Text style={[s.settingLabel, danger && { color: '#DC2626' }]}>{label}</Text>
      {toggle ? (
        <Switch
          value={toggleValue}
          onValueChange={onToggle}
          trackColor={{ false: colors.borderLight, true: colors.accentPrimary + '60' }}
          thumbColor={toggleValue ? colors.accentPrimary : '#FFFFFF'}
        />
      ) : (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
          {value && <Text style={s.settingValue}>{value}</Text>}
          <Ionicons name="chevron-forward" size={16} color={colors.textHint} />
        </View>
      )}
    </TouchableOpacity>
  );
}

export default function SettingsScreen() {
  const router = useRouter();
  const { logout } = useAuthStore();
  const [language, setLanguage] = useState('English');
  const [showLanguage, setShowLanguage] = useState(false);
  const [darkMode, setDarkMode] = useState(false);
  const [notifications, setNotifications] = useState(true);
  const [locationEnabled, setLocationEnabled] = useState(true);

  const handleLogout = () => {
    Alert.alert('Log Out', 'Are you sure you want to log out?', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Log Out', style: 'destructive', onPress: () => { logout(); router.replace('/'); } },
    ]);
  };

  const handleDeleteAccount = () => {
    Alert.alert(
      'Delete Account',
      'This will permanently delete your account and all your data. This action cannot be undone.',
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Delete', style: 'destructive', onPress: () => {
          Alert.alert('Account Scheduled for Deletion', 'Your account will be deleted within 30 days. Log in again to cancel.');
        }},
      ]
    );
  };

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={s.headerTitle}>Settings</Text>
        <View style={{ width: 44 }} />
      </View>

      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingBottom: 60 }}>
        {/* Account */}
        <Text style={s.sectionTitle}>ACCOUNT</Text>
        <View style={s.sectionCard}>
          <SettingRow icon="person-outline" label="Edit Profile" onPress={() => router.push('/edit-profile' as any)} />
          <SettingRow icon="lock-closed-outline" label="Change Password" onPress={() => Alert.alert('Change Password', 'Password reset email sent.')} />
          <SettingRow icon="mail-outline" label="Email" value="demo@flames-up.com" onPress={() => {}} />
        </View>

        {/* Preferences */}
        <Text style={s.sectionTitle}>PREFERENCES</Text>
        <View style={s.sectionCard}>
          <SettingRow icon="language-outline" label="Language" value={language} onPress={() => setShowLanguage(true)} />
          <SettingRow icon="moon-outline" label="Dark Mode" toggle toggleValue={darkMode} onToggle={setDarkMode} />
          <SettingRow icon="notifications-outline" label="Push Notifications" toggle toggleValue={notifications} onToggle={setNotifications} />
          <SettingRow icon="location-outline" label="Location Services" toggle toggleValue={locationEnabled} onToggle={setLocationEnabled} />
        </View>

        {/* Privacy & Security */}
        <Text style={s.sectionTitle}>PRIVACY & SECURITY</Text>
        <View style={s.sectionCard}>
          <SettingRow icon="shield-outline" label="Security" onPress={() => Alert.alert('Security', 'Two-factor authentication and login activity settings coming soon.')} />
          <SettingRow icon="eye-off-outline" label="Privacy" onPress={() => Alert.alert('Privacy', 'Control who can see your profile, posts, and stories.')} />
          <SettingRow icon="people-outline" label="Blocked Users" onPress={() => Alert.alert('Blocked Users', 'No blocked users.')} />
          <SettingRow icon="hand-left-outline" label="Content Preferences" onPress={() => Alert.alert('Content Preferences', 'Manage sensitive content display.')} />
        </View>

        {/* Legal */}
        <Text style={s.sectionTitle}>LEGAL</Text>
        <View style={s.sectionCard}>
          <SettingRow icon="document-text-outline" label="Terms of Service" onPress={() => Linking.openURL('https://flames-up.com/terms')} />
          <SettingRow icon="shield-checkmark-outline" label="Privacy Policy" onPress={() => Linking.openURL('https://flames-up.com/privacy')} />
          <SettingRow icon="information-circle-outline" label="About Flames-Up" onPress={() => Alert.alert('Flames-Up', 'Version 1.0.0\n\nFlames-Up is a social platform built for authentic connections and community.\n\n\u00a9 2025 Flames-Up')} />
          <SettingRow icon="help-circle-outline" label="Help & Support" onPress={() => Linking.openURL('https://flames-up.com/support')} />
        </View>

        {/* Data */}
        <Text style={s.sectionTitle}>DATA</Text>
        <View style={s.sectionCard}>
          <SettingRow icon="download-outline" label="Download My Data" onPress={() => Alert.alert('Data Download', 'Your data export will be emailed to you within 48 hours.')} />
          <SettingRow icon="cloud-outline" label="Storage & Cache" onPress={() => Alert.alert('Cache Cleared', 'App cache has been cleared.')} />
        </View>

        {/* Danger Zone */}
        <Text style={s.sectionTitle}>DANGER ZONE</Text>
        <View style={s.sectionCard}>
          <SettingRow icon="log-out-outline" label="Log Out" danger onPress={handleLogout} />
          <SettingRow icon="trash-outline" label="Delete Account" danger onPress={handleDeleteAccount} />
        </View>
      </ScrollView>

      {/* Language Modal */}
      <Modal visible={showLanguage} transparent animationType="slide" onRequestClose={() => setShowLanguage(false)}>
        <TouchableOpacity style={s.overlay} activeOpacity={1} onPress={() => setShowLanguage(false)}>
          <View style={s.langSheet}>
            <View style={s.sheetHandle} />
            <Text style={s.langTitle}>Select Language</Text>
            {LANGUAGES.map((lang) => (
              <TouchableOpacity
                key={lang.code}
                style={[s.langItem, language === lang.name && s.langItemActive]}
                onPress={() => { setLanguage(lang.name); setShowLanguage(false); }}
              >
                <Text style={[s.langItemText, language === lang.name && { color: colors.accentPrimary, fontWeight: '700' }]}>{lang.name}</Text>
                {language === lang.name && <Ionicons name="checkmark" size={20} color={colors.accentPrimary} />}
              </TouchableOpacity>
            ))}
          </View>
        </TouchableOpacity>
      </Modal>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bgApp },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: colors.borderSubtle },
  backBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 18, fontWeight: '700', color: colors.textPrimary, fontStyle: 'italic' },
  sectionTitle: { fontSize: 12, fontWeight: '800', color: colors.textHint, letterSpacing: 0.5, paddingHorizontal: 20, paddingTop: 24, paddingBottom: 10 },
  sectionCard: { marginHorizontal: 16, backgroundColor: colors.bgCard, borderRadius: 20, borderWidth: 1, borderColor: colors.borderLight, overflow: 'hidden' },
  settingRow: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 16, borderBottomWidth: 1, borderBottomColor: colors.borderSubtle },
  settingIcon: { width: 36, height: 36, borderRadius: 12, backgroundColor: colors.accentPrimaryLight, justifyContent: 'center', alignItems: 'center', marginRight: 14 },
  settingLabel: { flex: 1, fontSize: 15, fontWeight: '500', color: colors.textPrimary },
  settingValue: { fontSize: 14, color: colors.textHint },
  overlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.4)', justifyContent: 'flex-end' },
  langSheet: { backgroundColor: '#FFFFFF', borderTopLeftRadius: 20, borderTopRightRadius: 20, paddingTop: 8, paddingBottom: 34, maxHeight: '70%' },
  sheetHandle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.borderLight, alignSelf: 'center', marginBottom: 16 },
  langTitle: { fontSize: 18, fontWeight: '700', color: colors.textPrimary, paddingHorizontal: 20, marginBottom: 12 },
  langItem: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 20, paddingVertical: 16, borderTopWidth: 1, borderTopColor: colors.borderSubtle },
  langItemActive: { backgroundColor: colors.accentPrimaryLight },
  langItemText: { fontSize: 16, color: colors.textPrimary },
});
