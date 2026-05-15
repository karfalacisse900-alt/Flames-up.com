# C++ Recommendation Engine (JSI)

This folder contains a high-performance ranking core and a JSI install scaffold.

## Files

- `RecommendationEngineCore.h/.cpp`:
  Core ranking algorithm with:
  - Wilson lower-bound quality score
  - Time-decay recency
  - Interest affinity
  - Geo proximity boost
  - MMR diversity reranking

- `RecommendationEngineJSI.cpp`:
  JSI bridge that exposes:
  - `global.__FlamesRecommendationEngine.rankFeedItems(items, context, options)`
  - `global.__FlamesRecommendationEngine.rankFeed(payloadJson)` for backwards compatibility

## Integration Steps

1. Add these sources to your iOS/Android native targets.
2. Call `flames::InstallRecommendationEngine(runtime)` during JS runtime initialization.
3. Keep the JS fallback in `src/recommendation/` for Expo Go, web, and any build where the native engine is not installed.
