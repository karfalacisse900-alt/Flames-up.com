import React, { useEffect, useState, useRef } from 'react';
import {
  View, Text, StyleSheet, TextInput, TouchableOpacity, Image, ScrollView,
  KeyboardAvoidingView, Platform, ActivityIndicator, Alert,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import { useAuthStore } from '../src/store/authStore';
import api from '../src/api/client';
import { getPremiumStatus } from '../src/api/premium';
import { uploadImage } from '../src/utils/mediaUpload';

export default function EditProfileScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user, setUser } = useAuthStore();
  const [premiumActive, setPremiumActive] = useState(!!user?.is_premium);
  const isPremium = premiumActive || !!user?.is_premium;

  const [fullName, setFullName] = useState(user?.full_name || '');
  const [username, setUsername] = useState(user?.username || '');
  const [usernameStatus, setUsernameStatus] = useState<'idle'|'checking'|'available'|'taken'|'invalid'>('idle');
  const usernameTimer = useRef<any>(null);
  const [socialWebsite, setSocialWebsite] = useState(user?.social_website || '');
  const [socialTiktok, setSocialTiktok] = useState(user?.social_tiktok || '');
  const [socialInstagram, setSocialInstagram] = useState(user?.social_instagram || '');
  const [profileImage, setProfileImage] = useState(user?.profile_image || '');
  const [profileBackgroundImage, setProfileBackgroundImage] = useState(user?.profile_background_image || user?.cover_image || '');
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    let mounted = true;
    getPremiumStatus()
      .then((status) => {
        if (mounted) setPremiumActive(!!status.is_premium);
      })
      .catch(() => undefined);
    return () => { mounted = false; };
  }, [user?.is_premium]);

  // Username validation
  const sanitizeUsername = (text: string) => {
    return text.toLowerCase().replace(/[^a-z0-9_]/g, '').substring(0, 30);
  };

  const handleUsernameChange = (text: string) => {
    const clean = sanitizeUsername(text);
    setUsername(clean);
    if (clean === user?.username) { setUsernameStatus('idle'); return; }
    if (clean.length < 3) { setUsernameStatus('invalid'); return; }
    setUsernameStatus('checking');
    if (usernameTimer.current) clearTimeout(usernameTimer.current);
    usernameTimer.current = setTimeout(async () => {
      try {
        const res = await api.get(`/users/search/${clean}`);
        const taken = (res.data || []).some((u: any) => u.username?.toLowerCase() === clean && u.id !== user?.id);
        setUsernameStatus(taken ? 'taken' : 'available');
      } catch {
        setUsernameStatus('available'); // assume available if search fails
      }
    }, 500);
  };

  const pickProfileImage = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      allowsEditing: true, aspect: [1, 1], quality: 0.6, base64: true,
    });
    if (!result.canceled && result.assets?.[0]) {
      const asset = result.assets[0];
      // Show local preview immediately
      setProfileImage(asset.uri);
      
      if (asset.base64) {
        const b64 = asset.base64.startsWith('data:') ? asset.base64 : `data:image/jpeg;base64,${asset.base64}`;
        try {
          const url = await uploadImage(b64);
          if (url && url.startsWith('http')) {
            setProfileImage(url);
          } else {
            // Upload returned base64 fallback - keep local URI instead
            console.log('Image upload fell back to base64, using local URI');
          }
        } catch (e) {
          console.log('Profile image upload error:', e);
          Alert.alert('Upload Issue', 'Image will be saved locally. Upload may fail for large images.');
        }
      }
    }
  };

  const pickBackgroundImage = async () => {
    if (!isPremium) {
      Alert.alert('Premium background', 'Custom profile backgrounds are included with Premium.', [
        { text: 'Not now', style: 'cancel' },
        { text: 'Open Wallet', onPress: () => router.push('/wallet' as any) },
      ]);
      return;
    }
    const result = await ImagePicker.launchImageLibraryAsync({
      allowsEditing: true, aspect: [16, 9], quality: 0.75, base64: true,
    });
    if (!result.canceled && result.assets?.[0]) {
      const asset = result.assets[0];
      setProfileBackgroundImage(asset.uri);

      if (asset.base64) {
        const b64 = asset.base64.startsWith('data:') ? asset.base64 : `data:image/jpeg;base64,${asset.base64}`;
        try {
          const url = await uploadImage(b64);
          if (url && url.startsWith('http')) {
            setProfileBackgroundImage(url);
          }
        } catch (e) {
          console.log('Profile background upload error:', e);
          Alert.alert('Upload Issue', 'Background preview is set, but upload may fail for large images.');
        }
      }
    }
  };

  const handleSave = async () => {
    if (isSaving) return;
    if (usernameStatus === 'taken') {
      Alert.alert('Username Taken', 'Please choose a different username.');
      return;
    }
    if (usernameStatus === 'invalid') {
      Alert.alert('Invalid Username', 'Username must be at least 3 characters (letters, numbers, underscores only).');
      return;
    }
    setIsSaving(true);
    try {
      const payload: any = {
        full_name: fullName,
        username,
        profile_image: profileImage,
        social_website: socialWebsite,
        social_tiktok: socialTiktok,
        social_instagram: socialInstagram,
      };
      if (isPremium) {
        payload.profile_background_image = profileBackgroundImage;
        payload.cover_image = profileBackgroundImage;
      }
      
      const res = await api.put('/users/me', payload);
      if (res.data) {
        setUser(res.data);
        Alert.alert('Saved', 'Profile updated successfully');
        router.back();
      }
    } catch (error: any) {
      const msg = error?.response?.data?.detail || error?.message || 'Failed to update profile';
      console.log('Profile update error:', msg, error?.response?.status);
      Alert.alert('Error', msg);
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <KeyboardAvoidingView
      style={s.container}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      <View style={{ flex: 1, paddingTop: insets.top }}>
        {/* Header */}
        <View style={s.header}>
          <TouchableOpacity onPress={() => router.back()}>
            <Ionicons name="close" size={24} color="#1A1A1A" />
          </TouchableOpacity>
          <Text style={s.headerTitle}>Edit Profile</Text>
          <TouchableOpacity style={[s.saveBtn, isSaving && { opacity: 0.5 }]} onPress={handleSave} disabled={isSaving}>
            {isSaving ? <ActivityIndicator size="small" color="#FFF" /> : <Text style={s.saveBtnText}>Save</Text>}
          </TouchableOpacity>
        </View>

        <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingBottom: 60 }}>
          {/* Profile Image */}
          <View style={s.avatarSection}>
            <TouchableOpacity onPress={pickProfileImage} style={s.avatarWrap}>
              {profileImage ? (
                <Image source={{ uri: profileImage }} style={s.avatarImg} />
              ) : (
                <View style={s.avatarFallback}>
                  <Ionicons name="person" size={40} color="#CCC" />
                </View>
              )}
              <View style={s.avatarBadge}>
                <Ionicons name="camera" size={14} color="#FFF" />
              </View>
            </TouchableOpacity>
            <Text style={s.changePhotoText}>Change Photo</Text>
          </View>

          <View style={s.section}>
            <View style={s.sectionHeaderRow}>
              <Text style={s.sectionTitle}>Profile Background</Text>
              {isPremium ? (
                <View style={s.premiumPill}>
                  <Ionicons name="sparkles" size={12} color="#111111" />
                  <Text style={s.premiumPillText}>Premium</Text>
                </View>
              ) : null}
            </View>
            <TouchableOpacity style={s.backgroundCard} onPress={pickBackgroundImage} activeOpacity={0.86}>
              {profileBackgroundImage ? (
                <Image source={{ uri: profileBackgroundImage }} style={s.backgroundPreview} />
              ) : (
                <View style={s.backgroundEmpty}>
                  <Ionicons name="image-outline" size={26} color="#8A8A8A" />
                </View>
              )}
              <View style={s.backgroundShade} />
              <View style={s.backgroundCopy}>
                <Text style={s.backgroundTitle}>{isPremium ? 'Change background' : 'Unlock custom background'}</Text>
                <Text style={s.backgroundText}>{isPremium ? 'Use a wide banner image on your profile.' : 'Premium lets you upload a large profile banner.'}</Text>
              </View>
            </TouchableOpacity>
          </View>

          {/* Basic Info */}
          <View style={s.section}>
            <Text style={s.sectionTitle}>Basic Info</Text>
            <View style={s.field}>
              <Text style={s.fieldLabel}>Full Name</Text>
              <TextInput style={s.fieldInput} value={fullName} onChangeText={setFullName} placeholder="Your name" placeholderTextColor="#CCC" />
            </View>
            <View style={s.field}>
              <Text style={s.fieldLabel}>Username</Text>
              <View style={s.usernameFieldWrap}>
                <TextInput style={[s.fieldInput, s.usernameInput, usernameStatus === 'taken' && s.fieldInputError, usernameStatus === 'available' && s.fieldInputSuccess]} value={username} onChangeText={handleUsernameChange} placeholder="@username" placeholderTextColor="#CCC" autoCapitalize="none" />
                <View style={s.usernameStatusIcon}>
                  {usernameStatus === 'checking' && <ActivityIndicator size="small" color="#999" />}
                  {usernameStatus === 'available' && <Ionicons name="checkmark-circle" size={20} color="#10B981" />}
                  {usernameStatus === 'taken' && <Ionicons name="close-circle" size={20} color="#EF4444" />}
                  {usernameStatus === 'invalid' && <Ionicons name="alert-circle" size={20} color="#F59E0B" />}
                </View>
              </View>
              {usernameStatus === 'taken' && <Text style={s.fieldHintError}>Username already taken</Text>}
              {usernameStatus === 'invalid' && <Text style={s.fieldHintWarn}>Min 3 characters, lowercase letters, numbers, underscores</Text>}
              {usernameStatus === 'available' && <Text style={s.fieldHintSuccess}>Username is available</Text>}
            </View>
          </View>

          {/* Social Links */}
          <View style={s.section}>
            <Text style={s.sectionTitle}>Social Links</Text>
            <View style={s.socialField}>
              <Ionicons name="globe-outline" size={18} color="#0EA5E9" />
              <TextInput style={s.socialInput} value={socialWebsite} onChangeText={setSocialWebsite} placeholder="yourwebsite.com" placeholderTextColor="#CCC" autoCapitalize="none" keyboardType="url" />
            </View>
            <View style={s.socialField}>
              <Ionicons name="logo-tiktok" size={18} color="#1A1A1A" />
              <TextInput style={s.socialInput} value={socialTiktok} onChangeText={setSocialTiktok} placeholder="TikTok username" placeholderTextColor="#CCC" autoCapitalize="none" />
            </View>
            <View style={s.socialField}>
              <Ionicons name="logo-instagram" size={18} color="#E1306C" />
              <TextInput style={s.socialInput} value={socialInstagram} onChangeText={setSocialInstagram} placeholder="Instagram handle" placeholderTextColor="#CCC" autoCapitalize="none" />
            </View>
          </View>
        </ScrollView>
      </View>
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FAFAF8' },
  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 16, paddingVertical: 12,
    borderBottomWidth: 1, borderBottomColor: '#F0EDE7',
  },
  headerTitle: { fontSize: 17, fontWeight: '500', color: '#1A1A1A' },
  saveBtn: { backgroundColor: '#1A1A1A', paddingHorizontal: 20, paddingVertical: 9, borderRadius: 18, minWidth: 64, alignItems: 'center' },
  saveBtnText: { fontSize: 14, fontWeight: '500', color: '#FFF' },

  // Avatar
  avatarSection: { alignItems: 'center', paddingVertical: 24 },
  avatarWrap: { position: 'relative' },
  avatarImg: { width: 96, height: 96, borderRadius: 48 },
  avatarFallback: { width: 96, height: 96, borderRadius: 48, backgroundColor: '#F0EDE7', justifyContent: 'center', alignItems: 'center' },
  avatarBadge: {
    position: 'absolute', bottom: 0, right: 0,
    width: 32, height: 32, borderRadius: 16,
    backgroundColor: '#1A1A1A', justifyContent: 'center', alignItems: 'center',
    borderWidth: 3, borderColor: '#FAFAF8',
  },
  changePhotoText: { fontSize: 14, fontWeight: '600', color: '#0EA5E9', marginTop: 10 },

  // Section
  section: { paddingHorizontal: 16, paddingTop: 20 },
  sectionTitle: { fontSize: 12, fontWeight: '500', color: '#999', letterSpacing: 1, marginBottom: 12, textTransform: 'uppercase' },
  sectionHeaderRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  premiumPill: { height: 26, borderRadius: 13, backgroundColor: '#FFF64A', flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 10, marginBottom: 12 },
  premiumPillText: { color: '#111111', fontSize: 11, fontWeight: '700' },
  backgroundCard: { height: 150, borderRadius: 20, overflow: 'hidden', backgroundColor: '#EFEFEB', borderWidth: 1, borderColor: '#E7E3DD' },
  backgroundPreview: { ...StyleSheet.absoluteFillObject, width: '100%', height: '100%' },
  backgroundEmpty: { ...StyleSheet.absoluteFillObject, alignItems: 'center', justifyContent: 'center' },
  backgroundShade: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.24)' },
  backgroundCopy: { position: 'absolute', left: 14, right: 14, bottom: 14 },
  backgroundTitle: { color: '#FFFFFF', fontSize: 16, lineHeight: 20, fontWeight: '700' },
  backgroundText: { color: 'rgba(255,255,255,0.82)', fontSize: 12, lineHeight: 16, fontWeight: '500', marginTop: 2 },

  // Fields
  field: { marginBottom: 14 },
  fieldLabel: { fontSize: 13, fontWeight: '600', color: '#666', marginBottom: 6 },
  fieldInput: {
    backgroundColor: '#FFF', borderRadius: 14, borderWidth: 1.5, borderColor: '#F0EDE7',
    paddingHorizontal: 14, paddingVertical: 12, fontSize: 15, color: '#1A1A1A',
  },
  fieldInputError: { borderColor: '#FCA5A5' },
  fieldInputSuccess: { borderColor: '#6EE7B7' },
  fieldRow: { flexDirection: 'row', gap: 10 },
  usernameFieldWrap: { position: 'relative' },
  usernameInput: { paddingRight: 40 },
  usernameStatusIcon: { position: 'absolute', right: 12, top: 0, bottom: 0, justifyContent: 'center' },
  fieldHintError: { fontSize: 12, color: '#EF4444', marginTop: 4, fontWeight: '500' },
  fieldHintWarn: { fontSize: 12, color: '#F59E0B', marginTop: 4, fontWeight: '500' },
  fieldHintSuccess: { fontSize: 12, color: '#10B981', marginTop: 4, fontWeight: '500' },

  // Chips
  chipGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  chip: {
    paddingHorizontal: 16, paddingVertical: 10, borderRadius: 20,
    borderWidth: 1.5, borderColor: '#E8E4DF', backgroundColor: '#FFF',
  },
  chipActive: { backgroundColor: '#1A1A1A', borderColor: '#1A1A1A' },
  chipActiveAlt: { backgroundColor: '#7C3AED', borderColor: '#7C3AED' },
  chipText: { fontSize: 13, fontWeight: '600', color: '#888' },
  chipTextActive: { color: '#FFF' },

  // Social
  socialField: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: '#FFF', borderRadius: 14, borderWidth: 1, borderColor: '#F0EDE7',
    paddingHorizontal: 14, paddingVertical: 4, marginBottom: 10,
  },
  socialInput: { flex: 1, fontSize: 15, color: '#1A1A1A', paddingVertical: 12 },
});
