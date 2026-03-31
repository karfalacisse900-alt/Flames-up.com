import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  Image,
  ActivityIndicator,
  RefreshControl,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, borderRadius } from '../../src/utils/theme';
import api from '../../src/api/client';
import * as Location from 'expo-location';

const CATEGORIES = [
  { id: 'all', name: 'All', icon: 'apps' },
  { id: 'restaurant', name: 'Food', icon: 'restaurant' },
  { id: 'cafe', name: 'Cafe', icon: 'cafe' },
  { id: 'park', name: 'Parks', icon: 'leaf' },
  { id: 'shopping', name: 'Shopping', icon: 'bag' },
  { id: 'entertainment', name: 'Fun', icon: 'game-controller' },
];

export default function PlacesScreen() {
  const router = useRouter();
  const [places, setPlaces] = useState<any[]>([]);
  const [selectedCategory, setSelectedCategory] = useState('all');
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [location, setLocation] = useState<Location.LocationObject | null>(null);
  const [locationError, setLocationError] = useState<string | null>(null);

  useEffect(() => {
    requestLocation();
  }, []);

  useEffect(() => {
    loadPlaces();
  }, [selectedCategory, location]);

  const requestLocation = async () => {
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') {
        setLocationError('Location permission denied');
        loadPlaces();
        return;
      }

      const loc = await Location.getCurrentPositionAsync({});
      setLocation(loc);
    } catch (error) {
      setLocationError('Could not get location');
      loadPlaces();
    }
  };

  const loadPlaces = async () => {
    try {
      let url = '/places';
      if (selectedCategory !== 'all') {
        url += `?category=${selectedCategory}`;
      }
      
      if (location) {
        const separator = url.includes('?') ? '&' : '?';
        url = `/places/nearby?latitude=${location.coords.latitude}&longitude=${location.coords.longitude}&radius=50`;
        if (selectedCategory !== 'all') {
          // Filter nearby places by category on client side
        }
      }

      const response = await api.get(url);
      let placesData = response.data;
      
      if (selectedCategory !== 'all' && location) {
        placesData = placesData.filter((p: any) => p.category === selectedCategory);
      }
      
      setPlaces(placesData);
    } catch (error) {
      console.log('Error loading places:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const onRefresh = async () => {
    setIsRefreshing(true);
    await loadPlaces();
    setIsRefreshing(false);
  };

  const renderCategory = ({ item }: { item: typeof CATEGORIES[0] }) => (
    <TouchableOpacity
      style={[
        styles.categoryItem,
        selectedCategory === item.id && styles.categoryItemActive,
      ]}
      onPress={() => setSelectedCategory(item.id)}
    >
      <Ionicons
        name={item.icon as any}
        size={20}
        color={selectedCategory === item.id ? colors.textInverse : colors.textSecondary}
      />
      <Text
        style={[
          styles.categoryText,
          selectedCategory === item.id && styles.categoryTextActive,
        ]}
      >
        {item.name}
      </Text>
    </TouchableOpacity>
  );

  const renderPlace = ({ item }: { item: any }) => (
    <TouchableOpacity
      style={styles.placeCard}
      onPress={() => router.push(`/place/${item.id}`)}
    >
      {item.image ? (
        <Image source={{ uri: item.image }} style={styles.placeImage} />
      ) : (
        <View style={styles.placeImagePlaceholder}>
          <Ionicons name="image-outline" size={40} color={colors.textTertiary} />
        </View>
      )}
      <View style={styles.placeInfo}>
        <View style={styles.placeHeader}>
          <Text style={styles.placeName} numberOfLines={1}>{item.name}</Text>
          {item.rating > 0 && (
            <View style={styles.ratingBadge}>
              <Ionicons name="star" size={12} color={colors.warning} />
              <Text style={styles.ratingText}>{item.rating.toFixed(1)}</Text>
            </View>
          )}
        </View>
        <Text style={styles.placeAddress} numberOfLines={1}>{item.address}</Text>
        <View style={styles.placeFooter}>
          <View style={styles.categoryBadge}>
            <Text style={styles.categoryBadgeText}>{item.category}</Text>
          </View>
          {item.distance !== undefined && (
            <Text style={styles.distanceText}>{item.distance} km away</Text>
          )}
        </View>
      </View>
    </TouchableOpacity>
  );

  if (isLoading) {
    return (
      <SafeAreaView style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Places</Text>
        {location && (
          <View style={styles.locationBadge}>
            <Ionicons name="location" size={14} color={colors.success} />
            <Text style={styles.locationText}>Near you</Text>
          </View>
        )}
      </View>

      {/* Categories */}
      <FlatList
        data={CATEGORIES}
        renderItem={renderCategory}
        keyExtractor={(item) => item.id}
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.categoriesList}
      />

      {/* Places List */}
      <FlatList
        data={places}
        renderItem={renderPlace}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.placesList}
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={onRefresh}
            tintColor={colors.primary}
          />
        }
        ListEmptyComponent={
          <View style={styles.emptyContainer}>
            <Ionicons name="location-outline" size={64} color={colors.textTertiary} />
            <Text style={styles.emptyTitle}>No places found</Text>
            <Text style={styles.emptyText}>
              {locationError || 'Try a different category'}
            </Text>
          </View>
        }
        showsVerticalScrollIndicator={false}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.background,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  headerTitle: {
    fontSize: 28,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  locationBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.backgroundSecondary,
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.xs,
    borderRadius: borderRadius.full,
  },
  locationText: {
    fontSize: 12,
    color: colors.success,
    marginLeft: 4,
    fontWeight: '500',
  },
  categoriesList: {
    paddingHorizontal: spacing.md,
    paddingBottom: spacing.md,
  },
  categoryItem: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.backgroundSecondary,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: borderRadius.full,
    marginRight: spacing.sm,
  },
  categoryItemActive: {
    backgroundColor: colors.primary,
  },
  categoryText: {
    fontSize: 14,
    fontWeight: '500',
    color: colors.textSecondary,
    marginLeft: spacing.xs,
  },
  categoryTextActive: {
    color: colors.textInverse,
  },
  placesList: {
    paddingHorizontal: spacing.md,
    paddingBottom: spacing.xl,
  },
  placeCard: {
    backgroundColor: colors.background,
    borderRadius: borderRadius.lg,
    overflow: 'hidden',
    marginBottom: spacing.md,
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  placeImage: {
    width: '100%',
    height: 160,
  },
  placeImagePlaceholder: {
    width: '100%',
    height: 160,
    backgroundColor: colors.backgroundSecondary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  placeInfo: {
    padding: spacing.md,
  },
  placeHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: spacing.xs,
  },
  placeName: {
    fontSize: 17,
    fontWeight: '600',
    color: colors.textPrimary,
    flex: 1,
  },
  ratingBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.backgroundSecondary,
    paddingHorizontal: spacing.sm,
    paddingVertical: 4,
    borderRadius: borderRadius.sm,
    marginLeft: spacing.sm,
  },
  ratingText: {
    fontSize: 12,
    fontWeight: '600',
    color: colors.textPrimary,
    marginLeft: 4,
  },
  placeAddress: {
    fontSize: 14,
    color: colors.textSecondary,
    marginBottom: spacing.sm,
  },
  placeFooter: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  categoryBadge: {
    backgroundColor: colors.primaryLight,
    paddingHorizontal: spacing.sm,
    paddingVertical: 4,
    borderRadius: borderRadius.sm,
  },
  categoryBadgeText: {
    fontSize: 12,
    fontWeight: '500',
    color: colors.primaryDark,
    textTransform: 'capitalize',
  },
  distanceText: {
    fontSize: 12,
    color: colors.textTertiary,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 80,
  },
  emptyTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: colors.textPrimary,
    marginTop: spacing.md,
  },
  emptyText: {
    fontSize: 14,
    color: colors.textSecondary,
    marginTop: spacing.xs,
    textAlign: 'center',
  },
});
