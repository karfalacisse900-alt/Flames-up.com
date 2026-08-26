import SwiftUI

/// Account surface for the four-tab Aura shell. Profile fields come from the authenticated user,
/// while wallet/proof counts come only from local encrypted wallet and canonical proof state.
public struct AuraMeView: View {
  let api: MIRAAPIClient
  @ObservedObject private var authSession: MIRAAuthSession
  @ObservedObject private var wallet: AuraWalletStore
  @ObservedObject private var gateway: AuraWalletGatewayStore
  @ObservedObject private var proofs: AuraProofLifecycleStore
  let openWallet: () -> Void

  public init(
    api: MIRAAPIClient,
    authSession: MIRAAuthSession,
    wallet: AuraWalletStore,
    gateway: AuraWalletGatewayStore,
    proofs: AuraProofLifecycleStore,
    openWallet: @escaping () -> Void
  ) {
    self.api = api
    self.authSession = authSession
    self.wallet = wallet
    self.gateway = gateway
    self.proofs = proofs
    self.openWallet = openWallet
  }

  public var body: some View {
    NavigationStack {
      ScrollView(showsIndicators: false) {
        VStack(spacing: 13) {
          profileCard
          walletCard
          proofStats
          accountMenu
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 28)
      }
      .background(MIRATheme.Color.paperCanvas.ignoresSafeArea())
      .navigationTitle("Me")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(MIRATheme.Color.paperCanvas, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          NavigationLink {
            SettingsNativeView(api: api, authSession: authSession)
          } label: {
            Image(systemName: "gearshape")
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .frame(width: 34, height: 34)
              .background(MIRATheme.Color.paperSurface, in: Circle())
              .overlay { Circle().stroke(MIRATheme.Color.inkBorder, lineWidth: 1.2) }
              .shadow(color: MIRATheme.Color.hardShadow, radius: 0, x: 0, y: 2)
              .padding(.bottom, 2)
          }
          .accessibilityLabel("Settings")
        }
      }
    }
  }

  private var profileCard: some View {
    HStack(spacing: 14) {
      RemoteAvatar(url: authSession.user?.profileImage, size: 72)
        .overlay { Circle().stroke(MIRATheme.Color.inkBorder, lineWidth: 1.25) }
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 5) {
          Text(profileDisplayName)
            .font(.title3)
            .fontWeight(.bold)
          if authSession.user?.isVerified == true {
            Image(systemName: "checkmark.seal.fill")
              .foregroundStyle(MIRATheme.Color.auraViolet)
              .accessibilityLabel("Verified profile")
          }
        }
        Text(username)
          .font(.subheadline)
          .foregroundStyle(MIRATheme.Color.textSecondary)
        if let bio = authSession.user?.bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Text(bio)
            .font(.subheadline)
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(3)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(16)
    .physicalAuraCard(cornerRadius: 18)
  }

  private var walletCard: some View {
    HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Wallet balance")
          .font(.subheadline)
          .foregroundStyle(MIRATheme.Color.textSecondary)
        Text(walletBalance)
          .font(.title2)
          .fontWeight(.bold)
        Text(walletStatus)
          .font(.caption)
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
      Spacer()
      Button("View Wallet", action: openWallet)
        .buttonStyle(AuraTactilePrimaryButtonStyle())
    }
    .padding(16)
    .physicalAuraCard(cornerRadius: 18)
  }

  private var proofStats: some View {
    HStack(spacing: 0) {
      stat(value: String(proofs.records.count), label: "Proofs", systemImage: "checkmark.seal")
      Rectangle().fill(MIRATheme.Color.inkBorder.opacity(0.24)).frame(width: 1, height: 52)
      stat(value: String(confirmedProofCount), label: "Confirmed", systemImage: "cube.fill")
      Rectangle().fill(MIRATheme.Color.inkBorder.opacity(0.24)).frame(width: 1, height: 52)
      stat(value: String(feedbackCount), label: "Aura given", systemImage: "star.bubble")
    }
    .padding(.vertical, 16)
    .physicalAuraCard(cornerRadius: 18)
  }

  private var accountMenu: some View {
    VStack(spacing: 0) {
      NavigationLink {
        AuraMyCommunityView(api: api, scope: "created", title: "My Posts")
      } label: {
        menuRow("My Posts", systemImage: "square.and.pencil")
      }
      Divider().overlay(MIRATheme.Color.inkBorder.opacity(0.20)).padding(.leading, 52)
      NavigationLink {
        AuraMyCommunityView(api: api, scope: "joined", title: "Joined Meetups")
      } label: {
        menuRow("Joined Meetups", systemImage: "person.2")
      }
      Divider().overlay(MIRATheme.Color.inkBorder.opacity(0.20)).padding(.leading, 52)
      NavigationLink {
        AuraProofsView(api: api, proofs: proofs)
      } label: {
        menuRow("My Proofs", systemImage: "ticket")
      }
      Divider().overlay(MIRATheme.Color.inkBorder.opacity(0.20)).padding(.leading, 52)
      NavigationLink {
        AuraReputationView(api: api, wallet: wallet, proofs: proofs)
      } label: {
        menuRow("Leave Aura", systemImage: "star.bubble")
      }
      Divider().overlay(MIRATheme.Color.inkBorder.opacity(0.20)).padding(.leading, 52)
      NavigationLink {
        SettingsNativeView(api: api, authSession: authSession)
      } label: {
        menuRow("Privacy & Settings", systemImage: "lock.shield")
      }
      Divider().overlay(MIRATheme.Color.inkBorder.opacity(0.20)).padding(.leading, 52)
      NavigationLink {
        TermsOfServiceView()
      } label: {
        menuRow("About Aura", systemImage: "info.circle")
      }
    }
    .physicalAuraCard(cornerRadius: 18)
  }

  private func stat(value: String, label: String, systemImage: String) -> some View {
    VStack(spacing: 6) {
      Image(systemName: systemImage)
        .foregroundStyle(MIRATheme.Color.auraViolet)
      Text(value)
        .font(.title3)
        .fontWeight(.bold)
      Text(label)
        .font(.caption)
        .foregroundStyle(MIRATheme.Color.textSecondary)
    }
    .frame(maxWidth: .infinity)
  }

  private func menuRow(_ title: String, systemImage: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.headline)
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(width: 24)
      Text(title)
        .font(.body)
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Spacer()
      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundStyle(MIRATheme.Color.textMuted)
    }
    .padding(.horizontal, 16)
    .frame(minHeight: 50)
    .contentShape(Rectangle())
  }

  private var username: String {
    guard let username = authSession.user?.username,
          !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return "Username unavailable"
    }
    return "@\(username)"
  }

  private var profileDisplayName: String {
    if let fullName = authSession.user?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines),
       !fullName.isEmpty {
      return fullName
    }
    return authSession.user?.displayName ?? "Aura member"
  }

  private var walletBalance: String {
    guard wallet.state == .unlocked else { return "Unavailable" }
    return gateway.confirmedAUR.map { "\($0) AUR" } ?? "Unavailable"
  }

  private var walletStatus: String {
    switch wallet.state {
    case .unlocked:
      return gateway.isConnected ? "Validated Aura Devnet state" : "Gateway unavailable"
    case .locked: return "Encrypted wallet locked"
    case .noWallet: return "No wallet on this iPhone"
    case .unavailable: return "Wallet storage unavailable"
    }
  }

  private var confirmedProofCount: Int {
    proofs.records.filter(\.isConfirmed).count
  }

  private var feedbackCount: Int {
    proofs.records.filter(\.feedbackUsed).count
  }
}
