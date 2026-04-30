import { Alert } from 'react-native';

type PhoneVerifiedUser = {
  phone_verified?: boolean;
} | null | undefined;

type PushRouter = {
  push: (href: any) => void;
};

export const PHONE_VERIFICATION_REQUIRED = 'PHONE_VERIFICATION_REQUIRED';

export function requireVerifiedPhone(
  user: PhoneVerifiedUser,
  router: PushRouter,
  action = 'continue'
): boolean {
  if (user?.phone_verified) return true;

  Alert.alert(
    'Verify your phone',
    `Verify your phone number to ${action}. We will text you a 6-digit code.`,
    [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Verify', onPress: () => router.push('/verify-phone' as any) },
    ]
  );
  return false;
}

export function isPhoneVerificationError(error: any): boolean {
  return error?.response?.data?.code === PHONE_VERIFICATION_REQUIRED;
}
