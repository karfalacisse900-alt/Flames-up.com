# Captro buyer and seller payment rollout

The active native app is `ios_native/MIRA` (Stripe iOS 26.9.0). Its buyer
PaymentSheet uses a Stripe Customer/PaymentIntent and grants access only after
the server confirms payment. The marketplace uses separate charges and
transfers to a reusable, no-dashboard Connect recipient account. A buyer can
also be a seller under the same Captro login; saving a buyer card does not
start Connect or Identity.

## Seller policy

- Connect onboarding collects Stripe-required identity and payout details.
  Transfers, payouts, outstanding requirements, an eligible debit card, and
  (in test mode) a manual payout schedule are separate readiness gates.
- Set `CAPTRO_SELLER_IDENTITY_MODE=stripe_identity` **only in an isolated test
  environment** to require a separate Stripe Identity document check in
  addition to Connect. With the default `connect`, Connect handles required KYC
  and no duplicate Identity check is charged.
- The Identity result is not automatically associated with a Connect Person.
  Accounts v2 recipient onboarding remains authoritative; a separate verified
  Identity session cannot override Connect restrictions. Stripe's supported
  `related_person` association must be validated for the actual account and
  access level before it is used. Additional Connect verifications may need
  invitation-only access.
- Stripe Identity SDK 26.9.0's fully native initializer is documented in its
  pinned source as invite-only. The official SDK's web-based iOS sheet is the
  fallback. Set `CAPTRO_IDENTITY_NATIVE_ENABLED=true` only after Stripe grants
  access. An Identity submission stays `processing` until the backend retrieves
  Stripe's authoritative `verified` result.
- New Captro-managed recipient accounts are configured for manual payouts
  before onboarding. Existing live sellers' schedules are **not changed**.
  Test mode and the opt-in Stripe Identity policy refuse new sales and
  withdrawals if the schedule is not manual.
  Before enabling the same policy live, review existing seller schedules and
  applicable Stripe payout-holding limits; automatically scheduled payouts on
  pre-existing accounts cannot be stopped by guarding the Withdraw button.

## Isolated test setup

1. Use a dedicated Supabase project or branch, Worker, test users, and
   `STRIPE_MODE=test`; do not change the live project's mode. Apply migration
   `20260925120000_seller_identity_verification.sql` there.
2. In Stripe test mode, enable Identity. Supply test Stripe secret/publishable
   keys and both signed webhook secrets to the Worker. The platform webhook
   must subscribe to `identity.verification_session.verified`,
   `.requires_input`, `.processing`, and `.canceled` in addition to existing
   payment events. Connect webhook events remain required.
3. Set `CAPTRO_SELLER_IDENTITY_MODE=stripe_identity` in the test Worker and
   leave `CAPTRO_IDENTITY_NATIVE_ENABLED=false` unless Stripe explicitly
   enables it. Configure selfie matching only if the product policy requires
   it. Never place these secrets or ID images in the app database or logs.
4. Point an iOS test build at the test Worker. Verify buyer checkout without
   seller setup; free creation; paid draft; seller Identity submission and
   webhook; Connect onboarding; eligible debit card; test sale; test balance;
   idempotent test payout. Test a second account cannot read seller records.
5. Review Stripe Identity consent, Captro privacy text, Dashboard activation,
   account-specific Connect requirements, and Apple purchase classification
   before considering a live rollout. Digital in-app access remains blocked
   from Stripe checkout and needs a compliant StoreKit path.

The current production Worker is configured `STRIPE_MODE=live`. This change
must not be deployed there as a test. No live Identity checks or payout-policy
change are authorized by this implementation.
