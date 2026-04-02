import React, { useEffect, useState } from 'react';
import { View, StyleSheet, ActivityIndicator } from 'react-native';
import { Redirect } from 'expo-router';
import { useAuthStore } from '../src/store/authStore';
import { colors } from '../src/utils/theme';
import AsyncStorage from '@react-native-async-storage/async-storage';

const ONBOARDING_KEY = 'flames_up_onboarding_seen';

export default function Index() {
  const { isAuthenticated, isLoading } = useAuthStore();
  const [onboardingSeen, setOnboardingSeen] = useState<boolean | null>(null);

  useEffect(() => {
    checkOnboarding();
  }, []);

  const checkOnboarding = async () => {
    try {
      const seen = await AsyncStorage.getItem(ONBOARDING_KEY);
      setOnboardingSeen(seen === 'true');
    } catch {
      setOnboardingSeen(false);
    }
  };

  if (isLoading || onboardingSeen === null) {
    return (
      <View style={styles.container}>
        <ActivityIndicator size="large" color={colors.accentPrimary} />
      </View>
    );
  }

  // Show welcome page on first launch
  if (!onboardingSeen) {
    return <Redirect href="/welcome" />;
  }

  if (isAuthenticated) {
    return <Redirect href="/(tabs)/home" />;
  }

  return <Redirect href="/(auth)/login" />;
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.bgApp,
  },
});
