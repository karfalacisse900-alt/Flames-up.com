# Home Full-Bleed Release

## Scope

The Home media frame stays at the available feed width. If a tall image exceeds
the page's available height, the existing fill renderer crops vertically instead
of shrinking the frame horizontally. An explicitly sized pager no longer applies
a second aspect-fit layout constraint. Only the feed media ignores horizontal
container safe areas; navigation and stamp styling remain unchanged.

The release branch `release/home-full-bleed-20260904` starts at the last released
TestFlight commit `f255124236a6bbb7da2980d58af1150518911d60`. Release commit
`a9ea957c65bdbbe167f0ee31be04967809a7de27` contains the layout fix and its QA only.
It excludes the unreleased native PaymentSheet/backend migration work on
`fix/oauth-guest-access`. No backend deployment or payment-mode switch accompanies
this layout release.

## Simulator Evidence

[Release validation run 33935409381](https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/33935409381)
passed compilation, backend checks, and real XCUITests on iPhone SE (3rd generation)
and iPhone 17 Pro Max. The tests launch the actual Home screen with DEBUG-only local
media fixtures, not the obsolete standalone vertical-feed preview.

Both devices passed all five supported photo ratios and actual H.264 video.
Accessibility frame assertions verified x=0 and maxX=screen width. Video pause/play
controls were exercised. The exported screenshots were inspected, and pixel checks
confirmed colored media continuously reaches both outermost columns on all 12 images:

| Device | Screenshot Width | First Media Column | Last Media Column |
| --- | ---: | ---: | ---: |
| iPhone SE (3rd generation) | 750 px | 0 | 749 |
| iPhone 17 Pro Max | 1320 px | 0 | 1319 |

Artifacts: `home-full-bleed-simulator-evidence`, including xcresult bundles,
attachment manifests, screenshots, and the simulator log. QA fixtures never ship
in Release builds and do not replace real users' media.

[Development validation run 33935244798](https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/33935244798)
also passed the simulator checks, TypeScript validation, and all 115 backend tests.
This is not evidence of real payment or payout acceptance.

## Distribution

[TestFlight run 33936494619](https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/33936494619)
successfully uploaded version 1.0.1 (439.1) from the isolated layout release commit.
Apple reported `UPLOAD SUCCEEDED with no errors` at 2026-09-05 01:39:29 UTC.
Delivery ID: `490a5cdd-ba09-484d-b861-7d04519a0dae`.
App Store processing/tester availability was not independently confirmed.

## Payout Status

Sandbox Connect activation and real Captro onboarding-link creation passed in
run `33934777282`. Live Connect still requires account-owner setup. This release
does not claim live payouts work. See [the native payment release gate](stripe-native-release.md)
for the incomplete purchase-to-payout acceptance and production prerequisites.
