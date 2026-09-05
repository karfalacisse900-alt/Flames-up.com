import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

enum CaptroCommerceQRCode {
  static func image(for value: String) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(value.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage,
          let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
    return UIImage(cgImage: image)
  }
}

struct CaptroCommerceDashboardView: View {
  let dashboard: CaptroCommerceDashboard
  let api: MIRAAPIClient
  let onDecision: (String, Bool) async -> Void
  @State private var passPresentation: CaptroDashboardPassPresentation?
  @State private var isLoadingPass = false
  @State private var isShowingScanner = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 26) {
      if !dashboard.myStuff.isEmpty { myStuff }
      if !dashboard.pendingRequests.isEmpty { approvals }
      if !dashboard.created.isEmpty { created }
    }
    .sheet(item: $passPresentation) { presentation in
      CaptroDashboardPassView(presentation: presentation)
    }
    .sheet(isPresented: $isShowingScanner) { CaptroPassScannerSheet(api: api) }
    .alert("Couldn't complete that action", isPresented: Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
  }

  private var myStuff: some View {
    VStack(alignment: .leading, spacing: 12) {
      dashboardHeading("My Stuff")
      ForEach(myStuffSections, id: \.0) { title, purchases in
        sectionLabel(title)
        ForEach(purchases) { purchase in
          purchaseRow(purchase)
          thinDivider
        }
      }
    }
    .padding(.horizontal, 16)
  }

  private var approvals: some View {
    VStack(alignment: .leading, spacing: 12) {
      dashboardHeading("Requests")
      ForEach(dashboard.pendingRequests) { purchase in
        VStack(alignment: .leading, spacing: 10) {
          Text(purchase.itemTitle).font(.system(size: 15, weight: .semibold))
          Text("\(purchase.priceLabel) · \(purchase.totalAmount == 0 ? "Free" : purchase.totalLabel)")
            .font(.system(size: 12)).foregroundStyle(CaptroDetailStyle.secondary)
          HStack(spacing: 10) {
            Button("Decline") { Task { await onDecision(purchase.id, false) } }
              .frame(maxWidth: .infinity, minHeight: 40)
              .overlay(Rectangle().stroke(CaptroDetailStyle.divider, lineWidth: 1))
            Button("Approve") { Task { await onDecision(purchase.id, true) } }
              .frame(maxWidth: .infinity, minHeight: 40)
              .foregroundStyle(.white).background(CaptroDetailStyle.accent)
          }
          .buttonStyle(.plain)
          .font(.system(size: 13, weight: .semibold))
        }
        thinDivider
      }
    }
    .padding(.horizontal, 16)
  }

  private var created: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        dashboardHeading("Created")
        Spacer()
        if dashboard.created.contains(where: { $0.commerce.passRequired || ["ticket", "redemption"].contains($0.commerce.fulfillmentType) }) {
          Button { isShowingScanner = true } label: {
            Label("Scan pass", systemImage: "qrcode.viewfinder")
              .font(.system(size: 13, weight: .semibold)).frame(minHeight: 44)
          }
          .buttonStyle(.plain)
        }
      }
      ForEach(createdSections, id: \.0) { title, items in
        sectionLabel(title)
        ForEach(items) { item in
          creatorRow(item)
          thinDivider
        }
      }
    }
    .padding(.horizontal, 16)
  }

  private func purchaseRow(_ purchase: CaptroCommercePurchase) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: purchaseIcon(purchase.fulfillmentType))
        .font(.system(size: 17)).frame(width: 34, height: 34)
        .background(CaptroDetailStyle.accent.opacity(0.10)).clipShape(Circle())
      VStack(alignment: .leading, spacing: 4) {
        Text(purchase.itemTitle).font(.system(size: 14, weight: .semibold)).lineLimit(2)
        Text(purchaseStatus(purchase)).font(.system(size: 11, weight: .medium))
          .foregroundStyle(CaptroDetailStyle.secondary)
      }
      Spacer(minLength: 8)
      if let entitlement = purchase.entitlement {
        if let destinationId = entitlement.destinationId,
           ["membership", "group_access"].contains(entitlement.kind) {
          NavigationLink {
            ConversationNativeView(groupId: destinationId, title: purchase.itemTitle, api: api)
              .miraHideTabBarOnAppear()
          } label: {
            Image(systemName: "arrow.up.right").frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Open (purchase.itemTitle)")
        } else if entitlement.hasPass == true || ["ticket", "redemption"].contains(entitlement.kind) {
          Button { Task { await openPass(purchase, entitlementId: entitlement.id) } } label: {
            if isLoadingPass { ProgressView().frame(width: 44, height: 44) }
            else { Image(systemName: "qrcode").frame(width: 44, height: 44) }
          }
          .buttonStyle(.plain)
          .accessibilityLabel("View pass")
        }
      }
    }
    .frame(minHeight: 54)
  }

  private func creatorRow(_ item: CaptroCreatedCommerce) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(item.commerce.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
        Spacer(minLength: 8)
        Text(item.commerce.status.replacingOccurrences(of: "_", with: " ").uppercased())
          .font(.system(size: 10, weight: .bold)).foregroundStyle(CaptroDetailStyle.secondary)
      }
      HStack(spacing: 14) {
        metric("Sold", item.sold)
        if let capacity = item.commerce.capacity { metric("Capacity", capacity) }
        if (item.checkedIn ?? 0) > 0 { metric("Checked in", item.checkedIn ?? 0) }
        if (item.redeemed ?? 0) > 0 { metric("Redeemed", item.redeemed ?? 0) }
        if (item.paidMembers ?? 0) > 0 { metric("Paid", item.paidMembers ?? 0) }
      }
      HStack {
        Text("Sales").font(.system(size: 11)).foregroundStyle(CaptroDetailStyle.secondary)
        Spacer()
        Text(CaptroMoney.format(minorUnits: item.grossAmount, currency: item.currency))
          .font(.system(size: 13, weight: .semibold))
      }
      if let available = item.availableEarningsAmount {
        HStack {
          Text("Available earnings").font(.system(size: 11)).foregroundStyle(CaptroDetailStyle.secondary)
          Spacer()
          Text(CaptroMoney.format(minorUnits: available, currency: item.currency))
            .font(.system(size: 13, weight: .semibold))
        }
      }
      if item.pendingApprovals > 0 {
        Text("\(item.pendingApprovals) request\(item.pendingApprovals == 1 ? "" : "s") waiting")
          .font(.system(size: 11, weight: .semibold)).foregroundStyle(CaptroDetailStyle.accent)
      }
    }
    .padding(.vertical, 6)
  }

  private func metric(_ title: String, _ value: Int) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("\(value)").font(.system(size: 14, weight: .semibold))
      Text(title).font(.system(size: 10)).foregroundStyle(CaptroDetailStyle.secondary)
    }
  }

  private func openPass(_ purchase: CaptroCommercePurchase, entitlementId: String) async {
    guard !isLoadingPass else { return }
    isLoadingPass = true
    defer { isLoadingPass = false }
    do {
      let response = try await api.loadCommercePass(entitlementId: entitlementId)
      guard let pass = response.pass else {
        errorMessage = "This item does not require a scannable pass."
        return
      }
      passPresentation = CaptroDashboardPassPresentation(purchase: purchase, pass: pass)
    } catch {
      errorMessage = (error as? MIRAAPIError)?.errorDescription ?? "Could not load this pass."
    }
  }

  private var myStuffSections: [(String, [CaptroCommercePurchase])] {
    let order = ["ticket", "membership", "group_access", "attendance", "redemption", "order", "reservation"]
    let labels = ["ticket": "TICKETS", "membership": "CLUBS", "group_access": "GROUPS",
      "attendance": "MEETUPS", "redemption": "DEALS", "order": "ORDERS", "reservation": "BOOKINGS"]
    let grouped = Dictionary(grouping: dashboard.myStuff, by: \.fulfillmentType)
    return order.compactMap { key in grouped[key].map { (labels[key] ?? key.uppercased(), $0) } }
  }

  private var createdSections: [(String, [CaptroCreatedCommerce])] {
    let order = ["event", "party", "ticket", "club", "group", "meetup", "deal", "offer", "booking", "reservation"]
    let grouped = Dictionary(grouping: dashboard.created, by: { $0.commerce.contentType })
    return order.compactMap { key in
      grouped[key].map { (key == "reservation" ? "BOOKINGS" : key.uppercased() + "S", $0) }
    }
  }

  private func dashboardHeading(_ value: String) -> some View {
    Text(value).font(.system(size: 20, weight: .bold)).accessibilityAddTraits(.isHeader)
  }

  private func sectionLabel(_ value: String) -> some View {
    Text(value).font(.system(size: 11, weight: .bold)).foregroundStyle(CaptroDetailStyle.secondary).padding(.top, 4)
  }

  private var thinDivider: some View { Rectangle().fill(CaptroDetailStyle.divider).frame(height: 0.5) }

  private func purchaseIcon(_ kind: String) -> String {
    switch kind {
    case "ticket": return "ticket"
    case "membership", "group_access": return "person.2"
    case "attendance": return "calendar.badge.checkmark"
    case "redemption": return "tag"
    case "reservation": return "calendar"
    default: return "shippingbox"
    }
  }

  private func purchaseStatus(_ purchase: CaptroCommercePurchase) -> String {
    let status = purchase.entitlement?.status ?? purchase.status
    return [purchase.contentType.capitalized, status.replacingOccurrences(of: "_", with: " ").capitalized].joined(separator: " · ")
  }
}

struct CaptroDashboardPassPresentation: Identifiable {
  let purchase: CaptroCommercePurchase
  let pass: CaptroCommercePass
  var id: String { pass.id }
}

private struct CaptroDashboardPassView: View {
  @Environment(\.dismiss) private var dismiss
  let presentation: CaptroDashboardPassPresentation

  var body: some View {
    NavigationStack {
      VStack(spacing: 18) {
        Text(presentation.pass.kind == "redemption" ? "REDEMPTION PASS" : "ACCESS PASS")
          .font(.system(size: 11, weight: .bold)).foregroundStyle(CaptroDetailStyle.accent)
        Text(presentation.purchase.itemTitle).font(.system(size: 24, weight: .bold)).multilineTextAlignment(.center)
        if let image = CaptroCommerceQRCode.image(for: presentation.pass.token) {
          Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
            .frame(width: 210, height: 210).padding(12).background(Color.white)
        }
        Text(presentation.pass.tier ?? presentation.purchase.priceLabel).font(.system(size: 13, weight: .bold))
        Text(presentation.pass.code).font(.system(size: 15, weight: .semibold)).monospaced()
        Text(presentation.pass.status.replacingOccurrences(of: "_", with: " ").uppercased())
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(presentation.pass.status == "active" ? MIRATheme.Color.forest : CaptroDetailStyle.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity).padding(24).background(Color.white).privacySensitive()
      .navigationTitle("Pass").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }
}

private struct CaptroPassScannerSheet: View {
  @Environment(\.dismiss) private var dismiss
  let api: MIRAAPIClient
  @State private var isConsuming = false
  @State private var result: String?
  @State private var error: String?
  @State private var scanAttempt = 0

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        CaptroQRScanner { token in consume(token) }
          .id(scanAttempt)
          .overlay { RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.85), lineWidth: 2).frame(width: 230, height: 230) }
        if isConsuming { ProgressView("Checking pass...") }
        if let result {
          Label(result, systemImage: "checkmark.circle.fill")
            .font(.system(size: 17, weight: .semibold)).foregroundStyle(MIRATheme.Color.forest)
        }
        if let error {
          Text(error).font(.system(size: 14)).foregroundStyle(.red.opacity(0.86))
          Button("Scan another pass") { self.error = nil; scanAttempt += 1 }
            .font(.system(size: 14, weight: .semibold)).frame(minHeight: 44)
        }
      }
      .background(Color.black.ignoresSafeArea()).foregroundStyle(.white)
      .navigationTitle("Scan Pass").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }
  }

  private func consume(_ token: String) {
    guard !isConsuming, result == nil else { return }
    isConsuming = true
    Task {
      defer { isConsuming = false }
      do {
        let response = try await api.consumeCommercePass(token: token)
        result = response.status == "checked_in" ? "Checked In" : "Redeemed"
      } catch {
        self.error = (error as? MIRAAPIError)?.errorDescription ?? "This pass could not be accepted."
      }
    }
  }
}

private struct CaptroQRScanner: UIViewControllerRepresentable {
  let onCode: (String) -> Void
  func makeUIViewController(context: Context) -> CaptroQRScannerController { CaptroQRScannerController(onCode: onCode) }
  func updateUIViewController(_ uiViewController: CaptroQRScannerController, context: Context) {}
}

private final class CaptroQRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  private let session = AVCaptureSession()
  private let onCode: (String) -> Void
  private var preview: AVCaptureVideoPreviewLayer?
  private var delivered = false

  init(onCode: @escaping (String) -> Void) {
    self.onCode = onCode
    super.init(nibName: nil, bundle: nil)
  }
  @available(*, unavailable) required init?(coder: NSCoder) { nil }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    prepareCamera()
  }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }

  private func prepareCamera() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: configureCamera()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        guard granted else { return }
        DispatchQueue.main.async { self?.configureCamera() }
      }
    default: break
    }
  }

  private func configureCamera() {
    guard session.inputs.isEmpty,
          let device = AVCaptureDevice.default(for: .video),
          let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
    session.addInput(input)
    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else { return }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: .main)
    output.metadataObjectTypes = [.qr]
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    view.layer.insertSublayer(layer, at: 0)
    preview = layer
    DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
  }

  func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
    guard !delivered, let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
          let value = object.stringValue else { return }
    delivered = true
    session.stopRunning()
    onCode(value)
  }
}

struct CaptroEarningsView: View {
  let api: MIRAAPIClient
  @State private var response: CaptroEarningsResponse?
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var hostedDestination: CaptroCheckoutDestination?
  @State private var showingWithdrawal = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if let response {
          balanceSection(response)
          divider
          payoutAccountSection(response.account)
          divider
          recentSection(response.recent)
        } else if isLoading {
          ProgressView("Loading earnings...")
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
          ContentUnavailableView(
            "Earnings unavailable",
            systemImage: "dollarsign",
            description: Text(errorMessage ?? "Pull to try again.")
          )
          .frame(maxWidth: .infinity, minHeight: 320)
        }
      }
    }
    .background(Color.white)
    .foregroundStyle(CaptroDetailStyle.ink)
    .navigationTitle("Earnings")
    .navigationBarTitleDisplayMode(.inline)
    .miraHideTabBarOnAppear()
    .refreshable { await load() }
    .task { await load() }
    .sheet(item: $hostedDestination, onDismiss: { Task { await load() } }) { destination in
      CaptroCheckoutBrowser(url: destination.url).ignoresSafeArea()
    }
    .sheet(isPresented: $showingWithdrawal, onDismiss: { Task { await load() } }) {
      CaptroWithdrawView(api: api)
    }
    .alert("Couldn't open payouts", isPresented: Binding(
      get: { errorMessage != nil && response != nil },
      set: { if !$0 { errorMessage = nil } }
    )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
  }

  private func balanceSection(_ value: CaptroEarningsResponse) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      sectionHeading("EARNINGS")
      if value.balance.status == "available",
         let available = value.balance.available,
         let pending = value.balance.pending {
        HStack(spacing: 28) {
          balanceValue("Available", amount: available, currency: value.balance.currency)
          balanceValue("Pending", amount: pending, currency: value.balance.currency)
        }
        if value.account.ready, (value.balance.instantAvailable ?? 0) > 0 {
          Button { showingWithdrawal = true } label: {
            Label("Withdraw", systemImage: "creditcard")
              .frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.borderedProminent)
          .tint(CaptroDetailStyle.accent)
        }
      } else {
        VStack(alignment: .leading, spacing: 5) {
          Text("Balance unavailable").font(.system(size: 20, weight: .bold))
          Text(value.account.status == "not_started"
               ? "Set up earnings to receive money from paid posts."
               : "Could not retrieve your current balance. Try again shortly.")
            .font(.system(size: 13)).foregroundStyle(CaptroDetailStyle.secondary)
        }
      }
    }
    .padding(16)
  }

  private func payoutAccountSection(_ account: CaptroPayoutAccount) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeading("PAYOUT METHOD")
      if account.ready {
        HStack {
          Text("Status").foregroundStyle(CaptroDetailStyle.secondary)
          Spacer(minLength: 12)
          Label("Payouts Ready", systemImage: "checkmark.circle.fill")
            .fontWeight(.semibold)
            .foregroundStyle(CaptroDetailStyle.accent)
        }
        .font(.system(size: 13))
        if let card = account.payoutCard {
          detailRow("Debit Card", "\(card.brand) ···· \(card.last4)")
          if card.instantPayoutEligible {
            Label("Instant payout eligible", systemImage: "checkmark.circle")
              .font(.caption).foregroundStyle(CaptroDetailStyle.accent)
          }
        }
        Button("Replace Card") { openHostedAccount(manage: true) }
          .buttonStyle(CaptroOutlineButtonStyle())
      } else {
        Text(account.identityRequirementsComplete == true
             ? "Add an eligible debit card to receive your Captro earnings."
             : "Verify your identity and add a debit card to receive earnings from sales.")
          .font(.system(size: 14)).foregroundStyle(CaptroDetailStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Button(account.identityRequirementsComplete == true ? "Add Debit Card" : "Set Up Earnings") {
          openHostedAccount(manage: false)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(CaptroDetailStyle.accent)
        .buttonStyle(.plain)
      }
      NavigationLink {
        CaptroPayoutsView(api: api)
      } label: {
        HStack {
          Text("Payout History")
          Spacer()
          Image(systemName: "chevron.right")
        }
        .font(.system(size: 14, weight: .semibold))
        .frame(minHeight: 44)
      }
      .buttonStyle(.plain)
    }
    .padding(16)
  }

  private func recentSection(_ earnings: [CaptroCreatorEarning]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionHeading("RECENT EARNINGS").padding(.bottom, 8)
      if earnings.isEmpty {
        Text("Completed sales will appear here.")
          .font(.system(size: 14)).foregroundStyle(CaptroDetailStyle.secondary)
          .padding(.vertical, 20)
      } else {
        ForEach(earnings) { earning in
          NavigationLink {
            CaptroEarningDetailView(api: api, earningID: earning.id)
          } label: {
            HStack(alignment: .center, spacing: 12) {
              VStack(alignment: .leading, spacing: 4) {
                Text(earning.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                Text("\(earning.contentType.replacingOccurrences(of: "_", with: " ").capitalized) · \(CaptroCommerceDate.short(earning.purchasedAt))")
                  .font(.system(size: 11)).foregroundStyle(CaptroDetailStyle.secondary)
                Text(earning.status.replacingOccurrences(of: "_", with: " ").capitalized)
                  .font(.system(size: 11)).foregroundStyle(CaptroDetailStyle.secondary)
              }
              Spacer(minLength: 8)
              Text("+ \(CaptroMoney.format(minorUnits: earning.netCreatorAmount, currency: earning.currency))")
                .font(.system(size: 14, weight: .semibold))
              Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(CaptroDetailStyle.secondary)
            }
            .frame(minHeight: 62)
          }
          .buttonStyle(.plain)
          divider
        }
      }
    }
    .padding(16)
  }

  private func balanceValue(_ label: String, amount: Int, currency: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.system(size: 12)).foregroundStyle(CaptroDetailStyle.secondary)
      Text(CaptroMoney.format(minorUnits: amount, currency: currency)).font(.system(size: 25, weight: .bold))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func detailRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label).foregroundStyle(CaptroDetailStyle.secondary)
      Spacer(minLength: 12)
      Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing)
    }
    .font(.system(size: 13))
  }

  private func sectionHeading(_ value: String) -> some View {
    Text(value).font(.system(size: 11, weight: .bold)).foregroundStyle(CaptroDetailStyle.secondary)
  }

  private var divider: some View { Rectangle().fill(CaptroDetailStyle.divider).frame(height: 0.5) }

  private func openHostedAccount(manage: Bool) {
    guard !isLoading else { return }
    isLoading = true
    Task {
      defer { isLoading = false }
      do {
        let link: CaptroHostedAccountLinkResponse
        if manage {
            link = try await api.createPayoutManagementLink()
        } else {
            link = try await api.createPayoutOnboardingLink()
        }
        guard let url = URL(string: link.url) else { throw URLError(.badURL) }
        hostedDestination = CaptroCheckoutDestination(url: url)
      } catch {
        errorMessage = (error as? MIRAAPIError)?.errorDescription ?? "Could not open secure payout setup."
      }
    }
  }

  private func load() async {
    if response == nil { isLoading = true }
    defer { isLoading = false }
    do {
      response = try await api.loadCreatorEarnings()
      errorMessage = nil
    } catch {
      if response == nil { errorMessage = (error as? MIRAAPIError)?.errorDescription ?? "Could not load earnings." }
    }
  }
}

private struct CaptroPayoutsView: View {
  let api: MIRAAPIClient
  @State private var response: CaptroPayoutsResponse?
  @State private var errorMessage: String?

  var body: some View {
    Group {
      if let response {
        List(response.payouts) { payout in
          VStack(alignment: .leading, spacing: 5) {
            HStack {
              Text(CaptroCommerceDate.day(payout.createdAt)).font(.system(size: 14, weight: .semibold))
              Spacer()
              Text(CaptroMoney.format(minorUnits: payout.amount, currency: payout.currency)).font(.system(size: 14, weight: .semibold))
            }
            Text(payout.status.replacingOccurrences(of: "_", with: " ").capitalized)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(payout.status == "failed" ? Color.red : CaptroDetailStyle.secondary)
            if let card = payout.card {
              Text("\(card.brand) Debit ···· \(card.last4)").font(.system(size: 12))
            }
            if let fee = payout.fee, fee > 0 {
              Text("Fee: \(CaptroMoney.format(minorUnits: fee, currency: payout.currency))")
                .font(.system(size: 12)).foregroundStyle(CaptroDetailStyle.secondary)
            }
            if let message = payout.failureMessage, payout.status == "failed" {
              Text(message).font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
          }
          .listRowBackground(Color.white)
        }
        .listStyle(.plain)
        .overlay {
          if response.payouts.isEmpty {
            ContentUnavailableView("No payouts yet", systemImage: "creditcard", description: Text("Your debit-card payouts will appear here."))
          }
        }
      } else if let errorMessage {
        ContentUnavailableView("Payouts unavailable", systemImage: "exclamationmark.circle", description: Text(errorMessage))
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(Color.white)
    .navigationTitle("Payouts")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      do { response = try await api.loadCreatorPayouts() }
      catch { errorMessage = (error as? MIRAAPIError)?.errorDescription ?? "Could not load payouts." }
    }
  }
}

private struct CaptroEarningDetailView: View {
  let api: MIRAAPIClient
  let earningID: String
  @State private var response: CaptroEarningDetailResponse?
  @State private var errorMessage: String?

  var body: some View {
    ScrollView {
      if let response {
        VStack(alignment: .leading, spacing: 16) {
          Text(response.earning.title).font(.system(size: 25, weight: .bold))
          Text(response.earning.contentType.replacingOccurrences(of: "_", with: " ").capitalized + " purchase")
            .font(.system(size: 13)).foregroundStyle(CaptroDetailStyle.secondary)
          Rectangle().fill(CaptroDetailStyle.divider).frame(height: 0.5)
          earningRow("Buyer", response.earning.buyerHandle.map { "@\($0.trimmingCharacters(in: CharacterSet(charactersIn: "@")))" } ?? "Captro user")
          earningRow("Item price", CaptroMoney.format(minorUnits: response.earning.itemAmount, currency: response.earning.currency))
          earningRow("Creator earnings", CaptroMoney.format(minorUnits: response.earning.netCreatorAmount, currency: response.earning.currency))
          earningRow("Purchased", CaptroCommerceDate.long(response.earning.purchasedAt))
          earningRow("Payment", response.purchase.status.replacingOccurrences(of: "_", with: " ").capitalized)
          earningRow("Purchase ID", response.purchaseReference)
          ForEach(response.refunds) { refund in
            Rectangle().fill(CaptroDetailStyle.divider).frame(height: 0.5)
            earningRow("Refund", "− \(CaptroMoney.format(minorUnits: refund.creatorReversalAmount, currency: response.earning.currency))")
          }
        }
        .padding(16)
      } else if let errorMessage {
        ContentUnavailableView("Earning unavailable", systemImage: "exclamationmark.circle", description: Text(errorMessage))
          .frame(minHeight: 320)
      } else {
        ProgressView().frame(maxWidth: .infinity, minHeight: 320)
      }
    }
    .background(Color.white)
    .navigationTitle("Earning")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      do { response = try await api.loadCreatorEarning(id: earningID) }
      catch { errorMessage = (error as? MIRAAPIError)?.errorDescription ?? "Could not load this earning." }
    }
  }

  private func earningRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top) {
      Text(label).font(.system(size: 13)).foregroundStyle(CaptroDetailStyle.secondary)
      Spacer(minLength: 14)
      Text(value).font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.trailing)
    }
  }
}

private struct CaptroOutlineButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 14, weight: .semibold))
      .frame(maxWidth: .infinity, minHeight: 44)
      .foregroundStyle(CaptroDetailStyle.ink)
      .overlay(Rectangle().stroke(CaptroDetailStyle.divider, lineWidth: 1))
      .opacity(configuration.isPressed ? 0.6 : 1)
  }
}

private enum CaptroCommerceDate {
  static func short(_ value: String?) -> String { format(value, style: "MMM d") }
  static func day(_ value: String?) -> String { format(value, style: "MMM d") }
  static func long(_ value: String?) -> String { format(value, style: "MMM d, yyyy · h:mm a") }

  private static func format(_ value: String?, style: String) -> String {
    guard let value else { return "" }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return "" }
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.dateFormat = style
    return formatter.string(from: date)
  }
}
