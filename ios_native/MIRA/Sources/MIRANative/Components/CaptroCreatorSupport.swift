import SwiftUI
import StoreKit
import UIKit

private struct CaptroSupportViewerKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
  var captroSupportViewerID: String? {
    get { self[CaptroSupportViewerKey.self] }
    set { self[CaptroSupportViewerKey.self] = newValue }
  }
}
enum CaptroSupportPolicy {
  // No enabled value is shipped. Provider approval, storefront review, associated
  // domains and physical browser-return acceptance are independent release gates.
  static var enabled: Bool { Bundle.main.object(forInfoDictionaryKey: "CaptroCreatorSupportEnabled") as? Bool == true }
  static func permits(storefront: String?) -> Bool { storefront == "USA" }
  static func amount(_ text: String, locale: Locale = .current) -> Int? {
    guard let value = CaptroMoney.parse(text, currency: "USD", locale: locale), (200...20_000).contains(value) else { return nil }
    return value
  }
  static func handoffURL(_ raw: String, amount: Int) -> URL? {
    guard (200...20_000).contains(amount), var parts = URLComponents(string: raw),
      parts.scheme == "https", parts.host == "flames-up.com", parts.port == nil,
      parts.user == nil, parts.password == nil, parts.path == "/support-creator/", parts.query == nil,
      let fragment = parts.fragment, fragment.hasPrefix("handoff="),
      fragment.dropFirst(8).count == 64,
      fragment.dropFirst(8).allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
    parts.fragment = fragment + "&amount=\(amount)"
    return parts.url
  }
  static func returnPurchase(_ url: URL) -> String? {
    guard url.scheme == "https", url.host == "flames-up.com", url.port == nil,
      url.user == nil, url.password == nil, url.path == "/support-creator/return",
      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    let ids = (parts.queryItems ?? []).filter { $0.name == "purchase_id" }
    guard ids.count == 1, let value = ids.first?.value, UUID(uuidString: value) != nil else { return nil }
    return value
  }
}
extension Notification.Name { static let captroSupportReturned = Notification.Name("captro.support.returned") }

/// Hidden unless native storefront AND server eligibility both allow it. No Home integration.
struct CaptroSupportAction: View {
  let creatorID: String
  let name: String
  let username: String
  let avatar: String?
  let api: MIRAAPIClient
  var originPostID: String? = nil
  @Environment(\.captroSupportViewerID) private var viewerID
  @State private var eligible = false
  @State private var presented = false
  private struct Eligibility: Decodable { let enabled: Bool }
  var body: some View {
    Group {
      if eligible {
        Button("Support") { presented = true }
          .font(.subheadline.weight(.semibold))
          .frame(minWidth: 64, minHeight: 44)
          .padding(.horizontal, 8)
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .background(MIRATheme.Color.surface)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(MIRATheme.Color.hairline))
          .accessibilityIdentifier("creator.support")
      }
    }
    .task(id: "\(viewerID ?? "guest"):\(creatorID)") {
      eligible = false; presented = false
      guard CaptroSupportPolicy.enabled, let viewerID, viewerID != creatorID else { return }
      await refreshEligibility()
      for await _ in Storefront.updates {
        guard !Task.isCancelled else { return }
        await refreshEligibility()
      }
    }
    .sheet(isPresented: $presented) {
      CaptroSupportSheet(creatorID: creatorID, name: name, username: username, avatar: avatar, api: api, originPostID: originPostID)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }
  }
  private func refreshEligibility() async {
    guard CaptroSupportPolicy.permits(storefront: (await Storefront.current)?.countryCode) else {
      eligible = false; presented = false; return
    }
    do {
      let result: Eligibility = try await api.get("/creator-support/eligibility/\(creatorID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")")
      guard !Task.isCancelled else { return }; eligible = result.enabled
      if !eligible { presented = false }
    } catch { eligible = false; presented = false }
  }
}

private struct CaptroSupportSheet: View {
  let creatorID: String
  let name: String
  let username: String
  let avatar: String?
  let api: MIRAAPIClient
  let originPostID: String?
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
          Text("Test environment — no real payments.").font(.caption).foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 10) {
            Text("Amount (USD)").font(.subheadline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: textSize.isAccessibilitySize ? 2 : 4), spacing: 10) {
              ForEach([200, 500, 1000, 2000], id: \.self) { value in
                Button { usesCustom = false; amount = value } label: {
                  Text(CaptroMoney.format(minorUnits: value, currency: "USD")).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(selected == value ? .primary : .secondary)
                .accessibilityAddTraits(selected == value ? [.isSelected] : [])
              }
            }
            Button("Other amount") { usesCustom = true }.buttonStyle(.bordered).frame(minHeight: 44)
            if usesCustom {
              TextField("2.00–200.00 USD", text: $custom).keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Custom support amount in US dollars")
            }
          }.disabled(busy || handoffID != nil)
          Text("Captro takes 0%. Payment-processing fees apply.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
          if let notice { Text(notice).font(.subheadline).multilineTextAlignment(.center).accessibilityIdentifier("support.status") }
          Button { operationTask = Task { await continueInBrowser() } } label: {
            Group { if busy { ProgressView() } else { Text(handoffID == nil ? "Continue to secure checkout" : "Return to checkout") } }
              .frame(maxWidth: .infinity, minHeight: 44)
          }.buttonStyle(.borderedProminent).tint(.primary).disabled(selected == nil || busy || terminal)
          Label("Opens in your browser", systemImage: "arrow.up.right.square").font(.footnote).foregroundStyle(.secondary)
          if handoffID != nil {
            Button("Check payment status") { Task { await checkStatus() } }.frame(minHeight: 44).disabled(busy)
          }
        }.padding(24)
      }
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
    }
    .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await checkStatus() } } }
    .onReceive(NotificationCenter.default.publisher(for: .captroSupportReturned)) { _ in Task { await checkStatus() } }
    .onDisappear { operationTask?.cancel() }
  }
  private func continueInBrowser() async {
    guard !busy, let selected else { return }
    busy = true; notice = nil; defer { busy = false }
    guard CaptroSupportPolicy.permits(storefront: (await Storefront.current)?.countryCode), !Task.isCancelled else {
      notice = "External support is not available for this App Store storefront."; return
    }
    do {
      let handoff: Handoff = try await api.post("/creator-support/handoffs", body: HandoffBody(creator_id: creatorID, request_key: requestKey, storefront: "USA"))
      guard let url = CaptroSupportPolicy.handoffURL(handoff.url, amount: selected), !Task.isCancelled else { throw MIRAAPIError.badURL }
      guard let viewerID else { throw MIRAAPIError.badURL }
      returns.remember(handoffID: handoff.id, buyerID: viewerID, creatorID: creatorID, postID: originPostID)
      // System browser, never PaymentSheet or an embedded web view.
      guard await UIApplication.shared.open(url) else { throw MIRAAPIError.badURL }
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
