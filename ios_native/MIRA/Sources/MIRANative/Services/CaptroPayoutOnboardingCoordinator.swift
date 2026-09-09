import AuthenticationServices
import UIKit

enum CaptroPayoutOnboardingAction: Equatable {
  case complete
  case refresh
  case cancelled
}

private enum CaptroPayoutOnboardingError: LocalizedError {
  case invalidCallback
  case couldNotStart

  var errorDescription: String? {
    switch self {
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
      completion(.failure(CaptroPayoutOnboardingError.couldNotStart))
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.flatMap { $0.windows }.first(where: \.isKeyWindow)
      ?? scenes.first?.windows.first
      ?? UIWindow()
  }
}
