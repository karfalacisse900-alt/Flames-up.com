import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  Switch,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, shadows } from '../src/utils/theme';
import { useAuthStore } from '../src/store/authStore';

function SettingRow({ icon, iconColor, label, onPress, showArrow = true, rightElement }: any) {
  return (
    <TouchableOpacity style={rowStyles.row} onPress={onPress} activeOpacity={0.7}>
      <Ionicons name={icon} size={22} color={iconColor || colors.textSecondary} />
      <Text style={rowStyles.label}>{label}</Text>
      <View style={{ flex: 1 }} />
      {rightElement || null}
      {showArrow && <Ionicons name="chevron-forward" size={18} color={colors.textHint} />}
    </TouchableOpacity>
  );
}

const rowStyles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 16,
    gap: 14,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderSubtle,
  },
  label: {
    fontSize: 16,
    color: colors.textPrimary,
    fontWeight: '500',
  },
});

export default function SettingsScreen() {
  const router = useRouter();
  const { logout } = useAuthStore();
  const [notifs, setNotifs] = React.useState(true);
  const [darkMode, setDarkMode] = React.useState(false);

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={styles.title}>Settings</Text>
        <View style={{ width: 44 }} />
      </View>

      <ScrollView showsVerticalScrollIndicator={false}>
        <Text style={styles.sectionTitle}>Account</Text>
        <View style={styles.card}>
          <SettingRow icon="person-outline" label="Edit Profile" onPress={() => router.push('/edit-profile')} />
          <SettingRow icon="lock-closed-outline" label="Privacy" />
          <SettingRow icon="shield-checkmark-outline" label="Security" />
        </View>

        <Text style={styles.sectionTitle}>Preferences</Text>
        <View style={styles.card}>
          <SettingRow icon="notifications-outline" label="Notifications" showArrow={false}
            rightElement={<Switch value={notifs} onValueChange={setNotifs} trackColor={{ true: colors.accentPrimary }} />}
          />
          <SettingRow icon="moon-outline" label="Dark Mode" showArrow={false}
            rightElement={<Switch value={darkMode} onValueChange={setDarkMode} trackColor={{ true: colors.accentPrimary }} />}
          />
          <SettingRow icon="language-outline" label="Language" />
        </View>

        <Text style={styles.sectionTitle}>Support</Text>
        <View style={styles.card}>
          <SettingRow icon="help-circle-outline" label="Help Center" />
          <SettingRow icon="document-text-outline" label="Terms of Service" />
          <SettingRow icon="shield-outline" label="Privacy Policy" />
          <SettingRow icon="information-circle-outline" label="About" />
        </View>

        <TouchableOpacity style={styles.logoutBtn} onPress={() => {
          logout();
          router.replace('/(auth)/login');
        }}>
          <Text style={styles.logoutText}>Log Out</Text>
        </TouchableOpacity>

        <Text style={styles.version}>flames-up v1.0.0</Text>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bgApp },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderSubtle,
  },
  backBtn: { width: 44, height: 44, borderRadius: 22, justifyContent: 'center', alignItems: 'center' },
  title: { fontSize: 18, fontWeight: '700', color: colors.textPrimary },
  sectionTitle: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.textHint,
    letterSpacing: 0.5,
    textTransform: 'uppercase',
    paddingHorizontal: 16,
    marginTop: 24,
    marginBottom: 8,
  },
  card: {
    backgroundColor: colors.bgCard,
    marginHorizontal: 16,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    overflow: 'hidden',
  },
  logoutBtn: {
    marginHorizontal: 16,
    marginTop: 32,
    backgroundColor: '#FEE2E2',
    paddingVertical: 16,
    borderRadius: 16,
    alignItems: 'center',
  },
  logoutText: { fontSize: 16, fontWeight: '700', color: colors.error },
  version: { textAlign: 'center', color: colors.textHint, fontSize: 12, marginTop: 16, marginBottom: 40 },
});
