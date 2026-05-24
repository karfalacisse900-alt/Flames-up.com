#include "MIRACoreCpp.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <set>
#include <sstream>
#include <string>

namespace {

std::string Safe(const char* value) {
  return value == nullptr ? "" : std::string(value);
}

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
  return ext.size() <= 8 ? ext : "";
}

uint64_t StableHash64(const std::string& value) {
  uint64_t hash = 1469598103934665603ULL;
  for (unsigned char byte : value) {
    hash ^= static_cast<uint64_t>(byte);
    hash *= 1099511628211ULL;
  }
  return hash;
}

std::string HexHash(const std::string& value) {
  std::ostringstream out;
  out << std::hex << StableHash64(value);
  return out.str();
}

std::string JsonEscape(const std::string& value) {
  std::ostringstream out;
  for (char c : value) {
    switch (c) {
      case '"': out << "\\\""; break;
      case '\\': out << "\\\\"; break;
      case '\n': out << "\\n"; break;
      case '\r': out << "\\r"; break;
      case '\t': out << "\\t"; break;
      default: out << c; break;
    }
  }
  return out.str();
}

std::string DetectKind(const std::string& uri, const std::string& mimeType, const std::string& fileName) {
  const std::string lowerUri = Lower(uri);
  const std::string lowerMime = Lower(mimeType);
  const std::string fileExt = ExtensionFrom(fileName);
  const std::string ext = !fileExt.empty() ? fileExt : ExtensionFrom(uri);
  static const std::set<std::string> imageExt = {"jpg", "jpeg", "png", "webp", "heic", "heif"};
  static const std::set<std::string> videoExt = {"mp4", "mov", "m4v", "webm"};

  if (StartsWith(lowerUri, "cfstream:") || StartsWith(lowerMime, "video/") ||
      StartsWith(lowerUri, "data:video/") || videoExt.count(ext) > 0) {
    return "video";
  }
  if (StartsWith(lowerMime, "image/") || StartsWith(lowerUri, "data:image/") ||
      imageExt.count(ext) > 0) {
    return "image";
  }
  return "unknown";
}

bool IsUnsafeFile(const std::string& uri, const std::string& mimeType, const std::string& fileName) {
  const std::string fileExt = ExtensionFrom(fileName);
  const std::string ext = !fileExt.empty() ? fileExt : ExtensionFrom(uri);
  static const std::set<std::string> blocked = {
    "apk", "app", "bat", "cmd", "com", "dll", "dmg", "exe", "js", "msi", "ps1", "sh", "svg"
  };
  return blocked.count(ext) > 0 || Lower(mimeType).find("svg") != std::string::npos;
}

std::string& Scratch() {
  thread_local std::string scratch;
  return scratch;
}

}  // namespace

const char* mira_plan_media_json(
  const char* uri_c,
  const char* mime_type_c,
  const char* file_name_c,
  double file_size,
  double width,
  double height,
  const char* preset_c
) {
  const std::string uri = Safe(uri_c);
  const std::string mimeType = Safe(mime_type_c);
  const std::string fileName = Safe(file_name_c);
  const std::string preset = Safe(preset_c).empty() ? "balanced" : Safe(preset_c);
  const std::string kind = DetectKind(uri, mimeType, fileName);
  const bool unsafe = IsUnsafeFile(uri, mimeType, fileName);
  const int maxBytes = kind == "video" ? 500 * 1024 * 1024 : 20 * 1024 * 1024;
  const bool allowed = kind != "unknown" && !unsafe && file_size <= static_cast<double>(maxBytes);
  const double sourceWidth = width > 0 ? width : 1080.0;
  const double sourceHeight = height > 0 ? height : 1440.0;
  const double maxLongEdge = kind == "video"
    ? (preset == "quality" ? 1920.0 : (preset == "compact" ? 1080.0 : 1440.0))
    : preset == "quality"
      ? 2160.0
      : preset == "compact"
        ? 1080.0
        : 1440.0;
  const double longEdge = std::max(1.0, std::max(sourceWidth, sourceHeight));
  const double scale = std::min(1.0, maxLongEdge / longEdge);
  const int targetWidth = std::max(1, static_cast<int>(std::round(sourceWidth * scale)));
  const int targetHeight = std::max(1, static_cast<int>(std::round(sourceHeight * scale)));
  const std::string reason = kind == "unknown"
    ? "unknown_media_type"
    : unsafe
      ? "blocked_unsafe_file_type"
      : file_size > static_cast<double>(maxBytes)
        ? "file_too_large"
        : "ok";
  const double imageQuality = preset == "quality" ? 0.92 : (preset == "compact" ? 0.84 : 0.89);
  const int videoBitrate = preset == "quality" ? 12000000 : (preset == "compact" ? 5500000 : 8000000);
  const std::string cacheKey = HexHash(uri + "|" + fileName + "|" +
    std::to_string(static_cast<int>(sourceWidth)) + "x" +
    std::to_string(static_cast<int>(sourceHeight)) + "|" +
    std::to_string(static_cast<long long>(file_size)));

  std::ostringstream out;
  out << "{\"kind\":\"" << kind
      << "\",\"allowed\":" << (allowed ? "true" : "false")
      << ",\"reason\":\"" << reason
      << "\",\"targetWidth\":" << targetWidth
      << ",\"targetHeight\":" << targetHeight
      << ",\"aspectRatio\":" << (sourceWidth / std::max(1.0, sourceHeight))
      << ",\"maxBytes\":" << maxBytes
      << ",\"targetMimeType\":\"" << (kind == "video" ? "video/mp4" : "image/jpeg")
      << "\",\"imageQuality\":" << imageQuality
      << ",\"videoBitrate\":" << videoBitrate
      << ",\"targetFps\":30"
      << ",\"shouldUseThumbnail\":" << (kind == "video" ? "true" : "false")
      << ",\"cacheKey\":\"" << JsonEscape(cacheKey) << "\"}";

  Scratch() = out.str();
  return Scratch().c_str();
}

double mira_score_feed_item(
  double likes,
  double comments,
  double saves,
  double shares,
  double views,
  double age_hours,
  int is_followed,
  int is_video
) {
  const double engagement = (likes * 3.0) + (comments * 6.0) + (saves * 7.0) +
    (shares * 8.0) + (std::min(views, 5000.0) * 0.08);
  const double recency = std::max(0.0, 72.0 - age_hours) * 0.9;
  const double relationship = is_followed ? 18.0 : 0.0;
  const double mediaBoost = is_video ? 4.0 : 2.0;
  return engagement + recency + relationship + mediaBoost;
}

uint64_t mira_stable_hash64(const char* value) {
  return StableHash64(Safe(value));
}

const char* mira_native_design_profile_json(void) {
  Scratch() =
    "{\"runtime\":\"cpp\",\"platform\":\"ios\","
    "\"surface\":\"#FFFFFF\",\"surfaceSoft\":\"#FAFAF8\","
    "\"textPrimary\":\"#1D2119\",\"textSecondary\":\"#687066\","
    "\"forest\":\"#20361F\",\"forestPressed\":\"#172917\","
    "\"shadowColor\":\"#20361F\",\"shadowOpacity\":0.12,"
    "\"radiusCard\":22,\"radiusSheet\":28,\"minTouchTarget\":44}";
  return Scratch().c_str();
}
