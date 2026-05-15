import React, { useEffect, useState } from 'react';
import { ActivityIndicator, Platform, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import * as Linking from 'expo-linking';
import * as WebBrowser from 'expo-web-browser';
import { useRouter } from 'expo-router';
import { createSupabaseSessionFromUrl } from '../../src/api/supabaseOAuth';
import { useAuthStore } from '../../src/store/authStore';

WebBrowser.maybeCompleteAuthSession();

async function getCallbackUrl() {
  if (Platform.OS === 'web' && typeof window !== 'undefined') {
    return window.location.href;
  }
  return Linking.getInitialURL();
}

export default function AuthCallbackScreen() {
  const router = useRouter();
  const finishSupabaseSession = useAuthStore((state) => state.finishSupabaseSession);
  const [message, setMessage] = useState('Finishing sign in...');
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let mounted = true;

    const finish = async () => {
      try {
        const url = await getCallbackUrl();
        if (!url) throw new Error('Missing auth callback URL.');
        const session = await createSupabaseSessionFromUrl(url);
        await finishSupabaseSession(session, { oauth_callback: true });
        if (mounted) router.replace('/(tabs)/home');
      } catch (error: any) {
        if (mounted) {
          const detail = error?.response?.data?.detail || error?.message || 'Could not finish sign in.';
          setFailed(true);
          setMessage(`Sign in could not finish: ${detail}`);
        }
      }
    };

    finish();
    return () => {
      mounted = false;
    };
  }, [finishSupabaseSession, router]);

  return (
    <View style={styles.root}>
      {failed ? null : <ActivityIndicator color="#111111" />}
      <Text style={styles.text}>{message}</Text>
      {failed ? (
        <TouchableOpacity style={styles.button} onPress={() => router.replace('/(auth)/login')}>
          <Text style={styles.buttonText}>Back to login</Text>
        </TouchableOpacity>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
    backgroundColor: '#FFFFFF',
    paddingHorizontal: 24,
  },
  text: {
    color: '#111111',
    fontSize: 15,
    lineHeight: 21,
    fontWeight: '500',
    textAlign: 'center',
  },
  button: {
    marginTop: 8,
    borderRadius: 999,
    backgroundColor: '#111111',
    paddingHorizontal: 18,
    paddingVertical: 10,
  },
  buttonText: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '700',
  },
});
