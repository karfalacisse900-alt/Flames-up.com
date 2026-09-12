import AuthenticationServices
import UIKit

enum CaptroPayoutOnboardingAction: Equatable {
  case complete
  case refresh
  case cancelled
}

private enum CaptroPayoutOnboardingError: LocalizedError {
  case invalidConfiguration
  case invalidCallback
  case couldNotStart
  case profileEmailRequired
  case linkRequestFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration:
      return "The secure payout card configuration could not be verified."
    case .invalidCallback:
      return "The secure payout card setup did not return to Captro correctly."
    case .couldNotStart:
      return "Could not open secure payout card setup."
    case .profileEmailRequired:
      return "Add a valid email address to your Captro profile before setting up payouts."
    case .linkRequestFailed(let code):
      return "Captro could not create the secure payout setup link. Reference: \(code)."
    }
  }
}

extension Notification.Name {
  static let captroPayoutOnboardingCallback = Notification.Name(
    "com.captro.app.payout-onboarding-callback"
  )
}

@MainActor
final class CaptroPayoutOnboardingCoordinator: NSObject, ObservableObject,
  ASWebAuthenticationPresentationContextProviding {
  private var session: ASWebAuthenticationSession?
  private weak var presentingViewController: UIViewController?
  private var presentationWindow: UIWindow?
  private var externalBrowserCompletion: ((Result<CaptroPayoutOnboardingAction, Error>) -> Void)?
  private var externalBrowserDidBackground = false

  override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handlePayoutCallbackNotification(_:)),
      name: .captroPayoutOnboardingCallback,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  static func handleIncomingURL(_ url: URL) -> Bool {
    guard action(for: url) != nil else { return false }
    NotificationCenter.default.post(name: .captroPayoutOnboardingCallback, object: url)
    return true
  }

  func start(
    api: MIRAAPIClient,
    completion: @escaping (Result<CaptroPayoutOnboardingAction, Error>) -> Void
  ) {
    session?.cancel()
    externalBrowserCompletion = nil
    externalBrowserDidBackground = false
    Task {
      do {
        let link = try await api.createPayoutOnboardingLink()
        guard let url = URL(string: link.url) else {
          throw CaptroPayoutOnboardingError.invalidConfiguration
        }
        start(url: url, completion: completion)
      } catch {
        completion(.failure(Self.payoutLinkError(error)))
      }
    }
  }

  func start(
    url: URL,
    completion: @escaping (Result<CaptroPayoutOnboardingAction, Error>) -> Void
  ) {
    session?.cancel()
    presentingViewController = topViewController()
    guard let window = activeWindow() else {
      startExternalBrowser(url: url, completion: completion)
      return
    }
    presentationWindow = window
    let authenticationSession = ASWebAuthenticationSession(
      url: url,
      callbackURLScheme: "captro"
    ) { [weak self] callbackURL, error in
      Task { @MainActor in
        self?.session = nil
        self?.presentingViewController = nil
        self?.presentationWindow = nil
        if let authenticationError = error as? ASWebAuthenticationSessionError,
           authenticationError.code == .canceledLogin {
          completion(.success(.cancelled))
          return
        }
        if let error {
          completion(.failure(error))
          return
        }
        guard let callbackURL,
              callbackURL.scheme?.lowercased() == "captro",
              callbackURL.host?.lowercased() == "payouts" else {
          completion(.failure(CaptroPayoutOnboardingError.invalidCallback))
          return
        }
        switch callbackURL.path.lowercased() {
        case "/complete": completion(.success(.complete))
        case "/refresh": completion(.success(.refresh))
        default: completion(.failure(CaptroPayoutOnboardingError.invalidCallback))
        }
      }
    }
    authenticationSession.presentationContextProvider = self
    authenticationSession.prefersEphemeralWebBrowserSession = false
    session = authenticationSession
    if !authenticationSession.start() {
      session = nil
      presentingViewController = nil
      presentationWindow = nil
      startExternalBrowser(url: url, completion: completion)
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    presentationWindow ?? activeWindow() ?? UIWindow()
  }

  @objc private func handlePayoutCallbackNotification(_ notification: Notification) {
    guard let url = notification.object as? URL,
          let action = Self.action(for: url),
          externalBrowserCompletion != nil else { return }
    finishExternalBrowser(.success(action))
  }

  @objc private func applicationDidEnterBackground() {
    guard externalBrowserCompletion != nil else { return }
    externalBrowserDidBackground = true
  }

  @objc private func applicationDidBecomeActive() {
    guard externalBrowserCompletion != nil, externalBrowserDidBackground else { return }
    finishExternalBrowser(.success(.complete))
  }

  private func startExternalBrowser(
    url: URL,
    completion: @escaping (Result<CaptroPayoutOnboardingAction, Error>) -> Void
  ) {
    externalBrowserCompletion = completion
    externalBrowserDidBackground = false
    UIApplication.shared.open(url, options: [:]) { [weak self] opened in
      guard !opened else { return }
      Task { @MainActor in
        self?.finishExternalBrowser(.failure(CaptroPayoutOnboardingError.couldNotStart))
      }
    }
  }

  private func finishExternalBrowser(_ result: Result<CaptroPayoutOnboardingAction, Error>) {
    let completion = externalBrowserCompletion
    externalBrowserCompletion = nil
    externalBrowserDidBackground = false
    completion?(result)
  }

  private static func action(for url: URL) -> CaptroPayoutOnboardingAction? {
    guard url.scheme?.lowercased() == "captro",
          url.host?.lowercased() == "payouts" else { return nil }
    switch url.path.lowercased() {
    case "/complete": return .complete
    case "/refresh": return .refresh
    default: return nil
    }
  }

  private static func payoutLinkError(_ error: Error) -> Error {
    guard case let MIRAAPIError.server(_, code, _) = error,
          let code, !code.isEmpty else { return error }
    if code == "COMMERCE_PAYOUT_EMAIL_REQUIRED" {
      return CaptroPayoutOnboardingError.profileEmailRequired
    }
    return CaptroPayoutOnboardingError.linkRequestFailed(code)
  }

  private func activeWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
    return scenes.flatMap(\.windows).first(where: \.isKeyWindow)
      ?? presentingViewController?.viewIfLoaded?.window
      ?? scenes.flatMap(\.windows).first
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
    let root = scenes
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController
      ?? scenes.flatMap(\.windows).first?.rootViewController
    return topViewController(from: root)
  }

  private func topViewController(from root: UIViewController?) -> UIViewController? {
    if let presented = root?.presentedViewController {
      return topViewController(from: presented)
    }
    if let navigation = root as? UINavigationController {
      return topViewController(from: navigation.visibleViewController)
    }
    if let tabs = root as? UITabBarController {
      return topViewController(from: tabs.selectedViewController)
    }
    return root
  }
}
