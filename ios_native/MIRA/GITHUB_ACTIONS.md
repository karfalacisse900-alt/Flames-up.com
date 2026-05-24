# Native iOS GitHub Actions Build

The `Native iOS TestFlight` workflow builds the production SwiftUI/C++/Rust app from `ios_native/MIRA`.

## What The Workflow Does

1. Checks out the repo.
2. Builds the Rust core for `aarch64-apple-ios`.
3. Generates `MIRA.xcodeproj` from `project.yml` with XcodeGen.
4. Builds the SwiftUI app and C++ package target.
5. Archives and exports an `.ipa`.
6. Uploads the `.ipa` artifact.
7. Uploads the build to TestFlight with App Store Connect API credentials.

XcodeGen is used in CI so Windows development can still produce a native iOS archive through GitHub-hosted macOS runners.

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
base64 -i MIRA_App_Store.mobileprovision | pbcopy
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

Paste those copied values into:

- `IOS_DISTRIBUTION_CERTIFICATE_BASE64`
- `IOS_PROVISIONING_PROFILE_BASE64`
- `APP_STORE_CONNECT_API_KEY_BASE64`

The provisioning profile must match the bundle ID configured in `project.yml` and `.github/workflows/native-ios-testflight.yml`.

## Run

Open:

`Actions` -> `Native iOS TestFlight` -> `Run workflow`

When the run succeeds, TestFlight processing starts in App Store Connect.
