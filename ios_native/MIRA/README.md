# Aura Mobile Native iOS

This is the native iOS app for Aura Mobile, converted from the former Captro app. It keeps the `com.captro.app` bundle identifier so the existing App Store Connect app record and TestFlight history carry over; only the display name, product name, and Xcode scheme/target changed to Aura.

## Stack

- Swift / SwiftUI / UIKit for UI, navigation, transitions, camera, media creation, chat, comments, feed, profile, discover, settings, and legal screens.
- C++ package target `MIRACoreCpp` for deterministic feed/media helpers.
- Rust `mira_core` static library wrapping the real vendored `aura-core` and `aura-wallet` crates. It generates/restores wallets, encrypts wallet files, derives public addresses, builds canonical transfers, and signs locally without exposing private keys to Swift.
- Cloudflare Workers API in `../../backend-cf`.

## Build

The GitHub Actions workflow generates the Xcode project from `project.yml` with XcodeGen, builds the Rust core, archives the app, exports an IPA, and uploads it to TestFlight.

Local Mac build:

```bash
cd ios_native/MIRA
brew install xcodegen
bash ./scripts/build-rust-ios.sh iphonesimulator
xcodegen generate --spec project.yml
xcodebuild -project Aura.xcodeproj -scheme Aura -configuration Debug -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build
```

`scripts/build-rust-ios.sh` requires a working Rust toolchain. It produces a universal simulator static library or an arm64 device static library before Xcode links the app.

## Production Notes

- Auth/session tokens are stored through the Keychain session provider.
- Aura wallet files are encrypted by Rust with Argon2id and XChaCha20-Poly1305. iOS Complete Data Protection is applied as an additional device-lock boundary, and the wallet password is never stored.
- The iOS app should only receive public configuration values and short-lived backend-generated tokens.
- Apple and Google secrets stay in provider dashboards, GitHub secrets, or Cloudflare Worker secrets.
- Keep generated Xcode projects, build output, Rust target directories, and local `.env` files out of git.
