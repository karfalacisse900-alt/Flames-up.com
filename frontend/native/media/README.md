# C++ Media Engine (JSI)

Native-ready media planning helpers for upload and feed performance.

## What it does

- Detects image vs video from URI, MIME type, and filename
- Blocks unsafe file families such as executables and raw SVG uploads
- Creates a production media plan with target dimensions, max byte limits, target MIME type, JPEG quality, 1080p video bitrate, thumbnail needs, and cache key

## Why this is native-ready

Media detection and planning can run many times while users scroll, upload, or edit posts. Keeping the logic isolated lets the app use the TypeScript fallback in Expo Go, then switch to compiled C++ in development and production builds.

## Integration

1. Add `MediaEngineCore.cpp` and `MediaEngineJSI.cpp` to the native iOS/Android targets.
2. Call `flames::InstallMediaEngine(runtime)` during JS runtime setup.
3. The app uses `global.__FlamesMediaEngine` when present and falls back to `src/native/mediaEngine.ts`.

## Production preset

- Images: preserve high quality and plan up to 3000 px on the long edge for creator uploads.
- Videos: plan 1080p H.264 delivery with an 8-12 Mbps target bitrate depending on the selected preset.
- Large videos skip Worker backup upload and use Cloudflare Stream direct upload to avoid slow failed uploads.
