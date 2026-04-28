# C++ Geospatial Engine (JSI)

This folder contains a native high-performance geospatial core and a JSI install scaffold.

## Files

- `GeoSearchCore.h/.cpp`
  - Fast query ranking by text match + proximity + quality score
  - Grid-based clustering tuned by zoom level
  - Haversine distance helper

- `GeoSearchJSI.cpp`
  - JSI scaffold exposing:
    - `global.__FlamesGeoSearch.rankPlaces(payloadJson)`
    - `global.__FlamesGeoSearch.clusterPlaces(payloadJson)`

## Integration Steps

1. Add these files to your iOS/Android native targets.
2. Call `flames::InstallGeoSearch(runtime)` during JS runtime initialization.
3. Implement JSON payload parse/serialize in `GeoSearchJSI.cpp`.
4. Keep `src/utils/geoSpatial.ts` as fallback for Expo Go and web.

