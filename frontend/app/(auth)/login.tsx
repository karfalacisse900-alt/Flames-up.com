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
  const { login, loginWithOAuth, startPhoneLogin, verifyPhoneLogin } = useAuthStore();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [phone, setPhone] = useState('');
  const [phoneCode, setPhoneCode] = useState('');
  const [phoneStep, setPhoneStep] = useState<'phone' | 'code'>('phone');
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [isPhoneLoading, setIsPhoneLoading] = useState(false);
  const [showEmailForm, setShowEmailForm] = useState(false);
  const [showPhoneForm, setShowPhoneForm] = useState(false);
  const [activeSocialMethod, setActiveSocialMethod] = useState<AuthMethod | null>(null);

  const googleWebClientId = (process.env.EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID || '').trim();
  const googleIosClientId = (process.env.EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID || '').trim();
  const googleAndroidClientId = (process.env.EXPO_PUBLIC_GOOGLE_ANDROID_CLIENT_ID || '').trim();
  const activeGoogleClientId = Platform.select({
    ios: googleIosClientId || googleWebClientId,
    android: googleAndroidClientId || googleWebClientId,
    default: googleWebClientId,
  });
  const hasGoogleClientId = !!activeGoogleClientId;

  // expo-auth-session requires platform client IDs to be defined at hook init time.
  // Keep them as non-empty placeholders so the screen can render even before env setup.
  const placeholderGoogleClientId = 'missing-google-client-id.apps.googleusercontent.com';
  const safeGoogleWebClientId = googleWebClientId || placeholderGoogleClientId;
  const safeGoogleIosClientId = googleIosClientId || googleWebClientId || placeholderGoogleClientId;
  const safeGoogleAndroidClientId = googleAndroidClientId || googleWebClientId || placeholderGoogleClientId;

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
        'Set EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID for Expo Go, and add EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID / EXPO_PUBLIC_GOOGLE_ANDROID_CLIENT_ID for production builds.'
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
      const isAvailable = await AppleAuthentication.isAvailableAsync();
      if (!isAvailable) {
        Alert.alert('Apple sign in unavailable', 'This device or build does not support Sign in with Apple.');
        return;
      }

      const credential = await AppleAuthentication.signInAsync({
        requestedScopes: [AppleAuthentication.AppleAuthenticationScope.FULL_NAME, AppleAuthentication.AppleAuthenticationScope.EMAIL],
      });

      if (!credential.identityToken) {
        Alert.alert('Apple sign in failed', 'No identity token was returned by Apple.');
        return;
      }

      const formattedFullName = credential.fullName
        ? AppleAuthentication.formatFullName(credential.fullName)
        : '';

      await loginWithOAuth('apple', credential.identityToken, {
        apple_user: credential.user,
        email: credential.email,
        full_name: formattedFullName,
        authorization_code: credential.authorizationCode,
      });
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

  const handlePhoneStart = async () => {
    const trimmedPhone = phone.trim();
    if (!trimmedPhone) {
      Alert.alert('Phone number required', 'Enter your phone number with country code, for example +15555550100.');
      return;
    }

    setIsPhoneLoading(true);
    try {
      const result = await startPhoneLogin(trimmedPhone);
      setPhoneStep('code');
      const devCode = result.dev_code ? `\n\nDev code: ${result.dev_code}` : '';
      Alert.alert('Code sent', `${result.detail || 'Enter the code we sent to your phone.'}${devCode}`);
    } catch (error: any) {
      Alert.alert('Phone sign in failed', error?.response?.data?.detail || 'Could not start phone sign in.');
    } finally {
      setIsPhoneLoading(false);
    }
  };

  const handlePhoneVerify = async () => {
    if (!phoneCode.trim()) {
      Alert.alert('Code required', 'Enter the verification code.');
      return;
    }

    setIsPhoneLoading(true);
    try {
      await verifyPhoneLogin(phone.trim(), phoneCode.trim());
      router.replace('/(tabs)/home');
    } catch (error: any) {
      Alert.alert('Phone sign in failed', error?.response?.data?.detail || 'Invalid or expired code.');
    } finally {
      setIsPhoneLoading(false);
    }
  };

  const handleMethodPress = async (method: AuthMethod) => {
    if (method === 'email') {
      setShowEmailForm(true);
      setShowPhoneForm(false);
      return;
    }
    if (method === 'phone') {
      setShowEmailForm(false);
      setShowPhoneForm(true);
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

          {showPhoneForm ? (
            <View style={styles.emailForm}>
              <Text style={styles.phoneFormTitle}>
                {phoneStep === 'phone' ? 'Sign in with phone' : 'Enter your code'}
              </Text>
              <View style={styles.inputWrap}>
                <Ionicons name="call-outline" size={20} color="#5E5E5E" />
                <TextInput
                  style={styles.input}
                  placeholder="+1 555 555 0100"
                  placeholderTextColor="#6D6D6D"
                  value={phone}
                  onChangeText={setPhone}
                  autoCapitalize="none"
                  autoCorrect={false}
                  keyboardType="phone-pad"
                  editable={phoneStep === 'phone'}
                />
              </View>

              {phoneStep === 'code' ? (
                <View style={styles.inputWrap}>
                  <Ionicons name="keypad-outline" size={20} color="#5E5E5E" />
                  <TextInput
                    style={styles.input}
                    placeholder="6-digit code"
                    placeholderTextColor="#6D6D6D"
                    value={phoneCode}
                    onChangeText={(value) => setPhoneCode(value.replace(/[^0-9]/g, '').slice(0, 6))}
                    keyboardType="number-pad"
                    maxLength={6}
                  />
                </View>
              ) : null}

              <TouchableOpacity
                style={[styles.signInButton, isPhoneLoading && styles.signInButtonDisabled]}
                onPress={phoneStep === 'phone' ? handlePhoneStart : handlePhoneVerify}
                disabled={isPhoneLoading}
              >
                {isPhoneLoading ? (
                  <ActivityIndicator color="#FFFFFF" />
                ) : (
                  <Text style={styles.signInButtonText}>{phoneStep === 'phone' ? 'Send Code' : 'Verify Code'}</Text>
                )}
              </TouchableOpacity>

              {phoneStep === 'code' ? (
                <TouchableOpacity
                  style={styles.backToMethods}
                  onPress={() => {
                    setPhoneStep('phone');
                    setPhoneCode('');
                  }}
                >
                  <Text style={styles.backToMethodsText}>Use a different number</Text>
                </TouchableOpacity>
              ) : null}

              <TouchableOpacity
                style={styles.backToMethods}
                onPress={() => {
                  setShowPhoneForm(false);
                  setPhoneStep('phone');
                  setPhoneCode('');
                }}
              >
                <Text style={styles.backToMethodsText}>Back to all sign-in options</Text>
              </TouchableOpacity>
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
  phoneFormTitle: {
    color: '#151515',
    fontSize: 18,
    fontWeight: '800',
    marginBottom: 4,
    textAlign: 'center',
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
