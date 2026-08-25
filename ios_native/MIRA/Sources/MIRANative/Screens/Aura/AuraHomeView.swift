import SwiftUI

/// Four-tab Aura home feed. It renders only locally recorded proof lifecycle data and validated
/// gateway wallet data; missing social/network content remains an explicit empty state.
public struct AuraHomeView: View {
  let api: MIRAAPIClient
  @ObservedObject private var wallet: AuraWalletStore
  @ObservedObject private var gateway: AuraWalletGatewayStore
  @ObservedObject private var proofs: AuraProofLifecycleStore

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
        LazyVStack(spacing: 16) {
          networkStrip
          proofFeed
          walletFeed
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
      }
      .background(MIRATheme.Color.appBackground.ignoresSafeArea())
      .navigationTitle("Aura")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button { refresh() } label: {
            Image(systemName: "arrow.clockwise")
          }
          .accessibilityLabel("Refresh Aura")
        }
      }
      .refreshable { await refreshData() }
      .task { await refreshData() }
    }
  }

  private var networkStrip: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle().fill(gateway.isConnected ? MIRATheme.Color.forestSoft : MIRATheme.Color.surfaceSoft)
        Image(systemName: gateway.isConnected ? "network.badge.shield.half.filled" : "network.slash")
          .font(.headline)
          .foregroundStyle(gateway.isConnected ? MIRATheme.Color.forest : MIRATheme.Color.textMuted)
      }
      .frame(width: 42, height: 42)

      VStack(alignment: .leading, spacing: 2) {
        Text(gateway.isConnected ? "Aura Devnet connected" : "Aura Devnet unavailable")
          .font(.headline)
        if let status = gateway.chainStatus {
          Text("Block \(status.canonicalHeight) · \(status.connectedPeers) peers")
            .font(.subheadline)
            .foregroundStyle(MIRATheme.Color.textSecondary)
        } else {
          Text(gateway.errorMessage ?? "Validated chain state has not loaded.")
            .font(.subheadline)
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .lineLimit(2)
        }
      }
      Spacer()
    }
    .padding(14)
    .background(MIRATheme.Color.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(MIRATheme.Color.divider, lineWidth: 1)
    }
  }

  @ViewBuilder
  private var proofFeed: some View {
    AuraSectionHeader(title: "Verified activity")
    if proofs.records.isEmpty {
      MIRAEmptyState(
        title: "No verified documents yet",
        message: "Scan a receipt or invoice. Aura will recognize its type and show a ticket only after the real provider returns a result.",
        systemImage: "ticket"
      )
      .padding(.vertical, 18)
      .miraCardSurface(cornerRadius: 18)
    } else {
      ForEach(proofs.records.prefix(5)) { record in
        AuraDocumentTicketCard(
          merchant: record.merchantName,
          documentType: record.documentType ?? "receipt",
          date: record.documentDate,
          currency: record.currency,
          total: record.total,
          status: proofStatus(record),
          statusSystemImage: proofStatusIcon(record),
          statusColor: record.isConfirmed ? MIRATheme.Color.forest : MIRATheme.Color.auraViolet,
          detail: record.blockHeight.map { "Block #\($0)" } ?? shortIdentifier(record.proofId)
        )
      }
    }
  }

  @ViewBuilder
  private var walletFeed: some View {
    AuraSectionHeader(title: "Wallet activity")
    if wallet.state != .unlocked {
      MIRAEmptyState(
        title: wallet.state == .noWallet ? "No wallet on this iPhone" : "Wallet locked",
        message: "Open Wallet to create, restore, or unlock the local Rust wallet.",
        systemImage: "wallet.pass"
      )
      .padding(.vertical, 18)
      .miraCardSurface(cornerRadius: 18)
    } else if let history = gateway.history, !history.transactions.isEmpty {
      VStack(spacing: 0) {
        ForEach(history.transactions.prefix(4)) { transaction in
          transactionRow(transaction)
          if transaction.id != history.transactions.prefix(4).last?.id { Divider() }
        }
      }
      .padding(.horizontal, 14)
      .background(MIRATheme.Color.surface)
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(MIRATheme.Color.divider, lineWidth: 1)
      }
    } else {
      MIRAEmptyState(
        title: gateway.isConnected ? "No blockchain activity" : "Wallet network unavailable",
        message: gateway.isConnected
          ? "Real pending and confirmed AUR transfers will appear here."
          : "Aura cannot show balances or transactions until validated gateway state is available.",
        systemImage: gateway.isConnected ? "clock.arrow.circlepath" : "network.slash"
      )
      .padding(.vertical, 18)
      .miraCardSurface(cornerRadius: 18)
    }
  }

  private func transactionRow(_ transaction: AuraGatewayTransaction) -> some View {
    HStack(spacing: 12) {
      Image(systemName: transaction.direction == "incoming" ? "arrow.down" : "arrow.up")
        .font(.headline)
        .foregroundStyle(transaction.direction == "incoming" ? MIRATheme.Color.forest : MIRATheme.Color.auraViolet)
        .frame(width: 36, height: 36)
        .background(MIRATheme.Color.surfaceSoft, in: Circle())
      VStack(alignment: .leading, spacing: 3) {
        Text(transaction.direction == "incoming" ? "Received AUR" : "Sent AUR")
          .font(.subheadline)
          .fontWeight(.semibold)
        Text(transaction.state.capitalized)
          .font(.caption)
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
      Spacer()
      Text(transactionAmount(transaction))
        .font(.subheadline)
        .fontWeight(.bold)
        .foregroundStyle(transaction.direction == "incoming" ? MIRATheme.Color.forest : MIRATheme.Color.textPrimary)
    }
    .padding(.vertical, 12)
  }

  private func transactionAmount(_ transaction: AuraGatewayTransaction) -> String {
    let amount = AuraAmountCodec.aur(fromAtoms: transaction.amountAtoms) ?? "Unavailable"
    let sign = transaction.direction == "incoming" ? "+" : "−"
    return "\(sign)\(amount) AUR"
  }

  private func proofStatus(_ record: AuraPrivateProofRecord) -> String {
    switch record.state {
    case "confirmed": return "Verified · Confirmed"
    case "included": return "Verified · Included"
    case "pending": return "Verified · Pending"
    default: return "Proof unavailable"
    }
  }

  private func proofStatusIcon(_ record: AuraPrivateProofRecord) -> String {
    switch record.state {
    case "confirmed": return "checkmark.seal.fill"
    case "included": return "cube.fill"
    case "pending": return "clock.fill"
    default: return "exclamationmark.triangle"
    }
  }

  private func shortIdentifier(_ value: String) -> String {
    guard value.count > 12 else { return value }
    return "\(value.prefix(6))…\(value.suffix(4))"
  }

  private func refresh() {
    Task { await refreshData() }
  }

  private func refreshData() async {
    if let identity = wallet.identity {
      await gateway.refresh(identity: identity)
    }
    await proofs.refreshAll()
  }
}
