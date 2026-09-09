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

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration:
      return "The secure payout card configuration could not be verified."
    case .invalidCallback:
      return "The secure payout card setup did not return to Captro correctly."
    case .couldNotStart:
      return "Could not open secure payout card setup."
    }
  }
}

@MainActor
final class CaptroPayoutOnboardingCoordinator: NSObject, ObservableObject,
  ASWebAuthenticationPresentationContextProviding {
  private var session: ASWebAuthenticationSession?
  private weak var presentingViewController: UIViewController?

  func start(
    api: MIRAAPIClient,
    completion: @escaping (Result<CaptroPayoutOnboardingAction, Error>) -> Void
  ) {
    session?.cancel()
    presentingViewController = topViewController()
    Task {
      do {
        let link = try await api.createPayoutOnboardingLink()
        guard let url = URL(string: link.url) else {
          throw CaptroPayoutOnboardingError.invalidConfiguration
        }
        start(url: url, completion: completion)
      } catch {
        completion(.failure(error))
      }
    }
  }

  func start(
    url: URL,
    completion: @escaping (Result<CaptroPayoutOnboardingAction, Error>) -> Void
  ) {
    session?.cancel()
    let authenticationSession = ASWebAuthenticationSession(
      url: url,
      callbackURLScheme: "captro"
    ) { [weak self] callbackURL, error in
      Task { @MainActor in
        self?.session = nil
        self?.presentingViewController = nil
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
      completion(.failure(CaptroPayoutOnboardingError.couldNotStart))
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    if let window = presentingViewController?.viewIfLoaded?.window {
      return window
    }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.flatMap { $0.windows }.first(where: \.isKeyWindow)
      ?? scenes.first?.windows.first
      ?? UIWindow()
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
