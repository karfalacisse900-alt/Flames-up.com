#if DEBUG
import SwiftUI

/// Runs the shipping welcome/auth views with isolated, tokenless session storage.
/// No successful provider callback is faked and no production API is contacted.
public struct CaptroWelcomeReviewHost: View {
  @StateObject private var session: MIRAAuthSession
  private let api: MIRAAPIClient
  private let defaults: UserDefaults
  public init() {
    let defaults = UserDefaults(suiteName: "captro.welcome.review")!
    defaults.removePersistentDomain(forName: "captro.welcome.review")
    self.defaults = defaults
    let session = MIRAAuthSession(keychain: WelcomeReviewStorage(), defaults: defaults)
    if ProcessInfo.processInfo.arguments.contains("--welcome-error") {
      session.errorMessage = "Google sign in could not finish. Please try again."
    }
    _session = StateObject(wrappedValue: session)
    api = MIRAAPIClient(baseURL: URL(string: "https://localhost:9449")!, sessionProvider: session)
  }
  public var body: some View {
    Group {
      if session.isGuest {
        VStack(spacing: 20) {
          Text("Guest session — no authenticated account").accessibilityIdentifier("welcome.guest.confirmed")
          Button("Back to welcome") { session.exitGuestMode() }
        }
      } else { AuthNativeView(session: session, api: api) }
    }
    .defaultAppStorage(defaults)
    .environmentObject(MIRALocalization.shared)
    .environment(\.captroWelcomeReducedMotion, ProcessInfo.processInfo.arguments.contains("--welcome-reduce-motion") ? true : nil)
    .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("--welcome-large-text") ? .accessibility3 : .large)
  }
}

private final class WelcomeReviewStorage: MIRAAuthSessionStorage {
  func accessToken() async -> String? { nil }
  func refreshToken() async -> String? { nil }
  func saveSession(accessToken: String, refreshToken: String?) { assertionFailure("Welcome review must not create credentials") }
  func clearSession() {}
}
#endif
