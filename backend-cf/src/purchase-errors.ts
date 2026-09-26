/** Public, actionable recovery text; never expose provider secrets or SQL errors. */
export function purchaseFailureMessage(code: string): string {
  switch (code) {
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
