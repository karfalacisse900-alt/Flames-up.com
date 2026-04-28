#include "RecommendationEngineCore.h"

#include <jsi/jsi.h>

// This file is a JSI install scaffold.
// Hook this into your app startup (native iOS/Android) and replace payload parsing
// with your preferred JSON parser or binary bridge.
namespace flames {

using namespace facebook;

void InstallRecommendationEngine(jsi::Runtime& runtime) {
  auto rankFeedFn = jsi::Function::createFromHostFunction(
    runtime,
    jsi::PropNameID::forAscii(runtime, "rankFeed"),
    1,
    [](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t count) -> jsi::Value {
      if (count < 1 || !args[0].isString()) {
        return jsi::String::createFromAscii(rt, "[]");
      }

      // TODO: Parse payload JSON into FeedItem[] + RankContext + RankOptions.
      // For now, this scaffold returns an empty list until native parsing is wired.
      return jsi::String::createFromAscii(rt, "[]");
    }
  );

  jsi::Object engine(rt);
  engine.setProperty(rt, "rankFeed", std::move(rankFeedFn));
  runtime.global().setProperty(rt, "__FlamesRecommendationEngine", std::move(engine));
}

}  // namespace flames
