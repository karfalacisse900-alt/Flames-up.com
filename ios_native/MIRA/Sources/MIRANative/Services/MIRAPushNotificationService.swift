import Foundation
import UIKit

public extension Notification.Name {
  static let miraRemotePushTokenReceived = Notification.Name("mira.remotePushTokenReceived")
  static let miraRemotePushRegistrationFailed = Notification.Name("mira.remotePushRegistrationFailed")
  static let miraNotificationOpened = Notification.Name("mira.notificationOpened")
}

private struct MIRAPushTokenBody: Encodable {
  let token: String
  let deviceId: String
  let bundleId: String
  let environment: String
}

private struct MIRAPushTokenResponse: Decodable {
  let ok: Bool?
}

public enum MIRAPushNotificationRegistrar {
  private static let deviceIdKey = "mira.push.device_id"
  private static let tokenKey = "mira.push.device_token"

  public static func registerForRemoteNotifications() {
    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
    }
  }

  public static func cacheDeviceToken(_ token: String) {
    UserDefaults.standard.set(token, forKey: tokenKey)
  }

  public static var cachedDeviceToken: String? {
    UserDefaults.standard.string(forKey: tokenKey)
  }

  public static var deviceId: String {
    if let existing = UserDefaults.standard.string(forKey: deviceIdKey), !existing.isEmpty {
      return existing
    }
    let created = UUID().uuidString
    UserDefaults.standard.set(created, forKey: deviceIdKey)
    return created
  }

  public static var bundleId: String {
    Bundle.main.bundleIdentifier ?? "com.karfala90.frontend"
  }

  public static var environment: String {
    #if DEBUG
    return "development"
    #else
    return "production"
    #endif
  }
}

public actor MIRAPushTokenRegistry {
  public static let shared = MIRAPushTokenRegistry()

  private var lastRegisteredToken: String?

  public func registerDeviceToken(_ token: String, api: MIRAAPIClient) async {
    let clean = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard clean.count >= 32 else { return }
    if clean == lastRegisteredToken { return }

    let body = MIRAPushTokenBody(
      token: clean,
      deviceId: MIRAPushNotificationRegistrar.deviceId,
      bundleId: MIRAPushNotificationRegistrar.bundleId,
      environment: MIRAPushNotificationRegistrar.environment
    )

    do {
      let _: MIRAPushTokenResponse = try await api.post("/notifications/device-token", body: body)
      lastRegisteredToken = clean
    } catch {
      await MIRAObservability.record(
        "push_token_register_failed",
        category: "notifications",
        status: "error",
        metadata: ["environment": MIRAPushNotificationRegistrar.environment],
        api: api
      )
    }
  }
}
