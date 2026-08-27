import SwiftUI
import UIKit

/// Editorial account surface for the four-tab Aura shell. Profile fields come from the
/// authenticated user, while Wallet and journal destinations retain their real stores/actions.
public struct AuraMeView: View {
  let api: MIRAAPIClient
  @ObservedObject private var authSession: MIRAAuthSession
  @ObservedObject private var wallet: AuraWalletStore
  @ObservedObject private var gateway: AuraWalletGatewayStore
  @ObservedObject private var proofs: AuraProofLifecycleStore
  let openWallet: () -> Void
  @State private var isEditingProfile = false

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
        LazyVStack(alignment: .leading, spacing: 0) {
          profileHeader

          Divider()
            .padding(.vertical, 18)

          walletShortcut

          Divider()
            .padding(.vertical, 18)

          journal
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 36)
      }
      .background(Color(uiColor: .systemBackground).ignoresSafeArea())
      .navigationTitle("Me")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .sheet(isPresented: $isEditingProfile) {
        EditProfileNativeView(
          user: authSession.user,
          api: api,
          onCancel: { isEditingProfile = false }
        ) { updatedUser in
          Task { @MainActor in
            authSession.replaceUser(updatedUser)
            isEditingProfile = false
          }
        }
      }
    }
  }

  private var profileHeader: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 16) {
        RemoteAvatar(url: authSession.user?.profileImage, size: 88)

        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 6) {
            Text(profileDisplayName)
              .font(.title2)
              .fontWeight(.bold)
            if authSession.user?.isVerified == true {
              Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(MIRATheme.Color.auraViolet)
                .accessibilityLabel("Verified profile")
            }
          }

          if let profileUsername {
            Text(profileUsername)
              .font(.subheadline)
              .foregroundStyle(MIRATheme.Color.textSecondary)
          }

          if let profileLocation {
            Label(profileLocation, systemImage: "mappin.and.ellipse")
              .font(.subheadline)
              .foregroundStyle(MIRATheme.Color.textMuted)
          }
        }

        Spacer(minLength: 0)
      }

      if let profileBio {
        Text(profileBio)
          .font(.body)
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if authSession.user?.followersCount != nil || authSession.user?.followingCount != nil {
        HStack(spacing: 24) {
          if let followers = authSession.user?.followersCount {
            profileMetric(value: followers, label: "Followers")
          }
          if let following = authSession.user?.followingCount {
            profileMetric(value: following, label: "Following")
          }
        }
      }

      HStack(spacing: 10) {
        Button {
          isEditingProfile = true
        } label: {
          Label("Edit Profile", systemImage: "pencil")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(MIRATheme.Color.auraViolet)

        NavigationLink {
          SettingsNativeView(api: api, authSession: authSession)
        } label: {
          Label("Settings", systemImage: "gearshape")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(MIRATheme.Color.textSecondary)
      }
    }
  }

  private var walletShortcut: some View {
    Button(action: openWallet) {
      HStack(spacing: 13) {
        Image(systemName: "wallet.pass")
          .font(.title3.weight(.semibold))
          .foregroundStyle(MIRATheme.Color.auraViolet)
          .frame(width: 30)

        VStack(alignment: .leading, spacing: 3) {
          Text("Wallet")
            .font(.headline)
            .foregroundStyle(MIRATheme.Color.textPrimary)
          Text(walletStatus)
            .font(.caption)
            .foregroundStyle(MIRATheme.Color.textMuted)
            .lineLimit(1)
        }

        Spacer(minLength: 8)

        Text(walletBalance)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .multilineTextAlignment(.trailing)

        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Open Wallet, \(walletBalance), \(walletStatus)")
  }

  private var journal: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Your journal")
        .font(.title2)
        .fontWeight(.bold)
        .padding(.bottom, 8)

      NavigationLink {
        AuraMyCommunityView(api: api, scope: "created", title: "My Posts")
      } label: {
        journalRow("Posts", subtitle: "Your published community posts", systemImage: "square.and.pencil")
      }
      Divider().padding(.leading, 38)

      NavigationLink {
        AuraMyCommunityView(api: api, scope: "joined", title: "Joined Meetups")
      } label: {
        journalRow("Joined", subtitle: "Meetups you have joined", systemImage: "person.2")
      }
      Divider().padding(.leading, 38)

      NavigationLink {
        AuraProofsView(api: api, proofs: proofs)
      } label: {
        journalRow("Proofs", subtitle: "Your private proof history", systemImage: "checkmark.seal")
      }
      Divider().padding(.leading, 38)

      NavigationLink {
        AuraReputationView(api: api, wallet: wallet, proofs: proofs)
      } label: {
        journalRow("Reputation", subtitle: "Verified feedback and Aura", systemImage: "star.bubble")
      }
      Divider().padding(.leading, 38)

      NavigationLink {
        SettingsNativeView(api: api, authSession: authSession)
      } label: {
        journalRow("Settings", subtitle: "Privacy, notifications, and account", systemImage: "gearshape")
      }
    }
  }

  private func profileMetric(value: Int, label: String) -> some View {
    HStack(spacing: 4) {
      Text(value.formatted())
        .font(.subheadline.weight(.bold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Text(label)
        .font(.subheadline)
        .foregroundStyle(MIRATheme.Color.textSecondary)
    }
  }

  private func journalRow(_ title: String, subtitle: String, systemImage: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.headline)
        .foregroundStyle(MIRATheme.Color.auraViolet)
        .frame(width: 26)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.body.weight(.semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(MIRATheme.Color.textMuted)
      }

      Spacer()

      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
    }
    .frame(minHeight: 58)
    .contentShape(Rectangle())
  }

  private var profileUsername: String? {
    guard let username = authSession.user?.username,
          !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return "@\(username)"
  }

  private var profileBio: String? {
    guard let bio = authSession.user?.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty else {
      return nil
    }
    return bio
  }

  private var profileLocation: String? {
    guard let city = authSession.user?.city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty else {
      return nil
    }
    return city
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
}
