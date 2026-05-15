#include "MediaEngineCore.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <set>
#include <sstream>

namespace flames {

namespace {

std::string Lower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return value;
}

bool StartsWith(const std::string& value, const std::string& prefix) {
  return value.rfind(prefix, 0) == 0;
}

std::string ExtensionFrom(const std::string& value) {
  const std::string clean = Lower(value.substr(0, value.find_first_of("?#")));
  const size_t dot = clean.find_last_of('.');
  if (dot == std::string::npos || dot + 1 >= clean.size()) return "";
  const std::string ext = clean.substr(dot + 1);
  if (ext.size() > 8) return "";
  return ext;
}

double ClampRatio(double ratio) {
  if (!std::isfinite(ratio) || ratio <= 0.0) return 0.75;
  return std::max(9.0 / 16.0, std::min(1.91, ratio));
}

int ClampDimension(double value, int fallback) {
  if (!std::isfinite(value) || value <= 0.0) return fallback;
  return std::max(1, static_cast<int>(std::round(value)));
}

std::string ShortHash(const std::string& value) {
  uint32_t hash = 2166136261u;
  for (const unsigned char c : value) {
    hash ^= c;
    hash *= 16777619u;
  }
  std::ostringstream out;
  out << std::hex << std::setfill('0') << std::setw(8) << hash;
  return out.str();
}

std::string JsonEscape(const std::string& value) {
  std::ostringstream out;
  for (const char c : value) {
    if (c == '"' || c == '\\') out << '\\' << c;
    else out << c;
  }
  return out.str();
}

}  // namespace

MediaKind MediaEngineCore::DetectMediaKind(
    const std::string& uri,
    const std::string& mimeType,
    const std::string& fileName) {
  const std::string lowerUri = Lower(uri);
  const std::string lowerMime = Lower(mimeType);
  const std::string ext = !ExtensionFrom(fileName).empty() ? ExtensionFrom(fileName) : ExtensionFrom(uri);

  static const std::set<std::string> imageExt = {"jpg", "jpeg", "png", "webp", "heic", "heif"};
  static const std::set<std::string> videoExt = {"mp4", "mov", "m4v", "webm"};

  if (StartsWith(lowerUri, "cfstream:") || StartsWith(lowerMime, "video/") ||
      StartsWith(lowerUri, "data:video/") || videoExt.find(ext) != videoExt.end()) {
    return MediaKind::Video;
  }

  if (StartsWith(lowerMime, "image/") || StartsWith(lowerUri, "data:image/") ||
      imageExt.find(ext) != imageExt.end()) {
    return MediaKind::Image;
  }

  return MediaKind::Unknown;
}

MediaProcessingPlan MediaEngineCore::PlanMedia(const MediaPlanInput& input) {
  MediaProcessingPlan plan;
  plan.kind = DetectMediaKind(input.uri, input.mimeType, input.fileName);
  plan.allowed = plan.kind != MediaKind::Unknown;
  plan.reason = plan.allowed ? "ok" : "unknown_media_type";
  plan.shouldUseThumbnail = plan.kind == MediaKind::Video;

  const std::string ext = !ExtensionFrom(input.fileName).empty() ? ExtensionFrom(input.fileName) : ExtensionFrom(input.uri);
  static const std::set<std::string> unsafeExt = {
      "apk", "app", "bat", "cmd", "com", "dll", "dmg", "exe", "js", "msi", "ps1", "sh", "svg"};

  const std::string mime = Lower(input.mimeType);
  if (unsafeExt.find(ext) != unsafeExt.end() || mime.find("svg") != std::string::npos) {
    plan.allowed = false;
    plan.reason = "blocked_unsafe_file_type";
  }

  plan.maxBytes = plan.kind == MediaKind::Video ? 500 * 1024 * 1024 : 20 * 1024 * 1024;
  if (input.fileSize > plan.maxBytes) {
    plan.allowed = false;
    plan.reason = "file_too_large";
  }

  const int fallbackWidth = plan.kind == MediaKind::Video ? 1080 : 1440;
  const int fallbackHeight = plan.kind == MediaKind::Video ? 1920 : 1920;
  const int width = ClampDimension(input.width, fallbackWidth);
  const int height = ClampDimension(input.height, fallbackHeight);
  plan.aspectRatio = ClampRatio(static_cast<double>(width) / static_cast<double>(height));

  const int maxLongEdge = plan.kind == MediaKind::Video
      ? 1920
      : input.preset == "quality"
          ? 3000
          : input.preset == "compact"
              ? 1280
              : 2200;
  const double scale = std::min(1.0, static_cast<double>(maxLongEdge) / static_cast<double>(std::max(width, height)));
  plan.targetWidth = std::max(1, static_cast<int>(std::round(width * scale)));
  plan.targetHeight = std::max(1, static_cast<int>(std::round(height * scale)));
  plan.targetMimeType = plan.kind == MediaKind::Video ? "video/mp4" : "image/jpeg";
  plan.imageQuality = input.preset == "compact" ? 0.84 : input.preset == "quality" ? 0.92 : 0.89;
  plan.videoBitrate = input.preset == "compact" ? 5500000 : input.preset == "quality" ? 12000000 : 8000000;
  plan.targetFps = 30;
  plan.cacheKey = MediaKindToString(plan.kind) + ":" +
      ShortHash(input.uri + "|" + input.fileName + "|" + std::to_string(width) + "x" +
                std::to_string(height) + "|" + std::to_string(static_cast<long long>(input.fileSize)));

  return plan;
}

std::string MediaKindToString(MediaKind kind) {
  if (kind == MediaKind::Image) return "image";
  if (kind == MediaKind::Video) return "video";
  return "unknown";
}

std::string MediaPlanToJson(const MediaProcessingPlan& plan) {
  std::ostringstream out;
  out << "{\"kind\":\"" << MediaKindToString(plan.kind)
      << "\",\"allowed\":" << (plan.allowed ? "true" : "false")
      << ",\"reason\":\"" << JsonEscape(plan.reason)
      << "\",\"targetWidth\":" << plan.targetWidth
      << ",\"targetHeight\":" << plan.targetHeight
      << ",\"aspectRatio\":" << plan.aspectRatio
      << ",\"maxBytes\":" << plan.maxBytes
      << ",\"targetMimeType\":\"" << JsonEscape(plan.targetMimeType)
      << "\",\"imageQuality\":" << plan.imageQuality
      << ",\"videoBitrate\":" << plan.videoBitrate
      << ",\"targetFps\":" << plan.targetFps
      << ",\"shouldUseThumbnail\":" << (plan.shouldUseThumbnail ? "true" : "false")
      << ",\"cacheKey\":\"" << JsonEscape(plan.cacheKey) << "\"}";
  return out.str();
}

}  // namespace flames
