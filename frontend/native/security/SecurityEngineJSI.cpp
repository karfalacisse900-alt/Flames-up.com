#include "SecurityEngineCore.h"

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

std::string ReadString(Runtime& runtime, const Value* args, size_t count) {
  if (count < 1 || !args[0].isString()) return "";
  return args[0].asString(runtime).utf8(runtime);
}

Value NormalizeHost(Runtime& runtime, const Value&, const Value* args, size_t count) {
  return Value(String::createFromUtf8(runtime, SecurityEngineCore::NormalizeTextSignal(ReadString(runtime, args, count))));
}

Value FingerprintHost(Runtime& runtime, const Value&, const Value* args, size_t count) {
  return Value(String::createFromUtf8(runtime, SecurityEngineCore::FingerprintSignal(ReadString(runtime, args, count))));
}

Value AssessUrlHost(Runtime& runtime, const Value&, const Value* args, size_t count) {
  const UrlAssessment assessment = SecurityEngineCore::AssessUrl(ReadString(runtime, args, count));
  return Value(String::createFromUtf8(runtime, UrlAssessmentToJson(assessment)));
}

}  // namespace

void InstallSecurityEngine(Runtime& runtime) {
  Object engine(runtime);

  engine.setProperty(
      runtime,
      "normalizeTextSignal",
      Function::createFromHostFunction(
          runtime,
          PropNameID::forAscii(runtime, "normalizeTextSignal"),
          1,
          NormalizeHost));

  engine.setProperty(
      runtime,
      "fingerprintSignal",
      Function::createFromHostFunction(
          runtime,
          PropNameID::forAscii(runtime, "fingerprintSignal"),
          1,
          FingerprintHost));

  engine.setProperty(
      runtime,
      "assessUrl",
      Function::createFromHostFunction(
          runtime,
          PropNameID::forAscii(runtime, "assessUrl"),
          1,
          AssessUrlHost));

  runtime.global().setProperty(runtime, "__FlamesSecurityEngine", std::move(engine));
}

}  // namespace flames
