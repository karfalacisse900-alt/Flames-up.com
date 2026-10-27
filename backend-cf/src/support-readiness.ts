// Owner-only explanation of the existing gates. This never enables payments,
// creates an account, changes a payout schedule or replaces checkout validation.
export function supportReadiness(input: {
  mode: string; enabled: boolean; account: any; providerVerified: boolean;
  enrolled: boolean | null; manualRequired: boolean; identityRequired: boolean;
  identityVerified: boolean;
}) {
  const blockers: { source: string; code: string; message: string }[] = [];
  const add = (source: string, code: string, message: string) => blockers.push({source,code,message});
  if (!input.enabled) add('captro','rollout_disabled', input.mode === 'live'
    ? 'Live Support is disabled by Captro’s server-side rollout switch; this is not a Stripe account rejection.'
    : 'Support checkout is disabled by Captro in this environment.');
  if (input.enrolled === false) add('captro','creator_enrollment_required',
    'An administrator must approve this creator for Support in the current Stripe environment.');
  const a = input.account;
  if (!a) add('captro','payout_setup_required','No existing payout account was found in this Stripe mode. Use the payout setup below.');
  else if (!input.providerVerified) add('verification','provider_unavailable','The current Stripe account requirements could not be verified. Retry; your existing payout account is retained.');
  else {
    if (!a.details_submitted) add('stripe','details_incomplete','Stripe account details have not been completed.');
    if (!a.transfers_enabled) add('stripe','transfers_inactive','The Stripe recipient transfers capability is not active.');
    if (!a.payouts_enabled) add('stripe','payouts_disabled','Stripe has not enabled payouts on this account.');
    if (a.disabled_reason) add('stripe','account_restricted',`Stripe restriction: ${String(a.disabled_reason).replace(/[^a-zA-Z0-9_. -]/g,'').slice(0,120)}.`);
    if (!Array.isArray(a.requirements_currently_due)) add('verification','requirements_unknown','Stripe account requirements were not returned; readiness is unverified.');
    else for (const field of a.requirements_currently_due.slice(0,30)) {
      // Requirement field names only, never their personal values or provider IDs.
      if (typeof field === 'string' && /^[a-zA-Z0-9_.\[\]-]{1,120}$/.test(field))
        add('stripe',`requirement:${field}`,`Stripe requires: ${field.replace(/_/g,' ')}.`);
      else add('stripe','requirement_pending','Stripe has an outstanding account requirement. Open existing payout setup to review it.');
    }
    if (input.manualRequired && a.payout_schedule !== 'manual') add('captro','manual_schedule_required','Captro requires a manual payout schedule for this flow. The existing account schedule needs operator review; do not create another account.');
    if (!a.eligible_debit_card_exists) add('captro','eligible_payout_card_required','Captro’s current withdrawal flow requires an eligible payout debit card. Reuse this account’s payout setup.');
    if (a.status !== 'ready' && !blockers.some(b=>b.source==='stripe')) add('captro','account_state_not_ready','Captro has not confirmed this payout account as ready. Refresh the existing payout setup.');
  }
  if (input.identityRequired && !input.identityVerified) add('captro','seller_identity_required','Captro’s separate seller identity check is not verified for this payout account. Continue the existing verification flow.');
  return {status:blockers.length?'blocked':'ready',mode:input.mode,providerVerified:input.providerVerified,
    retryable:blockers.some(b=>b.source==='verification'),blockers};
}
