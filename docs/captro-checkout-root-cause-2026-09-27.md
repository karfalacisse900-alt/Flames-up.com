# Captro checkout: reproduced failure, repair and release evidence

## Actual root cause

The deployed GET /api/commerce/posts/:postId returned HTTP 500 / COMMERCE_READ_FAILED after an ordinary buyer signed in through Captro POST /auth/login.

Cloudflare Worker diagnostic, captured with the existing authorized tail permission:

- stage: commerce_details
- exception: Too many subrequests by single Worker invocation.
- request: 0101c64b-2b78-472d-b525-7442a5f17130
- before-fix run: https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/36285847875

Normal Captro sign-in creates account-identity associations. The access lookup re-resolved those associations repeatedly while hydrating comments, media/attached objects and viewer reactions. This exhausted Cloudflare's invocation subrequest limit before the final access lookup. This is a backend failure, not a card decline or a verified Stripe error.

The earlier production readiness script signed in directly through Supabase and only called /auth/me. It did not create the same identity associations and therefore missed this defect. Both production readiness and sandbox acceptance now sign in through Captro's actual endpoint. This fixes the test gap, not just the error message.

The same over-hydrated reader was also used by POST /payments/create. Both entry points now use the access-only path. We have reproduced the current access failure; we cannot attribute every older screenshot/card failure to it without its original request log.

## Implemented

- Account-identity reads coalesce in a request-scoped promise map. No cross-account/global private cache.
- Access/purchase lookups preserve post visibility checks but skip comments, reactions and attached-media/feed hydration.
- Access diagnostics identify the failing stage and request ID. iOS Release logs record checkout HTTP status/request IDs and decoding field/type, without response bodies or payment secrets.
- Real event BRONX RUN CLUB ends at 2026-09-04T21:49:15Z (September 4, 5:49 PM America/New_York). Its stored status was still active. API now derives ended availability, iOS shows EVENT ENDED and an additive database trigger rejects new purchases after an explicit end. Original dates and historical orders were not edited.
- A past start without an end does not imply expiration. Memberships retain their separate validity rules. Existing owners can still view their issued passes.
- No checkout redesign, SDK additions, default-card autocharge, fabricated payment success, new pool accounts or live payout schedule changes.

## Production verification

Source: c911f33f, branch feature/recorded-voice-moderation. Native target Captro / com.captro.app. Stripe iOS 26.9.0.

Production API: https://flames-up-api.karfalacisse900.workers.dev/api

Deployment: https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/36286336580

Worker: c91c0b3f-23ff-4592-8b97-ff43fab0cab4. Migration 20260927012001_commerce_ended_event_guard.sql applied. Scoped deployment did not run Stripe secret/bootstrap/webhook configuration jobs.

Post-deploy ordinary-buyer check: https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/36286411973

| Request | Before | After |
| --- | --- | --- |
| NYC PHOTO CLUB access, real Captro login | HTTP 500 in 2245 ms and 4731 ms, separate runs | HTTP 200 in 1272 ms, active |
| BRONX RUN CLUB access | Active persisted status despite past end | HTTP 200 in 1216 ms, ended |

After request IDs: 78201d11-c2e9-4c92-9cd4-b0cf436b6adf and a84558e3-93f1-40e0-bb66-864b3dec42c4. Timings are individual GitHub-runner-to-production API reads, including network; not iPhone rendering measurements or a latency guarantee. No live PaymentIntent, order, charge, transfer or payout was created by this check.

Production uses live Stripe. Backend secret accepted and publishable key matches. Five inspected buyer Customer associations exist in the same live environment. The inspected saved card has allow_redisplay=always. CustomerSession probes all returned 200. No evidence justified blanket Customer replacement or a consent migration.

Supabase security checks before/after: unchanged 46 informational service-only RLS/no-policy notices and existing leaked-password-protection warning. No financial grants were widened.

## Real Stripe sandbox evidence — NOT physical-device evidence

Run: https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/36286111069

An isolated schema-only database, synthetic accounts and real Stripe test-mode API were used. Login went through Captro. Signed webhook fulfillment, decline handling, requires_action for 3DS, cancellation, stale Customer replacement, duplicate prevention, seller release, payout and admin-only pool reports passed. CI TypeScript check and 188 regressions passed.

- Buyer Customer: cus_VKmdyged0Xkdc1
- First $5 PI: pi_3UK74D2KVcRiAcs90ZAtIUq5
- First order: 78235030-a69e-4d02-800a-3bdde0042c38
- Saved-method second $5 PI: pi_3UK74K2KVcRiAcs90q3yvsu6
- Consented PM: pm_1UK74E2KVcRiAcs9X9rbzmrK; allow_redisplay=always
- Quantity-two $10 PI: pi_3UK74G2KVcRiAcs914GT1Ygg
- Quantity-two order: 97658c46-062c-4641-8f46-be77785637ad
- Later reviewed test transfer: tr_3UK74G2KVcRiAcs91lsLisNJ
- Later test payout: po_1UK74y2KVcxegi0i9Dhv1oEy

For the quantity-two order: gross 1000 USD cents, processing 59, Captro fee 0 in this configured sandbox case, seller net 941. Seller pending was recorded on verified payment, with no transfer. After simulated completion and reviewed release, 941 was transferred and subsequently recorded paid out in the event category. No actual money is stored in Supabase. These fees are this test's configuration, not a universal pricing promise.

Important limitation: existing quantity-two issuance is one group pass representing two admissions. It is NOT yet two independently redeemable ticket units. The new uploaded specification requires those units, so that requirement is not marked complete.

## Financial rollout gates

The existing category views/admin Captro Funds implementation remains deployed: category → seller/object → order → ledger/Stripe references. Stripe cash balances are displayed separately from seller accounting. This repair did not rebuild that ledger or move seller funds. Admin reporting now labels the ledger allocation Released / unpaid (not withdrawable Available), includes gross less refunds, treats missing commission as unknown and distinguishes historical Paid out to date from current cash. The seller-side withdrawable-availability gate below remains unfinished. Admin production deployment https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/36287338790 succeeded; the served captro-admin.pages.dev entry asset was fetched and verified to contain the updated reporting labels. This is deployment/content verification, not signed-in browser screenshot testing.

Read-only live payout audit: US platform acct_1UCpquRzhAjBHiPI uses manual payouts. Existing US sellers acct_1UDZBp2L3FpnpghF and acct_1UDWk0Rr6qhGLmFB use daily schedules with payouts_enabled=false. Schedules were not changed. Do not enable them under the assumption that Supabase pending status prevents automatic payouts.

Before a broad financial rollout, the uploaded file still requires: individually redeemable quantity units and partial-ticket refund allocation; balanced journal/reconciliation coverage for all exception paths; truthful currently-withdrawable availability rather than merely transferred amounts; documented product-specific release/holding policies; and review of automatic payout paths before enabling existing sellers. Existing manual release review is not a substitute for those acceptance gates. No new policy duration or fee was invented.

Stripe's manual-payout documentation distinguishes transfers from payouts, states country-dependent holding limits, and explicitly says it does not provide escrow: https://docs.stripe.com/connect/manual-payouts . Do not automatically treat a connected-account holding limit as approval for every platform/product arrangement.

## Physical iPhone acceptance

No physical iPhone is controllable here. Device PASS is not claimed. PaymentSheet presentation, actual saved-card redisplay/selection, completed native 3DS and device receipt/QR display remain unverified.

Instrumented Release build job: https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/36286112367 . Build 497.1, version 1.0.1. Release archive/export/upload succeeded. Apple read-back at 2026-09-27T02:02:01Z confirms processing VALID, internalBuildState IN_BETA_TESTING, assigned to Captro private and Captro private2, with automatic notification enabled. Read-back: https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/36286816080/attempts/4 . External beta remains READY_FOR_BETA_SUBMISSION; external approval is not claimed.

Tester steps:

1. Verify installed Captro 1.0.1 (497.1). Reopen the reported September 4 event: expect EVENT ENDED, no new charge.
2. Open an eligible, future real-world item: access details must load and GET TICKET must open the Stripe payment sheet, not charge automatically. Canceling must not grant paid access.
3. For a purchase the tester actually intends to make in this live build, explicitly select a card and Pay. Record approximate time, screen error if any and installed build. Check server-confirmed ticket/receipt before calling it successful.
4. A second intended purchase must reuse the same Customer and show an eligible card only if saving was consented to. Card failures must allow another method without creating a second uncertain charge.
5. Synthetic decline/3DS card numbers must only be used in a separately configured sandbox device environment. NEVER enter Stripe test cards in live TestFlight 497.1. Apple Pay remains disabled until merchant setup is complete.
6. If it fails, export device Console records for subsystem com.captro.app, categories CheckoutAPI and Captro payment diagnostics. Correlate X-Request-ID with the Worker tail. Do not send card numbers, CVC, tokens or client secrets.

## Changed implementation files

- backend-cf/src/index.ts — access-only hydration, request-scoped identity coalescing, availability validation, request/stage diagnostics.
- backend-cf/src/commerce.ts and purchase-errors.ts — derived ended/expired status and specific rejection.
- supabase/migrations/20260927012001_commerce_ended_event_guard.sql — transactional date guard for newly inserted orders.
- backend-cf/tests/commerce_access_availability.test.mjs and deferred_marketplace_database.test.mjs — scope/coalescing, time-zone/expiry and transaction rollback regressions.
- backend-cf/scripts/production-checkout-readiness.mjs and checkout-readiness-with-tail.mjs — true Captro login reproduction with safe correlated Worker logs.
- backend-cf/scripts/stripe-sandbox-runtime.mjs and stripe-sandbox-schema.mjs — real login and pending migration in isolated payment acceptance.
- backend-cf/scripts/audit-buyer-payment-methods.mjs — read-only platform/connected payout schedule audit.
- admin-web/src/FinancePage.tsx — accurate allocation/cash labels and unknown-fee display.
- .github/workflows/deploy-worker.yml — scoped migration allowlist and readiness tracing, not payment configuration changes.
- ios_native/MIRA/Sources/MIRANative/Models/CaptroCommerce.swift and CaptroStampAdapter.swift — honest ended-event availability.
- ios_native/MIRA/Sources/MIRANative/Screens/CaptroCommerceDetailViews.swift — prevents new ended purchases while preserving existing pass viewing.
- ios_native/MIRA/Sources/MIRANative/Services/MIRAAPIClient.swift — Release checkout HTTP/coding-path diagnostics.
