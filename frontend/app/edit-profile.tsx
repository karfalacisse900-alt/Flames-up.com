import React, { useState, useEffect } from 'react';
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
import { uploadImage } from '../src/utils/mediaUpload';

const LOOKING_FOR_OPTIONS = ['Friends', 'Networking', 'Explore', 'Events', 'Collab', 'Dating'];
const INTEREST_OPTIONS = ['Food', 'Fashion', 'Music', 'Art', 'Travel', 'Nightlife', 'Street Culture', 'Photography', 'Film', 'Tech', 'Fitness', 'Comedy', 'Thrifting', 'Coffee', 'Vinyl', 'Sneakers'];

export default function EditProfileScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user, setUser } = useAuthStore();

  const [fullName, setFullName] = useState(user?.full_name || '');
  const [username, setUsername] = useState(user?.username || '');
  const [bio, setBio] = useState(user?.bio || '');
  const [city, setCity] = useState(user?.city || '');
  const [age, setAge] = useState(user?.age || '');
  const [lookingFor, setLookingFor] = useState<string[]>(() => {
    try { return JSON.parse(user?.looking_for || '[]'); } catch { return []; }
  });
  const [interests, setInterests] = useState<string[]>(() => {
    try { return JSON.parse(user?.interests || '[]'); } catch { return []; }
  });
  const [socialWebsite, setSocialWebsite] = useState(user?.social_website || '');
  const [socialTiktok, setSocialTiktok] = useState(user?.social_tiktok || '');
  const [socialInstagram, setSocialInstagram] = useState(user?.social_instagram || '');
  const [profileImage, setProfileImage] = useState(user?.profile_image || '');
  const [isSaving, setIsSaving] = useState(false);

  const toggleLookingFor = (item: string) => {
    setLookingFor(prev =>
      prev.includes(item) ? prev.filter(i => i !== item) : [...prev, item]
    );
  };

  const toggleInterest = (item: string) => {
    setInterests(prev =>
      prev.includes(item) ? prev.filter(i => i !== item) : [...prev, item]
    );
  };

  const pickProfileImage = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      allowsEditing: true, aspect: [1, 1], quality: 0.8, base64: true,
    });
    if (!result.canceled && result.assets?.[0]) {
      const asset = result.assets[0];
      setProfileImage(asset.uri);
      if (asset.base64) {
        const b64 = asset.base64.startsWith('data:') ? asset.base64 : `data:image/jpeg;base64,${asset.base64}`;
        const url = await uploadImage(b64);
        if (url) setProfileImage(url);
      }
    }
  };

  const handleSave = async () => {
    if (isSaving) return;
    setIsSaving(true);
    try {
      const res = await api.put('/users/me', {
        full_name: fullName,
        username,
        bio,
        city,
        age,
        profile_image: profileImage,
        looking_for: JSON.stringify(lookingFor),
        interests: JSON.stringify(interests),
        social_website: socialWebsite,
        social_tiktok: socialTiktok,
        social_instagram: socialInstagram,
      });
      setUser({ ...user, ...res.data });
      Alert.alert('Saved', 'Profile updated successfully');
      router.back();
    } catch (error) {
      Alert.alert('Error', 'Failed to update profile');
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

          {/* Basic Info */}
          <View style={s.section}>
            <Text style={s.sectionTitle}>Basic Info</Text>
            <View style={s.field}>
              <Text style={s.fieldLabel}>Full Name</Text>
              <TextInput style={s.fieldInput} value={fullName} onChangeText={setFullName} placeholder="Your name" placeholderTextColor="#CCC" />
            </View>
            <View style={s.field}>
              <Text style={s.fieldLabel}>Username</Text>
              <TextInput style={s.fieldInput} value={username} onChangeText={setUsername} placeholder="@username" placeholderTextColor="#CCC" autoCapitalize="none" />
            </View>
            <View style={s.field}>
              <Text style={s.fieldLabel}>Bio</Text>
              <TextInput style={[s.fieldInput, { minHeight: 70, textAlignVertical: 'top' }]} value={bio} onChangeText={setBio} placeholder="Tell us about yourself" placeholderTextColor="#CCC" multiline maxLength={200} />
            </View>
          </View>

          {/* Personal Info */}
          <View style={s.section}>
            <Text style={s.sectionTitle}>Personal Info</Text>
            <View style={s.fieldRow}>
              <View style={[s.field, { flex: 1 }]}>
                <Text style={s.fieldLabel}>Age</Text>
                <TextInput style={s.fieldInput} value={age} onChangeText={setAge} placeholder="25" placeholderTextColor="#CCC" keyboardType="numeric" maxLength={3} />
              </View>
              <View style={[s.field, { flex: 2 }]}>
                <Text style={s.fieldLabel}>Location</Text>
                <TextInput style={s.fieldInput} value={city} onChangeText={setCity} placeholder="Brooklyn, NYC" placeholderTextColor="#CCC" />
              </View>
            </View>
          </View>

          {/* Looking For */}
          <View style={s.section}>
            <Text style={s.sectionTitle}>Looking For</Text>
            <View style={s.chipGrid}>
              {LOOKING_FOR_OPTIONS.map(item => {
                const active = lookingFor.includes(item);
                return (
                  <TouchableOpacity
                    key={item}
                    style={[s.chip, active && s.chipActive]}
                    onPress={() => toggleLookingFor(item)}
                  >
                    <Text style={[s.chipText, active && s.chipTextActive]}>{item}</Text>
                  </TouchableOpacity>
                );
              })}
            </View>
          </View>

          {/* Interests */}
          <View style={s.section}>
            <Text style={s.sectionTitle}>Interests</Text>
            <View style={s.chipGrid}>
              {INTEREST_OPTIONS.map(item => {
                const active = interests.includes(item);
                return (
                  <TouchableOpacity
                    key={item}
                    style={[s.chip, active && s.chipActiveAlt]}
                    onPress={() => toggleInterest(item)}
                  >
                    <Text style={[s.chipText, active && s.chipTextActive]}>{item}</Text>
                  </TouchableOpacity>
                );
              })}
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
  headerTitle: { fontSize: 17, fontWeight: '700', color: '#1A1A1A' },
  saveBtn: { backgroundColor: '#1A1A1A', paddingHorizontal: 20, paddingVertical: 9, borderRadius: 18, minWidth: 64, alignItems: 'center' },
  saveBtnText: { fontSize: 14, fontWeight: '700', color: '#FFF' },

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
  sectionTitle: { fontSize: 12, fontWeight: '700', color: '#999', letterSpacing: 1, marginBottom: 12, textTransform: 'uppercase' },

  // Fields
  field: { marginBottom: 14 },
  fieldLabel: { fontSize: 13, fontWeight: '600', color: '#666', marginBottom: 6 },
  fieldInput: {
    backgroundColor: '#FFF', borderRadius: 14, borderWidth: 1, borderColor: '#F0EDE7',
    paddingHorizontal: 14, paddingVertical: 12, fontSize: 15, color: '#1A1A1A',
  },
  fieldRow: { flexDirection: 'row', gap: 10 },

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
