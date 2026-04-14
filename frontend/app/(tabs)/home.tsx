import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView,
  RefreshControl, Dimensions, ActivityIndicator,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as Location from 'expo-location';
import { colors } from '../../src/utils/theme';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';

const { width: SW } = Dimensions.get('window');
const GAP = 10;

// City configs — only hero block per city, no sub-category blocks
type CityConfig = {
  id: string; label: string; icon: string;
  heroTitle: string; heroSub: string; heroColor: string;
};

const CITIES: Record<string, CityConfig> = {
  near: { id: 'near', label: 'Near You', icon: 'location', heroTitle: 'Around You', heroSub: 'Discover what\'s nearby', heroColor: '#1B4332' },
  global: { id: 'global', label: 'Global', icon: 'globe-outline', heroTitle: 'World Scenes', heroSub: 'Culture from everywhere', heroColor: '#0C2340' },
  nyc: { id: 'nyc', label: 'NYC', icon: 'business-outline', heroTitle: 'Today in NYC', heroSub: 'The city that never sleeps', heroColor: '#1A1A1A' },
  miami: { id: 'miami', label: 'Miami', icon: 'sunny-outline', heroTitle: 'Today in Miami', heroSub: 'Sun, culture & vibes', heroColor: '#0E7490' },
  tokyo: { id: 'tokyo', label: 'Tokyo', icon: 'train-outline', heroTitle: 'Today in Tokyo', heroSub: 'Tradition meets future', heroColor: '#B91C1C' },
  london: { id: 'london', label: 'London', icon: 'rainy-outline', heroTitle: 'Today in London', heroSub: 'Timeless & ever-changing', heroColor: '#1E3A5F' },
  la: { id: 'la', label: 'LA', icon: 'film-outline', heroTitle: 'Today in LA', heroSub: 'Where dreams meet reality', heroColor: '#9A3412' },
  paris: { id: 'paris', label: 'Paris', icon: 'wine-outline', heroTitle: 'Today in Paris', heroSub: 'The city of light', heroColor: '#1E3A5F' },
};

const CITY_LIST = ['near', 'global', 'nyc', 'miami', 'tokyo', 'london', 'la', 'paris'];

export default function HomeScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();

  const [activeCity, setActiveCity] = useState('nyc');
  const [statuses, setStatuses] = useState<any[]>([]);
  const [feedPosts, setFeedPosts] = useState<any[]>([]);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [detectedCity, setDetectedCity] = useState<string | null>(null);

  const city = CITIES[activeCity] || CITIES.nyc;

  useEffect(() => { detectLocation(); loadData(); }, []);

  const detectLocation = async () => {
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status === 'granted') {
        const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Low });
        const geo = await Location.reverseGeocodeAsync({ latitude: loc.coords.latitude, longitude: loc.coords.longitude });
        if (geo[0]?.city) {
          const c = geo[0].city.toLowerCase();
          if (c.includes('new york') || c.includes('brooklyn') || c.includes('manhattan')) { setDetectedCity('nyc'); setActiveCity('nyc'); }
          else if (c.includes('miami')) { setDetectedCity('miami'); setActiveCity('miami'); }
          else if (c.includes('tokyo')) { setDetectedCity('tokyo'); setActiveCity('tokyo'); }
          else if (c.includes('london')) { setDetectedCity('london'); setActiveCity('london'); }
          else if (c.includes('los angeles')) { setDetectedCity('la'); setActiveCity('la'); }
          else if (c.includes('paris')) { setDetectedCity('paris'); setActiveCity('paris'); }
          else { setDetectedCity('near'); setActiveCity('near'); }
        }
      }
    } catch {}
  };

  const loadData = async () => {
    try {
      const [statusRes, feedRes] = await Promise.all([
        api.get('/statuses'),
        api.get('/posts/feed', { params: { limit: 20 } }),
      ]);
      setStatuses(Array.isArray(statusRes.data) ? statusRes.data : []);
      setFeedPosts(Array.isArray(feedRes.data) ? feedRes.data : []);
    } catch {}
  };

  const onRefresh = useCallback(async () => {
    setIsRefreshing(true);
    await loadData();
    setIsRefreshing(false);
  }, []);

  const greeting = () => {
    const h = new Date().getHours();
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  };

  // Get a cover image from feed posts
  const coverImage = feedPosts.find((p: any) => {
    const img = p.image || p.images?.[0];
    return img && img.startsWith('http');
  })?.image || feedPosts[0]?.images?.[0];

  return (
    <View style={s.container}>
      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {/* ── Header ── */}
        <View style={[s.header, { paddingTop: insets.top + 8 }]}>
          <View>
            <Text style={s.logo}>Flames-Up</Text>
            <Text style={s.greeting}>{greeting()}</Text>
          </View>
          <View style={s.headerRight}>
            <TouchableOpacity style={s.iconBtn} onPress={() => router.push('/create-post' as any)}>
              <Ionicons name="add" size={22} color="#1A1A1A" />
            </TouchableOpacity>
            <TouchableOpacity style={s.iconBtn} onPress={() => router.push('/notifications' as any)}>
              <Ionicons name="notifications-outline" size={20} color="#1A1A1A" />
            </TouchableOpacity>
          </View>
        </View>

        {/* ── Stories Row ── */}
        {statuses.length > 0 && (
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.stories}>
            <TouchableOpacity style={s.storyItem} onPress={() => router.push('/create-status')}>
              <View style={s.storyAddWrap}>
                {user?.profile_image ? (
                  <Image source={{ uri: user.profile_image }} style={s.storyAv} />
                ) : (
                  <View style={[s.storyAv, s.storyAvEmpty]}><Text style={s.storyInit}>{(user?.full_name || 'U')[0]}</Text></View>
                )}
                <View style={s.storyPlus}><Ionicons name="add" size={11} color="#FFF" /></View>
              </View>
              <Text style={s.storyLbl}>You</Text>
            </TouchableOpacity>
            {statuses.filter((g: any) => g.user_id !== user?.id).map((g: any) => (
              <TouchableOpacity key={g.user_id} style={s.storyItem} onPress={() => router.push(`/story-viewer?userId=${g.user_id}` as any)}>
                <View style={[s.storyRing, g.has_unviewed && s.storyRingNew]}>
                  {g.user_profile_image ? (
                    <Image source={{ uri: g.user_profile_image }} style={s.storyAv} />
                  ) : (
                    <View style={[s.storyAv, s.storyAvEmpty]}><Text style={s.storyInit}>{(g.user_full_name || 'U')[0]}</Text></View>
                  )}
                </View>
                <Text style={s.storyLbl} numberOfLines={1}>{g.user_full_name?.split(' ')[0]}</Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
        )}

        {/* ── City Selector ── */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.ctxRow}>
          {CITY_LIST.map(cid => {
            const c = CITIES[cid];
            const isActive = activeCity === cid;
            return (
              <TouchableOpacity
                key={cid}
                style={[s.ctxChip, isActive && s.ctxChipActive]}
                onPress={() => setActiveCity(cid)}
              >
                <Ionicons name={c.icon as any} size={13} color={isActive ? '#FFF' : '#999'} />
                <Text style={[s.ctxLabel, isActive && s.ctxLabelActive]}>{c.label}</Text>
                {detectedCity === cid && <View style={s.ctxDot} />}
              </TouchableOpacity>
            );
          })}
        </ScrollView>

        {/* ── City Hero Block ── */}
        <TouchableOpacity
          style={[s.heroBlock, { backgroundColor: city.heroColor }]}
          activeOpacity={0.9}
          onPress={() => router.push(`/scene/${activeCity}/all` as any)}
        >
          {coverImage ? <Image source={{ uri: coverImage }} style={s.heroImg} /> : null}
          <View style={s.heroOverlay} />
          <View style={s.heroContent}>
            <Text style={s.heroLabel}>{city.label.toUpperCase()}</Text>
            <Text style={s.heroTitle}>{city.heroTitle}</Text>
            <Text style={s.heroSub}>{city.heroSub}</Text>
          </View>
          <View style={s.heroArrow}>
            <Ionicons name="arrow-forward" size={18} color="rgba(255,255,255,0.6)" />
          </View>
        </TouchableOpacity>

        {/* ── Second Block: People Out Now ── */}
        <TouchableOpacity
          style={[s.secondBlock]}
          activeOpacity={0.88}
          onPress={() => router.push(`/scene/${activeCity}/people` as any)}
        >
          <View style={s.secondBlockInner}>
            <View style={s.secondIcon}><Ionicons name="people-outline" size={18} color="#FFF" /></View>
            <View style={{ flex: 1 }}>
              <Text style={s.secondTitle}>People Out Now</Text>
              <Text style={s.secondSub}>See what's happening in {city.label}</Text>
            </View>
            <Ionicons name="chevron-forward" size={18} color="rgba(255,255,255,0.5)" />
          </View>
        </TouchableOpacity>

        {/* ── Quick Actions ── */}
        <View style={s.quickRow}>
          <TouchableOpacity style={s.quickBtn} onPress={() => router.push('/create-post' as any)}>
            <View style={[s.quickIcon, { backgroundColor: '#F0FDF4' }]}><Ionicons name="camera-outline" size={18} color="#16A34A" /></View>
            <Text style={s.quickLabel}>Post</Text>
          </TouchableOpacity>
          <TouchableOpacity style={s.quickBtn} onPress={() => router.push('/my-spots' as any)}>
            <View style={[s.quickIcon, { backgroundColor: '#FEF3C7' }]}><Ionicons name="bookmark-outline" size={18} color="#D97706" /></View>
            <Text style={s.quickLabel}>My Spots</Text>
          </TouchableOpacity>
          <TouchableOpacity style={s.quickBtn} onPress={() => router.push('/creators' as any)}>
            <View style={[s.quickIcon, { backgroundColor: '#FFF7ED' }]}><Ionicons name="flame-outline" size={18} color="#F97316" /></View>
            <Text style={s.quickLabel}>Creators</Text>
          </TouchableOpacity>
          <TouchableOpacity style={s.quickBtn} onPress={() => router.push('/library' as any)}>
            <View style={[s.quickIcon, { backgroundColor: '#EDE9FE' }]}><Ionicons name="library-outline" size={18} color="#7C3AED" /></View>
            <Text style={s.quickLabel}>Library</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FAFAF8' },

  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 20, paddingBottom: 4 },
  logo: { fontSize: 24, fontWeight: '800', color: '#1A1A1A', fontStyle: 'italic', letterSpacing: -0.5 },
  greeting: { fontSize: 13, color: '#AAA', marginTop: 1 },
  headerRight: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  iconBtn: { width: 40, height: 40, borderRadius: 20, justifyContent: 'center', alignItems: 'center', backgroundColor: '#F5F0EB' },

  stories: { paddingHorizontal: 16, paddingVertical: 8, gap: 14 },
  storyItem: { alignItems: 'center', width: 56 },
  storyAddWrap: { position: 'relative' },
  storyAv: { width: 48, height: 48, borderRadius: 24 },
  storyAvEmpty: { backgroundColor: '#E8E4DF', justifyContent: 'center', alignItems: 'center' },
  storyInit: { fontSize: 16, fontWeight: '700', color: '#AAA' },
  storyPlus: { position: 'absolute', bottom: -1, right: -1, width: 16, height: 16, borderRadius: 8, backgroundColor: '#1A1A1A', justifyContent: 'center', alignItems: 'center', borderWidth: 2, borderColor: '#FAFAF8' },
  storyRing: { width: 52, height: 52, borderRadius: 26, borderWidth: 2, borderColor: '#E0DCD7', justifyContent: 'center', alignItems: 'center' },
  storyRingNew: { borderColor: '#1A1A1A' },
  storyLbl: { fontSize: 10, color: '#999', marginTop: 3 },

  ctxRow: { paddingHorizontal: 16, paddingVertical: 10, gap: 6 },
  ctxChip: { flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 14, paddingVertical: 8, borderRadius: 20, backgroundColor: '#FFF', borderWidth: 1, borderColor: '#E8E4DF' },
  ctxChipActive: { backgroundColor: '#1A1A1A', borderColor: '#1A1A1A' },
  ctxLabel: { fontSize: 13, fontWeight: '600', color: '#999' },
  ctxLabelActive: { color: '#FFF' },
  ctxDot: { width: 5, height: 5, borderRadius: 3, backgroundColor: '#22C55E' },

  heroBlock: { marginHorizontal: GAP, borderRadius: 24, height: SW * 0.52, overflow: 'hidden', position: 'relative', marginBottom: GAP },
  heroImg: { position: 'absolute', width: '100%', height: '100%', opacity: 0.3 },
  heroOverlay: { position: 'absolute', width: '100%', height: '100%', backgroundColor: 'rgba(0,0,0,0.15)' },
  heroContent: { position: 'absolute', bottom: 24, left: 24 },
  heroLabel: { fontSize: 11, fontWeight: '800', color: 'rgba(255,255,255,0.5)', letterSpacing: 2, marginBottom: 4 },
  heroTitle: { fontSize: 28, fontWeight: '800', color: '#FFFFFF', letterSpacing: -0.5 },
  heroSub: { fontSize: 14, color: 'rgba(255,255,255,0.65)', marginTop: 4 },
  heroArrow: { position: 'absolute', top: 20, right: 20, width: 32, height: 32, borderRadius: 16, backgroundColor: 'rgba(255,255,255,0.1)', justifyContent: 'center', alignItems: 'center' },

  // Second block - People Out Now
  secondBlock: { marginHorizontal: GAP, marginBottom: 16, borderRadius: 18, backgroundColor: '#2D2D2D', overflow: 'hidden' },
  secondBlockInner: { flexDirection: 'row', alignItems: 'center', padding: 18, gap: 14 },
  secondIcon: { width: 40, height: 40, borderRadius: 20, backgroundColor: 'rgba(255,255,255,0.15)', justifyContent: 'center', alignItems: 'center' },
  secondTitle: { fontSize: 16, fontWeight: '700', color: '#FFF' },
  secondSub: { fontSize: 12, color: 'rgba(255,255,255,0.5)', marginTop: 2 },

  quickRow: { flexDirection: 'row', justifyContent: 'space-around', paddingHorizontal: 20, paddingVertical: 16, marginHorizontal: GAP, backgroundColor: '#FFF', borderRadius: 20, borderWidth: 1, borderColor: '#E8E4DF' },
  quickBtn: { alignItems: 'center', gap: 6 },
  quickIcon: { width: 44, height: 44, borderRadius: 14, justifyContent: 'center', alignItems: 'center' },
  quickLabel: { fontSize: 11, fontWeight: '600', color: '#888' },
});
