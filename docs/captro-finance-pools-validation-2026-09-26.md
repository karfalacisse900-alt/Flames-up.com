# Captro category accounting and buyer checkout — 26 September 2026

## Scope

The existing Captro SwiftUI app (com.captro.app, scheme Captro), Cloudflare Worker, Supabase database and Stripe integration are retained. Branch: feature/recorded-voice-moderation. Stripe iOS SDK: 26.9.0. No new SDK, bank account, wallet, subscription or Stripe account per category was added.

Buyer checkout remains a platform PaymentIntent followed by authoritative server confirmation and entitlement issuance. Category reports never execute in the checkout path. Seller release, Connect transfer and payout remain separate operations. No production charge, transfer or payout was initiated during this work.

## Implemented

- Six accounting categories derive from immutable order snapshots: event, club, meetup, deal, group_access and local_offer. Unknown legacy types remain unassigned.
- Existing app_marketplace_ledger is the sole money-movement ledger. Security-invoker finance views provide order, object, category and seller totals; no duplicate balance tables.
- Pending combines pending/clearing/held/payout-in-progress. Available combines released and transferred-but-not-paid funds. Paid out means confirmed paid payout movements. Internal provider states remain intact.
- Future payouts are attributed FIFO to source orders within one seller, currency and Stripe mode. Partial payouts, repeated notifications and failure reversals append entries. Unmatched movements are flagged for reconciliation rather than assigned to a guessed order.
- Refund gross and returned platform fees append reversals. Unknown processing fees are displayed as unknown, not zero.
- Admin Captro Funds separates actual Stripe platform balances from accounting totals, with category → seller/object → order → immutable ledger/provider references. Queries are paginated and private/no-store.
- Ordinary buyers/sellers cannot call admin finance routes or directly read finance views. Sellers receive only their own current-environment totals.
- iOS earnings summary shows Available, Pending and Paid out.
- PaymentSheet retry obtains fresh customer credentials for the same order/PaymentIntent. It never auto-selects or confirms a saved card. Saving uses explicit opt-in.
- Release PaymentSheet diagnostics retain safe order/customer/intent/build/error correlation, underlying error codes and Stripe request IDs when available. Credentials and arbitrary provider payloads are not logged.

## Validation

- Local PostgreSQL-compatible PGlite tests: confirmed payment before seller setup; immutable ledger; refund reversal; duplicate confirmation; QR access/check-in; partial payout FIFO; failed payout reversal; cross-seller/currency/mode isolation; anon/authenticated finance denial.
- Backend TypeScript check and regression suite passed locally. Admin React/TypeScript production build passed.
- Stripe sandbox run 36281854065 passed against a disposable schema-only database and real Stripe test-mode API: first/second purchases, Customer reuse, consented saved-card attachment, signed payment webhook, ticket/QR, refund, later reviewed transfer, paid payout, admin pool drilldown and non-admin denial.
- Sandbox Customer: cus_VKlHd0Nq57zVaF. First PI: pi_3UK5ky2KVcRiAcs90Fbzfwvd. Second saved-card PI: pi_3UK5l52KVcRiAcs90Lz8Ouu3. PM: pm_1UK5kz2KVcRiAcs9uL8Im4Xr; allow_redisplay=always. These are synthetic sandbox fixtures, not physical-iPhone proof.
- Sandbox order a5458c3d-9372-4844-93b1-65244728aee9: 1000 USD cents paid, 941 cents seller payout attributed to the event pool after separate release. Transfer tr_3UK5l12KVcRiAcs91vWgn71m; payout po_1UK5lk2KVc1duj2G3Qni12tI. Duplicate transfer/payout prevented.
- A second sandbox run and scoped deployment dry run validate the final environment-isolation change before deployment.

## Buyer failure: not yet proven fixed on device

The user's reported TestFlight purchase remains failed. No physical iPhone is controllable in this environment. First-card, second-card/saved-card redisplay and completed 3DS cannot be marked PASS.

Read-only live audit found five users mapped to five distinct existing Stripe Customers. The sole stored live card had allow_redisplay=always; current CustomerSession flags succeeded for all five Customers. No live Captro purchase records or matching recent commerce PaymentIntents were found at audit time. This does not identify the exact iPhone failure and does not justify changing consent or recreating every Customer.

Cloudflare telemetry query was denied (HTTP 403, authentication error 10000). The available deployment credential lacks Workers Observability Write, which the telemetry query API requires. That permission was not broadened. Obtaining the exact device failure requires authorized Worker log access or the new Release buyer-checkout device diagnostics.

TestFlight 491.1 is live Stripe: never enter Stripe test-card numbers there. Automated test cards were confined to the protected sandbox. Apple Pay stays unavailable until its merchant configuration is complete; it is not required for card checkout.

## Files

- supabase/migrations/20260926235356_finance_category_reports.sql
- backend-cf/src/index.ts
- backend-cf/tests/deferred_marketplace_database.test.mjs
- backend-cf/tests/buyer_payment_sheet.test.mjs
- backend-cf/scripts/stripe-sandbox-schema.mjs
- backend-cf/scripts/stripe-sandbox-runtime.mjs
- backend-cf/scripts/audit-buyer-payment-methods.mjs
- .github/workflows/deploy-worker.yml
- admin-web/src/FinancePage.tsx, App.tsx, api.ts, types.ts, styles.css
- ios_native/MIRA/Sources/MIRANative/Models/CaptroCommerce.swift
- ios_native/MIRA/Sources/MIRANative/Screens/CaptroCommerceDashboardViews.swift
- ios_native/MIRA/Sources/MIRANative/Screens/CaptroPaymentSheetView.swift

## Deployment and remaining verification

Deployment results will be recorded below after CI completes. Existing sellers' payout schedules, fee policies and payment secrets/webhooks are not changed by this reporting deployment. Historical records whose environment/source cannot be verified must be reconciled, never guessed. Pool totals are accounting reports, not authorization for withdrawal and not legal escrow.
