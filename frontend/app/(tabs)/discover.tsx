import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Image,
  FlatList,
  RefreshControl,
  TextInput,
  ActivityIndicator,
  Dimensions,
  Platform,
  Animated,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, shadows } from '../../src/utils/theme';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';
import { formatDistanceToNow } from 'date-fns';

const { width: SW } = Dimensions.get('window');

const CATEGORIES = [
  { id: 'all', label: 'For You', icon: 'sparkles' },
  { id: 'news', label: 'Local News', icon: 'newspaper' },
  { id: 'events', label: 'Events', icon: 'calendar' },
  { id: 'culture', label: 'Culture', icon: 'color-palette' },
  { id: 'food', label: 'Food', icon: 'restaurant' },
  { id: 'lifestyle', label: 'Lifestyle', icon: 'heart' },
  { id: 'tech', label: 'Tech', icon: 'phone-portrait' },
  { id: 'tips', label: 'Tips', icon: 'bulb' },
  { id: 'spotlight', label: 'Spotlights', icon: 'flash' },
];

export default function DiscoverScreen() {
  const router = useRouter();
  const { user } = useAuthStore();
  const [activeCategory, setActiveCategory] = useState('all');
  const [posts, setPosts] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [publisherStatus, setPublisherStatus] = useState<any>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [showSearch, setShowSearch] = useState(false);
  const [suggestedUsers, setSuggestedUsers] = useState<any[]>([]);
  const scrollRef = useRef<ScrollView>(null);

  useEffect(() => { loadAll(); }, [activeCategory]);

  const loadAll = async () => {
    setIsLoading(true);
    try {
      const [feedRes, pubRes, suggestedRes] = await Promise.allSettled([
        api.get('/discover/feed', { params: { category: activeCategory } }),
        api.get('/publisher/status'),
        api.get('/discover/suggested-users'),
      ]);
      if (feedRes.status === 'fulfilled') setPosts(feedRes.value.data);
      if (pubRes.status === 'fulfilled') setPublisherStatus(pubRes.value.data);
      if (suggestedRes.status === 'fulfilled') setSuggestedUsers(suggestedRes.value.data);
    } catch {} finally { setIsLoading(false); }
  };

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await loadAll();
    setRefreshing(false);
  }, [activeCategory]);

  const handleLike = async (postId: string) => {
    try {
      const res = await api.post(`/discover/posts/${postId}/like`);
      setPosts(prev => prev.map(p => p.id === postId ? { ...p, likes_count: res.data.liked ? p.likes_count + 1 : p.likes_count - 1, liked: res.data.liked } : p));
    } catch {}
  };

  const timeAgo = (d: string) => {
    try { return formatDistanceToNow(new Date(d), { addSuffix: false }) + ' ago'; }
    catch { return ''; }
  };

  const getCategoryColor = (cat: string) => {
    const map: any = { news: '#3B82F6', events: '#8B5CF6', culture: '#EC4899', food: '#F59E0B', lifestyle: '#EF4444', tech: '#06B6D4', tips: '#10B981', spotlight: '#F97316' };
    return map[cat] || colors.accentPrimary;
  };

  // ─── Render Featured Card (first post, big) ─────────────────────
  const renderFeatured = (post: any) => (
    <TouchableOpacity
      key={post.id}
      style={ds.featuredCard}
      onPress={() => {}}
      activeOpacity={0.9}
    >
      {post.image ? (
        <Image source={{ uri: post.image }} style={ds.featuredImage} />
      ) : (
        <View style={[ds.featuredImage, { backgroundColor: getCategoryColor(post.category) + '15' }]}>
          <Ionicons name="newspaper-outline" size={48} color={getCategoryColor(post.category)} />
        </View>
      )}
      <View style={ds.featuredOverlay}>
        <View style={[ds.categoryBadge, { backgroundColor: getCategoryColor(post.category) }]}>
          <Text style={ds.categoryBadgeText}>{post.category?.toUpperCase()}</Text>
        </View>
        <Text style={ds.featuredTitle} numberOfLines={2}>{post.title}</Text>
        <View style={ds.featuredMeta}>
          <Text style={ds.featuredPublisher}>{post.publisher_name || post.user_full_name}</Text>
          <Text style={ds.featuredDot}>·</Text>
          <Text style={ds.featuredTime}>{timeAgo(post.created_at)}</Text>
        </View>
      </View>
    </TouchableOpacity>
  );

  // ─── Render Content Card ────────────────────────────────────────
  const renderCard = (post: any) => (
    <TouchableOpacity key={post.id} style={ds.card} activeOpacity={0.85}>
      <View style={ds.cardContent}>
        <View style={ds.cardHeader}>
          <View style={[ds.cardCatDot, { backgroundColor: getCategoryColor(post.category) }]} />
          <Text style={[ds.cardCatLabel, { color: getCategoryColor(post.category) }]}>
            {post.category?.charAt(0).toUpperCase() + post.category?.slice(1)}
          </Text>
          {post.event_date && (
            <View style={ds.eventDatePill}>
              <Ionicons name="calendar" size={11} color="#8B5CF6" />
              <Text style={ds.eventDateText}>
                {new Date(post.event_date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
              </Text>
            </View>
          )}
        </View>
        <Text style={ds.cardTitle} numberOfLines={2}>{post.title}</Text>
        <Text style={ds.cardBody} numberOfLines={2}>{post.content}</Text>
        <View style={ds.cardFooter}>
          <View style={ds.publisherRow}>
            <View style={ds.publisherAvatar}>
              {post.user_profile_image ? (
                <Image source={{ uri: post.user_profile_image }} style={{ width: '100%', height: '100%' }} />
              ) : (
                <Text style={ds.publisherInitial}>{(post.publisher_name || 'P')[0]}</Text>
              )}
            </View>
            <Text style={ds.publisherName} numberOfLines={1}>{post.publisher_name || post.user_full_name}</Text>
          </View>
          <View style={ds.cardActions}>
            <TouchableOpacity style={ds.cardAction} onPress={() => handleLike(post.id)}>
              <Ionicons name={post.liked ? 'heart' : 'heart-outline'} size={16} color={post.liked ? '#EF4444' : '#9CA3AF'} />
              {post.likes_count > 0 && <Text style={ds.cardActionCount}>{post.likes_count}</Text>}
            </TouchableOpacity>
            <TouchableOpacity style={ds.cardAction}>
              <Ionicons name="share-social-outline" size={16} color="#9CA3AF" />
            </TouchableOpacity>
            <TouchableOpacity style={ds.cardAction}>
              <Ionicons name="bookmark-outline" size={16} color="#9CA3AF" />
            </TouchableOpacity>
          </View>
        </View>
      </View>
      {post.image && <Image source={{ uri: post.image }} style={ds.cardImage} />}
    </TouchableOpacity>
  );

  // ─── Render Event Card ──────────────────────────────────────────
  const renderEventCard = (post: any) => (
    <TouchableOpacity key={post.id} style={ds.eventCard} activeOpacity={0.85}>
      {post.image && <Image source={{ uri: post.image }} style={ds.eventImage} />}
      <View style={ds.eventBody}>
        <Text style={ds.eventDate}>
          {post.event_date ? new Date(post.event_date).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : 'Upcoming'}
        </Text>
        <Text style={ds.eventTitle} numberOfLines={2}>{post.title}</Text>
        {post.event_location && (
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 4 }}>
            <Ionicons name="location" size={12} color="#6B7280" />
            <Text style={ds.eventLocation} numberOfLines={1}>{post.event_location}</Text>
          </View>
        )}
        <View style={ds.eventFooter}>
          <Text style={ds.eventPublisher}>{post.publisher_name}</Text>
          <TouchableOpacity style={ds.rsvpBtn}>
            <Text style={ds.rsvpText}>Interested</Text>
          </TouchableOpacity>
        </View>
      </View>
    </TouchableOpacity>
  );

  // ─── Render Suggested People ────────────────────────────────────
  const renderSuggested = () => (
    <View style={ds.suggestedSection}>
      <View style={ds.sectionHeader}>
        <Text style={ds.sectionTitle}>People to Follow</Text>
        <TouchableOpacity><Text style={ds.seeAll}>See all</Text></TouchableOpacity>
      </View>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 16, gap: 12 }}>
        {suggestedUsers.slice(0, 6).map((u: any) => (
          <TouchableOpacity key={u.id} style={ds.suggestedCard} onPress={() => router.push(`/user/${u.id}`)}>
            <View style={ds.suggestedAvatar}>
              {u.profile_image ? (
                <Image source={{ uri: u.profile_image }} style={{ width: '100%', height: '100%' }} />
              ) : (
                <Text style={ds.suggestedInitial}>{(u.full_name || 'U')[0].toUpperCase()}</Text>
              )}
            </View>
            <Text style={ds.suggestedName} numberOfLines={1}>{u.full_name || u.username}</Text>
            <Text style={ds.suggestedBio} numberOfLines={2}>{u.bio || 'Flames-Up member'}</Text>
            <TouchableOpacity style={ds.followBtn}>
              <Text style={ds.followText}>Follow</Text>
            </TouchableOpacity>
          </TouchableOpacity>
        ))}
      </ScrollView>
    </View>
  );

  return (
    <SafeAreaView style={ds.container} edges={['top']}>
      {/* Header */}
      <View style={ds.header}>
        <Text style={ds.headerTitle}>Discover</Text>
        <View style={ds.headerActions}>
          <TouchableOpacity style={ds.headerBtn} onPress={() => setShowSearch(!showSearch)}>
            <Ionicons name={showSearch ? 'close' : 'search'} size={20} color="#1B4332" />
          </TouchableOpacity>
          {publisherStatus?.is_publisher ? (
            <TouchableOpacity style={ds.publishBtn} onPress={() => router.push('/create-discover-post' as any)}>
              <Ionicons name="add" size={18} color="#FFF" />
              <Text style={ds.publishBtnText}>Publish</Text>
            </TouchableOpacity>
          ) : (
            <TouchableOpacity style={ds.applyBtn} onPress={() => router.push('/publisher-apply' as any)}>
              <Ionicons name="megaphone-outline" size={16} color="#2D6A4F" />
              <Text style={ds.applyBtnText}>
                {publisherStatus?.status === 'pending' ? 'Pending' : 'Become Publisher'}
              </Text>
            </TouchableOpacity>
          )}
        </View>
      </View>

      {/* Search */}
      {showSearch && (
        <View style={ds.searchBar}>
          <Ionicons name="search" size={18} color="#9CA3AF" />
          <TextInput
            style={ds.searchInput}
            placeholder="Search articles, events, topics..."
            placeholderTextColor="#9CA3AF"
            value={searchQuery}
            onChangeText={setSearchQuery}
            autoFocus
          />
        </View>
      )}

      {/* Category Chips */}
      <View style={ds.chipBar}>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 16, gap: 8 }}>
          {CATEGORIES.map((cat) => (
            <TouchableOpacity
              key={cat.id}
              style={[ds.chip, activeCategory === cat.id && ds.chipActive]}
              onPress={() => setActiveCategory(cat.id)}
            >
              <Ionicons name={cat.icon as any} size={14} color={activeCategory === cat.id ? '#FFF' : '#5C4033'} />
              <Text style={[ds.chipText, activeCategory === cat.id && ds.chipTextActive]}>{cat.label}</Text>
            </TouchableOpacity>
          ))}
        </ScrollView>
      </View>

      {/* Content Feed */}
      {isLoading ? (
        <View style={ds.loadCenter}><ActivityIndicator size="large" color="#2D6A4F" /></View>
      ) : (
        <ScrollView
          ref={scrollRef}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#2D6A4F" />}
          showsVerticalScrollIndicator={false}
          contentContainerStyle={{ paddingBottom: 80 }}
        >
          {posts.length === 0 ? (
            <View style={ds.emptyFeed}>
              {/* Show welcome + CTA when no discover content exists yet */}
              <View style={ds.welcomeCard}>
                <View style={ds.welcomeIcon}>
                  <Ionicons name="telescope-outline" size={40} color="#2D6A4F" />
                </View>
                <Text style={ds.welcomeTitle}>Welcome to Discover</Text>
                <Text style={ds.welcomeText}>
                  This is where local publishers share news, events, culture, food reviews, tips and more about your community.
                </Text>
                {!publisherStatus?.is_publisher && publisherStatus?.status !== 'pending' && (
                  <TouchableOpacity style={ds.welcomeCTA} onPress={() => router.push('/publisher-apply' as any)}>
                    <Ionicons name="megaphone" size={16} color="#FFF" />
                    <Text style={ds.welcomeCTAText}>Apply to Become a Local Publisher</Text>
                  </TouchableOpacity>
                )}
              </View>

              {/* Suggested People */}
              {suggestedUsers.length > 0 && renderSuggested()}

              {/* Content Tips */}
              <View style={ds.tipsSection}>
                <Text style={ds.sectionTitle}>What publishers share</Text>
                <View style={ds.tipsGrid}>
                  {[
                    { icon: 'newspaper', label: 'Local News', desc: 'What\'s happening nearby' },
                    { icon: 'calendar', label: 'Events', desc: 'Community gatherings' },
                    { icon: 'restaurant', label: 'Food Reviews', desc: 'Best eats in town' },
                    { icon: 'color-palette', label: 'Culture', desc: 'Art, music, traditions' },
                    { icon: 'bulb', label: 'Tips & Recs', desc: 'Hidden gems & advice' },
                    { icon: 'flash', label: 'Spotlights', desc: 'People & business stories' },
                  ].map((t, i) => (
                    <View key={i} style={ds.tipCard}>
                      <Ionicons name={t.icon as any} size={22} color="#2D6A4F" />
                      <Text style={ds.tipLabel}>{t.label}</Text>
                      <Text style={ds.tipDesc}>{t.desc}</Text>
                    </View>
                  ))}
                </View>
              </View>
            </View>
          ) : (
            <>
              {/* Featured post */}
              {posts[0] && renderFeatured(posts[0])}

              {/* Suggested People */}
              {suggestedUsers.length > 0 && renderSuggested()}

              {/* Content cards */}
              <View style={{ paddingHorizontal: 16, gap: 12 }}>
                {posts.slice(1).map((p) =>
                  p.category === 'events' ? renderEventCard(p) : renderCard(p)
                )}
              </View>
            </>
          )}
        </ScrollView>
      )}
    </SafeAreaView>
  );
}

const ds = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FAFAF8' },
  // Header
  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 16, paddingVertical: 12,
  },
  headerTitle: { fontSize: 28, fontWeight: '800', color: '#1B4332', letterSpacing: -0.8, fontStyle: 'italic' },
  headerActions: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  headerBtn: {
    width: 40, height: 40, borderRadius: 20, backgroundColor: '#E8F5E9',
    justifyContent: 'center', alignItems: 'center',
  },
  publishBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 4,
    paddingHorizontal: 14, paddingVertical: 8, borderRadius: 20, backgroundColor: '#2D6A4F',
  },
  publishBtnText: { fontSize: 13, fontWeight: '700', color: '#FFF' },
  applyBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 4,
    paddingHorizontal: 12, paddingVertical: 8, borderRadius: 20,
    backgroundColor: '#E8F5E9', borderWidth: 1, borderColor: '#A5D6A7',
  },
  applyBtnText: { fontSize: 12, fontWeight: '600', color: '#2D6A4F' },
  // Search
  searchBar: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    marginHorizontal: 16, marginBottom: 10, paddingHorizontal: 14, paddingVertical: 10,
    backgroundColor: '#F3F0EB', borderRadius: 14,
  },
  searchInput: { flex: 1, fontSize: 15, color: '#1B4332' },
  // Chips
  chipBar: { paddingVertical: 6, marginBottom: 4 },
  chip: {
    flexDirection: 'row', alignItems: 'center', gap: 5,
    paddingHorizontal: 14, paddingVertical: 8, borderRadius: 20,
    backgroundColor: '#F3F0EB', borderWidth: 1, borderColor: '#E0D5C5',
  },
  chipActive: { backgroundColor: '#2D6A4F', borderColor: '#2D6A4F' },
  chipText: { fontSize: 13, fontWeight: '600', color: '#5C4033' },
  chipTextActive: { color: '#FFF' },
  loadCenter: { flex: 1, justifyContent: 'center', alignItems: 'center', paddingTop: 60 },
  // Featured
  featuredCard: {
    marginHorizontal: 16, marginVertical: 8, borderRadius: 20, overflow: 'hidden',
    backgroundColor: '#FFF', height: 220,
  },
  featuredImage: { width: '100%', height: '100%', justifyContent: 'center', alignItems: 'center' },
  featuredOverlay: {
    position: 'absolute', bottom: 0, left: 0, right: 0, padding: 16,
    backgroundColor: 'rgba(0,0,0,0.45)',
  },
  categoryBadge: { alignSelf: 'flex-start', paddingHorizontal: 10, paddingVertical: 3, borderRadius: 8, marginBottom: 6 },
  categoryBadgeText: { fontSize: 10, fontWeight: '800', color: '#FFF', letterSpacing: 1 },
  featuredTitle: { fontSize: 18, fontWeight: '800', color: '#FFF', lineHeight: 24 },
  featuredMeta: { flexDirection: 'row', alignItems: 'center', marginTop: 6, gap: 6 },
  featuredPublisher: { fontSize: 12, fontWeight: '600', color: '#E8E8E8' },
  featuredDot: { color: '#E8E8E8' },
  featuredTime: { fontSize: 12, color: '#D4D4D4' },
  // Content Card
  card: {
    flexDirection: 'row', backgroundColor: '#FFF', borderRadius: 16, overflow: 'hidden',
    borderWidth: 1, borderColor: '#F0ECE5',
  },
  cardContent: { flex: 1, padding: 14 },
  cardImage: { width: 100, height: '100%' },
  cardHeader: { flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 6 },
  cardCatDot: { width: 8, height: 8, borderRadius: 4 },
  cardCatLabel: { fontSize: 11, fontWeight: '700', textTransform: 'uppercase', letterSpacing: 0.5 },
  eventDatePill: {
    flexDirection: 'row', alignItems: 'center', gap: 3, marginLeft: 'auto',
    paddingHorizontal: 8, paddingVertical: 2, borderRadius: 8, backgroundColor: '#EDE9FE',
  },
  eventDateText: { fontSize: 10, fontWeight: '600', color: '#7C3AED' },
  cardTitle: { fontSize: 16, fontWeight: '700', color: '#1B4332', lineHeight: 22, marginBottom: 4 },
  cardBody: { fontSize: 13, color: '#6B7280', lineHeight: 18 },
  cardFooter: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: 10 },
  publisherRow: { flexDirection: 'row', alignItems: 'center', gap: 6, flex: 1 },
  publisherAvatar: { width: 22, height: 22, borderRadius: 11, overflow: 'hidden', backgroundColor: '#E8F5E9', justifyContent: 'center', alignItems: 'center' },
  publisherInitial: { fontSize: 10, fontWeight: '700', color: '#2D6A4F' },
  publisherName: { fontSize: 12, fontWeight: '600', color: '#6B7280', flex: 1 },
  cardActions: { flexDirection: 'row', gap: 12 },
  cardAction: { flexDirection: 'row', alignItems: 'center', gap: 3 },
  cardActionCount: { fontSize: 11, color: '#9CA3AF' },
  // Event Card
  eventCard: {
    backgroundColor: '#FFF', borderRadius: 16, overflow: 'hidden',
    borderWidth: 1, borderColor: '#F0ECE5',
  },
  eventImage: { width: '100%', height: 140 },
  eventBody: { padding: 14 },
  eventDate: { fontSize: 13, fontWeight: '700', color: '#8B5CF6', marginBottom: 4 },
  eventTitle: { fontSize: 17, fontWeight: '800', color: '#1B4332', lineHeight: 22 },
  eventLocation: { fontSize: 12, color: '#6B7280' },
  eventFooter: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: 10 },
  eventPublisher: { fontSize: 12, fontWeight: '600', color: '#6B7280' },
  rsvpBtn: { paddingHorizontal: 14, paddingVertical: 6, borderRadius: 14, backgroundColor: '#EDE9FE' },
  rsvpText: { fontSize: 12, fontWeight: '700', color: '#7C3AED' },
  // Suggested
  suggestedSection: { marginVertical: 16 },
  sectionHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, marginBottom: 12 },
  sectionTitle: { fontSize: 18, fontWeight: '800', color: '#1B4332' },
  seeAll: { fontSize: 13, fontWeight: '600', color: '#2D6A4F' },
  suggestedCard: {
    width: 140, backgroundColor: '#FFF', borderRadius: 16, padding: 14, alignItems: 'center',
    borderWidth: 1, borderColor: '#F0ECE5',
  },
  suggestedAvatar: { width: 52, height: 52, borderRadius: 26, overflow: 'hidden', backgroundColor: '#E8F5E9', justifyContent: 'center', alignItems: 'center', marginBottom: 8 },
  suggestedInitial: { fontSize: 20, fontWeight: '700', color: '#2D6A4F' },
  suggestedName: { fontSize: 14, fontWeight: '700', color: '#1B4332', textAlign: 'center' },
  suggestedBio: { fontSize: 11, color: '#6B7280', textAlign: 'center', marginTop: 2, lineHeight: 15 },
  followBtn: { marginTop: 8, paddingHorizontal: 20, paddingVertical: 6, borderRadius: 14, backgroundColor: '#2D6A4F' },
  followText: { fontSize: 12, fontWeight: '700', color: '#FFF' },
  // Empty / Welcome
  emptyFeed: { paddingBottom: 40 },
  welcomeCard: {
    marginHorizontal: 16, marginVertical: 16, padding: 24, backgroundColor: '#FFF',
    borderRadius: 20, alignItems: 'center', borderWidth: 1, borderColor: '#E8F5E9',
  },
  welcomeIcon: {
    width: 72, height: 72, borderRadius: 36, backgroundColor: '#E8F5E9',
    justifyContent: 'center', alignItems: 'center', marginBottom: 16,
  },
  welcomeTitle: { fontSize: 22, fontWeight: '800', color: '#1B4332', marginBottom: 8 },
  welcomeText: { fontSize: 14, color: '#6B7280', textAlign: 'center', lineHeight: 20, paddingHorizontal: 12 },
  welcomeCTA: {
    flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 20,
    paddingHorizontal: 20, paddingVertical: 12, borderRadius: 20, backgroundColor: '#2D6A4F',
  },
  welcomeCTAText: { fontSize: 14, fontWeight: '700', color: '#FFF' },
  // Tips
  tipsSection: { paddingHorizontal: 16, marginTop: 8 },
  tipsGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10, marginTop: 12 },
  tipCard: {
    width: (SW - 42) / 2, backgroundColor: '#FFF', borderRadius: 16, padding: 16,
    borderWidth: 1, borderColor: '#F0ECE5',
  },
  tipLabel: { fontSize: 14, fontWeight: '700', color: '#1B4332', marginTop: 8 },
  tipDesc: { fontSize: 12, color: '#6B7280', marginTop: 2 },
});
