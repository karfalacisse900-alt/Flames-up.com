import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Link, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as WebBrowser from 'expo-web-browser';
import * as AppleAuthentication from 'expo-apple-authentication';
import { useAuthStore } from '../../src/store/authStore';
import { getSupabaseRedirectSetupHint } from '../../src/api/supabaseOAuth';

WebBrowser.maybeCompleteAuthSession();

type AuthMethod = 'apple' | 'google' | 'email';

const SHOW_APPLE_SIGN_IN = process.env.EXPO_PUBLIC_ENABLE_APPLE_SIGN_IN !== '0'
  && (Platform.OS === 'ios' || Platform.OS === 'web');
const GOOGLE_WEB_CLIENT_ID = (process.env.EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID || '').trim();
const GOOGLE_IOS_CLIENT_ID = (process.env.EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID || '').trim();
const GOOGLE_ANDROID_CLIENT_ID = (process.env.EXPO_PUBLIC_GOOGLE_ANDROID_CLIENT_ID || '').trim();

type NativeGoogleSignInModule = typeof import('@react-native-google-signin/google-signin');

type GoogleCredentialResponse = {
  credential?: string;
  select_by?: string;
};

async function getNativeGoogleSignIn() {
  try {
    return await import('@react-native-google-signin/google-signin') as NativeGoogleSignInModule;
  } catch {
    throw new Error('Google sign in needs a development or production build. Expo Go does not include the native Google Sign-In module.');
  }
}

let googleIdentityScriptPromise: Promise<void> | null = null;

function getGoogleIdentity() {
  if (Platform.OS !== 'web' || typeof window === 'undefined') return null;
  return (window as any).google?.accounts?.id || null;
}

function loadGoogleIdentityScript() {
  if (Platform.OS !== 'web' || typeof document === 'undefined') {
    return Promise.reject(new Error('Google web sign-in is only available in the browser.'));
  }
  if (getGoogleIdentity()) return Promise.resolve();
  if (googleIdentityScriptPromise) return googleIdentityScriptPromise;

  googleIdentityScriptPromise = new Promise((resolve, reject) => {
    const existing = document.querySelector('script[src="https://accounts.google.com/gsi/client"]');
    if (existing) {
      existing.addEventListener('load', () => resolve(), { once: true });
      existing.addEventListener('error', () => reject(new Error('Could not load Google sign-in.')), { once: true });
      return;
    }

    const script = document.createElement('script');
    script.src = 'https://accounts.google.com/gsi/client';
    script.async = true;
    script.defer = true;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error('Could not load Google sign-in.'));
    document.head.appendChild(script);
  });

  return googleIdentityScriptPromise;
}

function formatAppleFullName(fullName?: AppleAuthentication.AppleAuthenticationFullName | null) {
  if (!fullName) return '';
  return [
    fullName.givenName,
    fullName.middleName,
    fullName.familyName,
  ].filter(Boolean).join(' ').trim();
}

function GoogleIdentityWebButton({
  disabled,
  loading,
  onCredential,
  onError,
}: {
  disabled?: boolean;
  loading?: boolean;
  onCredential: (credential: string) => void;
  onError: (message: string) => void;
}) {
  const buttonRef = useRef<any>(null);
  const credentialRef = useRef(onCredential);
  const errorRef = useRef(onError);
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    credentialRef.current = onCredential;
    errorRef.current = onError;
  }, [onCredential, onError]);

  useEffect(() => {
    if (Platform.OS !== 'web') return;
    if (!GOOGLE_WEB_CLIENT_ID) {
      errorRef.current('Google web client ID is missing.');
      return;
    }

    let cancelled = false;
    loadGoogleIdentityScript()
      .then(() => {
        if (cancelled) return;
        const googleIdentity = getGoogleIdentity();
        const container = buttonRef.current;
        if (!googleIdentity || !container) throw new Error('Google sign-in is not ready.');

        googleIdentity.initialize({
          client_id: GOOGLE_WEB_CLIENT_ID,
          callback: (response: GoogleCredentialResponse) => {
            if (response?.credential) {
              credentialRef.current(response.credential);
            } else {
              errorRef.current('Google did not return a sign-in credential.');
            }
          },
          auto_select: false,
          cancel_on_tap_outside: true,
          use_fedcm_for_prompt: true,
        });

        container.innerHTML = '';
        googleIdentity.renderButton(container, {
          type: 'standard',
          theme: 'outline',
          size: 'large',
          text: 'continue_with',
          shape: 'pill',
          logo_alignment: 'left',
          width: Math.min(360, Math.max(280, window.innerWidth - 56)),
        });
        setIsReady(true);
      })
      .catch((error: any) => {
        if (!cancelled) errorRef.current(error?.message || 'Google sign-in could not load.');
      });

    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <View style={[styles.googleCard, disabled && styles.methodButtonDisabled]}>
      <View style={styles.googleCopy}>
        <Text style={styles.googleTitle}>Sign in with Google</Text>
        <Text style={styles.googleSubtitle}>Secure account login with no redirect loop.</Text>
      </View>
      <View style={styles.googleButtonShell}>
        {React.createElement('div', {
          ref: buttonRef,
          style: {
            minHeight: 44,
            display: loading || disabled ? 'none' : 'flex',
            justifyContent: 'center',
            width: '100%',
          },
        })}
        {!isReady || loading || disabled ? (
          <View style={styles.googleLoadingOverlay}>
            <ActivityIndicator color="#171717" />
            <Text style={styles.googleLoadingText}>
              {loading ? 'Signing you in...' : 'Preparing Google...'}
            </Text>
          </View>
        ) : null}
      </View>
    </View>
  );
}

function MethodButton({
  icon,
  label,
  variant,
  loading,
  disabled,
  onPress,
}: {
  icon: keyof typeof Ionicons.glyphMap;
  label: string;
  variant: 'light' | 'email';
  loading?: boolean;
  disabled?: boolean;
  onPress: () => void;
}) {
  return (
    <TouchableOpacity
      style={[
        styles.methodButton,
        variant === 'email' && styles.emailButton,
        disabled && styles.methodButtonDisabled,
      ]}
      onPress={onPress}
      activeOpacity={0.9}
      disabled={disabled}
    >
      {loading ? (
        <ActivityIndicator color="#171717" />
      ) : (
        <Ionicons name={icon} size={30} color="#151515" />
      )}
      <Text style={styles.methodButtonText}>{label}</Text>
    </TouchableOpacity>
  );
}

export default function LoginScreen() {
  const router = useRouter();
  const { login, loginWithOAuth, loginWithOAuthProvider } = useAuthStore();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [showEmailForm, setShowEmailForm] = useState(false);
  const [activeSocialMethod, setActiveSocialMethod] = useState<AuthMethod | null>(null);
  const [authError, setAuthError] = useState('');

  const handleLogin = async () => {
    if (!email || !password) {
      Alert.alert('Missing details', 'Please enter your email and password.');
      return;
    }

    setIsLoading(true);
    try {
      await login(email, password);
      router.replace('/(tabs)/home');
    } catch (error: any) {
      Alert.alert('Login failed', error.response?.data?.detail || error?.message || 'Invalid email or password.');
    } finally {
      setIsLoading(false);
    }
  };

  const finishGoogleIdTokenLogin = useCallback(async (credential: string, authSurface: string) => {
    try {
      setAuthError('');
      setActiveSocialMethod('google');
      await loginWithOAuth('google', credential, {
        auth_surface: authSurface,
      });
      router.replace('/(tabs)/home');
    } catch (error: any) {
      const detail = error?.response?.data?.detail || error?.message || 'Could not sign in with Google.';
      setAuthError(detail);
      Alert.alert('Google sign in failed', detail);
    } finally {
      setActiveSocialMethod(null);
    }
  }, [loginWithOAuth, router]);

  const handleGoogleCredential = useCallback(async (credential: string) => {
    await finishGoogleIdTokenLogin(credential, 'google_identity_services');
  }, [finishGoogleIdTokenLogin]);

  const handleGooglePress = async () => {
    try {
      setAuthError('');
      setActiveSocialMethod('google');
      if (Platform.OS === 'web') {
        throw new Error('Use the Google button on this page to sign in on web.');
      }
      if (Platform.OS === 'ios' && !GOOGLE_IOS_CLIENT_ID) {
        throw new Error('Google iOS client ID is missing. Add EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID from your Google Cloud iOS OAuth client, then rebuild/restart Expo.');
      }
      if (Platform.OS === 'android' && !GOOGLE_ANDROID_CLIENT_ID) {
        throw new Error('Google Android client ID is missing. Add EXPO_PUBLIC_GOOGLE_ANDROID_CLIENT_ID from your Google Cloud Android OAuth client, then rebuild/restart Expo.');
      }
      const { GoogleSignin } = await getNativeGoogleSignIn();
      GoogleSignin.configure({
        webClientId: GOOGLE_WEB_CLIENT_ID || undefined,
        iosClientId: GOOGLE_IOS_CLIENT_ID || undefined,
        offlineAccess: false,
        scopes: ['profile', 'email'],
      });
      if (Platform.OS === 'android') {
        await GoogleSignin.hasPlayServices({ showPlayServicesUpdateDialog: true });
      }
      const result = await GoogleSignin.signIn();
      if (result.type === 'cancelled') {
        return;
      }
      let idToken = result.data.idToken || '';
      if (!idToken) idToken = (await GoogleSignin.getTokens()).idToken;
      if (!idToken) {
        throw new Error('Google did not return an ID token.');
      }
      await loginWithOAuth('google', idToken, {
        auth_surface: 'native_google_signin',
      });
      router.replace('/(tabs)/home');
    } catch (error: any) {
      const code = String(error?.code || '');
      if (code === 'SIGN_IN_CANCELLED' || code === 'cancelled') {
        return;
      }
      const detail = error?.response?.data?.detail || error?.message || 'Could not sign in with Google.';
      setAuthError(detail);
      Alert.alert('Google sign in failed', detail);
    } finally {
      setActiveSocialMethod(null);
    }
  };

  const handleGoogleWebError = useCallback((message: string) => {
    setAuthError(message);
  }, []);

  const handleApplePress = async () => {
    try {
      setAuthError('');
      setActiveSocialMethod('apple');
      if (Platform.OS === 'ios') {
        const available = await AppleAuthentication.isAvailableAsync();
        if (!available) throw new Error('Apple sign in is not available on this device.');

        const credential = await AppleAuthentication.signInAsync({
          requestedScopes: [
            AppleAuthentication.AppleAuthenticationScope.FULL_NAME,
            AppleAuthentication.AppleAuthenticationScope.EMAIL,
          ],
        });
        if (!credential.identityToken) {
          throw new Error('Apple did not return an identity token.');
        }

        await loginWithOAuth('apple', credential.identityToken, {
          auth_surface: 'native_apple_authentication',
          apple_user: credential.user,
          email: credential.email || undefined,
          full_name: formatAppleFullName(credential.fullName) || undefined,
        });
      } else {
        await loginWithOAuthProvider('apple');
      }
      router.replace('/(tabs)/home');
    } catch (error: any) {
      const code = String(error?.code || '');
      const detail = error?.response?.data?.detail || error?.message || 'Could not sign in with Apple.';
      const lower = detail.toLowerCase();
      const setupHint = lower.includes('provider') && lower.includes('disabled')
        ? '\n\nEnable Apple in Supabase Dashboard > Authentication > Providers > Apple, then add the Apple Service ID, Team ID, Key ID, and private key.'
        : lower.includes('redirect')
          ? `\n\n${getSupabaseRedirectSetupHint()}`
          : '';
      if (!lower.includes('canceled') && !code.includes('ERR_REQUEST_CANCELED')) {
        setAuthError(detail);
        Alert.alert('Apple sign in failed', `${detail}${setupHint}`);
      }
    } finally {
      setActiveSocialMethod(null);
    }
  };

  const handleMethodPress = async (method: AuthMethod) => {
    if (method === 'email') {
      setShowEmailForm(true);
      return;
    }
    if (method === 'google') {
      await handleGooglePress();
      return;
    }
    await handleApplePress();
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="dark-content" />
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        style={styles.keyboard}
      >
        <ScrollView contentContainerStyle={styles.scrollContent} keyboardShouldPersistTaps="handled">
          <View style={styles.decorativeLayer} pointerEvents="none">
            <Ionicons name="heart" size={38} color="#D678F6" style={[styles.decoration, { top: 30, left: 28 }]} />
            <Ionicons name="rainy-outline" size={36} color="#3B3B3B" style={[styles.decoration, { top: 200, right: 36 }]} />
            <Ionicons name="star-outline" size={44} color="#151515" style={[styles.decoration, { top: 280, right: 58 }]} />
            <Ionicons name="happy-outline" size={44} color="#1E2E1E" style={[styles.decoration, { top: 260, left: 84 }]} />
            <Ionicons name="sparkles-outline" size={36} color="#F1BC2A" style={[styles.decoration, { top: 520, right: 58 }]} />
          </View>

          <View style={styles.hero}>
            <Text style={styles.brand} numberOfLines={1} adjustsFontSizeToFit>
              flames-up
            </Text>
            <Text style={styles.tagline}>If it is lit, it is here.</Text>
          </View>

          <View style={styles.methodsWrap}>
            {SHOW_APPLE_SIGN_IN ? (
              <MethodButton
                icon="logo-apple"
                label="Continue with Apple"
                variant="light"
                loading={activeSocialMethod === 'apple'}
                disabled={!!activeSocialMethod}
                onPress={() => handleMethodPress('apple')}
              />
            ) : null}
            {Platform.OS === 'web' ? (
              <GoogleIdentityWebButton
                loading={activeSocialMethod === 'google'}
                disabled={!!activeSocialMethod}
                onCredential={handleGoogleCredential}
                onError={handleGoogleWebError}
              />
            ) : (
              <MethodButton
                icon="logo-google"
                label="Continue with Google"
                variant="light"
                loading={activeSocialMethod === 'google'}
                disabled={!!activeSocialMethod}
                onPress={() => handleMethodPress('google')}
              />
            )}
            <MethodButton
              icon="mail-outline"
              label="Log in with Email"
              variant="email"
              disabled={!!activeSocialMethod}
              onPress={() => handleMethodPress('email')}
            />
          </View>
          {authError ? (
            <View style={styles.authErrorBox}>
              <Ionicons name="alert-circle-outline" size={18} color="#111111" />
              <Text style={styles.authErrorText}>{authError}</Text>
            </View>
          ) : null}

          {showEmailForm ? (
            <View style={styles.emailForm}>
              <View style={styles.inputWrap}>
                <Ionicons name="mail-outline" size={20} color="#5E5E5E" />
                <TextInput
                  style={styles.input}
                  placeholder="Email address"
                  placeholderTextColor="#6D6D6D"
                  value={email}
                  onChangeText={setEmail}
                  autoCapitalize="none"
                  autoCorrect={false}
                  keyboardType="email-address"
                />
              </View>

              <View style={styles.inputWrap}>
                <Ionicons name="lock-closed-outline" size={20} color="#5E5E5E" />
                <TextInput
                  style={styles.input}
                  placeholder="Password"
                  placeholderTextColor="#6D6D6D"
                  value={password}
                  onChangeText={setPassword}
                  secureTextEntry={!showPassword}
                />
                <TouchableOpacity onPress={() => setShowPassword(!showPassword)}>
                  <Ionicons
                    name={showPassword ? 'eye-off-outline' : 'eye-outline'}
                    size={20}
                    color="#5E5E5E"
                  />
                </TouchableOpacity>
              </View>

              <TouchableOpacity
                style={[styles.signInButton, isLoading && styles.signInButtonDisabled]}
                onPress={handleLogin}
                disabled={isLoading}
              >
                {isLoading ? (
                  <ActivityIndicator color="#FFFFFF" />
                ) : (
                  <Text style={styles.signInButtonText}>Sign In</Text>
                )}
              </TouchableOpacity>

              <View style={styles.registerRow}>
                <Text style={styles.registerText}>Need an account?</Text>
                <Link href="/(auth)/register" asChild>
                  <TouchableOpacity>
                    <Text style={styles.registerLink}>Sign Up</Text>
                  </TouchableOpacity>
                </Link>
              </View>

              <TouchableOpacity style={styles.backToMethods} onPress={() => setShowEmailForm(false)}>
                <Text style={styles.backToMethodsText}>Back to all sign-in options</Text>
              </TouchableOpacity>
            </View>
          ) : null}

          <View style={styles.legalFooter}>
            <Text style={styles.legalText}>By continuing, you agree to Captro's legal and safety terms.</Text>
            <View style={styles.legalLinks}>
              <Link href={'/legal/terms' as any} asChild>
                <TouchableOpacity style={styles.legalPill}><Text style={styles.legalPillText}>Terms</Text></TouchableOpacity>
              </Link>
              <Link href={'/legal/privacy' as any} asChild>
                <TouchableOpacity style={styles.legalPill}><Text style={styles.legalPillText}>Privacy</Text></TouchableOpacity>
              </Link>
              <Link href={'/legal/community-guidelines' as any} asChild>
                <TouchableOpacity style={styles.legalPill}><Text style={styles.legalPillText}>Guidelines</Text></TouchableOpacity>
              </Link>
              <Link href={'/legal/safety' as any} asChild>
                <TouchableOpacity style={styles.legalPill}><Text style={styles.legalPillText}>Safety</Text></TouchableOpacity>
              </Link>
            </View>
            <Text style={styles.supportText}>Support: karfalacisse900@gmail.com</Text>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#49D556',
  },
  keyboard: {
    flex: 1,
  },
  scrollContent: {
    flexGrow: 1,
    paddingHorizontal: 22,
    paddingBottom: 30,
  },
  decorativeLayer: {
    ...StyleSheet.absoluteFillObject,
  },
  decoration: {
    position: 'absolute',
  },
  hero: {
    marginTop: 120,
    alignItems: 'center',
  },
  brand: {
    fontSize: 66,
    lineHeight: 72,
    color: '#171717',
    fontWeight: '500',
    fontStyle: 'italic',
    textAlign: 'center',
    width: '100%',
  },
  tagline: {
    marginTop: 20,
    color: '#151515',
    fontSize: 22,
    fontWeight: '600',
    textAlign: 'center',
    lineHeight: 28,
  },
  methodsWrap: {
    marginTop: 80,
    gap: 14,
  },
  methodButton: {
    height: 66,
    borderRadius: 33,
    backgroundColor: '#F4F4F4',
    borderWidth: 2,
    borderColor: '#1E1E1E',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 14,
  },
  methodButtonDisabled: {
    opacity: 0.7,
  },
  emailButton: {
    backgroundColor: '#ECF259',
  },
  methodButtonText: {
    color: '#131313',
    fontSize: 17,
    fontWeight: '500',
  },
  googleCard: {
    borderRadius: 24,
    borderWidth: 2,
    borderColor: '#161616',
    backgroundColor: '#F8F8F4',
    padding: 14,
    gap: 12,
  },
  googleCopy: {
    gap: 3,
    alignItems: 'center',
  },
  googleTitle: {
    color: '#111111',
    fontSize: 18,
    lineHeight: 22,
    fontWeight: '700',
  },
  googleSubtitle: {
    color: '#4A4A4A',
    fontSize: 13,
    lineHeight: 18,
    fontWeight: '500',
    textAlign: 'center',
  },
  googleButtonShell: {
    minHeight: 48,
    alignItems: 'center',
    justifyContent: 'center',
  },
  googleLoadingOverlay: {
    minHeight: 48,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
  },
  googleLoadingText: {
    color: '#171717',
    fontSize: 14,
    fontWeight: '600',
  },
  authErrorBox: {
    marginTop: 12,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#111111',
    backgroundColor: 'rgba(255,255,255,0.78)',
    paddingHorizontal: 12,
    paddingVertical: 10,
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 8,
  },
  authErrorText: {
    flex: 1,
    color: '#111111',
    fontSize: 13,
    lineHeight: 18,
    fontWeight: '600',
  },
  emailForm: {
    marginTop: 20,
    backgroundColor: 'rgba(255,255,255,0.88)',
    borderRadius: 18,
    borderWidth: 1,
    borderColor: '#1E1E1E',
    padding: 14,
    gap: 10,
  },
  inputWrap: {
    height: 54,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#C5C5C5',
    backgroundColor: '#FFFFFF',
    paddingHorizontal: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  input: {
    flex: 1,
    color: '#171717',
    fontSize: 16,
  },
  signInButton: {
    marginTop: 6,
    height: 54,
    borderRadius: 12,
    backgroundColor: '#181818',
    justifyContent: 'center',
    alignItems: 'center',
  },
  signInButtonDisabled: {
    opacity: 0.7,
  },
  signInButtonText: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '500',
  },
  registerRow: {
    marginTop: 4,
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 6,
  },
  registerText: {
    color: '#404040',
    fontSize: 14,
  },
  registerLink: {
    color: '#161616',
    fontSize: 14,
    fontWeight: '500',
  },
  backToMethods: {
    alignItems: 'center',
    paddingVertical: 4,
  },
  backToMethodsText: {
    color: '#2E2E2E',
    fontSize: 13,
    fontWeight: '600',
  },
  legalFooter: {
    marginTop: 28,
    alignItems: 'center',
    gap: 10,
  },
  legalText: {
    color: '#151515',
    opacity: 0.72,
    fontSize: 12,
    lineHeight: 17,
    fontWeight: '600',
    textAlign: 'center',
  },
  legalLinks: {
    width: '100%',
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    justifyContent: 'center',
  },
  legalPill: {
    minWidth: 96,
    height: 34,
    paddingHorizontal: 12,
    borderRadius: 17,
    backgroundColor: 'rgba(244,244,244,0.86)',
    borderWidth: 1,
    borderColor: 'rgba(30,30,30,0.18)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  legalPillText: {
    color: '#151515',
    fontSize: 12,
    fontWeight: '700',
  },
  supportText: {
    color: '#151515',
    opacity: 0.72,
    fontSize: 12,
    fontWeight: '700',
    textAlign: 'center',
  },
});
