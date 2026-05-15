import { makeRedirectUri } from 'expo-auth-session';
import * as WebBrowser from 'expo-web-browser';
import { Platform } from 'react-native';
import { getSupabaseProviderCallbackUrl, supabase } from './supabase';

type SupabaseOAuthProvider = 'google' | 'apple';

const PRODUCTION_AUTH_CALLBACK = 'https://flames-up.com/auth/callback';

export function getSupabaseOAuthRedirectTo() {
  const publicSiteUrl = (process.env.EXPO_PUBLIC_SITE_URL || 'https://flames-up.com').trim().replace(/\/+$/, '');

  if (Platform.OS !== 'web') {
    const nativeOverride = (process.env.EXPO_PUBLIC_SUPABASE_NATIVE_REDIRECT_URI || '').trim();
    if (nativeOverride) return nativeOverride;

    const genericOverride = (process.env.EXPO_PUBLIC_SUPABASE_REDIRECT_URI || '').trim();
    if (genericOverride && !genericOverride.startsWith('http')) return genericOverride;

    return makeRedirectUri({
      scheme: 'frontend',
      native: 'frontend://auth/callback',
      path: 'auth/callback',
    });
  }

  const webOverride = (
    process.env.EXPO_PUBLIC_SUPABASE_WEB_REDIRECT_URI
    || process.env.EXPO_PUBLIC_SUPABASE_REDIRECT_URI
    || ''
  ).trim();
  if (webOverride) return webOverride;

  if (Platform.OS === 'web') {
    const redirect = `${publicSiteUrl}/auth/callback`;
    return redirect.includes('localhost') || redirect.includes('127.0.0.1') ? PRODUCTION_AUTH_CALLBACK : redirect;
  }

  return PRODUCTION_AUTH_CALLBACK;
}

export function getSupabaseRedirectSetupHint() {
  return [
    `Google Cloud redirect URI: ${getSupabaseProviderCallbackUrl()}`,
    `Supabase app redirect URL: ${getSupabaseOAuthRedirectTo()}`,
  ].filter(Boolean).join('\n');
}

function readAuthParams(url: string) {
  const hash = url.includes('#') ? url.split('#')[1] : '';
  const query = url.includes('?') ? url.split('?')[1].split('#')[0] : '';
  const params = new URLSearchParams(hash || query);
  return {
    accessToken: params.get('access_token') || '',
    refreshToken: params.get('refresh_token') || '',
    code: params.get('code') || '',
    error: params.get('error_description') || params.get('error') || '',
  };
}

export async function createSupabaseSessionFromUrl(url: string) {
  const params = readAuthParams(url);
  if (params.error) throw new Error(params.error);

  if (params.accessToken && params.refreshToken) {
    const { data, error } = await supabase.auth.setSession({
      access_token: params.accessToken,
      refresh_token: params.refreshToken,
    });
    if (error) throw error;
    return data.session;
  }

  if (params.code) {
    const { data, error } = await supabase.auth.exchangeCodeForSession(params.code);
    if (error) {
      const message = String(error.message || '');
      if (message.toLowerCase().includes('code verifier') || message.toLowerCase().includes('external code')) {
        throw new Error('OAuth callback could not be exchanged. Start and finish Google sign-in in the same app/browser, or use the native app redirect frontend://auth/callback.');
      }
      throw error;
    }
    return data.session;
  }

  throw new Error('Supabase did not return an OAuth session.');
}

export async function startSupabaseOAuth(provider: SupabaseOAuthProvider) {
  const redirectTo = getSupabaseOAuthRedirectTo();
  if (redirectTo.includes('localhost') || redirectTo.includes('127.0.0.1')) {
    throw new Error(`OAuth redirect cannot use localhost on mobile. Current redirect: ${redirectTo}`);
  }

  const { data, error } = await supabase.auth.signInWithOAuth({
    provider,
    options: {
      redirectTo,
      skipBrowserRedirect: true,
      queryParams: provider === 'google'
        ? { access_type: 'offline', prompt: 'select_account' }
        : undefined,
    },
  });

  if (error) throw error;
  if (!data?.url) throw new Error('Supabase did not return an OAuth URL.');

  if (Platform.OS === 'web' && typeof window !== 'undefined') {
    window.location.assign(data.url);
    return new Promise(() => undefined);
  }

  const result = await WebBrowser.openAuthSessionAsync(data.url, redirectTo);
  if (result.type === 'success') {
    return createSupabaseSessionFromUrl(result.url);
  }
  if (result.type === 'cancel' || result.type === 'dismiss') {
    throw new Error('Sign in was canceled.');
  }
  throw new Error('Could not finish OAuth sign in.');
}
