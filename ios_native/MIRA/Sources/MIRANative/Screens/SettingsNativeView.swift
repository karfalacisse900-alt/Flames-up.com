import AuthenticationServices
import GoogleSignIn
import SwiftUI
import UIKit
import UserNotifications

private struct SettingsProfileUpdateBody: Encodable {
  let isPrivate: Bool?
  let language: String?
}

private struct SettingsEmailBody: Encodable {
  let email: String
}

private struct SettingsPasswordBody: Encodable {
  let newPassword: String
}

private struct SettingsMessageResponse: Decodable {
  let detail: String?
  let deleted: Bool?
}

private struct SettingsAccountDeletionBody: Encodable {
  let confirmation: String
  let password: String?
  let provider: String?
  let idToken: String?
  let accessToken: String?
  let authorizationCode: String?
}

private struct SettingsAccountDeletionResponse: Decodable {
  let deletionPending: Bool?
  let deletionRequestedAt: String?
  let deletionScheduledAt: String?
  let detail: String?
}

private struct SettingsBlockedAccount: Decodable, Identifiable, Hashable {
  let blockedId: String
  let createdAt: String?
  let user: MIRAUser?

  var id: String { blockedId }
}

@MainActor
final class SettingsNativeModel: ObservableObject {
  @Published var user: MIRAUser?
  @Published var isPrivate = false
  @Published var language = MIRALanguageResolver.storedPreference()
  @Published var email = ""
  @Published var isLoading = false
  @Published var isSavingPrivacy = false
  @Published var isSavingLanguage = false
  @Published var isSavingEmail = false
  @Published var isSavingPassword = false
  @Published var isDeletingAccount = false
  @Published var bannerMessage: String?
  @Published var bannerIsError = false

  let api: MIRAAPIClient
  private weak var authSession: MIRAAuthSession?

  init(api: MIRAAPIClient, authSession: MIRAAuthSession?) {
    self.api = api
    self.authSession = authSession
    apply(user: authSession?.user)
  }

  func load() async {
    guard !isLoading else { return }
    if user == nil, let cached = await MIRAAppCacheStore.shared.loadSettings() {
      user = cached.user
      isPrivate = cached.isPrivate
      language = cached.language
      email = cached.user?.email ?? email
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let fresh: MIRAUser = try await api.get("/auth/me")
      apply(user: fresh)
      await MIRAAppCacheStore.shared.saveSettings(user: fresh, language: language, isPrivate: isPrivate)
      authSession?.replaceUser(fresh)
    } catch {
      if user == nil {
        show(MIRALocalization.shared.string("common.error"), isError: true)
      }
    }
  }

  func updatePrivacy(_ value: Bool) async {
    let previous = isPrivate
    isPrivate = value
    isSavingPrivacy = true
    defer { isSavingPrivacy = false }
    do {
      let updated: MIRAUser = try await api.put(
        "/users/me",
        body: SettingsProfileUpdateBody(isPrivate: value, language: nil)
      )
      apply(user: updated)
      await MIRAAppCacheStore.shared.saveSettings(user: updated, language: language, isPrivate: isPrivate)
      authSession?.replaceUser(updated)
      show(value ? "Private account is on." : "Private account is off.")
    } catch {
      isPrivate = previous
      show(MIRALocalization.shared.string("common.error"), isError: true)
    }
  }

  func updateLanguage(_ value: String) async {
    let previous = language
    language = value
    MIRALocalization.shared.setPreference(value)
    isSavingLanguage = true
    defer { isSavingLanguage = false }
    do {
      let backendLanguage = MIRALanguageResolver.resolvedLanguageCode(for: value)
      let updated: MIRAUser = try await api.put(
        "/users/me",
        body: SettingsProfileUpdateBody(isPrivate: nil, language: backendLanguage)
      )
      apply(user: updated)
      await MIRAAppCacheStore.shared.saveSettings(user: updated, language: value, isPrivate: isPrivate)
      authSession?.replaceUser(updated)
      language = value
      MIRALocalization.shared.setPreference(value)
      show(MIRALocalization.shared.string("settings.language_updated"))
    } catch {
      language = previous
      MIRALocalization.shared.setPreference(previous)
      show(MIRALocalization.shared.string("settings.language_failed"), isError: true)
    }
  }

  func updateEmail(newEmail: String) async -> Bool {
    let cleanEmail = newEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard cleanEmail.contains("@"), cleanEmail.contains(".") else {
      show("Enter a valid email address.", isError: true)
      return false
    }
    isSavingEmail = true
    defer { isSavingEmail = false }
    do {
      let updated: MIRAUser = try await api.put(
        "/users/me/email",
        body: SettingsEmailBody(email: cleanEmail)
      )
      apply(user: updated)
      await MIRAAppCacheStore.shared.saveSettings(user: updated, language: language, isPrivate: isPrivate)
      authSession?.replaceUser(updated)
      show("Email updated.")
      return true
    } catch {
      show("Could not update email. Try again in a moment.", isError: true)
      return false
    }
  }

  func updatePassword(newPassword: String) async -> Bool {
    guard !newPassword.isEmpty else {
      show("Enter a new password.", isError: true)
      return false
    }
    guard newPassword.count >= 8 else {
      show("New password must be at least 8 characters.", isError: true)
      return false
    }
    isSavingPassword = true
    defer { isSavingPassword = false }
    do {
      let _: SettingsMessageResponse = try await api.put(
        "/users/me/password",
        body: SettingsPasswordBody(newPassword: newPassword)
      )
      show("Password updated.")
      return true
    } catch {
      show("Could not update password. Try again in a moment.", isError: true)
      return false
    }
  }

  func deleteAccount(confirmation: String, password: String?, provider: String?, idToken: String?, accessToken: String?, authorizationCode: String?) async -> Bool {
    isDeletingAccount = true
    defer { isDeletingAccount = false }
    do {
      let response: SettingsAccountDeletionResponse = try await api.post(
        "/account/delete",
        body: SettingsAccountDeletionBody(
          confirmation: confirmation,
          password: password?.isEmpty == false ? password : nil,
          provider: provider?.isEmpty == false ? provider : nil,
          idToken: idToken?.isEmpty == false ? idToken : nil,
          accessToken: accessToken?.isEmpty == false ? accessToken : nil,
          authorizationCode: authorizationCode?.isEmpty == false ? authorizationCode : nil
        )
      )
      show(response.detail ?? "Account deletion is scheduled.")
      authSession?.logout()
      return true
    } catch {
      if let apiError = error as? MIRAAPIError, let message = apiError.errorDescription, !message.isEmpty {
        show(message, isError: true)
      } else {
        show("Could not delete your account right now.", isError: true)
      }
      return false
    }
  }

  func logout() {
    authSession?.logout()
  }

  private func apply(user: MIRAUser?) {
    self.user = user
    isPrivate = user?.isPrivate == true
    language = MIRALanguageResolver.storedPreference()
    email = user?.email ?? ""
  }

  private func show(_ message: String, isError: Bool = false) {
    bannerMessage = message
    bannerIsError = isError
  }

  private func supportedLanguage(_ raw: String?) -> String {
    let normalized = (raw ?? "system").lowercased()
    return ["system", "en", "fr", "es"].contains(normalized) ? normalized : "system"
  }
}

public struct SettingsNativeView: View {
  @StateObject private var model: SettingsNativeModel
  @EnvironmentObject private var localization: MIRALocalization

  public init(api: MIRAAPIClient, authSession: MIRAAuthSession? = nil) {
    _model = StateObject(wrappedValue: SettingsNativeModel(api: api, authSession: authSession))
  }

  public var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 14) {
        settingsHero

        if let message = model.bannerMessage {
          SettingsBanner(message: message, isError: model.bannerIsError)
        }

        SettingsCard(title: localization.string("settings.account")) {
          SettingsNavigationRow(
            title: localization.string("settings.privacy"),
            subtitle: model.isPrivate ? "Private account is on" : "Public account",
            systemImage: "lock",
            destination: PrivacySettingsNativeView(model: model)
          )
          SettingsNavigationRow(
            title: localization.string("settings.notifications"),
            subtitle: "Push, likes, comments, messages",
            systemImage: "bell",
            destination: NotificationSettingsNativeView()
          )
          SettingsNavigationRow(
            title: localization.string("settings.security"),
            subtitle: "Email, password, account actions",
            systemImage: "shield",
            destination: SecuritySettingsNativeView(model: model)
          )
        }

        SettingsCard(title: localization.string("settings.preferences")) {
          SettingsNavigationRow(
            title: "Appearance & cache",
            subtitle: "Dark mode and clear cache",
            systemImage: "circle.lefthalf.filled",
            destination: PreferenceSettingsNativeView()
          )
        }

        SettingsCard(title: localization.string("settings.legal_safety")) {
          SettingsNavigationRow(
            title: localization.string("legal.terms"),
            subtitle: "Rules for using Captro",
            systemImage: "doc.text",
            destination: TermsOfServiceView()
          )
          SettingsNavigationRow(
            title: localization.string("legal.privacy"),
            subtitle: "How Captro handles data",
            systemImage: "hand.raised",
            destination: PrivacyPolicyView()
          )
          SettingsNavigationRow(
            title: localization.string("legal.community"),
            subtitle: "Posting, chat, and safety rules",
            systemImage: "person.2",
            destination: CommunityGuidelinesView()
          )
          SettingsNavigationRow(
            title: localization.string("legal.safety"),
            subtitle: "Report, block, and stay safe",
            systemImage: "shield.lefthalf.filled",
            destination: SafetyReportingView()
          )
        }
      }
      .padding(.horizontal, 18)
      .padding(.top, 12)
      .padding(.bottom, MIRATheme.Space.xxl)
    }
    .background(MIRATheme.Color.appBackground.ignoresSafeArea())
    .miraScreenEnter(.push)
    .navigationTitle(localization.string("settings.title"))
    .navigationBarTitleDisplayMode(.inline)
    .miraHideTabBarOnAppear()
    .task { await model.load() }
  }

  private var settingsHero: some View {
    HStack(spacing: 12) {
      RemoteAvatar(url: model.user?.profileImage, size: 48)
      VStack(alignment: .leading, spacing: 2) {
        Text(model.user?.displayName ?? "Captro")
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text(model.email.isEmpty ? localization.string("settings.manage_account") : model.email)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(1)
      }
      Spacer()
      if model.isLoading {
        ProgressView()
          .tint(MIRATheme.Color.forest)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .settingsPillSurface(cornerRadius: 28)
  }
}

private struct PrivacySettingsNativeView: View {
  @ObservedObject var model: SettingsNativeModel
  @AppStorage("mira.settings.show_activity_status") private var showActivityStatus = true
  @AppStorage("mira.settings.allow_message_requests") private var allowMessageRequests = true
  @AppStorage("mira.settings.story_replies") private var allowStoryReplies = true

  var body: some View {
    SettingsDetailScaffold(title: "Privacy") {
      SettingsCard(title: "Profile") {
        SettingsToggleRow(
          title: "Private account",
          subtitle: "Only approved people can see private profile content.",
          systemImage: "lock.fill",
          isOn: Binding(
            get: { model.isPrivate },
            set: { value in Task { await model.updatePrivacy(value) } }
          ),
          isLoading: model.isSavingPrivacy
        )
      }

      SettingsCard(title: "Interactions") {
        SettingsToggleRow(
          title: "Activity status",
          subtitle: "Let people see when you are recently active.",
          systemImage: "dot.radiowaves.left.and.right",
          isOn: $showActivityStatus
        )
        SettingsToggleRow(
          title: "Message requests",
          subtitle: "Allow people to message you from your profile.",
          systemImage: "message",
          isOn: $allowMessageRequests
        )
        SettingsToggleRow(
          title: "Story replies",
          subtitle: "Allow replies on stories.",
          systemImage: "bubble.left",
          isOn: $allowStoryReplies
        )
      }

      SettingsCard(title: "Privacy tools") {
        SettingsNavigationRow(title: "Blocked accounts", subtitle: "Review and unblock people.", systemImage: "person.crop.circle.badge.xmark", destination: BlockedAccountsNativeView(api: model.api))
        SettingsNavigationRow(title: "Privacy Policy", subtitle: "Read how data is handled", systemImage: "hand.raised", destination: PrivacyPolicyView())
        SettingsNavigationRow(title: "Safety & Reporting", subtitle: "Report abuse or unsafe behavior", systemImage: "shield.lefthalf.filled", destination: SafetyReportingView())
        SettingsLinkRow(title: "Data deletion", subtitle: "Learn how account deletion works", systemImage: "trash", url: MIRAProductionBackend.siteURL("data-deletion"))
      }
    }
  }
}

private struct BlockedAccountsNativeView: View {
  let api: MIRAAPIClient
  @State private var rows: [SettingsBlockedAccount] = []
  @State private var isLoading = false
  @State private var errorMessage: String?

  var body: some View {
    SettingsDetailScaffold(title: "Blocked accounts") {
      SettingsCard(title: "People you blocked") {
        if isLoading && rows.isEmpty {
          VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
              SettingsRowContent(title: "Loading", subtitle: "Blocked account", systemImage: "person") {
                ProgressView()
              }
              .redacted(reason: .placeholder)
            }
          }
        } else if rows.isEmpty {
          VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
            Image(systemName: "person.crop.circle.badge.checkmark")
              .font(.system(size: 24, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.forest)
            Text("No blocked accounts")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textPrimary)
            Text("People you block will show here so you can manage them later.")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(MIRATheme.Color.textSecondary)
          }
          .padding(MIRATheme.Space.md)
        } else {
          ForEach(rows) { row in
            blockedRow(row)
          }
        }
      }

      if let errorMessage {
        SettingsBanner(message: errorMessage, isError: true)
      }
    }
    .task { await load() }
  }

  private func blockedRow(_ row: SettingsBlockedAccount) -> some View {
    HStack(spacing: MIRATheme.Space.sm) {
      RemoteAvatar(url: row.user?.profileImage, size: 38)
      VStack(alignment: .leading, spacing: 3) {
        Text(row.user?.displayName ?? "Captro user")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
        Text(row.user?.username.map { "@\(MIRAUsernameRules.normalized($0))" } ?? "Blocked account")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(1)
      }
      Spacer()
      Button {
        Task { await unblock(row) }
      } label: {
        Text("Unblock")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .frame(height: 30)
          .background(MIRATheme.Color.forest)
          .clipShape(Capsule())
      }
      .buttonStyle(.miraPress)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(minHeight: 58)
    .settingsPillSurface(cornerRadius: 26)
  }

  @MainActor
  private func load() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      rows = try await api.get("/blocks")
      errorMessage = nil
    } catch {
      errorMessage = "Could not load blocked accounts."
    }
  }

  @MainActor
  private func unblock(_ row: SettingsBlockedAccount) async {
    do {
      let _: SettingsMessageResponse = try await api.delete("/users/\(row.blockedId)/block")
      rows.removeAll { $0.id == row.id }
      errorMessage = nil
    } catch {
      errorMessage = "Could not unblock this account."
    }
  }
}

private struct NotificationSettingsNativeView: View {
  @AppStorage("mira.settings.push_enabled") private var pushEnabled = false
  @AppStorage("mira.settings.notify_likes") private var notifyLikes = true
  @AppStorage("mira.settings.notify_comments") private var notifyComments = true
  @AppStorage("mira.settings.notify_follows") private var notifyFollows = true
  @AppStorage("mira.settings.notify_messages") private var notifyMessages = true
  @AppStorage("mira.settings.notify_posts") private var notifyPosts = true
  @AppStorage("mira.settings.email_updates") private var emailUpdates = false
  @State private var authorizationStatus = "Checking..."

  var body: some View {
    SettingsDetailScaffold(title: "Notifications") {
      SettingsCard(title: "Device") {
        SettingsToggleRow(
          title: "Push notifications",
          subtitle: "Use iPhone notifications for important activity.",
          systemImage: "bell.badge",
          isOn: Binding(
            get: { pushEnabled },
            set: { value in
              if value {
                Task { await requestPushPermission() }
              } else {
                pushEnabled = false
              }
            }
          )
        )
        SettingsButtonRow(title: "iOS notification settings", subtitle: authorizationStatus, systemImage: "gearshape") {
          openAppSettings()
        }
      }

      SettingsCard(title: "Activity") {
        SettingsToggleRow(title: "Likes", subtitle: "When someone likes your post or note.", systemImage: "heart", isOn: $notifyLikes)
        SettingsToggleRow(title: "Comments and replies", subtitle: "When someone comments or replies.", systemImage: "bubble.left", isOn: $notifyComments)
        SettingsToggleRow(title: "Follows", subtitle: "When someone follows you.", systemImage: "person.badge.plus", isOn: $notifyFollows)
        SettingsToggleRow(title: "Messages", subtitle: "New chat messages and calls.", systemImage: "message", isOn: $notifyMessages)
        SettingsToggleRow(title: "New posts", subtitle: "When people you follow post.", systemImage: "photo.on.rectangle", isOn: $notifyPosts)
        SettingsToggleRow(title: "Email updates", subtitle: "Occasional account and safety emails.", systemImage: "envelope", isOn: $emailUpdates)
      }
    }
    .task { await refreshNotificationStatus() }
  }

  private func requestPushPermission() async {
    do {
      let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
      pushEnabled = granted
      if granted {
        MIRAPushNotificationRegistrar.registerForRemoteNotifications()
      }
      await refreshNotificationStatus()
    } catch {
      pushEnabled = false
      await refreshNotificationStatus()
    }
  }

  private func refreshNotificationStatus() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    switch settings.authorizationStatus {
    case .authorized:
      authorizationStatus = "Allowed"
    case .provisional:
      authorizationStatus = "Quiet notifications allowed"
    case .denied:
      authorizationStatus = "Blocked in iOS Settings"
    case .notDetermined:
      authorizationStatus = "Not requested yet"
    case .ephemeral:
      authorizationStatus = "Temporary permission"
    @unknown default:
      authorizationStatus = "Unknown"
    }
    pushEnabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
  }
}

private struct SecuritySettingsNativeView: View {
  @ObservedObject var model: SettingsNativeModel
  @State private var newEmail = ""
  @State private var newPassword = ""
  @State private var showLogoutConfirm = false

  var body: some View {
    SettingsDetailScaffold(title: "Security") {
      SettingsCard(title: "Email") {
        SettingsTextField(title: "Email", text: $newEmail, keyboardType: .emailAddress)
        Text("Uses your signed-in Captro session. Log out on shared devices.")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .padding(.horizontal, 8)
          .padding(.bottom, 2)
        SettingsActionButton(title: model.isSavingEmail ? "Saving..." : "Update email", disabled: model.isSavingEmail) {
          Task {
            _ = await model.updateEmail(newEmail: newEmail)
          }
        }
      }

      SettingsCard(title: "Password") {
        SettingsSecureField(title: "New password", text: $newPassword)
        Text("Minimum 8 characters. This updates the login password for your signed-in account.")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textMuted)
          .padding(.horizontal, 8)
          .padding(.bottom, 2)
        SettingsActionButton(title: model.isSavingPassword ? "Saving..." : "Update password", disabled: model.isSavingPassword) {
          Task {
            if await model.updatePassword(newPassword: newPassword) {
              newPassword = ""
            }
          }
        }
      }

      SettingsCard(title: "Account") {
        SettingsButtonRow(title: "Log out", subtitle: "Sign out on this device.", systemImage: "rectangle.portrait.and.arrow.right", tint: .red) {
          showLogoutConfirm = true
        }
        NavigationLink(destination: DeleteAccountNativeView(model: model)) {
          SettingsRowContent(title: "Delete account", subtitle: "Hide now, permanently delete after 30 days.", systemImage: "trash", tint: .red) {
            Image(systemName: "chevron.right")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(MIRATheme.Color.textMuted)
          }
        }
        .buttonStyle(.miraPress)
      }
    }
    .onAppear {
      if newEmail.isEmpty { newEmail = model.email }
    }
    .confirmationDialog("Log out?", isPresented: $showLogoutConfirm) {
      Button("Log out", role: .destructive) { model.logout() }
      Button("Cancel", role: .cancel) {}
    }
  }
}

private struct DeleteAccountNativeView: View {
  @ObservedObject var model: SettingsNativeModel
  @Environment(\.dismiss) private var dismiss

  @State private var confirmation = ""
  @State private var password = ""
  @State private var oauthProvider = ""
  @State private var oauthIdToken = ""
  @State private var oauthAccessToken = ""
  @State private var oauthAuthorizationCode = ""
  @State private var localError: String?

  private var provider: String {
    (model.user?.authProvider ?? "").lowercased()
  }

  private var needsOAuthReauth: Bool {
    provider.contains("apple") || provider.contains("google")
  }

  private var canSubmit: Bool {
    confirmation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE"
      && (needsOAuthReauth ? !oauthIdToken.isEmpty : !password.isEmpty)
      && !model.isDeletingAccount
  }

  var body: some View {
    SettingsDetailScaffold(title: "Delete account") {
      SettingsCard(title: "What happens") {
        VStack(alignment: .leading, spacing: 12) {
          warningRow("Your profile, posts, comments, likes, follows, saved items, and push tokens are hidden immediately.")
          warningRow("Captro schedules permanent deletion for 30 days from now.")
          warningRow("Signing in during that window lets you restore the account.")
          warningRow("After permanent deletion, old posts, followers, likes, messages, username, and media are not restored.")
        }
        .padding(16)
        .settingsPillSurface(cornerRadius: 28)
      }

      SettingsCard(title: "Confirm") {
        Text("Type DELETE to continue.")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .padding(.horizontal, 8)
        SettingsTextField(title: "DELETE", text: $confirmation)
          .textInputAutocapitalization(.characters)
      }

      if needsOAuthReauth {
        SettingsCard(title: "Recent sign in") {
          Text(provider.contains("apple") ? "Confirm with Sign in with Apple before deletion." : "Confirm with Google before deletion.")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .padding(.horizontal, 8)

          if provider.contains("apple") {
            appleReauthButton
          } else {
            googleReauthButton
          }

          if !oauthIdToken.isEmpty {
            Label("Recent sign in confirmed", systemImage: "checkmark.circle.fill")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(.green)
              .padding(.horizontal, 8)
          }
        }
      } else {
        SettingsCard(title: "Password") {
          SettingsSecureField(title: "Current password", text: $password)
          Text("Recent authentication is required before Captro can schedule deletion.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textMuted)
            .padding(.horizontal, 8)
        }
      }

      if let message = localError ?? (model.bannerIsError ? model.bannerMessage : nil) {
        SettingsBanner(message: message, isError: true)
      }

      SettingsActionButton(
        title: model.isDeletingAccount ? "Scheduling deletion..." : "Delete account",
        disabled: !canSubmit,
        tint: .red
      ) {
        Task {
          localError = nil
          let success = await model.deleteAccount(
            confirmation: confirmation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            password: needsOAuthReauth ? nil : password,
            provider: needsOAuthReauth ? (oauthProvider.isEmpty ? provider : oauthProvider) : "email",
            idToken: oauthIdToken,
            accessToken: oauthAccessToken,
            authorizationCode: oauthAuthorizationCode
          )
          if success {
            dismiss()
          } else {
            localError = model.bannerMessage ?? "Could not delete your account right now."
          }
        }
      }
    }
  }

  private func warningRow(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.circle")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.red)
        .frame(width: 20)
      Text(text)
        .font(.system(size: 13.5, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var appleReauthButton: some View {
    SignInWithAppleButton(.continue) { request in
      request.requestedScopes = []
    } onCompletion: { result in
      switch result {
      case .success(let authorization):
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
          localError = "Apple could not confirm your sign in."
          return
        }
        oauthProvider = "apple"
        oauthIdToken = token
        oauthAccessToken = ""
        oauthAuthorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        localError = nil
      case .failure:
        localError = "Apple sign in could not finish."
      }
    }
    .signInWithAppleButtonStyle(.black)
    .frame(height: 52)
    .clipShape(Capsule())
  }

  private var googleReauthButton: some View {
    Button {
      startGoogleReauth()
    } label: {
      HStack(spacing: 10) {
        Image(systemName: "g.circle.fill")
          .font(.system(size: 18, weight: .semibold))
        Text(oauthIdToken.isEmpty ? "Confirm with Google" : "Google confirmed")
          .font(.system(size: 15, weight: .bold))
      }
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .frame(maxWidth: .infinity)
      .frame(height: 52)
      .background(MIRATheme.Color.surface)
      .clipShape(Capsule())
    }
    .buttonStyle(.miraPress)
  }

  private var googleClientID: String {
    Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
      ?? "702354172189-9gg83vd92n3s217n5pb4ddqqsnme8ocb.apps.googleusercontent.com"
  }

  @MainActor
  private func startGoogleReauth() {
    GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientID)
    guard let presenter = UIApplication.shared.miraSettingsTopPresentedViewController() else {
      localError = "Google sign in is not ready. Please try again."
      return
    }
    GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
      if error != nil {
        Task { @MainActor in localError = "Google sign in could not finish." }
        return
      }
      guard let token = result?.user.idToken?.tokenString else {
        Task { @MainActor in localError = "Google did not return a valid token." }
        return
      }
      Task { @MainActor in
        oauthProvider = "google"
        oauthIdToken = token
        oauthAccessToken = result?.user.accessToken.tokenString ?? ""
        localError = nil
      }
    }
  }
}

private struct PreferenceSettingsNativeView: View {
  @AppStorage(MIRAAppearanceResolver.preferenceKey) private var appearancePreference = MIRAAppearance.system.rawValue
  @State private var isClearingMediaCache = false

  var body: some View {
    SettingsDetailScaffold(title: "Appearance & cache") {
      SettingsCard(title: "Appearance") {
        HStack(spacing: 8) {
          ForEach(MIRAAppearance.allCases) { option in
            Button {
              CaptroHaptics.light()
              withAnimation(CaptroMotion.feedChromeAnimation(reduceMotion: false)) {
                appearancePreference = option.rawValue
              }
            } label: {
              VStack(spacing: 7) {
                Image(systemName: option.systemImage)
                  .font(.system(size: 15, weight: .semibold))
                Text(option.title)
                  .font(.system(size: 12, weight: .bold))
                  .lineLimit(1)
                  .minimumScaleFactor(0.82)
              }
              .foregroundStyle(appearancePreference == option.rawValue ? .white : MIRATheme.Color.textPrimary)
              .frame(maxWidth: .infinity)
              .frame(height: 52)
              .background(appearancePreference == option.rawValue ? MIRATheme.Color.forest : MIRATheme.Color.surfaceSoft)
              .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.miraPress)
          }
        }
      }

      SettingsCard(title: "Storage") {
        SettingsButtonRow(
          title: isClearingMediaCache ? "Clearing media cache..." : "Clear media cache",
          subtitle: "Remove old cached thumbnails, posters, and feed images.",
          systemImage: "externaldrive.badge.xmark"
        ) {
          guard !isClearingMediaCache else { return }
          isClearingMediaCache = true
          MIRAMediaCacheMaintenance.clearMediaCaches()
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            isClearingMediaCache = false
          }
        }
      }
    }
  }
}

private struct PermissionSettingsNativeView: View {
  var body: some View {
    SettingsDetailScaffold(title: "App permissions") {
      SettingsCard(title: "iPhone access") {
        SettingsButtonRow(title: "Camera", subtitle: "Used to create posts and stories.", systemImage: "camera") { openAppSettings() }
        SettingsButtonRow(title: "Photos", subtitle: "Used to choose media from your library.", systemImage: "photo") { openAppSettings() }
        SettingsButtonRow(title: "Microphone", subtitle: "Used for videos and calls.", systemImage: "mic") { openAppSettings() }
        SettingsButtonRow(title: "Notifications", subtitle: "Used for likes, comments, messages, and follows.", systemImage: "bell") { openAppSettings() }
      }
    }
  }
}

private struct SettingsDetailScaffold<Content: View>: View {
  let title: String
  private let content: Content
  @Environment(\.dismiss) private var dismiss

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: MIRATheme.Space.sm) {
        Button {
          CaptroHaptics.light()
          dismiss()
        } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.miraPress)

        Text(title)
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .lineLimit(1)
        Spacer()
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 8)
      .background(MIRATheme.Color.appBackground)
      .overlay(alignment: .bottom) {
        Rectangle().fill(MIRATheme.Color.hairline.opacity(0.55)).frame(height: 0.5)
      }

      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 14) {
          content
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, MIRATheme.Space.xxl)
      }
    }
    .background(MIRATheme.Color.appBackground.ignoresSafeArea())
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .navigationBar)
    .miraHideTabBarOnAppear()
  }
}

private struct SettingsCard<Content: View>: View {
  let title: String
  private let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title.uppercased())
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .padding(.horizontal, 8)

      VStack(spacing: 8) {
        content
      }
    }
  }
}

private struct SettingsNavigationRow<Destination: View>: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let destination: Destination

  var body: some View {
    NavigationLink(destination: destination) {
      SettingsRowContent(title: title, subtitle: subtitle, systemImage: systemImage) {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
    }
    .buttonStyle(.miraPress)
    .simultaneousGesture(TapGesture().onEnded { CaptroHaptics.light() })
  }
}

private struct SettingsLinkRow: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let url: URL
  @Environment(\.openURL) private var openURL

  var body: some View {
    Button {
      CaptroHaptics.light()
      openURL(url)
    } label: {
      SettingsRowContent(title: title, subtitle: subtitle, systemImage: systemImage) {
        Image(systemName: "arrow.up.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
    }
    .buttonStyle(.miraPress)
  }
}

private struct SettingsButtonRow: View {
  let title: String
  let subtitle: String
  let systemImage: String
  var tint: Color = MIRATheme.Color.textPrimary
  let action: () -> Void

  var body: some View {
    Button {
      CaptroHaptics.light()
      action()
    } label: {
      SettingsRowContent(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint) {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
    }
    .buttonStyle(.miraPress)
  }
}

private struct SettingsToggleRow: View {
  let title: String
  let subtitle: String
  let systemImage: String
  @Binding var isOn: Bool
  var isLoading = false

  var body: some View {
    SettingsRowContent(title: title, subtitle: subtitle, systemImage: systemImage) {
      if isLoading {
        ProgressView()
          .tint(MIRATheme.Color.forest)
      } else {
        Toggle("", isOn: $isOn)
          .labelsHidden()
          .tint(MIRATheme.Color.forest)
      }
    }
  }
}

private struct SettingsRowContent<Trailing: View>: View {
  let title: String
  let subtitle: String
  let systemImage: String
  var tint: Color = MIRATheme.Color.textPrimary
  private let trailing: Trailing

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color = MIRATheme.Color.textPrimary,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.trailing = trailing()
  }

  var body: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 34, height: 34)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(tint)
          .lineLimit(1)
          .minimumScaleFactor(0.86)
        Text(subtitle)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(2)
      }

      Spacer(minLength: MIRATheme.Space.sm)
      trailing
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(minHeight: 58)
    .settingsPillSurface(cornerRadius: 26)
    .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
  }
}

private struct SettingsTextField: View {
  let title: String
  @Binding var text: String
  var keyboardType: UIKeyboardType = .default

  var body: some View {
    TextField(title, text: $text)
      .keyboardType(keyboardType)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .font(.system(size: 15, weight: .medium))
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .settingsPillSurface(cornerRadius: 22)
      .padding(.bottom, 4)
  }
}

private struct SettingsSecureField: View {
  let title: String
  @Binding var text: String

  var body: some View {
    SecureField(title, text: $text)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .font(.system(size: 15, weight: .medium))
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .settingsPillSurface(cornerRadius: 22)
      .padding(.bottom, 4)
  }
}

private struct SettingsActionButton: View {
  let title: String
  let disabled: Bool
  var tint: Color = MIRATheme.Color.forest
  let action: () -> Void

  var body: some View {
    Button {
      CaptroHaptics.light()
      action()
    } label: {
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(disabled ? MIRATheme.Color.textMuted.opacity(0.45) : tint)
        .clipShape(Capsule())
    }
    .buttonStyle(.miraPress)
    .disabled(disabled)
    .padding(.bottom, 4)
  }
}

private struct SettingsBanner: View {
  let message: String
  let isError: Bool

  var body: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle")
      Text(message)
        .font(.system(size: 13, weight: .semibold))
      Spacer()
    }
    .foregroundStyle(isError ? Color.red : MIRATheme.Color.forest)
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background((isError ? Color.red : MIRATheme.Color.forest).opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
  }
}

private struct SettingsPillSurface: ViewModifier {
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    content
      .background {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(MIRATheme.Color.surfaceRaised)
          .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
              .stroke(MIRATheme.Color.hairline.opacity(0.65), lineWidth: 1)
          )
      }
      .shadow(color: .black.opacity(0.045), radius: 12, x: 0, y: 5)
  }
}

private extension View {
  func settingsPillSurface(cornerRadius: CGFloat) -> some View {
    modifier(SettingsPillSurface(cornerRadius: cornerRadius))
  }
}

private extension UIApplication {
  @MainActor
  func miraSettingsTopPresentedViewController() -> UIViewController? {
    connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow }?
      .rootViewController?
      .miraSettingsTopPresentedViewController()
  }
}

private extension UIViewController {
  @MainActor
  func miraSettingsTopPresentedViewController() -> UIViewController {
    if let navigationController = self as? UINavigationController,
       let visibleViewController = navigationController.visibleViewController {
      return visibleViewController.miraSettingsTopPresentedViewController()
    }
    if let tabBarController = self as? UITabBarController,
       let selectedViewController = tabBarController.selectedViewController {
      return selectedViewController.miraSettingsTopPresentedViewController()
    }
    if let presentedViewController {
      return presentedViewController.miraSettingsTopPresentedViewController()
    }
    return self
  }
}

private let languageOptions: [(code: String, label: String)] = [
  ("system", "System Default"),
  ("en", "English"),
  ("fr", "Français"),
  ("es", "Español"),
]

private func languageLabel(_ code: String, localization: MIRALocalization) -> String {
  localization.languageDisplayName(code)
}

private func openAppSettings() {
  guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
  UIApplication.shared.open(url)
}
