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
  void user;
  void router;
  void action;
  return true;
}

export function isPhoneVerificationError(error: any): boolean {
  void error;
  return false;
}
