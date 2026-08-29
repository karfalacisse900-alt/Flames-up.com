import Foundation
import os

enum MIRAAuthProvider: String {
  case apple
  case google
  case email
}

enum MIRAAuthFailureCategory: String {
  case providerCancelled
  case providerConfiguration
  case callbackFailure
  case credentialExchangeFailure
  case networkFailure
  case sessionFailure
  case unknown
}

enum MIRAAuthDiagnostics {
  #if DEBUG
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.captro.app",
    category: "auth"
  )
  #endif

  static func stage(_ provider: MIRAAuthProvider, _ stage: String) {
    let cleanStage = safeIdentifier(stage, fallback: "unknown")
    MIRAApplePerformanceLogger.event("oauth_\(provider.rawValue)_\(cleanStage)")
    #if DEBUG
    let line = "[AUTH][\(provider.rawValue.uppercased())] \(cleanStage)"
    logger.debug("\(line, privacy: .public)")
    print(line)
    #endif
  }

  static func failure(
    _ provider: MIRAAuthProvider,
    stage: String,
    category: MIRAAuthFailureCategory? = nil,
    error: Error
  ) {
    let cleanStage = safeIdentifier(stage, fallback: "unknown")
    let resolvedCategory = category ?? classify(error)
    MIRAApplePerformanceLogger.event(
      "oauth_\(provider.rawValue)_failed",
      detail: "stage=\(cleanStage) category=\(resolvedCategory.rawValue)"
    )
    #if DEBUG
    let nsError = error as NSError
    let diagnostic = safeDiagnosticDetails(error)
    let line = "[AUTH][\(provider.rawValue.uppercased())] FAILED at \(cleanStage) category=\(resolvedCategory.rawValue) domain=\(safeIdentifier(nsError.domain, fallback: "unknown")) code=\(nsError.code) \(diagnostic)"
    logger.error("\(line, privacy: .public)")
    print(line)
    #endif
  }

  static func callbackReceived(_ url: URL, googleHandled: Bool) {
    let scheme = safeIdentifier(url.scheme ?? "none", fallback: "none")
    let host = safeIdentifier(url.host ?? "none", fallback: "none")
    MIRAApplePerformanceLogger.event(
      "oauth_callback_received",
      detail: "scheme=\(scheme) host=\(host) google=\(googleHandled ? "handled" : "not_handled")"
    )
    #if DEBUG
    let line = "[AUTH][CALLBACK] scheme=\(scheme) host=\(host) google=\(googleHandled ? "handled" : "not_handled")"
    logger.debug("\(line, privacy: .public)")
    print(line)
    #endif
  }

  static func sessionStage(_ stage: String) {
    let cleanStage = safeIdentifier(stage, fallback: "unknown")
    MIRAApplePerformanceLogger.event("auth_session_\(cleanStage)")
    #if DEBUG
    let line = "[AUTH][SESSION] \(cleanStage)"
    logger.debug("\(line, privacy: .public)")
    print(line)
    #endif
  }

  static func classify(_ error: Error) -> MIRAAuthFailureCategory {
    if error is CancellationError { return .providerCancelled }
    if let urlError = error as? URLError {
      return urlError.code == .cancelled ? .providerCancelled : .networkFailure
    }
    guard let apiError = error as? MIRAAPIError else { return .unknown }
    switch apiError {
    case .server(let status, let code, _):
      let normalizedCode = (code ?? "").uppercased()
      if normalizedCode.contains("CONFIGURATION") || normalizedCode.contains("AUDIENCE_MISMATCH") {
        return .providerConfiguration
      }
      if normalizedCode.contains("SESSION") { return .sessionFailure }
      if status == 408 || status == 429 || status >= 500 { return .networkFailure }
      return .credentialExchangeFailure
    case .badURL, .insecureURL:
      return .providerConfiguration
    case .badStatus(let status):
      return status >= 500 ? .networkFailure : .credentialExchangeFailure
    case .decodingFailed, .emptyResponse:
      return .sessionFailure
    }
  }

  private static func safeDiagnosticDetails(_ error: Error) -> String {
    if let apiError = error as? MIRAAPIError {
      switch apiError {
      case .server(let status, let code, let detail):
        return "http=\(status) server=\(safeIdentifier(code ?? "none", fallback: "none")) message=\(safeMessage(detail ?? "none"))"
      case .badStatus(let status):
        return "http=\(status)"
      case .badURL:
        return "message=bad_url"
      case .insecureURL:
        return "message=insecure_url"
      case .decodingFailed:
        return "message=response_decoding_failed"
      case .emptyResponse:
        return "message=session_response_empty"
      }
    }
    return "message=\(safeMessage((error as NSError).localizedDescription))"
  }

  private static func safeIdentifier(_ value: String, fallback: String) -> String {
    let filtered = value
      .replacingOccurrences(of: "[^A-Za-z0-9_.:-]", with: "_", options: .regularExpression)
      .prefix(96)
    return filtered.isEmpty ? fallback : String(filtered)
  }

  private static func safeMessage(_ value: String) -> String {
    let clean = value.replacingOccurrences(of: "\n", with: " ").prefix(180)
    let lowered = clean.lowercased()
    let sensitiveMarkers = ["access_token", "id_token", "refresh_token", "bearer ", "password", "secret", "code=", "state=", "eyj", "@"]
    guard !sensitiveMarkers.contains(where: lowered.contains) else { return "redacted" }
    return clean.isEmpty ? "none" : String(clean)
  }
}
