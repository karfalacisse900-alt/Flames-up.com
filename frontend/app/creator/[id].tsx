import React, { useState, useEffect } from 'react';
import {
  View, Text, StyleSheet, ScrollView, TouchableOpacity, Image,
  Dimensions, ActivityIndicator, Linking, FlatList,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../../src/utils/theme';
import api from '../../src/api/client';

const { width: SW } = Dimensions.get('window');
const PORTFOLIO_SIZE = (SW - 48 - 8) / 3;

const AVAILABILITY_MAP: Record<string, { label: string; color: string; bg: string }> = {
  available: { label: 'Available', color: '#16A34A', bg: '#DCFCE7' },
  busy: { label: 'Busy', color: '#F59E0B', bg: '#FEF3C7' },
  offline: { label: 'Offline', color: '#9CA3AF', bg: '#F3F4F6' },
};

export default function CreatorDetailScreen() {
  const router = useRouter();
  const { id } = useLocalSearchParams<{ id: string }>();
  const [creator, setCreator] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'about' | 'portfolio'>('about');

  useEffect(() => { loadCreator(); }, [id]);

  const loadCreator = async () => {
    try {
      const res = await api.get(`/creators/${id}`);
      setCreator(res.data);
    } catch {
      setCreator(null);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <SafeAreaView style={s.container} edges={['top']}>
        <View style={s.loadingWrap}>
          <ActivityIndicator size="large" color={colors.accentPrimary} />
        </View>
      </SafeAreaView>
    );
  }

  if (!creator) {
    return (
      <SafeAreaView style={s.container} edges={['top']}>
        <View style={s.header}>
          <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
            <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
          </TouchableOpacity>
          <Text style={s.headerTitle}>Creator</Text>
          <View style={{ width: 44 }} />
        </View>
        <View style={s.loadingWrap}>
          <Ionicons name="alert-circle-outline" size={48} color={colors.textHint} />
          <Text style={{ fontSize: 16, color: colors.textHint, marginTop: 8 }}>Creator not found</Text>
        </View>
      </SafeAreaView>
    );
  }

  const avail = AVAILABILITY_MAP[creator.availability_status] || AVAILABILITY_MAP.offline;
  const portfolioLinks = creator.portfolio_links || [];
  const portfolio = creator.portfolio || [];

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={s.headerTitle}>Creator Profile</Text>
        <View style={{ width: 44 }} />
      </View>

      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingBottom: 60 }}>
        {/* Hero Card */}
        <View style={s.heroCard}>
          <View style={s.avatarWrap}>
            {creator.profile_image ? (
              <Image source={{ uri: creator.profile_image }} style={s.avatar} />
            ) : (
              <View style={[s.avatar, s.avatarPlaceholder]}>
                <Text style={s.avatarText}>{(creator.full_name || 'C')[0]}</Text>
              </View>
            )}
            <View style={[s.availDot, { backgroundColor: avail.color }]} />
          </View>

          <View style={s.nameWrap}>
            <Text style={s.name}>{creator.full_name}</Text>
            {creator.is_verified ? (
              <View style={s.verifiedBadge}>
                <Ionicons name="checkmark-circle" size={16} color={colors.accentPrimary} />
                <Text style={s.verifiedText}>Creator</Text>
              </View>
            ) : null}
          </View>

          <Text style={s.category}>{creator.category}</Text>

          <View style={[s.availChip, { backgroundColor: avail.bg }]}>
            <View style={[s.availCircle, { backgroundColor: avail.color }]} />
            <Text style={[s.availLabel, { color: avail.color }]}>{avail.label}</Text>
          </View>

          <View style={s.statsRow}>
            <View style={s.statItem}>
              <Text style={s.statNum}>{creator.followers_count || 0}</Text>
              <Text style={s.statLabel}>Followers</Text>
            </View>
            <View style={s.statDivider} />
            <View style={s.statItem}>
              <Text style={s.statNum}>{creator.posts_count || 0}</Text>
              <Text style={s.statLabel}>Posts</Text>
            </View>
            <View style={s.statDivider} />
            <View style={s.statItem}>
              <Text style={s.statNum}>{portfolio.length}</Text>
              <Text style={s.statLabel}>Portfolio</Text>
            </View>
          </View>

          {/* Action Buttons */}
          <View style={s.actionRow}>
            <TouchableOpacity
              style={s.msgBtn}
              onPress={() => router.push(`/conversation/${creator.user_id}` as any)}
            >
              <Ionicons name="chatbubble-outline" size={18} color="#FFFFFF" />
              <Text style={s.msgBtnText}>Message</Text>
            </TouchableOpacity>
            {creator.contact_link ? (
              <TouchableOpacity
                style={s.contactBtn}
                onPress={() => Linking.openURL(creator.contact_link)}
              >
                <Ionicons name="open-outline" size={18} color={colors.accentPrimary} />
              </TouchableOpacity>
            ) : null}
          </View>
        </View>

        {/* Pricing */}
        {creator.pricing_range ? (
          <View style={s.infoCard}>
            <Ionicons name="cash-outline" size={18} color={colors.accentPrimary} />
            <Text style={s.infoText}>Pricing: {creator.pricing_range}</Text>
          </View>
        ) : null}

        {/* Tabs */}
        <View style={s.tabRow}>
          <TouchableOpacity
            style={[s.tabItem, activeTab === 'about' && s.tabItemActive]}
            onPress={() => setActiveTab('about')}
          >
            <Text style={[s.tabLabel, activeTab === 'about' && s.tabLabelActive]}>About</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[s.tabItem, activeTab === 'portfolio' && s.tabItemActive]}
            onPress={() => setActiveTab('portfolio')}
          >
            <Text style={[s.tabLabel, activeTab === 'portfolio' && s.tabLabelActive]}>Portfolio</Text>
          </TouchableOpacity>
        </View>

        {activeTab === 'about' ? (
          <View style={s.sectionPad}>
            {creator.short_bio ? (
              <View style={s.bioCard}>
                <Text style={s.bioText}>{creator.short_bio}</Text>
              </View>
            ) : null}

            {creator.city ? (
              <View style={s.detailRow}>
                <Ionicons name="location-outline" size={16} color={colors.textHint} />
                <Text style={s.detailText}>{creator.city}{creator.borough ? `, ${creator.borough}` : ''}</Text>
              </View>
            ) : null}

            {portfolioLinks.length > 0 ? (
              <View style={s.linksCard}>
                <Text style={s.linksTitle}>Links</Text>
                {portfolioLinks.map((link: string, idx: number) => (
                  <TouchableOpacity key={idx} style={s.linkRow} onPress={() => Linking.openURL(link)}>
                    <Ionicons
                      name={link.includes('instagram') ? 'logo-instagram' : link.includes('tiktok') ? 'logo-tiktok' : 'globe-outline'}
                      size={18}
                      color={colors.accentPrimary}
                    />
                    <Text style={s.linkText} numberOfLines={1}>{link}</Text>
                    <Ionicons name="open-outline" size={14} color={colors.textHint} />
                  </TouchableOpacity>
                ))}
              </View>
            ) : null}
          </View>
        ) : (
          <View style={s.sectionPad}>
            {portfolio.length === 0 ? (
              <View style={s.emptyPortfolio}>
                <Ionicons name="images-outline" size={40} color={colors.textHint} />
                <Text style={s.emptyText}>No portfolio items yet</Text>
              </View>
            ) : (
              <View style={s.portfolioGrid}>
                {portfolio.map((item: any) => (
                  <TouchableOpacity key={item.id} style={s.portfolioItem}>
                    {item.image ? (
                      <Image source={{ uri: item.image }} style={s.portfolioImage} />
                    ) : (
                      <View style={[s.portfolioImage, { backgroundColor: colors.bgSubtle, justifyContent: 'center', alignItems: 'center' }]}>
                        <Ionicons name="document-text-outline" size={24} color={colors.textHint} />
                      </View>
                    )}
                  </TouchableOpacity>
                ))}
              </View>
            )}
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
  headerTitle: { fontSize: 18, fontWeight: '700', color: colors.textPrimary, fontStyle: 'italic' },
  loadingWrap: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  heroCard: { backgroundColor: colors.bgCard, margin: 16, borderRadius: 24, padding: 24, alignItems: 'center', borderWidth: 1, borderColor: colors.borderLight },
  avatarWrap: { position: 'relative', marginBottom: 12 },
  avatar: { width: 88, height: 88, borderRadius: 44, backgroundColor: colors.bgSubtle },
  avatarPlaceholder: { justifyContent: 'center', alignItems: 'center' },
  avatarText: { fontSize: 32, fontWeight: '800', color: colors.textHint },
  availDot: { position: 'absolute', bottom: 2, right: 2, width: 18, height: 18, borderRadius: 9, borderWidth: 3, borderColor: colors.bgCard },
  nameWrap: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  name: { fontSize: 22, fontWeight: '800', color: colors.textPrimary },
  verifiedBadge: { flexDirection: 'row', alignItems: 'center', gap: 3, backgroundColor: colors.accentPrimaryLight, paddingHorizontal: 8, paddingVertical: 3, borderRadius: 12 },
  verifiedText: { fontSize: 11, fontWeight: '700', color: colors.accentPrimary },
  category: { fontSize: 15, color: colors.accentPrimary, fontWeight: '600', marginTop: 4, textTransform: 'capitalize' },
  availChip: { flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 14, paddingVertical: 6, borderRadius: 20, marginTop: 10 },
  availCircle: { width: 8, height: 8, borderRadius: 4 },
  availLabel: { fontSize: 13, fontWeight: '600' },
  statsRow: { flexDirection: 'row', alignItems: 'center', marginTop: 20, gap: 4 },
  statItem: { alignItems: 'center', paddingHorizontal: 16 },
  statNum: { fontSize: 18, fontWeight: '800', color: colors.textPrimary },
  statLabel: { fontSize: 12, color: colors.textHint, marginTop: 2 },
  statDivider: { width: 1, height: 24, backgroundColor: colors.borderLight },
  actionRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 20, width: '100%' },
  msgBtn: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, backgroundColor: colors.accentPrimary, borderRadius: 16, paddingVertical: 14 },
  msgBtnText: { fontSize: 15, fontWeight: '700', color: '#FFFFFF' },
  contactBtn: { width: 48, height: 48, borderRadius: 16, backgroundColor: colors.accentPrimaryLight, justifyContent: 'center', alignItems: 'center' },
  infoCard: { flexDirection: 'row', alignItems: 'center', gap: 10, marginHorizontal: 16, backgroundColor: colors.bgCard, borderRadius: 16, padding: 16, borderWidth: 1, borderColor: colors.borderLight, marginBottom: 12 },
  infoText: { fontSize: 15, fontWeight: '500', color: colors.textPrimary },
  tabRow: { flexDirection: 'row', marginHorizontal: 16, borderBottomWidth: 1, borderBottomColor: colors.borderLight },
  tabItem: { flex: 1, paddingVertical: 14, alignItems: 'center' },
  tabItemActive: { borderBottomWidth: 2, borderBottomColor: colors.accentPrimary },
  tabLabel: { fontSize: 15, fontWeight: '600', color: colors.textHint },
  tabLabelActive: { color: colors.accentPrimary },
  sectionPad: { padding: 16 },
  bioCard: { backgroundColor: colors.bgCard, borderRadius: 20, padding: 20, borderWidth: 1, borderColor: colors.borderLight, marginBottom: 12 },
  bioText: { fontSize: 15, color: colors.textSecondary, lineHeight: 23 },
  detailRow: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 12 },
  detailText: { fontSize: 14, color: colors.textSecondary },
  linksCard: { backgroundColor: colors.bgCard, borderRadius: 20, padding: 16, borderWidth: 1, borderColor: colors.borderLight },
  linksTitle: { fontSize: 15, fontWeight: '700', color: colors.textPrimary, marginBottom: 8 },
  linkRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 10, borderTopWidth: 1, borderTopColor: colors.borderSubtle },
  linkText: { flex: 1, fontSize: 14, color: colors.accentPrimary },
  emptyPortfolio: { alignItems: 'center', paddingTop: 40 },
  emptyText: { fontSize: 15, color: colors.textHint, marginTop: 8 },
  portfolioGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 4 },
  portfolioItem: { width: PORTFOLIO_SIZE, height: PORTFOLIO_SIZE },
  portfolioImage: { width: '100%', height: '100%', borderRadius: 8 },
});
