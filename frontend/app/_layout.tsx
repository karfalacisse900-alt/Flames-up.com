import React, { useEffect } from 'react';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { View, ActivityIndicator, StyleSheet, ScrollView, FlatList, SectionList, AppState } from 'react-native';
import { useAuthStore } from '../src/store/authStore';
import { useNotificationStore } from '../src/store/notificationStore';
import { colors } from '../src/utils/theme';
import { configureTypographyDefaults } from '../src/utils/typography';
import api from '../src/api/client';

configureTypographyDefaults();

function configureScrollDefaults() {
  const scrollDefaults = {
    bounces: false,
    alwaysBounceVertical: false,
    overScrollMode: 'never',
  };

  [ScrollView, FlatList, SectionList].forEach((Component) => {
    const scrollComponent = Component as unknown as { defaultProps?: Record<string, unknown> };
    scrollComponent.defaultProps = {
      ...(scrollComponent.defaultProps || {}),
      ...scrollDefaults,
    };
  });
}

configureScrollDefaults();

export default function RootLayout() {
  const { isLoading, loadUser, user } = useAuthStore();
  const refreshUnreadCount = useNotificationStore((state) => state.refreshUnreadCount);
  const resetNotifications = useNotificationStore((state) => state.reset);

  useEffect(() => {
    loadUser();
  }, []);

  useEffect(() => {
    if (!user?.id) return;
    const touchPresence = () => {
      api.post('/presence/touch').catch(() => {});
    };
    touchPresence();
    const interval = setInterval(touchPresence, 60_000);
    return () => clearInterval(interval);
  }, [user?.id]);

  useEffect(() => {
    if (!user?.id) {
      resetNotifications();
      return;
    }

    void refreshUnreadCount();
    const interval = setInterval(() => {
      if (AppState.currentState === 'active') void refreshUnreadCount();
    }, 30_000);
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') void refreshUnreadCount();
    });

    return () => {
      clearInterval(interval);
      subscription.remove();
    };
  }, [refreshUnreadCount, resetNotifications, user?.id]);

  if (isLoading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.accentPrimary} />
      </View>
    );
  }

  return (
    <>
      <StatusBar style="dark" />
      <Stack screenOptions={{ headerShown: false }}>
        <Stack.Screen name="index" />
        <Stack.Screen name="(auth)" />
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="post/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="note/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="user/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="conversation/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="group-conversation/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="call/[channel]" options={{ presentation: 'fullScreenModal' }} />
        <Stack.Screen name="place/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="event/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="recommendation/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="people/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="create-post" options={{ presentation: 'card' }} />
        <Stack.Screen name="create-recommendation" options={{ presentation: 'card' }} />
        <Stack.Screen name="checkin-post" options={{ presentation: 'modal' }} />
        <Stack.Screen name="create-status" options={{ presentation: 'modal' }} />
        <Stack.Screen name="verify-phone" options={{ presentation: 'modal' }} />
        <Stack.Screen name="notifications" options={{ presentation: 'card' }} />
        <Stack.Screen name="edit-profile" options={{ presentation: 'modal' }} />
        <Stack.Screen name="settings" options={{ presentation: 'card' }} />
        <Stack.Screen name="wallet" options={{ presentation: 'card' }} />
        <Stack.Screen name="my-library" options={{ presentation: 'card' }} />
        <Stack.Screen name="referrals" options={{ presentation: 'card' }} />
        <Stack.Screen name="admin-panel" options={{ presentation: 'card' }} />
        <Stack.Screen name="content-manager" options={{ presentation: 'card' }} />
        <Stack.Screen name="my-spots" options={{ presentation: 'card' }} />
        <Stack.Screen name="drop-moment" options={{ presentation: 'modal' }} />
        <Stack.Screen name="tonight" options={{ presentation: 'card' }} />
        <Stack.Screen name="scene/[context]/[category]" options={{ presentation: 'card' }} />
      </Stack>
    </>
  );
}

const styles = StyleSheet.create({
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.bgApp,
  },
});
