import SwiftUI
import UIKit

/// Only opaque navigation references persist. Never a browser bearer, amount,
/// account credential, or cached assertion that payment succeeded.
struct CaptroSupportOrigin: Codable, Equatable {
  let handoffID: String
  let buyerID: String
  let creatorID: String
  let postID: String?
  let createdAt: Date
}

@MainActor final class CaptroSupportReturnStore: ObservableObject {
  @Published var pendingPurchaseID: String?
  private let defaults: UserDefaults
  private let clock: () -> Date
  private let key = "captro.support.origin.v1"
  init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init) {
    self.defaults = defaults; self.clock = clock
  }
  private var recent: [CaptroSupportOrigin] {
    guard let data = defaults.data(forKey: key),
      let values = try? JSONDecoder().decode([CaptroSupportOrigin].self, from: data) else { return [] }
    return values.filter { clock().timeIntervalSince($0.createdAt) >= 0 && clock().timeIntervalSince($0.createdAt) < 7 * 86400 }
  }
  func remember(handoffID: String, buyerID: String, creatorID: String, postID: String?) {
    guard UUID(uuidString: handoffID) != nil, !buyerID.isEmpty, !creatorID.isEmpty else { return }
    var values = recent.filter { $0.handoffID != handoffID }
    values.insert(CaptroSupportOrigin(handoffID: handoffID, buyerID: buyerID, creatorID: creatorID, postID: postID, createdAt: clock()), at: 0)
    if let data = try? JSONEncoder().encode(Array(values.prefix(8))) { defaults.set(data, forKey: key) }
  }
  func origin(handoffID: String?, buyerID: String) -> CaptroSupportOrigin? {
    recent.first { $0.handoffID == handoffID && $0.buyerID == buyerID }
  }
  func forget(accountID: String) {
    if let data = try? JSONEncoder().encode(recent.filter { $0.buyerID != accountID }) { defaults.set(data, forKey: key) }
    pendingPurchaseID = nil
  }
}

/// Like password recovery, this presenter does not dismiss another sheet/draft
/// or change the selected feed tab. It also works after a cold launch.
struct CaptroSupportReturnPresenter: UIViewControllerRepresentable {
  @ObservedObject var store: CaptroSupportReturnStore
  @ObservedObject var session: MIRAAuthSession
  let api: MIRAAPIClient
  let ready: Bool
  func makeUIViewController(context: Context) -> Anchor { Anchor() }
  func updateUIViewController(_ controller: Anchor, context: Context) {
    controller.value = self
    Task { @MainActor [weak controller] in controller?.reconcile() }
  }
  @MainActor final class Anchor: UIViewController {
    var value: CaptroSupportReturnPresenter?
    private var host: UIHostingController<CaptroSupportReceipt>?
    private var transitioning = false
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); reconcile() }
    func reconcile() {
      guard let value, let root = view.window?.rootViewController else { return }
      guard let id = value.store.pendingPurchaseID else {
        if let host { self.host = nil; host.dismiss(animated: true) }; return
      }
      guard value.ready, value.session.passwordResetContext == nil else { return }
      let receipt = CaptroSupportReceipt(purchaseID: id, accountID: value.session.user?.id, api: value.api, store: value.store)
      if let host { host.rootView = receipt; return }
      guard !transitioning else { return }
      var top = root
      while let presented = top.presentedViewController { top = presented }
      if let transition = top.transitionCoordinator {
        transitioning = true
        transition.animate(alongsideTransition: nil) { [weak self] _ in self?.transitioning = false; self?.reconcile() }
        return
      }
      let controller = UIHostingController(rootView: receipt)
      controller.isModalInPresentation = true; controller.modalPresentationStyle = .formSheet
      host = controller; top.present(controller, animated: true)
    }
  }
}

private struct CaptroSupportReceipt: View {
  let purchaseID: String
  let accountID: String?
  let api: MIRAAPIClient
  @ObservedObject var store: CaptroSupportReturnStore
  @State private var status = "Checking payment…"
  @State private var origin: CaptroSupportOrigin?
  @State private var retry = 0
  private struct Receipt: Decodable { let id: String; let status: String; let handoffId: String? }
  var body: some View {
    NavigationStack {
      List {
        Text(status).accessibilityIdentifier("support.return.status")
        if accountID != nil { Button("Check again") { retry += 1 }.frame(minHeight: 44) }
        if let origin {
          NavigationLink(origin.postID == nil ? "Return to creator" : "Return to post") {
            CaptroSupportOriginView(origin: origin, api: api)
              .environmentObject(store).environmentObject(MIRALocalization.shared)
              .environment(\.captroSupportViewerID, accountID)
          }
        }
      }.navigationTitle("Support payment")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { store.pendingPurchaseID = nil } } }
    }
    .task(id: "\(accountID ?? "guest"):\(purchaseID):\(retry)") {
      origin = nil
      guard let accountID else { status = "Sign in to the account that started this payment, then reopen the return link. No account has been switched."; return }
      status = "Checking payment…"
      do {
        let receipt: Receipt = try await api.get("/creator-support/purchases/\(purchaseID)")
        guard !Task.isCancelled, receipt.id.caseInsensitiveCompare(purchaseID) == .orderedSame else { return }
        origin = store.origin(handoffID: receipt.handoffId, buyerID: accountID)
        switch receipt.status {
        case "confirmed": status = "Support confirmed. Thank you."
        case "refunded": status = "This support payment was refunded."
        case "partially_refunded": status = "This support payment was partially refunded."
        case "disputed": status = "This payment is disputed and is being reviewed."
        case "under_review": status = "Payment received and under review. Please do not pay again."
        case "expired", "cancelled": status = "Checkout ended without a confirmed payment."
        default: status = "Confirming payment. Check again shortly; do not start another payment."
        }
      } catch {
        guard !Task.isCancelled else { return }
        status = "Could not verify this payment. Check your connection and that you are signed in to the account that started it."
      }
    }
  }
}

private struct CaptroSupportOriginView: View {
  let origin: CaptroSupportOrigin
  let api: MIRAAPIClient
  @State private var post: MIRAPost?
  @State private var failed = false
  @State private var retry = 0
  var body: some View {
    Group {
      if origin.postID == nil { UserProfileNativeView(userId: origin.creatorID, api: api) }
      else if let post { PostDetailNativeView(post: post, api: api) }
      else if failed {
        VStack { Text("This post could not be opened. It may be unavailable or your connection may need to recover."); Button("Try again") { retry += 1 } }.padding()
      } else { ProgressView("Loading post") }
    }
    .task(id: retry) {
      guard let id = origin.postID else { return }; failed = false
      do {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let result: MIRAPost = try await api.get("/posts/\(encoded)")
        guard !Task.isCancelled else { return }; post = result
      } catch { if !Task.isCancelled { failed = true } }
    }
  }
}
