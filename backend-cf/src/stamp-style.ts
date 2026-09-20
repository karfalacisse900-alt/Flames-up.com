// Style is presentation metadata, never a product type, price or entitlement.
const variants: Record<string, readonly string[]> = {
  moment: ['moment-paper', 'moment-postal', 'moment-voice'],
  club: ['club-oval', 'club-member', 'club-tag'],
  event: ['event-ticket', 'event-screening', 'event-postal'],
  meetup: ['meetup-note', 'meetup-fold', 'meetup-route'],
  deal: ['deal-coupon', 'deal-cashback', 'deal-drop'],
};
export function stampFamily(postType: unknown): string {
  switch (postType) {
    case 'club': case 'group': return 'club';
    case 'event': case 'party': case 'ticket': return 'event';
    case 'meetup': case 'booking': return 'meetup';
    case 'deal': case 'offer': case 'local_offer': return 'deal';
    default: return 'moment';
  }
}
export function validatedStampVariant(value: unknown, postType: unknown): string | null {
  const allowed = variants[stampFamily(postType)];
  return typeof value === 'string' && allowed.includes(value) ? value : null;
}
