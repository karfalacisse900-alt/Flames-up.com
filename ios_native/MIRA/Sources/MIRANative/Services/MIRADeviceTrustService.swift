import DeviceCheck
import Foundation

public actor MIRADeviceTrustService {
  public static let shared = MIRADeviceTrustService()

  private init() {}

  public func headers(for method: String, path: String) async -> [String: String] {
    guard shouldAttachTrustSignal(method: method, path: path) else { return [:] }

    var headers: [String: String] = [
      "X-Captro-Device-Trust-Mode": "monitor",
      "X-Captro-Device-Trust-Action": "\(method.uppercased()) \(path)"
    ]

    if DCAppAttestService.shared.isSupported {
      headers["X-Captro-App-Attest-Supported"] = "1"
    }

    if DCDevice.current.isSupported, let token = await deviceCheckToken() {
      headers["X-Captro-DeviceCheck-Token"] = token
    }

    return headers
  }

  private func shouldAttachTrustSignal(method: String, path: String) -> Bool {
    let cleanMethod = method.uppercased()
    guard cleanMethod != "GET" else { return false }
    let cleanPath = path.lowercased()
    return [
      "/upload/",
      "/posts",
      "/comments",
      "/reports",
      "/auth/",
      "/username",
      "/notifications/device-token"
    ].contains { cleanPath.contains($0) }
  }

  private func deviceCheckToken() async -> String? {
    await withCheckedContinuation { continuation in
      DCDevice.current.generateToken { data, _ in
        continuation.resume(returning: data?.base64EncodedString())
      }
    }
  }
}
