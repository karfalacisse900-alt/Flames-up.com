import { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import {
  dismissReport,
  getMe,
  getReports,
  getStats,
  login,
  removePost,
  resolveReport,
  banUser,
  unbanUser,
} from '@/api/client';
import { clearStoredToken, getStoredToken, saveStoredToken } from '@/auth/session';
import { GovernanceDashboard } from '@/components/GovernanceDashboard';
import { LoginScreen } from '@/components/LoginScreen';
import { ReportDetailSheet } from '@/components/ReportDetailSheet';
import { colors } from '@/theme';
import type { AdminUser, FilterStatus, GovernanceReport, GovernanceStats } from '@/types';

const emptyStats: GovernanceStats = {
  active_users: 0,
  pending_reports: 0,
  banned_users: 0,
  removed_posts: 0,
};

function getErrorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  return 'Something went wrong.';
}

export default function GovernanceHome() {
  const [token, setToken] = useState<string | null>(null);
  const [admin, setAdmin] = useState<AdminUser | null>(null);
  const [stats, setStats] = useState<GovernanceStats>(emptyStats);
  const [reports, setReports] = useState<GovernanceReport[]>([]);
  const [selectedReport, setSelectedReport] = useState<GovernanceReport | null>(null);
  const [status, setStatus] = useState<FilterStatus>('pending');
  const [booting, setBooting] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [working, setWorking] = useState(false);
  const [loginError, setLoginError] = useState('');
  const [actionError, setActionError] = useState('');

  const signedIn = useMemo(() => Boolean(token && admin), [admin, token]);

  const loadGovernance = useCallback(async (activeToken: string, activeStatus: FilterStatus) => {
    const [nextStats, nextReports] = await Promise.all([
      getStats(activeToken),
      getReports(activeToken, activeStatus),
    ]);
    setStats(nextStats);
    setReports(nextReports);
  }, []);

  useEffect(() => {
    let mounted = true;

    async function bootstrap() {
      try {
        const savedToken = await getStoredToken();
        if (!savedToken) return;

        const me = await getMe(savedToken);
        if (!me.is_admin) {
          await clearStoredToken();
          return;
        }

        if (!mounted) return;
        setToken(savedToken);
        setAdmin(me);
        await loadGovernance(savedToken, 'pending');
      } catch {
        await clearStoredToken();
      } finally {
        if (mounted) setBooting(false);
      }
    }

    bootstrap();
    return () => {
      mounted = false;
    };
  }, [loadGovernance]);

  const handleLogin = useCallback(async (email: string, password: string) => {
    setLoginError('');
    setWorking(true);
    try {
      const response = await login(email, password);
      const nextToken = response.access_token;
      if (!nextToken) throw new Error('The API did not return a login token.');

      const me = await getMe(nextToken);
      if (!me.is_admin) throw new Error('This account does not have admin access.');

      await saveStoredToken(nextToken);
      setToken(nextToken);
      setAdmin(me);
      await loadGovernance(nextToken, status);
    } catch (error) {
      setLoginError(getErrorMessage(error));
    } finally {
      setWorking(false);
    }
  }, [loadGovernance, status]);

  const handleLogout = useCallback(async () => {
    await clearStoredToken();
    setToken(null);
    setAdmin(null);
    setReports([]);
    setStats(emptyStats);
    setSelectedReport(null);
  }, []);

  const handleRefresh = useCallback(async () => {
    if (!token) return;
    setRefreshing(true);
    setActionError('');
    try {
      await loadGovernance(token, status);
    } catch (error) {
      setActionError(getErrorMessage(error));
    } finally {
      setRefreshing(false);
    }
  }, [loadGovernance, status, token]);

  const handleStatusChange = useCallback(async (nextStatus: FilterStatus) => {
    if (!token) return;
    setStatus(nextStatus);
    setRefreshing(true);
    setActionError('');
    try {
      await loadGovernance(token, nextStatus);
    } catch (error) {
      setActionError(getErrorMessage(error));
    } finally {
      setRefreshing(false);
    }
  }, [loadGovernance, token]);

  const runAction = useCallback(async (action: () => Promise<unknown>) => {
    if (!token) return;
    setWorking(true);
    setActionError('');
    try {
      await action();
      setSelectedReport(null);
      await loadGovernance(token, status);
    } catch (error) {
      setActionError(getErrorMessage(error));
    } finally {
      setWorking(false);
    }
  }, [loadGovernance, status, token]);

  if (booting) {
    return (
      <SafeAreaView style={styles.centered}>
        <ActivityIndicator color={colors.primary} />
        <Text style={styles.loadingText}>Opening governance console</Text>
      </SafeAreaView>
    );
  }

  if (!signedIn) {
    return (
      <LoginScreen
        error={loginError}
        loading={working}
        onLogin={handleLogin}
      />
    );
  }

  return (
    <View style={styles.screen}>
      <GovernanceDashboard
        admin={admin}
        error={actionError}
        reports={reports}
        refreshing={refreshing}
        stats={stats}
        status={status}
        onLogout={handleLogout}
        onOpenReport={setSelectedReport}
        onRefresh={handleRefresh}
        onStatusChange={handleStatusChange}
      />
      <ReportDetailSheet
        loading={working}
        report={selectedReport}
        onClose={() => setSelectedReport(null)}
        onBanUser={(userId, reason) => runAction(() => banUser(token!, userId, reason))}
        onDismiss={(reportId, notes) => runAction(() => dismissReport(token!, reportId, notes))}
        onRemovePost={(postId, reason, deleteStream) => runAction(() => removePost(token!, postId, reason, deleteStream))}
        onResolve={(reportId, notes, actionTaken) => runAction(() => resolveReport(token!, reportId, notes, actionTaken))}
        onUnbanUser={(userId) => runAction(() => unbanUser(token!, userId))}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.background,
  },
  centered: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.background,
    gap: 12,
  },
  loadingText: {
    color: colors.muted,
    fontSize: 14,
    fontWeight: '600',
  },
});
