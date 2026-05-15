# Flames Native Engines

This folder keeps heavy client-side logic behind native-ready C++ cores with TypeScript fallbacks.

## Engines

- `recommendation`: feed ranking, recency, quality, affinity, diversity
- `geospatial`: place search ranking and map clustering
- `media`: image/video detection and upload/display planning
- `security`: local abuse-signal normalization, link safety checks, fast fingerprints
- `offline`: cached feed ordering for offline-first behavior

## Expo Go limitation

Expo Go cannot load custom C++/Rust native modules. The app keeps working there through the TypeScript fallbacks in `src/recommendation`, `src/utils/geoSpatial.ts`, and `src/native`.

To actually execute the C++ engines on device, use a development build and wire each `Install*Engine(runtime)` function into the iOS/Android runtime setup.

## No new dependencies

These modules do not add packages. The JSI bridges read JavaScript objects directly instead of adding a JSON parser dependency.

## Why C++ first

This Expo/React Native app can call C++ directly through JSI once it is in a development or production build. Rust is still possible later, but it needs an extra native toolchain bridge. C++ gives the app the native speed path now without adding another dependency layer.
