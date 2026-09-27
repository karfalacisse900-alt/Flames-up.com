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

This pass does **not** implement missing two-factor enrollment, an active-session management API, per-category server notification preferences, muted-account management, phone-number editing, discovery-radius preferences, or self-service account export/deactivation. Data requests and report follow-up use the existing support address. A dedicated licenses listing was not added. No dead rows or fake success states were added for those features.

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

Native validation uses GitHub's macOS 26 runner, Xcode and the iPhone 17 simulator (iOS 26). These UI-only tests do not submit credentials, modify production account settings, or perform payments. Screenshots therefore include the honest unauthenticated/error state, not a fabricated signed-in profile or fake cards.

- Source `3cbacfd3`: [native Settings validation](https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/36354171378) passed all five UI tests. They exercise buyer/seller separation and logout cancellation; dark/accessibility-size legal documents; native back/swipe-back, hidden tabs and email/password validation; separate Appearance/Storage and cache cancellation; welcome/login/signup/back navigation.
- Source `3cbacfd3`: [Home/Stamp regression](https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/36354171371) passed 37 unit tests and two UI tests.
- An earlier Settings run exposed an iOS 26 confirmation-dialog adaptation: the system showed a dismissible popover without a Cancel button. Cache clearing and main Settings logout now use native alerts with explicit Cancel actions; the rerun passed.
- Reviewed actual simulator screenshots of main Settings, Security, login/signup/welcome, dark large-text legal documents, buyer payment methods and cache confirmation. Tightened list row/top insets and removed the nested decorative error container based on those screenshots.
- Final source `fc844783`: [Settings validation](https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/36354702983) passed all five UI tests; [Home/Stamp regression](https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/36354702809) also passed. This includes the fractional-second-aware purchase date parsing update.

Test runtimes are not app responsiveness benchmarks. No physical-device frame-rate, tap-latency or launch-time claim is made. iOS 26 renders its standard native back control with a system background; Captro no longer supplies a custom floating circular back button for these screens.

No dependencies, migrations, production API deployments, payment configuration changes, or payout schedule changes are required by this refactor. A physical iPhone is not available in this environment; device, VoiceOver, authenticated account-change and live Stripe-management testing remain distinct acceptance checks.

## TestFlight delivery

- Release source: `fc844783440b46ea947ab402b961ae49bc677a9b`.
- Version/build: **1.0.1 (499.1)**.
- [Release build and upload](https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/36355937872): succeeded. IPA export succeeded; Apple upload reported `UPLOAD SUCCEEDED with no errors` at 22:52:18 UTC on September 27, 2026.
- [Read-only Apple status verification](https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/36357028799), September 27 at 22:57:21 UTC: build `499.1`, version `1.0.1`, processing `VALID`, internal state `IN_BETA_TESTING`, assigned to `Captro private` and `Captro private2`. External state is `READY_FOR_BETA_SUBMISSION`; this is not an external-beta approval or public App Store release.

## Actual simulator captures

These are captures from the final-source validation run, not mockups. The unsigned test host intentionally shows real account-loading errors where authentication is required.

- [Main Settings](C:/Users/The-s/AppData/Local/Temp/captro-settings-final/settings-screenshots/settings-main-light.png)
- [Security menu](C:/Users/The-s/AppData/Local/Temp/captro-settings-final/settings-screenshots/settings-security-menu.png)
- [Appearance](C:/Users/The-s/AppData/Local/Temp/captro-settings-final/settings-screenshots/settings-appearance.png)
- [Login](C:/Users/The-s/AppData/Local/Temp/captro-settings-final/settings-screenshots/login-native.png)
- [Signup](C:/Users/The-s/AppData/Local/Temp/captro-settings-final/settings-screenshots/signup-native.png)

The screenshots also remain in the final-source GitHub validation artifact; local temporary copies are not permanent repository assets.
