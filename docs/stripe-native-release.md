# Captro Native Payments: Release Gate

Status: implementation under validation. No real Stripe sandbox purchase-to-payout
acceptance has been recorded, and this update is not cleared for production or
TestFlight distribution. A successful compiler/unit-test run is not payment evidence.

## Architecture

- iOS sends post, price, quantity, selection and a persistent request ID to
  `POST /api/payments/create`. Prices, fees, taxes, creator proceeds and inventory
  are calculated and snapshotted on the server, in integer minor units.
- The server creates a real destination PaymentIntent with `payment:{purchaseId}`
  idempotency. PaymentSheet receives only the publishable key and client secret.
- Verified Stripe webhooks confirm the purchase and issue its entitlement and
  creator earning transactionally. PaymentSheet completion never grants access.
- One Express connected account serves every paid content type for a creator.
  Stripe-hosted onboarding collects identity and payout information. Captro
  stores only IDs, requirement statuses and safe debit-card metadata.
- Withdrawal quotes use Stripe's expanded, destination-specific instant balance.
  Creation uses `method=instant`, a validated debit-card destination, an immutable
  stored quote and `payout:{creatorId}:{requestId}` idempotency.
- Refunds remain separate from sales. A refund revokes access even if transfer
  recovery fails. Unresolved recovery/disputes block new Captro withdrawals.

Home navigation, stamps and post paging are unchanged by this integration.

## Recorded Sandbox Evidence

The protected `captro-payments-test` GitHub environment authenticates with real
Stripe sandbox keys. CI run `33933211810` started disposable Supabase Auth/Postgres
on a GitHub runner, applied the native payment schema, and verified the Stripe
account and connected-account list APIs. It copied only deployed database DDL,
not production users, purchases, credentials or other rows.

Run `33933452278` additionally started the real Captro Worker and Stripe CLI
webhook forwarding. Authenticated API access passed, unauthenticated payout
access returned 401, and an unsigned webhook returned 400. Actual creator
onboarding reached Stripe but account creation returned HTTP 400:

- Request ID: `req_JxzAJpQcvMzv0W`
- Cause: the sandbox has not signed up for Connect.
- Connect's marketplace setup was subsequently enabled in the sandbox dashboard.

Listing connected accounts successfully is not proof that creating them is
enabled. No purchase, ticket, creator earning or payout passed real acceptance
in this run. No new TestFlight build or production deployment was released.
Native validation run `33933452281` passed; compiler success is separate evidence.

Retry `33934777282` passed actual account creation and hosted onboarding-link
creation through Captro. Stripe returned an Express account with real outstanding
identity/business/external-account requirements and `payoutsReady=false`, matching
Captro's persisted flags. The disposable empty test account was cleaned up. This
clears the sandbox activation blocker, but not identity onboarding or payment and
payout acceptance. The live account still shows Connect's "Continue setup" page.

The ephemeral runtime is API integration coverage only. A persistently isolated
test backend and sandbox-targeted iOS build are still required for native
PaymentSheet, hosted onboarding, and device acceptance.

## Provision An Isolated Sandbox

Do not put test purchases in the production Supabase project or point test keys
at the production Worker. Use a dedicated Supabase branch/project, Worker, D1/KV
bindings and test users. No existing Captro test branch was available when checked.

Apply migrations through `20260904231905_stripe_native_payments.sql` to that
environment, then explicitly provision its singleton:

```sql
insert into public.app_payment_environment(id, stripe_mode) values(true, 'test');
```

There is deliberately no default or automatic mode switch. The Worker rejects
Stripe operations when its configured mode differs from the database. Never flip
an existing database between modes to reuse connected-account or purchase rows.

Load protected Worker secrets through the deployment environment, never Git or iOS:

- `STRIPE_MODE=test`
- `STRIPE_SECRET_KEY`: the sandbox secret/restricted key with the required API permissions
- `STRIPE_PUBLISHABLE_KEY`: the matching sandbox publishable key
- `STRIPE_WEBHOOK_SECRET`: account webhook signing secret
- `STRIPE_CONNECT_WEBHOOK_SECRET`: connected-account webhook signing secret
- `CAPTRO_TICKET_SIGNING_SECRET`: at least 32 random characters
- The isolated environment's existing Captro authentication/database secrets

Register enabled destinations at the test Worker's `/api/stripe/webhook` and
`/api/stripe/connect-webhook`. Account events must include PaymentIntent success,
failure and cancellation, refunds and disputes. Connected events must include
account/capability/external-account changes, `balance.available`, and payout
created/updated/paid/failed/canceled. Retain required legacy Checkout events.
The old live-only bootstrap helper is not a sandbox provisioner.

Use Stripe's Connect dashboard settings to allow debit cards and remove mandatory
bank collection where supported. Captro only accepts cards for withdrawal, but
Express-hosted screens are controlled by Stripe. Confirm those hosted screens
meet the product's debit-only expectations before release; the app cannot force
an ineligible card or account to become eligible.

## Fee Policy

Server sale configuration uses integer basis points and cents:

- `CAPTRO_SERVICE_FEE_BPS`
- `CAPTRO_SERVICE_FEE_FIXED_CENTS`
- `CAPTRO_SERVICE_FEE_MINIMUM_CENTS`
- `CAPTRO_PLATFORM_FEE_BUYER_PAYS` (default true)
- `CAPTRO_PLATFORM_FEE_CREATOR_PAYS` (default false; both cannot be true)

For the requested $20/$1.50 acceptance example, configure 500 basis points plus
50 cents in the sandbox. The $20 creator snapshot is independent of Stripe's
processing charge to the platform.

Current implemented payout policy is **platform absorbs the payout fee**:
explicitly set `CAPTRO_PAYOUT_FEE_POLICY=platform_absorbs` and leave Stripe
Instant Payout platform monetization disabled. The creator sees a zero payout
fee because the platform absorbs it, not because Stripe is free. A nonzero
Stripe platform-pricing difference fails closed. Passing Stripe payout fees to
creators requires additional pricing/reconciliation work; do not turn it on by
changing a displayed fee or subtracting a guessed percentage.

USD instant payouts are implemented; do not advertise other payout currencies.
Tax currently follows the existing configured server calculation; no new Stripe
Tax registration or automatic tax jurisdiction calculation is provisioned here.

## Apple Pay

PaymentSheet decides which supported methods to show. Apple Pay is gated by a
real merchant ID in both the backend and the signed app:

1. Register/enable an Apple merchant ID, associate it with the app and complete
   Stripe's Apple Pay payment-processing certificate setup.
2. Regenerate the app provisioning profile with that merchant entitlement.
3. Set Worker `CAPTRO_APPLE_PAY_MERCHANT_ID` and the same GitHub repository variable.
4. The TestFlight workflow runs `scripts/configure-apple-pay.py` and verifies the
   merchant is authorized by the profile and the signed archive.

Without that setup, card PaymentSheet remains supported and no fake Apple Pay
button is shown. Apple Pay provisioning has not been completed by this change.

## Required Real Acceptance

Use actual Stripe sandbox records, not inserted success rows or fabricated events.

1. Creator drafts a $20 event; publish prompts for earnings setup without losing the draft.
2. Complete Stripe's required test identity onboarding and add an eligible test debit card.
3. Publish the event, then open it as a different buyer in the sandbox iOS build.
4. Inspect the complete $20 item, configured service fee and total; open real PaymentSheet.
5. Pay using Stripe's documented test card flow. Test 3DS, cancellation and a decline separately.
6. Close the app immediately. Confirm the signed webhook creates one paid purchase,
   one $20 creator earning and the ticket. Reopen and view the ticket.
7. Replay the actual Stripe event and retry the original request ID. Verify no duplicate
   charge, entitlement or earning. Reject another user's purchase/payout read or write.
8. Read real earnings and destination-specific instant balance. Request a permitted
   debit payout from Captro and wait for the actual Stripe payout webhook.
9. Confirm payout history matches Stripe; use Stripe's failing-payout test card
   separately and verify balance reconciliation rather than a local subtraction.
10. Refund a purchase and verify the actual transfer reversal, refund ledger and
    revoked entitlement. Test duplicate delivery and delayed recovery.
11. Host scans the QR once successfully; the second scan must be rejected by the backend.
12. Confirm normal free posts/joins never demand earnings setup and Home remains unchanged.

After the successful native payment and withdrawal, run this **read-only** verifier
from `backend-cf` using protected environment variables:

```text
STRIPE_MODE=test
STRIPE_SECRET_KEY
CAPTRO_TEST_API_URL
CAPTRO_TEST_SUPABASE_URL
CAPTRO_TEST_SERVICE_ROLE_KEY
CAPTRO_TEST_BUYER_TOKEN
CAPTRO_TEST_CREATOR_TOKEN
CAPTRO_TEST_PURCHASE_ID
CAPTRO_TEST_PAYOUT_ID
```

```sh
node scripts/verify-stripe-native.mjs
```

It compares real PaymentIntent/events/account/card/balance/payout responses with
the ledger and private app endpoints. It does not simulate PaymentSheet or submit
payments, and it does not replace the iOS interaction and QR acceptance checks.
Keep only redacted IDs/results as evidence, never tokens, card data or client secrets.

Local checks:

```sh
npx tsc --noEmit
npm test
```

The PostgreSQL test fixtures are isolated SQL tests, not real Stripe integration proof.

## Production And TestFlight

Do not dispatch the production deploy or TestFlight workflow until sandbox
acceptance is recorded and the release target has matching API/database/Stripe
configuration. The current TestFlight app targets production, not the sandbox.

Provision production explicitly with `STRIPE_MODE=live`, live keys, live Connect,
enabled live webhook destinations, its own signing secrets and a `live` database
singleton. Confirm existing accounts and migrations before rollout. Production
mode must never be inferred from Swift's Release build configuration.

The previous live endpoint was disabled and Connect/API permissions were not
ready when checked. Recheck the actual account before rollout; merely possessing
a secret key is not evidence that Connect or webhook delivery works.

Digital-only content consumed in iOS may require StoreKit or an applicable Apple
program. The existing digital-goods guard remains; do not route in-app digital
group access through Stripe by disguising it as an event or physical service.

## References

- [PaymentSheet for iOS](https://docs.stripe.com/payments/accept-a-payment?platform=ios)
- [Connect Instant Payouts and fee handling](https://docs.stripe.com/connect/instant-payouts)
- [Connect payout account collection](https://docs.stripe.com/connect/payouts-bank-accounts)
- [Connect test data](https://docs.stripe.com/connect/testing)
- [Apple Pay integration](https://docs.stripe.com/apple-pay)
- [Apple review payment rules](https://developer.apple.com/app-store/review/guidelines/)
