#include "RecommendationEngineCore.h"

#include <jsi/jsi.h>

#include <algorithm>
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

double ReadNumber(Runtime& runtime, const Object& object, const char* key, double fallback = 0.0) {
  Value value = object.getProperty(runtime, key);
  if (value.isNumber()) return value.asNumber();
  if (value.isString()) {
    try {
      return std::stod(value.asString(runtime).utf8(runtime));
    } catch (...) {
      return fallback;
    }
  }
  return fallback;
}

bool HasNumber(Runtime& runtime, const Object& object, const char* key) {
  Value value = object.getProperty(runtime, key);
  if (value.isNumber()) return true;
  if (!value.isString()) return false;
  try {
    std::stod(value.asString(runtime).utf8(runtime));
    return true;
  } catch (...) {
    return false;
  }
}

std::vector<std::string> ReadStringArray(Runtime& runtime, const Object& object, const char* key) {
  std::vector<std::string> output;
  Value value = object.getProperty(runtime, key);
  if (!value.isObject()) return output;

  Object maybeArray = value.asObject(runtime);
  if (!maybeArray.isArray(runtime)) return output;

  Array array = maybeArray.asArray(runtime);
  const size_t count = array.size(runtime);
  output.reserve(count);

  for (size_t i = 0; i < count; ++i) {
    Value item = array.getValueAtIndex(runtime, i);
    if (item.isString()) output.push_back(item.asString(runtime).utf8(runtime));
    else if (item.isNumber()) output.push_back(std::to_string(item.asNumber()));
  }

  return output;
}

std::vector<FeedItem> ReadFeedItems(Runtime& runtime, const Value& value) {
  std::vector<FeedItem> output;
  if (!value.isObject()) return output;

  Object maybeArray = value.asObject(runtime);
  if (!maybeArray.isArray(runtime)) return output;

  Array array = maybeArray.asArray(runtime);
  const size_t count = array.size(runtime);
  output.reserve(count);

  for (size_t i = 0; i < count; ++i) {
    Value rawItem = array.getValueAtIndex(runtime, i);
    if (!rawItem.isObject()) continue;

    Object itemObject = rawItem.asObject(runtime);
    FeedItem item;
    item.id = ReadString(runtime, itemObject, "id");
    if (item.id.empty()) continue;

    item.authorId = ReadString(runtime, itemObject, "authorId");
    item.category = ReadString(runtime, itemObject, "category");
    item.location = ReadString(runtime, itemObject, "location");
    item.createdAtMs = ReadNumber(runtime, itemObject, "createdAtMs");
    item.likes = ReadNumber(runtime, itemObject, "likes");
    item.comments = ReadNumber(runtime, itemObject, "comments");
    item.shares = ReadNumber(runtime, itemObject, "shares");
    item.saves = ReadNumber(runtime, itemObject, "saves");
    item.impressions = ReadNumber(runtime, itemObject, "impressions");
    item.hasCoordinates = HasNumber(runtime, itemObject, "lat") && HasNumber(runtime, itemObject, "lng");
    item.lat = ReadNumber(runtime, itemObject, "lat");
    item.lng = ReadNumber(runtime, itemObject, "lng");
    output.push_back(item);
  }

  return output;
}

RankContext ReadRankContext(Runtime& runtime, const Value& value) {
  RankContext context;
  if (!value.isObject()) return context;

  Object object = value.asObject(runtime);
  context.nowMs = ReadNumber(runtime, object, "nowMs");
  context.hasUserCoordinates = HasNumber(runtime, object, "userLat") && HasNumber(runtime, object, "userLng");
  context.userLat = ReadNumber(runtime, object, "userLat");
  context.userLng = ReadNumber(runtime, object, "userLng");
  context.interests = ReadStringArray(runtime, object, "interests");
  return context;
}

RankOptions ReadRankOptions(Runtime& runtime, const Value& value, int itemCount) {
  RankOptions options;
  options.maxItems = std::max(0, itemCount);
  if (!value.isObject()) return options;

  Object object = value.asObject(runtime);
  options.maxItems = static_cast<int>(ReadNumber(runtime, object, "maxItems", options.maxItems));
  options.maxItems = std::max(0, std::min(options.maxItems, itemCount));
  options.lambda = ReadNumber(runtime, object, "lambda", options.lambda);
  options.halfLifeHours = ReadNumber(runtime, object, "halfLifeHours", options.halfLifeHours);
  return options;
}

Value RankedIdsToArray(Runtime& runtime, const std::vector<std::string>& ids) {
  Array output(runtime, ids.size());
  for (size_t i = 0; i < ids.size(); ++i) {
    output.setValueAtIndex(runtime, i, String::createFromUtf8(runtime, ids[i]));
  }
  return Value(std::move(output));
}

Value RankFeedItemsHost(Runtime& runtime, const Value&, const Value* args, size_t count) {
  if (count < 2) {
    Array empty(runtime, 0);
    return Value(std::move(empty));
  }

  std::vector<FeedItem> items = ReadFeedItems(runtime, args[0]);
  RankContext context = ReadRankContext(runtime, args[1]);
  RankOptions options = ReadRankOptions(runtime, count >= 3 ? args[2] : Value::undefined(), static_cast<int>(items.size()));
  std::vector<std::string> ids = RankFeed(items, context, options);
  return RankedIdsToArray(runtime, ids);
}

Value RankFeedJsonPlaceholder(Runtime& runtime, const Value&, const Value* args, size_t count) {
  if (count < 1 || !args[0].isString()) {
    return Value(String::createFromUtf8(runtime, "[]"));
  }

  // Kept for backwards compatibility with older JS. The app now prefers
  // rankFeedItems(items, context, options), which avoids a JSON parser dependency.
  return Value(String::createFromUtf8(runtime, "[]"));
}

}  // namespace

void InstallRecommendationEngine(Runtime& runtime) {
  Object engine(runtime);

  engine.setProperty(
      runtime,
      "rankFeedItems",
      Function::createFromHostFunction(
          runtime,
          PropNameID::forAscii(runtime, "rankFeedItems"),
          3,
          RankFeedItemsHost));

  engine.setProperty(
      runtime,
      "rankFeed",
      Function::createFromHostFunction(
          runtime,
          PropNameID::forAscii(runtime, "rankFeed"),
          1,
          RankFeedJsonPlaceholder));

  runtime.global().setProperty(runtime, "__FlamesRecommendationEngine", std::move(engine));
}

}  // namespace flames
