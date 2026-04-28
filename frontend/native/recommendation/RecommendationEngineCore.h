#pragma once

#include <string>
#include <vector>

namespace flames {

struct FeedItem {
  std::string id;
  std::string authorId;
  std::string category;
  std::string location;
  double createdAtMs = 0.0;
  double likes = 0.0;
  double comments = 0.0;
  double shares = 0.0;
  double saves = 0.0;
  double impressions = 0.0;
  double lat = 0.0;
  double lng = 0.0;
  bool hasCoordinates = false;
};

struct RankContext {
  double nowMs = 0.0;
  double userLat = 0.0;
  double userLng = 0.0;
  bool hasUserCoordinates = false;
  std::vector<std::string> interests;
};

struct RankOptions {
  int maxItems = 200;
  double lambda = 0.8;
  double halfLifeHours = 36.0;
};

std::vector<std::string> RankFeed(
  const std::vector<FeedItem>& items,
  const RankContext& context,
  const RankOptions& options
);

}  // namespace flames
