import AuthenticationServices
import GoogleSignIn
import SwiftUI
import UIKit
import UserNotifications
import CoreLocation

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
  @Published var loadError: String?
  @Published var user: MIRAUser?
  @Published var isPrivate = false
  @Published var language = MIRALanguageResolver.storedPreference()
  @Published var email = ""
  @Published var isLoading = false
  @Published var isSavingPrivacy = false
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
      loadError = nil
      apply(user: fresh)
      await MIRAAppCacheStore.shared.saveSettings(user: fresh, language: language, isPrivate: isPrivate)
      authSession?.replaceUser(fresh)
    } catch {
      if user == nil {
        loadError = "Couldn't load account settings. Pull down to try again."
      }
    }
  }

  func updatePrivacy(_ value: Bool) async {
    guard !isSavingPrivacy else { return }
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

  func updateEmail(newEmail: String) async -> Bool {
    guard !isSavingEmail else { return false }
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
    guard !isSavingPassword else { return false }
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
    guard !isDeletingAccount else { return false }
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

  func profileDidChange(_ updated: MIRAUser) {
    apply(user: updated)
    authSession?.replaceUser(updated)
    Task { await MIRAAppCacheStore.shared.saveSettings(user: updated, language: language, isPrivate: isPrivate) }
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
  private let profileModel: ProfileNativeModel?
  private let paymentsModel: CaptroPaymentsModel?
  @EnvironmentObject private var localization: MIRALocalization
  @Environment(\.dismiss) private var dismiss
  @State private var showLogoutConfirm = false

  public init(api: MIRAAPIClient, authSession: MIRAAuthSession? = nil) {
    _model = StateObject(wrappedValue: SettingsNativeModel(api: api, authSession: authSession))
    profileModel = nil
    paymentsModel = nil
  }

  init(
    api: MIRAAPIClient,
    authSession: MIRAAuthSession? = nil,
    profileModel: ProfileNativeModel,
    paymentsModel: CaptroPaymentsModel?
  ) {
    _model = StateObject(wrappedValue: SettingsNativeModel(api: api, authSession: authSession))
    self.profileModel = profileModel
    self.paymentsModel = paymentsModel
  }

  public var body: some View {
    SettingsDetailScaffold(title: localization.string("settings.title")) {
        Section {
          Button { dismiss() } label: { settingsHero }
            .buttonStyle(.automatic)
            .accessibilityLabel("View your profile")
        }

        if let loadError = model.loadError {
          SettingsBanner(message: loadError, isError: true)
        }
        if let message = model.bannerMessage {
          SettingsBanner(message: message, isError: model.bannerIsError)
        }

        SettingsCard(title: localization.string("settings.account")) {
          SettingsNavigationRow(
            title: "Account", subtitle: "", systemImage: "person",
            destination: AccountSettingsNativeView(model: model)
          )
          if let profileModel {
            SettingsNavigationRow(
              title: "Your activity",
            subtitle: "",
              systemImage: "list.bullet.rectangle",
              destination: ProfileActivityNativeView(model: profileModel)
            )
          }
          SettingsNavigationRow(
            title: localization.string("settings.privacy"),
            subtitle: "",
            systemImage: "lock",
            destination: PrivacySettingsNativeView(model: model)
          )
          .disabled(model.user == nil)
          SettingsNavigationRow(
            title: localization.string("settings.notifications"),
            subtitle: "",
            systemImage: "bell",
            destination: NotificationSettingsNativeView()
          )
          SettingsNavigationRow(
            title: localization.string("settings.security"),
            subtitle: "",
            systemImage: "shield",
            destination: SecuritySettingsNativeView(model: model)
          )
        }

        SettingsCard(title: "Payments") {
          SettingsNavigationRow(title: "Payments & payouts", subtitle: "", systemImage: "creditcard", destination: paymentsDestination)
          if let profileModel {
            SettingsNavigationRow(title: "Purchases & receipts", subtitle: "", systemImage: "doc.text", destination: SettingsPurchasesView(model: profileModel))
          }
        }
        SettingsCard(title: localization.string("settings.preferences")) {
          SettingsNavigationRow(
            title: "Appearance",
            subtitle: "",
            systemImage: "circle.lefthalf.filled",
            destination: PreferenceSettingsNativeView()
          )
          SettingsNavigationRow(title: "Storage & cache", subtitle: "", systemImage: "internaldrive", destination: StorageSettingsNativeView())
          SettingsNavigationRow(title: "Location & permissions", subtitle: "", systemImage: "location", destination: DevicePermissionsSettingsView())
          SettingsNavigationRow(title: "Accessibility", subtitle: "", systemImage: "accessibility", destination: AccessibilitySettingsNativeView())
        }

        SettingsCard(title: "Support & safety") {
          SettingsNavigationRow(title: "Help & support", subtitle: "", systemImage: "questionmark.circle", destination: SupportSettingsNativeView())
          SettingsNavigationRow(title: "Safety & reporting", subtitle: "", systemImage: "shield", destination: SafetySettingsNativeView(api: model.api))
        }
        SettingsCard(title: "Legal") {
          SettingsNavigationRow(
            title: localization.string("legal.terms"),
            subtitle: "",
            systemImage: "doc.text",
            destination: TermsOfServiceView()
          )
          SettingsNavigationRow(
            title: localization.string("legal.privacy"),
            subtitle: "",
            systemImage: "hand.raised",
            destination: PrivacyPolicyView()
          )
          SettingsNavigationRow(
            title: localization.string("legal.community"),
            subtitle: "",
            systemImage: "person.2",
            destination: CommunityGuidelinesView()
          )
          SettingsNavigationRow(title: "About Captro", subtitle: "", systemImage: "info.circle", destination: AboutCaptroSettingsView())
        }
        Section {
          Button("Log out") { showLogoutConfirm = true }
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .frame(minHeight: 44)
        }
        Section {
          NavigationLink(destination: DeleteAccountNativeView(model: model)) {
            Text("Delete account").foregroundStyle(.red).frame(minHeight: 44)
          }
        }
    }
    .task { await model.load() }
    .refreshable { await model.load() }
    .confirmationDialog("Log out of Captro?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
      Button("Log out", role: .destructive) { model.logout() }
      Button("Cancel", role: .cancel) {}
    }
  }

  private var paymentsDestination: CaptroPaymentsView {
    if let paymentsModel {
      return CaptroPaymentsView(api: model.api, model: paymentsModel)
    }
    return CaptroPaymentsView(api: model.api)
  }

  private var settingsHero: some View {
    HStack(spacing: 12) {
      RemoteAvatar(url: model.user?.profileImage, size: 48)
      VStack(alignment: .leading, spacing: 2) {
        Text(model.user?.username.map { "@\(MIRAUsernameRules.normalized($0))" } ?? "Your profile")
          .font(.body.weight(.semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text(model.user?.displayName ?? "View profile")
          .font(.subheadline)
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(1)
      }
      Spacer()
      if model.isLoading {
        ProgressView()
          .tint(MIRATheme.Color.forest)
      }
      Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
    }
    .padding(.vertical, 4)
    .frame(minHeight: 60)
    .contentShape(Rectangle())
  }
}

private struct PrivacySettingsNativeView: View {
  @ObservedObject var model: SettingsNativeModel

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

      // Do not expose local-only flags as server-enforced privacy controls.
      SettingsCard(title: "Privacy tools") {
        SettingsNavigationRow(title: "Blocked accounts", subtitle: "Review and unblock people.", systemImage: "person.crop.circle.badge.xmark", destination: BlockedAccountsNativeView(api: model.api))
        SettingsNavigationRow(title: "Privacy Policy", subtitle: "Read how data is handled", systemImage: "hand.raised", destination: PrivacyPolicyView())
        SettingsNavigationRow(title: "Safety & Reporting", subtitle: "Report abuse or unsafe behavior", systemImage: "shield.lefthalf.filled", destination: SafetyReportingView())
        SettingsLinkRow(title: "Data deletion", subtitle: "Learn how account deletion works", systemImage: "trash", url: MIRAProductionBackend.siteURL("data-deletion"))
      }
      if let message = model.bannerMessage {
        SettingsBanner(message: message, isError: model.bannerIsError)
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
    .contentShape(Rectangle())
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
  @Environment(\.scenePhase) private var scenePhase
  @State private var pushEnabled = false
  @State private var hasRequested = false
  @State private var isChecking = true
  @State private var authorizationStatus = "Checking..."

  var body: some View {
    SettingsDetailScaffold(title: "Notifications") {
      SettingsCard(title: "Device") {
        SettingsToggleRow(
          title: "Push notifications",
          subtitle: "Permission is controlled by iOS.",
          systemImage: "bell.badge",
          isOn: Binding(
            get: { pushEnabled },
            set: { value in
              if value && !hasRequested {
                Task { await requestPushPermission() }
              } else {
                // iOS permission cannot be revoked with a local preference.
                openAppSettings()
              }
            }
          ), isLoading: isChecking
        )
        SettingsButtonRow(title: "iOS notification settings", subtitle: authorizationStatus, systemImage: "gearshape") {
          openAppSettings()
        }
      }

      Text("Choose alerts, sounds, badges and previews in iOS notification settings.")
        .font(.footnote).foregroundStyle(.secondary)
    }
    .task { await refreshNotificationStatus() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await refreshNotificationStatus() } }
    }
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
    hasRequested = settings.authorizationStatus != .notDetermined
    isChecking = false
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
  @State private var showLogoutConfirm = false

  var body: some View {
    SettingsDetailScaffold(title: "Security") {
      SettingsCard(title: "Sign-in details") {
        SettingsNavigationRow(title: "Email", subtitle: model.email, systemImage: "envelope", destination: SettingsEmailEditor(model: model))
        SettingsNavigationRow(title: "Password", subtitle: "", systemImage: "key", destination: SettingsPasswordEditor(model: model))
      }

      SettingsCard(title: "Account") {
        SettingsButtonRow(title: "Log out", subtitle: "Sign out on this device.", systemImage: "rectangle.portrait.and.arrow.right", tint: .red) {
          showLogoutConfirm = true
        }
        NavigationLink(destination: DeleteAccountNativeView(model: model)) {
          SettingsRowContent(title: "Delete account", subtitle: "Hide now, permanently delete after 30 days.", systemImage: "trash", tint: .red) {
            EmptyView()
          }
        }
        .buttonStyle(.automatic)

      }
    }
    .confirmationDialog("Log out?", isPresented: $showLogoutConfirm) {
      Button("Log out", role: .destructive) { model.logout() }
      Button("Cancel", role: .cancel) {}
    }
  }
}

private struct AccountSettingsNativeView: View {
  @ObservedObject var model: SettingsNativeModel
  @State private var editingProfile = false

  var body: some View {
    SettingsDetailScaffold(title: "Account") {
      SettingsCard(title: "Profile") {
        SettingsButtonRow(title: "Edit profile", subtitle: "Photo, name and username", systemImage: "person.crop.circle") { editingProfile = true }
          .disabled(model.user == nil)
        SettingsNavigationRow(title: "Email", subtitle: model.email, systemImage: "envelope", destination: SettingsEmailEditor(model: model))
      }
      SettingsCard(title: "Security") {
        SettingsNavigationRow(title: "Sign-in & security", subtitle: "", systemImage: "lock", destination: SecuritySettingsNativeView(model: model))
      }
      SettingsCard(title: "Your data") {
        SettingsLinkRow(title: "Request your data", subtitle: "Contact Captro support", systemImage: "square.and.arrow.down", url: captroSupportURL(subject: "Personal data request"))
      }
      SettingsCard(title: "Account removal") {
        NavigationLink(destination: DeleteAccountNativeView(model: model)) {
          Text("Delete account").foregroundStyle(.red).frame(minHeight: 44)
        }
      }
    }
    .sheet(isPresented: $editingProfile) {
      EditProfileNativeView(user: model.user, api: model.api, onCancel: { editingProfile = false }) { updated in
        model.profileDidChange(updated)
        editingProfile = false
      }
    }
  }
}

private struct SettingsEmailEditor: View {
  @ObservedObject var model: SettingsNativeModel
  @State private var email = ""
  @FocusState private var focused: Bool

  private var valid: Bool {
    let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.contains("@") && value.contains(".") && !value.contains(" ") && value.lowercased() != model.email.lowercased()
  }
  var body: some View {
    SettingsDetailScaffold(title: "Email") {
      Section {
        TextField("Email address", text: $email)
          .keyboardType(.emailAddress).textContentType(.emailAddress)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .focused($focused).submitLabel(.done).onSubmit { save() }
          .accessibilityIdentifier("settings.email.input")
      } header: { Text("Email address") } footer: { Text("Use an address you can access.") }
      Section {
        Button { save() } label: {
          HStack { Text("Save email"); Spacer(); if model.isSavingEmail { ProgressView() } }
        }.disabled(!valid || model.isSavingEmail)
      }
      if let message = model.bannerMessage { SettingsBanner(message: message, isError: model.bannerIsError) }
    }
    .onAppear { email = model.email; model.bannerMessage = nil }
  }
  private func save() {
    guard valid, !model.isSavingEmail else { return }
    focused = false
    Task { _ = await model.updateEmail(newEmail: email) }
  }
}

private struct SettingsPasswordEditor: View {
  @ObservedObject var model: SettingsNativeModel
  @State private var password = ""
  @State private var confirmation = ""
  @FocusState private var field: Int?
  private var valid: Bool { password.count >= 8 && password == confirmation }
  var body: some View {
    SettingsDetailScaffold(title: "Password") {
      Section {
        SecureField("New password", text: $password).textContentType(.newPassword)
          .focused($field, equals: 1).submitLabel(.next).onSubmit { field = 2 }
        SecureField("Confirm password", text: $confirmation).textContentType(.newPassword)
          .focused($field, equals: 2).submitLabel(.done).onSubmit { save() }
      } header: { Text("New password") } footer: {
        Text(!confirmation.isEmpty && password != confirmation ? "Passwords do not match." : "Use at least 8 characters.")
      }
      Section {
        Button { save() } label: {
          HStack { Text("Update password"); Spacer(); if model.isSavingPassword { ProgressView() } }
        }.disabled(!valid || model.isSavingPassword)
      }
      if let message = model.bannerMessage { SettingsBanner(message: message, isError: model.bannerIsError) }
    }.onAppear { model.bannerMessage = nil }
  }
  private func save() {
    guard valid, !model.isSavingPassword else { return }
    field = nil
    Task { if await model.updatePassword(newPassword: password) { password = ""; confirmation = "" } }
  }
}

private func captroSupportURL(subject: String) -> URL {
  var components = URLComponents()
  components.scheme = "mailto"
  components.path = "karfalacisse900@gmail.com"
  components.queryItems = [URLQueryItem(name: "subject", value: "Captro — \(subject)")]
  return components.url!
}

private struct SupportSettingsNativeView: View {
  var body: some View {
    SettingsDetailScaffold(title: "Help & support") {
      SettingsCard(title: "Contact Captro") {
        SettingsLinkRow(title: "Contact support", subtitle: "", systemImage: "envelope", url: captroSupportURL(subject: "Support"))
        SettingsLinkRow(title: "Report a problem", subtitle: "", systemImage: "exclamationmark.bubble", url: captroSupportURL(subject: "Report a problem"))
        SettingsLinkRow(title: "Payment help", subtitle: "", systemImage: "creditcard", url: captroSupportURL(subject: "Payment help"))
      }
      SettingsCard(title: "Guidance") {
        SettingsNavigationRow(title: "Safety help", subtitle: "", systemImage: "shield", destination: SafetyReportingView())
        SettingsNavigationRow(title: "Community Guidelines", subtitle: "", systemImage: "person.2", destination: CommunityGuidelinesView())
      }
      Text("Never include passwords, card numbers or verification codes in a support request.").font(.footnote).foregroundStyle(.secondary)
    }
  }
}

private struct SafetySettingsNativeView: View {
  let api: MIRAAPIClient
  var body: some View {
    SettingsDetailScaffold(title: "Safety & reporting") {
      SettingsCard(title: "Safety tools") {
        SettingsNavigationRow(title: "Blocked accounts", subtitle: "", systemImage: "person.crop.circle.badge.xmark", destination: BlockedAccountsNativeView(api: api))
        SettingsNavigationRow(title: "How to report", subtitle: "", systemImage: "flag", destination: SafetyReportingView())
        SettingsLinkRow(title: "Ask about a report", subtitle: "Contact the safety team", systemImage: "envelope", url: captroSupportURL(subject: "Safety report follow-up"))
      }
      Section {
        Text("For immediate danger, contact local emergency services. Captro is not an emergency service.").font(.footnote).foregroundStyle(.secondary)
      }
    }
  }
}

private struct AboutCaptroSettingsView: View {
  var body: some View {
    SettingsDetailScaffold(title: "About Captro") {
      SettingsCard(title: "Captro") {
        LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unavailable")
        LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unavailable")
      }
      SettingsCard(title: "Legal") {
        SettingsNavigationRow(title: "Terms of Service", subtitle: "", systemImage: "doc.text", destination: TermsOfServiceView())
        SettingsNavigationRow(title: "Privacy Policy", subtitle: "", systemImage: "hand.raised", destination: PrivacyPolicyView())
        SettingsNavigationRow(title: "Community Guidelines", subtitle: "", systemImage: "person.2", destination: CommunityGuidelinesView())
      }
    }
  }
}

private struct DevicePermissionsSettingsView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var locationStatus = "Checking…"
  var body: some View {
    SettingsDetailScaffold(title: "Location & permissions") {
      Section {
        LabeledContent("Location access", value: locationStatus)
        SettingsButtonRow(title: "Open iOS Settings", subtitle: "Location, camera, microphone and photos", systemImage: "gearshape") { openAppSettings() }
      } footer: { Text("Precise location is controlled by iOS. Captro does not publish your live location. Places you choose to tag can appear on your posts.") }
    }.onAppear { refresh() }.onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
  }
  private func refresh() {
    switch CLLocationManager().authorizationStatus {
    case .authorizedAlways: locationStatus = "Always"
    case .authorizedWhenInUse: locationStatus = "While using the app"
    case .denied: locationStatus = "Not allowed"
    case .restricted: locationStatus = "Restricted by iOS"
    case .notDetermined: locationStatus = "Not requested"
    @unknown default: locationStatus = "Unavailable"
    }
  }
}

private struct AccessibilitySettingsNativeView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    SettingsDetailScaffold(title: "Accessibility") {
      Section {
        LabeledContent("Reduce Motion", value: reduceMotion ? "On" : "Off")
        Text("Captro follows your iPhone’s text size, VoiceOver and Reduce Motion settings. Change these in Settings → Accessibility.")
          .font(.subheadline).foregroundStyle(.secondary)
      }
    }
  }
}

private struct SettingsPurchasesView: View {
  @ObservedObject var model: ProfileNativeModel
  var body: some View {
    ScrollView {
      if let dashboard = model.commerceDashboard {
        if dashboard.myStuff.isEmpty { ContentUnavailableView("No purchases yet", systemImage: "doc.text", description: Text("Your purchases and access will appear here.")) }
        else {
          CaptroCommerceDashboardView(dashboard: CaptroCommerceDashboard(myStuff: dashboard.myStuff, created: [], pendingRequests: []), api: model.api, onDecision: { _, _ in })
        }
      } else if model.isLoadingActivity { ProgressView("Loading purchases…").padding() }
      if let error = model.activityError { Text(error).foregroundStyle(.red).padding() }
    }
    .navigationTitle("Purchases & receipts").navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar).miraHideTabBarOnAppear()
    .background(MIRATheme.Color.appBackground)
    .task { await model.loadActivity() }.refreshable { await model.loadActivity(forceRefresh: true) }
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
        tint: .red,
        foreground: .white
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

  private var googleServerClientID: String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed.contains("$(") {
      return nil
    }
    return trimmed
  }

  @MainActor
  private func startGoogleReauth() {
    if let googleServerClientID {
      GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientID, serverClientID: googleServerClientID)
    } else {
      GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientID)
    }
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

struct PreferenceSettingsNativeView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage(MIRAAppearanceResolver.preferenceKey) private var appearancePreference = MIRAAppearance.system.rawValue

  var body: some View {
    SettingsDetailScaffold(title: "Appearance") {
      SettingsCard(title: "Theme") {
          ForEach(MIRAAppearance.allCases) { option in
            Button {
              appearancePreference = option.rawValue
            } label: {
              HStack(spacing: 12) {
                Image(systemName: option.systemImage)
                  .font(.body)
                  .frame(width: 24)
                  .accessibilityHidden(true)
                Text(option.title)
                  .font(.body.weight(.medium))
                  .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if appearancePreference == option.rawValue {
                  Image(systemName: "checkmark").foregroundStyle(MIRATheme.Color.forest)
                }
              }
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 4)
              .frame(minHeight: 48)
            }
            .buttonStyle(.automatic)
            .accessibilityAddTraits(appearancePreference == option.rawValue ? .isSelected : [])
          }
      }
      SettingsCard(title: "Reading & motion") {
        SettingsNavigationRow(title: "Text size & Reduce Motion", subtitle: "Uses your iPhone preferences", systemImage: "textformat.size", destination: AccessibilitySettingsNativeView())
      }
    }
  }
}

private struct StorageSettingsNativeView: View {
  @State private var isClearingMediaCache = false
  @State private var cacheNotice: String?
  @State private var cacheClearFailed = false
  @State private var confirmClear = false

  var body: some View {
    SettingsDetailScaffold(title: "Storage & cache") {
      SettingsCard(title: "Storage") {
        SettingsButtonRow(
          title: isClearingMediaCache ? "Clearing media cache..." : "Clear media cache",
          subtitle: "Remove old cached thumbnails, posters, and feed images.",
          systemImage: "externaldrive.badge.xmark"
        ) {
          confirmClear = true
        }
        .disabled(isClearingMediaCache)
        if let cacheNotice { SettingsBanner(message: cacheNotice, isError: cacheClearFailed) }
      }
      Text("This removes downloaded media copies only. Your posts, account and unfinished uploads are kept.")
        .font(.footnote).foregroundStyle(.secondary)
    }
    .confirmationDialog("Clear downloaded media?", isPresented: $confirmClear, titleVisibility: .visible) {
      Button("Clear cache", role: .destructive) {
          guard !isClearingMediaCache else { return }
          isClearingMediaCache = true
          cacheNotice = nil
          Task {
            let cleared = await MIRAMediaCacheMaintenance.clearMediaCaches()
            cacheClearFailed = !cleared
            cacheNotice = cleared ? "Cached media cleared. Images reload as needed." : "Some cached files couldn't be cleared. Try again."
            isClearingMediaCache = false
          }
      }
      Button("Cancel", role: .cancel) {}
    }
  }
}

struct SettingsDetailScaffold<Content: View>: View {
  let title: String
  private let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    List {
      content
        .listRowBackground(MIRATheme.Color.surfaceSoft)
    }
    .listStyle(.insetGrouped)
    .listSectionSpacing(16)
    .contentMargins(.horizontal, 16, for: .scrollContent)
    .scrollContentBackground(.hidden)
    .scrollDismissesKeyboard(.interactively)
    .environment(\.defaultMinListRowHeight, 52)
    .tint(MIRATheme.Color.forest)
    .background(MIRATheme.Color.appBackground.ignoresSafeArea())
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    .miraHideTabBarOnAppear()
  }
}

struct SettingsCard<Content: View>: View {
  let title: String
  private let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    Section { content } header: { Text(title).textCase(nil) }
  }
}

struct SettingsNavigationRow<Destination: View>: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let destination: Destination

  var body: some View {
    NavigationLink(destination: destination) {
      SettingsRowContent(title: title, subtitle: subtitle, systemImage: systemImage) {
        EmptyView()
      }
    }
    .buttonStyle(.automatic)
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
    .buttonStyle(.automatic)
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
    .buttonStyle(.automatic)
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
        Toggle(title, isOn: $isOn)
          .labelsHidden()
          .tint(MIRATheme.Color.forest)
          .accessibilityHint(subtitle)
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
        .font(.body.weight(.regular))
        .foregroundStyle(tint)
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.body)
          .foregroundStyle(tint)
          .fixedSize(horizontal: false, vertical: true)
        if !subtitle.isEmpty {
          Text(subtitle)
            .font(.footnote)
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Spacer(minLength: MIRATheme.Space.sm)
      trailing
    }
    .padding(.vertical, 4)
    .frame(minHeight: 44)
    .contentShape(Rectangle())
  }
}

private struct SettingsTextField: View {
  let title: String
  @Binding var text: String
  var keyboardType: UIKeyboardType = .default

  var body: some View {
    MIRAFormInput(title: title, text: $text, keyboardType: keyboardType,
                  contentType: keyboardType == .emailAddress ? .emailAddress : nil)
  }
}

private struct SettingsSecureField: View {
  let title: String
  @Binding var text: String

  var body: some View {
    MIRAFormInput(title: title, text: $text, secure: true)
  }
}

private struct SettingsActionButton: View {
  let title: String
  let disabled: Bool
  var tint: Color = MIRATheme.Color.forest
  var foreground: Color = MIRATheme.Color.onPrimary
  let action: () -> Void

  var body: some View {
    Button {
      CaptroHaptics.light()
      action()
    } label: {
      Text(title)
        .font(.body.weight(.semibold))
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .background(disabled ? MIRATheme.Color.textMuted.opacity(0.45) : tint)
        .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.small, style: .continuous))
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
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
      Spacer()
    }
    .foregroundStyle(isError ? Color.red : MIRATheme.Color.forest)
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background((isError ? Color.red : MIRATheme.Color.forest).opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.small, style: .continuous))
  }
}

private struct SettingsPillSurface: ViewModifier {
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    content
      .background {
        RoundedRectangle(cornerRadius: MIRATheme.Radius.small, style: .continuous)
          .fill(MIRATheme.Color.surfaceRaised)
          .overlay(
            RoundedRectangle(cornerRadius: MIRATheme.Radius.small, style: .continuous)
              .stroke(MIRATheme.Color.hairline.opacity(0.65), lineWidth: 1)
          )
      }
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

private func openAppSettings() {
  guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
  UIApplication.shared.open(url)
}
