# Native iOS GitHub Actions Build

Three workflows cover Aura Mobile's iOS CI/CD, all building the SwiftUI/C++/Rust app from `ios_native/MIRA`:

- **`ios-ci.yml`** — every push and pull request touching `ios_native/MIRA/**`. Builds for the simulator and runs unit tests. No signing, no upload. This is what runs on ordinary commits so TestFlight build numbers aren't spent on every push.
- **`native-ios-testflight.yml`** ("Aura iOS TestFlight") — only on `workflow_dispatch` or a pushed `ios-v*` tag. Builds, signs, archives, exports an IPA, uploads to App Store Connect, and distributes to the TestFlight beta group once processing finishes.
- **`native-ios-testflight-distribute.yml`** ("Aura iOS TestFlight Distribution") — `workflow_dispatch` only, to assign an already-uploaded and already-processed build to a beta group without rebuilding.
- **`rust-mobile.yml`** — runs `cargo test` for `rust/mira_core` and the vendored `aura-core`/`aura-wallet` crates on any push or PR touching `ios_native/MIRA/rust/**`.

## What The TestFlight Workflow Does

1. Checks out the repo.
2. Builds the Rust core for `aarch64-apple-ios`.
3. Generates `Aura.xcodeproj` from `project.yml` with XcodeGen.
4. Builds the SwiftUI app and C++ package target, and runs unit tests.
5. Reads the latest processed build number from App Store Connect via the ASC API key and uses `latest + 1` — it never guesses or reuses a run-number-based build number.
6. Archives and exports an `.ipa`.
7. Uploads the `.ipa` artifact.
8. Uploads the build to TestFlight with App Store Connect API credentials, then waits for processing and assigns it to the beta group.

XcodeGen is used in CI so Windows development can still produce a native iOS archive through GitHub-hosted macOS runners. The bundle identifier stays `com.captro.app` on purpose — it is what keeps this build attached to the existing App Store Connect app record and its TestFlight history; only the display name, product name, scheme, and target changed to Aura.

## Required GitHub Secrets

Add these in GitHub:

`Settings` -> `Secrets and variables` -> `Actions` -> `New repository secret`

- `APPLE_TEAM_ID`
- `IOS_DISTRIBUTION_CERTIFICATE_BASE64`
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`
- `IOS_PROVISIONING_PROFILE_BASE64`
- `IOS_PROVISIONING_PROFILE_NAME`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_BASE64`
- `KEYCHAIN_PASSWORD`

`KEYCHAIN_PASSWORD` can be any strong random value.

## Certificate/Profile Encoding

On a Mac with Apple Developer access:

```bash
base64 -i Certificates.p12 | pbcopy
base64 -i Captro_App_Store.mobileprovision | pbcopy
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

Paste those copied values into:

- `IOS_DISTRIBUTION_CERTIFICATE_BASE64`
- `IOS_PROVISIONING_PROFILE_BASE64`
- `APP_STORE_CONNECT_API_KEY_BASE64`

The provisioning profile must match the bundle ID `com.captro.app` configured in `project.yml` and `.github/workflows/native-ios-testflight.yml`.

## Run

Open:

`Actions` -> `Aura iOS TestFlight` -> `Run workflow`

Or push a tag matching `ios-v*` (e.g. `ios-v1.0.2`).

When the run succeeds, TestFlight processing starts in App Store Connect.
