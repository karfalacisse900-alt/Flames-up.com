import CryptoKit
import SwiftUI

/// Feedback is unlocked only by canonical confirmed purchase proofs. Aura Mobile commits the
/// ratings locally and the Rust wallet signs that exact commitment. The Devnet contribution
/// service, not this UI, applies anti-farming/budget rules and may create a normal AUR transfer.
public struct AuraReputationView: View {
  let api: MIRAAPIClient
  @ObservedObject private var wallet: AuraWalletStore
  @ObservedObject private var proofs: AuraProofLifecycleStore
  @State private var selectedProof: AuraPrivateProofRecord?

  public init(
    api: MIRAAPIClient,
    wallet: AuraWalletStore,
    proofs: AuraProofLifecycleStore
  ) {
    self.api = api
    self.wallet = wallet
    self.proofs = proofs
  }

  public var body: some View {
    ScrollView {
        VStack(spacing: MIRATheme.Space.md) {
          if proofs.records.isEmpty {
            MIRAEmptyState(
              title: "No verified purchase standing",
              message: "Leave Aura becomes available only after a real Proof of Purchase reaches the canonical chain and receives the required confirmations.",
              systemImage: "chart.line.uptrend.xyaxis"
            )
            .miraCardSurface()
          } else {
            ForEach(proofs.records) { record in
              reputationCard(record)
            }
          }
        }
        .padding(MIRATheme.Space.lg)
    }
    .background(MIRATheme.Color.appBackground.ignoresSafeArea())
    .navigationTitle("Reputation")
    .refreshable { await proofs.refreshAll() }
    .task { await proofs.refreshAll() }
    .sheet(item: $selectedProof) { record in
      AuraFeedbackSheet(record: record, wallet: wallet, proofs: proofs)
    }
  }

  private func reputationCard(_ record: AuraPrivateProofRecord) -> some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      HStack {
        Label("Verified purchase", systemImage: record.isConfirmed ? "checkmark.seal.fill" : "clock")
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(record.isConfirmed ? MIRATheme.Color.forest : MIRATheme.Color.textPrimary)
        Spacer()
        Text(record.isConfirmed ? "Confirmed" : "\(record.confirmations) confirmations")
          .font(.system(size: 11.5, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
      Text(record.proofId)
        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .textSelection(.enabled)

      if record.feedbackUsed {
        Label("Feedback right used exactly once", systemImage: "checkmark.circle.fill")
          .font(.system(size: 13.5, weight: .bold))
          .foregroundStyle(MIRATheme.Color.forest)
        if let rewardAtoms = record.rewardAtoms,
           let rewardAUR = AuraAmountCodec.aur(fromAtoms: rewardAtoms) {
          Text("The contribution service authorized \(rewardAUR) AUR as a real Devnet transfer. Wallet balance changes only after that transaction is mined.")
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textSecondary)
        }
      } else {
        Button("Leave Aura") { selectedProof = record }
          .buttonStyle(AuraPrimaryButtonStyle())
          .disabled(!record.isConfirmed || wallet.identity?.address != record.owner)
        if !record.isConfirmed {
          Text("Waiting for \(record.requiredConfirmations) canonical confirmations.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
      }
    }
    .padding(MIRATheme.Space.lg)
    .miraCardSurface()
  }
}

private struct AuraFeedbackSheet: View {
  @Environment(\.dismiss) private var dismiss
  let record: AuraPrivateProofRecord
  @ObservedObject var wallet: AuraWalletStore
  @ObservedObject var proofs: AuraProofLifecycleStore
  @State private var service = 0
  @State private var checkout = 0
  @State private var availability = 0
  @State private var storeCondition = 0
  @State private var wouldReturn = 0
  @State private var isSubmitting = false
  @State private var errorMessage: String?
  @State private var result: AuraFeedbackRewardResult?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
          Text("This feedback right belongs to one confirmed purchase proof. Aura stores only a commitment in the Devnet contribution record; it cannot be submitted twice.")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textSecondary)

          ratingRow("Service", selection: $service)
          ratingRow("Checkout", selection: $checkout)
          ratingRow("Availability", selection: $availability)
          ratingRow("Store condition", selection: $storeCondition)

          Picker("Would you return?", selection: $wouldReturn) {
            Text("Yes").tag(1)
            Text("Maybe").tag(2)
            Text("No").tag(3)
          }
          .pickerStyle(.segmented)

          if let result {
            VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
              Label("Feedback accepted", systemImage: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MIRATheme.Color.forest)
              Text("Reward transaction: \(result.rewardTransactionId)")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
              Text("State: pending real Aura block confirmation")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(MIRATheme.Color.textSecondary)
            }
            .padding(MIRATheme.Space.md)
            .miraCardSurface()
          } else {
            Button(isSubmitting ? "Authorizing…" : "Submit Feedback") {
              submit()
            }
            .buttonStyle(AuraPrimaryButtonStyle())
            .disabled(isSubmitting || !isComplete)
          }
        }
        .padding(MIRATheme.Space.lg)
      }
      .background(MIRATheme.Color.appBackground.ignoresSafeArea())
      .navigationTitle("Leave Aura")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .alert(
        "Feedback unavailable",
        isPresented: Binding(
          get: { errorMessage != nil },
          set: { if !$0 { errorMessage = nil } }
        )
      ) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "Aura could not authorize this contribution.")
      }
    }
  }

  private var isComplete: Bool {
    [service, checkout, availability, storeCondition, wouldReturn].allSatisfy { $0 > 0 }
  }

  private func ratingRow(_ title: String, selection: Binding<Int>) -> some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
      Text(title).font(.system(size: 14, weight: .bold))
      HStack {
        ForEach(1...5, id: \.self) { rating in
          Button {
            selection.wrappedValue = rating
          } label: {
            Image(systemName: rating <= selection.wrappedValue ? "star.fill" : "star")
              .font(.system(size: 24, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.forest)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private func submit() {
    guard let identity = wallet.identity,
          identity.address == record.owner,
          record.isConfirmed else {
      errorMessage = "Unlock the wallet that owns this confirmed proof."
      return
    }
    isSubmitting = true
    Task {
      defer { isSubmitting = false }
      do {
        let eligibility = try await proofs.eligibility(for: record)
        guard eligibility.eligible else {
          throw AuraWalletNativeError.nativeFailure(
            "Contribution policy rejected this action: \(eligibility.reason)."
          )
        }
        let commitment = feedbackCommitment()
        let authorization = try wallet.authorizeFeedback(
          AuraFeedbackAuthorizationRequest(
            chainIdHashHex: AuraExpectedDevnet.chainIdHash,
            proofIdHex: record.proofId,
            feedbackCommitmentHex: commitment
          )
        )
        guard authorization.ownerPublicKeyHex.lowercased() == identity.publicKeyHex.lowercased() else {
          throw AuraWalletGatewayError.walletIdentityMismatch
        }
        result = try await proofs.submitFeedback(
          proofId: record.proofId,
          owner: record.owner,
          feedbackCommitment: commitment,
          authorization: authorization
        )
        await proofs.refreshAll()
      } catch {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      }
    }
  }

  private func feedbackCommitment() -> String {
    let canonical = [
      "aura/contribution/feedback-content/v1",
      record.proofId.lowercased(),
      "service=\(service)",
      "checkout=\(checkout)",
      "availability=\(availability)",
      "store_condition=\(storeCondition)",
      "would_return=\(wouldReturn)",
    ].joined(separator: "\n")
    return SHA256.hash(data: Data(canonical.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }
}
