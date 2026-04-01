import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Image,
  ScrollView,
  RefreshControl,
  ActivityIndicator,
  Dimensions,
  TextInput,
  FlatList,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, shadows } from '../../src/utils/theme';
import api from '../../src/api/client';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const GRID_GAP = 4;
const COL3_WIDTH = (SCREEN_WIDTH - GRID_GAP * 2) / 3;

const PLACE_TYPES = [
  { id: 'restaurant', label: 'Restaurants', icon: 'restaurant-outline' },
  { id: 'cafe', label: 'Cafes', icon: 'cafe-outline' },
  { id: 'bar', label: 'Bars', icon: 'wine-outline' },
  { id: 'park', label: 'Parks', icon: 'leaf-outline' },
  { id: 'museum', label: 'Museums', icon: 'business-outline' },
  { id: 'gym', label: 'Gyms', icon: 'barbell-outline' },
  { id: 'shopping_mall', label: 'Shopping', icon: 'bag-outline' },
  { id: 'night_club', label: 'Nightlife', icon: 'musical-notes-outline' },
];

function PlaceGridItem({ place, size, onPress }: { place: any; size: 'large' | 'small'; onPress: () => void }) {
  const isLarge = size === 'large';
  const w = isLarge ? COL3_WIDTH * 2 + GRID_GAP : COL3_WIDTH;
  const h = isLarge ? COL3_WIDTH * 2 + GRID_GAP : COL3_WIDTH;

  return (
    <TouchableOpacity
      style={[gridStyles.item, { width: w, height: h }]}
      onPress={onPress}
      activeOpacity={0.9}
    >
      {place.photo_url ? (
        <Image source={{ uri: place.photo_url }} style={gridStyles.image} />
      ) : (
        <View style={gridStyles.placeholder}>
          <Ionicons name="image-outline" size={32} color={colors.textHint} />
        </View>
      )}
      <View style={gridStyles.overlay} />
      <View style={gridStyles.info}>
        <Text style={gridStyles.name} numberOfLines={1}>{place.name}</Text>
        <View style={gridStyles.ratingRow}>
          <Ionicons name="star" size={11} color="#FCD34D" />
          <Text style={gridStyles.rating}>{place.rating?.toFixed(1) || '–'}</Text>
          {place.open_now !== undefined && (
            <View style={[gridStyles.statusDot, { backgroundColor: place.open_now ? '#22C55E' : '#EF4444' }]} />
          )}
        </View>
      </View>
    </TouchableOpacity>
  );
}

const gridStyles = StyleSheet.create({
  item: {
    borderRadius: 6,
    overflow: 'hidden',
    backgroundColor: colors.bgSubtle,
  },
  image: {
    width: '100%',
    height: '100%',
  },
  placeholder: {
    width: '100%',
    height: '100%',
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.bgSubtle,
  },
  overlay: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: '45%',
    backgroundColor: 'rgba(0,0,0,0.45)',
  },
  info: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    padding: 8,
  },
  name: {
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: '700',
    lineHeight: 16,
  },
  ratingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    marginTop: 2,
  },
  rating: {
    color: 'rgba(255,255,255,0.85)',
    fontSize: 11,
    fontWeight: '600',
  },
  statusDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    marginLeft: 4,
  },
});

export default function PlacesScreen() {
  const router = useRouter();
  const [places, setPlaces] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [search, setSearch] = useState('');
  const [activeType, setActiveType] = useState('restaurant');

  const loadPlaces = async (type: string, keyword?: string) => {
    try {
      const params: any = { type, lat: 40.7128, lng: -74.006, radius: 5000 };
      if (keyword) params.keyword = keyword;
      const response = await api.get('/google-places/nearby', { params });
      setPlaces(response.data);
    } catch (error) {
      console.log('Error loading places:', error);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    setIsLoading(true);
    loadPlaces(activeType);
  }, [activeType]);

  const onRefresh = useCallback(async () => {
    setIsRefreshing(true);
    await loadPlaces(activeType, search || undefined);
    setIsRefreshing(false);
  }, [activeType, search]);

  const handleSearch = () => {
    if (search.trim()) {
      setIsLoading(true);
      loadPlaces(activeType, search.trim());
    }
  };

  // Build Lemon8-style grid pattern: [large + 2 small stacked], [3 small], repeat
  const renderGrid = () => {
    const rows: React.ReactNode[] = [];
    let i = 0;
    let rowIdx = 0;

    while (i < places.length) {
      if (rowIdx % 2 === 0 && i + 2 < places.length) {
        // Pattern: 1 large (2x2) + 2 small stacked
        const leftLarge = rowIdx % 4 === 0;
        // Capture local references to avoid closure issues with mutable `i`
        const p0 = places[i];
        const p1 = places[i + 1];
        const p2 = places[i + 2];
        rows.push(
          <View key={`row-${rowIdx}`} style={pStyles.gridRow}>
            {leftLarge ? (
              <>
                <PlaceGridItem
                  place={p0}
                  size="large"
                  onPress={() => router.push(`/place/${p0.place_id}`)}
                />
                <View style={pStyles.stackedCol}>
                  <PlaceGridItem
                    place={p1}
                    size="small"
                    onPress={() => router.push(`/place/${p1.place_id}`)}
                  />
                  <PlaceGridItem
                    place={p2}
                    size="small"
                    onPress={() => router.push(`/place/${p2.place_id}`)}
                  />
                </View>
              </>
            ) : (
              <>
                <View style={pStyles.stackedCol}>
                  <PlaceGridItem
                    place={p1}
                    size="small"
                    onPress={() => router.push(`/place/${p1.place_id}`)}
                  />
                  <PlaceGridItem
                    place={p2}
                    size="small"
                    onPress={() => router.push(`/place/${p2.place_id}`)}
                  />
                </View>
                <PlaceGridItem
                  place={p0}
                  size="large"
                  onPress={() => router.push(`/place/${p0.place_id}`)}
                />
              </>
            )}
          </View>
        );
        i += 3;
      } else {
        // Pattern: 3 small in a row
        const rowItems = places.slice(i, i + 3);
        rows.push(
          <View key={`row-${rowIdx}`} style={pStyles.gridRow}>
            {rowItems.map((place) => (
              <PlaceGridItem
                key={place.place_id}
                place={place}
                size="small"
                onPress={() => router.push(`/place/${place.place_id}`)}
              />
            ))}
          </View>
        );
        i += rowItems.length;
      }
      rowIdx++;
    }
    return rows;
  };

  return (
    <SafeAreaView style={pStyles.container} edges={['top']}>
      {/* Header */}
      <View style={pStyles.header}>
        <Text style={pStyles.headerTitle}>Places</Text>
        <TouchableOpacity style={pStyles.mapBtn}>
          <Ionicons name="map-outline" size={20} color={colors.accentPrimary} />
        </TouchableOpacity>
      </View>

      {/* Search */}
      <View style={pStyles.searchBar}>
        <Ionicons name="search" size={18} color={colors.textHint} />
        <TextInput
          style={pStyles.searchInput}
          placeholder="Search places..."
          placeholderTextColor={colors.textHint}
          value={search}
          onChangeText={setSearch}
          onSubmitEditing={handleSearch}
          returnKeyType="search"
        />
        {search.length > 0 && (
          <TouchableOpacity onPress={() => { setSearch(''); setIsLoading(true); loadPlaces(activeType); }}>
            <Ionicons name="close-circle" size={18} color={colors.textHint} />
          </TouchableOpacity>
        )}
      </View>

      {/* Category chips */}
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={pStyles.chipRow}
      >
        {PLACE_TYPES.map((t) => (
          <TouchableOpacity
            key={t.id}
            style={[pStyles.chip, activeType === t.id && pStyles.chipActive]}
            onPress={() => setActiveType(t.id)}
          >
            <Ionicons
              name={t.icon as any}
              size={16}
              color={activeType === t.id ? '#FFFFFF' : colors.textSecondary}
            />
            <Text style={[pStyles.chipText, activeType === t.id && pStyles.chipTextActive]}>
              {t.label}
            </Text>
          </TouchableOpacity>
        ))}
      </ScrollView>

      {/* Grid */}
      {isLoading ? (
        <View style={pStyles.loadingCenter}>
          <ActivityIndicator size="large" color={colors.accentPrimary} />
        </View>
      ) : (
        <ScrollView
          showsVerticalScrollIndicator={false}
          refreshControl={
            <RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} tintColor={colors.accentPrimary} />
          }
          contentContainerStyle={{ paddingBottom: 100, gap: GRID_GAP }}
        >
          {places.length === 0 ? (
            <View style={pStyles.emptyState}>
              <Ionicons name="location-outline" size={56} color={colors.textHint} />
              <Text style={pStyles.emptyTitle}>No places found</Text>
              <Text style={pStyles.emptyText}>Try a different category or search</Text>
            </View>
          ) : (
            renderGrid()
          )}
        </ScrollView>
      )}
    </SafeAreaView>
  );
}

const pStyles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FFFFFF' },
  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 20, paddingVertical: 12,
  },
  headerTitle: { fontSize: 24, fontWeight: '700', color: colors.textPrimary, fontStyle: 'italic' },
  mapBtn: {
    width: 44, height: 44, borderRadius: 22, backgroundColor: colors.accentPrimaryLight,
    justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: colors.accentPrimary,
  },
  searchBar: {
    flexDirection: 'row', alignItems: 'center', marginHorizontal: 16, marginBottom: 12,
    paddingHorizontal: 14, paddingVertical: 10, borderRadius: 14,
    backgroundColor: colors.bgSubtle, gap: 10,
  },
  searchInput: { flex: 1, fontSize: 15, color: colors.textPrimary },
  chipRow: { paddingHorizontal: 16, gap: 8, marginBottom: 12 },
  chip: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    paddingHorizontal: 14, paddingVertical: 8, borderRadius: 18,
    backgroundColor: colors.bgSubtle, borderWidth: 1, borderColor: colors.borderLight,
  },
  chipActive: { backgroundColor: colors.accentPrimary, borderColor: colors.accentPrimary },
  chipText: { fontSize: 13, fontWeight: '600', color: colors.textSecondary },
  chipTextActive: { color: '#FFFFFF' },
  gridRow: { flexDirection: 'row', gap: GRID_GAP },
  stackedCol: { gap: GRID_GAP },
  loadingCenter: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  emptyState: { alignItems: 'center', paddingVertical: 60 },
  emptyTitle: { fontSize: 16, fontWeight: '700', color: colors.textPrimary, marginTop: 12 },
  emptyText: { fontSize: 13, color: colors.textHint, marginTop: 4 },
});
