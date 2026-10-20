import {STRIPE_ACCOUNTS_V2_VERSION, stripeV2RecipientTransfersEnabled} from '../src/stripe-connect-v2.ts';

// Read-only selection for the sandbox contract. Read the same v2 capability as
// the production seller gate; never manufacture readiness from a v1 alias.
export async function findSupportSandboxRecipient(readV1, readV2) {
  const counts = {examined:0, incomplete:0, payoutUnavailable:0, nonManual:0, requirementsDue:0, transfersInactive:0, ready:0};
  const seen = new Set();
  let cursor;
  for (let page = 0; page < 20; page++) {
    const result = await readV1('/accounts?limit=100' + (cursor ? '&starting_after=' + encodeURIComponent(cursor) : ''));
    if (!Array.isArray(result.data)) throw Error('Sandbox account list was malformed');
    for (const account of result.data) {
      if (!/^acct_[A-Za-z0-9]+$/.test(account.id || '') || seen.has(account.id)) throw Error('Sandbox account cursor did not progress');
      seen.add(account.id); counts.examined++;
      if (account.details_submitted !== true) { counts.incomplete++; continue; }
      if (account.payouts_enabled !== true) { counts.payoutUnavailable++; continue; }
      if (account.settings?.payouts?.schedule?.interval !== 'manual') { counts.nonManual++; continue; }
      if (!Array.isArray(account.requirements?.currently_due) || account.requirements.currently_due.length) { counts.requirementsDue++; continue; }
      const v2 = await readV2('/v2/core/accounts/' + account.id + '?include[0]=configuration.recipient', STRIPE_ACCOUNTS_V2_VERSION);
      if (v2.id !== account.id || v2.livemode !== false) throw Error('Sandbox recipient identity/mode mismatch');
      if (!stripeV2RecipientTransfersEnabled(v2)) { counts.transfersInactive++; continue; }
      counts.ready++;
      return {recipient:account, counts};
    }
    if (!result.has_more) return {recipient:null, counts};
    if (!result.data.length) throw Error('Sandbox account cursor did not progress');
    cursor = result.data.at(-1).id;
  }
  throw Error('Sandbox recipient scan exceeded bounded page budget');
}
