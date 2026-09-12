import Combine
import StripeConnect
import StripePayments
import UIKit

enum CaptroPayoutOnboardingAction: Equatable {
  case complete
}

private enum CaptroPayoutOnboardingError: LocalizedError {
  case invalidConfiguration
  case couldNotStart
  case profileEmailRequired
  case payoutSetupUnavailable
  case payoutAccountConflict

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration:
      return "The secure payout card configuration could not be verified."
    case .couldNotStart:
      return "Could not open secure payout card setup."
    case .profileEmailRequired:
      return "Add a valid email address to your Captro profile before setting up payouts."
    case .payoutSetupUnavailable:
      return "Could not open secure payout card setup. Please try again."
    case .payoutAccountConflict:
      return "We could not verify your existing payout setup securely. Please contact Captro support."
    }
  }
}

/// Presents Stripe's in-app payout card setup and required verification UI.
///
/// Account Session secrets are intentionally short-lived. This coordinator only
/// keeps them in memory while the embedded component is on screen and asks the
/// Captro API for a fresh secret whenever Stripe refreshes the session.
@MainActor
final class CaptroPayoutOnboardingCoordinator: NSObject, ObservableObject,
  AccountOnboardingControllerDelegate {
  private var embeddedComponentManager: EmbeddedComponentManager?
  private var accountOnboardingController: AccountOnboardingController?
  private weak var presentingViewController: UIViewController?
  private var completion: ((Result<CaptroPayoutOnboardingAction, Error>) -> Void)?

  func start(
    api: MIRAAPIClient,
    completion: @escaping (Result<CaptroPayoutOnboardingAction, Error>) -> Void
  ) {
    guard self.completion == nil else { return }
    self.completion = completion

    Task { [weak self] in
      do {
        let configuration = try await api.createPayoutAccountSession()
        guard Self.isValid(configuration) else {
          throw CaptroPayoutOnboardingError.invalidConfiguration
        }
        guard let self else { return }

        let stripeClient = STPAPIClient(publishableKey: configuration.publishableKey)
        let expectedMode = configuration.mode
        let expectedPublishableKey = configuration.publishableKey
        let manager = EmbeddedComponentManager(
          apiClient: stripeClient,
          fetchClientSecret: { [api] in
            do {
              let session = try await api.createPayoutAccountSession()
              guard Self.isValid(
                session,
                expectedMode: expectedMode,
                expectedPublishableKey: expectedPublishableKey
              ) else {
                return nil
              }
              return session.accountSessionClientSecret
            } catch {
              return nil
            }
          }
        )
        let controller = manager.createAccountOnboardingController(
          recipientTermsOfServiceUrl: URL(string: "https://captro.app/legal/terms"),
          privacyPolicyUrl: URL(string: "https://captro.app/legal/privacy")
        )
        controller.delegate = self
        controller.title = "Payout Card Setup"

        guard let presentingViewController = self.topViewController() else {
          throw CaptroPayoutOnboardingError.couldNotStart
        }
        guard self.completion != nil else { return }
        self.embeddedComponentManager = manager
        self.accountOnboardingController = controller
        self.presentingViewController = presentingViewController
        controller.present(from: presentingViewController)
      } catch {
        self?.finish(.failure(Self.payoutSessionError(error)))
      }
    }
  }

  func accountOnboardingDidExit(_ accountOnboarding: AccountOnboardingController) {
    finish(.success(.complete))
  }

  func accountOnboarding(
    _ accountOnboarding: AccountOnboardingController,
    didFailLoadWithError error: Error
  ) {
    presentingViewController?.dismiss(animated: true)
    finish(.failure(error))
  }

  private func finish(_ result: Result<CaptroPayoutOnboardingAction, Error>) {
    let handler = self.completion
    self.completion = nil
    accountOnboardingController = nil
    embeddedComponentManager = nil
    presentingViewController = nil
    handler?(result)
  }

  nonisolated private static func isValid(
    _ session: CaptroPayoutAccountSession,
    expectedMode: String? = nil,
    expectedPublishableKey: String? = nil
  ) -> Bool {
    let clientSecret = session.accountSessionClientSecret
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard ["test", "live"].contains(session.mode),
          session.publishableKey.hasPrefix("pk_\(session.mode)_"),
          !clientSecret.isEmpty else {
      return false
    }
    if let expectedMode, session.mode != expectedMode { return false }
    if let expectedPublishableKey, session.publishableKey != expectedPublishableKey { return false }
    return true
  }

  private static func payoutSessionError(_ error: Error) -> Error {
    guard case let MIRAAPIError.server(_, code, _) = error,
          let code, !code.isEmpty else {
      return error
    }
    if code == "COMMERCE_PAYOUT_EMAIL_REQUIRED" {
      return CaptroPayoutOnboardingError.profileEmailRequired
    }
    if code == "CAPTRO_PAYOUT_ACCOUNT_CONFLICT" {
      return CaptroPayoutOnboardingError.payoutAccountConflict
    }
    return CaptroPayoutOnboardingError.payoutSetupUnavailable
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
