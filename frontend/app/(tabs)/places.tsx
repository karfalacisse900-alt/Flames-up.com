import React, { useCallback, useEffect, useMemo, useState } from 'react';
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
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../../src/utils/theme';
import api from '../../src/api/client';
import { rankPlacesByQuery } from '../../src/utils/geoSpatial';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const GRID_GAP = 6;
const COL3_WIDTH = (SCREEN_WIDTH - GRID_GAP * 4) / 3;

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

const CITY_BOARDS = [
  { id: 'world', label: 'World Board', lat: 20.0, lng: 0.0, radius: 45000 },
  { id: 'nyc', label: 'NYC', lat: 40.7128, lng: -74.006, radius: 15000 },
  { id: 'miami', label: 'Miami', lat: 25.7617, lng: -80.1918, radius: 15000 },
  { id: 'la', label: 'Los Angeles', lat: 34.0522, lng: -118.2437, radius: 16000 },
  { id: 'london', label: 'London', lat: 51.5072, lng: -0.1276, radius: 16000 },
  { id: 'tokyo', label: 'Tokyo', lat: 35.6762, lng: 139.6503, radius: 16000 },
];

function PlaceGridItem({
  place,
  size,
  onPress,
}: {
  place: any;
  size: 'large' | 'small';
  onPress: () => void;
}) {
  const isLarge = size === 'large';
  const w = isLarge ? COL3_WIDTH * 2 + GRID_GAP : COL3_WIDTH;
  const h = isLarge ? COL3_WIDTH * 2 + GRID_GAP : COL3_WIDTH;

  return (
    <TouchableOpacity style={[gridStyles.item, { width: w, height: h }]} onPress={onPress} activeOpacity={0.9}>
      {place.photo_url ? (
        <Image source={{ uri: place.photo_url }} style={gridStyles.image} />
      ) : (
        <View style={gridStyles.placeholder}>
          <Ionicons name="image-outline" size={32} color={colors.textHint} />
        </View>
      )}
      <View style={gridStyles.bottomGradient} />
      <View style={gridStyles.info}>
        <Text style={gridStyles.name} numberOfLines={isLarge ? 2 : 1}>
          {place.name}
        </Text>
        <View style={gridStyles.ratingRow}>
          <Ionicons name="star" size={11} color="#FCD34D" />
          <Text style={gridStyles.rating}>{place.rating?.toFixed(1) || '-'}</Text>
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
    borderRadius: 14,
    overflow: 'hidden',
    backgroundColor: colors.bgSubtle,
  },
  image: {
    width: '100%',
    height: '100%',
    resizeMode: 'cover',
  },
  placeholder: {
    width: '100%',
    height: '100%',
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.bgSubtle,
  },
  bottomGradient: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: '35%',
    backgroundColor: 'rgba(0,0,0,0.25)',
  },
  info: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    padding: 10,
  },
  name: {
    color: '#FFFFFF',
    fontSize: 13,
    fontWeight: '700',
    lineHeight: 17,
    textShadowColor: 'rgba(0,0,0,0.6)',
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 3,
  },
  ratingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    marginTop: 3,
  },
  rating: {
    color: 'rgba(255,255,255,0.9)',
    fontSize: 11,
    fontWeight: '600',
    textShadowColor: 'rgba(0,0,0,0.5)',
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 2,
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
  const [allPlaces, setAllPlaces] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [search, setSearch] = useState('');
  const [activeType, setActiveType] = useState('restaurant');
  const [activeBoard, setActiveBoard] = useState(CITY_BOARDS[0].id);
  const [error, setError] = useState<string | null>(null);

  const selectedBoard = useMemo(
    () => CITY_BOARDS.find((b) => b.id === activeBoard) || CITY_BOARDS[0],
    [activeBoard]
  );

  const loadPlaces = useCallback(
    async (type: string, keyword?: string) => {
      setIsLoading(true);
      setError(null);
      try {
        const params: any = {
          type,
          lat: selectedBoard.lat,
          lng: selectedBoard.lng,
          radius: selectedBoard.radius,
        };
        if (keyword?.trim()) params.keyword = keyword.trim();

        const response = await api.get('/google-places/nearby', { params });
        const data = response.data;
        if (data?.error) {
          setError(data.error);
          setAllPlaces([]);
          setPlaces([]);
        } else {
          const list = Array.isArray(data) ? data : data?.places || [];
          setAllPlaces(list);
          if (keyword?.trim()) {
            setPlaces(
              rankPlacesByQuery(
                list,
                keyword.trim(),
                { lat: selectedBoard.lat, lng: selectedBoard.lng },
                180
              )
            );
          } else {
            setPlaces(list);
          }
        }
      } catch {
        setError('Failed to load places');
        setAllPlaces([]);
        setPlaces([]);
      } finally {
        setIsLoading(false);
      }
    },
    [selectedBoard]
  );

  useEffect(() => {
    loadPlaces(activeType);
  }, [activeType, activeBoard, loadPlaces]);

  useEffect(() => {
    const query = search.trim();
    if (!query) {
      setPlaces(allPlaces);
      return;
    }
    setPlaces(
      rankPlacesByQuery(
        allPlaces,
        query,
        { lat: selectedBoard.lat, lng: selectedBoard.lng },
        180
      )
    );
  }, [search, allPlaces, selectedBoard]);

  const onRefresh = useCallback(async () => {
    setIsRefreshing(true);
    await loadPlaces(activeType, search || undefined);
    setIsRefreshing(false);
  }, [activeType, search, loadPlaces]);

  const handleSearch = () => {
    if (search.trim()) {
      setIsLoading(true);
      loadPlaces(activeType, search.trim());
    }
  };

  const renderGrid = () => {
    const rows: React.ReactNode[] = [];
    let i = 0;
    let rowIdx = 0;

    while (i < places.length) {
      if (rowIdx % 2 === 0 && i + 2 < places.length) {
        const leftLarge = rowIdx % 4 === 0;
        const p0 = places[i];
        const p1 = places[i + 1];
        const p2 = places[i + 2];
        rows.push(
          <View key={`row-${rowIdx}`} style={pStyles.gridRow}>
            {leftLarge ? (
              <>
                <PlaceGridItem place={p0} size="large" onPress={() => router.push(`/place/${p0.place_id}`)} />
                <View style={pStyles.stackedCol}>
                  <PlaceGridItem place={p1} size="small" onPress={() => router.push(`/place/${p1.place_id}`)} />
                  <PlaceGridItem place={p2} size="small" onPress={() => router.push(`/place/${p2.place_id}`)} />
                </View>
              </>
            ) : (
              <>
                <View style={pStyles.stackedCol}>
                  <PlaceGridItem place={p1} size="small" onPress={() => router.push(`/place/${p1.place_id}`)} />
                  <PlaceGridItem place={p2} size="small" onPress={() => router.push(`/place/${p2.place_id}`)} />
                </View>
                <PlaceGridItem place={p0} size="large" onPress={() => router.push(`/place/${p0.place_id}`)} />
              </>
            )}
          </View>
        );
        i += 3;
      } else {
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
      <View style={pStyles.header}>
        <View>
          <Text style={pStyles.headerTitle}>City Boards</Text>
          <View style={pStyles.locationRow}>
            <Ionicons name="globe-outline" size={12} color={colors.accentPrimary} />
            <Text style={pStyles.locationLabel}>{selectedBoard.label}</Text>
          </View>
        </View>
        <TouchableOpacity
          style={pStyles.mapBtn}
          onPress={() =>
            router.push(
              `/map-view?type=${activeType}&board=${selectedBoard.id}&lat=${selectedBoard.lat}&lng=${selectedBoard.lng}&city=${encodeURIComponent(selectedBoard.label)}` as any
            )
          }
        >
          <Ionicons name="map-outline" size={20} color={colors.accentPrimary} />
        </TouchableOpacity>
      </View>

      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={pStyles.boardRow}>
        {CITY_BOARDS.map((board) => (
          <TouchableOpacity
            key={board.id}
            style={[pStyles.boardChip, activeBoard === board.id && pStyles.boardChipActive]}
            onPress={() => setActiveBoard(board.id)}
          >
            <Text style={[pStyles.boardText, activeBoard === board.id && pStyles.boardTextActive]}>
              {board.label}
            </Text>
          </TouchableOpacity>
        ))}
      </ScrollView>

      <View style={pStyles.searchBar}>
        <Ionicons name="search" size={18} color={colors.textHint} />
        <TextInput
          style={pStyles.searchInput}
          placeholder="Search in this board..."
          placeholderTextColor={colors.textHint}
          value={search}
          onChangeText={setSearch}
          onSubmitEditing={handleSearch}
          returnKeyType="search"
        />
        {search.length > 0 && (
          <TouchableOpacity
            onPress={() => {
              setSearch('');
              setIsLoading(true);
              loadPlaces(activeType);
            }}
          >
            <Ionicons name="close-circle" size={18} color={colors.textHint} />
          </TouchableOpacity>
        )}
      </View>

      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={pStyles.chipRow}>
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
            <Text style={[pStyles.chipText, activeType === t.id && pStyles.chipTextActive]}>{t.label}</Text>
          </TouchableOpacity>
        ))}
      </ScrollView>

      {isLoading ? (
        <View style={pStyles.loadingCenter}>
          <ActivityIndicator size="large" color={colors.accentPrimary} />
        </View>
      ) : (
        <ScrollView
          showsVerticalScrollIndicator={false}
          refreshControl={<RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} tintColor={colors.accentPrimary} />}
          contentContainerStyle={{ paddingHorizontal: GRID_GAP, paddingBottom: 100, gap: GRID_GAP }}
        >
          {places.length === 0 ? (
            <View style={pStyles.emptyState}>
              <Ionicons name="earth-outline" size={56} color={colors.textHint} />
              <Text style={pStyles.emptyTitle}>No places found</Text>
              {error ? (
                <Text style={{ fontSize: 13, color: '#DC2626', marginTop: 8, textAlign: 'center', paddingHorizontal: 20 }}>
                  {error.includes('Billing')
                    ? 'Enable Google Maps Billing on your Google Cloud Console to see places.'
                    : error}
                </Text>
              ) : (
                <Text style={pStyles.emptyText}>Try another board or category</Text>
              )}
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
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 12,
  },
  headerTitle: {
    fontSize: 24,
    fontWeight: '700',
    color: colors.textPrimary,
    fontStyle: 'italic',
  },
  locationRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    marginTop: 2,
  },
  locationLabel: {
    fontSize: 12,
    fontWeight: '600',
    color: colors.accentPrimary,
  },
  mapBtn: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: colors.accentPrimaryLight,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.accentPrimary + '40',
  },
  boardRow: {
    paddingHorizontal: 16,
    gap: 8,
    marginBottom: 10,
  },
  boardChip: {
    paddingHorizontal: 14,
    paddingVertical: 9,
    borderRadius: 20,
    backgroundColor: '#F4F1EC',
    borderWidth: 1,
    borderColor: '#E2DBCF',
  },
  boardChipActive: {
    backgroundColor: '#1F2937',
    borderColor: '#1F2937',
  },
  boardText: {
    fontSize: 13,
    color: '#4B5563',
    fontWeight: '700',
  },
  boardTextActive: {
    color: '#FFFFFF',
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    marginHorizontal: 16,
    marginBottom: 12,
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 14,
    backgroundColor: colors.bgSubtle,
    gap: 10,
  },
  searchInput: { flex: 1, fontSize: 15, color: colors.textPrimary },
  chipRow: {
    paddingHorizontal: 16,
    gap: 10,
    marginBottom: 14,
    paddingBottom: 2,
  },
  chip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 18,
    paddingVertical: 12,
    borderRadius: 24,
    backgroundColor: colors.bgSubtle,
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  chipActive: {
    backgroundColor: colors.accentPrimary,
    borderColor: colors.accentPrimary,
  },
  chipText: { fontSize: 15, fontWeight: '600', color: colors.textSecondary },
  chipTextActive: { color: '#FFFFFF' },
  gridRow: { flexDirection: 'row', gap: GRID_GAP },
  stackedCol: { gap: GRID_GAP },
  loadingCenter: { flex: 1, justifyContent: 'center', alignItems: 'center', paddingTop: 60 },
  emptyState: { alignItems: 'center', paddingVertical: 60 },
  emptyTitle: { fontSize: 16, fontWeight: '700', color: colors.textPrimary, marginTop: 12 },
  emptyText: { fontSize: 13, color: colors.textHint, marginTop: 4 },
});

