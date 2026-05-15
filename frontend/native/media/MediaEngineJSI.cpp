#include "MediaEngineCore.h"

#include <jsi/jsi.h>

#include <string>
#include <utility>

namespace flames {

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

Value DetectKindHost(Runtime& runtime, const Value&, const Value* args, size_t count) {
  const std::string uri = count >= 1 && args[0].isString() ? args[0].asString(runtime).utf8(runtime) : "";
  const std::string mime = count >= 2 && args[1].isString() ? args[1].asString(runtime).utf8(runtime) : "";
  const std::string fileName = count >= 3 && args[2].isString() ? args[2].asString(runtime).utf8(runtime) : "";
  const MediaKind kind = MediaEngineCore::DetectMediaKind(uri, mime, fileName);
  return Value(String::createFromUtf8(runtime, MediaKindToString(kind)));
}

Value PlanMediaHost(Runtime& runtime, const Value&, const Value* args, size_t count) {
  if (count < 1 || !args[0].isObject()) {
    MediaProcessingPlan empty;
    return Value(String::createFromUtf8(runtime, MediaPlanToJson(empty)));
  }

  Object object = args[0].asObject(runtime);
  MediaPlanInput input;
  input.uri = ReadString(runtime, object, "uri");
  input.mimeType = ReadString(runtime, object, "mimeType");
  input.fileName = ReadString(runtime, object, "fileName");
  input.fileSize = ReadNumber(runtime, object, "fileSize");
  input.width = ReadNumber(runtime, object, "width");
  input.height = ReadNumber(runtime, object, "height");
  input.preset = ReadString(runtime, object, "preset");
  if (input.preset.empty()) input.preset = "balanced";

  return Value(String::createFromUtf8(runtime, MediaPlanToJson(MediaEngineCore::PlanMedia(input))));
}

}  // namespace

void InstallMediaEngine(Runtime& runtime) {
  Object engine(runtime);

  engine.setProperty(
      runtime,
      "detectMediaKind",
      Function::createFromHostFunction(
          runtime,
          PropNameID::forAscii(runtime, "detectMediaKind"),
          3,
          DetectKindHost));

  engine.setProperty(
      runtime,
      "planMedia",
      Function::createFromHostFunction(
          runtime,
          PropNameID::forAscii(runtime, "planMedia"),
          1,
          PlanMediaHost));

  runtime.global().setProperty(runtime, "__FlamesMediaEngine", std::move(engine));
}

}  // namespace flames
