#include "OfflineEngineCore.h"

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

bool ReadBool(Runtime& runtime, const Object& object, const char* key) {
  Value value = object.getProperty(runtime, key);
  return value.isBool() ? value.getBool() : false;
}

std::vector<OfflineFeedItem> ReadItems(Runtime& runtime, const Value& value) {
  std::vector<OfflineFeedItem> items;
  if (!value.isObject()) return items;
  Object maybeArray = value.asObject(runtime);
  if (!maybeArray.isArray(runtime)) return items;

  Array array = maybeArray.asArray(runtime);
  const size_t count = array.size(runtime);
  items.reserve(count);
  for (size_t i = 0; i < count; ++i) {
    Value rawItem = array.getValueAtIndex(runtime, i);
    if (!rawItem.isObject()) continue;

    Object object = rawItem.asObject(runtime);
    OfflineFeedItem item;
    item.id = ReadString(runtime, object, "id");
    if (item.id.empty()) continue;
    item.authorId = ReadString(runtime, object, "authorId");
    item.createdAtMs = ReadNumber(runtime, object, "createdAtMs");
    item.likes = ReadNumber(runtime, object, "likes");
    item.comments = ReadNumber(runtime, object, "comments");
    item.saves = ReadNumber(runtime, object, "saves");
    item.shares = ReadNumber(runtime, object, "shares");
    item.views = ReadNumber(runtime, object, "views");
    item.hasMedia = ReadBool(runtime, object, "hasMedia");
    item.isSaved = ReadBool(runtime, object, "isSaved");
    item.isFollowing = ReadBool(runtime, object, "isFollowing");
    items.push_back(item);
  }

  return items;
}

OfflineFeedOptions ReadOptions(Runtime& runtime, const Value& value, int itemCount) {
  OfflineFeedOptions options;
  options.limit = itemCount;
  if (!value.isObject()) return options;
  Object object = value.asObject(runtime);
  options.nowMs = ReadNumber(runtime, object, "nowMs");
  options.limit = static_cast<int>(ReadNumber(runtime, object, "limit"));
  if (options.limit <= 0) options.limit = itemCount;
  return options;
}

Value IdsToArray(Runtime& runtime, const std::vector<std::string>& ids) {
  Array output(runtime, ids.size());
  for (size_t i = 0; i < ids.size(); ++i) {
    output.setValueAtIndex(runtime, i, String::createFromUtf8(runtime, ids[i]));
  }
  return Value(std::move(output));
}

Value BuildOfflineQueueHost(Runtime& runtime, const Value&, const Value* args, size_t count) {
  if (count < 1) {
    Array empty(runtime, 0);
    return Value(std::move(empty));
  }

  std::vector<OfflineFeedItem> items = ReadItems(runtime, args[0]);
  OfflineFeedOptions options = ReadOptions(runtime, count >= 2 ? args[1] : Value::undefined(), static_cast<int>(items.size()));
  return IdsToArray(runtime, OfflineEngineCore::BuildOfflineQueue(items, options));
}

}  // namespace

void InstallOfflineEngine(Runtime& runtime) {
  Object engine(runtime);
  engine.setProperty(
      runtime,
      "buildOfflineQueue",
      Function::createFromHostFunction(
          runtime,
          PropNameID::forAscii(runtime, "buildOfflineQueue"),
          2,
          BuildOfflineQueueHost));

  runtime.global().setProperty(runtime, "__FlamesOfflineEngine", std::move(engine));
}

}  // namespace flames
