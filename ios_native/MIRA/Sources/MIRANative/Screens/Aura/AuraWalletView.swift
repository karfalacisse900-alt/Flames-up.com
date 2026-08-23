import SwiftUI

/// Aura Mobile's Wallet tab. Deliberately has no key-generation or signing logic yet: wallet
/// private keys must never be invented with ad hoc Swift crypto (see project rule: never invent
/// custom cryptography). The real implementation should reuse Aura's existing Rust wallet crate
/// through the same Rust-to-Swift FFI bridge this project already scaffolds for `mira_core`
/// (see `ios_native/MIRA/rust/mira_core`), with the derived signing key held in the Secure
/// Enclave / Keychain and never sent to any backend or database.
public struct AuraWalletView: View {
  let api: MIRAAPIClient

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: MIRATheme.Space.lg) {
          balanceCard
          actionRow
          MIRAEmptyState(
            title: "No wallet on this device",
            message: "Create or restore an Aura wallet to see a real balance, send and receive AUR, and view transaction history. Private keys stay on this device.",
            systemImage: "wallet.pass"
          )
          .miraCardSurface()
        }
        .padding(MIRATheme.Space.lg)
      }
      .background(MIRATheme.Color.appBackground.ignoresSafeArea())
      .navigationTitle("Wallet")
    }
  }

  private var balanceCard: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.xs) {
      Text("Total Balance")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.8))
      Text("Unavailable")
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
      Text("No wallet is set up on this device")
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(.white.opacity(0.75))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MIRATheme.Space.lg)
    .background(MIRATheme.Color.forest)
    .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.large, style: .continuous))
  }

  private var actionRow: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      walletAction(label: "Receive", systemImage: "arrow.down")
      walletAction(label: "Send", systemImage: "arrow.up")
      walletAction(label: "Scan QR", systemImage: "qrcode.viewfinder")
    }
  }

  private func walletAction(label: String, systemImage: String) -> some View {
    VStack(spacing: MIRATheme.Space.xxs) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .semibold))
      Text(label)
        .font(.system(size: 12.5, weight: .semibold))
    }
    .foregroundStyle(MIRATheme.Color.textPrimary)
    .frame(maxWidth: .infinity, minHeight: 56)
    .miraCardSurface()
  }
}
