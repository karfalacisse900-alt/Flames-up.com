import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  Image,
  RefreshControl,
  ActivityIndicator,
  TextInput,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, borderRadius, shadows } from '../../src/utils/theme';
import api from '../../src/api/client';

const CATEGORIES = ['All', 'Restaurant', 'Cafe', 'Bar', 'Park', 'Shop', 'Gallery', 'Gym', 'Club'];

function PlaceCard({ place, onPress }: { place: any; onPress: () => void }) {
  return (
    <TouchableOpacity style={cardStyles.card} onPress={onPress} activeOpacity={0.9}>
      {place.image_url ? (
        <Image source={{ uri: place.image_url }} style={cardStyles.image} />
      ) : (
        <View style={cardStyles.imagePlaceholder}>
          <Ionicons name="location" size={32} color={colors.textHint} />
        </View>
      )}
      <View style={cardStyles.content}>
        <Text style={cardStyles.name} numberOfLines={1}>{place.name}</Text>
        <Text style={cardStyles.address} numberOfLines={1}>{place.address}</Text>
        <View style={cardStyles.metaRow}>
          {place.category && (
            <View style={cardStyles.categoryPill}>
              <Text style={cardStyles.categoryText}>{place.category}</Text>
            </View>
          )}
          {place.rating > 0 && (
            <View style={cardStyles.ratingRow}>
              <Ionicons name="star" size={12} color="#F59E0B" />
              <Text style={cardStyles.ratingText}>{place.rating.toFixed(1)}</Text>
            </View>
          )}
        </View>
      </View>
    </TouchableOpacity>
  );
}

const cardStyles = StyleSheet.create({
  card: {
    flexDirection: 'row',
    backgroundColor: colors.bgCard,
    borderRadius: 20,
    overflow: 'hidden',
    marginHorizontal: 16,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation1,
  },
  image: {
    width: 100,
    height: 100,
  },
  imagePlaceholder: {
    width: 100,
    height: 100,
    backgroundColor: colors.bgSubtle,
    justifyContent: 'center',
    alignItems: 'center',
  },
  content: {
    flex: 1,
    padding: 12,
    justifyContent: 'center',
  },
  name: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.textPrimary,
    marginBottom: 4,
  },
  address: {
    fontSize: 12,
    color: colors.textHint,
    marginBottom: 8,
  },
  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  categoryPill: {
    backgroundColor: colors.accentPrimaryLight,
    paddingHorizontal: 10,
    paddingVertical: 3,
    borderRadius: 10,
  },
  categoryText: {
    fontSize: 11,
    fontWeight: '600',
    color: colors.accentPrimary,
  },
  ratingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
  },
  ratingText: {
    fontSize: 12,
    fontWeight: '600',
    color: colors.textSecondary,
  },
});

export default function PlacesScreen() {
  const router = useRouter();
  const [places, setPlaces] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('All');

  const loadPlaces = async () => {
    try {
      const response = await api.get('/places', {
        params: {
          category: category !== 'All' ? category : undefined,
        },
      });
      setPlaces(response.data);
    } catch (error) {
      console.log('Error loading places:', error);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadPlaces();
  }, [category]);

  const onRefresh = useCallback(async () => {
    setIsRefreshing(true);
    await loadPlaces();
    setIsRefreshing(false);
  }, [category]);

  const filteredPlaces = search
    ? places.filter(
        (p) =>
          p.name?.toLowerCase().includes(search.toLowerCase()) ||
          p.address?.toLowerCase().includes(search.toLowerCase())
      )
    : places;

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Places</Text>
        <TouchableOpacity style={styles.mapBtn}>
          <Ionicons name="map-outline" size={20} color={colors.accentPrimary} />
        </TouchableOpacity>
      </View>

      {/* Search */}
      <View style={styles.searchBar}>
        <Ionicons name="search" size={18} color={colors.textHint} />
        <TextInput
          style={styles.searchInput}
          placeholder="Search places..."
          placeholderTextColor={colors.textHint}
          value={search}
          onChangeText={setSearch}
        />
        {search.length > 0 && (
          <TouchableOpacity onPress={() => setSearch('')}>
            <Ionicons name="close-circle" size={18} color={colors.textHint} />
          </TouchableOpacity>
        )}
      </View>

      {/* Category chips */}
      <FlatList
        horizontal
        data={CATEGORIES}
        keyExtractor={(item) => item}
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.chipRow}
        renderItem={({ item }) => (
          <TouchableOpacity
            style={[styles.chip, category === item && styles.chipActive]}
            onPress={() => setCategory(item)}
          >
            <Text style={[styles.chipText, category === item && styles.chipTextActive]}>
              {item}
            </Text>
          </TouchableOpacity>
        )}
      />

      {isLoading ? (
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={colors.accentPrimary} />
        </View>
      ) : (
        <FlatList
          data={filteredPlaces}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => (
            <PlaceCard
              place={item}
              onPress={() => router.push(`/place/${item.id}`)}
            />
          )}
          refreshControl={
            <RefreshControl
              refreshing={isRefreshing}
              onRefresh={onRefresh}
              tintColor={colors.accentPrimary}
            />
          }
          contentContainerStyle={{ paddingBottom: 100, paddingTop: 4 }}
          ListEmptyComponent={
            <View style={styles.emptyState}>
              <Ionicons name="location-outline" size={48} color={colors.textHint} />
              <Text style={styles.emptyTitle}>No places found</Text>
              <Text style={styles.emptyText}>Try a different category or location</Text>
            </View>
          }
          showsVerticalScrollIndicator={false}
        />
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bgApp,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
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
  mapBtn: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: colors.accentPrimaryLight,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.accentPrimary,
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    marginHorizontal: 16,
    marginBottom: 12,
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 16,
    backgroundColor: colors.bgCard,
    borderWidth: 1,
    borderColor: colors.borderLight,
    gap: 12,
  },
  searchInput: {
    flex: 1,
    fontSize: 15,
    color: colors.textPrimary,
  },
  chipRow: {
    paddingHorizontal: 16,
    gap: 6,
    marginBottom: 12,
  },
  chip: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 18,
    backgroundColor: colors.bgCard,
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  chipActive: {
    backgroundColor: colors.accentPrimary,
    borderColor: colors.accentPrimary,
  },
  chipText: {
    fontSize: 13,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  chipTextActive: {
    color: '#FFFFFF',
  },
  emptyState: {
    alignItems: 'center',
    paddingVertical: 60,
  },
  emptyTitle: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.textPrimary,
    marginTop: 12,
  },
  emptyText: {
    fontSize: 13,
    color: colors.textHint,
    marginTop: 4,
  },
});
