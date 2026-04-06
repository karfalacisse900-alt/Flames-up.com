import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView,
  RefreshControl, Dimensions, ActivityIndicator,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import api from '../src/api/client';

const { width: SW } = Dimensions.get('window');

const TONIGHT_CATEGORIES = [
  { id: 'all', label: 'Everything', icon: 'sparkles-outline' },
  { id: 'bars', label: 'Bars', icon: 'wine-outline' },
  { id: 'clubs', label: 'Clubs', icon: 'musical-notes-outline' },
  { id: 'dining', label: 'Late Dining', icon: 'restaurant-outline' },
  { id: 'events', label: 'Events', icon: 'calendar-outline' },
  { id: 'live', label: 'Live Music', icon: 'mic-outline' },
];

// Curated tonight content
const TONIGHT_PICKS = [
  {
    id: 't-1', title: 'Best rooftop bars open tonight',
    subtitle: 'Skyline views and craft cocktails',
    image: 'https://images.unsplash.com/photo-1470337458703-46ad1756a187?w=800&q=80',
    location: 'NYC', category: 'bars', vibe: 'Upscale chill',
  },
  {
    id: 't-2', title: 'Underground jazz in the Village',
    subtitle: 'Live sets starting at 10PM',
    image: 'https://images.unsplash.com/photo-1415201364774-f6f0bb35f28f?w=800&q=80',
    location: 'NYC', category: 'live', vibe: 'Intimate',
  },
  {
    id: 't-3', title: 'Late night ramen crawl',
    subtitle: 'The best bowls served after midnight',
    image: 'https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=800&q=80',
    location: 'NYC', category: 'dining', vibe: 'Cozy',
  },
  {
    id: 't-4', title: 'Warehouse party in Bushwick',
    subtitle: 'House music until sunrise',
    image: 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=800&q=80',
    location: 'NYC', category: 'clubs', vibe: 'High energy',
  },
  {
    id: 't-5', title: 'Comedy night at the Cellar',
    subtitle: 'Open mic starts at 9PM — surprise headliners',
    image: 'https://images.unsplash.com/photo-1585699324551-f6c309eedeca?w=800&q=80',
    location: 'NYC', category: 'events', vibe: 'Fun',
  },
  {
    id: 't-6', title: 'Speakeasy cocktail tour',
    subtitle: 'Hidden doors and prohibition-era drinks',
    image: 'https://images.unsplash.com/photo-1551024709-8f23befc6f87?w=800&q=80',
    location: 'NYC', category: 'bars', vibe: 'Mysterious',
  },
];

export default function TonightScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const [activeCat, setActiveCat] = useState('all');
  const [feedPosts, setFeedPosts] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  useEffect(() => { loadNightPosts(); }, []);

  const loadNightPosts = async () => {
    try {
      setIsLoading(true);
      const res = await api.get('/posts/feed', { params: { limit: 20 } });
      const all = Array.isArray(res.data) ? res.data : [];
      // Filter for nightlife-related posts
      const nightKeywords = ['night', 'bar', 'club', 'party', 'drinks', 'cocktail', 'dj', 'dance', 'rooftop', 'live', 'music', 'concert'];
      const nightPosts = all.filter((p: any) => {
        const text = ((p.content || '') + (p.location || '')).toLowerCase();
        return nightKeywords.some(k => text.includes(k));
      });
      setFeedPosts(nightPosts.length > 0 ? nightPosts : all.slice(0, 6));
    } catch {} finally { setIsLoading(false); }
  };

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await loadNightPosts();
    setRefreshing(false);
  }, []);

  const filteredPicks = activeCat === 'all'
    ? TONIGHT_PICKS
    : TONIGHT_PICKS.filter(p => p.category === activeCat);

  // Current time greeting
  const hour = new Date().getHours();
  const greeting = hour >= 18 ? 'Tonight' : hour >= 12 ? 'This Evening' : 'Later Tonight';

  return (
    <View style={s.container}>
      {/* Header */}
      <View style={[s.header, { paddingTop: insets.top + 8 }]}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={20} color="#FFF" />
        </TouchableOpacity>
        <View>
          <Text style={s.headerTitle}>{greeting}</Text>
          <Text style={s.headerSub}>What's happening after dark</Text>
        </View>
        <View style={s.liveDot}>
          <View style={s.liveDotInner} />
          <Text style={s.liveText}>LIVE</Text>
        </View>
      </View>

      {/* Category pills */}
      <View style={s.catBar}>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 16, gap: 8 }}>
          {TONIGHT_CATEGORIES.map(cat => (
            <TouchableOpacity
              key={cat.id}
              style={[s.catPill, activeCat === cat.id && s.catPillActive]}
              onPress={() => setActiveCat(cat.id)}
            >
              <Ionicons name={cat.icon as any} size={14} color={activeCat === cat.id ? '#0A0A0A' : 'rgba(255,255,255,0.5)'} />
              <Text style={[s.catText, activeCat === cat.id && s.catTextActive]}>{cat.label}</Text>
            </TouchableOpacity>
          ))}
        </ScrollView>
      </View>

      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#F97316" />}
        contentContainerStyle={{ paddingBottom: 60 }}
      >
        {/* Tonight's Picks */}
        <View style={s.sectionHeader}>
          <Text style={s.sectionTitle}>Tonight's Picks</Text>
        </View>

        {/* Hero pick */}
        {filteredPicks[0] && (
          <TouchableOpacity style={s.heroPick} activeOpacity={0.92}>
            <Image source={{ uri: filteredPicks[0].image }} style={s.heroImage} />
            <View style={s.heroOverlay} />
            <View style={s.heroContent}>
              <View style={s.vibeBadge}>
                <Ionicons name="sparkles" size={10} color="#F97316" />
                <Text style={s.vibeText}>{filteredPicks[0].vibe}</Text>
              </View>
              <Text style={s.heroTitle}>{filteredPicks[0].title}</Text>
              <Text style={s.heroSub}>{filteredPicks[0].subtitle}</Text>
            </View>
          </TouchableOpacity>
        )}

        {/* Grid picks */}
        <View style={s.picksGrid}>
          {filteredPicks.slice(1).map(pick => (
            <TouchableOpacity key={pick.id} style={s.pickCard} activeOpacity={0.9}>
              <Image source={{ uri: pick.image }} style={s.pickImage} />
              <View style={s.pickOverlay} />
              <View style={s.pickContent}>
                <Text style={s.pickVibe}>{pick.vibe}</Text>
                <Text style={s.pickTitle} numberOfLines={2}>{pick.title}</Text>
                <Text style={s.pickSub} numberOfLines={1}>{pick.subtitle}</Text>
              </View>
            </TouchableOpacity>
          ))}
        </View>

        {/* Active now from feed */}
        {feedPosts.length > 0 && (
          <>
            <View style={[s.sectionHeader, { marginTop: 28 }]}>
              <Text style={s.sectionTitle}>Active Now</Text>
              <Text style={s.sectionSub}>People out tonight</Text>
            </View>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 16, gap: 10 }}>
              {feedPosts.filter((p: any) => p.image || p.images?.[0]).slice(0, 8).map((post: any) => (
                <TouchableOpacity
                  key={post.id}
                  style={s.activeCard}
                  activeOpacity={0.9}
                  onPress={() => router.push(`/post/${post.id}` as any)}
                >
                  <Image source={{ uri: post.image || post.images?.[0] }} style={s.activeImage} />
                  <View style={s.activeOverlay} />
                  <View style={s.activeContent}>
                    <Text style={s.activeName} numberOfLines={1}>{post.user_full_name}</Text>
                    <Text style={s.activeCaption} numberOfLines={1}>{post.content}</Text>
                  </View>
                </TouchableOpacity>
              ))}
            </ScrollView>
          </>
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0A0A0A' },

  // Header
  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 20, paddingBottom: 12,
  },
  backBtn: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.08)', justifyContent: 'center', alignItems: 'center',
  },
  headerTitle: { fontSize: 24, fontWeight: '800', color: '#FFF', letterSpacing: -0.5 },
  headerSub: { fontSize: 13, color: 'rgba(255,255,255,0.4)', marginTop: 2 },
  liveDot: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  liveDotInner: { width: 8, height: 8, borderRadius: 4, backgroundColor: '#22C55E' },
  liveText: { fontSize: 10, fontWeight: '800', color: '#22C55E', letterSpacing: 1 },

  // Category
  catBar: { paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.06)' },
  catPill: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    paddingHorizontal: 14, paddingVertical: 8, borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.06)',
  },
  catPillActive: { backgroundColor: '#F97316' },
  catText: { fontSize: 13, fontWeight: '600', color: 'rgba(255,255,255,0.5)' },
  catTextActive: { color: '#0A0A0A' },

  // Section
  sectionHeader: { paddingHorizontal: 20, paddingTop: 24, paddingBottom: 12 },
  sectionTitle: { fontSize: 20, fontWeight: '800', color: '#FFF', letterSpacing: -0.3 },
  sectionSub: { fontSize: 13, color: 'rgba(255,255,255,0.35)', marginTop: 2 },

  // Hero pick
  heroPick: {
    marginHorizontal: 16, height: SW * 0.55, borderRadius: 22,
    overflow: 'hidden', position: 'relative',
  },
  heroImage: { width: '100%', height: '100%', position: 'absolute' },
  heroOverlay: { position: 'absolute', width: '100%', height: '100%', backgroundColor: 'rgba(0,0,0,0.4)' },
  heroContent: { position: 'absolute', bottom: 20, left: 20, right: 20 },
  vibeBadge: {
    flexDirection: 'row', alignItems: 'center', gap: 5,
    backgroundColor: 'rgba(0,0,0,0.4)', paddingHorizontal: 10, paddingVertical: 4,
    borderRadius: 8, alignSelf: 'flex-start', marginBottom: 10,
  },
  vibeText: { fontSize: 11, fontWeight: '700', color: '#F97316' },
  heroTitle: { fontSize: 22, fontWeight: '800', color: '#FFF', lineHeight: 28, marginBottom: 4 },
  heroSub: { fontSize: 13, color: 'rgba(255,255,255,0.6)' },

  // Picks grid
  picksGrid: {
    flexDirection: 'row', flexWrap: 'wrap', gap: 10,
    paddingHorizontal: 16, paddingTop: 10,
  },
  pickCard: {
    width: (SW - 42) / 2, height: (SW - 42) / 2 * 1.2,
    borderRadius: 18, overflow: 'hidden', position: 'relative',
  },
  pickImage: { width: '100%', height: '100%', position: 'absolute' },
  pickOverlay: { position: 'absolute', width: '100%', height: '100%', backgroundColor: 'rgba(0,0,0,0.35)' },
  pickContent: { position: 'absolute', bottom: 14, left: 14, right: 14 },
  pickVibe: { fontSize: 10, fontWeight: '700', color: '#F97316', marginBottom: 4 },
  pickTitle: { fontSize: 14, fontWeight: '700', color: '#FFF', lineHeight: 18 },
  pickSub: { fontSize: 11, color: 'rgba(255,255,255,0.5)', marginTop: 3 },

  // Active now
  activeCard: {
    width: SW * 0.38, height: SW * 0.5, borderRadius: 16,
    overflow: 'hidden', position: 'relative',
  },
  activeImage: { width: '100%', height: '100%', position: 'absolute' },
  activeOverlay: { position: 'absolute', width: '100%', height: '100%', backgroundColor: 'rgba(0,0,0,0.3)' },
  activeContent: { position: 'absolute', bottom: 12, left: 12, right: 12 },
  activeName: { fontSize: 12, fontWeight: '700', color: '#FFF' },
  activeCaption: { fontSize: 11, color: 'rgba(255,255,255,0.6)', marginTop: 2 },
});
