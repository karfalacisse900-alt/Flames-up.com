import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Image,
  ActivityIndicator,
  Alert,
  RefreshControl,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, shadows } from '../src/utils/theme';
import api from '../src/api/client';

type TabId = 'posts' | 'accounts' | 'flagged';

export default function ContentManagerScreen() {
  const router = useRouter();
  const [tab, setTab] = useState<TabId>('posts');
  const [reportedPosts, setReportedPosts] = useState<any[]>([]);
  const [reportedAccounts, setReportedAccounts] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  useEffect(() => { loadData(); }, [tab]);

  const loadData = async () => {
    setLoading(true);
    try {
      if (tab === 'posts') {
        const r = await api.get('/admin/reported-posts');
        setReportedPosts(r.data || []);
      } else if (tab === 'accounts') {
        const r = await api.get('/admin/reported-accounts');
        setReportedAccounts(r.data || []);
      }
    } catch (e: any) {
      if (e.response?.status === 403) {
        Alert.alert('Access Denied', 'Admin access required.');
        router.back();
      }
    } finally {
      setLoading(false);
    }
  };

  const handleRemovePost = async (postId: string) => {
    Alert.alert('Remove Post', 'This will permanently delete this post. Continue?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Remove', style: 'destructive', onPress: async () => {
          try {
            await api.post(`/admin/remove-post/${postId}`);
            Alert.alert('Done', 'Post has been removed.');
            loadData();
          } catch { Alert.alert('Error', 'Could not remove post.'); }
        }
      },
    ]);
  };

  const handleDismissReport = async (reportId: string) => {
    try {
      await api.post(`/admin/reports/${reportId}/dismiss`);
      loadData();
    } catch {
      // If endpoint doesn't exist, just remove locally
      setReportedPosts(prev => prev.filter(r => r.id !== reportId));
    }
  };

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      {/* Header */}
      <View style={s.header}>
        <TouchableOpacity onPress={() => router.back()} style={s.backBtn}>
          <Ionicons name="arrow-back" size={22} color="#1B4332" />
        </TouchableOpacity>
        <Text style={s.headerTitle}>Content Manager</Text>
        <View style={s.cmBadge}>
          <Ionicons name="shield-checkmark" size={12} color="#FFF" />
        </View>
      </View>

      {/* Tabs */}
      <View style={s.tabRow}>
        {([
          { id: 'posts' as TabId, label: 'Reported Posts', icon: 'document-text' },
          { id: 'accounts' as TabId, label: 'Reported Users', icon: 'person-circle' },
        ]).map(t => (
          <TouchableOpacity
            key={t.id}
            style={[s.tab, tab === t.id && s.tabActive]}
            onPress={() => setTab(t.id)}
          >
            <Ionicons name={t.icon as any} size={16} color={tab === t.id ? '#FFF' : '#5C4033'} />
            <Text style={[s.tabText, tab === t.id && s.tabTextActive]}>{t.label}</Text>
          </TouchableOpacity>
        ))}
      </View>

      <ScrollView
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={async () => { setRefreshing(true); await loadData(); setRefreshing(false); }}
            tintColor="#2D6A4F"
          />
        }
        contentContainerStyle={{ padding: 16, paddingBottom: 80 }}
      >
        {loading ? (
          <ActivityIndicator size="large" color="#2D6A4F" style={{ marginTop: 40 }} />
        ) : (
          <>
            {/* Reported Posts Tab */}
            {tab === 'posts' && (
              reportedPosts.length === 0 ? (
                <View style={s.empty}>
                  <Ionicons name="checkmark-circle" size={56} color="#10B981" />
                  <Text style={s.emptyTitle}>All Clear!</Text>
                  <Text style={s.emptyText}>No reported posts to review</Text>
                </View>
              ) : reportedPosts.map((report, i) => (
                <View key={report.id || i} style={s.card}>
                  {/* Report Header */}
                  <View style={s.cardHeader}>
                    <View style={s.reportBadge}>
                      <Ionicons name="flag" size={12} color="#EF4444" />
                      <Text style={s.reportBadgeText}>REPORTED</Text>
                    </View>
                    <Text style={s.reporterName}>
                      by {report.reporter?.full_name || report.reporter_name || 'Anonymous'}
                    </Text>
                  </View>

                  {/* Reason */}
                  <View style={s.reasonBox}>
                    <Ionicons name="chatbubble-ellipses-outline" size={14} color="#6B7280" />
                    <Text style={s.reasonText}>{report.reason || 'No reason provided'}</Text>
                  </View>

                  {/* Post Content */}
                  {report.post && (
                    <View style={s.postPreview}>
                      <View style={s.postAuthorRow}>
                        {report.post.user_profile_image ? (
                          <Image source={{ uri: report.post.user_profile_image }} style={s.postAuthorAvatar} />
                        ) : (
                          <View style={s.postAuthorAvatarPlaceholder}>
                            <Text style={s.postAuthorInitial}>
                              {(report.post.user_full_name || 'U')[0]}
                            </Text>
                          </View>
                        )}
                        <View>
                          <Text style={s.postAuthorName}>{report.post.user_full_name}</Text>
                          <Text style={s.postAuthorHandle}>@{report.post.user_username}</Text>
                        </View>
                      </View>
                      <Text style={s.postContent} numberOfLines={3}>
                        {report.post.content || '(No text content)'}
                      </Text>
                      {report.post.image && (
                        <Image source={{ uri: report.post.image }} style={s.postImage} />
                      )}
                    </View>
                  )}

                  {/* Actions */}
                  <View style={s.actionsRow}>
                    {report.post?.id && (
                      <TouchableOpacity style={s.removeBtn} onPress={() => handleRemovePost(report.post.id)}>
                        <Ionicons name="trash" size={16} color="#FFF" />
                        <Text style={s.removeBtnText}>Remove Post</Text>
                      </TouchableOpacity>
                    )}
                    <TouchableOpacity style={s.keepBtn} onPress={() => handleDismissReport(report.id)}>
                      <Ionicons name="checkmark" size={16} color="#16A34A" />
                      <Text style={s.keepBtnText}>Dismiss</Text>
                    </TouchableOpacity>
                  </View>
                </View>
              ))
            )}

            {/* Reported Accounts Tab */}
            {tab === 'accounts' && (
              reportedAccounts.length === 0 ? (
                <View style={s.empty}>
                  <Ionicons name="people-circle" size={56} color="#10B981" />
                  <Text style={s.emptyTitle}>No Reported Users</Text>
                  <Text style={s.emptyText}>All user accounts are in good standing</Text>
                </View>
              ) : reportedAccounts.map((account, i) => (
                <View key={account.id || i} style={s.card}>
                  <View style={s.userRow}>
                    {account.profile_image ? (
                      <Image source={{ uri: account.profile_image }} style={s.userAvatar} />
                    ) : (
                      <View style={s.userAvatarPlaceholder}>
                        <Text style={s.userInitial}>
                          {(account.full_name || account.username || 'U')[0].toUpperCase()}
                        </Text>
                      </View>
                    )}
                    <View style={{ flex: 1 }}>
                      <Text style={s.userName}>{account.full_name || account.username}</Text>
                      <Text style={s.userHandle}>@{account.username}</Text>
                      {account.report_count && (
                        <View style={s.reportCountBadge}>
                          <Text style={s.reportCountText}>{account.report_count} reports</Text>
                        </View>
                      )}
                    </View>
                  </View>
                  {account.reasons && account.reasons.length > 0 && (
                    <View style={s.reasonsList}>
                      {account.reasons.slice(0, 3).map((r: string, idx: number) => (
                        <Text key={idx} style={s.reasonItem}>- {r}</Text>
                      ))}
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
  header: {
    flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16,
    paddingVertical: 12, gap: 12,
  },
  backBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { flex: 1, fontSize: 22, fontWeight: '800', color: '#1B4332' },
  cmBadge: {
    width: 28, height: 28, borderRadius: 14, backgroundColor: '#F59E0B',
    justifyContent: 'center', alignItems: 'center',
  },
  tabRow: { flexDirection: 'row', paddingHorizontal: 16, gap: 8, marginBottom: 8 },
  tab: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: 5, paddingVertical: 10, borderRadius: 14, backgroundColor: '#F3F0EB',
    borderWidth: 1, borderColor: '#E0D5C5',
  },
  tabActive: { backgroundColor: '#2D6A4F', borderColor: '#2D6A4F' },
  tabText: { fontSize: 12, fontWeight: '600', color: '#5C4033' },
  tabTextActive: { color: '#FFF' },
  empty: { alignItems: 'center', paddingTop: 60, gap: 8 },
  emptyTitle: { fontSize: 20, fontWeight: '700', color: '#1B4332' },
  emptyText: { fontSize: 14, color: '#9CA3AF' },
  card: {
    backgroundColor: '#FFF', borderRadius: 20, padding: 16, marginBottom: 14,
    borderWidth: 1, borderColor: '#F0ECE5', ...shadows.elevation1,
  },
  cardHeader: {
    flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 10,
  },
  reportBadge: {
    flexDirection: 'row', alignItems: 'center', gap: 4,
    backgroundColor: '#FEF2F2', paddingHorizontal: 8, paddingVertical: 3, borderRadius: 8,
  },
  reportBadgeText: { fontSize: 10, fontWeight: '800', color: '#EF4444', letterSpacing: 0.5 },
  reporterName: { fontSize: 12, color: '#9CA3AF', fontWeight: '500' },
  reasonBox: {
    flexDirection: 'row', alignItems: 'flex-start', gap: 6,
    backgroundColor: '#F9FAFB', borderRadius: 12, padding: 10, marginBottom: 12,
  },
  reasonText: { flex: 1, fontSize: 13, color: '#374151', lineHeight: 18 },
  postPreview: {
    backgroundColor: '#FAFAF8', borderRadius: 14, padding: 12, marginBottom: 12,
    borderWidth: 1, borderColor: '#F0ECE5',
  },
  postAuthorRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginBottom: 8 },
  postAuthorAvatar: { width: 32, height: 32, borderRadius: 16 },
  postAuthorAvatarPlaceholder: {
    width: 32, height: 32, borderRadius: 16, backgroundColor: '#E8F5E9',
    justifyContent: 'center', alignItems: 'center',
  },
  postAuthorInitial: { fontSize: 14, fontWeight: '700', color: '#2D6A4F' },
  postAuthorName: { fontSize: 14, fontWeight: '600', color: '#1B4332' },
  postAuthorHandle: { fontSize: 11, color: '#9CA3AF' },
  postContent: { fontSize: 13, color: '#374151', lineHeight: 18, marginBottom: 6 },
  postImage: { width: '100%', height: 140, borderRadius: 10, marginTop: 4 },
  actionsRow: { flexDirection: 'row', gap: 10 },
  removeBtn: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: 6, paddingVertical: 11, borderRadius: 14, backgroundColor: '#EF4444',
  },
  removeBtnText: { fontSize: 14, fontWeight: '700', color: '#FFF' },
  keepBtn: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: 6, paddingVertical: 11, borderRadius: 14, backgroundColor: '#DCFCE7',
    borderWidth: 1, borderColor: '#BBF7D0',
  },
  keepBtnText: { fontSize: 14, fontWeight: '700', color: '#16A34A' },
  // User accounts
  userRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  userAvatar: { width: 48, height: 48, borderRadius: 24 },
  userAvatarPlaceholder: {
    width: 48, height: 48, borderRadius: 24, backgroundColor: '#E8F5E9',
    justifyContent: 'center', alignItems: 'center',
  },
  userInitial: { fontSize: 20, fontWeight: '700', color: '#2D6A4F' },
  userName: { fontSize: 16, fontWeight: '700', color: '#1B4332' },
  userHandle: { fontSize: 12, color: '#9CA3AF', marginTop: 1 },
  reportCountBadge: {
    marginTop: 4, alignSelf: 'flex-start',
    backgroundColor: '#FEF2F2', paddingHorizontal: 8, paddingVertical: 2, borderRadius: 6,
  },
  reportCountText: { fontSize: 11, fontWeight: '700', color: '#EF4444' },
  reasonsList: { marginTop: 10, paddingLeft: 4, gap: 2 },
  reasonItem: { fontSize: 12, color: '#6B7280', lineHeight: 18 },
});
