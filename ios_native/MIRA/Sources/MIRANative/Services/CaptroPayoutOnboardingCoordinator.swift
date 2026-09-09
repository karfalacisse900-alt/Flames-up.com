import AuthenticationServices
import StripeConnect
import StripePayments
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
  ASWebAuthenticationPresentationContextProviding, AccountOnboardingControllerDelegate {
  private var session: ASWebAuthenticationSession?
  private var componentManager: EmbeddedComponentManager?
  private var onboardingController: AccountOnboardingController?
  private weak var presentingViewController: UIViewController?
  private var nativeCompletion: ((Result<CaptroPayoutOnboardingAction, Error>) -> Void)?
  private var onboardingAPI: MIRAAPIClient?
  private var isStartingHostedFallback = false

  func start(
    api: MIRAAPIClient,
    completion: @escaping (Result<CaptroPayoutOnboardingAction, Error>) -> Void
  ) {
    clearNativeState()
    nativeCompletion = completion
    onboardingAPI = api
    Task {
      do {
        let initialSession = try await api.createPayoutAccountSession()
        try presentNativeOnboarding(initialSession: initialSession, api: api)
      } catch {
        await startHostedFallback(api: api)
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
    if let window = presentingViewController?.viewIfLoaded?.window {
      return window
    }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.flatMap { $0.windows }.first(where: \.isKeyWindow)
      ?? scenes.first?.windows.first
      ?? UIWindow()
  }

  func accountOnboardingDidExit(_ accountOnboarding: AccountOnboardingController) {
    finishNative(.success(.complete))
  }

  func accountOnboarding(
    _ accountOnboarding: AccountOnboardingController,
    didFailLoadWithError error: Error
  ) {
    guard let api = onboardingAPI else {
      finishNative(.failure(error))
      return
    }
    let fallback = { [weak self] in
      Task { @MainActor in
        await self?.startHostedFallback(api: api)
      }
    }
    if let presented = presentingViewController?.presentedViewController {
      presented.dismiss(animated: true, completion: fallback)
    } else {
      fallback()
    }
  }

  private func presentNativeOnboarding(
    initialSession: CaptroPayoutAccountSession,
    api: MIRAAPIClient
  ) throws {
    guard ["test", "live"].contains(initialSession.mode),
          initialSession.publishableKey.hasPrefix("pk_\(initialSession.mode)_"),
          initialSession.accountSessionClientSecret.count > 20,
          let presenter = topViewController() else {
      throw CaptroPayoutOnboardingError.invalidConfiguration
    }

    let secretProvider = CaptroPayoutAccountSessionSecretProvider(
      api: api,
      initialSession: initialSession
    )
    let stripeClient = STPAPIClient(publishableKey: initialSession.publishableKey)
    let manager = EmbeddedComponentManager(apiClient: stripeClient) {
      await secretProvider.nextSecret()
    }
    let controller = manager.createAccountOnboardingController()
    controller.delegate = self
    controller.title = initialSession.account.needsIdentityVerification
      ? "Verify Identity"
      : "Add Payout Card"
    componentManager = manager
    onboardingController = controller
    presentingViewController = presenter
    controller.present(from: presenter)
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

  private func finishNative(_ result: Result<CaptroPayoutOnboardingAction, Error>) {
    let completion = nativeCompletion
    clearNativeState()
    completion?(result)
  }

  private func startHostedFallback(api: MIRAAPIClient) async {
    guard !isStartingHostedFallback else { return }
    isStartingHostedFallback = true
    componentManager = nil
    onboardingController = nil
    do {
      let link = try await api.createPayoutOnboardingLink()
      guard let url = URL(string: link.url) else {
        throw CaptroPayoutOnboardingError.invalidConfiguration
      }
      let completion = nativeCompletion
      nativeCompletion = nil
      onboardingAPI = nil
      isStartingHostedFallback = false
      start(url: url) { [weak self] result in
        Task { @MainActor in self?.clearNativeState() }
        completion?(result)
      }
    } catch {
      finishNative(.failure(error))
    }
  }

  private func clearNativeState(keepingCompletion: Bool = false) {
    componentManager = nil
    onboardingController = nil
    presentingViewController = nil
    onboardingAPI = nil
    isStartingHostedFallback = false
    if !keepingCompletion { nativeCompletion = nil }
  }
}

private actor CaptroPayoutAccountSessionSecretProvider {
  private let api: MIRAAPIClient
  private let publishableKey: String
  private let mode: String
  private var initialSecret: String?

  init(api: MIRAAPIClient, initialSession: CaptroPayoutAccountSession) {
    self.api = api
    publishableKey = initialSession.publishableKey
    mode = initialSession.mode
    initialSecret = initialSession.accountSessionClientSecret
  }

  func nextSecret() async -> String? {
    if let initialSecret {
      self.initialSecret = nil
      return initialSecret
    }
    guard let session = try? await api.createPayoutAccountSession(),
          session.mode == mode,
          session.publishableKey == publishableKey,
          session.accountSessionClientSecret.count > 20 else {
      return nil
    }
    return session.accountSessionClientSecret
  }
}
