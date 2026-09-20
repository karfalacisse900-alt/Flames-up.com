# Codex handoff — Captro Stamps V2

## Task

Replace the previous Captro stamp visuals with this kit. Keep exactly five product types: `moment`, `club`, `event`, `meetup`, `deal`. Keep the rest of the application and its existing navigation intact. Inspect the actual repository before editing; this kit does not know its routes, schemas or backend.

## Implementation

1. Use `src/render-stamp.ts`, `src/templates.ts` and the appropriate web/native component. Preserve the supplied geometry, colors and typography hierarchy. Never crop the contact sheet or display a static screenshot as a live stamp.
2. Start with `density="compact"` and `width={232}` in the feed. Use the full layout in larger detail views. Geometry is 640 × 224 compact and 640 × 288 full, not V1's 640 × 264. Never stretch the SVG into a different ratio.
3. Put one stamp over the media, with about 12px inset. Preserve media ratios 4:5, 1:1, 3:4 and 16:9. Do not add large promotional cards, nested buttons or extra feed tabs.
4. Populate `StampData` with real app records. Use `compactText` as an app-authored short summary with the essential price/date/condition; it must not contradict the full details. Preserve full names and terms in the detail view. Overlong financial fields must use the complete fallback, never an ellipsis that changes the amount.
5. Use `data.id` and `data.type` to open the correct existing detail route through `onPress`. No guessed route names. Pressing the stamp only opens details; it must not purchase, join, reserve, redeem, scan, verify or pay automatically.
6. Keep receipt rewards, visit-to-unlock and limited drops under `deal`. A subtype/variant does not introduce another product category. Keep Moment as a normal social post, not a sales card.
7. Use the app's own authentication, server-side eligibility, inventory, expiry and payment logic. These stamps are display components. Do not create fake rewards, member counts, active offers, admission QR codes or completed redemptions to make a demo appear functional.
8. Bind real state (`active`, `saved`, `joined`, `claimed`, `used`, `expired`, `full`) without mutating the record. A rendered expired state does not itself enforce server permissions. Keep eligibility and availability enforcement in the existing backend.
9. Reuse installed app fonts or configure the wrappers' `fonts` prop. No fonts are bundled. The outlined SVGs preserve the reference examples but are not suitable for live editable text. Do not import arbitrary user-provided SVG/HTML. All dynamic strings must continue to pass through the renderer's escaping.
10. Honor accessibility labels and reduced motion. Keep full details readable at the device's text-size settings. Offer a discoverable hide/restore control on the surrounding media where supported, rather than hiding stamps during scrolling.

## Mapping

| Type | Visual variants | Typical detail action |
|---|---|---|
| Moment | `moment-paper`, `moment-postal`, `moment-voice` | Open post; real audio controls live on its detail view. |
| Club | `club-oval`, `club-member`, `club-tag` | Open club / membership details. |
| Event | `event-ticket`, `event-screening`, `event-postal` | Open event / ticket details. |
| Meetup | `meetup-note`, `meetup-fold`, `meetup-route` | Open meetup / attendance details. |
| Deal | `deal-coupon`, `deal-cashback`, `deal-drop` | Open offer, eligibility and terms. |

Use the application's real data names and create an explicit adapter. Do not infer ticket prices, payout amounts, local dates, subscription periods or minimum spending from decorative strings in example assets. Format these from validated source values.

## Acceptance checks in the app

- All five types open their correct detail screen using a real record ID.
- No duplicate categories, extra tabs or irreversible actions on stamp tap.
- One stamp per post; supported photo/video ratios remain unchanged.
- Compact layouts remain readable on the actual smallest supported phone. Test 232px and nearby widths, the app's real fonts, long titles and the app's supported languages.
- Expired, used, claimed, joined and full states are visible and do not bypass server rules.
- Repeated cells in a real feed scroll smoothly. Keep texture off in compact feeds by default.
- Screen-reader labels preserve full context, focus is visible on web, and normal scalable text in the detail view exposes all terms.
- No real payments, rewards or merchant offers are fabricated from the sample data.

## Validation boundary

The shared renderer and studio were tested in this kit. The wrappers were syntax-checked, not run in Captro, an iOS simulator, an Android emulator or a physical device. Verify native font rendering, touch gestures, navigation, accessibility and backend behavior in the actual application before release. Do not claim the live app was updated until you actually integrate and run it.
