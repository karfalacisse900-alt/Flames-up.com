#include "GeoSearchCore.h"

#include <jsi/jsi.h>

#include <string>
#include <utility>
#include <vector>

namespace flames {

using facebook::jsi::Array;
using facebook::jsi::Function;
using facebook::jsi::Object;
using facebook::jsi::PropNameID;
using facebook::jsi::Runtime;
using facebook::jsi::String;
using facebook::jsi::Value;

namespace {

std::string ReadString(Runtime& runtime, const Object& object, const char* key) {
  Value value = object.getProperty(runtime, key);
  if (value.isString()) return value.asString(runtime).utf8(runtime);
  if (value.isNumber()) return std::to_string(value.asNumber());
  return "";
}

double ReadNumber(Runtime& runtime, const Object& object, const char* key) {
  Value value = object.getProperty(runtime, key);
  if (value.isNumber()) return value.asNumber();
  if (value.isString()) {
    try {
      return std::stod(value.asString(runtime).utf8(runtime));
    } catch (...) {
      return 0.0;
    }
  }
  return 0.0;
}

std::vector<std::string> ReadTypes(Runtime& runtime, const Object& object) {
  std::vector<std::string> types;
  Value value = object.getProperty(runtime, "types");
  if (!value.isObject()) return types;
  Object maybeArray = value.asObject(runtime);
  if (!maybeArray.isArray(runtime)) return types;
  Array array = maybeArray.asArray(runtime);
  const size_t count = array.size(runtime);
  types.reserve(count);
  for (size_t i = 0; i < count; ++i) {
    Value item = array.getValueAtIndex(runtime, i);
    if (item.isString()) types.push_back(item.asString(runtime).utf8(runtime));
  }
  return types;
}

std::vector<PlacePoint> ReadPlaces(Runtime& runtime, const Value& value) {
  std::vector<PlacePoint> places;
  if (!value.isObject()) return places;
  Object maybeArray = value.asObject(runtime);
  if (!maybeArray.isArray(runtime)) return places;

  Array array = maybeArray.asArray(runtime);
  const size_t count = array.size(runtime);
  places.reserve(count);
  for (size_t i = 0; i < count; ++i) {
    Value raw = array.getValueAtIndex(runtime, i);
    if (!raw.isObject()) continue;

    Object object = raw.asObject(runtime);
    PlacePoint place;
    place.id = ReadString(runtime, object, "place_id");
    if (place.id.empty()) place.id = ReadString(runtime, object, "id");
    if (place.id.empty()) place.id = "place-" + std::to_string(i);
    place.name = ReadString(runtime, object, "name");
    place.vicinity = ReadString(runtime, object, "vicinity");
    place.lat = ReadNumber(runtime, object, "lat");
    place.lng = ReadNumber(runtime, object, "lng");
    place.rating = ReadNumber(runtime, object, "rating");
    place.ratingsTotal = static_cast<int>(ReadNumber(runtime, object, "user_ratings_total"));
    place.types = ReadTypes(runtime, object);
    places.push_back(place);
  }

  return places;
}

Value IdsToArray(Runtime& runtime, const std::vector<PlacePoint>& places) {
  Array output(runtime, places.size());
  for (size_t i = 0; i < places.size(); ++i) {
    output.setValueAtIndex(runtime, i, String::createFromUtf8(runtime, places[i].id));
  }
  return Value(std::move(output));
}

Value RankPlaceIdsHost(Runtime& runtime, const Value&, const Value* args, size_t count) {
  if (count < 2) {
    Array empty(runtime, 0);
    return Value(std::move(empty));
  }
  const std::vector<PlacePoint> places = ReadPlaces(runtime, args[0]);
  const std::string query = args[1].isString() ? args[1].asString(runtime).utf8(runtime) : "";
  const double userLat = count >= 3 && args[2].isNumber() ? args[2].asNumber() : 0.0;
  const double userLng = count >= 4 && args[3].isNumber() ? args[3].asNumber() : 0.0;
  const int limit = count >= 5 && args[4].isNumber() ? static_cast<int>(args[4].asNumber()) : 120;
  return IdsToArray(runtime, GeoSearchCore::RankQuery(places, query, userLat, userLng, limit));
}

}  // namespace

void InstallGeoSearch(Runtime& runtime) {
  Object engine(runtime);

  engine.setProperty(
      runtime,
      "rankPlaceIds",
      Function::createFromHostFunction(
          runtime,
          PropNameID::forAscii(runtime, "rankPlaceIds"),
          5,
          RankPlaceIdsHost));

  runtime.global().setProperty(runtime, "__FlamesGeoSearch", std::move(engine));
}

}  // namespace flames
