import React, { useState, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Image,
  Dimensions,
  TextInput,
  FlatList,
  ActivityIndicator,
  Modal,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, borderRadius, shadows } from '../../src/utils/theme';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const COLUMN_GAP = 12;
const COLUMN_WIDTH = (SCREEN_WIDTH - 16 * 2 - COLUMN_GAP) / 2;

const STYLE_CATEGORIES = ['All', 'Casual', 'Bohemian', 'Grunge', 'Chic', 'Streetwear', 'Vintage', 'Minimalist', 'Sporty', 'Glam'];

// Mock fashion data for visual demonstration
const MOCK_FASHION: any[] = [
  { id: '1', title: 'The Fashion Killer', style: 'Vintage', description: 'Fashion Killa" is slang for a person with an impeccable, daring, and trend-setting sense of style, often referencing someone who....', image_url: 'https://images.unsplash.com/photo-1509631179647-0177331693ae?w=400', like_count: 24, author_name: 'StyleGuru' },
  { id: '2', title: 'Street Dreams', style: 'Streetwear', description: 'Urban fashion at its finest. Mixing high-end with street culture.', image_url: 'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?w=400', like_count: 18, author_name: 'UrbanFit' },
  { id: '3', title: 'Boho Vibes', style: 'Bohemian', description: 'Free-spirited fashion that flows with the wind.', image_url: 'https://images.unsplash.com/photo-1496747611176-843222e1e57c?w=400', like_count: 31, author_name: 'BohoQueen' },
  { id: '4', title: 'Minimalist Edit', style: 'Minimalist', description: 'Less is more. Clean lines and neutral tones.', image_url: 'https://images.unsplash.com/photo-1487222477894-8943e31ef7b2?w=400', like_count: 12, author_name: 'CleanCut' },
  { id: '5', title: 'Glam Night Out', style: 'Glam', description: 'Sparkle and shine for the evening.', image_url: 'https://images.unsplash.com/photo-1518577915332-c2a19f149a75?w=400', like_count: 45, author_name: 'GlamLife' },
  { id: '6', title: 'Casual Friday', style: 'Casual', description: 'Effortless everyday style.', image_url: 'https://images.unsplash.com/photo-1495385794356-15371f348c31?w=400', like_count: 8, author_name: 'DailyWear' },
  { id: '7', title: 'Sporty Chic', style: 'Sporty', description: 'Athletic meets fashion-forward.', image_url: 'https://images.unsplash.com/photo-1483985988355-763728e1935b?w=400', like_count: 22, author_name: 'FitFash' },
  { id: '8', title: 'Grunge Revival', style: 'Grunge', description: 'Raw and unapologetic.', image_url: 'https://images.unsplash.com/photo-1509631179647-0177331693ae?w=400', like_count: 15, author_name: 'GrungeKid' },
];

// ── Fashion Card (Masonry) ─────────────────────────────────────
function FashionCard({ post, onPress, tall }: { post: any; onPress: () => void; tall: boolean }) {
  return (
    <TouchableOpacity
      style={[cardStyles.card, { height: tall ? 280 : 200 }]}
      onPress={onPress}
      activeOpacity={0.9}
    >
      <Image source={{ uri: post.image_url }} style={cardStyles.cardImage} />
      <View style={cardStyles.cardOverlay} />
      <View style={cardStyles.cardContent}>
        <Text style={cardStyles.cardTitle} numberOfLines={2}>{post.title}</Text>
        <Text style={cardStyles.cardStyle}>{post.style}</Text>
      </View>
      {/* Like badge */}
      <View style={cardStyles.likeBadge}>
        <Ionicons name="heart" size={12} color="#FFFFFF" />
        <Text style={cardStyles.likeCount}>{post.like_count || 0}</Text>
      </View>
    </TouchableOpacity>
  );
}

const cardStyles = StyleSheet.create({
  card: {
    borderRadius: 20,
    overflow: 'hidden',
    marginBottom: 12,
    backgroundColor: colors.fashionCard,
  },
  cardImage: {
    width: '100%',
    height: '100%',
    position: 'absolute',
  },
  cardOverlay: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: '55%',
    backgroundColor: 'rgba(0,0,0,0.5)',
  },
  cardContent: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    padding: 12,
  },
  cardTitle: {
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: '700',
    lineHeight: 16,
  },
  cardStyle: {
    color: 'rgba(255,255,255,0.65)',
    fontSize: 10,
    fontWeight: '500',
    marginTop: 2,
  },
  likeBadge: {
    position: 'absolute',
    top: 8,
    right: 8,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    backgroundColor: 'rgba(0,0,0,0.4)',
    borderRadius: 12,
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  likeCount: {
    color: '#FFFFFF',
    fontSize: 10,
    fontWeight: '600',
  },
});

// ── Trending Card ──────────────────────────────────────────────
function TrendingCard({ post, onPress }: { post: any; onPress: () => void }) {
  return (
    <TouchableOpacity style={trendStyles.card} onPress={onPress} activeOpacity={0.9}>
      <Image source={{ uri: post.image_url }} style={trendStyles.image} />
      <View style={trendStyles.overlay} />
      <View style={trendStyles.content}>
        <Text style={trendStyles.title} numberOfLines={2}>{post.title}</Text>
        <Text style={trendStyles.style}>{post.style}</Text>
      </View>
      <View style={trendStyles.likeBadge}>
        <Ionicons name="heart" size={12} color="#f87171" />
        <Text style={trendStyles.likeCount}>{post.like_count || 0}</Text>
      </View>
    </TouchableOpacity>
  );
}

const trendStyles = StyleSheet.create({
  card: {
    width: 160,
    height: 230,
    borderRadius: 24,
    overflow: 'hidden',
    backgroundColor: colors.fashionCard,
    marginRight: 12,
  },
  image: {
    width: '100%',
    height: '100%',
    position: 'absolute',
  },
  overlay: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: '50%',
    backgroundColor: 'rgba(0,0,0,0.6)',
  },
  content: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    padding: 12,
  },
  title: {
    color: '#FFFFFF',
    fontSize: 11,
    fontWeight: '700',
    lineHeight: 15,
  },
  style: {
    color: 'rgba(255,255,255,0.6)',
    fontSize: 10,
    marginTop: 2,
  },
  likeBadge: {
    position: 'absolute',
    top: 10,
    left: 10,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: 'rgba(0,0,0,0.45)',
    borderRadius: 12,
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  likeCount: {
    color: '#FFFFFF',
    fontSize: 10,
    fontWeight: '700',
  },
});

// ── Detail View ────────────────────────────────────────────────
function PostDetail({ post, onClose }: { post: any; onClose: () => void }) {
  const [liked, setLiked] = useState(false);
  const [saved, setSaved] = useState(false);

  return (
    <Modal visible animationType="slide" presentationStyle="fullScreen">
      <View style={detailStyles.container}>
        <ScrollView bounces={false}>
          {/* Image */}
          <View style={detailStyles.imageContainer}>
            <Image source={{ uri: post.image_url }} style={detailStyles.image} />
            <TouchableOpacity style={detailStyles.backBtn} onPress={onClose}>
              <Ionicons name="arrow-back" size={20} color="#FFFFFF" />
            </TouchableOpacity>
          </View>

          {/* Content */}
          <View style={detailStyles.content}>
            <View style={detailStyles.titleRow}>
              <View style={{ flex: 1 }}>
                <Text style={detailStyles.title}>{post.title}</Text>
                <View style={detailStyles.stylePill}>
                  <Text style={detailStyles.styleText}>{post.style}</Text>
                </View>
              </View>
              <View style={detailStyles.actionBtns}>
                <TouchableOpacity
                  style={[detailStyles.actionBtn, liked && { backgroundColor: '#FEE2E2' }]}
                  onPress={() => setLiked(!liked)}
                >
                  <Ionicons
                    name={liked ? 'heart' : 'heart-outline'}
                    size={20}
                    color={liked ? '#EF4444' : colors.fashionHint}
                  />
                </TouchableOpacity>
                <TouchableOpacity
                  style={[detailStyles.actionBtn, saved && { backgroundColor: '#D8F3DC' }]}
                  onPress={() => setSaved(!saved)}
                >
                  <Ionicons
                    name={saved ? 'bookmark' : 'bookmark-outline'}
                    size={20}
                    color={saved ? '#2D6A4F' : colors.fashionHint}
                  />
                </TouchableOpacity>
              </View>
            </View>

            {post.description && (
              <Text style={detailStyles.description}>{post.description}</Text>
            )}

            {/* Author */}
            <View style={detailStyles.authorRow}>
              <View style={detailStyles.authorAvatar}>
                <Text style={detailStyles.authorInitial}>
                  {(post.author_name || 'U')[0].toUpperCase()}
                </Text>
              </View>
              <Text style={detailStyles.authorName}>{post.author_name}</Text>
              <View style={{ flex: 1 }} />
              <Ionicons name="heart-outline" size={14} color={colors.fashionHint} />
              <Text style={detailStyles.likeText}>{post.like_count || 0}</Text>
            </View>
          </View>
        </ScrollView>
      </View>
    </Modal>
  );
}

const detailStyles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.fashionBg,
  },
  imageContainer: {
    width: '100%',
    aspectRatio: 4 / 5,
  },
  image: {
    width: '100%',
    height: '100%',
  },
  backBtn: {
    position: 'absolute',
    top: 50,
    left: 16,
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  content: {
    padding: 20,
  },
  titleRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    marginBottom: 16,
  },
  title: {
    fontSize: 22,
    fontWeight: '900',
    color: colors.fashionText,
    fontStyle: 'italic',
    lineHeight: 28,
  },
  stylePill: {
    backgroundColor: colors.fashionCard,
    alignSelf: 'flex-start',
    paddingHorizontal: 10,
    paddingVertical: 3,
    borderRadius: 12,
    marginTop: 8,
  },
  styleText: {
    fontSize: 12,
    fontWeight: '600',
    color: '#6B6355',
  },
  actionBtns: {
    flexDirection: 'row',
    gap: 8,
    marginLeft: 12,
  },
  actionBtn: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: colors.fashionCard,
    justifyContent: 'center',
    alignItems: 'center',
  },
  description: {
    fontSize: 14,
    color: '#4A3F2F',
    lineHeight: 22,
    marginBottom: 20,
  },
  authorRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingTop: 16,
    borderTopWidth: 1,
    borderTopColor: colors.fashionBorder,
  },
  authorAvatar: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: colors.fashionCard,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 8,
  },
  authorInitial: {
    fontSize: 14,
    fontWeight: '700',
    color: '#6B6355',
  },
  authorName: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.fashionText,
  },
  likeText: {
    fontSize: 12,
    color: colors.fashionHint,
    marginLeft: 4,
  },
});

// ── Main Fashion Feed ──────────────────────────────────────────
export default function FashionFeedScreen() {
  const [category, setCategory] = useState('All');
  const [search, setSearch] = useState('');
  const [selectedPost, setSelectedPost] = useState<any>(null);

  const filtered = MOCK_FASHION.filter((p) => {
    const matchCat = category === 'All' || p.style === category;
    const matchSearch = !search || p.title.toLowerCase().includes(search.toLowerCase());
    return matchCat && matchSearch;
  });

  const trending = [...filtered].sort((a, b) => (b.like_count || 0) - (a.like_count || 0)).slice(0, 6);
  const col1 = filtered.filter((_, i) => i % 2 === 0);
  const col2 = filtered.filter((_, i) => i % 2 === 1);

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingBottom: 100 }}>
        {/* Header */}
        <View style={styles.header}>
          <Text style={styles.headerTitle}>
            What's Your{'\n'}Favorite Style?
          </Text>
        </View>

        {/* Search */}
        <View style={styles.searchContainer}>
          <View style={styles.searchBar}>
            <Ionicons name="search" size={16} color={colors.fashionHint} />
            <TextInput
              style={styles.searchInput}
              placeholder="Search styles..."
              placeholderTextColor={colors.fashionHint}
              value={search}
              onChangeText={setSearch}
            />
            {search.length > 0 && (
              <TouchableOpacity onPress={() => setSearch('')}>
                <Ionicons name="close" size={16} color={colors.fashionHint} />
              </TouchableOpacity>
            )}
          </View>
        </View>

        {/* Category chips */}
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.chipRow}
        >
          {STYLE_CATEGORIES.map((cat) => (
            <TouchableOpacity
              key={cat}
              style={[styles.chip, category === cat && styles.chipActive]}
              onPress={() => setCategory(cat)}
            >
              <Text style={[styles.chipText, category === cat && styles.chipTextActive]}>
                {cat}
              </Text>
            </TouchableOpacity>
          ))}
        </ScrollView>

        {filtered.length === 0 ? (
          <View style={styles.emptyState}>
            <Text style={{ fontSize: 48, marginBottom: 12 }}>👗</Text>
            <Text style={styles.emptyTitle}>No looks yet</Text>
            <Text style={styles.emptyText}>Be the first to share your style!</Text>
          </View>
        ) : (
          <>
            {/* Trending section */}
            {trending.length > 0 && (
              <View style={styles.trendingSection}>
                <View style={styles.sectionHeader}>
                  <Text style={styles.sectionTitle}>Trending Now 🔥</Text>
                  <Text style={styles.sectionHint}>Swipe to explore</Text>
                </View>
                <ScrollView
                  horizontal
                  showsHorizontalScrollIndicator={false}
                  contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 4 }}
                >
                  {trending.map((post) => (
                    <TrendingCard
                      key={post.id}
                      post={post}
                      onPress={() => setSelectedPost(post)}
                    />
                  ))}
                </ScrollView>
              </View>
            )}

            {/* Popular label */}
            <View style={styles.popularHeader}>
              <Text style={styles.sectionTitle}>Popular</Text>
            </View>

            {/* Masonry Grid */}
            <View style={styles.masonryContainer}>
              <View style={styles.masonryColumn}>
                {col1.map((post, i) => (
                  <FashionCard
                    key={post.id}
                    post={post}
                    onPress={() => setSelectedPost(post)}
                    tall={i % 3 === 0}
                  />
                ))}
              </View>
              <View style={[styles.masonryColumn, { marginTop: 40 }]}>
                {col2.map((post, i) => (
                  <FashionCard
                    key={post.id}
                    post={post}
                    onPress={() => setSelectedPost(post)}
                    tall={i % 3 === 1}
                  />
                ))}
              </View>
            </View>
          </>
        )}
      </ScrollView>

      {/* FAB */}
      <TouchableOpacity style={styles.fab} activeOpacity={0.8}>
        <Ionicons name="add" size={24} color="#FFFFFF" />
      </TouchableOpacity>

      {/* Detail View */}
      {selectedPost && (
        <PostDetail
          post={selectedPost}
          onClose={() => setSelectedPost(null)}
        />
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.fashionBg,
  },
  header: {
    paddingHorizontal: 20,
    paddingTop: 12,
    paddingBottom: 12,
  },
  headerTitle: {
    fontSize: 30,
    fontWeight: '900',
    color: colors.fashionText,
    fontStyle: 'italic',
    lineHeight: 36,
  },
  searchContainer: {
    paddingHorizontal: 16,
    marginBottom: 12,
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 16,
    backgroundColor: '#FFFFFF',
    borderWidth: 1,
    borderColor: colors.fashionCard,
  },
  searchInput: {
    flex: 1,
    fontSize: 14,
    color: colors.fashionText,
  },
  chipRow: {
    paddingHorizontal: 16,
    gap: 6,
    marginBottom: 20,
  },
  chip: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: 'rgba(28,26,22,0.07)',
  },
  chipActive: {
    backgroundColor: colors.fashionText,
  },
  chipText: {
    fontSize: 12,
    fontWeight: '700',
    color: '#6B6355',
  },
  chipTextActive: {
    color: '#FFFFFF',
  },
  trendingSection: {
    marginBottom: 24,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    marginBottom: 12,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '900',
    color: colors.fashionText,
    fontStyle: 'italic',
  },
  sectionHint: {
    fontSize: 12,
    fontWeight: '600',
    color: colors.fashionHint,
  },
  popularHeader: {
    paddingHorizontal: 20,
    marginBottom: 12,
  },
  masonryContainer: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    gap: COLUMN_GAP,
  },
  masonryColumn: {
    flex: 1,
  },
  emptyState: {
    alignItems: 'center',
    paddingVertical: 60,
  },
  emptyTitle: {
    fontSize: 14,
    fontWeight: '700',
    color: colors.fashionText,
  },
  emptyText: {
    fontSize: 12,
    color: colors.fashionHint,
    marginTop: 4,
  },
  fab: {
    position: 'absolute',
    bottom: 24,
    right: 20,
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: colors.fashionText,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.3,
    shadowRadius: 16,
    elevation: 8,
  },
});
