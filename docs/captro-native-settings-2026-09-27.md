# Native Settings and authentication presentation

## Scope

Active app: SwiftUI `Captro` scheme in `ios_native/MIRA`, bundle `com.captro.app`, iOS 17+. Branch: `feature/recorded-voice-moderation`. This is a presentation/navigation refactor of the existing application, not another app or backend.

## Implemented

- Replaced the hidden navigation bar/custom header with native push navigation, inline titles and standard back controls. Settings destinations hide both the native tab bar and Captro's custom tab-bar presentation through its existing visibility modifier.
- Introduced a shared grouped `List` scaffold and compact SF Symbol rows. Section grouping replaces individual floating cards. Controls use minimum 44-point hit areas, semantic fonts and existing adaptive Captro colors.
- Main Settings groups Account, Payments, Preferences, Support & safety, and Legal. The compact profile row returns to the existing Profile. Logout requires confirmation; deletion remains separately placed and requires typed confirmation plus existing reauthentication.
- Security is a menu. Email and password have dedicated editors with validation, submission guards, keyboard behavior and server-result banners. Profile editing reuses the existing editor and updates the authenticated profile/cache.
- Buyer payment-method management and seller payout configuration are separate destinations. Buyer cards still use Stripe CustomerSheet; payout setup still uses the existing coordinator. This work does not change checkout, ledger, verification, transfer, or payout business rules.
- Purchases & receipts uses the retained Profile activity model with native full-row navigation. Every purchase opens a receipt/details page; applicable ticket/QR and membership-access actions reuse the existing pass API and viewer. Missing fee/payment-method fields are omitted rather than fabricated.
- Privacy exposes the server-backed private-account setting and blocking tools. Unblocking requires confirmation and prevents duplicate requests; a failed load is not presented as an empty blocked list.
- Notifications displays actual iOS authorization state and routes changes to the supported system permission flow. Appearance persists the existing System/Light/Dark preference. Cache clearing is separate, confirmed, and invokes the existing media-cache operation without removing drafts.
- Support provides actionable contact/report/payment-help links. Location shows actual authorization and links to the app's iOS permission settings. Accessibility follows system text sizing and Reduce Motion rather than introducing a disconnected preference.
- Terms, Privacy Policy, Guidelines and Safety are readable documents with headings, selectable text and bounded reading width. Existing legal text/date are unchanged.
- Welcome, login, signup and password reset now use native navigation rather than a custom floating panel. Existing email, Apple, Google, consent and reset operations are preserved. No new photography or generated artwork was added.

## Removed misleading controls

The former activity-status, message-request, story-reply and per-category notification switches only wrote local preferences; no other code consumed those values. They were not real controls. They are no longer presented as if they change server behavior.

This pass does **not** implement missing two-factor enrollment, an active-session management API, per-category server notification preferences, muted-account management, phone-number editing, discovery-radius preferences, or self-service account export/deactivation. Data requests and report follow-up use the existing support address. No dead rows or fake success states were added for those features.

## Files

- `Screens/SettingsNativeView.swift`: architecture, grouped components, account/security/preferences/support/permission pages.
- `Screens/CaptroPaymentsView.swift`: separate buyer and seller destinations, reused payment model.
- `Screens/LegalNativeViews.swift`: document presentation.
- `Screens/AuthNativeView.swift`: welcome/login/signup/reset presentation; removed unused decorative welcome components.
- `Screens/ProfileChatVerificationStudio.swift`: permits reuse of the existing profile editor.
- `Screens/CaptroCommerceDashboardViews.swift`: permits reuse of the existing pass viewer from purchase details.
- `Screens/CaptroDesignQualityTestView.swift`: DEBUG-only native-tab navigation test host.
- `LayoutUITests/SettingsSystemTests.swift` and `DesignQualityTests.swift`: native navigation, keyboard, appearance/cache, document and auth checks.
- `.github/workflows/native-settings-validation.yml`: macOS simulator build/UI test workflow and screenshot artifacts.

All Swift paths above are relative to `ios_native/MIRA/Sources/MIRANative`, except the explicitly named test/workflow paths.

## Validation

Native build/UI validation is being run on GitHub's macOS 26 runner with the iPhone 17 simulator. Final results and artifact references will be recorded after the runs complete. These UI-only tests do not submit credentials, modify production account settings, or perform payments.

No dependencies, migrations, production API deployments, payment configuration changes, or payout schedule changes are required by this refactor. A physical iPhone is not available in this environment; device, VoiceOver, authenticated account-change and live Stripe-management testing remain distinct acceptance checks.
