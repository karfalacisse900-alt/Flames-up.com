import { Alert } from 'react-native';

type PhoneVerifiedUser = {
  phone_verified?: boolean;
  username?: string | null;
} | null | undefined;

type PushRouter = {
  push: (href: any) => void;
};

export const PHONE_VERIFICATION_REQUIRED = 'PHONE_VERIFICATION_REQUIRED';
const OWNER_USERNAMES = ['dxhfqhsd5c'];

function isOwnerAccount(user: PhoneVerifiedUser): boolean {
  const clean = String(user?.username || '').replace(/^@/, '').trim().toLowerCase();
  return !!clean && OWNER_USERNAMES.includes(clean);
}

export function requireVerifiedPhone(
  user: PhoneVerifiedUser,
  router: PushRouter,
  action = 'continue'
): boolean {
  if (user?.phone_verified || isOwnerAccount(user)) return true;

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
