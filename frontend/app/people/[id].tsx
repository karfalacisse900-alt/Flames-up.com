import React, { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Alert, Image, ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import PeopleCard from '../../src/components/PeopleCard';
import { PeopleProfile, claimPeopleProfile, getPeopleProfile, reportPeopleProfile, togglePeopleInteraction } from '../../src/utils/recommendFeatures';
import { colors } from '../../src/utils/theme';
import { openSafeUrl } from '../../src/utils/safeLinking';

export default function PeopleDetailScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{ id?: string }>();
  const id = Array.isArray(params.id) ? params.id[0] : params.id || '';
  const [profile, setProfile] = useState<PeopleProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [claiming, setClaiming] = useState(false);
  const [claimMessage, setClaimMessage] = useState('');

  const load = useCallback(async () => {
    if (!id) return;
    setLoading(true);
    try {
      setProfile(await getPeopleProfile(id));
    } catch (error: any) {
      Alert.alert('Could not load profile', error?.response?.data?.detail || 'Try again.', [
        { text: 'OK', onPress: () => router.back() },
      ]);
    } finally {
      setLoading(false);
    }
  }, [id, router]);

  useEffect(() => { load(); }, [load]);

  const interact = async (kind: 'follow' | 'save') => {
    if (!profile) return;
    try {
      const result = await togglePeopleInteraction(profile.id, kind);
      const countKey = kind === 'follow' ? 'followers_count' : 'saves_count';
      const activeKey = kind === 'follow' ? 'followed' : 'saved';
      setProfile({
        ...profile,
        [activeKey]: result.active,
        [countKey]: Math.max(0, Number((profile as any)[countKey] || 0) + (result.active ? 1 : -1)),
      } as PeopleProfile);
    } catch (error: any) {
      Alert.alert('Not updated', error?.response?.data?.detail || 'Try again in a moment.');
    }
  };

  const open = (url?: string) => {
    if (url) openSafeUrl(url);
  };

  const report = async () => {
    if (!profile) return;
    try {
      await reportPeopleProfile(profile.id);
      Alert.alert('Reported', 'Admin will review this profile.');
    } catch (error: any) {
      Alert.alert('Report failed', error?.response?.data?.detail || 'Could not report this profile.');
    }
  };

  const claim = async () => {
    if (!profile || claiming) return;
    setClaiming(true);
    try {
      await claimPeopleProfile(profile.id, claimMessage.trim() || 'I want to claim this profile.');
      Alert.alert('Claim sent', 'Admin will review your claim.');
      setProfile({ ...profile, claim_status: 'pending' });
    } catch (error: any) {
      Alert.alert('Claim failed', error?.response?.data?.detail || 'Could not submit claim.');
    } finally {
      setClaiming(false);
    }
  };

  if (loading) {
    return (
      <SafeAreaView style={styles.safeArea}>
        <View style={styles.loading}><ActivityIndicator size="large" color={colors.textPrimary} /></View>
      </SafeAreaView>
    );
  }

  if (!profile) return null;

  return (
    <SafeAreaView style={styles.safeArea} edges={['top']}>
      <View style={styles.header}>
        <TouchableOpacity style={styles.headerBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={30} color="#FFFFFF" />
        </TouchableOpacity>
        <TouchableOpacity style={styles.headerBtn} onPress={report}>
          <Ionicons name="flag-outline" size={23} color="#FFFFFF" />
        </TouchableOpacity>
      </View>
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingBottom: insets.bottom + 32 }}>
        <View style={styles.hero}>
          {profile.profile_image ? (
            <Image source={{ uri: profile.profile_image }} style={styles.heroImage} />
          ) : (
            <View style={[styles.heroImage, styles.heroFallback]}>
              <Text style={styles.heroInitial}>{profile.name[0]?.toUpperCase() || 'P'}</Text>
            </View>
          )}
          <View style={styles.heroShade} />
          <View style={styles.heroCopy}>
            <Text style={styles.role}>{profile.role}</Text>
            <Text style={styles.name}>{profile.name}</Text>
            <Text style={styles.city}>{profile.city || 'Public profile'}</Text>
          </View>
        </View>

        <View style={styles.content}>
          <View style={styles.statsRow}>
            <TouchableOpacity style={[styles.followBtn, profile.followed && styles.followBtnOn]} onPress={() => interact('follow')}>
              <Text style={[styles.followText, profile.followed && styles.followTextOn]}>{profile.followed ? 'Following' : 'Follow'}</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[styles.saveBtn, profile.saved && styles.saveBtnOn]} onPress={() => interact('save')}>
              <Ionicons name={profile.saved ? 'bookmark' : 'bookmark-outline'} size={15} color={profile.saved ? '#FFFFFF' : '#111111'} />
              <Text style={[styles.saveText, profile.saved && styles.saveTextOn]}>{profile.saves_count}</Text>
            </TouchableOpacity>
          </View>

          <Text style={styles.sectionTitle}>Bio</Text>
          <Text style={styles.body}>{profile.bio || 'No public bio yet.'}</Text>
          {profile.known_for ? (
            <>
              <Text style={styles.sectionTitle}>Known for</Text>
              <Text style={styles.body}>{profile.known_for}</Text>
            </>
          ) : null}

          <View style={styles.links}>
            {profile.instagram_url ? <TouchableOpacity style={styles.link} onPress={() => open(profile.instagram_url)}><Ionicons name="logo-instagram" size={18} color="#111111" /><Text style={styles.linkText}>Instagram</Text></TouchableOpacity> : null}
            {profile.tiktok_url ? <TouchableOpacity style={styles.link} onPress={() => open(profile.tiktok_url)}><Ionicons name="musical-notes-outline" size={18} color="#111111" /><Text style={styles.linkText}>TikTok</Text></TouchableOpacity> : null}
            {profile.youtube_url ? <TouchableOpacity style={styles.link} onPress={() => open(profile.youtube_url)}><Ionicons name="logo-youtube" size={18} color="#111111" /><Text style={styles.linkText}>YouTube</Text></TouchableOpacity> : null}
            {profile.website_url ? <TouchableOpacity style={styles.link} onPress={() => open(profile.website_url)}><Ionicons name="globe-outline" size={18} color="#111111" /><Text style={styles.linkText}>Website</Text></TouchableOpacity> : null}
          </View>

          <View style={styles.claimBox}>
            <Text style={styles.claimTitle}>Claim profile</Text>
            <Text style={styles.claimText}>If this is you, send a claim for admin approval.</Text>
            <TextInput value={claimMessage} onChangeText={setClaimMessage} placeholder="Add a short verification note..." placeholderTextColor="#8B8B8B" style={styles.claimInput} />
            <TouchableOpacity style={styles.claimButton} onPress={claim} disabled={claiming}>
              {claiming ? <ActivityIndicator color="#FFFFFF" /> : <Text style={styles.claimButtonText}>{profile.claim_status === 'pending' ? 'Claim pending' : 'Submit claim'}</Text>}
            </TouchableOpacity>
          </View>

          {profile.similar_people?.length ? (
            <>
              <Text style={styles.sectionTitle}>Similar people</Text>
              <View style={{ gap: 12 }}>
                {profile.similar_people.map((item) => <PeopleCard key={item.id} profile={item} />)}
              </View>
            </>
          ) : null}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: { flex: 1, backgroundColor: colors.bgApp },
  loading: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.bgApp },
  header: { position: 'absolute', top: 44, left: 0, right: 0, zIndex: 10, flexDirection: 'row', justifyContent: 'space-between', paddingHorizontal: 18 },
  headerBtn: { width: 46, height: 46, borderRadius: 23, backgroundColor: 'rgba(0,0,0,0.32)', alignItems: 'center', justifyContent: 'center' },
  hero: { height: 430, backgroundColor: '#111111', position: 'relative' },
  heroImage: { width: '100%', height: '100%' },
  heroFallback: { alignItems: 'center', justifyContent: 'center', backgroundColor: '#DFF0D8' },
  heroInitial: { color: '#111111', fontSize: 72, fontWeight: '500' },
  heroShade: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.28)' },
  heroCopy: { position: 'absolute', left: 22, right: 22, bottom: 24 },
  role: { color: 'rgba(255,255,255,0.84)', fontSize: 16, fontWeight: '600', textTransform: 'capitalize' },
  name: { color: '#FFFFFF', fontSize: 42, lineHeight: 45, fontWeight: '500', marginTop: 4 },
  city: { color: 'rgba(255,255,255,0.82)', fontSize: 14, fontWeight: '600', marginTop: 8 },
  content: { padding: 18, gap: 18 },
  statsRow: { flexDirection: 'row', gap: 10 },
  followBtn: { flex: 1, height: 42, borderRadius: 21, backgroundColor: colors.accentPrimary, borderWidth: 1, borderColor: colors.accentPrimaryHover, alignItems: 'center', justifyContent: 'center' },
  followBtnOn: { backgroundColor: '#111111' },
  followText: { color: '#FFFFFF', fontSize: 14, fontWeight: '500' },
  followTextOn: { color: '#FFFFFF' },
  saveBtn: { width: 78, height: 42, borderRadius: 21, backgroundColor: '#F3F3F3', flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 5 },
  saveBtnOn: { backgroundColor: colors.accentPrimary, borderWidth: 1, borderColor: colors.accentPrimaryHover },
  saveText: { color: '#111111', fontSize: 14, fontWeight: '500' },
  saveTextOn: { color: '#FFFFFF' },
  sectionTitle: { color: '#111111', fontSize: 20, fontWeight: '500' },
  body: { color: '#333333', fontSize: 16, lineHeight: 23, fontWeight: '500' },
  links: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  link: { minHeight: 38, borderRadius: 19, backgroundColor: '#F2F2F2', flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 12 },
  linkText: { color: '#111111', fontSize: 13, fontWeight: '500' },
  claimBox: { borderRadius: 22, backgroundColor: '#F7F7F7', borderWidth: 1, borderColor: '#ECECEC', padding: 14, gap: 10 },
  claimTitle: { color: '#111111', fontSize: 17, fontWeight: '500' },
  claimText: { color: '#686868', fontSize: 13, lineHeight: 18, fontWeight: '500' },
  claimInput: { minHeight: 48, borderRadius: 16, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#E4E4E4', paddingHorizontal: 12, color: '#111111', fontWeight: '500' },
  claimButton: { height: 40, borderRadius: 20, backgroundColor: colors.accentPrimary, borderWidth: 1, borderColor: colors.accentPrimaryHover, alignItems: 'center', justifyContent: 'center' },
  claimButtonText: { color: '#FFFFFF', fontSize: 14, fontWeight: '500' },
});
