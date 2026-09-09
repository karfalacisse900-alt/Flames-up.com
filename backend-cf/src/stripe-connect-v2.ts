export const STRIPE_ACCOUNTS_V2_VERSION = '2026-08-26.dahlia';

type RecipientAccountInput = {
  contactEmail: string;
  displayName: string;
  country: string;
  authUserId: string;
  appUserId: string;
};

export function stripeRecipientAccountPayload(input: RecipientAccountInput) {
  return {
    contact_email: input.contactEmail,
    display_name: input.displayName,
    dashboard: 'express',
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
    },
    include: ['configuration.recipient', 'identity', 'requirements', 'defaults'],
  };
}

export function stripeRecipientOnboardingPayload(
  accountId: string,
  refreshUrl: string,
  returnUrl: string,
) {
  return {
    account: accountId,
    use_case: {
      type: 'account_onboarding',
      account_onboarding: {
        collection_options: { fields: 'currently_due' },
        configurations: ['recipient'],
        refresh_url: refreshUrl,
        return_url: returnUrl,
      },
    },
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
