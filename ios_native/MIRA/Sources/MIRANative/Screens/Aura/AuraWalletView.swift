import SwiftUI

/// Aura Mobile's real local-wallet surface. Key generation, restoration, encrypted persistence,
/// address derivation, and signing stay in Rust. Network balances and transaction history remain
/// unavailable until a real Aura Mobile Gateway is connected.
public struct AuraWalletView: View {
  @Environment(\.scenePhase) private var scenePhase
  let api: MIRAAPIClient
  @StateObject private var wallet = AuraWalletStore()
  @State private var presentedSheet: WalletSheet?
  @State private var unlockPassword = ""

  public init(api: MIRAAPIClient) {
    self.api = api
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
      .sheet(item: $presentedSheet) { sheet in
        switch sheet {
        case .create:
          AuraCreateWalletSheet(wallet: wallet)
        case .restore:
          AuraRestoreWalletSheet(wallet: wallet)
        case .receive:
          AuraReceiveWalletSheet(identity: wallet.identity)
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
        if phase != .active, wallet.state == .unlocked {
          wallet.lock()
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
      .miraCardSurface()
    }
  }

  private var balanceCard: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.xs) {
      Text("AUR Balance")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.8))
      Text("Unavailable")
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
      Text(balanceSubtitle)
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(.white.opacity(0.75))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MIRATheme.Space.lg)
    .background(
      LinearGradient(
        colors: [MIRATheme.Color.forest, MIRATheme.Color.forest.opacity(0.82)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.large, style: .continuous))
  }

  private var balanceSubtitle: String {
    switch wallet.state {
    case .unlocked: return "Wallet unlocked · Aura Mobile Gateway not connected"
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
    .miraCardSurface()
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
    .miraCardSurface()
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
        .miraCardSurface()
      }

      MIRAEmptyState(
        title: "Network data not connected",
        message: "Balance, nonce, fees, transaction history, and confirmations will appear only after a real Aura Mobile Gateway is available.",
        systemImage: "network.slash"
      )
      .miraCardSurface()

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
        wallet.report(
          AuraWalletNativeError.nativeFailure(
            "Send is unavailable until Aura Mobile can obtain a real chain ID, balance, nonce, and fee from the network."
          )
        )
      }
      walletAction(label: "History", systemImage: "clock.arrow.circlepath") {
        wallet.report(
          AuraWalletNativeError.nativeFailure(
            "Transaction history is unavailable until Aura Mobile is connected to real chain state."
          )
        )
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
    .miraCardSurface()
  }
}

private enum WalletSheet: String, Identifiable {
  case create
  case restore
  case receive

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
        Image(systemName: "qrcode")
          .font(.system(size: 72, weight: .light))
          .foregroundStyle(MIRATheme.Color.textMuted)
        Text("QR rendering is not connected yet")
          .font(.system(size: 17, weight: .bold))
        if let identity {
          Text(identity.address)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .textSelection(.enabled)
            .multilineTextAlignment(.center)
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

private struct AuraPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .bold))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, minHeight: 48)
      .background(MIRATheme.Color.forest.opacity(configuration.isPressed ? 0.78 : 1))
      .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.medium, style: .continuous))
  }
}

private struct AuraSecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .bold))
      .foregroundStyle(MIRATheme.Color.forest)
      .frame(maxWidth: .infinity, minHeight: 48)
      .background(MIRATheme.Color.surfaceSoft.opacity(configuration.isPressed ? 0.7 : 1))
      .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.medium, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: MIRATheme.Radius.medium, style: .continuous)
          .stroke(MIRATheme.Color.forest.opacity(0.2), lineWidth: 1)
      }
  }
}
