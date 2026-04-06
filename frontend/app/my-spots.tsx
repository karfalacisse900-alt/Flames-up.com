import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView,
  RefreshControl, Dimensions, ActivityIndicator, Alert,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../src/utils/theme';
import { useAuthStore } from '../src/store/authStore';
import api from '../src/api/client';

const { width: SW } = Dimensions.get('window');

type SaveType = 'all' | 'want_to_go' | 'favorite' | 'been_there';

const TABS: { key: SaveType; label: string; icon: string; color: string }[] = [
  { key: 'all',        label: 'All',          icon: 'layers-outline',    color: '#1A1A1A' },
  { key: 'want_to_go', label: 'Want to Go',   icon: 'flag-outline',      color: '#7C3AED' },
  { key: 'favorite',   label: 'Favorites',    icon: 'heart-outline',     color: '#DC2626' },
  { key: 'been_there', label: 'Been There',   icon: 'checkmark-circle-outline', color: '#16A34A' },
];

type SavedPlace = {
  id: string;
  place_id: string;
  place_name: string;
  place_type: string;
  save_type: string;
  created_at: string;
};

type SavedPost = {
  id: string;
  post_id: string;
  collection: string;
  content: string;
  image: string;
  images: string;
  likes_count: number;
  post_type: string;
  post_date: string;
  full_name: string;
  username: string;
  profile_image: string;
};

export default function MySpotsScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();

  const [activeTab, setActiveTab] = useState<SaveType>('all');
  const [savedPlaces, setSavedPlaces] = useState<SavedPlace[]>([]);
  const [savedPosts, setSavedPosts] = useState<SavedPost[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [viewMode, setViewMode] = useState<'places' | 'posts'>('places');

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      setIsLoading(true);
      const [placesRes, postsRes] = await Promise.allSettled([
        api.get('/saved-places'),
        api.get('/bookmarks'),
      ]);
      if (placesRes.status === 'fulfilled') {
        setSavedPlaces(placesRes.value.data?.places || []);
      }
      if (postsRes.status === 'fulfilled') {
        setSavedPosts(postsRes.value.data?.bookmarks || []);
      }
    } catch (err) {
      console.log('My Spots load error:', err);
    } finally {
      setIsLoading(false);
    }
  };

  const onRefresh = useCallback(async () => {
    setIsRefreshing(true);
    await loadData();
    setIsRefreshing(false);
  }, []);

  const handleRemovePlace = async (placeId: string) => {
    Alert.alert('Remove Place', 'Remove this from your saved spots?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Remove', style: 'destructive',
        onPress: async () => {
          try {
            await api.delete(`/saved-places/${placeId}`);
            setSavedPlaces(prev => prev.filter(p => p.place_id !== placeId));
          } catch (err) {
            console.log('Remove place error:', err);
          }
        },
      },
    ]);
  };

  const handleRemovePost = async (postId: string) => {
    Alert.alert('Remove Bookmark', 'Remove this saved post?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Remove', style: 'destructive',
        onPress: async () => {
          try {
            await api.delete(`/bookmarks/${postId}`);
            setSavedPosts(prev => prev.filter(p => p.post_id !== postId));
          } catch (err) {
            console.log('Remove bookmark error:', err);
          }
        },
      },
    ]);
  };

  const filteredPlaces = activeTab === 'all'
    ? savedPlaces
    : savedPlaces.filter(p => p.save_type === activeTab);

  const getSaveTypeIcon = (type: string) => {
    switch (type) {
      case 'want_to_go': return 'flag';
      case 'favorite': return 'heart';
      case 'been_there': return 'checkmark-circle';
      default: return 'bookmark';
    }
  };

  const getSaveTypeColor = (type: string) => {
    switch (type) {
      case 'want_to_go': return '#7C3AED';
      case 'favorite': return '#DC2626';
      case 'been_there': return '#16A34A';
      default: return '#999';
    }
  };

  const getPlaceTypeIcon = (type: string) => {
    if (type.includes('restaurant') || type.includes('food')) return 'restaurant-outline';
    if (type.includes('bar') || type.includes('club')) return 'wine-outline';
    if (type.includes('cafe') || type.includes('coffee')) return 'cafe-outline';
    if (type.includes('park') || type.includes('garden')) return 'leaf-outline';
    if (type.includes('shop') || type.includes('store')) return 'bag-outline';
    if (type.includes('museum') || type.includes('gallery')) return 'color-palette-outline';
    return 'location-outline';
  };

  return (
    <View style={s.container}>
      {/* ── Header ── */}
      <View style={[s.header, { paddingTop: insets.top + 8 }]}>
        <View style={s.headerTop}>
          <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
            <Ionicons name="arrow-back" size={20} color="#1A1A1A" />
          </TouchableOpacity>
          <Text style={s.headerTitle}>My Spots</Text>
          <View style={{ width: 40 }} />
        </View>

        {/* View Mode Toggle */}
        <View style={s.viewToggle}>
          <TouchableOpacity
            style={[s.toggleBtn, viewMode === 'places' && s.toggleActive]}
            onPress={() => setViewMode('places')}
          >
            <Ionicons name="location-outline" size={15} color={viewMode === 'places' ? '#FFF' : '#999'} />
            <Text style={[s.toggleText, viewMode === 'places' && s.toggleTextActive]}>Places</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[s.toggleBtn, viewMode === 'posts' && s.toggleActive]}
            onPress={() => setViewMode('posts')}
          >
            <Ionicons name="bookmark-outline" size={15} color={viewMode === 'posts' ? '#FFF' : '#999'} />
            <Text style={[s.toggleText, viewMode === 'posts' && s.toggleTextActive]}>Saved Posts</Text>
          </TouchableOpacity>
        </View>
      </View>

      {/* ── Tab Filter (Places only) ── */}
      {viewMode === 'places' && (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.tabRow}>
          {TABS.map(tab => (
            <TouchableOpacity
              key={tab.key}
              style={[s.tabChip, activeTab === tab.key && { backgroundColor: tab.color, borderColor: tab.color }]}
              onPress={() => setActiveTab(tab.key)}
            >
              <Ionicons
                name={tab.icon as any}
                size={14}
                color={activeTab === tab.key ? '#FFF' : '#888'}
              />
              <Text style={[s.tabText, activeTab === tab.key && s.tabTextActive]}>
                {tab.label}
              </Text>
            </TouchableOpacity>
          ))}
        </ScrollView>
      )}

      {/* ── Content ── */}
      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
        contentContainerStyle={{ paddingBottom: 40, flexGrow: 1 }}
      >
        {isLoading ? (
          <View style={s.loadingWrap}>
            <ActivityIndicator size="large" color="#1A1A1A" />
          </View>
        ) : viewMode === 'places' ? (
          // ── Places View ──
          filteredPlaces.length === 0 ? (
            <View style={s.emptyState}>
              <View style={s.emptyIcon}>
                <Ionicons name="location-outline" size={32} color="#CCC" />
              </View>
              <Text style={s.emptyTitle}>
                {activeTab === 'all' ? 'No saved spots yet' : `No ${TABS.find(t => t.key === activeTab)?.label} spots`}
              </Text>
              <Text style={s.emptySub}>
                Save places from your feed and map to see them here
              </Text>
            </View>
          ) : (
            <View style={s.listWrap}>
              {filteredPlaces.map((place) => (
                <TouchableOpacity
                  key={place.id}
                  style={s.placeCard}
                  activeOpacity={0.85}
                >
                  <View style={[s.placeIcon, { backgroundColor: getSaveTypeColor(place.save_type) + '15' }]}>
                    <Ionicons
                      name={getPlaceTypeIcon(place.place_type) as any}
                      size={20}
                      color={getSaveTypeColor(place.save_type)}
                    />
                  </View>
                  <View style={s.placeInfo}>
                    <Text style={s.placeName} numberOfLines={1}>{place.place_name || 'Unnamed Place'}</Text>
                    <View style={s.placeMeta}>
                      <View style={s.saveTypeBadge}>
                        <Ionicons
                          name={getSaveTypeIcon(place.save_type) as any}
                          size={10}
                          color={getSaveTypeColor(place.save_type)}
                        />
                        <Text style={[s.saveTypeText, { color: getSaveTypeColor(place.save_type) }]}>
                          {place.save_type === 'want_to_go' ? 'Want to go'
                            : place.save_type === 'favorite' ? 'Favorite'
                            : place.save_type === 'been_there' ? 'Been there'
                            : 'Saved'}
                        </Text>
                      </View>
                      {place.place_type ? (
                        <Text style={s.placeType}>{place.place_type}</Text>
                      ) : null}
                    </View>
                  </View>
                  <TouchableOpacity
                    style={s.removeBtn}
                    onPress={() => handleRemovePlace(place.place_id)}
                  >
                    <Ionicons name="close" size={16} color="#BBB" />
                  </TouchableOpacity>
                </TouchableOpacity>
              ))}
            </View>
          )
        ) : (
          // ── Saved Posts View ──
          savedPosts.length === 0 ? (
            <View style={s.emptyState}>
              <View style={s.emptyIcon}>
                <Ionicons name="bookmark-outline" size={32} color="#CCC" />
              </View>
              <Text style={s.emptyTitle}>No saved posts yet</Text>
              <Text style={s.emptySub}>
                Bookmark posts from your feed to save them here
              </Text>
            </View>
          ) : (
            <View style={s.listWrap}>
              {savedPosts.map((post) => {
                const postImg = post.image || (post.images ? JSON.parse(post.images || '[]')[0] : null);
                return (
                  <TouchableOpacity
                    key={post.id}
                    style={s.postCard}
                    activeOpacity={0.85}
                    onPress={() => router.push(`/post/${post.post_id}` as any)}
                  >
                    {postImg ? (
                      <Image source={{ uri: postImg }} style={s.postThumb} />
                    ) : (
                      <View style={[s.postThumb, s.postThumbEmpty]}>
                        <Ionicons name="image-outline" size={20} color="#CCC" />
                      </View>
                    )}
                    <View style={s.postInfo}>
                      <Text style={s.postContent} numberOfLines={2}>
                        {post.content || 'No caption'}
                      </Text>
                      <View style={s.postMeta}>
                        {post.profile_image ? (
                          <Image source={{ uri: post.profile_image }} style={s.postAvatar} />
                        ) : (
                          <View style={[s.postAvatar, s.postAvatarFallback]}>
                            <Text style={s.postAvatarInit}>{(post.full_name || 'U')[0]}</Text>
                          </View>
                        )}
                        <Text style={s.postAuthor} numberOfLines={1}>{post.full_name}</Text>
                        <View style={s.postLikes}>
                          <Ionicons name="heart" size={10} color="#DC2626" />
                          <Text style={s.postLikesText}>{post.likes_count}</Text>
                        </View>
                      </View>
                    </View>
                    <TouchableOpacity
                      style={s.removeBtn}
                      onPress={() => handleRemovePost(post.post_id)}
                    >
                      <Ionicons name="close" size={16} color="#BBB" />
                    </TouchableOpacity>
                  </TouchableOpacity>
                );
              })}
            </View>
          )
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FAFAF8' },

  // Header
  header: { backgroundColor: '#FFF', borderBottomWidth: 1, borderBottomColor: '#ECEAE3', paddingBottom: 12 },
  headerTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, marginBottom: 12 },
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#F5F0EB', justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 20, fontWeight: '800', color: '#1A1A1A', letterSpacing: -0.3 },

  // View toggle
  viewToggle: {
    flexDirection: 'row', marginHorizontal: 16,
    backgroundColor: '#F5F0EB', borderRadius: 12, padding: 3,
  },
  toggleBtn: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: 6, paddingVertical: 8, borderRadius: 10,
  },
  toggleActive: { backgroundColor: '#1A1A1A' },
  toggleText: { fontSize: 13, fontWeight: '600', color: '#999' },
  toggleTextActive: { color: '#FFF' },

  // Tab filter
  tabRow: { paddingHorizontal: 16, paddingVertical: 12, gap: 8, alignItems: 'center' },
  tabChip: {
    flexDirection: 'row', alignItems: 'center', alignSelf: 'center', gap: 6,
    paddingHorizontal: 14, paddingVertical: 8, height: 36,
    borderRadius: 20, borderWidth: 1, borderColor: '#E8E4DF',
    backgroundColor: '#FFF',
  },
  tabText: { fontSize: 13, fontWeight: '600', color: '#888' },
  tabTextActive: { color: '#FFF' },

  // Loading
  loadingWrap: { flex: 1, justifyContent: 'center', alignItems: 'center', paddingVertical: 80 },

  // Empty
  emptyState: { alignItems: 'center', paddingVertical: 60, paddingHorizontal: 40 },
  emptyIcon: {
    width: 72, height: 72, borderRadius: 36,
    backgroundColor: '#F5F0EB', justifyContent: 'center', alignItems: 'center', marginBottom: 16,
  },
  emptyTitle: { fontSize: 18, fontWeight: '700', color: '#1A1A1A', marginBottom: 6 },
  emptySub: { fontSize: 14, color: '#999', textAlign: 'center', lineHeight: 20 },

  // List
  listWrap: { paddingHorizontal: 16, paddingTop: 4 },

  // Place Card
  placeCard: {
    flexDirection: 'row', alignItems: 'center', padding: 14,
    backgroundColor: '#FFF', borderRadius: 16, marginBottom: 8,
    borderWidth: 1, borderColor: '#F0EDE7',
  },
  placeIcon: {
    width: 44, height: 44, borderRadius: 14,
    justifyContent: 'center', alignItems: 'center', marginRight: 12,
  },
  placeInfo: { flex: 1 },
  placeName: { fontSize: 15, fontWeight: '700', color: '#1A1A1A', marginBottom: 4 },
  placeMeta: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  saveTypeBadge: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  saveTypeText: { fontSize: 11, fontWeight: '600' },
  placeType: { fontSize: 11, color: '#AAA' },
  removeBtn: {
    width: 32, height: 32, borderRadius: 16,
    justifyContent: 'center', alignItems: 'center',
  },

  // Post Card
  postCard: {
    flexDirection: 'row', alignItems: 'center', padding: 10,
    backgroundColor: '#FFF', borderRadius: 16, marginBottom: 8,
    borderWidth: 1, borderColor: '#F0EDE7',
  },
  postThumb: {
    width: 64, height: 64, borderRadius: 12, marginRight: 12,
    backgroundColor: '#F5F0EB',
  },
  postThumbEmpty: { justifyContent: 'center', alignItems: 'center' },
  postInfo: { flex: 1 },
  postContent: { fontSize: 14, fontWeight: '600', color: '#1A1A1A', lineHeight: 19, marginBottom: 6 },
  postMeta: { flexDirection: 'row', alignItems: 'center' },
  postAvatar: { width: 18, height: 18, borderRadius: 9, marginRight: 6 },
  postAvatarFallback: { backgroundColor: '#E8E4DF', justifyContent: 'center', alignItems: 'center' },
  postAvatarInit: { fontSize: 8, fontWeight: '700', color: '#AAA' },
  postAuthor: { fontSize: 11, color: '#999', flex: 1 },
  postLikes: { flexDirection: 'row', alignItems: 'center', gap: 3 },
  postLikesText: { fontSize: 11, color: '#999' },
});
