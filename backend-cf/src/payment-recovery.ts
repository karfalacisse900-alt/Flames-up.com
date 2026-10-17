/** Operator-approved recovery only. No background refund or implicit fulfillment. */
export async function resolvePaymentRecovery(io: {
  claim: () => Promise<any>; purchase: any; liveMode: boolean;
  readIntent: (id: string) => Promise<any>;
  readCharge: (id: string) => Promise<any>;
  listRefunds: (paymentId: string) => Promise<any>;
  createRefund: (paymentId: string, amount: number, key: string) => Promise<any>;
  resolve: (record: any, outcome: 'fulfilled' | 'refunded', reference: string, charge: string, fee: number) => Promise<any>;
  now: () => number;
}) {
  const record = await io.claim();
  if (record.status !== 'needs_review') return {status: record.status};
  const p = io.purchase;
  if (p.settlement_model !== 'deferred' || p.stripe_mode !== (io.liveMode ? 'live' : 'test')) throw Error('CAPTRO_RECOVERY_MANUAL_ACCOUNTING_REQUIRED');
  const intent = await io.readIntent(record.provider_payment_id);
  if (intent.id !== record.provider_payment_id || intent.status !== 'succeeded' || intent.livemode !== io.liveMode
      || intent.amount_received !== record.amount || intent.currency?.toUpperCase() !== record.currency
      || record.amount !== p.total_amount || record.currency !== p.currency
      || intent.metadata?.source !== 'captro_commerce' || intent.metadata?.captro_purchase_id !== p.id
      || intent.transfer_data || intent.on_behalf_of) throw Error('STRIPE_PAYMENT_MISMATCH');
  const chargeID = typeof intent.latest_charge === 'string' ? intent.latest_charge : intent.latest_charge?.id;
  if (!chargeID?.startsWith('ch_')) throw Error('STRIPE_PAYMENT_SETTLEMENT_PENDING');
  const charge = await io.readCharge(chargeID);
  if (charge.id !== chargeID || charge.payment_intent !== intent.id || !charge.paid || charge.status !== 'succeeded'
      || charge.amount_captured !== record.amount || charge.currency?.toUpperCase() !== record.currency || charge.transfer || charge.disputed) {
    throw Error('CAPTRO_RECOVERY_MANUAL_ACCOUNTING_REQUIRED');
  }
  if (record.decision === 'fulfill') {
    if (charge.amount_refunded !== 0) throw Error('CAPTRO_RECOVERY_REFUND_IN_FLIGHT');
    const balance = charge.balance_transaction;
    if (balance && (typeof balance !== 'object' || balance.source !== charge.id || balance.amount !== record.amount
        || balance.currency !== charge.currency || !Number.isSafeInteger(balance.fee) || balance.fee < 0)) throw Error('STRIPE_PAYMENT_MISMATCH');
    return io.resolve(record,'fulfilled',intent.id,chargeID,balance?.fee ?? -1);
  }
  if (record.decision !== 'refund') throw Error('CAPTRO_RECOVERY_REVIEW_REQUIRED');
  // An ambiguous lost response is reconciled from the provider before replay.
  const listed = await io.listRefunds(intent.id);
  if (!Array.isArray(listed.data) || listed.has_more) throw Error('CAPTRO_RECOVERY_MANUAL_ACCOUNTING_REQUIRED');
  let refund = listed.data.find((r: any) => r.metadata?.captro_recovery_purchase_id === p.id);
  if (!refund) {
    if (charge.amount_refunded || listed.data.some((r: any) => !['failed','canceled'].includes(r.status))) throw Error('CAPTRO_RECOVERY_MANUAL_ACCOUNTING_REQUIRED');
    // Never reuse an expired provider idempotency key to blindly create another refund.
    const started=Date.parse(record.decision_started_at);
    if (!Number.isFinite(started) || started>io.now() || io.now()-started >= 23 * 3600000) throw Error('CAPTRO_RECOVERY_MANUAL_ACCOUNTING_REQUIRED');
    refund = await io.createRefund(intent.id,record.amount,`recovery-refund:${p.id}`);
  }
  if (!refund?.id?.startsWith('re_') || refund.payment_intent !== intent.id || refund.amount !== record.amount
      || refund.currency?.toUpperCase() !== record.currency || refund.metadata?.captro_recovery_purchase_id !== p.id) throw Error('STRIPE_PAYMENT_MISMATCH');
  if (refund.status !== 'succeeded') return {status: 'refund_pending'};
  return io.resolve(record,'refunded',refund.id,chargeID,0);
}
