# C++ Offline Engine (JSI)

Native-ready ordering logic for the offline feed/cache queue.

## What it does

- Dedupes cached posts by ID
- Prioritizes saved posts, followed creators, media posts, engagement, and recency
- Returns ordered post IDs so the JS layer can preserve original post objects

## Integration

1. Add `OfflineEngineCore.cpp` and `OfflineEngineJSI.cpp` to the native iOS/Android targets.
2. Call `flames::InstallOfflineEngine(runtime)` during JS runtime setup.
3. The app uses `global.__FlamesOfflineEngine` when present and falls back to `src/native/offlineEngine.ts`.
