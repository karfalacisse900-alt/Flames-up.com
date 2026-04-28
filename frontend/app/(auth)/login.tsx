import React, { useEffect, useState } from 'react';
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
import * as AppleAuthentication from 'expo-apple-authentication';
import * as Google from 'expo-auth-session/providers/google';
import { makeRedirectUri } from 'expo-auth-session';
import * as WebBrowser from 'expo-web-browser';
import { useAuthStore } from '../../src/store/authStore';

WebBrowser.maybeCompleteAuthSession();

type AuthMethod = 'apple' | 'google' | 'phone' | 'email';

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
  variant: 'light' | 'phone' | 'email';
  loading?: boolean;
  disabled?: boolean;
  onPress: () => void;
}) {
  return (
    <TouchableOpacity
      style={[
        styles.methodButton,
        variant === 'phone' && styles.phoneButton,
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
  const { login, loginWithOAuth } = useAuthStore();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [showEmailForm, setShowEmailForm] = useState(false);
  const [activeSocialMethod, setActiveSocialMethod] = useState<AuthMethod | null>(null);

  const googleWebClientId = (process.env.EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID || '').trim();
  const googleIosClientId = (process.env.EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID || '').trim();
  const googleAndroidClientId = (process.env.EXPO_PUBLIC_GOOGLE_ANDROID_CLIENT_ID || '').trim();
  const hasGoogleClientId = (
    Platform.select({
      ios: !!googleIosClientId,
      android: !!googleAndroidClientId,
      default: !!googleWebClientId,
    }) || false
  );

  // expo-auth-session requires platform client IDs to be defined at hook init time.
  // Keep them as non-empty placeholders so the screen can render even before env setup.
  const placeholderGoogleClientId = 'missing-google-client-id.apps.googleusercontent.com';
  const safeGoogleWebClientId = googleWebClientId || placeholderGoogleClientId;
  const safeGoogleIosClientId = googleIosClientId || placeholderGoogleClientId;
  const safeGoogleAndroidClientId = googleAndroidClientId || placeholderGoogleClientId;

  const [googleRequest, googleResponse, promptGoogleAsync] = Google.useIdTokenAuthRequest({
    webClientId: safeGoogleWebClientId,
    iosClientId: safeGoogleIosClientId,
    androidClientId: safeGoogleAndroidClientId,
    redirectUri: makeRedirectUri({ scheme: 'frontend' }),
  });

  useEffect(() => {
    const handleGoogleResponse = async () => {
      if (googleResponse?.type !== 'success') return;
      const idToken = googleResponse.params?.id_token;
      if (!idToken) {
        Alert.alert('Google sign in failed', 'No token was returned from Google.');
        setActiveSocialMethod(null);
        return;
      }

      try {
        await loginWithOAuth('google', idToken);
        router.replace('/(tabs)/home');
      } catch (error: any) {
        Alert.alert('Google sign in failed', error?.response?.data?.detail || 'Could not sign in with Google.');
      } finally {
        setActiveSocialMethod(null);
      }
    };

    handleGoogleResponse();
  }, [googleResponse, loginWithOAuth, router]);

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
      Alert.alert('Login failed', error.response?.data?.detail || 'Invalid email or password.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleGooglePress = async () => {
    if (!hasGoogleClientId) {
      Alert.alert(
        'Google sign in not configured',
        'Please set EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID, EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID, and EXPO_PUBLIC_GOOGLE_ANDROID_CLIENT_ID.'
      );
      return;
    }
    if (!googleRequest) {
      Alert.alert('Google sign in', 'Google auth request is not ready yet. Please try again.');
      return;
    }
    setActiveSocialMethod('google');
    await promptGoogleAsync();
  };

  const handleApplePress = async () => {
    if (Platform.OS !== 'ios') {
      Alert.alert('Apple sign in', 'Apple sign in is supported on iOS devices.');
      return;
    }

    setActiveSocialMethod('apple');
    try {
      const credential = await AppleAuthentication.signInAsync({
        requestedScopes: [AppleAuthentication.AppleAuthenticationScope.FULL_NAME, AppleAuthentication.AppleAuthenticationScope.EMAIL],
      });

      if (!credential.identityToken) {
        Alert.alert('Apple sign in failed', 'No identity token was returned by Apple.');
        return;
      }

      await loginWithOAuth('apple', credential.identityToken);
      router.replace('/(tabs)/home');
    } catch (error: any) {
      const isCanceled = error?.code === 'ERR_REQUEST_CANCELED';
      if (!isCanceled) {
        Alert.alert('Apple sign in failed', error?.response?.data?.detail || 'Could not sign in with Apple.');
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
    if (method === 'phone') {
      Alert.alert('Phone sign in', 'Phone/OTP backend is the next auth method to enable.');
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
            <MethodButton
              icon="logo-apple"
              label="Continue with Apple"
              variant="light"
              loading={activeSocialMethod === 'apple'}
              disabled={!!activeSocialMethod}
              onPress={() => handleMethodPress('apple')}
            />
            <MethodButton
              icon="logo-google"
              label="Continue with Google"
              variant="light"
              loading={activeSocialMethod === 'google'}
              disabled={!!activeSocialMethod}
              onPress={() => handleMethodPress('google')}
            />
            <MethodButton
              icon="call-outline"
              label="Continue with Phone"
              variant="phone"
              disabled={!!activeSocialMethod}
              onPress={() => handleMethodPress('phone')}
            />
            <MethodButton
              icon="mail-outline"
              label="Log in with Email"
              variant="email"
              disabled={!!activeSocialMethod}
              onPress={() => handleMethodPress('email')}
            />
          </View>

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
    fontWeight: '700',
    fontStyle: 'italic',
    textAlign: 'center',
    width: '100%',
  },
  tagline: {
    marginTop: 20,
    color: '#151515',
    fontSize: 22,
    fontWeight: '800',
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
  phoneButton: {
    backgroundColor: '#4ED862',
  },
  emailButton: {
    backgroundColor: '#ECF259',
  },
  methodButtonText: {
    color: '#131313',
    fontSize: 17,
    fontWeight: '700',
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
    fontWeight: '700',
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
    fontWeight: '700',
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
});
