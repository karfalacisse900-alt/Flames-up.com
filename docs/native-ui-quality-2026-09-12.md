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
| Onboarding and auth | Safe-area layout, restrained typography, removal of decorative background shapes, persistent form labels and focus borders, Google's supplied sign-in control |
| Settings | Readable rows and toggle labels, shared forms, appearance selection states, duplicate-submit guards, real cache-completion feedback |
| Home, notifications and chat inbox | Explicit load failures with retry instead of misleading empty states; larger Home toolbar touch targets |
| Search | Cancelled-request handling, stale-result protection, error/retry state, clear-search label and touch target |
| Posting | Confirmation before discarding a draft; prevent cancelling during submission; consistent primary action |
| Chat | Dark appearance, larger controls and semantic message text, removal of redundant bottom spacing |
| Profiles and legal | Wrapping profile headings, readable navigation copy, scalable legal body text |
| Post details and commerce | Adaptive surfaces and text, accessible comment input and cancel target, consistent commerce action, scrollable payment summary |

## Verification

- Backend regression suite: 134 tests passed locally after the UI changes.
- Backend TypeScript check: passed.
- Final native compilation and simulator verification: [run 34730708156](https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/34730708156) passed on code revision `bfbe9b995a8c08a3057ef1489c3506be2c8fa981`. Eight test cases passed on each device, for **16 passed, zero failures**. The same run also passed all 134 backend tests and the TypeScript check.
- Reviewed the exported final screenshots for draft confirmation, cache completion, sign-in, search with the keyboard, legal reading and dark large-text settings, in addition to the earlier shared-control and Home media screenshot review. No app crash or Auto Layout constraint errors were found in the final test log; this is limited to the exercised flows.
- The simulator suite covers shared controls, sheet scrolling/dismissal, menus, large-text onboarding/forms, dark large-text settings, cache completion, draft retention, search clearing, legal reading, and Home photo/video layout on small and large iPhones.
- Debug-only visual entry points are excluded from Release. They do not replace production payment or payout behavior.

### Findings fixed during screenshot and interaction review

- The compact iPhone discard confirmation exposed a destructive action without a visible cancel option. It now uses an explicit two-button alert, and the test verifies that choosing **Keep editing** preserves the exact draft text.
- Fresh simulators can display Apple's first-time keyboard tutorial. The test handles that system prompt before typing; it does not skip or weaken the draft-retention assertion.
- The sign-in screen still had inconsistent heavy typography and an improvised Google icon. It now uses the shared text/control treatment and the existing Google SDK's supplied button.
- Unavailable account settings were being presented as a known public-account state. The screen now distinguishes a load failure, offers pull-to-refresh, and does not imply that unknown privacy settings are known.

### Reproduction

Run the **Native payments validation** GitHub Actions workflow on the target branch. Its simulator step builds the complete native app and runs `DesignQualityTests` and `HomeFullBleedTests` on an iPhone SE (3rd generation) and iPhone 17 Pro Max. The `home-full-bleed-simulator-evidence` artifact contains the build/test log, result bundles and exported screenshots. `skip_generic_build=true` skips only the redundant generic build, not the simulator app build or tests.

## Coverage boundaries

Authenticated posting/chat, physical camera capture, VoiceOver on a physical device, and live purchase/withdrawal transactions require dedicated account/device checks. Simulator layout tests are not evidence that real-money transfers succeeded. No payment-provider, payout-account, ledger, or backend money-handling implementation is changed by this pass.

Existing SDK deprecation warnings remain in camera/location code. They were not converted into broad API migrations during this visual pass.
