import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Image,
  ActivityIndicator,
  FlatList,
  RefreshControl,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, borderRadius, shadows } from '../../src/utils/theme';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';

const TABS = [
  { id: 'foryou', label: 'For you' },
  { id: 'culture', label: 'Culture' },
  { id: 'science', label: 'Science' },
  { id: 'featured', label: 'Featured', badge: 'New' },
  { id: 'daily', label: 'Daily' },
];

// Mock discover articles
const MOCK_ARTICLES = [
  { id: '1', title: 'The Rise of Sustainable Fashion in NYC', category: 'Culture', summary: 'How New York\'s fashion scene is embracing eco-friendly materials and ethical production.', image: 'https://images.unsplash.com/photo-1558618666-fcd25c85f82e?w=400', author: 'StyleWatch', date: 'Jun 15' },
  { id: '2', title: 'Understanding Urban Architecture', category: 'Science', summary: 'Modern buildings are not just structures — they are living, breathing ecosystems.', image: 'https://images.unsplash.com/photo-1486325212027-8081e485255e?w=400', author: 'ArchDigest', date: 'Jun 14' },
  { id: '3', title: 'Local Music Scene Thriving in Brooklyn', category: 'Culture', summary: 'From jazz clubs to underground hip-hop, Brooklyn\'s music scene is exploding.', image: 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=400', author: 'BKMusic', date: 'Jun 13' },
  { id: '4', title: 'Tech Startups Changing the Bronx', category: 'Featured', summary: 'Young entrepreneurs are building the next big thing right from their neighborhoods.', image: 'https://images.unsplash.com/photo-1519389950473-47ba0277781c?w=400', author: 'TechBX', date: 'Jun 12' },
  { id: '5', title: 'Best Coffee Spots This Week', category: 'Daily', summary: 'Our curated list of the top coffee experiences in your area.', image: 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=400', author: 'CoffeeGuide', date: 'Today' },
];

function ArticleCard({ article }: { article: any }) {
  return (
    <TouchableOpacity style={articleStyles.card} activeOpacity={0.9}>
      <View style={articleStyles.textContent}>
        <Text style={articleStyles.category}>{article.category}</Text>
        <Text style={articleStyles.title} numberOfLines={2}>{article.title}</Text>
        <Text style={articleStyles.summary} numberOfLines={2}>{article.summary}</Text>
        <View style={articleStyles.meta}>
          <Text style={articleStyles.author}>{article.author}</Text>
          <Text style={articleStyles.dot}>·</Text>
          <Text style={articleStyles.date}>{article.date}</Text>
        </View>
      </View>
      {article.image && (
        <Image source={{ uri: article.image }} style={articleStyles.image} />
      )}
    </TouchableOpacity>
  );
}

const articleStyles = StyleSheet.create({
  card: {
    flexDirection: 'row',
    backgroundColor: colors.bgCard,
    borderRadius: 20,
    padding: 16,
    marginHorizontal: 16,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation1,
  },
  textContent: {
    flex: 1,
    paddingRight: 12,
  },
  category: {
    fontSize: 11,
    fontWeight: '700',
    color: colors.accentSecondary,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    marginBottom: 6,
  },
  title: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.textPrimary,
    lineHeight: 22,
    marginBottom: 6,
  },
  summary: {
    fontSize: 13,
    color: colors.textSecondary,
    lineHeight: 18,
    marginBottom: 8,
  },
  meta: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  author: {
    fontSize: 12,
    fontWeight: '600',
    color: colors.textHint,
  },
  dot: {
    fontSize: 12,
    color: colors.textHint,
    marginHorizontal: 6,
  },
  date: {
    fontSize: 12,
    color: colors.textHint,
  },
  image: {
    width: 90,
    height: 90,
    borderRadius: 14,
  },
});

export default function DiscoverScreen() {
  const router = useRouter();
  const { user } = useAuthStore();
  const [activeTab, setActiveTab] = useState('foryou');
  const [neighborhood, setNeighborhood] = useState('Your Area');
  const [isRefreshing, setIsRefreshing] = useState(false);

  const filtered = activeTab === 'foryou'
    ? MOCK_ARTICLES
    : MOCK_ARTICLES.filter(a => a.category.toLowerCase() === activeTab);

  const onRefresh = async () => {
    setIsRefreshing(true);
    await new Promise(r => setTimeout(r, 1000));
    setIsRefreshing(false);
  };

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <View style={styles.topRow}>
          <TouchableOpacity style={styles.locationBtn}>
            <View style={styles.locationIcon}>
              <Ionicons name="location" size={14} color={colors.accentPrimary} />
            </View>
            <Text style={styles.locationText}>{neighborhood}</Text>
            <Ionicons name="chevron-down" size={16} color={colors.textSecondary} />
          </TouchableOpacity>
          <View style={styles.headerActions}>
            <TouchableOpacity style={styles.iconBtn}>
              <Ionicons name="notifications-outline" size={20} color={colors.textSecondary} />
            </TouchableOpacity>
            <TouchableOpacity style={styles.iconBtn}>
              <Ionicons name="chatbubble-outline" size={20} color={colors.textSecondary} />
            </TouchableOpacity>
            {user && (
              <View style={styles.avatarSmall}>
                {user.profile_image ? (
                  <Image source={{ uri: user.profile_image }} style={{ width: '100%', height: '100%' }} />
                ) : (
                  <Text style={styles.avatarSmallText}>
                    {(user.full_name || 'U')[0].toUpperCase()}
                  </Text>
                )}
              </View>
            )}
          </View>
        </View>

        {/* Tabs */}
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.tabsRow}
        >
          {TABS.map((tab) => (
            <TouchableOpacity
              key={tab.id}
              style={[
                styles.tab,
                activeTab === tab.id && styles.tabActive,
              ]}
              onPress={() => setActiveTab(tab.id)}
            >
              <Text style={[
                styles.tabText,
                activeTab === tab.id && styles.tabTextActive,
              ]}>
                {tab.label}
              </Text>
              {tab.badge && (
                <View style={styles.tabBadge}>
                  <Text style={styles.tabBadgeText}>{tab.badge}</Text>
                </View>
              )}
            </TouchableOpacity>
          ))}
        </ScrollView>
      </View>

      {/* Feed */}
      <FlatList
        data={filtered}
        keyExtractor={(item) => item.id}
        renderItem={({ item }) => <ArticleCard article={item} />}
        contentContainerStyle={{ paddingTop: 12, paddingBottom: 100 }}
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={onRefresh}
            tintColor={colors.accentPrimary}
          />
        }
        ListEmptyComponent={
          <View style={styles.emptyState}>
            <Text style={{ fontSize: 48, marginBottom: 12 }}>📰</Text>
            <Text style={styles.emptyTitle}>No articles yet</Text>
            <Text style={styles.emptyText}>Check back soon for updates</Text>
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
    backgroundColor: colors.bgApp,
  },
  header: {
    backgroundColor: colors.bgCard,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderLight,
  },
  topRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  locationBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  locationIcon: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: colors.accentPrimaryLight,
    justifyContent: 'center',
    alignItems: 'center',
  },
  locationText: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  iconBtn: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: colors.bgSubtle,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarSmall: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: colors.accentPrimary,
    justifyContent: 'center',
    alignItems: 'center',
    overflow: 'hidden',
  },
  avatarSmallText: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '700',
  },
  tabsRow: {
    paddingHorizontal: 12,
    gap: 0,
  },
  tab: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  tabActive: {
    borderBottomColor: colors.textPrimary,
  },
  tabText: {
    fontSize: 14,
    fontWeight: '500',
    color: colors.textHint,
  },
  tabTextActive: {
    fontWeight: '700',
    color: colors.textPrimary,
  },
  tabBadge: {
    backgroundColor: '#16A34A',
    borderRadius: 8,
    paddingHorizontal: 6,
    paddingVertical: 2,
  },
  tabBadgeText: {
    fontSize: 10,
    fontWeight: '700',
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
  },
  emptyText: {
    fontSize: 13,
    color: colors.textHint,
    marginTop: 4,
  },
});
