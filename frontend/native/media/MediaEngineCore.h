#pragma once

#include <string>

namespace flames {

enum class MediaKind {
  Image,
  Video,
  Unknown,
};

struct MediaPlanInput {
  std::string uri;
  std::string mimeType;
  std::string fileName;
  double fileSize = 0.0;
  double width = 0.0;
  double height = 0.0;
  std::string preset = "balanced";
};

struct MediaProcessingPlan {
  MediaKind kind = MediaKind::Unknown;
  bool allowed = false;
  std::string reason = "unknown_media_type";
  int targetWidth = 0;
  int targetHeight = 0;
  double aspectRatio = 0.75;
  int maxBytes = 0;
  std::string targetMimeType = "image/jpeg";
  double imageQuality = 0.89;
  int videoBitrate = 8000000;
  int targetFps = 30;
  bool shouldUseThumbnail = false;
  std::string cacheKey;
};

class MediaEngineCore {
 public:
  static MediaKind DetectMediaKind(
      const std::string& uri,
      const std::string& mimeType,
      const std::string& fileName);

  static MediaProcessingPlan PlanMedia(const MediaPlanInput& input);
};

std::string MediaKindToString(MediaKind kind);
std::string MediaPlanToJson(const MediaProcessingPlan& plan);

}  // namespace flames
