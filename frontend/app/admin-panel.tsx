import React, { useState, useEffect } from 'react';
import {
  View, Text, StyleSheet, ScrollView, TouchableOpacity, Image,
  ActivityIndicator, Alert, RefreshControl,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../src/utils/theme';
import api from '../src/api/client';

type TabId = 'overview' | 'reports' | 'publishers';

export default function AdminPanelScreen() {
  const router = useRouter();
  const [tab, setTab] = useState<TabId>('overview');
  const [stats, setStats] = useState<any>(null);
  const [reports, setReports] = useState<any[]>([]);
  const [publisherApps, setPublisherApps] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  useEffect(() => { loadData(); }, [tab]);

  const loadData = async () => {
    setLoading(true);
    try {
      if (tab === 'overview') {
        const r = await api.get('/admin/stats');
        setStats(r.data);
      } else if (tab === 'reports') {
        const r = await api.get('/admin/reported-posts');
        setReports(r.data);
      } else {
        const r = await api.get('/admin/publisher-applications');
        setPublisherApps(r.data);
      }
    } catch (e: any) {
      if (e.response?.status === 403) Alert.alert('Access Denied', 'Admin access required.');
    } finally { setLoading(false); }
  };

  const handlePublisherDecision = async (appId: string, action: string) => {
    try {
      await api.post(`/admin/publisher-applications/${appId}/decide`, { action });
      Alert.alert('Done', action === 'approve' ? 'Publisher approved!' : 'Application declined.');
      loadData();
    } catch { Alert.alert('Error', 'Could not process.'); }
  };

  const handleRemovePost = async (postId: string) => {
    Alert.alert('Remove Post', 'Permanently delete this post?', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Remove', style: 'destructive', onPress: async () => {
        try { await api.post(`/admin/remove-post/${postId}`); Alert.alert('Removed'); loadData(); }
        catch { Alert.alert('Error'); }
      }},
    ]);
  };

  const StatCard = ({ label, value, icon, color }: any) => (
    <View style={[s.statCard, { borderLeftColor: color }]}>
      <View style={[s.statIcon, { backgroundColor: color + '15' }]}>
        <Ionicons name={icon} size={20} color={color} />
      </View>
      <Text style={s.statValue}>{value ?? '—'}</Text>
      <Text style={s.statLabel}>{label}</Text>
    </View>
  );

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      <View style={s.header}>
        <TouchableOpacity onPress={() => router.back()} style={s.backBtn}>
          <Ionicons name="arrow-back" size={22} color="#1B4332" />
        </TouchableOpacity>
        <Text style={s.headerTitle}>Admin Panel</Text>
        <View style={s.adminBadge}><Text style={s.adminBadgeText}>ADMIN</Text></View>
      </View>

      <View style={s.tabRow}>
        {([
          { id: 'overview' as TabId, label: 'Overview', icon: 'grid' },
          { id: 'reports' as TabId, label: 'Reports', icon: 'flag' },
          { id: 'publishers' as TabId, label: 'Publishers', icon: 'megaphone' },
        ]).map(t => (
          <TouchableOpacity key={t.id} style={[s.tab, tab === t.id && s.tabActive]} onPress={() => setTab(t.id)}>
            <Ionicons name={t.icon as any} size={16} color={tab === t.id ? '#FFF' : '#5C4033'} />
            <Text style={[s.tabText, tab === t.id && s.tabTextActive]}>{t.label}</Text>
          </TouchableOpacity>
        ))}
      </View>

      <ScrollView
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={async () => { setRefreshing(true); await loadData(); setRefreshing(false); }} tintColor="#2D6A4F" />}
        contentContainerStyle={{ padding: 16, paddingBottom: 80 }}
      >
        {loading ? <ActivityIndicator size="large" color="#2D6A4F" style={{ marginTop: 40 }} /> : (
          <>
            {tab === 'overview' && stats && (
              <View style={s.statsGrid}>
                <StatCard label="Users" value={stats.total_users} icon="people" color="#3B82F6" />
                <StatCard label="Posts" value={stats.total_posts} icon="document-text" color="#10B981" />
                <StatCard label="Reports" value={stats.pending_reports} icon="flag" color="#EF4444" />
                <StatCard label="Publishers" value={stats.total_publishers} icon="megaphone" color="#8B5CF6" />
                <StatCard label="Pending Apps" value={stats.pending_publisher_apps} icon="time" color="#F59E0B" />
                <StatCard label="Discover" value={stats.total_discover_posts} icon="newspaper" color="#06B6D4" />
              </View>
            )}

            {tab === 'reports' && (
              reports.length === 0 ? (
                <View style={s.empty}><Ionicons name="checkmark-circle" size={48} color="#10B981" /><Text style={s.emptyText}>No reports to review</Text></View>
              ) : reports.map((r, i) => (
                <View key={i} style={s.reportCard}>
                  <View style={s.reportHeader}>
                    <Ionicons name="flag" size={16} color="#EF4444" />
                    <Text style={s.reportType}>{r.report_type || 'Report'}</Text>
                    <Text style={s.reportTime}>{r.reporter?.full_name || r.reporter_name || 'User'}</Text>
                  </View>
                  <Text style={s.reportReason}>{r.reason || 'No reason'}</Text>
                  {r.post && <View style={s.reportContent}><Text style={s.reportContentText} numberOfLines={2}>{r.post.content || '—'}</Text></View>}
                  {r.status ? (
                    <View style={s.resolvedBadge}><Text style={s.resolvedText}>Resolved: {r.status}</Text></View>
                  ) : (
                    <View style={s.reportActions}>
                      {r.post?.id && <TouchableOpacity style={s.removeBtn} onPress={() => handleRemovePost(r.post.id)}><Ionicons name="trash" size={14} color="#FFF" /><Text style={s.removeBtnText}>Remove</Text></TouchableOpacity>}
                      <TouchableOpacity style={s.dismissBtn}><Text style={s.dismissBtnText}>Keep</Text></TouchableOpacity>
                    </View>
                  )}
                </View>
              ))
            )}

            {tab === 'publishers' && (
              publisherApps.length === 0 ? (
                <View style={s.empty}><Ionicons name="megaphone-outline" size={48} color="#9CA3AF" /><Text style={s.emptyText}>No applications</Text></View>
              ) : publisherApps.map((a, i) => (
                <View key={i} style={s.pubCard}>
                  <View style={s.pubHeader}>
                    <View style={s.pubAvatar}>
                      {a.user_profile_image ? <Image source={{ uri: a.user_profile_image }} style={{ width: '100%', height: '100%' }} /> : <Text style={s.pubInitial}>{(a.user_full_name || 'U')[0]}</Text>}
                    </View>
                    <View style={{ flex: 1 }}>
                      <Text style={s.pubName}>{a.user_full_name}</Text>
                      <Text style={s.pubBiz}>{a.business_name} · {a.category}</Text>
                    </View>
                    <View style={[s.statusPill, { backgroundColor: a.status === 'approved' ? '#DCFCE7' : a.status === 'declined' ? '#FEE2E2' : '#FEF3C7' }]}>
                      <Text style={[s.statusPillText, { color: a.status === 'approved' ? '#16A34A' : a.status === 'declined' ? '#DC2626' : '#D97706' }]}>{a.status?.toUpperCase()}</Text>
                    </View>
                  </View>
                  <View style={s.pubDetails}>
                    <Text style={s.pubDetailLabel}>Phone: <Text style={s.pubDetailValue}>{a.phone}</Text></Text>
                    <Text style={s.pubDetailLabel}>About: <Text style={s.pubDetailValue}>{a.about}</Text></Text>
                    <Text style={s.pubDetailLabel}>Why: <Text style={s.pubDetailValue}>{a.why_publish}</Text></Text>
                    {a.social_instagram && <Text style={s.pubDetailLabel}>IG: <Text style={s.pubDetailValue}>{a.social_instagram}</Text></Text>}
                  </View>
                  {a.status === 'pending' && (
                    <View style={s.pubActions}>
                      <TouchableOpacity style={s.approveBtn} onPress={() => handlePublisherDecision(a.id, 'approve')}>
                        <Ionicons name="checkmark" size={16} color="#FFF" /><Text style={s.approveBtnText}>Approve</Text>
                      </TouchableOpacity>
                      <TouchableOpacity style={s.declineBtn} onPress={() => handlePublisherDecision(a.id, 'decline')}>
                        <Ionicons name="close" size={16} color="#DC2626" /><Text style={s.declineBtnText}>Decline</Text>
                      </TouchableOpacity>
                    </View>
                  )}
                </View>
              ))
            )}
          </>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FAFAF8' },
  header: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12, gap: 12 },
  backBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { flex: 1, fontSize: 22, fontWeight: '800', color: '#1B4332' },
  adminBadge: { paddingHorizontal: 10, paddingVertical: 4, borderRadius: 8, backgroundColor: '#EF4444' },
  adminBadgeText: { fontSize: 10, fontWeight: '800', color: '#FFF', letterSpacing: 1 },
  tabRow: { flexDirection: 'row', paddingHorizontal: 16, gap: 8, marginBottom: 8 },
  tab: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 5, paddingVertical: 10, borderRadius: 14, backgroundColor: '#F3F0EB', borderWidth: 1, borderColor: '#E0D5C5' },
  tabActive: { backgroundColor: '#2D6A4F', borderColor: '#2D6A4F' },
  tabText: { fontSize: 12, fontWeight: '600', color: '#5C4033' },
  tabTextActive: { color: '#FFF' },
  statsGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 },
  statCard: { width: '47%' as any, backgroundColor: '#FFF', borderRadius: 16, padding: 16, borderLeftWidth: 4, borderWidth: 1, borderColor: '#F0ECE5' },
  statIcon: { width: 36, height: 36, borderRadius: 12, justifyContent: 'center', alignItems: 'center', marginBottom: 8 },
  statValue: { fontSize: 28, fontWeight: '800', color: '#1B4332' },
  statLabel: { fontSize: 12, color: '#6B7280', marginTop: 2, fontWeight: '500' },
  empty: { alignItems: 'center', paddingTop: 60 },
  emptyText: { fontSize: 16, color: '#9CA3AF', marginTop: 12 },
  reportCard: { backgroundColor: '#FFF', borderRadius: 16, padding: 16, marginBottom: 12, borderWidth: 1, borderColor: '#FEE2E2' },
  reportHeader: { flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 8 },
  reportType: { fontSize: 13, fontWeight: '700', color: '#EF4444', textTransform: 'capitalize' },
  reportTime: { marginLeft: 'auto', fontSize: 12, color: '#9CA3AF' },
  reportReason: { fontSize: 14, color: '#374151', lineHeight: 20, marginBottom: 8 },
  reportContent: { backgroundColor: '#F9FAFB', borderRadius: 10, padding: 10, marginBottom: 10 },
  reportContentText: { fontSize: 13, color: '#6B7280', fontStyle: 'italic' },
  resolvedBadge: { alignSelf: 'flex-start', paddingHorizontal: 10, paddingVertical: 4, borderRadius: 8, backgroundColor: '#F3F4F6' },
  resolvedText: { fontSize: 11, fontWeight: '600', color: '#6B7280' },
  reportActions: { flexDirection: 'row', gap: 10 },
  removeBtn: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 4, paddingVertical: 10, borderRadius: 12, backgroundColor: '#EF4444' },
  removeBtnText: { fontSize: 13, fontWeight: '700', color: '#FFF' },
  dismissBtn: { flex: 1, paddingVertical: 10, borderRadius: 12, backgroundColor: '#F3F4F6', alignItems: 'center' },
  dismissBtnText: { fontSize: 13, fontWeight: '600', color: '#6B7280' },
  pubCard: { backgroundColor: '#FFF', borderRadius: 16, padding: 16, marginBottom: 12, borderWidth: 1, borderColor: '#F0ECE5' },
  pubHeader: { flexDirection: 'row', alignItems: 'center', gap: 12, marginBottom: 12 },
  pubAvatar: { width: 44, height: 44, borderRadius: 22, overflow: 'hidden', backgroundColor: '#E8F5E9', justifyContent: 'center', alignItems: 'center' },
  pubInitial: { fontSize: 18, fontWeight: '700', color: '#2D6A4F' },
  pubName: { fontSize: 16, fontWeight: '700', color: '#1B4332' },
  pubBiz: { fontSize: 12, color: '#6B7280', marginTop: 1 },
  statusPill: { paddingHorizontal: 10, paddingVertical: 3, borderRadius: 8 },
  statusPillText: { fontSize: 10, fontWeight: '800', letterSpacing: 0.5 },
  pubDetails: { gap: 4, marginBottom: 4 },
  pubDetailLabel: { fontSize: 12, fontWeight: '700', color: '#9CA3AF' },
  pubDetailValue: { fontSize: 13, color: '#374151', fontWeight: '400' },
  pubActions: { flexDirection: 'row', gap: 10, marginTop: 12 },
  approveBtn: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 4, paddingVertical: 10, borderRadius: 14, backgroundColor: '#10B981' },
  approveBtnText: { fontSize: 14, fontWeight: '700', color: '#FFF' },
  declineBtn: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 4, paddingVertical: 10, borderRadius: 14, backgroundColor: '#FEE2E2', borderWidth: 1, borderColor: '#FECACA' },
  declineBtnText: { fontSize: 14, fontWeight: '700', color: '#DC2626' },
});
