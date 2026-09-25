export type SellerGate = {
  connectReady: boolean;
  manualScheduleRequired: boolean;
  payoutSchedule: string | null;
  identityRequired: boolean;
  identityStatus: string | null;
};

export function sellerGateFailure(input: SellerGate): string | null {
  if (!input.connectReady) return 'CAPTRO_PAYOUTS_NOT_READY';
  if (input.manualScheduleRequired && input.payoutSchedule !== 'manual') {
    return 'CAPTRO_PAYOUT_SCHEDULE_REVIEW_REQUIRED';
  }
  if (input.identityRequired && input.identityStatus !== 'verified') {
    return 'CAPTRO_SELLER_IDENTITY_REQUIRED';
  }
  return null;
}
