# Flames Mobile Flutter Prototype

This is a separate Flutter prototype for the Flames app. The current Expo app stays untouched while this proves the Flutter + Rust + C++ architecture.

## Structure

```text
lib/                    Flutter UI
lib/src/native_core/    Dart service layer for native core calls
lib/src/rust/           flutter_rust_bridge generated Dart bindings
native/                 Rust crate compiled as cdylib/staticlib
native/cpp/             C++ logic compiled by native/build.rs
```

## Local Web Preview

Web preview uses a Dart mirror of the native ranking service so the UI can run in Chrome or Edge before mobile native libraries are bundled.

```powershell
cd "C:\Users\The-s\Documents\New project\Flames-up.com\mobile_flutter"
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 5050
```

Open:

```text
http://127.0.0.1:5050
```

## Regenerate Rust Bridge

The path `New project` can trigger a Windows path bug in `flutter_rust_bridge_codegen`. If direct generation fails, copy to a no-space temp path, generate there, then copy `lib/src/rust` and `native/src/frb_generated.rs` back.

```powershell
flutter_rust_bridge_codegen generate
```

## Android Native Build Plan

```powershell
cargo install cargo-ndk
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cargo ndk -t arm64-v8a -o android/app/src/main/jniLibs build --release
flutter build apk
```

## iOS Native Build Plan

iOS builds require macOS/Xcode.

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
flutter build ios
```
