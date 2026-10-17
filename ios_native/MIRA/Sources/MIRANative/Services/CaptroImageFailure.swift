import Foundation

/// Transport failures are not interchangeable with cancellation or an empty URL.
/// Deliberately contains no URL, token, response body, or customer identifier.
enum CaptroImageFailure: Error, Equatable {
  case missing, inaccessible, removed, invalidData, invalidResponse, oversized
  case transient, throttled, transport

  static func response(status: Int, mime: String?) -> Self? {
    switch status {
    case 401, 403: return .inaccessible
    case 404, 410: return .removed
    case 429: return .throttled
    case 500...599, 408: return .transient
    case 200...299:
      // Some signed object stores legitimately omit the MIME type or use octet-stream.
      guard let mime = mime?.lowercased(), !mime.isEmpty else { return nil }
      return mime.hasPrefix("image/") || mime == "application/octet-stream" ? nil : .invalidResponse
    default: return .invalidResponse
    }
  }
  var mayRetryAutomatically: Bool { self == .transient || self == .transport }
  var permitsFallback: Bool { self != .inaccessible }
  var unavailable: Bool { [.missing, .inaccessible, .removed].contains(self) }
  var message: String {
    switch self {
    case .missing, .removed: return "Image unavailable"
    case .inaccessible: return "Image access unavailable"
    case .throttled: return "Image loading is busy. Try again shortly."
    default: return "Image couldn't load"
    }
  }
}
