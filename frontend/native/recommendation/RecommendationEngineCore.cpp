#include "RecommendationEngineCore.h"

#include <algorithm>
#include <cmath>
#include <unordered_set>

namespace flames {

namespace {

constexpr double kZ80 = 1.281551565545;

double Clamp01(double v) {
  if (v < 0.0) return 0.0;
  if (v > 1.0) return 1.0;
  return v;
}

double WilsonLowerBound(double positive, double total) {
  if (total <= 0.0) return 0.0;
  const double pHat = positive / total;
  const double z2 = kZ80 * kZ80;
  const double denom = 1.0 + z2 / total;
  const double center = pHat + z2 / (2.0 * total);
  const double margin = kZ80 * std::sqrt((pHat * (1.0 - pHat) + z2 / (4.0 * total)) / total);
  return Clamp01((center - margin) / denom);
}

double HoursSince(double createdAtMs, double nowMs) {
  return std::max(0.0, (nowMs - createdAtMs) / (1000.0 * 60.0 * 60.0));
}

double RecencyDecay(double ageHours, double halfLifeHours) {
  const double safeHalfLife = std::max(1.0, halfLifeHours);
  return std::pow(2.0, -ageHours / safeHalfLife);
}

double ToRad(double v) {
  return v * M_PI / 180.0;
}

double HaversineKm(double lat1, double lng1, double lat2, double lng2) {
  const double dLat = ToRad(lat2 - lat1);
  const double dLng = ToRad(lng2 - lng1);
  const double a = std::sin(dLat / 2.0) * std::sin(dLat / 2.0) +
    std::cos(ToRad(lat1)) * std::cos(ToRad(lat2)) *
    std::sin(dLng / 2.0) * std::sin(dLng / 2.0);
  return 6371.0 * (2.0 * std::atan2(std::sqrt(a), std::sqrt(1.0 - a)));
}

double ProximityScore(const FeedItem& item, const RankContext& ctx) {
  if (!ctx.hasUserCoordinates || !item.hasCoordinates) return 0.45;
  const double dKm = HaversineKm(ctx.userLat, ctx.userLng, item.lat, item.lng);
  return Clamp01(std::exp(-dKm / 20.0));
}

bool ContainsToken(const std::string& haystack, const std::string& token) {
  return haystack.find(token) != std::string::npos;
}

double AffinityScore(const FeedItem& item, const RankContext& ctx) {
  if (ctx.interests.empty()) return 0.35;
  std::string corpus = item.category + " " + item.location;
  std::transform(corpus.begin(), corpus.end(), corpus.begin(), ::tolower);

  int hits = 0;
  for (const auto& rawInterest : ctx.interests) {
    std::string interest = rawInterest;
    std::transform(interest.begin(), interest.end(), interest.begin(), ::tolower);
    if (!interest.empty() && ContainsToken(corpus, interest)) {
      hits += 1;
    }
  }
  const double ratio = static_cast<double>(hits) / std::max<size_t>(1, ctx.interests.size());
  return Clamp01(0.2 + ratio * 0.8);
}

double Similarity(const FeedItem& a, const FeedItem& b) {
  double score = 0.05;
  if (!a.authorId.empty() && !b.authorId.empty() && a.authorId == b.authorId) score += 0.65;
  if (!a.category.empty() && !b.category.empty() && a.category == b.category) score += 0.2;
  if (!a.location.empty() && !b.location.empty() &&
      (ContainsToken(a.location, b.location) || ContainsToken(b.location, a.location))) {
    score += 0.12;
  }
  return Clamp01(score);
}

struct ScoredItem {
  FeedItem item;
  double baseScore = 0.0;
};

ScoredItem ScoreItem(const FeedItem& item, const RankContext& ctx, const RankOptions& options) {
  const double interactions = item.likes + item.comments * 2.0 + item.shares * 3.0 + item.saves * 2.0;
  const double views = std::max(item.impressions, interactions + 20.0);
  const double quality = WilsonLowerBound(std::min(interactions, views), views);
  const double recency = RecencyDecay(HoursSince(item.createdAtMs, ctx.nowMs), options.halfLifeHours);
  const double affinity = AffinityScore(item, ctx);
  const double proximity = ProximityScore(item, ctx);

  // Weighted ranking blend tuned for engagement + freshness + personalization.
  const double base =
    quality * 0.42 +
    recency * 0.28 +
    affinity * 0.20 +
    proximity * 0.10;

  return {item, base};
}

}  // namespace

std::vector<std::string> RankFeed(
  const std::vector<FeedItem>& items,
  const RankContext& context,
  const RankOptions& options
) {
  if (items.size() <= 1) {
    std::vector<std::string> ids;
    ids.reserve(items.size());
    for (const auto& item : items) ids.push_back(item.id);
    return ids;
  }

  std::vector<ScoredItem> candidates;
  candidates.reserve(items.size());
  for (const auto& item : items) {
    candidates.push_back(ScoreItem(item, context, options));
  }

  std::vector<ScoredItem> selected;
  selected.reserve(std::min<int>(options.maxItems, static_cast<int>(candidates.size())));

  while (!candidates.empty() && static_cast<int>(selected.size()) < options.maxItems) {
    size_t bestIdx = 0;
    double bestValue = -1e9;

    for (size_t i = 0; i < candidates.size(); ++i) {
      const auto& candidate = candidates[i];
      double maxSim = 0.0;
      for (const auto& s : selected) {
        maxSim = std::max(maxSim, Similarity(candidate.item, s.item));
      }
      const double mmr = options.lambda * candidate.baseScore - (1.0 - options.lambda) * maxSim;
      if (mmr > bestValue) {
        bestValue = mmr;
        bestIdx = i;
      }
    }

    selected.push_back(candidates[bestIdx]);
    candidates.erase(candidates.begin() + static_cast<long long>(bestIdx));
  }

  std::vector<std::string> rankedIds;
  rankedIds.reserve(selected.size());
  for (const auto& s : selected) rankedIds.push_back(s.item.id);
  return rankedIds;
}

}  // namespace flames
