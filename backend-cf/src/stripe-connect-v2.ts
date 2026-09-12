export const STRIPE_ACCOUNTS_V2_VERSION = '2026-08-26.dahlia';

type RecipientAccountInput = {
  contactEmail: string;
  displayName: string;
  country: string;
  authUserId: string;
  appUserId: string;
  migratedFromAccountId?: string;
};

export function stripeRecipientAccountPayload(input: RecipientAccountInput) {
  return {
    contact_email: input.contactEmail,
    display_name: input.displayName,
    // Captro owns the seller experience. A no-dashboard recipient account gives
    // the native app an Account Session without sending the seller to Express.
    dashboard: 'none',
    identity: { country: input.country.toLowerCase() },
    configuration: {
      recipient: {
        capabilities: {
          stripe_balance: {
            stripe_transfers: { requested: true },
          },
        },
      },
    },
    defaults: {
      currency: 'usd',
      responsibilities: {
        fees_collector: 'application',
        losses_collector: 'application',
      },
      locales: ['en-US'],
      profile: {
        product_description: 'Sales and paid access through Captro',
      },
    },
    metadata: {
      captro_auth_user_id: input.authUserId,
      captro_app_user_id: input.appUserId,
      ...(input.migratedFromAccountId ? {
        migrated_from_account_id: input.migratedFromAccountId,
        // A webhook can arrive before the replacement mapping is swapped.
        // The worker ignores this exact marker until that mapping exists.
        captro_payout_migration_pending: input.migratedFromAccountId,
      } : {}),
    },
    include: ['configuration.recipient', 'identity', 'requirements', 'defaults'],
  };
}

export function stripeV2RecipientTransferStatus(account: any): string {
  return String(account?.configuration?.recipient?.capabilities?.stripe_balance?.stripe_transfers?.status || '')
    .trim()
    .toLowerCase();
}

export function stripeV2RecipientTransfersEnabled(account: any): boolean {
  return stripeV2RecipientTransferStatus(account) === 'active';
}
