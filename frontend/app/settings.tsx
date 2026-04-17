import React, { useState } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Switch, TextInput, Alert, ScrollView,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuthStore } from '../src/store/authStore';
import api from '../src/api/client';

export default function SettingsScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user, setUser, logout } = useAuthStore();

  const [isPrivate, setIsPrivate] = useState(user?.is_private || false);
  const [showPasswordForm, setShowPasswordForm] = useState(false);
  const [showEmailForm, setShowEmailForm] = useState(false);
  const [oldPassword, setOldPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [newEmail, setNewEmail] = useState(user?.email || '');
  const [saving, setSaving] = useState(false);

  const togglePrivacy = async (val: boolean) => {
    setIsPrivate(val);
    try {
      await api.put('/users/me', { is_private: val });
      if (user) setUser({ ...user, is_private: val });
    } catch {}
  };

  const changePassword = async () => {
    if (!oldPassword || !newPassword) { Alert.alert('Error', 'Fill in both fields'); return; }
    if (newPassword.length < 6) { Alert.alert('Error', 'New password must be at least 6 characters'); return; }
    setSaving(true);
    try {
      await api.put('/users/me/password', { old_password: oldPassword, new_password: newPassword });
      Alert.alert('Done', 'Password updated');
      setShowPasswordForm(false);
      setOldPassword(''); setNewPassword('');
    } catch { Alert.alert('Error', 'Could not update password'); }
    setSaving(false);
  };

  const changeEmail = async () => {
    if (!newEmail || !newEmail.includes('@')) { Alert.alert('Error', 'Enter a valid email'); return; }
    setSaving(true);
    try {
      await api.put('/users/me', { email: newEmail });
      if (user) setUser({ ...user, email: newEmail });
      Alert.alert('Done', 'Email updated');
      setShowEmailForm(false);
    } catch { Alert.alert('Error', 'Could not update email'); }
    setSaving(false);
  };

  const handleLogout = () => {
    Alert.alert('Sign Out', 'Are you sure?', [
      { text: 'Cancel' },
      { text: 'Sign Out', style: 'destructive', onPress: () => { logout(); router.replace('/(auth)/login'); } },
    ]);
  };

  return (
    <View style={s.root}>
      <View style={[s.header, { paddingTop: insets.top }]}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="chevron-back" size={20} color="#1A1A1A" />
        </TouchableOpacity>
        <Text style={s.headerTitle}>Settings</Text>
        <View style={{ width: 40 }} />
      </View>

      <ScrollView style={s.content} showsVerticalScrollIndicator={false}>
        {/* Privacy */}
        <View style={s.section}>
          <Text style={s.sectionTitle}>Privacy</Text>
          <View style={s.row}>
            <View style={s.rowLeft}>
              <Ionicons name="lock-closed-outline" size={20} color="#1A1A1A" />
              <Text style={s.rowLabel}>Private Account</Text>
            </View>
            <Switch value={isPrivate} onValueChange={togglePrivacy} trackColor={{ false: '#E0E0E0', true: '#1A1A1A' }} thumbColor="#FFF" />
          </View>
        </View>

        {/* Email */}
        <View style={s.section}>
          <Text style={s.sectionTitle}>Account</Text>
          <TouchableOpacity style={s.row} onPress={() => setShowEmailForm(!showEmailForm)}>
            <View style={s.rowLeft}>
              <Ionicons name="mail-outline" size={20} color="#1A1A1A" />
              <View>
                <Text style={s.rowLabel}>Email</Text>
                <Text style={s.rowSub}>{user?.email}</Text>
              </View>
            </View>
            <Ionicons name="chevron-forward" size={16} color="#CCC" />
          </TouchableOpacity>
          {showEmailForm && (
            <View style={s.form}>
              <TextInput style={s.input} value={newEmail} onChangeText={setNewEmail} placeholder="New email" keyboardType="email-address" autoCapitalize="none" placeholderTextColor="#BBB" />
              <TouchableOpacity style={s.saveBtn} onPress={changeEmail} disabled={saving}>
                <Text style={s.saveTx}>{saving ? 'Saving...' : 'Update Email'}</Text>
              </TouchableOpacity>
            </View>
          )}

          <TouchableOpacity style={s.row} onPress={() => setShowPasswordForm(!showPasswordForm)}>
            <View style={s.rowLeft}>
              <Ionicons name="key-outline" size={20} color="#1A1A1A" />
              <Text style={s.rowLabel}>Password</Text>
            </View>
            <Ionicons name="chevron-forward" size={16} color="#CCC" />
          </TouchableOpacity>
          {showPasswordForm && (
            <View style={s.form}>
              <TextInput style={s.input} value={oldPassword} onChangeText={setOldPassword} placeholder="Current password" secureTextEntry placeholderTextColor="#BBB" />
              <TextInput style={s.input} value={newPassword} onChangeText={setNewPassword} placeholder="New password" secureTextEntry placeholderTextColor="#BBB" />
              <TouchableOpacity style={s.saveBtn} onPress={changePassword} disabled={saving}>
                <Text style={s.saveTx}>{saving ? 'Saving...' : 'Update Password'}</Text>
              </TouchableOpacity>
            </View>
          )}
        </View>

        {/* Language */}
        <View style={s.section}>
          <Text style={s.sectionTitle}>Preferences</Text>
          <View style={s.row}>
            <View style={s.rowLeft}>
              <Ionicons name="language-outline" size={20} color="#1A1A1A" />
              <Text style={s.rowLabel}>Language</Text>
            </View>
            <Text style={s.rowValue}>English</Text>
          </View>
        </View>

        {/* Sign Out */}
        <TouchableOpacity style={s.logoutBtn} onPress={handleLogout}>
          <Ionicons name="log-out-outline" size={20} color="#EF4444" />
          <Text style={s.logoutTx}>Sign Out</Text>
        </TouchableOpacity>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#FFF' },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingBottom: 12 },
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#F5F5F5', justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 18, fontWeight: '700', color: '#1A1A1A' },
  content: { flex: 1, paddingHorizontal: 16 },

  section: { marginBottom: 24 },
  sectionTitle: { fontSize: 12, fontWeight: '700', color: '#999', textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 8 },
  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: 14, borderBottomWidth: 0.5, borderBottomColor: '#F0F0F0' },
  rowLeft: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  rowLabel: { fontSize: 16, fontWeight: '500', color: '#1A1A1A' },
  rowSub: { fontSize: 13, color: '#999', marginTop: 1 },
  rowValue: { fontSize: 14, color: '#999' },

  form: { paddingVertical: 12, gap: 10 },
  input: { backgroundColor: '#F5F5F5', borderRadius: 12, paddingHorizontal: 16, paddingVertical: 12, fontSize: 15, color: '#1A1A1A' },
  saveBtn: { backgroundColor: '#1A1A1A', borderRadius: 12, paddingVertical: 14, alignItems: 'center' },
  saveTx: { fontSize: 15, fontWeight: '700', color: '#FFF' },

  logoutBtn: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, marginTop: 20, marginBottom: 40, paddingVertical: 16, borderRadius: 12, backgroundColor: '#FEF2F2' },
  logoutTx: { fontSize: 16, fontWeight: '600', color: '#EF4444' },
});
