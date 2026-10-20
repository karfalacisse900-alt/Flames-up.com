import SwiftUI
import UIKit

/// A root-owned presenter, independent of auth/guest/onboarding destinations.
/// Presents above an existing sheet without dismissing its draft or navigation.
struct CaptroRecoveryPresenter: UIViewControllerRepresentable {
  @ObservedObject var session: MIRAAuthSession
  let api: MIRAAPIClient
  var ready = true
  func makeUIViewController(context: Context) -> Anchor {
    let controller = Anchor()
    controller.session = session
    controller.api = api
    controller.ready = ready
    return controller
  }
  func updateUIViewController(_ controller: Anchor, context: Context) {
    controller.session = session
    controller.api = api
    controller.ready = ready
    Task { @MainActor [weak controller] in controller?.reconcile() }
  }
  @MainActor final class Anchor: UIViewController {
    weak var session: MIRAAuthSession?
    var api: MIRAAPIClient?
    var ready = true
    private var host: UIHostingController<CaptroRecoveryForm>?
    private var waitingForTransition = false
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); reconcile() }
    func reconcile() {
      guard let session, let api, let root = view.window?.rootViewController else { return }
      guard session.passwordResetContext != nil else {
        if let host { self.host = nil; host.dismiss(animated: true) }
        return
      }
      guard ready, host == nil, !waitingForTransition else { return }
      var top = root
      while let presented = top.presentedViewController { top = presented }
      if let transition = top.transitionCoordinator {
        waitingForTransition = true
        transition.animate(alongsideTransition: nil) { [weak self] _ in
          self?.waitingForTransition = false
          self?.reconcile()
        }
        return
      }
      let controller = UIHostingController(rootView: CaptroRecoveryForm(session: session, api: api))
      controller.isModalInPresentation = true
      controller.modalPresentationStyle = .formSheet
      host = controller
      top.present(controller, animated: true)
    }
  }
}

private struct CaptroRecoveryForm: View {
  @ObservedObject var session: MIRAAuthSession
  let api: MIRAAPIClient
  @State private var password = ""
  @State private var confirmation = ""
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("Reset the password for the account linked to your recovery email. This will not switch your current account.")
          SecureField("New password", text: $password).textContentType(.newPassword)
          SecureField("Confirm password", text: $confirmation).textContentType(.newPassword)
        } footer: { Text("Use at least 8 characters. After saving, use the new password when signing in.") }
        Button("Save new password") {
          Task {
            if await session.completePasswordReset(password: password, api: api) {
              password = ""; confirmation = ""
            }
          }
        }.disabled(session.isWorking || password.count < 8 || password != confirmation)
        if session.isWorking { ProgressView("Saving password") }
        if let error = session.errorMessage { Text(error).foregroundStyle(.red) }
      }
      .navigationTitle("New password")
      .toolbar { ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { password = ""; confirmation = ""; session.clearPasswordResetContext() }
          .disabled(session.isWorking)
      } }
      .onChange(of: session.passwordResetContext) { _, _ in password = ""; confirmation = "" }
    }
  }
}
