# MIRA Native iOS Layer

This folder starts the native SwiftUI migration while keeping the current Expo app and backend working.

What this does now:
- Keeps the existing backend/API contract.
- Adds a SwiftUI design system with clean white surfaces, forest green actions, soft shadows, and native controls.
- Adds native screens for Main, Post Detail, Discover Notes, Note Detail, Notifications, My Library, User Search, Create Post, Create Note, Profile, Chat, Conversation, Wallet, Settings, and Studio.
- Uses native `URLSession`, `AsyncImage`, `VideoPlayer`, `NavigationStack`, and `TabView`.
- Adds a C++ Swift Package target, `MIRACoreCpp`, for native media planning, feed scoring, stable hashing, and native design profile data.
- Adds a Rust FFI crate scaffold at `rust/mira_core` for security-sensitive URL/text risk scoring and byte hashing.
- Includes native app-target starter files in `AppTarget/` for a standalone SwiftUI iOS app.
- Avoids new third-party dependencies.

What this does not do yet:
- It does not delete or replace the Expo app.
- It does not create the `.xcodeproj` automatically on Windows.
- It does not compile Rust into the iOS app until a Mac build script is added.
- It does not include Agora/Google/Apple native SDK installation in the Xcode target yet.

How to use on a Mac:
1. Open Xcode.
2. Create an iOS app target named `MIRA`.
3. Use `AppTarget/MIRAApp.swift`, `AppTarget/Info.plist`, `AppTarget/MIRA.entitlements`, and `Config/MIRAProduction.xcconfig` as the app-target starting files.
4. Add this Swift package folder: `ios_native/MIRA`.
5. Link both package products:
   - `MIRANative`
   - `MIRACoreCpp`
6. In the app's root view, render:

```swift
import SwiftUI
import MIRANative

@main
struct MIRAApp: App {
  var body: some Scene {
    WindowGroup {
      MIRANativeRootView()
    }
  }
}
```

Auth note:
`MIRAAPIClient` accepts a `MIRASessionProviding` object. The default root view now uses `MIRAKeychainSessionProvider`, so the native login flow should save the backend/Supabase access token with `saveAccessToken(_:)` after sign-in.

Migration order:
1. Main feed, post creation, post detail, comments, notifications.
2. Discover stories/notes, notes creation, notes detail, user search.
3. Profile, library, wallet, settings.
4. Chat, conversation, presence, typing, calls with native Agora SDK.
5. Studio camera/composer with `AVFoundation`, `PhotosUI`, and native media export.
6. Rust static library integration for trust/safety/offline logic.

The current Expo app remains the production fallback while these SwiftUI screens are hardened.

Native core split:
- SwiftUI: all user-facing UI, navigation, sheets, camera/editor UI, auth screens.
- C++: fast feed/media/ranking/helpers that benefit from deterministic native execution.
- Rust: security-sensitive scoring, safe link checks, text risk scoring, offline-safe data transforms.

Full native build note:
The direct-install Expo EAS build can ship native modules now. The full SwiftUI iOS app requires opening this package on a Mac, creating the Xcode app target, linking Apple/Google/Agora SDKs, and building with Apple signing.
