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
    Bundle.main.bundleIdentifier ?? "com.captro.app"
  }

  public static var environment: String {
    #if DEBUG
    return "development"
    #else
    return "production"
    #endif
  }
}

@MainActor public final class MIRAPushTokenRegistry {
  public static let shared = MIRAPushTokenRegistry()

  private struct Binding {
    let accountID: String
    let body: MIRAPushTokenBody
    let api: MIRAAPIClient
    var key: String { "\(accountID):\(body.token)" }
  }

  private var desired: Binding?
  private var registered: Binding?
  private var pendingRemoval: [String: Binding] = [:]
  private var work: Task<Void, Never>?
  private var revision: UInt64 = 0

  public init() {}

  public func registerDeviceToken(_ token: String, accountID: String, accessToken: String, api: MIRAAPIClient) async {
    let clean = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard (32...512).contains(clean.count), clean.allSatisfy(\.isHexDigit),
          !accountID.isEmpty, !accessToken.isEmpty else { return }

    let body = MIRAPushTokenBody(
      token: clean,
      deviceId: MIRAPushNotificationRegistrar.deviceId,
      bundleId: MIRAPushNotificationRegistrar.bundleId,
      environment: MIRAPushNotificationRegistrar.environment
    )

    let target = Binding(accountID: accountID, body: body, api: api.pinned(to: accessToken))
    desired = target
    if registered?.key == target.key, pendingRemoval.isEmpty {
      registered = target // Keep current credentials for a later unregister.
      return
    }
    enqueueTransition()
    await work?.value
  }

  public func endSession() {
    desired = nil
    UIApplication.shared.unregisterForRemoteNotifications()
    enqueueTransition()
  }

  private func enqueueTransition() {
    revision &+= 1
    let requestedRevision = revision
    let previous = work
    // Finish an already-sent registration before unregistering it. Cancelling
    // its URLSession task alone cannot undo a write already accepted by server.
    work = Task { [weak self] in
      await previous?.value
      guard let self, requestedRevision == self.revision else { return }
      await self.reconcile()
    }
  }

  private func reconcile() async {
    if let registered, registered.key != desired?.key {
      pendingRemoval[registered.key] = registered
      self.registered = nil
    }
    for (key, old) in pendingRemoval {
      do {
        let _: MIRAPushTokenResponse = try await old.api.delete("/notifications/device-token", body: old.body)
        pendingRemoval[key] = nil
      } catch {
        // Retain the old pinned binding for a retry on the next foreground or
        // account transition. No token, account ID, or credentials are logged.
        await recordFailure("push_token_unregister_failed", api: old.api)
      }
    }
    guard let target = desired, registered?.key != target.key else { return }
    do {
      let _: MIRAPushTokenResponse = try await target.api.post("/notifications/device-token", body: target.body)
      registered = target
    } catch {
      // A lost response can still mean the write reached the server.
      pendingRemoval[target.key] = target
      await recordFailure("push_token_register_failed", api: target.api)
    }
  }

  private func recordFailure(_ event: String, api: MIRAAPIClient) async {
    await MIRAObservability.record(event, category: "notifications", status: "error",
      metadata: ["environment": MIRAPushNotificationRegistrar.environment], api: api)
  }
}
