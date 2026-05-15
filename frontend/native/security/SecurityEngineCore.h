#pragma once

#include <string>

namespace flames {

struct UrlAssessment {
  bool allowed = false;
  std::string safeUrl;
  std::string reason;
  int riskScore = 0;
};

class SecurityEngineCore {
 public:
  static std::string NormalizeTextSignal(const std::string& value);
  static std::string FingerprintSignal(const std::string& value);
  static UrlAssessment AssessUrl(const std::string& value);

 private:
  static bool IsPrivateOrLocalHost(const std::string& host);
};

std::string UrlAssessmentToJson(const UrlAssessment& assessment);

}  // namespace flames
