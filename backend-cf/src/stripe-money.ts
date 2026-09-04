// Money stays in integer minor units; percentages are stored in basis points.
export function cents(value: unknown, minimum = 0): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < minimum || value > 99_999_999) {
    throw new Error('CAPTRO_AMOUNT_INVALID');
  }
  return value;
}

export function stripeMode(env: Record<string, any>): 'test' | 'live' {
  if (env.STRIPE_MODE !== 'test' && env.STRIPE_MODE !== 'live') throw new Error('STRIPE_MODE_REQUIRED');
  const mode = env.STRIPE_MODE;
  if (!new RegExp(`^(sk|rk)_${mode}_`).test(String(env.STRIPE_SECRET_KEY || ''))
      || !String(env.STRIPE_PUBLISHABLE_KEY || '').startsWith(`pk_${mode}_`)) {
    throw new Error('STRIPE_MODE_KEY_MISMATCH');
  }
  return mode;
}

export function percentageFee(amount: number, basisPoints: number, fixed: number): number {
  cents(amount); cents(basisPoints); cents(fixed);
  return cents(Number((BigInt(amount) * BigInt(basisPoints) + 9999n) / 10000n) + fixed);
}

export function saleAmounts(item: number, fee: { basisPoints: number; fixedAmount: number; minimumAmount: number;
  buyerPaysPlatformFee: boolean; creatorPaysPlatformFee: boolean }, tax = 0) {
  cents(item); cents(tax);
  if (fee.buyerPaysPlatformFee && fee.creatorPaysPlatformFee) throw new Error('CAPTRO_FEE_CONFIGURATION_INVALID');
  const platformFee = item > 0 ? Math.max(fee.minimumAmount, percentageFee(item, fee.basisPoints, fee.fixedAmount)) : 0;
  const serviceFeeAmount = fee.buyerPaysPlatformFee ? platformFee : 0;
  const creatorDeduction = fee.creatorPaysPlatformFee ? platformFee : 0;
  return { itemAmount: item, serviceFeeAmount, creatorAmount: cents(item - creatorDeduction),
    platformFeeAmount: serviceFeeAmount + creatorDeduction, taxAmount: item ? tax : 0,
    buyerTotal: cents(item + serviceFeeAmount + (item ? tax : 0)) };
}

export function eligibleDebitCard(card: any, currency: string, today = new Date()): boolean {
  return card?.object === 'card' && card?.funding === 'debit' && /^card_/.test(card?.id || '')
    && card.currency?.toLowerCase() === currency.toLowerCase()
    && Array.isArray(card.available_payout_methods) && card.available_payout_methods.includes('instant')
    && Number.isInteger(card.exp_month) && card.exp_month >= 1 && card.exp_month <= 12
    && (card.exp_year > today.getUTCFullYear()
      || (card.exp_year === today.getUTCFullYear() && card.exp_month >= today.getUTCMonth() + 1));
}

export function payoutCardMetadata(card: any) {
  return { id: card.id, brand: String(card.brand || 'Debit'), last4: String(card.last4 || ''),
    expirationMonth: card.exp_month, expirationYear: card.exp_year, instantPayoutEligible: true };
}

export function instantBalance(balance: any, cardId: string, currency: string): number {
  const entry = balance?.instant_available?.find((item: any) => item.currency === currency.toLowerCase());
  // An absent expansion or destination is not evidence that funds can be paid out.
  const destination = entry?.net_available?.find((item: any) => item.destination === cardId);
  if (!destination || !Number.isSafeInteger(destination.amount) || !Number.isSafeInteger(entry.amount)) return 0;
  return Math.max(0, Math.min(destination.amount, entry.amount));
}

export function payoutQuote(amount: number, balance: any, cardId: string, currency: string, env: Record<string, any>) {
  cents(amount, 1);
  if (currency !== 'USD') throw new Error('CAPTRO_PAYOUT_CURRENCY_UNSUPPORTED');
  // Stripe bills its Connect fees to the platform. Do not invent a seller charge.
  // A monetized payout policy requires Stripe platform-pricing reconciliation first.
  if (env.CAPTRO_PAYOUT_FEE_POLICY !== 'platform_absorbs') throw new Error('CAPTRO_PAYOUT_FEE_POLICY_REQUIRED');
  const entry = balance?.instant_available?.find((item: any) => item.currency === 'usd');
  const available = instantBalance(balance, cardId, currency);
  if (available !== entry?.amount) throw new Error('CAPTRO_PAYOUT_PRICING_MISMATCH');
  if (amount < 50 || amount > 999900 || amount > available) throw new Error('CAPTRO_PAYOUT_AMOUNT_UNAVAILABLE');
  return { amount, fee: 0, netAmount: amount, currency, available, feePolicy: 'platform_absorbs' };
}
