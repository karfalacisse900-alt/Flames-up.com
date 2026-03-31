import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  FlatList,
  Image,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, borderRadius } from '../../src/utils/theme';
import api from '../../src/api/client';
import PostCard from '../../src/components/PostCard';
import { useAuthStore } from '../../src/store/authStore';

type Tab = 'trending' | 'users' | 'places';

export default function DiscoverScreen() {
  const router = useRouter();
  const { user } = useAuthStore();
  const [activeTab, setActiveTab] = useState<Tab>('trending');
  const [searchQuery, setSearchQuery] = useState('');
  const [isSearching, setIsSearching] = useState(false);
  const [trendingPosts, setTrendingPosts] = useState<any[]>([]);
  const [suggestedUsers, setSuggestedUsers] = useState<any[]>([]);
  const [searchResults, setSearchResults] = useState<any>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    loadInitialData();
  }, []);

  const loadInitialData = async () => {
    try {
      const [trendingRes, usersRes] = await Promise.all([
        api.get('/discover/trending'),
        api.get('/discover/suggested-users'),
      ]);
      setTrendingPosts(trendingRes.data);
      setSuggestedUsers(usersRes.data);
    } catch (error) {
      console.log('Error loading discover data:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleSearch = async () => {
    if (!searchQuery.trim()) return;
    
    setIsSearching(true);
    try {
      const response = await api.get(`/discover/search?query=${encodeURIComponent(searchQuery)}`);
      setSearchResults(response.data);
    } catch (error) {
      console.log('Error searching:', error);
    } finally {
      setIsSearching(false);
    }
  };

  const clearSearch = () => {
    setSearchQuery('');
    setSearchResults(null);
  };

  const renderUserItem = ({ item }: { item: any }) => (
    <TouchableOpacity
      style={styles.userItem}
      onPress={() => router.push(`/user/${item.id}`)}
    >
      {item.profile_image ? (
        <Image source={{ uri: item.profile_image }} style={styles.userAvatar} />
      ) : (
        <View style={styles.userAvatarPlaceholder}>
          <Text style={styles.userAvatarText}>{item.username[0].toUpperCase()}</Text>
        </View>
      )}
      <View style={styles.userInfo}>
        <Text style={styles.userName}>{item.full_name}</Text>
        <Text style={styles.userHandle}>@{item.username}</Text>
      </View>
      <TouchableOpacity style={styles.followButton}>
        <Text style={styles.followButtonText}>Follow</Text>
      </TouchableOpacity>
    </TouchableOpacity>
  );

  const renderSearchResults = () => {
    if (!searchResults) return null;

    return (
      <View style={styles.searchResults}>
        {searchResults.users?.length > 0 && (
          <View style={styles.searchSection}>
            <Text style={styles.searchSectionTitle}>Users</Text>
            {searchResults.users.map((item: any) => (
              <TouchableOpacity
                key={item.id}
                style={styles.userItem}
                onPress={() => router.push(`/user/${item.id}`)}
              >
                {item.profile_image ? (
                  <Image source={{ uri: item.profile_image }} style={styles.userAvatar} />
                ) : (
                  <View style={styles.userAvatarPlaceholder}>
                    <Text style={styles.userAvatarText}>{item.username[0].toUpperCase()}</Text>
                  </View>
                )}
                <View style={styles.userInfo}>
                  <Text style={styles.userName}>{item.full_name}</Text>
                  <Text style={styles.userHandle}>@{item.username}</Text>
                </View>
              </TouchableOpacity>
            ))}
          </View>
        )}

        {searchResults.posts?.length > 0 && (
          <View style={styles.searchSection}>
            <Text style={styles.searchSectionTitle}>Posts</Text>
            {searchResults.posts.map((post: any) => (
              <PostCard
                key={post.id}
                post={post}
                currentUserId={user?.id || ''}
                onPress={() => router.push(`/post/${post.id}`)}
                onUserPress={() => router.push(`/user/${post.user_id}`)}
              />
            ))}
          </View>
        )}

        {searchResults.places?.length > 0 && (
          <View style={styles.searchSection}>
            <Text style={styles.searchSectionTitle}>Places</Text>
            {searchResults.places.map((place: any) => (
              <TouchableOpacity
                key={place.id}
                style={styles.placeItem}
                onPress={() => router.push(`/place/${place.id}`)}
              >
                <Ionicons name="location" size={24} color={colors.primary} />
                <View style={styles.placeInfo}>
                  <Text style={styles.placeName}>{place.name}</Text>
                  <Text style={styles.placeAddress}>{place.address}</Text>
                </View>
              </TouchableOpacity>
            ))}
          </View>
        )}
      </View>
    );
  };

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
        <Text style={styles.headerTitle}>Discover</Text>
      </View>

      {/* Search Bar */}
      <View style={styles.searchContainer}>
        <View style={styles.searchBar}>
          <Ionicons name="search" size={20} color={colors.textTertiary} />
          <TextInput
            style={styles.searchInput}
            placeholder="Search users, posts, places..."
            placeholderTextColor={colors.textTertiary}
            value={searchQuery}
            onChangeText={setSearchQuery}
            onSubmitEditing={handleSearch}
            returnKeyType="search"
          />
          {searchQuery.length > 0 && (
            <TouchableOpacity onPress={clearSearch}>
              <Ionicons name="close-circle" size={20} color={colors.textTertiary} />
            </TouchableOpacity>
          )}
        </View>
      </View>

      {isSearching ? (
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      ) : searchResults ? (
        <FlatList
          data={[]}
          renderItem={() => null}
          ListHeaderComponent={renderSearchResults}
          showsVerticalScrollIndicator={false}
        />
      ) : (
        <FlatList
          data={activeTab === 'users' ? suggestedUsers : trendingPosts}
          renderItem={activeTab === 'users' ? renderUserItem : ({ item }) => (
            <PostCard
              post={item}
              currentUserId={user?.id || ''}
              onPress={() => router.push(`/post/${item.id}`)}
              onUserPress={() => router.push(`/user/${item.user_id}`)}
            />
          )}
          keyExtractor={(item) => item.id}
          ListHeaderComponent={
            <View style={styles.tabs}>
              <TouchableOpacity
                style={[styles.tab, activeTab === 'trending' && styles.activeTab]}
                onPress={() => setActiveTab('trending')}
              >
                <Text style={[styles.tabText, activeTab === 'trending' && styles.activeTabText]}>
                  Trending
                </Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.tab, activeTab === 'users' && styles.activeTab]}
                onPress={() => setActiveTab('users')}
              >
                <Text style={[styles.tabText, activeTab === 'users' && styles.activeTabText]}>
                  Suggested
                </Text>
              </TouchableOpacity>
            </View>
          }
          ListEmptyComponent={
            <View style={styles.emptyContainer}>
              <Ionicons name="search-outline" size={64} color={colors.textTertiary} />
              <Text style={styles.emptyTitle}>Nothing to show</Text>
              <Text style={styles.emptyText}>Try searching for something</Text>
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
    backgroundColor: colors.background,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.background,
  },
  header: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  headerTitle: {
    fontSize: 28,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  searchContainer: {
    paddingHorizontal: spacing.md,
    paddingBottom: spacing.md,
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.backgroundSecondary,
    borderRadius: borderRadius.md,
    paddingHorizontal: spacing.md,
    height: 44,
  },
  searchInput: {
    flex: 1,
    fontSize: 15,
    color: colors.textPrimary,
    marginLeft: spacing.sm,
  },
  tabs: {
    flexDirection: 'row',
    paddingHorizontal: spacing.md,
    marginBottom: spacing.md,
  },
  tab: {
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    borderRadius: borderRadius.full,
    marginRight: spacing.sm,
    backgroundColor: colors.backgroundSecondary,
  },
  activeTab: {
    backgroundColor: colors.primary,
  },
  tabText: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  activeTabText: {
    color: colors.textInverse,
  },
  userItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  userAvatar: {
    width: 50,
    height: 50,
    borderRadius: 25,
  },
  userAvatarPlaceholder: {
    width: 50,
    height: 50,
    borderRadius: 25,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  userAvatarText: {
    color: colors.textInverse,
    fontSize: 20,
    fontWeight: '600',
  },
  userInfo: {
    flex: 1,
    marginLeft: spacing.md,
  },
  userName: {
    fontSize: 15,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  userHandle: {
    fontSize: 13,
    color: colors.textSecondary,
    marginTop: 2,
  },
  followButton: {
    backgroundColor: colors.primary,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.xs,
    borderRadius: borderRadius.full,
  },
  followButtonText: {
    color: colors.textInverse,
    fontSize: 13,
    fontWeight: '600',
  },
  searchResults: {
    paddingBottom: spacing.xl,
  },
  searchSection: {
    marginBottom: spacing.lg,
  },
  searchSectionTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.textPrimary,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  placeItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  placeInfo: {
    flex: 1,
    marginLeft: spacing.md,
  },
  placeName: {
    fontSize: 15,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  placeAddress: {
    fontSize: 13,
    color: colors.textSecondary,
    marginTop: 2,
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
  },
});
