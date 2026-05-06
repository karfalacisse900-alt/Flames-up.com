import React, { useEffect } from 'react';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { View, ActivityIndicator, StyleSheet } from 'react-native';
import { useAuthStore } from '../src/store/authStore';
import { colors } from '../src/utils/theme';

export default function RootLayout() {
  const { isLoading, loadUser } = useAuthStore();

  useEffect(() => {
    loadUser();
  }, []);

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
        <Stack.Screen name="user/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="conversation/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="group-conversation/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="call/[channel]" options={{ presentation: 'fullScreenModal' }} />
        <Stack.Screen name="place/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="event/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="recommendation/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="music/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="music-post/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="note/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="people/[id]" options={{ presentation: 'card' }} />
        <Stack.Screen name="create-post" options={{ presentation: 'card' }} />
        <Stack.Screen name="create-recommendation" options={{ presentation: 'card' }} />
        <Stack.Screen name="create-music-post" options={{ presentation: 'card' }} />
        <Stack.Screen name="create-note" options={{ presentation: 'card' }} />
        <Stack.Screen name="checkin-post" options={{ presentation: 'modal' }} />
        <Stack.Screen name="create-discover-post" options={{ presentation: 'modal' }} />
        <Stack.Screen name="create-status" options={{ presentation: 'modal' }} />
        <Stack.Screen name="verify-phone" options={{ presentation: 'modal' }} />
        <Stack.Screen name="notifications" options={{ presentation: 'card' }} />
        <Stack.Screen name="edit-profile" options={{ presentation: 'modal' }} />
        <Stack.Screen name="settings" options={{ presentation: 'card' }} />
        <Stack.Screen name="my-library" options={{ presentation: 'card' }} />
        <Stack.Screen name="referrals" options={{ presentation: 'card' }} />
        <Stack.Screen name="admin-panel" options={{ presentation: 'card' }} />
        <Stack.Screen name="content-manager" options={{ presentation: 'card' }} />
        <Stack.Screen name="my-spots" options={{ presentation: 'card' }} />
        <Stack.Screen name="drop-moment" options={{ presentation: 'modal' }} />
        <Stack.Screen name="tonight" options={{ presentation: 'card' }} />
        <Stack.Screen name="discover/story/[id]" options={{ presentation: 'card' }} />
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
