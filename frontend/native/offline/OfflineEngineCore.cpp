#include "OfflineEngineCore.h"

#include <algorithm>
#include <cmath>
#include <unordered_set>

namespace flames {

namespace {

double AgeHours(double createdAtMs, double nowMs) {
  return std::max(0.0, (nowMs - createdAtMs) / (1000.0 * 60.0 * 60.0));
}

double ScoreItem(const OfflineFeedItem& item, double nowMs) {
  const double engagement =
      item.likes * 3.0 +
      item.comments * 5.0 +
      item.saves * 5.0 +
      item.shares * 6.0 +
      std::log10(1.0 + std::max(0.0, item.views)) * 8.0;
  const double recency = std::pow(2.0, -AgeHours(item.createdAtMs > 0.0 ? item.createdAtMs : nowMs, nowMs) / 96.0) * 45.0;
  const double savedBoost = item.isSaved ? 85.0 : 0.0;
  const double followBoost = item.isFollowing ? 28.0 : 0.0;
  const double mediaBoost = item.hasMedia ? 12.0 : 0.0;
  return savedBoost + followBoost + mediaBoost + engagement + recency;
}

struct ScoredOfflineItem {
  OfflineFeedItem item;
  double score = 0.0;
};

}  // namespace

std::vector<std::string> OfflineEngineCore::BuildOfflineQueue(
    const std::vector<OfflineFeedItem>& items,
    const OfflineFeedOptions& options) {
  const int limit = std::max(1, std::min(options.limit, static_cast<int>(items.size())));
  std::unordered_set<std::string> seen;
  std::vector<ScoredOfflineItem> scored;
  scored.reserve(items.size());

  for (const auto& item : items) {
    if (item.id.empty() || seen.find(item.id) != seen.end()) continue;
    seen.insert(item.id);
    scored.push_back({item, ScoreItem(item, options.nowMs)});
  }

  std::sort(scored.begin(), scored.end(), [](const ScoredOfflineItem& a, const ScoredOfflineItem& b) {
    return a.score > b.score;
  });

  std::vector<std::string> ids;
  ids.reserve(limit);
  for (int i = 0; i < static_cast<int>(scored.size()) && i < limit; ++i) {
    ids.push_back(scored[i].item.id);
  }
  return ids;
}

}  // namespace flames
