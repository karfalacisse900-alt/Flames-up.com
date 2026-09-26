/** Extract the database's exception, never its RPC function name. */
export function paymentErrorCode(error: any): string {
  const raw = String(error?.code || error?.message || '');
  const value = raw.replace(/^SUPABASE_RPC_FAILED:[^:]+:\d+:/, '');
  const appCode = value.match(/\b(?:CAPTRO|COMMERCE|STRIPE|PAYOUT)_[A-Z0-9_]+\b/);
  if (appCode) return appCode[0];
  const providerCodes: Record<string, string> = {
    card_declined: 'STRIPE_CARD_DECLINED', authentication_required: 'STRIPE_AUTHENTICATION_REQUIRED',
    resource_missing: 'STRIPE_RESOURCE_MISSING', api_connection_error: 'STRIPE_CONNECTION_ERROR',
  };
  return providerCodes[value] || 'COMMERCE_REQUEST_FAILED';
}

/** Public, actionable recovery text; never expose provider secrets or SQL errors. */
export function purchaseFailureMessage(code: string): string {
  switch (code) {
    case 'STRIPE_CARD_DECLINED': return 'Your card was declined. Try another payment method.';
    case 'STRIPE_AUTHENTICATION_REQUIRED': return 'Complete your bank authentication in the payment sheet.';
    case 'STRIPE_CONNECTION_ERROR': return 'Could not connect. Please try again.';
    case 'CAPTRO_CREATOR_CANNOT_PURCHASE': return 'You own this item. Open its management options instead of buying or joining it.';
    case 'CAPTRO_ITEM_EXPIRED': return 'This item has expired and is no longer accepting purchases or joins.';
    case 'CAPTRO_ITEM_UNAVAILABLE': return 'This item is no longer available.';
    case 'CAPTRO_CAPACITY_REACHED':
    case 'CAPTRO_TIER_SOLD_OUT': return 'There are no places left for this option. Refresh the details to choose another option.';
    case 'CAPTRO_PRICE_UNAVAILABLE': return 'This price has changed or is unavailable. Reopen the item for current options.';
    case 'CAPTRO_BOOKING_SLOT_UNAVAILABLE': return 'This time is no longer available. Choose another time.';
    case 'CAPTRO_PAYOUTS_NOT_READY':
    case 'CAPTRO_SELLER_IDENTITY_REQUIRED':
    case 'CAPTRO_PAYOUT_SCHEDULE_REVIEW_REQUIRED': return 'The seller must finish seller setup before accepting payments. Your card was not charged.';
    default: return 'Could not begin this purchase or join. Please try again. If this continues, contact Captro support.';
  }
}
