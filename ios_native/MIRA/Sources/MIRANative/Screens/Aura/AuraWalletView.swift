import CoreImage.CIFilterBuiltins
import SwiftUI

/// Aura Mobile's real local-wallet surface. Key generation, restoration, encrypted persistence,
/// address derivation, and signing stay in Rust. Public chain state comes from the authenticated
/// Aura Mobile Gateway and every signed transaction still passes the real node mempool.
public struct AuraWalletView: View {
  @Environment(\.scenePhase) private var scenePhase
  let api: MIRAAPIClient
  @ObservedObject private var wallet: AuraWalletStore
  @ObservedObject private var proofs: AuraProofLifecycleStore
  @ObservedObject private var gateway: AuraWalletGatewayStore
  @State private var presentedSheet: WalletSheet?
  @State private var unlockPassword = ""

  public init(
    api: MIRAAPIClient,
    wallet: AuraWalletStore,
    gateway: AuraWalletGatewayStore,
    proofs: AuraProofLifecycleStore
  ) {
    self.api = api
    self.wallet = wallet
    self.gateway = gateway
    self.proofs = proofs
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: MIRATheme.Space.lg) {
          balanceCard
          content
        }
        .padding(MIRATheme.Space.lg)
      }
      .background(MIRATheme.Color.appBackground.ignoresSafeArea())
      .navigationTitle("Wallet")
      .refreshable {
        if let identity = wallet.identity {
          await gateway.refresh(identity: identity)
          await proofs.refreshAll()
        }
      }
      .sheet(item: $presentedSheet) { sheet in
        switch sheet {
        case .create:
          AuraCreateWalletSheet(wallet: wallet)
        case .restore:
          AuraRestoreWalletSheet(wallet: wallet)
        case .receive:
          AuraReceiveWalletSheet(identity: wallet.identity)
        case .send:
          if let identity = wallet.identity {
            AuraSendWalletSheet(wallet: wallet, gateway: gateway, identity: identity)
          }
        case .history:
          AuraWalletHistorySheet(gateway: gateway)
        }
      }
      .alert(
        "Wallet error",
        isPresented: Binding(
          get: { wallet.errorMessage != nil },
          set: { if !$0 { wallet.clearError() } }
        )
      ) {
        Button("OK") { wallet.clearError() }
      } message: {
        Text(wallet.errorMessage ?? "Aura wallet operation failed.")
      }
      .onChange(of: scenePhase) { _, phase in
        // Camera, photo-picker, and system sheets can make an app briefly inactive. Lock when the
        // process is actually backgrounded so receipt capture cannot invalidate its own wallet.
        if phase == .background, wallet.state == .unlocked {
          wallet.lock()
          gateway.clear()
        }
      }
      .task(id: wallet.identity?.address) {
        if let identity = wallet.identity {
          gateway.start(identity: identity)
          await proofs.refreshAll()
        } else {
          gateway.clear()
        }
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch wallet.state {
    case .noWallet:
      noWalletCard
    case .locked:
      unlockCard
    case .unlocked:
      unlockedContent
    case .unavailable:
      MIRAEmptyState(
        title: "Wallet storage unavailable",
        message: "Aura could not access this device's protected Application Support directory.",
        systemImage: "exclamationmark.shield"
      )
      .physicalAuraCard(cornerRadius: 18)
    }
  }

  private var balanceCard: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.xs) {
      Text("Spendable AUR")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.8))
      Text(gateway.availableAUR.map { "\($0) AUR" } ?? "Unavailable")
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
      Text(balanceSubtitle)
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(.white.opacity(0.75))
      if let balance = gateway.balance {
        Divider().overlay(.white.opacity(0.2))
        HStack(spacing: MIRATheme.Space.sm) {
          balanceMetric(
            "Confirmed",
            AuraAmountCodec.aur(fromAtoms: balance.confirmedAtoms) ?? "Unavailable"
          )
          balanceMetric(
            "Pending in",
            AuraAmountCodec.aur(fromAtoms: balance.pendingIncomingAtoms).map { "+\($0)" }
              ?? "Unavailable"
          )
          balanceMetric(
            "Pending out",
            AuraAmountCodec.aur(fromAtoms: balance.pendingOutgoingAtoms).map { "−\($0)" }
              ?? "Unavailable"
          )
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MIRATheme.Space.lg)
    .background(MIRATheme.Color.auraViolet)
    .physicalAuraCard(cornerRadius: MIRATheme.Radius.large)
  }

  private func balanceMetric(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(.white.opacity(0.65))
      Text(value)
        .font(.system(size: 12.5, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var balanceSubtitle: String {
    switch wallet.state {
    case .unlocked:
      if gateway.isLoading { return "Wallet unlocked · Reading validated Devnet state" }
      if let status = gateway.chainStatus {
        let live = gateway.isEventStreamConnected ? "Live updates" : "Connecting updates"
        return "Wallet unlocked · Block \(status.canonicalHeight) · \(live)"
      }
      return "Wallet unlocked · Aura Mobile Gateway not connected"
    case .locked: return "Encrypted wallet locked"
    case .noWallet: return "No wallet is set up on this device"
    case .unavailable: return "Protected wallet storage unavailable"
    }
  }

  private var noWalletCard: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      Label("Set up your Aura wallet", systemImage: "wallet.pass")
        .font(.system(size: 18, weight: .bold))
      Text("Aura creates and signs with the real Rust wallet. Your encrypted wallet file stays on this device, and Aura never stores your password.")
        .font(.system(size: 13.5, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textSecondary)

      Button("Create New Wallet") { presentedSheet = .create }
        .buttonStyle(AuraPrimaryButtonStyle())
      Button("Restore with Recovery Phrase") { presentedSheet = .restore }
        .buttonStyle(AuraSecondaryButtonStyle())
    }
    .padding(MIRATheme.Space.lg)
    .physicalAuraCard(cornerRadius: 18)
  }

  private var unlockCard: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      Label("Unlock encrypted wallet", systemImage: "lock.shield")
        .font(.system(size: 18, weight: .bold))
      Text("Enter the password for the wallet already stored on this iPhone. The password is used locally and is not saved.")
        .font(.system(size: 13.5, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textSecondary)
      SecureField("Wallet password", text: $unlockPassword)
        .textContentType(.password)
        .padding(MIRATheme.Space.md)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.medium, style: .continuous))
      Button("Unlock Wallet") {
        do {
          try wallet.unlock(password: unlockPassword)
          unlockPassword = ""
        } catch {
          unlockPassword = ""
          wallet.report(error)
        }
      }
      .buttonStyle(AuraPrimaryButtonStyle())
      .disabled(unlockPassword.isEmpty)
    }
    .padding(MIRATheme.Space.lg)
    .physicalAuraCard(cornerRadius: 18)
  }

  private var unlockedContent: some View {
    VStack(spacing: MIRATheme.Space.lg) {
      actionRow
      if let identity = wallet.identity {
        VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
          HStack {
            Label("Public wallet", systemImage: "checkmark.shield.fill")
              .font(.system(size: 16, weight: .bold))
            Spacer()
            Text(identity.network.capitalized)
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(MIRATheme.Color.forest)
          }
          Text(identity.address)
            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
            .textSelection(.enabled)
          Text("This is public receiving information. The private signing key remains inside the encrypted Rust wallet.")
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
        .padding(MIRATheme.Space.lg)
        .physicalAuraCard(cornerRadius: 18)
      }

      networkContent

      Button("Lock Wallet") { wallet.lock() }
        .buttonStyle(AuraSecondaryButtonStyle())
    }
  }

  private var actionRow: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      walletAction(label: "Receive", systemImage: "arrow.down") {
        presentedSheet = .receive
      }
      walletAction(label: "Send", systemImage: "arrow.up") {
        if gateway.isConnected {
          presentedSheet = .send
        } else {
          wallet.report(AuraWalletGatewayError.networkUnavailable)
        }
      }
      walletAction(label: "History", systemImage: "clock.arrow.circlepath") {
        if gateway.history != nil {
          presentedSheet = .history
        } else {
          wallet.report(AuraWalletGatewayError.networkUnavailable)
        }
      }
    }
  }

  private func walletAction(
    label: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: MIRATheme.Space.xxs) {
        Image(systemName: systemImage)
          .font(.system(size: 17, weight: .semibold))
        Text(label)
          .font(.system(size: 12.5, weight: .semibold))
      }
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .frame(maxWidth: .infinity, minHeight: 56)
    }
    .physicalAuraCard(cornerRadius: 16)
  }

  @ViewBuilder
  private var networkContent: some View {
    if gateway.isLoading {
      ProgressView("Reading Aura Devnet")
        .frame(maxWidth: .infinity, minHeight: 150)
        .physicalAuraCard(cornerRadius: 18)
    } else if let status = gateway.chainStatus, let fees = gateway.fees {
      VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
        HStack {
          Label("Aura node data", systemImage: "network.badge.shield.half.filled")
            .font(.system(size: 17, weight: .bold))
          Spacer()
          Text("Devnet")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(MIRATheme.Color.forest)
        }
        HStack {
          AuraWalletMetric(label: "Block", value: status.canonicalHeight)
          AuraWalletMetric(label: "Peers", value: status.connectedPeers)
          AuraWalletMetric(
            label: "Latency",
            value: gateway.latencyMilliseconds.map { "\($0) ms" } ?? "Unavailable"
          )
        }
        HStack {
          AuraWalletMetric(
            label: "Min fee",
            value: AuraAmountCodec.aur(fromAtoms: fees.minimumFeeAtoms).map { "\($0) AUR" } ?? "Unavailable"
          )
          AuraWalletMetric(label: "Mempool", value: status.mempoolTransactions)
          AuraWalletMetric(label: "Sync", value: status.syncStatus.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        if let balance = gateway.balance {
          HStack {
            AuraWalletMetric(
              label: "Spendable",
              value: AuraAmountCodec.aur(fromAtoms: balance.spendableAtoms).map { "\($0) AUR" }
                ?? "Unavailable"
            )
            AuraWalletMetric(
              label: "Pending in",
              value: AuraAmountCodec.aur(fromAtoms: balance.pendingIncomingAtoms).map { "+\($0) AUR" }
                ?? "Unavailable"
            )
            AuraWalletMetric(
              label: "Pending out",
              value: AuraAmountCodec.aur(fromAtoms: balance.pendingOutgoingAtoms).map { "−\($0) AUR" }
                ?? "Unavailable"
            )
          }
        }
        Text(status.syncStatus == "no_peers" ? "No peers" : "Connected peers · independently validating")
          .font(.system(size: 12.5, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
        if let history = gateway.history, !history.transactions.isEmpty {
          Divider()
          ForEach(history.transactions.prefix(3)) { transaction in
            AuraWalletTransactionRow(transaction: transaction)
          }
        }
      }
      .padding(MIRATheme.Space.lg)
      .physicalAuraCard(cornerRadius: 18)
    } else {
      VStack(spacing: MIRATheme.Space.md) {
        MIRAEmptyState(
          title: "Network data not connected",
          message: gateway.errorMessage ?? "Balance, nonce, fees, transaction history, and confirmations require the authenticated Aura Mobile Gateway.",
          systemImage: "network.slash"
        )
        Button("Retry Gateway") {
          if let identity = wallet.identity {
            Task { await gateway.refresh(identity: identity) }
          }
        }
        .buttonStyle(AuraSecondaryButtonStyle())
      }
      .physicalAuraCard(cornerRadius: 18)
    }
  }
}

private enum WalletSheet: String, Identifiable {
  case create
  case restore
  case receive
  case send
  case history

  var id: String { rawValue }
}

private struct AuraCreateWalletSheet: View {
  @ObservedObject var wallet: AuraWalletStore
  @Environment(\.dismiss) private var dismiss
  @State private var password = ""
  @State private var confirmation = ""
  @State private var recoveryPhrase: String?
  @State private var acknowledged = false

  var body: some View {
    NavigationStack {
      Form {
        if let recoveryPhrase {
          Section("Your 24-word recovery phrase") {
            Text(recoveryPhrase)
              .font(.system(size: 15, weight: .semibold, design: .monospaced))
              .textSelection(.enabled)
            Text("Write these words down in order and keep them offline. Aura cannot recover them or your password.")
              .foregroundStyle(.secondary)
            Toggle("I saved my recovery phrase", isOn: $acknowledged)
          }
        } else {
          Section("Encrypt this wallet") {
            SecureField("Password (12+ characters)", text: $password)
              .textContentType(.newPassword)
            SecureField("Confirm password", text: $confirmation)
              .textContentType(.newPassword)
          }
          Section {
            Text("The key is generated by Aura's Rust wallet using operating-system secure randomness. The encrypted wallet stays on this iPhone.")
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle(recoveryPhrase == nil ? "Create Wallet" : "Back Up Wallet")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          if recoveryPhrase == nil {
            Button("Cancel") { dismiss() }
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          if recoveryPhrase == nil {
            Button("Create") { createWallet() }
              .disabled(password.count < 12 || password != confirmation)
          } else {
            Button("Done") {
              recoveryPhrase = nil
              dismiss()
            }
            .disabled(!acknowledged)
          }
        }
      }
    }
    .interactiveDismissDisabled(recoveryPhrase != nil && !acknowledged)
  }

  private func createWallet() {
    do {
      recoveryPhrase = try wallet.create(password: password)
      password = ""
      confirmation = ""
    } catch {
      wallet.report(error)
    }
  }
}

private struct AuraRestoreWalletSheet: View {
  @ObservedObject var wallet: AuraWalletStore
  @Environment(\.dismiss) private var dismiss
  @State private var recoveryPhrase = ""
  @State private var password = ""
  @State private var confirmation = ""

  var body: some View {
    NavigationStack {
      Form {
        Section("24-word Aura recovery phrase") {
          TextEditor(text: $recoveryPhrase)
            .frame(minHeight: 120)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        Section("New local encryption password") {
          SecureField("Password (12+ characters)", text: $password)
            .textContentType(.newPassword)
          SecureField("Confirm password", text: $confirmation)
            .textContentType(.newPassword)
        }
        Section {
          Text("The recovery phrase is processed locally by Rust and is not uploaded.")
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Restore Wallet")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Restore") { restoreWallet() }
            .disabled(
              recoveryPhrase.split(separator: " ").count != 24 ||
              password.count < 12 ||
              password != confirmation
            )
        }
      }
    }
  }

  private func restoreWallet() {
    do {
      try wallet.restore(recoveryPhrase: recoveryPhrase, password: password)
      recoveryPhrase = ""
      password = ""
      confirmation = ""
      dismiss()
    } catch {
      wallet.report(error)
    }
  }
}

private struct AuraReceiveWalletSheet: View {
  let identity: AuraWalletIdentity?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: MIRATheme.Space.lg) {
        if let identity {
          AuraAddressQRCode(address: identity.address)
            .frame(width: 220, height: 220)
          Text("Scan to receive AUR")
            .font(.system(size: 17, weight: .bold))
          Text(identity.address)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .textSelection(.enabled)
            .multilineTextAlignment(.center)
          Button("Copy Address") {
            UIPasteboard.general.string = identity.address
          }
          .buttonStyle(AuraSecondaryButtonStyle())
        } else {
          Image(systemName: "qrcode")
            .font(.system(size: 72, weight: .light))
            .foregroundStyle(MIRATheme.Color.textMuted)
          Text("Public address unavailable")
        }
        Text("Use only the public address above on the \(identity?.network.capitalized ?? "selected") Aura network.")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .multilineTextAlignment(.center)
        Spacer()
      }
      .padding(MIRATheme.Space.xl)
      .navigationTitle("Receive AUR")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

private struct AuraAddressQRCode: View {
  let address: String

  var body: some View {
    if let image = Self.image(for: address) {
      Image(uiImage: image)
        .interpolation(.none)
        .resizable()
        .scaledToFit()
        .accessibilityLabel("QR code for Aura receiving address")
    } else {
      Image(systemName: "qrcode")
        .font(.system(size: 72, weight: .light))
    }
  }

  private static func image(for value: String) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(value.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
          let cgImage = CIContext().createCGImage(output, from: output.extent) else {
      return nil
    }
    return UIImage(cgImage: cgImage)
  }
}

private struct AuraSendWalletSheet: View {
  @ObservedObject var wallet: AuraWalletStore
  @ObservedObject var gateway: AuraWalletGatewayStore
  let identity: AuraWalletIdentity
  @Environment(\.dismiss) private var dismiss
  @State private var recipient = ""
  @State private var amount = ""
  @State private var isSending = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("Recipient") {
          TextField("Devnet Aura address", text: $recipient)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        Section("Amount") {
          TextField("0.00 AUR", text: $amount)
            .keyboardType(.decimalPad)
          if let fee = gateway.fees.flatMap({ AuraAmountCodec.aur(fromAtoms: $0.minimumFeeAtoms) }) {
            LabeledContent("Network minimum fee", value: "\(fee) AUR")
          }
          if let available = gateway.availableAUR {
            LabeledContent("Available", value: "\(available) AUR")
          }
        }
        Section {
          Text("Aura signs on this iPhone. Only the signed canonical transaction is sent to the gateway and validated by the node mempool.")
            .foregroundStyle(.secondary)
        }
        if let intentId = gateway.lastSubmittedIntentId {
          Section("Submitted") {
            Text(intentId)
              .font(.system(size: 12, design: .monospaced))
              .textSelection(.enabled)
            Text("Unconfirmed until a genuine Proof-of-Work block includes it.")
              .foregroundStyle(.secondary)
          }
        }
        if let errorMessage {
          Section {
            Text(errorMessage).foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("Send AUR")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(isSending ? "Sending…" : "Sign & Send") { submit() }
            .disabled(isSending || recipient.isEmpty || amount.isEmpty)
        }
      }
    }
  }

  private func submit() {
    isSending = true
    errorMessage = nil
    Task {
      defer { isSending = false }
      do {
        _ = try await gateway.send(
          from: wallet,
          identity: identity,
          recipient: recipient,
          amountAUR: amount
        )
        amount = ""
      } catch {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      }
    }
  }
}

private struct AuraWalletHistorySheet: View {
  @ObservedObject var gateway: AuraWalletGatewayStore
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        if let history = gateway.history {
          if history.transactions.isEmpty {
            Text("No transactions are present in the validated mempool or scanned canonical history.")
              .foregroundStyle(.secondary)
          } else {
            ForEach(history.transactions) { transaction in
              AuraWalletTransactionRow(transaction: transaction)
            }
          }
          if !history.complete {
            Text("Recent bounded history shown through block \(history.oldestScannedHeight).")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } else {
          Text("Transaction history unavailable.")
        }
      }
      .navigationTitle("AUR History")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

private struct AuraWalletTransactionRow: View {
  let transaction: AuraGatewayTransaction

  var body: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Image(systemName: icon)
        .foregroundStyle(transaction.direction == "sent" ? .red : MIRATheme.Color.forest)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.system(size: 14, weight: .semibold))
        Text(status)
          .font(.system(size: 11.5, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }
      Spacer()
      Text(amount)
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .foregroundStyle(transaction.direction == "sent" ? .red : MIRATheme.Color.forest)
    }
  }

  private var title: String {
    switch transaction.direction {
    case "sent": "Sent"
    case "received": "Received"
    case "mining_reward": "Mining reward"
    default: "Transaction"
    }
  }

  private var icon: String {
    switch transaction.direction {
    case "sent": "arrow.up.right"
    case "mining_reward": "hammer.fill"
    default: "arrow.down.left"
    }
  }

  private var amount: String {
    let value = AuraAmountCodec.aur(fromAtoms: transaction.amountAtoms) ?? "Unavailable"
    let prefix = transaction.direction == "sent" ? "−" : "+"
    return "\(prefix)\(value) AUR"
  }

  private var status: String {
    if transaction.state == "confirmed" {
      let block = transaction.blockHeight.map { " · Block #\($0)" } ?? ""
      return transaction.confirmations == "1"
        ? "Confirmed · 1 confirmation\(block)"
        : "Confirmed · \(transaction.confirmations) confirmations\(block)"
    }
    return "Pending · Validated mempool"
  }
}

private struct AuraWalletMetric: View {
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
      Text(value)
        .font(.system(size: 13, weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct AuraPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .bold))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, minHeight: 48)
      .background(MIRATheme.Color.auraViolet.opacity(configuration.isPressed ? 0.78 : 1))
      .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.medium, style: .continuous))
  }
}

private struct AuraSecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .bold))
      .foregroundStyle(MIRATheme.Color.auraViolet)
      .frame(maxWidth: .infinity, minHeight: 48)
      .background(MIRATheme.Color.surfaceSoft.opacity(configuration.isPressed ? 0.7 : 1))
      .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.medium, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: MIRATheme.Radius.medium, style: .continuous)
          .stroke(MIRATheme.Color.auraViolet.opacity(0.28), lineWidth: 1)
      }
  }
}
