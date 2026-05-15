# C++ Security Engine (JSI)

Native-ready helpers for security-sensitive client work that benefits from fast, deterministic processing.

## What belongs here

- Local abuse-signal normalization for repeated profile text, links, and names
- Fast non-cryptographic fingerprints for local grouping and dedupe
- External-link risk checks before opening user-submitted URLs

## Important security note

`FingerprintSignal` is not a password hash and is not a replacement for backend security. The backend still owns auth, permissions, rate limits, reports, and moderation. This module only makes local checks faster and more consistent.

## Integration

1. Add `SecurityEngineCore.cpp` and `SecurityEngineJSI.cpp` to the native iOS/Android targets.
2. Call `flames::InstallSecurityEngine(runtime)` during JS runtime setup.
3. The app automatically uses `global.__FlamesSecurityEngine` when present and falls back to `src/native/securityEngine.ts` in Expo Go and web.
