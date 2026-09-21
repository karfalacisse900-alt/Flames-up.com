# Captro Stamps V2 implementation evidence

## Real app screenshots

### Physical-material refinement pass

Final iPhone 17 feed-scale captures from commit `de962c61`, Actions run
`35551395291`:

- [Moment on a photograph](refinement-feed-moment.png)
- [Club on a photograph](refinement-feed-club.png)
- [Event on a photograph](refinement-feed-event.png)
- [Meetup on a photograph](refinement-feed-meetup.png)
- [Deal on a photograph](refinement-feed-deal.png)

These use the production native stamp component at its responsive feed width over a
read-only photograph from Captro's public feed. The surrounding header/action layout
is a non-writing DEBUG QA fixture at the real iPhone viewport; it is not a redesigned
production feed. The run passed six native renderer/data tests and one five-family
tap/screenshot flow. The photos verify the compact stamp scale, contrast, complete
Event title, Club/Meetup spacing, and Deal merchant plus qualifying condition.

This pass changed only stamp presentation: responsive 184–214 point sizing, close
contour-following contact shadow, deterministic 2.4% paper fibers, quieter Moment,
physical Club pass construction, multiline fallback for genuinely long Event/Club/
Meetup titles, and a printed paper state slip instead of a rounded UI capsule. Data,
navigation, five-family mapping, media ratios and consequential actions are unchanged.

The final signed app archive uploaded successfully to TestFlight as **1.0.1 (464.1)**
in run `35552279096` at 2026-09-21 02:04:05 UTC. Apple-side processing and tester
availability occur after upload and were not verified in this run.

- [Before](home-before.png): Home's production component in the offline media fixture,
  September 19, commit `6d9cfa98`, iPhone 17 Pro Max, Actions run `35458338471`.
- [After](home-after.png): same square-media fixture in Home, September 20 local time,
  commit `127373b6`, iPhone 17, Actions run `35546384608`.

These are actual app screenshots, not rendered marketing mockups. Device sizes differ;
they are not a pixel-for-pixel viewport comparison. Colored stripes are the existing
offline media fixture, not a customer's photo. The later accessibility-only fix does
not change the artwork shown here.

[Deal material comparison](deal-materials.png) shows the actual native component
over light, dark and busy fixture backgrounds, with real transparent cutouts and
conditions retained alongside Expired / Saved. Run `35547481917`, commit `c35b28c6`.

## Changed implementation

- `design/captro-stamps-v2`: supplied source subset, refined source generator,
  native exporter, template definitions, palettes and provenance/reference previews.
- `Components/CaptroStampArtwork.swift`: native paths, live measured text, protected
  financial/condition overflow, real waveform input, texture off in the feed.
- `Components/CaptroPostStamp.swift`: five-family adapter, 15 style IDs, single detail
  button, separate printed availability/relationship slip, responsive feed sizing,
  screen-reader description.
- `Models/CaptroStampAdapter.swift`: real commerce dates/timezones, billing intervals,
  offer conditions and status; no amounts parsed from decorative strings.
- `CaptroFeedPostOverlays`, `CaptroFeedMediaPager`, `CaptroFeedPostView`: record mapping,
  232-point compact overlay with 12-point inset, text-only content retained.
- `NotificationLibrarySearchCreateViews`: one optional style picker, shared previews,
  saved style, editable deal conditions. Done remains draft-only.
- `CaptroCommerceDetailViews`, `CaptroPostDetailSections`: full renderer alongside
  scalable existing information and confirmed actions. Saving stays in details.
- `MIRAModels`, `MIRAAppCacheStore`, `MIRAAuthSession`: style encoding/cache preservation,
  drafts survive process restart and are cleared on explicit logout/guest transition.
- `backend-cf/src/stamp-style.ts`, `index.ts`, `commerce.ts`: allowlisted presentation
  metadata and truthful expired/cancelled attachment reads. No schema migration.
- Native/backend tests and focused validation workflow.

## Navigation and data

Moment opens the existing post/conversation. Club, Event, Meetup and Deal open the
existing post-details route, which fetches its attached commerce record. The post ID
is not passed as a purchasable ID: actions continue to use the loaded commerce ID.
Stamp tapping cannot purchase, subscribe, join, redeem, verify a receipt or pay a reward.
Existing backend permission, inventory and transaction checks remain in place.

## Verification and limits

- 146 backend tests passed; TypeScript `tsc --noEmit` passed.
- Four native tests passed: 30 layouts with real iOS font measurements, recurring vs
  one-time prices, safe state/condition separation, style reload/engagement updates.
- Home UI test passed for the five ratios already supported by this repository.
  This stamp update does not add a previously unsupported 16:9 media pipeline.
- The first dedicated interaction test exposed a wrapper accessibility issue; the
  label/identifier now belong directly to the Button, not an enclosing Other element.
  Corrected run `35547481917` passed all four native tests and the interaction test,
  which captured all 15 styles.
- Release archive and TestFlight upload of 1.0.1 (463.1), including the accessibility
  correction, succeeded in run `35547500932` at 2026-09-21 00:37:27 UTC. Apple's
  subsequent processing/tester availability was not verified.

The user approved stamp-only backend deployment. Release branch `release/stamp-only`
isolates the three runtime files from unrelated voice work, based on the last successful
production source release `af5bdc3e`. All 136 baseline/release tests and type checking
passed. Run `35548091184` deployed Worker version
`3e9b942b-f6a4-4eb3-9ba2-59287af678f9`. Its final unauthenticated curl probe received
403 on the GitHub runner; subsequent public API and workers.dev probes both returned
200. A read-only public feed probe confirmed `stamp_variant` in the live response.
No migrations, secret rotation, payment provisioning or production test posts were run.
Real-account publishing/reload, real-device
scroll profiling, smallest-phone/larger-text VoiceOver checks, and live payment/join/
redemption flows remain unverified. No real charges or public test posts were created.
Feed texture remains disabled. A cashback/drop visual variant does not supply a missing
reward backend. Existing creation supports one-time pricing; it does not create new
recurring subscriptions. Missing terms show a neutral “View offer” summary.

The Supabase skill informed reuse of the existing metadata column and retention of
existing authorization; no schema, RLS or live database changes were made.
