import SwiftUI
import StoreKit
import UIKit

private struct CaptroSupportViewerKey: EnvironmentKey { static let defaultValue: String? = nil }
struct CaptroSupportRuntime {
  var enabled = CaptroSupportPolicy.enabled
  var currentStorefront: () async -> String? = { (await Storefront.current)?.countryCode }
  var openBrowser: (URL) async -> Bool = { await UIApplication.shared.open($0) }
}
private struct CaptroSupportRuntimeKey: EnvironmentKey { static let defaultValue = CaptroSupportRuntime() }
extension EnvironmentValues {
  var captroSupportViewerID: String? {
    get { self[CaptroSupportViewerKey.self] }
    set { self[CaptroSupportViewerKey.self] = newValue }
  }
  var captroSupportRuntime: CaptroSupportRuntime {
    get { self[CaptroSupportRuntimeKey.self] }
    set { self[CaptroSupportRuntimeKey.self] = newValue }
  }
}
enum CaptroSupportPolicy {
  // No enabled value is shipped. Provider approval, storefront review, associated
  // domains and physical browser-return acceptance are independent release gates.
  static var enabled: Bool { Bundle.main.object(forInfoDictionaryKey: "CaptroCreatorSupportEnabled") as? Bool == true }
  static func permits(storefront: String?) -> Bool { storefront == "USA" }
  static func recipientName(_ preferred: String?, fallback: String) -> String {
    let clean = preferred?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return clean.isEmpty ? fallback : clean
  }
  static func amount(_ text: String, locale: Locale = .current) -> Int? {
    guard let value = CaptroMoney.parse(text, currency: "USD", locale: locale), (200...20_000).contains(value) else { return nil }
    return value
  }
  static func handoffURL(_ raw: String, amount: Int) -> URL? {
    guard (200...20_000).contains(amount), var parts = URLComponents(string: raw),
parts.scheme == "https", parts.host == "captro-site.pages.dev", parts.port == nil,
      parts.user == nil, parts.password == nil, parts.path == "/support-creator/", parts.query == nil,
      let fragment = parts.fragment, fragment.hasPrefix("handoff="),
      fragment.dropFirst(8).count == 64,
      fragment.dropFirst(8).allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
    parts.fragment = fragment + "&amount=\(amount)"
    return parts.url
  }
  static func returnPurchase(_ url: URL) -> String? {
guard url.scheme == "https", url.host == "captro-site.pages.dev", url.port == nil,
      url.user == nil, url.password == nil, url.path == "/support-creator/return",
      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    let ids = (parts.queryItems ?? []).filter { $0.name == "purchase_id" }
    guard ids.count == 1, let value = ids.first?.value, UUID(uuidString: value) != nil else { return nil }
    return value
  }
}
extension Notification.Name { static let captroSupportReturned = Notification.Name("captro.support.returned") }

/// The entry point stays discoverable in supported storefronts. Checkout itself
/// remains disabled unless the build and server both authorize the test flow.
struct CaptroSupportAction: View {
  let creatorID: String
  let name: String
  let username: String
  let avatar: String?
  let api: MIRAAPIClient
  var originPostID: String? = nil
  @Environment(\.captroSupportViewerID) private var viewerID
  @Environment(\.captroSupportRuntime) private var runtime
  @State private var canCheckout = false
  @State private var checking = false
  @State private var visibleInStorefront = false
  @State private var failed = false
  @State private var retry = 0
  @State private var presented = false
  @State private var unavailableMessage = "No payment was started."
  private var identity: String { "\(viewerID ?? "guest"):\(creatorID)" }
  private struct Eligibility: Decodable { let enabled: Bool }
  var body: some View {
    // The task decides visibility from the real storefront and viewer identity.
    ZStack {
      Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
      if visibleInStorefront {
        Button(failed ? "Retry Support" : "Support") {
          CaptroHaptics.light()
          if failed { retry += 1 }
          else { presented = true }
        }
          .font(.subheadline.weight(.semibold))
          .frame(minWidth: 64, minHeight: 44)
          .padding(.horizontal, 8)
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .background(MIRATheme.Color.surface)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(MIRATheme.Color.hairline))
          .accessibilityIdentifier("creator.support")
          .accessibilityValue(canCheckout ? "Available" : "Not available")
          .accessibilityHint(failed ? "Availability could not be checked. Tries again without starting a payment." :
            canCheckout ? "Opens one-time support options" : "Support checkout is not available yet. No payment will be started.")
          .disabled(checking)
      }
    }
    .task(id: "\(identity):\(retry)") {
      let expected = identity
      canCheckout = false; failed = false; presented = false; checking = false
      visibleInStorefront = false
      guard let viewerID, viewerID != creatorID else { return }
      let storefront = await runtime.currentStorefront()
      guard !Task.isCancelled, expected == identity, CaptroSupportPolicy.permits(storefront: storefront) else { return }
      // Live payment remains off. Keep the real entry point visible and tell the
      // user plainly instead of silently removing it from the profile/Details UI.
      guard runtime.enabled else {
        visibleInStorefront = true
        unavailableMessage = "Captro has not enabled Support checkout yet. No payment can be made right now."
        return
      }
      // Keep the layout stable while the server verifies the creator. The
      // button is visible but temporarily disabled until that answer arrives.
      visibleInStorefront = true
      await refreshEligibility(expected: expected)
      for await _ in Storefront.updates {
        guard !Task.isCancelled else { return }
        await refreshEligibility(expected: expected)
      }
    }
    .sheet(isPresented: $presented) {
      CaptroSupportSheet(creatorID: creatorID, name: name, username: username, avatar: avatar, api: api, originPostID: originPostID,
        checkoutAvailable: canCheckout, unavailableMessage: unavailableMessage,
        currentStorefront: runtime.currentStorefront, openBrowser: runtime.openBrowser)
        .id(identity)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }
  }
  private func refreshEligibility(expected: String) async {
    checking = true
    defer { checking = false }
    guard !Task.isCancelled, expected == identity else { return }
    do {
      let result: Eligibility = try await api.get("/creator-support/eligibility/\(creatorID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")")
      guard !Task.isCancelled, expected == identity else { return }
      failed = false; canCheckout = result.enabled
      if !canCheckout {
        presented = false
        unavailableMessage = "This creator can’t receive Support through Captro yet. They can check their exact setup requirements in Earnings. No payment was started."
      }
    } catch {
      guard !Task.isCancelled, expected == identity else { return }
      canCheckout = false; failed = true; presented = false
      unavailableMessage = "Support availability couldn’t be checked. Please retry; no payment was started."
    }
  }
}

struct CaptroSupportSheet: View {
  let creatorID: String
  let name: String
  let username: String
  let avatar: String?
  let api: MIRAAPIClient
  let originPostID: String?
  var checkoutAvailable = false
  var unavailableMessage = "Support checkout is not available yet. No payment will be taken."
  var currentStorefront: () async -> String? = { (await Storefront.current)?.countryCode }
  var openBrowser: (URL) async -> Bool = { await UIApplication.shared.open($0) }
  @EnvironmentObject private var returns: CaptroSupportReturnStore
  @Environment(\.captroSupportViewerID) private var viewerID
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var textSize
  @State private var amount: Int?
  @State private var custom = ""
  @State private var usesCustom = false
  @State private var busy = false
  @State private var notice: String?
  @State private var handoffID: String?
  @State private var requestKey = UUID().uuidString
  @State private var operationTask: Task<Void, Never>?
  @State private var terminal = false
  private struct HandoffBody: Encodable { let creator_id: String; let request_key: String; let storefront: String }
  private struct Handoff: Decodable { let id: String; let url: String }
  private struct Status: Decodable { let status: String }
  private var selected: Int? { usesCustom ? CaptroSupportPolicy.amount(custom) : amount }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          RemoteAvatar(url: avatar, size: 64)
          VStack(spacing: 4) {
            Text("Support \(name)").font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text(username.hasPrefix("@") ? username : "@\(username)").foregroundStyle(.secondary)
          }
          Text("Send one-time support for their work.").foregroundStyle(.secondary).multilineTextAlignment(.center)
          Text(checkoutAvailable ? "Test environment — no real payments." : unavailableMessage)
            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
          VStack(alignment: .leading, spacing: 10) {
            Text("Amount (USD)").font(.subheadline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: textSize.isAccessibilitySize ? 2 : 4), spacing: 10) {
              ForEach([200, 500, 1000, 2000], id: \.self) { value in
                Button { usesCustom = false; amount = value } label: {
                  Text(CaptroMoney.format(minorUnits: value, currency: "USD")).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(CaptroSupportOptionStyle(selected: selected == value))
                .accessibilityAddTraits(selected == value ? [.isSelected] : [])
                .accessibilityIdentifier("support.amount.\(value)")
              }
            }
            Button { usesCustom = true } label: { Text("Other amount").frame(maxWidth: .infinity, minHeight: 44) }
              .buttonStyle(CaptroSupportOptionStyle(selected: usesCustom))
              .accessibilityAddTraits(usesCustom ? [.isSelected] : [])
            if usesCustom {
              TextField("2.00–200.00 USD", text: $custom).keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Custom support amount in US dollars")
                .accessibilityIdentifier("support.custom")
              if !custom.isEmpty && selected == nil {
                Text("Enter $2–$200 with no more than two decimal places.")
                  .font(.footnote).foregroundStyle(.secondary)
              }
            }
          }.disabled(busy || handoffID != nil)
          Text("Captro takes 0%. Payment-processing fees apply.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
          if let notice { Text(notice).font(.subheadline).multilineTextAlignment(.center).accessibilityIdentifier("support.status") }
          Button { operationTask = Task { await continueInBrowser() } } label: {
            Group { if busy { ProgressView() } else { Text(handoffID == nil ? "Continue to secure checkout" : "Return to checkout") } }
              .frame(maxWidth: .infinity, minHeight: 44)
          }.buttonStyle(CaptroSupportCheckoutStyle()).disabled(selected == nil || busy || terminal || !checkoutAvailable)
            .accessibilityIdentifier("support.checkout")
          Label("Opens in your browser", systemImage: "arrow.up.right.square").font(.footnote).foregroundStyle(.secondary)
          if handoffID != nil {
            Button("Check payment status") { Task { await checkStatus() } }.frame(minHeight: 44).disabled(busy)
          }
        }.padding(24)
      }
      .background(Color(uiColor: .systemBackground))
      .toolbar { ToolbarItem(placement: .topBarTrailing) {
        Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Close")
      } }
    }
    .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await checkStatus() } } }
    .onReceive(NotificationCenter.default.publisher(for: .captroSupportReturned)) { _ in Task { await checkStatus() } }
    .onDisappear { operationTask?.cancel() }
  }
  private func continueInBrowser() async {
    guard !busy, let selected else { return }
    busy = true; notice = nil; defer { busy = false }
    guard checkoutAvailable else { notice = unavailableMessage; return }
    guard CaptroSupportPolicy.permits(storefront: await currentStorefront()), !Task.isCancelled else {
      notice = "External support is not available for this App Store storefront."; return
    }
    do {
      let handoff: Handoff = try await api.post("/creator-support/handoffs", body: HandoffBody(creator_id: creatorID, request_key: requestKey, storefront: "USA"))
      guard let url = CaptroSupportPolicy.handoffURL(handoff.url, amount: selected), !Task.isCancelled else { throw MIRAAPIError.badURL }
      guard let viewerID else { throw MIRAAPIError.badURL }
      returns.remember(handoffID: handoff.id, buyerID: viewerID, creatorID: creatorID, postID: originPostID)
      // System browser, never PaymentSheet or an embedded web view.
      guard await openBrowser(url) else { throw MIRAAPIError.badURL }
      handoffID = handoff.id
      notice = "Continue in your browser. Payment is not confirmed yet."
    } catch { notice = "Could not open secure checkout. Please try again." }
  }
  private func checkStatus() async {
    guard !busy, let handoffID else { return }
    busy = true; defer { busy = false }
    do {
      let result: Status = try await api.get("/creator-support/handoffs/\(handoffID)/status")
      terminal = ["confirmed", "refunded", "partially_refunded", "cancelled", "expired", "disputed", "under_review"].contains(result.status)
      switch result.status {
      case "confirmed": notice = "Support confirmed. Thank you."
      case "refunded": notice = "This support payment was refunded."
      case "partially_refunded": notice = "This support payment was partially refunded."
      case "disputed": notice = "This payment is disputed. Its outcome is being reviewed."
      case "under_review": notice = "Payment received and under review. Please do not pay again."
      case "cancelled", "expired": notice = "Checkout ended without a confirmed payment."
      case "not_started": notice = "No payment has been started."
      default: notice = "Confirming payment. Please check again shortly."
      }
    } catch { notice = "Could not check payment status. Please retry before starting another payment." }
  }
}

private struct CaptroSupportOptionStyle: ButtonStyle {
  let selected: Bool
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.subheadline.weight(.semibold))
      .foregroundStyle(Color.primary)
      .background(selected ? Color.primary.opacity(0.06) : Color(uiColor: .systemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.primary : Color.secondary.opacity(0.3), lineWidth: selected ? 1.5 : 1))
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}
private struct CaptroSupportCheckoutStyle: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.subheadline.weight(.semibold)).padding(.vertical, 4)
      .foregroundStyle(enabled ? Color(uiColor: .systemBackground) : Color.secondary)
      .background(enabled ? Color.primary : Color.secondary.opacity(0.16))
      .clipShape(RoundedRectangle(cornerRadius: 8)).opacity(configuration.isPressed ? 0.7 : 1)
  }
}
