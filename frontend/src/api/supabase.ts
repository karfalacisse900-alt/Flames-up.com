import 'react-native-url-polyfill/auto';
import { createClient } from '@supabase/supabase-js';
import { AppState, Platform } from 'react-native';
import * as SecureStore from 'expo-secure-store';

const supabaseUrl = (process.env.EXPO_PUBLIC_SUPABASE_URL || '').trim();
const supabaseKey = (
  process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY
  || process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY
  || ''
).trim();

export function isSupabaseConfigured() {
  return supabaseUrl.startsWith('https://') && supabaseKey.length > 20;
}

export function getSupabaseProviderCallbackUrl() {
  return supabaseUrl ? `${supabaseUrl.replace(/\/+$/, '')}/auth/v1/callback` : '';
}

function hasBrowserStorage() {
  return typeof window !== 'undefined' && !!window.localStorage;
}

function isNativeRuntime() {
  return Platform.OS !== 'web'
    && typeof navigator !== 'undefined'
    && String((navigator as any).product || '').toLowerCase() === 'reactnative';
}

const supabaseStorage = {
  getItem: async (key: string) => {
    if (!hasBrowserStorage() && !isNativeRuntime()) return null;
    if (Platform.OS === 'web') {
      if (!hasBrowserStorage()) return null;
      return window.localStorage.getItem(key);
    }
    return SecureStore.getItemAsync(key);
  },
  setItem: async (key: string, value: string) => {
    if (!hasBrowserStorage() && !isNativeRuntime()) return;
    if (Platform.OS === 'web') {
      if (!hasBrowserStorage()) return;
      window.localStorage.setItem(key, value);
      return;
    }
    return SecureStore.setItemAsync(key, value);
  },
  removeItem: async (key: string) => {
    if (!hasBrowserStorage() && !isNativeRuntime()) return;
    if (Platform.OS === 'web') {
      if (!hasBrowserStorage()) return;
      window.localStorage.removeItem(key);
      return;
    }
    return SecureStore.deleteItemAsync(key);
  },
};

export const supabase = createClient(
  supabaseUrl || 'https://example.supabase.co',
  supabaseKey || 'missing-supabase-key',
  {
    auth: {
      storage: supabaseStorage,
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: false,
      flowType: 'pkce',
    },
  }
);

if (Platform.OS !== 'web') {
  AppState.addEventListener('change', (state) => {
    if (state === 'active') {
      supabase.auth.startAutoRefresh();
    } else {
      supabase.auth.stopAutoRefresh();
    }
  });
}
