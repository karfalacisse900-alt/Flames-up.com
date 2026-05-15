#include "SecurityEngineCore.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <set>
#include <sstream>

namespace flames {

namespace {

std::string Trim(const std::string& value) {
  size_t start = 0;
  while (start < value.size() && std::isspace(static_cast<unsigned char>(value[start]))) start++;
  size_t end = value.size();
  while (end > start && std::isspace(static_cast<unsigned char>(value[end - 1]))) end--;
  return value.substr(start, end - start);
}

std::string Lower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return value;
}

bool HasUnsafeControlOrHtml(const std::string& value) {
  for (const char c : value) {
    const unsigned char u = static_cast<unsigned char>(c);
    if (u < 32 || u == 127) return true;
    if (c == '<' || c == '>' || c == '"' || c == '\'' || c == '`' || c == '\\') return true;
  }
  return false;
}

bool StartsWith(const std::string& value, const std::string& prefix) {
  return value.rfind(prefix, 0) == 0;
}

std::string StripTrailingDots(std::string host) {
  while (!host.empty() && host.back() == '.') host.pop_back();
  return host;
}

std::string ExtractHost(const std::string& url) {
  const size_t scheme = url.find("://");
  size_t start = scheme == std::string::npos ? 0 : scheme + 3;
  const size_t end = url.find_first_of("/?#", start);
  std::string hostPort = url.substr(start, end == std::string::npos ? std::string::npos : end - start);
  const size_t at = hostPort.find('@');
  if (at != std::string::npos) return "";
  if (!hostPort.empty() && hostPort.front() == '[') return "";
  const size_t colon = hostPort.find(':');
  std::string host = colon == std::string::npos ? hostPort : hostPort.substr(0, colon);
  return StripTrailingDots(Lower(host));
}

std::string JsonEscape(const std::string& value) {
  std::ostringstream out;
  for (const char c : value) {
    if (c == '"' || c == '\\') out << '\\' << c;
    else if (c == '\n') out << "\\n";
    else if (c == '\r') out << "\\r";
    else if (c == '\t') out << "\\t";
    else out << c;
  }
  return out.str();
}

}  // namespace

std::string SecurityEngineCore::NormalizeTextSignal(const std::string& value) {
  std::string lower = Lower(value);
  std::string output;
  output.reserve(std::min<size_t>(lower.size(), 512));

  bool lastSpace = false;
  for (size_t i = 0; i < lower.size() && output.size() < 512; ++i) {
    const unsigned char c = static_cast<unsigned char>(lower[i]);
    const bool keep = std::isalnum(c) || c == '@' || c == '.' || c == '_' || c == '-';
    if (keep) {
      output.push_back(static_cast<char>(c));
      lastSpace = false;
    } else if (!lastSpace) {
      output.push_back(' ');
      lastSpace = true;
    }
  }
  return Trim(output);
}

std::string SecurityEngineCore::FingerprintSignal(const std::string& value) {
  const std::string normalized = NormalizeTextSignal(value);
  uint64_t hash = 14695981039346656037ull;
  for (const unsigned char c : normalized) {
    hash ^= static_cast<uint64_t>(c);
    hash *= 1099511628211ull;
  }

  std::ostringstream out;
  out << std::hex << std::setfill('0') << std::setw(16) << hash;
  return out.str();
}

bool SecurityEngineCore::IsPrivateOrLocalHost(const std::string& host) {
  if (host.empty() || host == "localhost") return true;
  if (host.size() >= 6 && host.substr(host.size() - 6) == ".local") return true;
  if (StartsWith(host, "0.") || StartsWith(host, "10.") || StartsWith(host, "127.")) return true;
  if (StartsWith(host, "169.254.") || StartsWith(host, "192.168.")) return true;
  if (StartsWith(host, "172.")) {
    const size_t secondDot = host.find('.', 4);
    if (secondDot != std::string::npos) {
      const int block = std::atoi(host.substr(4, secondDot - 4).c_str());
      if (block >= 16 && block <= 31) return true;
    }
  }
  return false;
}

UrlAssessment SecurityEngineCore::AssessUrl(const std::string& value) {
  const std::string raw = Trim(value);
  if (raw.empty()) return {false, "", "empty", 0};
  if (HasUnsafeControlOrHtml(raw)) return {false, "", "unsafe_characters", 95};

  std::string url = raw;
  std::string lowered = Lower(url);
  if (!StartsWith(lowered, "http://") && !StartsWith(lowered, "https://")) {
    url = "https://" + url;
    lowered = Lower(url);
  }

  if (!StartsWith(lowered, "http://") && !StartsWith(lowered, "https://")) {
    return {false, "", "blocked_protocol", 100};
  }

  const std::string host = ExtractHost(url);
  if (host.empty()) return {false, "", "invalid_host", 90};
  if (IsPrivateOrLocalHost(host)) return {false, "", "private_or_local_host", 90};

  static const std::set<std::string> shorteners = {
      "bit.ly", "cutt.ly", "goo.gl", "is.gd", "lnkd.in", "ow.ly",
      "rebrand.ly", "shorturl.at", "t.co", "tiny.cc", "tinyurl.com"};

  int risk = StartsWith(lowered, "http://") ? 20 : 0;
  if (shorteners.find(host) != shorteners.end()) risk += 25;
  if (url.size() > 280) risk += 10;

  return {true, url, risk > 0 ? "allowed_with_caution" : "allowed", risk};
}

std::string UrlAssessmentToJson(const UrlAssessment& assessment) {
  std::ostringstream out;
  out << "{\"allowed\":" << (assessment.allowed ? "true" : "false")
      << ",\"safeUrl\":\"" << JsonEscape(assessment.safeUrl)
      << "\",\"reason\":\"" << JsonEscape(assessment.reason)
      << "\",\"riskScore\":" << assessment.riskScore << "}";
  return out.str();
}

}  // namespace flames
