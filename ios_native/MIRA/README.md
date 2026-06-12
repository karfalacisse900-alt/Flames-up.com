# Captro Native iOS

This is the production native iOS app for Captro.

## Stack

- Swift / SwiftUI / UIKit for UI, navigation, transitions, camera, media creation, chat, comments, feed, profile, discover, settings, and legal screens.
- C++ package target `MIRACoreCpp` for deterministic feed/media helpers.
- Rust crate scaffold in `rust/mira_core` for security-sensitive text/link checks and byte hashing.
- Cloudflare Workers API in `../../backend-cf`.

## Build

The GitHub Actions workflow generates the Xcode project from `project.yml` with XcodeGen, builds the Rust core, archives the app, exports an IPA, and uploads it to TestFlight.

Local Mac build:

```bash
cd ios_native/MIRA
brew install xcodegen
xcodegen generate --spec project.yml
xcodebuild -project Captro.xcodeproj -scheme Captro -configuration Debug -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build
```

## Production Notes

- Auth/session tokens are stored through the Keychain session provider.
- The iOS app should only receive public configuration values and short-lived backend-generated tokens.
- Apple/Google/Agora secrets stay in provider dashboards, GitHub secrets, or Cloudflare Worker secrets.
- Keep generated Xcode projects, build output, Rust target directories, and local `.env` files out of git.
