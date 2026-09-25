import Combine
import StripeIdentity
import UIKit

enum CaptroSellerIdentityAction {
  case submitted
  case canceled
  case alreadyVerified
  case processing
}

private enum CaptroSellerIdentityError: LocalizedError {
  case invalidSession
  case noPresenter
  case missingBrandLogo

  var errorDescription: String? {
    switch self {
    case .invalidSession: return "Could not open secure identity verification. Please try again."
    case .noPresenter: return "Could not show verification right now. Please try again."
    case .missingBrandLogo: return "Captro's verification screen is unavailable. Please contact support."
    }
  }
}

/// Stripe collects documents directly. A finished sheet is only a submission;
/// the backend checks Stripe's authoritative result before enabling selling.
@MainActor
final class CaptroSellerIdentityCoordinator: ObservableObject {
  private var sheet: IdentityVerificationSheet?
  private var completion: ((Result<CaptroSellerIdentityAction, Error>) -> Void)?

  func start(api: MIRAAPIClient, completion: @escaping (Result<CaptroSellerIdentityAction, Error>) -> Void) {
    guard self.completion == nil else { return }
    self.completion = completion
    Task { [weak self] in
      do {
        let session = try await api.createSellerIdentitySession()
        guard let self else { return }
        if session.status == "verified" { self.finish(.success(.alreadyVerified)); return }
        if session.status == "processing" { self.finish(.success(.processing)); return }
        guard session.status == "requires_input",
              let presenter = self.topViewController() else {
          throw CaptroSellerIdentityError.noPresenter
        }
        let verificationSheet: IdentityVerificationSheet
        if let ephemeral = session.ephemeralKeySecret, !ephemeral.isEmpty,
           let sessionId = session.verificationSessionId {
          guard let logo = UIImage(named: "CaptroLaunchLogo") else {
            throw CaptroSellerIdentityError.missingBrandLogo
          }
          verificationSheet = IdentityVerificationSheet(
            verificationSessionId: sessionId,
            ephemeralKeySecret: ephemeral,
            configuration: .init(brandLogo: logo)
          )
        } else if let clientSecret = session.clientSecret, clientSecret.hasPrefix("vs_") {
          verificationSheet = IdentityVerificationSheet(verificationSessionClientSecret: clientSecret)
        } else {
          throw CaptroSellerIdentityError.invalidSession
        }
        self.sheet = verificationSheet
        verificationSheet.present(from: presenter) { [weak self] result in
          Task { @MainActor [weak self] in
            guard let self else { return }
            switch result {
            case .flowCompleted: self.finish(.success(.submitted))
            case .flowCanceled: self.finish(.success(.canceled))
            case .flowFailed(let error): self.finish(.failure(error))
            }
          }
        }
      } catch {
        self?.finish(.failure(error))
      }
    }
  }

  private func finish(_ result: Result<CaptroSellerIdentityAction, Error>) {
    let callback = completion
    completion = nil
    sheet = nil
    callback?(result)
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
    let root = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
    return topViewController(from: root)
  }

  private func topViewController(from root: UIViewController?) -> UIViewController? {
    if let presented = root?.presentedViewController { return topViewController(from: presented) }
    if let navigation = root as? UINavigationController { return topViewController(from: navigation.visibleViewController) }
    if let tabs = root as? UITabBarController { return topViewController(from: tabs.selectedViewController) }
    return root
  }
}
