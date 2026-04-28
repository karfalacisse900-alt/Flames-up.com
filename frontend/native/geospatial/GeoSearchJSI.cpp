#include "GeoSearchCore.h"

#include <jsi/jsi.h>

namespace flames {

using facebook::jsi::Function;
using facebook::jsi::PropNameID;
using facebook::jsi::Runtime;
using facebook::jsi::String;
using facebook::jsi::Value;

namespace {

Value rankGeoPlaceholder(Runtime& runtime, const Value&, const Value* args, size_t count) {
  if (count < 1 || !args[0].isString()) {
    return Value(String::createFromUtf8(runtime, "[]"));
  }

  // TODO:
  // Parse JSON payload from args[0], call GeoSearchCore::RankQuery and serialize back.
  // Payload shape suggestion:
  // { places: PlacePoint[], query: string, userLat: number, userLng: number, limit: number }
  return Value(String::createFromUtf8(runtime, "[]"));
}

Value clusterGeoPlaceholder(Runtime& runtime, const Value&, const Value* args, size_t count) {
  if (count < 1 || !args[0].isString()) {
    return Value(String::createFromUtf8(runtime, "[]"));
  }

  // TODO:
  // Parse JSON payload from args[0], call GeoSearchCore::ClusterByGrid and serialize back.
  // Payload shape suggestion:
  // { places: PlacePoint[], zoomLevel: number, baseRadiusMeters?: number }
  return Value(String::createFromUtf8(runtime, "[]"));
}

}  // namespace

void InstallGeoSearch(Runtime& runtime) {
  auto global = runtime.global();
  auto moduleObject = facebook::jsi::Object(runtime);

  moduleObject.setProperty(
      runtime,
      "rankPlaces",
      Function::createFromHostFunction(
          runtime,
          PropNameID::forAscii(runtime, "rankPlaces"),
          1,
          rankGeoPlaceholder));

  moduleObject.setProperty(
      runtime,
      "clusterPlaces",
      Function::createFromHostFunction(
          runtime,
          PropNameID::forAscii(runtime, "clusterPlaces"),
          1,
          clusterGeoPlaceholder));

  global.setProperty(runtime, "__FlamesGeoSearch", std::move(moduleObject));
}

}  // namespace flames

