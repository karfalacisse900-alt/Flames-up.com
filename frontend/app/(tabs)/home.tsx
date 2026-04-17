import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView,
  RefreshControl, Dimensions,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';

const { width: SW } = Dimensions.get('window');
const GAP = 6;
const PAD = 6;
const COL_W = (SW - PAD * 2 - GAP) / 2;
const RATIOS = [1.35, 1.0, 1.5, 1.15, 1.3, 0.95, 1.4, 1.1];

export default function HomeScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();
  const [statuses, setStatuses] = useState<any[]>([]);
  const [posts, setPosts] = useState<any[]>([]);
  const [refreshing, setRefreshing] = useState(false);

  useEffect(() => { loadData(); }, []);

  const loadData = async () => {
    try {
      const [sRes, pRes] = await Promise.all([
        api.get('/statuses'),
        api.get('/posts/feed', { params: { limit: 30 } }),
      ]);
      setStatuses(Array.isArray(sRes.data) ? sRes.data : []);
      setPosts(Array.isArray(pRes.data) ? pRes.data : []);
    } catch {}
  };

  const onRefresh = useCallback(async () => {
    setRefreshing(true); await loadData(); setRefreshing(false);
  }, []);

  const greeting = () => {
    const h = new Date().getHours();
    return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
  };

  // Posts with images for masonry
  const items = posts.filter((p: any) => {
    const img = p.image || (p.images && p.images[0]);
    return img && typeof img === 'string' && (img.startsWith('http') || img.startsWith('data:'));
  });

  const L: any[] = [], R: any[] = [];
  let lh = 0, rh = 0;
  items.forEach((p, i) => {
    const h = COL_W * RATIOS[i % RATIOS.length];
    if (lh <= rh) { L.push({ ...p, _h: h }); lh += h + GAP + 52; }
    else { R.push({ ...p, _h: h }); rh += h + GAP + 52; }
  });

  const Card = ({ p }: { p: any }) => {
    const img = p.image || (p.images && p.images[0]);
    const name = p.user_full_name || p.user_username || '';
    return (
      <TouchableOpacity style={s.card} activeOpacity={0.96} onPress={() => router.push(`/post/${p.id}` as any)}>
        <Image source={{ uri: img }} style={[s.cardImg, { height: p._h }]} resizeMode="cover" />
        <View style={s.cardBot}>
          {p.content ? <Text style={s.cardCap} numberOfLines={2}>{p.content}</Text> : null}
          <View style={s.cardRow}>
            {p.user_profile_image ? (
              <Image source={{ uri: p.user_profile_image }} style={s.av} />
            ) : (
              <View style={s.avFb}><Text style={s.avTx}>{(name || 'U')[0]}</Text></View>
            )}
            <Text style={s.cardName} numberOfLines={1}>{name}</Text>
            <Ionicons name="heart-outline" size={12} color="#CCC" />
          </View>
        </View>
      </TouchableOpacity>
    );
  };

  return (
    <View style={s.root}>
      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {/* Header */}
        <View style={[s.header, { paddingTop: insets.top + 8 }]}>
          <View>
            <Text style={s.logo}>Flames-Up</Text>
            <Text style={s.greet}>{greeting()}</Text>
          </View>
          <View style={s.headerR}>
            <TouchableOpacity style={s.iconBtn} onPress={() => router.push('/create-post' as any)}>
              <Ionicons name="add" size={22} color="#1A1A1A" />
            </TouchableOpacity>
            <TouchableOpacity style={s.iconBtn} onPress={() => router.push('/notifications' as any)}>
              <Ionicons name="notifications-outline" size={20} color="#1A1A1A" />
            </TouchableOpacity>
          </View>
        </View>

        {/* Stories */}
        {statuses.length > 0 && (
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.stories}>
            <TouchableOpacity style={s.storyItem} onPress={() => router.push('/create-status')}>
              <View style={s.storyAddWrap}>
                {user?.profile_image ? (
                  <Image source={{ uri: user.profile_image }} style={s.storyAv} />
                ) : (
                  <View style={[s.storyAv, s.storyAvEmpty]}><Text style={s.storyInit}>{(user?.full_name || 'U')[0]}</Text></View>
                )}
                <View style={s.storyPlus}><Ionicons name="add" size={11} color="#FFF" /></View>
              </View>
              <Text style={s.storyLbl}>You</Text>
            </TouchableOpacity>
            {statuses.filter((g: any) => g.user_id !== user?.id).map((g: any) => (
              <TouchableOpacity key={g.user_id} style={s.storyItem} onPress={() => router.push(`/story-viewer?userId=${g.user_id}` as any)}>
                <View style={[s.storyRing, g.has_unviewed && s.storyRingNew]}>
                  {g.user_profile_image ? (
                    <Image source={{ uri: g.user_profile_image }} style={s.storyAv} />
                  ) : (
                    <View style={[s.storyAv, s.storyAvEmpty]}><Text style={s.storyInit}>{(g.user_full_name || 'U')[0]}</Text></View>
                  )}
                </View>
                <Text style={s.storyLbl} numberOfLines={1}>{g.user_full_name?.split(' ')[0]}</Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
        )}

        {/* Masonry Feed */}
        {items.length > 0 ? (
          <View style={s.grid}>
            <View style={s.col}>{L.map(p => <Card key={p.id} p={p} />)}</View>
            <View style={s.col}>{R.map(p => <Card key={p.id} p={p} />)}</View>
          </View>
        ) : (
          <View style={s.empty}>
            <Ionicons name="images-outline" size={40} color="#DDD" />
            <Text style={s.emptyTx}>No posts yet</Text>
          </View>
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#FAFAF8' },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, paddingBottom: 4 },
  logo: { fontSize: 24, fontWeight: '800', color: '#1A1A1A', fontStyle: 'italic', letterSpacing: -0.5 },
  greet: { fontSize: 13, color: '#AAA', marginTop: 1 },
  headerR: { flexDirection: 'row', gap: 8 },
  iconBtn: { width: 40, height: 40, borderRadius: 20, justifyContent: 'center', alignItems: 'center', backgroundColor: '#F0F0F0' },

  stories: { paddingHorizontal: 12, paddingVertical: 8, gap: 14 },
  storyItem: { alignItems: 'center', width: 56 },
  storyAddWrap: { position: 'relative' },
  storyAv: { width: 48, height: 48, borderRadius: 24 },
  storyAvEmpty: { backgroundColor: '#E8E4DF', justifyContent: 'center', alignItems: 'center' },
  storyInit: { fontSize: 16, fontWeight: '700', color: '#AAA' },
  storyPlus: { position: 'absolute', bottom: -1, right: -1, width: 16, height: 16, borderRadius: 8, backgroundColor: '#1A1A1A', justifyContent: 'center', alignItems: 'center', borderWidth: 2, borderColor: '#FAFAF8' },
  storyRing: { width: 52, height: 52, borderRadius: 26, borderWidth: 2, borderColor: '#E0DCD7', justifyContent: 'center', alignItems: 'center' },
  storyRingNew: { borderColor: '#1A1A1A' },
  storyLbl: { fontSize: 10, color: '#999', marginTop: 3 },

  grid: { flexDirection: 'row', paddingHorizontal: PAD, gap: GAP, marginTop: 4 },
  col: { flex: 1, gap: GAP },

  card: { borderRadius: 12, overflow: 'hidden', backgroundColor: '#FFF' },
  cardImg: { width: '100%' },
  cardBot: { paddingHorizontal: 8, paddingTop: 6, paddingBottom: 8 },
  cardCap: { fontSize: 13, fontWeight: '600', color: '#1A1A1A', lineHeight: 17, marginBottom: 5 },
  cardRow: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  av: { width: 16, height: 16, borderRadius: 8 },
  avFb: { width: 16, height: 16, borderRadius: 8, backgroundColor: '#EEE', justifyContent: 'center', alignItems: 'center' },
  avTx: { fontSize: 8, fontWeight: '700', color: '#BBB' },
  cardName: { fontSize: 11, color: '#AAA', flex: 1 },

  empty: { paddingTop: 100, alignItems: 'center' },
  emptyTx: { fontSize: 14, color: '#CCC', marginTop: 10 },
});
