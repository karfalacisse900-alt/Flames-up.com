#pragma once

#include <string>
#include <vector>

namespace flames {

struct OfflineFeedItem {
  std::string id;
  std::string authorId;
  double createdAtMs = 0.0;
  double likes = 0.0;
  double comments = 0.0;
  double saves = 0.0;
  double shares = 0.0;
  double views = 0.0;
  bool hasMedia = false;
  bool isSaved = false;
  bool isFollowing = false;
};

struct OfflineFeedOptions {
  double nowMs = 0.0;
  int limit = 200;
};

class OfflineEngineCore {
 public:
  static std::vector<std::string> BuildOfflineQueue(
      const std::vector<OfflineFeedItem>& items,
      const OfflineFeedOptions& options);
};

}  // namespace flames
