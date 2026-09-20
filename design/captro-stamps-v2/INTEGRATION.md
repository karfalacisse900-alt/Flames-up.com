# Captro native integration

The source kit is retained here. `tools/build-designs.py` owns geometry and palettes.
`tools/export-swift.py` compiles those shapes into the app's bundled drawing commands;
titles, prices, dates and terms remain live UIKit text. No WebView, bitmap title,
font download or new mobile dependency is used.

Rebuild (Python 3, development-only `fonttools==4.59.2`):

```
python design/captro-stamps-v2/tools/build-designs.py
python design/captro-stamps-v2/tools/export-swift.py
```

Native entry points: `CaptroPostStamp`, `CaptroStampArtwork`, `CaptroStampAdapter`.
Feed/editor use compact 640×224 at 232 points. Details use 640×288 with 3.5%
deterministic vector fibers. Feed texture remains off pending device profiling.
System sans and installed Georgia are measured with NSString, not estimated.
Unknown variants fall back within their own family. Important term overflow uses
neutral details copy; an overflowing deal condition also suppresses its benefit.

Post identity and `detail.commerce.id` remain separate. Stamp taps invoke the
existing post-details route, which loads the attached commerce record and invokes
the existing commerce services only after an explicit details-screen action.
Styles never call purchase, join or redeem endpoints. No payment implementation
or authorization changes were made.

`stamp_variant` is an allowlisted value in existing post metadata. Worker changes
must be deployed before selected styles round-trip on the live service. There is
no migration. No production deployment/data mutation is part of this change.
Older records use the family default. Drafts include the style and no longer get
silently cleared on process startup. Explicit discard and publish still clear them.

Existing commerce creation supports one-time prices, not creation of subscriptions.
Existing recurring records display their billing interval. Offer conditions are
free-form `redemptionRules`, not a structured minimum spend: these are preserved
verbatim, never parsed into fabricated benefits. Missing conditions produce
“View offer”. Missing commerce facts never imply free access. Cash-back/drop styles
do not create a rewards backend or claim verified purchases/paid rewards.

Tests: backend `stamp_v2.test.mjs`, updated existing stamp guards, native
`CaptroStampTests`, and focused `StampVisualTests` through the manually dispatched
Validate Captro Stamps workflow. Debug-only fixture screens cannot publish or charge.
Actual device scrolling, VoiceOver, real account publication/reload, and before/after
production screenshots require further verification. A CI screenshot is an offline
app fixture, not proof of live backend deployment or successful purchases.
