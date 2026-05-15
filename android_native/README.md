# Flames Android Native

Android-only prototype using Kotlin for the app UI, Rust for core logic, and C++ for low-level scoring helpers.

## Architecture

```text
Kotlin Activity/UI
  -> JNI bridge
    -> Rust native library
      -> C++ scoring helper compiled by Rust build.rs
```

## Requirements

Install these in Android Studio SDK Manager:

```text
Android SDK Platform
Android SDK Platform-Tools
Android SDK Build-Tools
NDK (Side by side)
CMake
```

Install Rust Android tools:

```powershell
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cargo install cargo-ndk
```

## Open In Android Studio

```powershell
Start-Process "C:\Program Files\Android\Android Studio\bin\studio64.exe" "C:\Users\The-s\Documents\New project\Flames-up.com\android_native"
```

## Build From PowerShell

```powershell
cd "C:\Users\The-s\Documents\New project\Flames-up.com\android_native"
.\scripts\build-debug-apk.ps1
```

Output:

```text
android_native\app\build\outputs\apk\debug\app-debug.apk
```
