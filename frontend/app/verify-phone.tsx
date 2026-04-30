import React, { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuthStore } from '../src/store/authStore';

export default function VerifyPhoneScreen() {
  const router = useRouter();
  const { user, startPhoneVerification, verifyPhoneVerification } = useAuthStore();
  const [phone, setPhone] = useState(user?.phone || '');
  const [code, setCode] = useState('');
  const [step, setStep] = useState<'phone' | 'code'>('phone');
  const [isLoading, setIsLoading] = useState(false);

  const sendCode = async () => {
    const normalizedPhone = phone.trim();
    if (!normalizedPhone) {
      Alert.alert('Phone required', 'Enter your phone number with country code, for example +15555550100.');
      return;
    }

    setIsLoading(true);
    try {
      const result = await startPhoneVerification(normalizedPhone);
      setStep('code');
      const devCode = result.dev_code ? `\n\nDev code: ${result.dev_code}` : '';
      Alert.alert('Code sent', `${result.detail || 'Enter the code we texted you.'}${devCode}`);
    } catch (error: any) {
      const detail = error?.response?.data?.detail || 'Could not send a verification code.';
      const twilioCode = error?.response?.data?.code ? `\n\n${error.response.data.code}` : '';
      Alert.alert('Phone verification failed', `${detail}${twilioCode}`);
    } finally {
      setIsLoading(false);
    }
  };

  const verifyCode = async () => {
    const trimmedCode = code.replace(/\D/g, '');
    if (trimmedCode.length !== 6) {
      Alert.alert('Code required', 'Enter the 6-digit verification code.');
      return;
    }

    setIsLoading(true);
    try {
      await verifyPhoneVerification(phone.trim(), trimmedCode);
      Alert.alert('Verified', 'Your phone number is verified.', [
        { text: 'Done', onPress: () => router.back() },
      ]);
    } catch (error: any) {
      const detail = error?.response?.data?.detail || 'Invalid or expired code.';
      const twilioCode = error?.response?.data?.code ? `\n\n${error.response.data.code}` : '';
      Alert.alert('Verification failed', `${detail}${twilioCode}`);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <SafeAreaView style={styles.safe}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={styles.keyboard}>
        <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
          <View style={styles.header}>
            <TouchableOpacity style={styles.backButton} onPress={() => router.back()}>
              <Ionicons name="close" size={24} color="#1A1A1A" />
            </TouchableOpacity>
            <Text style={styles.title}>Verify phone</Text>
            <Text style={styles.subtitle}>
              Phone verification is required before posting, stories, messages, and video calls.
            </Text>
          </View>

          <View style={styles.card}>
            <View style={styles.inputWrap}>
              <Ionicons name="call-outline" size={20} color="#5E5E5E" />
              <TextInput
                style={styles.input}
                placeholder="+1 555 555 0100"
                placeholderTextColor="#8E8E8E"
                value={phone}
                onChangeText={setPhone}
                keyboardType="phone-pad"
                editable={step === 'phone'}
              />
            </View>

            {step === 'code' ? (
              <View style={styles.inputWrap}>
                <Ionicons name="keypad-outline" size={20} color="#5E5E5E" />
                <TextInput
                  style={styles.input}
                  placeholder="6-digit code"
                  placeholderTextColor="#8E8E8E"
                  value={code}
                  onChangeText={(value) => setCode(value.replace(/\D/g, '').slice(0, 6))}
                  keyboardType="number-pad"
                  maxLength={6}
                />
              </View>
            ) : null}

            <TouchableOpacity
              style={[styles.primaryButton, isLoading && styles.disabledButton]}
              disabled={isLoading}
              onPress={step === 'phone' ? sendCode : verifyCode}
            >
              {isLoading ? (
                <ActivityIndicator color="#FFFFFF" />
              ) : (
                <Text style={styles.primaryButtonText}>{step === 'phone' ? 'Send code' : 'Verify code'}</Text>
              )}
            </TouchableOpacity>

            {step === 'code' ? (
              <TouchableOpacity
                style={styles.secondaryButton}
                onPress={() => {
                  setStep('phone');
                  setCode('');
                }}
              >
                <Text style={styles.secondaryButtonText}>Use a different number</Text>
              </TouchableOpacity>
            ) : null}
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#FAFAF8' },
  keyboard: { flex: 1 },
  content: { flexGrow: 1, paddingHorizontal: 22, paddingBottom: 28 },
  header: { paddingTop: 18, gap: 10 },
  backButton: { width: 44, height: 44, borderRadius: 22, justifyContent: 'center', alignItems: 'center' },
  title: { fontSize: 34, fontWeight: '900', color: '#151515' },
  subtitle: { fontSize: 15, lineHeight: 22, color: '#5F5F5F' },
  card: {
    marginTop: 26,
    backgroundColor: '#FFFFFF',
    borderRadius: 18,
    borderWidth: 1,
    borderColor: '#ECE8DF',
    padding: 16,
    gap: 12,
  },
  inputWrap: {
    height: 56,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#DDD8CC',
    backgroundColor: '#FFFFFF',
    paddingHorizontal: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  input: { flex: 1, color: '#171717', fontSize: 16 },
  primaryButton: {
    height: 54,
    borderRadius: 16,
    backgroundColor: '#1A1A1A',
    justifyContent: 'center',
    alignItems: 'center',
  },
  disabledButton: { opacity: 0.65 },
  primaryButtonText: { color: '#FFFFFF', fontSize: 16, fontWeight: '800' },
  secondaryButton: { alignItems: 'center', paddingVertical: 4 },
  secondaryButtonText: { color: '#2E2E2E', fontSize: 13, fontWeight: '700' },
});
