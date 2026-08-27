import MIRANative
import UIKit
import UserNotifications

final class MIRAAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    MIRAApplePerformanceLogger.event("application_launch_started")
    MIRAAppleRuntimeDiagnostics.start()
    _ = MIRANativeBridgeDiagnostics.verifyStartupLinkage()
    MIRAApplePerformanceLogger.event("background_task_registration_started")
    MIRABackgroundTaskCoordinator.shared.register()
    MIRAApplePerformanceLogger.event("background_task_registration_finished")
    UNUserNotificationCenter.current().delegate = self
    MIRAApplePerformanceLogger.event("application_launch_finished")
    return true
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    MIRAPushNotificationRegistrar.cacheDeviceToken(token)
    NotificationCenter.default.post(name: .miraRemotePushTokenReceived, object: token)
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NotificationCenter.default.post(name: .miraRemotePushRegistrationFailed, object: error.localizedDescription)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound, .badge, .list]
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let userInfo = response.notification.request.content.userInfo
    NotificationCenter.default.post(name: .miraNotificationOpened, object: nil, userInfo: userInfo)
    MIRAApplePerformanceLogger.event("notification_opened")
  }
}
