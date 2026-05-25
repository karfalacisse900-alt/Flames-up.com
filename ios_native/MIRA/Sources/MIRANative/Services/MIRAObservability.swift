import Foundation

private struct MIRAClientEventBody: Encodable {
  let eventName: String
  let category: String
  let status: String
  let durationMs: Int
  let metadata: [String: String]
  let appVersion: String
  let platform: String
}

private struct MIRAClientEventResponse: Decodable {
  let accepted: Bool?
}

public enum MIRAObservability {
  public static func record(
    _ eventName: String,
    category: String,
    status: String,
    durationMilliseconds: Int = 0,
    metadata: [String: String] = [:],
    api: MIRAAPIClient
  ) async {
    let body = MIRAClientEventBody(
      eventName: eventName,
      category: category,
      status: status,
      durationMs: max(0, min(durationMilliseconds, 600_000)),
      metadata: sanitized(metadata),
      appVersion: appVersion,
      platform: "ios"
    )

    do {
      let _: MIRAClientEventResponse = try await api.post("/client/events", body: body)
    } catch {
      // Telemetry must never block the user flow.
    }
  }

  private static var appVersion: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    return [version, build].compactMap { value in
      guard let value, !value.isEmpty else { return nil }
      return value
    }.joined(separator: ".")
  }

  private static func sanitized(_ metadata: [String: String]) -> [String: String] {
    var output: [String: String] = [:]
    for (key, value) in metadata.prefix(12) {
      let lowered = key.lowercased()
      guard !lowered.contains("token"),
            !lowered.contains("password"),
            !lowered.contains("secret"),
            !lowered.contains("email"),
            !lowered.contains("message"),
            !lowered.contains("caption")
      else { continue }
      let cleanKey = key.filter { $0.isLetter || $0.isNumber || "_.:-".contains($0) }.prefix(40)
      guard !cleanKey.isEmpty else { continue }
      output[String(cleanKey)] = String(value.prefix(120))
    }
    return output
  }
}
