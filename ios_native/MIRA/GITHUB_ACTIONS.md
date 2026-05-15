# Native iOS GitHub Actions Build

This native build path is for the SwiftUI/C++/Rust iOS app in `ios_native/MIRA`.
It is separate from the Expo/EAS build.

## What the workflow does

`.github/workflows/native-ios-testflight.yml` runs on a GitHub-hosted Mac:

1. Checks out the repo.
2. Builds the Rust core for `aarch64-apple-ios`.
3. Generates `MIRA.xcodeproj` from `project.yml` using XcodeGen.
4. Builds the SwiftUI app and C++ package target.
5. Archives and exports an `.ipa`.
6. Uploads the `.ipa` to TestFlight with App Store Connect API credentials.

XcodeGen is used only in CI because this repo is being authored from Windows and does not yet have a checked-in Xcode project.

## Required GitHub secrets

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

## How to create the certificate/profile secrets

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

The provisioning profile must match:

```text
com.karfala90.frontend
```

## How to run it

Push this repo to GitHub, then open:

`Actions` -> `Native iOS TestFlight` -> `Run workflow`

When the run succeeds, TestFlight processing starts in App Store Connect. Apple can take a few minutes before the build appears.

## Current native status

This workflow builds the native SwiftUI app foundation. The Expo app remains separate.

Still to wire in native iOS:

- Apple Sign In screen flow
- Google Sign In native SDK flow
- Agora native voice/video calls
- Full native camera/story editor
- Production push-notification registration
- Rust static library linking into Swift/C++ runtime
