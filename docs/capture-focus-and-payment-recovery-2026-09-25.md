# Captro Capture focus and payment recovery

## Implementation

Active app: Captro, bundle com.captro.app, native SwiftUI, iOS 17+. Branch: feature/recorded-voice-moderation. App source commit: 4254a77f. Build: 1.0.1 (484.1).

- CaptroCaptureFocusView: full-bleed retained media; compact creator/close controls; left-edge dock with finger-driven expansion; lower 55% details sheet; tap-to-hide chrome; exclusive hold/swipe gestures; brief capture counter. No segmented bars, automatic photo timer, permanent reply field, or heavy media gradients.
- DiscoverNativeView and MainFeedView: native full-screen presentation with safe-area-aware controls; swipe visits each capture before moving between groups; stable group IDs instead of author IDs; previous group opens its final capture. Existing bounded prewarming, background pausing, reporting, blocking, viewers, and private replies remain.
- CaptroCaptureDetailsSheet: actual linked-post and commerce data, no fabricated attendance/prices, separate attachment/post IDs, details navigation without purchases. Existing player remains mounted behind the sheet.
- ProfileChatVerificationStudio: restored Payments toolbar shortcut and retained payment model.
- CaptroPaymentsView: prominent Continue Seller Setup action and clear separation of buyer cards from seller readiness.
- CaptroPaymentSheetView: invalid payment configuration produces an explicit error instead of a blank payment action area.
- backend-cf/src/purchase-errors.ts and index.ts: specific recovery for owning an item, expired/unavailable inventory, changed prices, capacity, and seller restrictions. No bypass of payment or seller eligibility.
- CI: read-only Stripe readiness and TestFlight availability checks. Scoped Worker deployment retains existing payment credentials and webhooks.

## Verified

- 178 automated tests passed locally and on the deployment runner; TypeScript check passed.
- Actual commerce migrations executed in isolated PGlite: free club join confirms membership with an unready seller, duplicate requests do not duplicate membership, buyer does not receive a Connect account, own-item purchase is rejected, restricted paid seller is rejected. Existing payment snapshot/refund/idempotency tests passed.
- Cloudflare production deploy succeeded (run 36205673579), Worker version c1c2ce42-ead8-4b89-ae0d-f7238aca5e07. Private R2 bucket and configured voice credential confirmed. Auth-required voice, status, and chat route checks passed; these are NOT authenticated end-to-end upload tests.
- Reviewed additive seller identity status migration applied. Backend-only RLS/grants; no identity images or sensitive document data. Optional separate Stripe Identity policy not enabled, no paid verification session created.
- Direct Stripe API read confirmed platform live card payments/transfers enabled and relevant webhook endpoints enabled. All connected seller accounts returned inactive transfers and requirements.past_due: business_type, external_account, tos_acceptance.date, tos_acceptance.ip. The two existing paid listings have no payout-ready seller.
- Live database contained one unexpired capture; seven older captures had passed their 24-hour window. Expired media was not republished.
- Apple's API confirmed new build 484.1 is VALID and IN_BETA_TESTING in Captro private and Captro private2, with auto-notify enabled (status run 36208071837, 2026-09-26 01:20:20 UTC). External status is READY_FOR_BETA_SUBMISSION; no external beta review approval is claimed.

## Remaining requirements / limitations

- The actual seller must complete Profile > Payments > Continue Seller Setup, including accurate business details, supported payout destination, and Stripe's terms/verification. Captro cannot complete these declarations or fake eligibility. No live card was charged and no end-to-end live purchase is claimed.
- Free joining was executed against isolated database fixtures, not through a signed-in physical iPhone. Its real-device API/UI path remains unverified.
- Viewer source-contract checks are not gesture measurements. No physical-iPhone visual, gesture, accessibility, or FPS testing was available. No real-device screenshots are claimed.
- Details reveal only available backend fields; member-avatar lists and proximity are not invented. Full transactions continue in existing detail screens.
- Browser App Store Connect session was expired. Read-only API verification uses existing authorized CI credentials; it does not require a new browser login.

## Release

Build 484.1 compiled, archived, exported, and uploaded successfully in run 36207072011. Apple upload confirmation: 2026-09-26 01:15:05 UTC, delivery db1ba80b-3933-4824-b116-85510d14b0d5. Apple separately confirmed VALID / IN_BETA_TESTING and assignment to Captro private and Captro private2 at 01:20:20 UTC. Earlier build 482.1 failed compilation on an accessibility action signature; this was corrected before the successful build.
