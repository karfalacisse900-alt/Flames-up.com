# Captro native UI quality pass

## Design rules

- Preserve the media-led feed and Captro identity; remove decorative onboarding shapes and oversized marketing typography.
- Use neutral surfaces, semantic text colors, restrained shadows, and a shared 10-point control radius.
- Reserve filled primary buttons for the main action. Use at least 44-point touch targets, with 48-point form controls where practical.
- Use Dynamic Type for shared controls, form labels, settings rows, message text, legal reading, and primary commerce actions.
- Keep labels visible while typing; show focus explicitly and distinguish disabled controls from available actions.
- Preserve white QR/barcode canvases for machine readability even in dark appearance.

## Implemented scope

| Area | Changes |
| --- | --- |
| Shared components | Button dimensions, disabled/pressed feedback, typography, empty-state wrapping, neutral surfaces and reduced shadows |
| Presentations | Scroll-safe sheet dismissal handle, constrained sheet height, modal accessibility isolation, escape actions, protection against stale dismissal callbacks |
| Onboarding and auth | Safe-area layout, restrained typography, removal of decorative background shapes, persistent form labels and focus borders |
| Settings | Readable rows and toggle labels, shared forms, appearance selection states, duplicate-submit guards, real cache-completion feedback |
| Home and notifications | Explicit load failures with retry instead of misleading empty states; larger Home toolbar touch targets |
| Search | Cancelled-request handling, stale-result protection, error/retry state, clear-search label and touch target |
| Posting | Confirmation before discarding a draft; prevent cancelling during submission; consistent primary action |
| Chat | Dark appearance, larger controls and semantic message text, removal of redundant bottom spacing |
| Profiles and legal | Wrapping profile headings, readable navigation copy, scalable legal body text |
| Post details and commerce | Adaptive surfaces and text, accessible comment input and cancel target, consistent commerce action, scrollable payment summary |

## Verification

- Backend regression suite: 134 tests passed locally after the UI changes.
- Backend TypeScript check: passed.
- Native compilation and simulator evidence are tracked in the GitHub Actions runs for `polish/native-ui-quality`.
- The simulator suite covers shared controls, sheet scrolling/dismissal, menus, large-text onboarding/forms, dark large-text settings, cache completion, draft retention, search clearing, legal reading, and Home photo/video layout on small and large iPhones.
- Debug-only visual entry points are excluded from Release. They do not replace production payment or payout behavior.

## Coverage boundaries

Authenticated posting/chat, physical camera capture, VoiceOver on a physical device, and live purchase/withdrawal transactions require dedicated account/device checks. Simulator layout tests are not evidence that real-money transfers succeeded. No payment-provider, payout-account, ledger, or backend money-handling implementation is changed by this pass.

Existing SDK deprecation warnings remain in camera/location code. They were not converted into broad API migrations during this visual pass.
