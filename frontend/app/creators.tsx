import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, ScrollView, TouchableOpacity, TextInput,
  Image, FlatList, ActivityIndicator, Dimensions, RefreshControl,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, borderRadius } from '../src/utils/theme';
import api from '../src/api/client';
import { useAuthStore } from '../src/store/authStore';

const { width: SW } = Dimensions.get('window');
const CARD_WIDTH = (SW - 48 - 12) / 2;

const TABS = ['Near Me', 'Trending', 'Categories'];

const CATEGORY_LIST = [
  { id: 'photographer', name: 'Photographer', icon: 'camera-outline', color: '#3B82F6' },
  { id: 'artist', name: 'Artist', icon: 'color-palette-outline', color: '#8B5CF6' },
  { id: 'musician', name: 'Musician', icon: 'musical-notes-outline', color: '#EC4899' },
  { id: 'model', name: 'Model', icon: 'body-outline', color: '#F59E0B' },
  { id: 'stylist', name: 'Stylist', icon: 'cut-outline', color: '#10B981' },
  { id: 'dancer', name: 'Dancer', icon: 'walk-outline', color: '#EF4444' },
  { id: 'influencer', name: 'Influencer', icon: 'star-outline', color: '#F97316' },
  { id: 'chef', name: 'Chef', icon: 'restaurant-outline', color: '#14B8A6' },
  { id: 'filmmaker', name: 'Filmmaker', icon: 'videocam-outline', color: '#6366F1' },
  { id: 'designer', name: 'Designer', icon: 'brush-outline', color: '#D946EF' },
  { id: 'writer', name: 'Writer', icon: 'pencil-outline', color: '#64748B' },
  { id: 'dj', name: 'DJ', icon: 'headset-outline', color: '#0EA5E9' },
];

const AVAILABILITY_COLORS: Record<string, string> = {
  available: '#16A34A',
  busy: '#F59E0B',
  offline: '#9CA3AF',
};

export default function CreatorsScreen() {
  const router = useRouter();
  const { user } = useAuthStore();
  const [activeTab, setActiveTab] = useState(0);
  const [creators, setCreators] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [search, setSearch] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [myCreatorStatus, setMyCreatorStatus] = useState<any>(null);

  useEffect(() => { loadCreators(); checkMyStatus(); }, [activeTab, selectedCategory]);

  const checkMyStatus = async () => {
    try {
      const res = await api.get('/creators/me');
      setMyCreatorStatus(res.data);
    } catch {}
  };

  const loadCreators = async () => {
    setLoading(true);
    try {
      const params: any = {};
      if (selectedCategory) params.category = selectedCategory;
      if (search.trim()) params.search = search.trim();
      if (activeTab === 0) params.availability = 'available';
      const res = await api.get('/creators', { params });
      setCreators(res.data?.creators || []);
    } catch {
      setCreators([]);
    } finally {
      setLoading(false);
    }
  };

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await loadCreators();
    setRefreshing(false);
  }, [activeTab, selectedCategory, search]);

  const handleSearch = () => { loadCreators(); };

  const renderCreatorCard = ({ item }: { item: any }) => (
    <TouchableOpacity
      style={s.creatorCard}
      onPress={() => router.push(`/creator/${item.id}` as any)}
      activeOpacity={0.8}
    >
      <View style={s.cardImageWrap}>
        {item.profile_image ? (
          <Image source={{ uri: item.profile_image }} style={s.cardImage} />
        ) : (
          <View style={[s.cardImage, s.cardImagePlaceholder]}>
            <Text style={s.cardImageText}>{(item.full_name || 'C')[0]}</Text>
          </View>
        )}
        <View style={[s.availabilityDot, { backgroundColor: AVAILABILITY_COLORS[item.availability_status] || '#9CA3AF' }]} />
      </View>
      <View style={s.cardInfo}>
        <View style={s.nameRow}>
          <Text style={s.cardName} numberOfLines={1}>{item.full_name}</Text>
          {item.is_verified ? <Ionicons name="checkmark-circle" size={14} color={colors.accentPrimary} /> : null}
        </View>
        <Text style={s.cardCategory}>{item.category}</Text>
        <View style={s.statsRow}>
          <Ionicons name="people-outline" size={12} color={colors.textHint} />
          <Text style={s.statText}>{item.followers_count || 0}</Text>
          <Ionicons name="grid-outline" size={12} color={colors.textHint} />
          <Text style={s.statText}>{item.posts_count || 0}</Text>
        </View>
      </View>
    </TouchableOpacity>
  );

  const renderCategoryGrid = () => (
    <View style={s.categoryGrid}>
      {CATEGORY_LIST.map((cat) => (
        <TouchableOpacity
          key={cat.id}
          style={[s.categoryCard, selectedCategory === cat.id && { borderColor: cat.color, borderWidth: 2 }]}
          onPress={() => {
            setSelectedCategory(selectedCategory === cat.id ? null : cat.id);
          }}
        >
          <View style={[s.categoryIcon, { backgroundColor: cat.color + '15' }]}>
            <Ionicons name={cat.icon as any} size={24} color={cat.color} />
          </View>
          <Text style={s.categoryName}>{cat.name}</Text>
        </TouchableOpacity>
      ))}
    </View>
  );

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      {/* Header */}
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={s.headerTitle}>Creator Hub</Text>
        {!myCreatorStatus?.is_creator ? (
          <TouchableOpacity style={s.applyBtn} onPress={() => router.push('/creator/apply' as any)}>
            <Text style={s.applyBtnText}>Apply</Text>
          </TouchableOpacity>
        ) : (
          <View style={s.badgeSmall}>
            <Ionicons name="checkmark-circle" size={14} color={colors.accentPrimary} />
            <Text style={s.badgeText}>Creator</Text>
          </View>
        )}
      </View>

      {/* Search */}
      <View style={s.searchWrap}>
        <Ionicons name="search" size={18} color={colors.textHint} />
        <TextInput
          style={s.searchInput}
          placeholder="Search creators..."
          placeholderTextColor={colors.textHint}
          value={search}
          onChangeText={setSearch}
          onSubmitEditing={handleSearch}
          returnKeyType="search"
        />
        {search.length > 0 && (
          <TouchableOpacity onPress={() => { setSearch(''); loadCreators(); }}>
            <Ionicons name="close-circle" size={18} color={colors.textHint} />
          </TouchableOpacity>
        )}
      </View>

      {/* Tabs */}
      <View style={s.tabs}>
        {TABS.map((tab, idx) => (
          <TouchableOpacity
            key={tab}
            style={[s.tab, activeTab === idx && s.tabActive]}
            onPress={() => { setActiveTab(idx); setSelectedCategory(null); }}
          >
            <Text style={[s.tabText, activeTab === idx && s.tabTextActive]}>{tab}</Text>
          </TouchableOpacity>
        ))}
      </View>

      {/* Content */}
      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={s.scrollContent}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.accentPrimary} />}
      >
        {activeTab === 2 && renderCategoryGrid()}

        {selectedCategory && (
          <View style={s.filterChip}>
            <Text style={s.filterChipText}>{CATEGORY_LIST.find(c => c.id === selectedCategory)?.name}</Text>
            <TouchableOpacity onPress={() => setSelectedCategory(null)}>
              <Ionicons name="close" size={16} color={colors.accentPrimary} />
            </TouchableOpacity>
          </View>
        )}

        {loading ? (
          <View style={s.loadingWrap}>
            <ActivityIndicator size="large" color={colors.accentPrimary} />
            <Text style={s.loadingText}>Finding creators...</Text>
          </View>
        ) : creators.length === 0 ? (
          <View style={s.emptyWrap}>
            <Ionicons name="people-outline" size={48} color={colors.textHint} />
            <Text style={s.emptyTitle}>No creators found</Text>
            <Text style={s.emptyBody}>
              {activeTab === 0 ? 'No available creators near you yet.' : 'Try a different search or category.'}
            </Text>
            {!myCreatorStatus?.is_creator && (
              <TouchableOpacity style={s.emptyCta} onPress={() => router.push('/creator/apply' as any)}>
                <Text style={s.emptyCtaText}>Become a Creator</Text>
              </TouchableOpacity>
            )}
          </View>
        ) : (
          <View style={s.gridWrap}>
            {creators.map((creator) => (
              <View key={creator.id}>{renderCreatorCard({ item: creator })}</View>
            ))}
          </View>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bgApp },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: colors.borderSubtle },
  backBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 20, fontWeight: '800', color: colors.textPrimary, fontStyle: 'italic' },
  applyBtn: { backgroundColor: colors.accentPrimary, paddingHorizontal: 16, paddingVertical: 8, borderRadius: 20 },
  applyBtnText: { fontSize: 13, fontWeight: '700', color: '#FFFFFF' },
  badgeSmall: { flexDirection: 'row', alignItems: 'center', gap: 4, backgroundColor: colors.accentPrimaryLight, paddingHorizontal: 12, paddingVertical: 6, borderRadius: 20 },
  badgeText: { fontSize: 12, fontWeight: '700', color: colors.accentPrimary },
  searchWrap: { flexDirection: 'row', alignItems: 'center', marginHorizontal: 16, marginTop: 12, backgroundColor: colors.bgCard, borderRadius: 16, paddingHorizontal: 14, paddingVertical: 10, borderWidth: 1, borderColor: colors.borderLight, gap: 8 },
  searchInput: { flex: 1, fontSize: 15, color: colors.textPrimary },
  tabs: { flexDirection: 'row', marginHorizontal: 16, marginTop: 12, gap: 8 },
  tab: { paddingHorizontal: 16, paddingVertical: 10, borderRadius: 20, backgroundColor: colors.bgCard, borderWidth: 1, borderColor: colors.borderLight },
  tabActive: { backgroundColor: colors.accentPrimary, borderColor: colors.accentPrimary },
  tabText: { fontSize: 13, fontWeight: '600', color: colors.textSecondary },
  tabTextActive: { color: '#FFFFFF' },
  scrollContent: { padding: 16, paddingBottom: 80 },
  categoryGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10, marginBottom: 16 },
  categoryCard: { width: (SW - 48 - 20) / 3, backgroundColor: colors.bgCard, borderRadius: 16, padding: 14, alignItems: 'center', borderWidth: 1, borderColor: colors.borderLight },
  categoryIcon: { width: 48, height: 48, borderRadius: 16, justifyContent: 'center', alignItems: 'center', marginBottom: 8 },
  categoryName: { fontSize: 12, fontWeight: '600', color: colors.textPrimary, textAlign: 'center' },
  filterChip: { flexDirection: 'row', alignItems: 'center', gap: 6, alignSelf: 'flex-start', backgroundColor: colors.accentPrimaryLight, paddingHorizontal: 14, paddingVertical: 8, borderRadius: 20, marginBottom: 12 },
  filterChipText: { fontSize: 13, fontWeight: '600', color: colors.accentPrimary },
  gridWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 },
  creatorCard: { width: CARD_WIDTH, backgroundColor: colors.bgCard, borderRadius: 20, overflow: 'hidden', borderWidth: 1, borderColor: colors.borderLight },
  cardImageWrap: { position: 'relative' },
  cardImage: { width: '100%', height: CARD_WIDTH * 1.1, backgroundColor: colors.bgSubtle },
  cardImagePlaceholder: { justifyContent: 'center', alignItems: 'center' },
  cardImageText: { fontSize: 32, fontWeight: '800', color: colors.textHint },
  availabilityDot: { position: 'absolute', bottom: 8, right: 8, width: 14, height: 14, borderRadius: 7, borderWidth: 2, borderColor: '#FFFFFF' },
  cardInfo: { padding: 12 },
  nameRow: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  cardName: { fontSize: 14, fontWeight: '700', color: colors.textPrimary, flex: 1 },
  cardCategory: { fontSize: 12, color: colors.accentPrimary, fontWeight: '600', marginTop: 2, textTransform: 'capitalize' },
  statsRow: { flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 6 },
  statText: { fontSize: 11, color: colors.textHint, marginRight: 6 },
  loadingWrap: { alignItems: 'center', paddingTop: 60 },
  loadingText: { fontSize: 14, color: colors.textHint, marginTop: 12 },
  emptyWrap: { alignItems: 'center', paddingTop: 60 },
  emptyTitle: { fontSize: 18, fontWeight: '700', color: colors.textPrimary, marginTop: 12 },
  emptyBody: { fontSize: 14, color: colors.textHint, marginTop: 4, textAlign: 'center', maxWidth: 280 },
  emptyCta: { backgroundColor: colors.accentPrimary, paddingHorizontal: 24, paddingVertical: 12, borderRadius: 24, marginTop: 20 },
  emptyCtaText: { fontSize: 14, fontWeight: '700', color: '#FFFFFF' },
});
