import SwiftUI

public enum AuraProofStatus: String {
  case pendingVerification = "Pending Verification"
  case verified = "Verified"
  case submitted = "Submitted"
  case pendingBlockchain = "Pending Blockchain"
  case confirmed = "Confirmed"
  case rejected = "Rejected"

  var color: SwiftUI.Color {
    switch self {
    case .confirmed, .verified: return MIRATheme.Color.forest
    case .rejected: return .red
    case .pendingVerification, .submitted, .pendingBlockchain: return MIRATheme.Color.textMuted
    }
  }
}

/// Aura Mobile's Proofs tab: Proof of Purchase, Proof of Invoice, Proof of Paid Invoice, Refund
/// Proof, Return Proof, Service Proof. Empty until connected to a real Aura Mobile Gateway --
/// this screen never fabricates a proof record.
public struct AuraProofsView: View {
  let api: MIRAAPIClient

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        MIRAEmptyState(
          title: "No proofs yet",
          message: "Proof of Purchase, Proof of Invoice, and other verified-document proofs will appear here once a scanned document is verified and submitted to Aura.",
          systemImage: "checkmark.seal"
        )
        .miraCardSurface()
        .padding(MIRATheme.Space.lg)
      }
      .background(MIRATheme.Color.appBackground.ignoresSafeArea())
      .navigationTitle("Proofs")
    }
  }
}
