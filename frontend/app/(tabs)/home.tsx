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
const HALF = (SW - GAP * 3) / 2;

// ═══════════════════════════════════════════════════════════════
// CONTEXT CONFIGURATION — Blocks per city/context
// ═══════════════════════════════════════════════════════════════
type BlockDef = {
  id: string; title: string; subtitle: string;
  gradient: string[]; icon: string; hero?: boolean;
};

type ContextConfig = {
  id: string; label: string; icon: string;
  heroTitle: string; heroSub: string; heroColor: string;
  blocks: BlockDef[];
};

const CONTEXTS: Record<string, ContextConfig> = {
  near: {
    id: 'near', label: 'Near You', icon: 'location',
    heroTitle: 'Around You', heroSub: 'Discover what\'s nearby',
    heroColor: '#1B4332',
    blocks: [
      { id: 'open-now', title: 'Open Now', subtitle: 'Active spots near you', gradient: ['#0F766E', '#134E4A'], icon: 'time-outline' },
      { id: 'nearby-spots', title: 'Nearby Spots', subtitle: 'Places to check out', gradient: ['#1E40AF', '#1E3A5F'], icon: 'navigate-outline' },
      { id: 'active', title: 'People Out Now', subtitle: 'Recent check-ins', gradient: ['#9333EA', '#581C87'], icon: 'people-outline' },
      { id: 'food', title: 'Food Near You', subtitle: 'Eat something good', gradient: ['#DC2626', '#7F1D1D'], icon: 'restaurant-outline' },
      { id: 'hidden', title: 'Hidden Gems', subtitle: 'Off the beaten path', gradient: ['#CA8A04', '#713F12'], icon: 'diamond-outline' },
    ],
  },
  global: {
    id: 'global', label: 'Global', icon: 'globe-outline',
    heroTitle: 'World Scenes', heroSub: 'Culture from everywhere',
    heroColor: '#0C2340',
    blocks: [
      { id: 'culture', title: 'Culture', subtitle: 'Art & heritage worldwide', gradient: ['#7C3AED', '#4C1D95'], icon: 'color-palette-outline' },
      { id: 'fashion', title: 'Fashion', subtitle: 'Street style around the globe', gradient: ['#DB2777', '#831843'], icon: 'shirt-outline' },
      { id: 'travel', title: 'Travel', subtitle: 'Beautiful destinations', gradient: ['#0891B2', '#164E63'], icon: 'airplane-outline' },
      { id: 'food', title: 'Food', subtitle: 'Cuisines from every corner', gradient: ['#EA580C', '#7C2D12'], icon: 'restaurant-outline' },
      { id: 'nightlife', title: 'Nightlife', subtitle: 'After dark, worldwide', gradient: ['#4338CA', '#1E1B4B'], icon: 'moon-outline' },
    ],
  },
  nyc: {
    id: 'nyc', label: 'NYC', icon: 'business-outline',
    heroTitle: 'Today in NYC', heroSub: 'The city that never sleeps',
    heroColor: '#1A1A1A',
    blocks: [
      { id: 'nightlife', title: 'Nightlife', subtitle: 'Brooklyn bars to Manhattan clubs', gradient: ['#581C87', '#3B0764'], icon: 'moon-outline' },
      { id: 'food', title: 'Street Food', subtitle: 'Halal carts to pizza slices', gradient: ['#DC2626', '#7F1D1D'], icon: 'restaurant-outline' },
      { id: 'places', title: 'Places to Go', subtitle: 'Spots locals love', gradient: ['#0D9488', '#134E4A'], icon: 'location-outline' },
      { id: 'street', title: 'Street Culture', subtitle: 'Art, music & vibes', gradient: ['#D97706', '#78350F'], icon: 'musical-notes-outline' },
      { id: 'hidden', title: 'Hidden Gems', subtitle: 'Secret spots in the 5 boroughs', gradient: ['#4338CA', '#1E1B4B'], icon: 'diamond-outline' },
    ],
  },
  miami: {
    id: 'miami', label: 'Miami', icon: 'sunny-outline',
    heroTitle: 'Today in Miami', heroSub: 'Sun, culture & vibes',
    heroColor: '#0E7490',
    blocks: [
      { id: 'beach', title: 'Beach Life', subtitle: 'South Beach to Key Biscayne', gradient: ['#0891B2', '#164E63'], icon: 'water-outline' },
      { id: 'nightlife', title: 'Nightlife', subtitle: 'Wynwood to Downtown', gradient: ['#7C3AED', '#4C1D95'], icon: 'moon-outline' },
      { id: 'food', title: 'Latin Flavors', subtitle: 'Cuban coffee to ceviche', gradient: ['#EA580C', '#7C2D12'], icon: 'restaurant-outline' },
      { id: 'art', title: 'Art & Culture', subtitle: 'Murals, galleries & more', gradient: ['#DB2777', '#831843'], icon: 'color-palette-outline' },
      { id: 'places', title: 'Must Visit', subtitle: 'Spots you can\'t miss', gradient: ['#16A34A', '#14532D'], icon: 'star-outline' },
    ],
  },
  tokyo: {
    id: 'tokyo', label: 'Tokyo', icon: 'train-outline',
    heroTitle: 'Today in Tokyo', heroSub: 'Tradition meets future',
    heroColor: '#B91C1C',
    blocks: [
      { id: 'culture', title: 'Anime Culture', subtitle: 'Akihabara & beyond', gradient: ['#DC2626', '#7F1D1D'], icon: 'sparkles-outline' },
      { id: 'food', title: 'Street Food', subtitle: 'Ramen to takoyaki', gradient: ['#EA580C', '#7C2D12'], icon: 'restaurant-outline' },
      { id: 'fashion', title: 'Fashion Districts', subtitle: 'Harajuku to Shibuya', gradient: ['#DB2777', '#831843'], icon: 'shirt-outline' },
      { id: 'cafes', title: 'Cafés', subtitle: 'Kissaten to cat cafés', gradient: ['#92400E', '#78350F'], icon: 'cafe-outline' },
      { id: 'hidden', title: 'Hidden Tokyo', subtitle: 'Backstreets & secrets', gradient: ['#4338CA', '#1E1B4B'], icon: 'map-outline' },
    ],
  },
  london: {
    id: 'london', label: 'London', icon: 'rainy-outline',
    heroTitle: 'Today in London', heroSub: 'Timeless & ever-changing',
    heroColor: '#1E3A5F',
    blocks: [
      { id: 'culture', title: 'Culture', subtitle: 'Museums to markets', gradient: ['#7C3AED', '#4C1D95'], icon: 'color-palette-outline' },
      { id: 'food', title: 'Food Scene', subtitle: 'Borough Market to brick lane', gradient: ['#DC2626', '#7F1D1D'], icon: 'restaurant-outline' },
      { id: 'nightlife', title: 'Nightlife', subtitle: 'Soho to Shoreditch', gradient: ['#581C87', '#3B0764'], icon: 'moon-outline' },
      { id: 'street', title: 'Street Style', subtitle: 'London looks', gradient: ['#0D9488', '#134E4A'], icon: 'shirt-outline' },
      { id: 'hidden', title: 'Hidden London', subtitle: 'Locals only', gradient: ['#CA8A04', '#713F12'], icon: 'diamond-outline' },
    ],
  },
  la: {
    id: 'la', label: 'LA', icon: 'film-outline',
    heroTitle: 'Today in LA', heroSub: 'Where dreams meet reality',
    heroColor: '#9A3412',
    blocks: [
      { id: 'food', title: 'Food Trucks', subtitle: 'Tacos to fusion', gradient: ['#EA580C', '#7C2D12'], icon: 'restaurant-outline' },
      { id: 'nightlife', title: 'Nightlife', subtitle: 'Hollywood to DTLA', gradient: ['#581C87', '#3B0764'], icon: 'moon-outline' },
      { id: 'beach', title: 'Beach Vibes', subtitle: 'Venice to Malibu', gradient: ['#0891B2', '#164E63'], icon: 'water-outline' },
      { id: 'culture', title: 'Art & Culture', subtitle: 'LACMA to street art', gradient: ['#7C3AED', '#4C1D95'], icon: 'color-palette-outline' },
      { id: 'hidden', title: 'Hidden LA', subtitle: 'Secret spots', gradient: ['#CA8A04', '#713F12'], icon: 'diamond-outline' },
    ],
  },
  paris: {
    id: 'paris', label: 'Paris', icon: 'wine-outline',
    heroTitle: 'Today in Paris', heroSub: 'The city of light',
    heroColor: '#1E3A5F',
    blocks: [
      { id: 'cafes', title: 'Cafés', subtitle: 'Espresso & croissants', gradient: ['#92400E', '#78350F'], icon: 'cafe-outline' },
      { id: 'fashion', title: 'Fashion', subtitle: 'Le Marais to Saint-Germain', gradient: ['#DB2777', '#831843'], icon: 'shirt-outline' },
      { id: 'culture', title: 'Art & Culture', subtitle: 'Beyond the Louvre', gradient: ['#7C3AED', '#4C1D95'], icon: 'color-palette-outline' },
      { id: 'food', title: 'Cuisine', subtitle: 'Bistros to boulangeries', gradient: ['#DC2626', '#7F1D1D'], icon: 'restaurant-outline' },
      { id: 'nightlife', title: 'Nightlife', subtitle: 'Pigalle to Oberkampf', gradient: ['#4338CA', '#1E1B4B'], icon: 'moon-outline' },
    ],
  },
};

const CONTEXT_LIST = ['near', 'global', 'nyc', 'miami', 'tokyo', 'london', 'la', 'paris'];

// ═══════════════════════════════════════════════════════════════
// THEME BLOCK COMPONENT
// ═══════════════════════════════════════════════════════════════
function ThemeBlock({ block, context, coverImage, onPress, wide }: {
  block: BlockDef; context: string; coverImage?: string; onPress: () => void; wide?: boolean;
}) {
  const w = wide ? SW - GAP * 2 : HALF;
  const h = wide ? SW * 0.5 : HALF * 1.15;

  return (
    <TouchableOpacity
      style={[tb.container, { width: w, height: h, backgroundColor: block.gradient[0] }]}
      activeOpacity={0.88}
      onPress={onPress}
    >
      {coverImage ? (
        <Image source={{ uri: coverImage }} style={tb.coverImg} />
      ) : null}
      <View style={tb.overlay} />
      <View style={tb.content}>
        <View style={tb.iconWrap}>
          <Ionicons name={block.icon as any} size={16} color="rgba(255,255,255,0.9)" />
        </View>
        <Text style={tb.title}>{block.title}</Text>
        <Text style={tb.subtitle}>{block.subtitle}</Text>
      </View>
      <View style={tb.arrow}>
        <Ionicons name="arrow-forward" size={14} color="rgba(255,255,255,0.5)" />
      </View>
    </TouchableOpacity>
  );
}

const tb = StyleSheet.create({
  container: { borderRadius: 20, overflow: 'hidden', position: 'relative', marginBottom: GAP },
  coverImg: { position: 'absolute', width: '100%', height: '100%', opacity: 0.35 },
  overlay: { position: 'absolute', width: '100%', height: '100%', backgroundColor: 'rgba(0,0,0,0.2)' },
  content: { position: 'absolute', bottom: 16, left: 16, right: 16 },
  iconWrap: { width: 28, height: 28, borderRadius: 14, backgroundColor: 'rgba(255,255,255,0.15)', justifyContent: 'center', alignItems: 'center', marginBottom: 8 },
  title: { fontSize: 18, fontWeight: '800', color: '#FFFFFF', letterSpacing: -0.3 },
  subtitle: { fontSize: 12, color: 'rgba(255,255,255,0.65)', marginTop: 2, fontWeight: '400' },
  arrow: { position: 'absolute', top: 14, right: 14 },
});


// ═══════════════════════════════════════════════════════════════
// HOME SCREEN
// ═══════════════════════════════════════════════════════════════
export default function HomeScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();

  const [activeContext, setActiveContext] = useState('nyc');
  const [statuses, setStatuses] = useState<any[]>([]);
  const [blockImages, setBlockImages] = useState<Record<string, string>>({});
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [detectedCity, setDetectedCity] = useState<string | null>(null);

  const ctx = CONTEXTS[activeContext] || CONTEXTS.global;

  useEffect(() => { detectLocation(); loadStatuses(); }, []);
  useEffect(() => { loadBlockImages(); }, [activeContext]);

  const detectLocation = async () => {
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status === 'granted') {
        const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Low });
        const geo = await Location.reverseGeocodeAsync({ latitude: loc.coords.latitude, longitude: loc.coords.longitude });
        if (geo[0]?.city) {
          const city = geo[0].city.toLowerCase();
          if (city.includes('new york') || city.includes('brooklyn') || city.includes('manhattan')) {
            setDetectedCity('nyc'); setActiveContext('nyc');
          } else if (city.includes('miami')) {
            setDetectedCity('miami'); setActiveContext('miami');
          } else if (city.includes('tokyo')) {
            setDetectedCity('tokyo'); setActiveContext('tokyo');
          } else if (city.includes('london')) {
            setDetectedCity('london'); setActiveContext('london');
          } else if (city.includes('los angeles')) {
            setDetectedCity('la'); setActiveContext('la');
          } else if (city.includes('paris')) {
            setDetectedCity('paris'); setActiveContext('paris');
          } else {
            setDetectedCity('near'); setActiveContext('near');
          }
        }
      }
    } catch {}
  };

  const loadStatuses = async () => {
    try {
      const res = await api.get('/statuses');
      setStatuses(Array.isArray(res.data) ? res.data : []);
    } catch {}
  };

  const loadBlockImages = async () => {
    // Try to fetch a representative image for each block from posts
    try {
      const res = await api.get('/posts/feed');
      const posts = Array.isArray(res.data) ? res.data : [];
      const imgs: Record<string, string> = {};
      const validPosts = posts.filter((p: any) => {
        const img = p.image || p.images?.[0];
        return img && !img.startsWith('file://') && (img.startsWith('http') || img.startsWith('data:'));
      });
      ctx.blocks.forEach((block, idx) => {
        if (validPosts[idx]?.image) {
          imgs[block.id] = validPosts[idx].image;
        }
      });
      setBlockImages(imgs);
    } catch {}
  };

  const onRefresh = useCallback(async () => {
    setIsRefreshing(true);
    await Promise.all([loadStatuses(), loadBlockImages()]);
    setIsRefreshing(false);
  }, [activeContext]);

  const navigateToScene = (blockId: string) => {
    router.push(`/scene/${activeContext}/${blockId}` as any);
  };

  const greeting = () => {
    const h = new Date().getHours();
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  };

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
            <TouchableOpacity style={s.storyBtn} onPress={() => router.push('/create-status')}>
              <Ionicons name="add-circle-outline" size={22} color="#1A1A1A" />
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

        {/* ── Context Selector ── */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.ctxRow}>
          {CONTEXT_LIST.map(cid => {
            const c = CONTEXTS[cid];
            const isActive = activeContext === cid;
            return (
              <TouchableOpacity
                key={cid}
                style={[s.ctxChip, isActive && s.ctxChipActive]}
                onPress={() => setActiveContext(cid)}
              >
                <Ionicons name={c.icon as any} size={13} color={isActive ? '#FFF' : '#999'} />
                <Text style={[s.ctxLabel, isActive && s.ctxLabelActive]}>{c.label}</Text>
                {detectedCity === cid && <View style={s.ctxDot} />}
              </TouchableOpacity>
            );
          })}
        </ScrollView>

        {/* ── Hero Block ── */}
        <TouchableOpacity
          style={[s.heroBlock, { backgroundColor: ctx.heroColor }]}
          activeOpacity={0.9}
          onPress={() => navigateToScene(ctx.blocks[0]?.id || 'all')}
        >
          {blockImages[ctx.blocks[0]?.id] ? (
            <Image source={{ uri: blockImages[ctx.blocks[0]?.id] }} style={s.heroImg} />
          ) : null}
          <View style={s.heroOverlay} />
          <View style={s.heroContent}>
            <Text style={s.heroLabel}>{ctx.label.toUpperCase()}</Text>
            <Text style={s.heroTitle}>{ctx.heroTitle}</Text>
            <Text style={s.heroSub}>{ctx.heroSub}</Text>
          </View>
          <View style={s.heroArrow}>
            <Ionicons name="arrow-forward" size={18} color="rgba(255,255,255,0.6)" />
          </View>
        </TouchableOpacity>

        {/* ── Theme Blocks Grid ── */}
        <View style={s.blockGrid}>
          {ctx.blocks.slice(1).map((block, idx) => {
            // First block after hero is wide, rest alternate 2-col
            const isWide = idx === 0;
            return (
              <ThemeBlock
                key={block.id}
                block={block}
                context={activeContext}
                coverImage={blockImages[block.id]}
                onPress={() => navigateToScene(block.id)}
                wide={isWide}
              />
            );
          })}
        </View>

        {/* ── Quick Actions ── */}
        <View style={s.quickRow}>
          <TouchableOpacity style={s.quickBtn} onPress={() => router.push('/drop-moment' as any)}>
            <View style={[s.quickIcon, { backgroundColor: '#FEE2E2' }]}><Ionicons name="flash-outline" size={18} color="#DC2626" /></View>
            <Text style={s.quickLabel}>Moment</Text>
          </TouchableOpacity>
          <TouchableOpacity style={s.quickBtn} onPress={() => router.push('/my-spots' as any)}>
            <View style={[s.quickIcon, { backgroundColor: '#FEF3C7' }]}><Ionicons name="bookmark-outline" size={18} color="#D97706" /></View>
            <Text style={s.quickLabel}>My Spots</Text>
          </TouchableOpacity>
          <TouchableOpacity style={s.quickBtn} onPress={() => router.push('/create-post' as any)}>
            <View style={[s.quickIcon, { backgroundColor: '#F0FDF4' }]}><Ionicons name="camera-outline" size={18} color="#16A34A" /></View>
            <Text style={s.quickLabel}>Post</Text>
          </TouchableOpacity>
          <TouchableOpacity style={s.quickBtn} onPress={() => router.push('/creators' as any)}>
            <View style={[s.quickIcon, { backgroundColor: '#FFF7ED' }]}><Ionicons name="flame-outline" size={18} color="#F97316" /></View>
            <Text style={s.quickLabel}>Creators</Text>
          </TouchableOpacity>
          <TouchableOpacity style={s.quickBtn} onPress={() => router.push('/settings' as any)}>
            <View style={[s.quickIcon, { backgroundColor: '#F1F5F9' }]}><Ionicons name="settings-outline" size={18} color="#64748B" /></View>
            <Text style={s.quickLabel}>Settings</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </View>
  );
}

// ═══════════════════════════════════════════════════════════════
const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FAFAF8' },

  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 20, paddingBottom: 4 },
  logo: { fontSize: 24, fontWeight: '800', color: '#1A1A1A', fontStyle: 'italic', letterSpacing: -0.5 },
  greeting: { fontSize: 13, color: '#AAA', marginTop: 1 },
  headerRight: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  storyBtn: { width: 38, height: 38, borderRadius: 19, justifyContent: 'center', alignItems: 'center', backgroundColor: '#F5F0EB' },
  iconBtn: { width: 38, height: 38, borderRadius: 19, justifyContent: 'center', alignItems: 'center', backgroundColor: '#F5F0EB' },

  // Stories
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

  // Context selector
  ctxRow: { paddingHorizontal: 16, paddingVertical: 10, gap: 6 },
  ctxChip: { flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 14, paddingVertical: 8, borderRadius: 20, backgroundColor: '#FFF', borderWidth: 1, borderColor: '#E8E4DF' },
  ctxChipActive: { backgroundColor: '#1A1A1A', borderColor: '#1A1A1A' },
  ctxLabel: { fontSize: 13, fontWeight: '600', color: '#999' },
  ctxLabelActive: { color: '#FFF' },
  ctxDot: { width: 5, height: 5, borderRadius: 3, backgroundColor: '#22C55E' },

  // Hero
  heroBlock: { marginHorizontal: GAP, borderRadius: 24, height: SW * 0.52, overflow: 'hidden', position: 'relative', marginBottom: GAP },
  heroImg: { position: 'absolute', width: '100%', height: '100%', opacity: 0.3 },
  heroOverlay: { position: 'absolute', width: '100%', height: '100%', backgroundColor: 'rgba(0,0,0,0.15)' },
  heroContent: { position: 'absolute', bottom: 24, left: 24 },
  heroLabel: { fontSize: 11, fontWeight: '800', color: 'rgba(255,255,255,0.5)', letterSpacing: 2, marginBottom: 4 },
  heroTitle: { fontSize: 28, fontWeight: '800', color: '#FFFFFF', letterSpacing: -0.5 },
  heroSub: { fontSize: 14, color: 'rgba(255,255,255,0.65)', marginTop: 4 },
  heroArrow: { position: 'absolute', top: 20, right: 20, width: 32, height: 32, borderRadius: 16, backgroundColor: 'rgba(255,255,255,0.1)', justifyContent: 'center', alignItems: 'center' },

  // Block grid
  blockGrid: { flexDirection: 'row', flexWrap: 'wrap', paddingHorizontal: GAP, gap: GAP, marginBottom: 16 },

  // Quick actions
  quickRow: { flexDirection: 'row', justifyContent: 'space-around', paddingHorizontal: 20, paddingVertical: 16, marginHorizontal: GAP, backgroundColor: '#FFF', borderRadius: 20, borderWidth: 1, borderColor: '#E8E4DF' },
  quickBtn: { alignItems: 'center', gap: 6 },
  quickIcon: { width: 44, height: 44, borderRadius: 14, justifyContent: 'center', alignItems: 'center' },
  quickLabel: { fontSize: 11, fontWeight: '600', color: '#888' },
});
