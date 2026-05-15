import React, { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { formatDistanceToNow } from 'date-fns';
import api from '../src/api/client';
import { EmptyState, NotificationSkeletonList } from '../src/components/PolishedStates';
import { useNotificationStore } from '../src/store/notificationStore';
import { appFontFamily } from '../src/utils/typography';
import { borderRadius, colors, hitSlop, layout, shadows, spacing } from '../src/utils/theme';

type NotificationIcon = {
  name: keyof typeof Ionicons.glyphMap;
  color: string;
};

function getNotificationData(notification: any) {
  if (!notification?.data) return {};
  if (typeof notification.data === 'object') return notification.data;
  try {
    return JSON.parse(notification.data);
  } catch {
    return {};
  }
}

function notificationIcon(type: string): NotificationIcon {
  switch (type) {
    case 'like':
      return { name: 'heart', color: colors.error };
    case 'comment':
    case 'comment_reply':
      return { name: 'chatbubble', color: colors.accentPrimary };
    case 'follow':
      return { name: 'person-add', color: colors.success };
    case 'message':
      return { name: 'chatbubble-ellipses', color: colors.info };
    case 'coin_gift':
      return { name: 'gift', color: colors.flameGold };
    case 'new_post':
      return { name: 'sparkles', color: colors.accentSecondary };
    default:
      return { name: 'notifications', color: colors.textSecondary };
  }
}

function safeTimeAgo(value?: string) {
  const createdAt = new Date(value || Date.now());
  return formatDistanceToNow(Number.isNaN(createdAt.getTime()) ? new Date() : createdAt, { addSuffix: true });
}

export default function NotificationsScreen() {
  const router = useRouter();
  const markAllRead = useNotificationStore((state) => state.markAllRead);
  const [notifications, setNotifications] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRetrying, setIsRetrying] = useState(false);
  const [errorText, setErrorText] = useState('');

  const loadNotifications = useCallback(async (quiet = false) => {
    if (!quiet) setIsLoading(true);
    setErrorText('');
    try {
      const response = await api.get('/notifications');
      const rows = Array.isArray(response.data) ? response.data : [];
      setNotifications(rows);
      await markAllRead();
    } catch {
      setErrorText('Notifications could not load. Please try again.');
    } finally {
      setIsLoading(false);
      setIsRetrying(false);
    }
  }, [markAllRead]);

  useEffect(() => {
    loadNotifications();
  }, [loadNotifications]);

  const handleNotificationPress = (notification: any) => {
    const data = getNotificationData(notification);
    switch (notification.type) {
      case 'like':
      case 'comment':
      case 'comment_reply':
      case 'new_post':
        if (data?.post_id) router.push(`/post/${data.post_id}` as any);
        break;
      case 'follow':
        if (data?.follower_id || data?.from_user_id) router.push(`/user/${data.follower_id || data.from_user_id}` as any);
        break;
      case 'message':
        if (data?.conversation_id) router.push(`/conversation/${data.conversation_id}` as any);
        else if (data?.sender_id) router.push(`/conversation/${data.sender_id}` as any);
        break;
      case 'coin_gift':
        if (data?.post_id) router.push(`/post/${data.post_id}` as any);
        else router.push('/wallet' as any);
        break;
      default:
        break;
    }
  };

  const renderNotification = ({ item }: { item: any }) => {
    const icon = notificationIcon(String(item.type || 'general'));
    const unread = !item.is_read;

    return (
      <TouchableOpacity
        style={[styles.notificationItem, unread && styles.notificationUnread]}
        onPress={() => handleNotificationPress(item)}
        activeOpacity={0.86}
        accessibilityRole="button"
        accessibilityLabel={`${item.title || 'Notification'}: ${item.body || ''}`}
      >
        <View style={[styles.iconContainer, { backgroundColor: `${icon.color}18` }]}>
          <Ionicons name={icon.name} size={19} color={icon.color} />
        </View>
        <View style={styles.notificationContent}>
          <View style={styles.titleRow}>
            <Text style={styles.notificationTitle} numberOfLines={1}>{item.title || 'New activity'}</Text>
            {unread ? <View style={styles.unreadDot} /> : null}
          </View>
          <Text style={styles.notificationBody} numberOfLines={2}>{item.body || 'Something new happened on Flames-Up.'}</Text>
          <Text style={styles.notificationTime}>{safeTimeAgo(item.created_at)}</Text>
        </View>
        <Ionicons name="chevron-forward" size={18} color={colors.textDisabled} />
      </TouchableOpacity>
    );
  };

  const retry = () => {
    setIsRetrying(true);
    loadNotifications(true);
  };

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.header}>
        <TouchableOpacity style={styles.headerButton} onPress={() => router.back()} hitSlop={hitSlop} activeOpacity={0.84}>
          <Ionicons name="chevron-back" size={24} color={colors.textPrimary} />
        </TouchableOpacity>
        <View style={styles.headerTextWrap}>
          <Text style={styles.headerTitle}>Notifications</Text>
          <Text style={styles.headerSubtitle}>Likes, comments, follows, gifts, and posts</Text>
        </View>
        <TouchableOpacity style={styles.headerButton} onPress={retry} disabled={isRetrying} hitSlop={hitSlop} activeOpacity={0.84}>
          {isRetrying ? <ActivityIndicator size="small" color={colors.accentPrimary} /> : <Ionicons name="refresh" size={19} color={colors.accentPrimary} />}
        </TouchableOpacity>
      </View>

      {isLoading ? (
        <NotificationSkeletonList count={7} />
      ) : (
        <FlatList
          data={notifications}
          renderItem={renderNotification}
          keyExtractor={(item, index) => String(item?.id || `notification-${index}`)}
          contentContainerStyle={[styles.listContent, notifications.length === 0 && styles.listEmptyContent]}
          ItemSeparatorComponent={() => <View style={styles.separator} />}
          ListHeaderComponent={errorText ? (
            <View style={styles.errorCard}>
              <Ionicons name="alert-circle-outline" size={18} color={colors.error} />
              <Text style={styles.errorText}>{errorText}</Text>
            </View>
          ) : null}
          ListEmptyComponent={(
            <EmptyState
              icon="notifications-outline"
              title="No notifications yet"
              body="When someone follows you, likes your post, comments, sends a gift, or posts something new, it will show here."
              actionLabel="Check again"
              onAction={retry}
            />
          )}
          showsVerticalScrollIndicator={false}
        />
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bgApp,
  },
  header: {
    minHeight: 72,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.gutter,
    paddingHorizontal: spacing.md,
    paddingTop: spacing.xs,
    paddingBottom: spacing.gutter,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.divider,
    backgroundColor: colors.bgApp,
  },
  headerButton: {
    width: layout.minTouchTarget,
    height: layout.minTouchTarget,
    borderRadius: layout.minTouchTarget / 2,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation1,
  },
  headerTextWrap: {
    flex: 1,
    minWidth: 0,
  },
  headerTitle: {
    color: colors.textPrimary,
    fontFamily: appFontFamily,
    fontSize: 24,
    lineHeight: 29,
    fontWeight: '600',
  },
  headerSubtitle: {
    marginTop: 2,
    color: colors.textSecondary,
    fontFamily: appFontFamily,
    fontSize: 12,
    lineHeight: 16,
    fontWeight: '400',
  },
  listContent: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    paddingBottom: spacing.xxl,
  },
  listEmptyContent: {
    flexGrow: 1,
    justifyContent: 'center',
  },
  notificationItem: {
    minHeight: 78,
    borderRadius: borderRadius.xl,
    backgroundColor: colors.surfaceRaised,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.gutter,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation1,
  },
  notificationUnread: {
    backgroundColor: '#FBFFF5',
    borderColor: 'rgba(32,54,31,0.12)',
  },
  iconContainer: {
    width: 46,
    height: 46,
    borderRadius: 23,
    justifyContent: 'center',
    alignItems: 'center',
  },
  notificationContent: {
    flex: 1,
    minWidth: 0,
  },
  titleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  notificationTitle: {
    flex: 1,
    minWidth: 0,
    color: colors.textPrimary,
    fontFamily: appFontFamily,
    fontSize: 15,
    lineHeight: 20,
    fontWeight: '600',
  },
  unreadDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.accentPrimary,
  },
  notificationBody: {
    marginTop: 2,
    color: colors.textSecondary,
    fontFamily: appFontFamily,
    fontSize: 13,
    lineHeight: 18,
    fontWeight: '400',
  },
  notificationTime: {
    marginTop: 5,
    color: colors.textHint,
    fontFamily: appFontFamily,
    fontSize: 11,
    lineHeight: 14,
    fontWeight: '400',
  },
  separator: {
    height: spacing.sm,
  },
  errorCard: {
    minHeight: 44,
    marginBottom: spacing.sm,
    borderRadius: borderRadius.lg,
    backgroundColor: '#FFF4F6',
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingHorizontal: spacing.md,
  },
  errorText: {
    flex: 1,
    color: colors.error,
    fontFamily: appFontFamily,
    fontSize: 13,
    lineHeight: 18,
    fontWeight: '500',
  },
});
