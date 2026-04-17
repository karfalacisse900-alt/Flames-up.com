import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView,
  RefreshControl, Dimensions, ActivityIndicator,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import api from '../../src/api/client';
import { useAuthStore } from '../../src/store/authStore';
import {
  EDITORIAL_STORIES, VOICES, SPOTLIGHTS,
  Story,
} from '../../src/data/editorialContent';

const { width: SW } = Dimensions.get('window');
const GAP = 12;

const CATEGORIES = [
  { id: 'all',       label: 'All',          icon: 'sparkles-outline' },
  { id: 'events',    label: 'Events',       icon: 'calendar-outline' },
  { id: 'food',      label: 'Food & Drink', icon: 'restaurant-outline' },
  { id: 'things',    label: 'Things to Do', icon: 'compass-outline' },
  { id: 'culture',   label: 'Culture',      icon: 'color-palette-outline' },
  { id: 'style',     label: 'Style',        icon: 'shirt-outline' },
  { id: 'nightlife', label: 'Nightlife',    icon: 'moon-outline' },
  { id: 'city_life', label: 'City Life',    icon: 'business-outline' },
];

// ========== COMPONENTS ==========

function HeroCard({ story, onPress }: { story: Story; onPress: () => void }) {
  return (
    <TouchableOpacity style={heroS.wrap} activeOpacity={0.92} onPress={onPress}>
      <Image source={{ uri: story.image }} style={heroS.img} />
      <View style={heroS.overlay} />
      <View style={heroS.content}>
        <View style={heroS.badge}><Text style={heroS.badgeText}>FEATURED</Text></View>
        <Text style={heroS.title}>{story.title}</Text>
        <Text style={heroS.sub}>{story.subtitle}</Text>
        <View style={heroS.meta}>
          <Text style={heroS.metaT}>{story.location}</Text>
          <View style={heroS.dot} />
          <Text style={heroS.metaT}>{story.readTime}</Text>
        </View>
      </View>
    </TouchableOpacity>
  );
}

const heroS = StyleSheet.create({
  wrap: { marginHorizontal: 16, borderRadius: 24, overflow: 'hidden', height: SW * 0.65, position: 'relative' },
  img: { width: '100%', height: '100%', position: 'absolute' },
  overlay: { position: 'absolute', bottom: 0, left: 0, right: 0, height: '70%', backgroundColor: 'rgba(0,0,0,0.55)' },
  content: { position: 'absolute', bottom: 24, left: 24, right: 24 },
  badge: { alignSelf: 'flex-start', backgroundColor: 'rgba(255,255,255,0.15)', paddingHorizontal: 10, paddingVertical: 4, borderRadius: 8, marginBottom: 12 },
  badgeText: { fontSize: 10, fontWeight: '800', color: '#FFF', letterSpacing: 1.5 },
  title: { fontSize: 24, fontWeight: '800', color: '#FFF', lineHeight: 30, letterSpacing: -0.5, marginBottom: 6 },
  sub: { fontSize: 14, color: 'rgba(255,255,255,0.7)', lineHeight: 20 },
  meta: { flexDirection: 'row', alignItems: 'center', marginTop: 10, gap: 8 },
  metaT: { fontSize: 12, color: 'rgba(255,255,255,0.5)', fontWeight: '500' },
  dot: { width: 3, height: 3, borderRadius: 2, backgroundColor: 'rgba(255,255,255,0.3)' },
});

function StoryCard({ story, onPress, large }: { story: Story; onPress: () => void; large?: boolean }) {
  const w = large ? SW - 32 : (SW - 32 - GAP) / 2;
  const imgH = large ? w * 0.55 : w * 0.75;
  return (
    <TouchableOpacity style={[scS.wrap, { width: w }]} activeOpacity={0.9} onPress={onPress}>
      <Image source={{ uri: story.image }} style={[scS.img, { height: imgH }]} />
      <View style={scS.body}>
        <Text style={scS.title} numberOfLines={2}>{story.title}</Text>
        <Text style={scS.sub} numberOfLines={large ? 2 : 1}>{story.subtitle}</Text>
        <View style={scS.metaRow}>
          {story.location ? (
            <View style={scS.locBadge}>
              <Ionicons name="location" size={10} color="#DC2626" />
              <Text style={scS.locText}>{story.location}</Text>
            </View>
          ) : null}
          <Text style={scS.read}>{story.readTime}</Text>
        </View>
      </View>
    </TouchableOpacity>
  );
}

const scS = StyleSheet.create({
  wrap: { marginBottom: GAP },
  img: { width: '100%', borderRadius: 18, backgroundColor: '#E8E4DF' },
  body: { paddingTop: 10, paddingHorizontal: 2 },
  title: { fontSize: 15, fontWeight: '700', color: '#1A1A1A', lineHeight: 20, letterSpacing: -0.2 },
  sub: { fontSize: 12, color: '#999', marginTop: 3, lineHeight: 17 },
  metaRow: { flexDirection: 'row', alignItems: 'center', marginTop: 6, gap: 8 },
  locBadge: { flexDirection: 'row', alignItems: 'center', gap: 3 },
  locText: { fontSize: 11, fontWeight: '600', color: '#888' },
  read: { fontSize: 11, color: '#BBB' },
});

function VoiceCard({ story, onPress }: { story: Story; onPress: () => void }) {
  return (
    <TouchableOpacity style={vcS.wrap} activeOpacity={0.9} onPress={onPress}>
      <Image source={{ uri: story.image }} style={vcS.img} />
      <View style={vcS.overlay} />
      <View style={vcS.content}>
        <Text style={vcS.quote}>{"\u201C"}</Text>
        <Text style={vcS.title} numberOfLines={2}>{story.title}</Text>
        <Text style={vcS.author}>{story.author}</Text>
      </View>
    </TouchableOpacity>
  );
}

const vcS = StyleSheet.create({
  wrap: { width: SW * 0.65, height: SW * 0.5, borderRadius: 20, overflow: 'hidden', position: 'relative', marginRight: GAP },
  img: { width: '100%', height: '100%', position: 'absolute' },
  overlay: { position: 'absolute', width: '100%', height: '100%', backgroundColor: 'rgba(0,0,0,0.4)' },
  content: { position: 'absolute', bottom: 20, left: 18, right: 18 },
  quote: { fontSize: 36, fontWeight: '300', color: 'rgba(255,255,255,0.3)', lineHeight: 36, marginBottom: -8 },
  title: { fontSize: 16, fontWeight: '700', color: '#FFF', lineHeight: 22 },
  author: { fontSize: 12, fontWeight: '500', color: 'rgba(255,255,255,0.6)', marginTop: 6 },
});

function SpotlightCard({ story, onPress }: { story: Story; onPress: () => void }) {
  return (
    <TouchableOpacity style={spS.wrap} activeOpacity={0.9} onPress={onPress}>
      <Image source={{ uri: story.image }} style={spS.img} />
      <View style={spS.body}>
        <View style={spS.badge}>
          <Ionicons name="flash" size={10} color="#F97316" />
          <Text style={spS.badgeTxt}>SPOTLIGHT</Text>
        </View>
        <Text style={spS.title} numberOfLines={2}>{story.title}</Text>
        <Text style={spS.sub} numberOfLines={1}>{story.subtitle}</Text>
        <View style={spS.metaRow}>
          <Ionicons name="location" size={10} color="#DC2626" />
          <Text style={spS.metaTxt}>{story.location}</Text>
        </View>
      </View>
    </TouchableOpacity>
  );
}

const spS = StyleSheet.create({
  wrap: { flexDirection: 'row', backgroundColor: '#FFF', borderRadius: 18, overflow: 'hidden', marginBottom: 10, borderWidth: 1, borderColor: '#F0EDE7' },
  img: { width: 110, height: 110 },
  body: { flex: 1, padding: 14, justifyContent: 'center' },
  badge: { flexDirection: 'row', alignItems: 'center', gap: 4, marginBottom: 6 },
  badgeTxt: { fontSize: 9, fontWeight: '800', color: '#F97316', letterSpacing: 1 },
  title: { fontSize: 14, fontWeight: '700', color: '#1A1A1A', lineHeight: 19 },
  sub: { fontSize: 12, color: '#999', marginTop: 2 },
  metaRow: { flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 6 },
  metaTxt: { fontSize: 11, color: '#BBB', fontWeight: '500' },
});

// ========== MAIN SCREEN ==========
export default function DiscoverScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();

  const [activeCategory, setActiveCategory] = useState('all');
  const [feedPosts, setFeedPosts] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  useEffect(() => { loadFeedPosts(); }, []);

  const loadFeedPosts = async () => {
    try {
      setIsLoading(true);
      const res = await api.get('/posts/feed', { params: { limit: 30 } });
      setFeedPosts(Array.isArray(res.data) ? res.data : []);
    } catch {} finally { setIsLoading(false); }
  };

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await loadFeedPosts();
    setRefreshing(false);
  }, []);

  const openStory = (story: Story) => {
    router.push({ pathname: '/discover/story/[id]', params: { id: story.id } } as any);
  };

  const filteredStories = activeCategory === 'all'
    ? EDITORIAL_STORIES.filter(s => !s.featured)
    : EDITORIAL_STORIES.filter(s => s.category === activeCategory && !s.featured);

  const featuredStory = EDITORIAL_STORIES.find(s => s.featured) || EDITORIAL_STORIES[0];

  const filteredVoices = activeCategory === 'all'
    ? VOICES
    : VOICES.filter(v => v.category === activeCategory);

  const filteredSpotlights = activeCategory === 'all'
    ? SPOTLIGHTS
    : SPOTLIGHTS.filter(s => s.category === activeCategory);

  return (
    <View style={s.container}>
      {/* Header */}
      <View style={[s.header, { paddingTop: insets.top + 4 }]}>
        <Text style={s.headerTitle}>Discover</Text>
        <TouchableOpacity style={s.searchBtn}>
          <Ionicons name="search-outline" size={20} color="#1A1A1A" />
        </TouchableOpacity>
      </View>

      {/* Category Tabs */}
      <View style={s.tabBar}>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.tabContent}>
          {CATEGORIES.map(cat => {
            const active = activeCategory === cat.id;
            return (
              <TouchableOpacity
                key={cat.id}
                style={[s.tab, active && s.tabActive]}
                onPress={() => setActiveCategory(cat.id)}
              >
                <Text style={[s.tabText, active && s.tabTextActive]}>{cat.label}</Text>
              </TouchableOpacity>
            );
          })}
        </ScrollView>
      </View>

      {/* Main Content */}
      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {/* Hero Feature */}
        <View style={{ marginTop: 8 }}>
          <HeroCard story={featuredStory} onPress={() => openStory(featuredStory)} />
        </View>

        {/* Stories */}
        <View style={s.sectionHeader}>
          <Text style={s.sectionTitle}>Stories</Text>
        </View>
        <View style={s.storyGrid}>
          {filteredStories.length > 0 ? (
            <>
              <StoryCard story={filteredStories[0]} large onPress={() => openStory(filteredStories[0])} />
              <View style={s.twoCol}>
                {filteredStories.slice(1).map(story => (
                  <StoryCard key={story.id} story={story} onPress={() => openStory(story)} />
                ))}
              </View>
            </>
          ) : (
            <View style={s.emptySection}>
              <Text style={s.emptyText}>No stories in this category yet</Text>
            </View>
          )}
        </View>

        {/* Voices */}
        {filteredVoices.length > 0 && (
          <>
            <View style={s.sectionHeader}>
              <Text style={s.sectionTitle}>Voices</Text>
              <Text style={s.sectionSub}>Personal perspectives from the community</Text>
            </View>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 16 }}>
              {filteredVoices.map(voice => (
                <VoiceCard key={voice.id} story={voice} onPress={() => openStory(voice)} />
              ))}
            </ScrollView>
          </>
        )}

        {/* Spotlight */}
        {filteredSpotlights.length > 0 && (
          <>
            <View style={[s.sectionHeader, { marginTop: 28 }]}>
              <Text style={s.sectionTitle}>Spotlight</Text>
              <Text style={s.sectionSub}>Local gems worth knowing about</Text>
            </View>
            <View style={{ paddingHorizontal: 16 }}>
              {filteredSpotlights.map(spot => (
                <SpotlightCard key={spot.id} story={spot} onPress={() => openStory(spot)} />
              ))}
            </View>
          </>
        )}

        {/* Community feed posts */}
        {feedPosts.length > 0 && (
          <>
            <View style={[s.sectionHeader, { marginTop: 28 }]}>
              <Text style={s.sectionTitle}>From the Community</Text>
              <Text style={s.sectionSub}>Recent posts from Flames-Up members</Text>
            </View>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 16, gap: GAP }}>
              {feedPosts
                .filter((p: any) => { const img = p.image || p.images?.[0]; return img && (img.startsWith('http') || img.startsWith('data:')); })
                .slice(0, 8)
                .map((post: any) => (
                  <TouchableOpacity key={post.id} style={s.feedCard} activeOpacity={0.9} onPress={() => router.push(`/post/${post.id}` as any)}>
                    <Image source={{ uri: post.image || post.images?.[0] }} style={s.feedImg} />
                    <View style={s.feedOverlay} />
                    <View style={s.feedContent}>
                      <Text style={s.feedAuthor} numberOfLines={1}>{post.user_full_name}</Text>
                      <Text style={s.feedCaption} numberOfLines={2}>{post.content}</Text>
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
  container: { flex: 1, backgroundColor: '#FAFAF8' },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 20, paddingBottom: 4 },
  headerTitle: { fontSize: 26, fontWeight: '800', color: '#1A1A1A', letterSpacing: -0.5 },
  searchBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#F5F0EB', justifyContent: 'center', alignItems: 'center' },
  tabBar: { borderBottomWidth: 1, borderBottomColor: '#F0EDE7' },
  tabContent: { paddingHorizontal: 16, paddingVertical: 10, gap: 6 },
  tab: { paddingHorizontal: 16, paddingVertical: 8, borderRadius: 20 },
  tabActive: { backgroundColor: '#1A1A1A' },
  tabText: { fontSize: 14, fontWeight: '600', color: '#999' },
  tabTextActive: { color: '#FFF' },
  sectionHeader: { paddingHorizontal: 20, marginTop: 28, marginBottom: 14 },
  sectionTitle: { fontSize: 20, fontWeight: '800', color: '#1A1A1A', letterSpacing: -0.3 },
  sectionSub: { fontSize: 13, color: '#AAA', marginTop: 2 },
  storyGrid: { paddingHorizontal: 16 },
  twoCol: { flexDirection: 'row', flexWrap: 'wrap', gap: GAP },
  emptySection: { paddingVertical: 40, alignItems: 'center' },
  emptyText: { fontSize: 14, color: '#BBB' },
  feedCard: { width: SW * 0.42, height: SW * 0.56, borderRadius: 18, overflow: 'hidden', position: 'relative', backgroundColor: '#E8E4DF' },
  feedImg: { width: '100%', height: '100%', position: 'absolute' },
  feedOverlay: { position: 'absolute', width: '100%', height: '100%', backgroundColor: 'rgba(0,0,0,0.3)' },
  feedContent: { position: 'absolute', bottom: 14, left: 14, right: 14 },
  feedAuthor: { fontSize: 12, fontWeight: '700', color: '#FFF', marginBottom: 3 },
  feedCaption: { fontSize: 12, color: 'rgba(255,255,255,0.75)', lineHeight: 16 },
});
