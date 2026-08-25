import SwiftUI

/// Displays only proofs recorded after a real locally signed submission. Every lifecycle state is
/// refreshed from the validated Aura Devnet node; this view does not promote local OCR to proof.
public struct AuraProofsView: View {
  let api: MIRAAPIClient
  @ObservedObject private var proofs: AuraProofLifecycleStore

  public init(api: MIRAAPIClient, proofs: AuraProofLifecycleStore) {
    self.api = api
    self.proofs = proofs
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        if proofs.records.isEmpty {
          MIRAEmptyState(
            title: "No on-chain proofs yet",
            message: "A record appears only after a verified receipt is authorized by the local Rust wallet and accepted by the real Aura Devnet mempool.",
            systemImage: "checkmark.seal"
          )
          .miraCardSurface()
          .padding(MIRATheme.Space.lg)
        } else {
          LazyVStack(spacing: MIRATheme.Space.md) {
            ForEach(proofs.records) { record in
              proofCard(record)
            }
          }
          .padding(MIRATheme.Space.lg)
        }
      }
      .background(MIRATheme.Color.appBackground.ignoresSafeArea())
      .navigationTitle("Proofs")
      .refreshable { await proofs.refreshAll() }
      .task { await proofs.refreshAll() }
      .alert(
        "Proof status error",
        isPresented: Binding(
          get: { proofs.errorMessage != nil },
          set: { if !$0 { proofs.clearError() } }
        )
      ) {
        Button("OK") { proofs.clearError() }
      } message: {
        Text(proofs.errorMessage ?? "Aura could not read proof state.")
      }
    }
  }

  private func proofCard(_ record: AuraPrivateProofRecord) -> some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      HStack {
        Label(stateTitle(record), systemImage: stateIcon(record))
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(record.isConfirmed ? MIRATheme.Color.forest : MIRATheme.Color.textPrimary)
        Spacer()
        Text("Purchase")
          .font(.system(size: 11.5, weight: .bold))
          .foregroundStyle(MIRATheme.Color.forest)
      }

      valueRow("Proof ID", record.proofId)
      valueRow("Transaction", record.proofTransactionId)
      if let blockHeight = record.blockHeight { valueRow("Block", blockHeight) }
      valueRow("Confirmations", "\(record.confirmations) / \(record.requiredConfirmations)")

      if let rewardTransactionId = record.rewardTransactionId {
        Divider()
        Label("Devnet contribution reward", systemImage: "bitcoinsign.circle.fill")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(MIRATheme.Color.forest)
        if let atoms = record.rewardAtoms, let aur = AuraAmountCodec.aur(fromAtoms: atoms) {
          valueRow("Reward", "\(aur) AUR")
        }
        valueRow("Reward transaction", rewardTransactionId)
        if let height = record.rewardBlockHeight { valueRow("Reward block", height) }
        valueRow("Reward state", rewardState(record))
      }
    }
    .padding(MIRATheme.Space.lg)
    .miraCardSurface()
  }

  private func stateTitle(_ record: AuraPrivateProofRecord) -> String {
    switch record.state {
    case "pending": return "Pending"
    case "included": return "Included in block #\(record.blockHeight ?? "Unavailable")"
    case "confirmed": return "Confirmed"
    default: return "Not found on canonical Devnet"
    }
  }

  private func stateIcon(_ record: AuraPrivateProofRecord) -> String {
    switch record.state {
    case "confirmed": return "checkmark.seal.fill"
    case "included": return "cube.fill"
    case "pending": return "clock.arrow.circlepath"
    default: return "questionmark.diamond"
    }
  }

  private func rewardState(_ record: AuraPrivateProofRecord) -> String {
    switch record.rewardState {
    case "confirmed": return "Confirmed · \(record.rewardConfirmations ?? "0") confirmations"
    case "unconfirmed", "pending": return "Pending in mempool"
    default: return "Unavailable"
    }
  }

  private func valueRow(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.xxs) {
      Text(label)
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
      Text(value)
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .textSelection(.enabled)
    }
  }
}
