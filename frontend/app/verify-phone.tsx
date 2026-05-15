import React, { useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
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

type Notice = {
  tone: 'info' | 'success' | 'error';
  text: string;
};

type LoadingAction = 'send' | 'verify' | null;

function normalizePhoneInput(value: string) {
  const trimmed = String(value || '').trim();
  const digits = trimmed.replace(/\D/g, '');
  if (!digits) return '';
  if (trimmed.startsWith('+')) return `+${digits}`;
  if (digits.length === 10) return `+1${digits}`;
  return `+${digits}`;
}

function formatCountdown(seconds: number) {
  if (seconds <= 0) return '';
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  const rest = seconds % 60;
  return `${minutes}:${String(rest).padStart(2, '0')}`;
}

function getVerificationError(error: any) {
  const data = error?.response?.data || {};
  return {
    detail: data.detail || 'Could not send a verification code. Try again.',
    retryAfter: Number(data.retry_after || 0),
    status: Number(error?.response?.status || 0),
  };
}

export default function VerifyPhoneScreen() {
  const router = useRouter();
  const { user, startPhoneVerification, verifyPhoneVerification } = useAuthStore();
  const [phone, setPhone] = useState(user?.phone || '');
  const [sentPhone, setSentPhone] = useState('');
  const [code, setCode] = useState('');
  const [step, setStep] = useState<'phone' | 'code'>('phone');
  const [loadingAction, setLoadingAction] = useState<LoadingAction>(null);
  const [resendIn, setResendIn] = useState(0);
  const [notice, setNotice] = useState<Notice | null>(null);

  const isBusy = loadingAction !== null;
  const isCodeReady = useMemo(() => code.replace(/\D/g, '').length === 6, [code]);

  useEffect(() => {
    if (step !== 'code' || resendIn <= 0) return undefined;
    const timer = setInterval(() => {
      setResendIn((current) => Math.max(0, current - 1));
    }, 1000);
    return () => clearInterval(timer);
  }, [resendIn, step]);

  const sendCode = async (resend = false) => {
    const normalizedPhone = normalizePhoneInput(phone);
    if (!normalizedPhone) {
      setNotice({ tone: 'error', text: 'Enter your phone number with country code, for example +15555550100.' });
      return;
    }
    if (resend && resendIn > 0) return;

    setLoadingAction('send');
    setNotice(null);
    try {
      const result = await startPhoneVerification(normalizedPhone);
      setPhone(normalizedPhone);
      setSentPhone(normalizedPhone);
      setCode('');
      setStep('code');
      setResendIn(45);

      const devCode = result.dev_code ? ` Dev code: ${result.dev_code}` : '';
      setNotice({
        tone: 'success',
        text: `${result.detail || 'We sent a verification code.'}${devCode}`,
      });
    } catch (error: any) {
      const { detail, retryAfter, status } = getVerificationError(error);
      if (status === 429 || retryAfter > 0) {
        setPhone(normalizedPhone);
        setSentPhone(normalizedPhone);
        setStep('code');
        setResendIn(retryAfter || 60);
        setNotice({
          tone: 'info',
          text: `${detail} You can still enter the code you already received.`,
        });
      } else {
        setNotice({ tone: 'error', text: detail });
      }
    } finally {
      setLoadingAction(null);
    }
  };

  const verifyCode = async () => {
    const trimmedCode = code.replace(/\D/g, '');
    const activePhone = sentPhone || normalizePhoneInput(phone);
    if (trimmedCode.length !== 6) {
      setNotice({ tone: 'error', text: 'Enter the 6-digit verification code.' });
      return;
    }
    if (!activePhone) {
      setStep('phone');
      setNotice({ tone: 'error', text: 'Enter your phone number again before verifying.' });
      return;
    }

    setLoadingAction('verify');
    setNotice(null);
    try {
      await verifyPhoneVerification(activePhone, trimmedCode);
      setNotice({ tone: 'success', text: 'Phone verified. You can post, message, share stories, and start calls now.' });
      setTimeout(() => router.back(), 650);
    } catch (error: any) {
      const { detail, retryAfter, status } = getVerificationError(error);
      if (status === 429 || retryAfter > 0) setResendIn(retryAfter || 60);
      setNotice({ tone: 'error', text: detail || 'Invalid or expired code. Request a new one and try again.' });
    } finally {
      setLoadingAction(null);
    }
  };

  const changeNumber = () => {
    setStep('phone');
    setSentPhone('');
    setCode('');
    setResendIn(0);
    setNotice(null);
  };

  return (
    <SafeAreaView style={styles.safe}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={styles.keyboard}>
        <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
          <View style={styles.topBar}>
            <TouchableOpacity style={styles.closeButton} onPress={() => router.back()} disabled={isBusy}>
              <Ionicons name="close" size={22} color="#161616" />
            </TouchableOpacity>
          </View>

          <View style={styles.hero}>
            <View style={styles.heroIcon}>
              <Ionicons name="shield-checkmark" size={27} color="#FFFFFF" />
            </View>
            <Text style={styles.title}>Verify your phone</Text>
            <Text style={styles.subtitle}>
              We use one SMS code to unlock posting, stories, messages, and video calls.
            </Text>
          </View>

          <View style={styles.card}>
            <View style={styles.stepRow}>
              <View style={[styles.stepDot, styles.stepDotActive]}>
                <Text style={styles.stepDotText}>1</Text>
              </View>
              <View style={styles.stepLine} />
              <View style={[styles.stepDot, step === 'code' && styles.stepDotActive]}>
                <Text style={[styles.stepDotText, step !== 'code' && styles.stepDotTextMuted]}>2</Text>
              </View>
            </View>

            <View style={styles.fieldGroup}>
              <Text style={styles.label}>Phone number</Text>
              <View style={[styles.inputWrap, step === 'code' && styles.inputWrapLocked]}>
                <Ionicons name="call-outline" size={20} color="#505050" />
                <TextInput
                  style={styles.input}
                  placeholder="+1 555 555 0100"
                  placeholderTextColor="#9B9B9B"
                  value={phone}
                  onChangeText={(value) => {
                    setPhone(value);
                    if (notice?.tone === 'error') setNotice(null);
                  }}
                  keyboardType="phone-pad"
                  textContentType="telephoneNumber"
                  editable={!isBusy && step === 'phone'}
                  selectionColor="#111111"
                />
              </View>
            </View>

            {step === 'code' ? (
              <View style={styles.fieldGroup}>
                <View style={styles.sentRow}>
                  <Text style={styles.label}>Verification code</Text>
                  <Text style={styles.sentText}>Sent to {sentPhone || phone}</Text>
                </View>
                <View style={[styles.inputWrap, styles.codeWrap]}>
                  <Ionicons name="keypad-outline" size={20} color="#505050" />
                  <TextInput
                    style={[styles.input, styles.codeInput]}
                    placeholder="000000"
                    placeholderTextColor="#B8B8B8"
                    value={code}
                    onChangeText={(value) => {
                      setCode(value.replace(/\D/g, '').slice(0, 6));
                      if (notice?.tone === 'error') setNotice(null);
                    }}
                    keyboardType="number-pad"
                    maxLength={6}
                    textContentType="oneTimeCode"
                    editable={!isBusy}
                    selectionColor="#111111"
                  />
                </View>
              </View>
            ) : null}

            {notice ? (
              <View style={[styles.notice, styles[`notice_${notice.tone}`]]}>
                <Ionicons
                  name={notice.tone === 'error' ? 'alert-circle' : notice.tone === 'success' ? 'checkmark-circle' : 'time'}
                  size={18}
                  color={notice.tone === 'error' ? '#8A1F11' : '#111111'}
                />
                <Text style={styles.noticeText}>{notice.text}</Text>
              </View>
            ) : null}

            <TouchableOpacity
              style={[
                styles.primaryButton,
                (isBusy || (step === 'code' && !isCodeReady)) && styles.disabledButton,
              ]}
              disabled={isBusy || (step === 'code' && !isCodeReady)}
              onPress={step === 'phone' ? () => sendCode(false) : verifyCode}
            >
              {loadingAction ? (
                <ActivityIndicator color="#FFFFFF" />
              ) : (
                <>
                  <Text style={styles.primaryButtonText}>
                    {step === 'phone' ? 'Send verification code' : 'Verify phone'}
                  </Text>
                  <Ionicons name="arrow-forward" size={17} color="#FFFFFF" />
                </>
              )}
            </TouchableOpacity>

            {step === 'code' ? (
              <View style={styles.actionRow}>
                <TouchableOpacity
                  style={[styles.actionButton, (isBusy || resendIn > 0) && styles.actionButtonDisabled]}
                  disabled={isBusy || resendIn > 0}
                  onPress={() => sendCode(true)}
                >
                  <Ionicons name="refresh" size={16} color="#111111" />
                  <Text style={styles.actionButtonText}>
                    {resendIn > 0 ? `Resend in ${formatCountdown(resendIn)}` : 'Resend code'}
                  </Text>
                </TouchableOpacity>
                <TouchableOpacity style={styles.actionButton} disabled={isBusy} onPress={changeNumber}>
                  <Ionicons name="create-outline" size={16} color="#111111" />
                  <Text style={styles.actionButtonText}>Change number</Text>
                </TouchableOpacity>
              </View>
            ) : null}
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#F5F5F1' },
  keyboard: { flex: 1 },
  content: { flexGrow: 1, paddingHorizontal: 22, paddingBottom: 28 },
  topBar: { paddingTop: 10, alignItems: 'flex-end' },
  closeButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    backgroundColor: '#FFFFFF',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: '#E6E1D8',
  },
  hero: { alignItems: 'center', paddingTop: 20, paddingBottom: 22, gap: 10 },
  heroIcon: {
    width: 64,
    height: 64,
    borderRadius: 32,
    backgroundColor: '#20361F',
    borderWidth: 1.5,
    borderColor: '#172917',
    alignItems: 'center',
    justifyContent: 'center',
  },
  title: { fontSize: 32, lineHeight: 36, fontWeight: '500', color: '#111111', textAlign: 'center' },
  subtitle: { maxWidth: 310, fontSize: 15, lineHeight: 22, color: '#565656', textAlign: 'center' },
  card: {
    backgroundColor: '#FFFFFF',
    borderRadius: 24,
    borderWidth: 1,
    borderColor: '#E6E1D8',
    padding: 18,
    gap: 16,
  },
  stepRow: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 24, paddingVertical: 4 },
  stepDot: {
    width: 30,
    height: 30,
    borderRadius: 15,
    backgroundColor: '#F1F1ED',
    borderWidth: 1,
    borderColor: '#E6E1D8',
    alignItems: 'center',
    justifyContent: 'center',
  },
  stepDotActive: { backgroundColor: '#111111', borderColor: '#111111' },
  stepDotText: { color: '#FFFFFF', fontSize: 13, fontWeight: '500' },
  stepDotTextMuted: { color: '#777777' },
  stepLine: { flex: 1, height: 2, backgroundColor: '#E6E1D8', marginHorizontal: 10 },
  fieldGroup: { gap: 8 },
  label: { fontSize: 13, fontWeight: '500', color: '#222222' },
  sentRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 10 },
  sentText: { flexShrink: 1, fontSize: 12, color: '#6E6E6E', textAlign: 'right' },
  inputWrap: {
    minHeight: 46,
    borderRadius: 18,
    borderWidth: 1.5,
    borderColor: '#D9D4CA',
    backgroundColor: '#FFFFFF',
    paddingHorizontal: 14,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  inputWrapLocked: { backgroundColor: '#F7F7F3' },
  codeWrap: { borderColor: '#111111' },
  input: { flex: 1, minHeight: 52, color: '#171717', fontSize: 17, fontWeight: '500' },
  codeInput: { fontSize: 24, fontWeight: '500' },
  notice: {
    borderRadius: 16,
    borderWidth: 1,
    paddingHorizontal: 12,
    paddingVertical: 11,
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 9,
  },
  notice_info: { backgroundColor: '#F5F5F1', borderColor: '#E4E0D7' },
  notice_success: { backgroundColor: '#E5F1E1', borderColor: '#C7D0BD' },
  notice_error: { backgroundColor: '#FFF0EA', borderColor: '#F3B8A4' },
  noticeText: { flex: 1, color: '#242424', fontSize: 13, lineHeight: 18, fontWeight: '500' },
  primaryButton: {
    minHeight: 46,
    borderRadius: 18,
    backgroundColor: '#20361F',
    borderWidth: 1,
    borderColor: '#172917',
    alignItems: 'center',
    justifyContent: 'center',
    flexDirection: 'row',
    gap: 8,
  },
  disabledButton: { opacity: 0.48 },
  primaryButtonText: { color: '#FFFFFF', fontSize: 15, fontWeight: '500' },
  actionRow: { flexDirection: 'row', gap: 10 },
  actionButton: {
    flex: 1,
    minHeight: 46,
    borderRadius: 15,
    backgroundColor: '#F5F5F1',
    borderWidth: 1,
    borderColor: '#E6E1D8',
    alignItems: 'center',
    justifyContent: 'center',
    flexDirection: 'row',
    gap: 6,
    paddingHorizontal: 10,
  },
  actionButtonDisabled: { opacity: 0.55 },
  actionButtonText: { color: '#111111', fontSize: 13, fontWeight: '500', textAlign: 'center' },
});
