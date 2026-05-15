import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Dimensions,
  Image,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import api from '../../src/api/client';
import { colors } from '../../src/utils/theme';
import { openSafeUrl } from '../../src/utils/safeLinking';

let WebView: any = null;
try {
  WebView = require('react-native-webview').WebView;
} catch {}

const { width: SCREEN_WIDTH } = Dimensions.get('window');

type Recommendation = {
  id: string;
  title: string;
  description?: string;
  category?: string;
  tags?: string[];
  external_url?: string;
  provider?: string;
  embed_url?: string;
  thumbnail_url?: string;
  creator_name?: string;
  created_at?: string;
  user?: {
    username?: string;
    full_name?: string;
    profile_image?: string;
  };
};

function pretty(value?: string) {
  const clean = String(value || 'link').replace(/_/g, ' ');
  return clean.charAt(0).toUpperCase() + clean.slice(1);
}

function dateLabel(value?: string) {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime())) return 'Community recommend';
  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

export default function RecommendationDetailScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{ id?: string }>();
  const insets = useSafeAreaInsets();
  const id = Array.isArray(params.id) ? params.id[0] : params.id || '';
  const [item, setItem] = useState<Recommendation | null>(null);
  const [loading, setLoading] = useState(true);
  const [reported, setReported] = useState(false);

  const loadRecommendation = useCallback(async () => {
    if (!id) return;
    setLoading(true);
    try {
      const response = await api.get(`/recommendations/${encodeURIComponent(id)}`);
      setItem(response.data);
    } catch (error: any) {
      Alert.alert('Could not load', error?.response?.data?.detail || 'Recommendation was not found.', [
        { text: 'OK', onPress: () => router.back() },
      ]);
    } finally {
      setLoading(false);
    }
  }, [id, router]);

  useEffect(() => {
    loadRecommendation();
  }, [loadRecommendation]);

  const submitter = item?.user?.full_name || item?.user?.username || 'Flames community';
  const sourceLabel = pretty(item?.provider || item?.category);
  const canEmbed = !!item?.embed_url;

  const embedHtml = useMemo(() => {
    if (!item?.embed_url) return '';
    const src = JSON.stringify(item.embed_url);
    return `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>
      *{box-sizing:border-box}html,body{width:100%;height:100%;margin:0;background:#000;overflow:hidden}
      iframe{width:100%;height:100%;border:0;background:#000}
    </style></head><body><iframe src=${src} allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe></body></html>`;
  }, [item?.embed_url]);

  const openSource = () => {
    if (item?.external_url) openSafeUrl(item.external_url);
  };

  const report = async () => {
    if (!item || reported) return;
    try {
      await api.post(`/recommendations/${item.id}/report`, { reason: 'Recommendation report' });
      setReported(true);
      Alert.alert('Reported', 'Thanks. Moderation will review this recommendation.');
    } catch (error: any) {
      Alert.alert('Report failed', error?.response?.data?.detail || 'Could not report this recommendation.');
    }
  };

  if (loading) {
    return (
      <SafeAreaView style={styles.safeArea}>
        <View style={styles.loading}>
          <ActivityIndicator size="large" color={colors.textPrimary} />
        </View>
      </SafeAreaView>
    );
  }

  if (!item) return null;

  return (
    <SafeAreaView style={styles.safeArea} edges={['top']}>
      <View style={styles.screen}>
        <View style={styles.header}>
          <TouchableOpacity style={styles.headerBtn} onPress={() => router.back()} activeOpacity={0.75}>
            <Ionicons name="arrow-back" size={30} color={colors.textPrimary} />
          </TouchableOpacity>
          <Text style={styles.headerTitle}>Recommend</Text>
          <TouchableOpacity style={styles.headerBtn} onPress={report} activeOpacity={0.75}>
            <Ionicons name={reported ? 'flag' : 'flag-outline'} size={24} color={colors.textPrimary} />
          </TouchableOpacity>
        </View>

        <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 132 }]}>
          <View style={styles.hero}>
            {canEmbed ? (
              Platform.OS === 'web' ? (
                <iframe srcDoc={embedHtml} style={{ width: '100%', height: '100%', border: 'none' } as any} title={item.title} />
              ) : WebView ? (
                <WebView source={{ html: embedHtml }} style={styles.webview} javaScriptEnabled domStorageEnabled allowsFullscreenVideo mediaPlaybackRequiresUserAction={false} />
              ) : item.thumbnail_url ? (
                <Image source={{ uri: item.thumbnail_url }} style={styles.heroImage} resizeMode="cover" />
              ) : (
                <View style={styles.heroFallback}><Ionicons name="play-circle-outline" size={54} color="#FFFFFF" /></View>
              )
            ) : item.thumbnail_url ? (
              <Image source={{ uri: item.thumbnail_url }} style={styles.heroImage} resizeMode="cover" />
            ) : (
              <View style={styles.heroFallback}>
                <View style={styles.heroCurveOne} />
                <View style={styles.heroCurveTwo} />
                <Ionicons name="sparkles-outline" size={48} color="#FFFFFF" />
              </View>
            )}
          </View>

          <View style={styles.titleRow}>
            <View style={styles.titleCopy}>
              <Text style={styles.kicker}>{sourceLabel}</Text>
              <Text style={styles.title} numberOfLines={3}>{item.title}</Text>
              <Text style={styles.hostLine} numberOfLines={1}>
                Recommended by <Text style={styles.hostName}>{submitter}</Text>
              </Text>
            </View>

            <View style={styles.dateCard}>
              <View style={styles.dateTop}><Text style={styles.dateTopText}>{pretty(item.category)}</Text></View>
              <Ionicons name="link-outline" size={30} color={colors.textPrimary} />
              <Text style={styles.dateBottom}>{dateLabel(item.created_at)}</Text>
            </View>
          </View>

          <View style={styles.actionRow}>
            <TouchableOpacity style={styles.roundAction} activeOpacity={0.8} onPress={report}>
              <Ionicons name={reported ? 'flag' : 'flag-outline'} size={23} color={colors.textPrimary} />
            </TouchableOpacity>
            <TouchableOpacity style={styles.roundAction} activeOpacity={0.8}>
              <Ionicons name="arrow-redo-outline" size={24} color={colors.textPrimary} />
            </TouchableOpacity>
            <TouchableOpacity style={styles.ticketBtn} onPress={openSource} activeOpacity={0.85}>
              <Text style={styles.ticketText}>{canEmbed ? 'Open source' : 'Open link'}</Text>
            </TouchableOpacity>
          </View>

          <View style={styles.infoBlock}>
            <View style={styles.infoRow}>
              <Ionicons name="person-outline" size={30} color={colors.textPrimary} />
              <Text style={styles.infoText}>{item.creator_name || sourceLabel}</Text>
            </View>
            <TouchableOpacity style={styles.infoRow} onPress={openSource} activeOpacity={0.8}>
              <Ionicons name="open-outline" size={30} color={colors.textPrimary} />
              <Text style={styles.infoText} numberOfLines={2}>{item.external_url || 'External source'}</Text>
            </TouchableOpacity>
          </View>

          {item.tags?.length ? (
            <View style={styles.tagRow}>
              {item.tags.slice(0, 3).map((tag) => (
                <View key={tag} style={styles.tagPill}><Text style={styles.tagText}>{tag}</Text></View>
              ))}
            </View>
          ) : null}

          <View style={styles.descriptionBlock}>
            <Text style={styles.sectionTitle}>Description</Text>
            <Text style={styles.description}>{item.description || 'A community recommendation shared with an external source link.'}</Text>
          </View>
        </ScrollView>

        <View style={[styles.bottomBar, { paddingBottom: insets.bottom + 14 }]}>
          <TouchableOpacity style={styles.rsvpBtn} onPress={openSource} activeOpacity={0.9}>
            <Text style={styles.rsvpText}>{canEmbed ? 'WATCH / OPEN' : 'OPEN LINK'}</Text>
          </TouchableOpacity>
        </View>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: { flex: 1, backgroundColor: colors.bgApp },
  screen: { flex: 1, backgroundColor: colors.bgApp },
  loading: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.bgApp },
  header: {
    height: 82,
    borderBottomWidth: 1.5,
    borderBottomColor: colors.textPrimary,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 22,
  },
  headerBtn: { width: 48, height: 48, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 21, fontWeight: '500', color: colors.textPrimary },
  content: { paddingBottom: 120 },
  hero: {
    width: '100%',
    height: Math.min(260, SCREEN_WIDTH * 0.58),
    borderBottomLeftRadius: 16,
    borderBottomRightRadius: 16,
    borderWidth: 1.5,
    borderTopWidth: 0,
    borderColor: colors.textPrimary,
    overflow: 'hidden',
    backgroundColor: '#050505',
  },
  heroImage: { width: '100%', height: '100%' },
  webview: { flex: 1, backgroundColor: '#000000' },
  heroFallback: { flex: 1, backgroundColor: '#111111', justifyContent: 'center', alignItems: 'center', overflow: 'hidden' },
  heroCurveOne: { position: 'absolute', width: SCREEN_WIDTH * 1.2, height: 72, borderRadius: 44, backgroundColor: '#C7353E', left: -90, bottom: 18, transform: [{ rotate: '-13deg' }] },
  heroCurveTwo: { position: 'absolute', width: SCREEN_WIDTH * 0.7, height: 76, borderRadius: 42, backgroundColor: '#D8C0A8', right: -54, top: 4, transform: [{ rotate: '18deg' }] },
  titleRow: { flexDirection: 'row', alignItems: 'flex-start', gap: 14, paddingHorizontal: 18, paddingTop: 32 },
  titleCopy: { flex: 1, minWidth: 0 },
  kicker: { color: '#6B6B6B', fontSize: 13, fontWeight: '500', textTransform: 'uppercase', marginBottom: 7 },
  title: { color: colors.textPrimary, fontSize: 31, lineHeight: 35, fontWeight: '500' },
  hostLine: { marginTop: 8, color: '#333333', fontSize: 18 },
  hostName: { textDecorationLine: 'underline' },
  dateCard: { width: 94, minHeight: 116, borderWidth: 1.5, borderColor: colors.textPrimary, borderRadius: 12, overflow: 'hidden', backgroundColor: colors.white, alignItems: 'center', justifyContent: 'space-between', paddingBottom: 9 },
  dateTop: { width: '100%', backgroundColor: '#FBF84A', borderBottomWidth: 1.5, borderBottomColor: colors.textPrimary, paddingVertical: 7, alignItems: 'center' },
  dateTopText: { color: colors.textPrimary, fontSize: 12, fontWeight: '500' },
  dateBottom: { color: '#4A4A4A', fontSize: 11, fontWeight: '600', textAlign: 'center', paddingHorizontal: 4 },
  actionRow: { flexDirection: 'row', alignItems: 'center', gap: 18, paddingHorizontal: 18, paddingTop: 26 },
  roundAction: { width: 54, height: 54, borderRadius: 27, borderWidth: 1.5, borderColor: colors.textPrimary, justifyContent: 'center', alignItems: 'center', backgroundColor: colors.white },
  ticketBtn: { minWidth: 140, height: 50, borderRadius: 14, borderWidth: 1.5, borderColor: colors.textPrimary, justifyContent: 'center', alignItems: 'center', paddingHorizontal: 22, backgroundColor: colors.white },
  ticketText: { color: colors.textPrimary, fontSize: 18, fontWeight: '500' },
  infoBlock: { paddingHorizontal: 22, paddingTop: 28, gap: 18 },
  infoRow: { flexDirection: 'row', alignItems: 'center', gap: 20 },
  infoText: { flex: 1, color: colors.textPrimary, fontSize: 18, lineHeight: 24 },
  tagRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, paddingHorizontal: 18, paddingTop: 28 },
  tagPill: { minHeight: 32, borderRadius: 16, backgroundColor: '#F0F0F0', justifyContent: 'center', paddingHorizontal: 12 },
  tagText: { color: '#222222', fontSize: 12, fontWeight: '500' },
  descriptionBlock: { paddingHorizontal: 18, paddingTop: 30 },
  sectionTitle: { color: colors.textPrimary, fontSize: 22, fontWeight: '500', marginBottom: 22 },
  description: { color: '#2B2B2B', fontSize: 20, lineHeight: 31 },
  bottomBar: { position: 'absolute', left: 0, right: 0, bottom: 0, paddingHorizontal: 18, paddingTop: 14, backgroundColor: colors.bgApp },
  rsvpBtn: { height: 64, borderRadius: 32, borderWidth: 1.5, borderColor: colors.textPrimary, backgroundColor: '#41D34C', justifyContent: 'center', alignItems: 'center' },
  rsvpText: { color: '#050505', fontSize: 20, fontWeight: '500' },
});
