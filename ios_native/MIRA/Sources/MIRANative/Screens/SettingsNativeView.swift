import SwiftUI
import UIKit
import UserNotifications

private struct SettingsProfileUpdateBody: Encodable {
  let isPrivate: Bool?
  let language: String?
}

private struct SettingsEmailBody: Encodable {
  let email: String
  let password: String
}

private struct SettingsPasswordBody: Encodable {
  let oldPassword: String
  let newPassword: String
}

private struct SettingsMessageResponse: Decodable {
  let detail: String?
  let deleted: Bool?
}

@MainActor
final class SettingsNativeModel: ObservableObject {
  @Published var user: MIRAUser?
  @Published var isPrivate = false
  @Published var language = "en"
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
    isLoading = true
    defer { isLoading = false }
    do {
      let fresh: MIRAUser = try await api.get("/auth/me")
      apply(user: fresh)
      authSession?.replaceUser(fresh)
    } catch {
      if user == nil {
        show("Settings could not load. Check your connection and try again.", isError: true)
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
      authSession?.replaceUser(updated)
      show(value ? "Private account is on." : "Private account is off.")
    } catch {
      isPrivate = previous
      show("Could not update privacy.", isError: true)
    }
  }

  func updateLanguage(_ value: String) async {
    let previous = language
    language = value
    isSavingLanguage = true
    defer { isSavingLanguage = false }
    do {
      let updated: MIRAUser = try await api.put(
        "/users/me",
        body: SettingsProfileUpdateBody(isPrivate: nil, language: value)
      )
      apply(user: updated)
      authSession?.replaceUser(updated)
      show("Language updated.")
    } catch {
      language = previous
      show("Could not update language.", isError: true)
    }
  }

  func updateEmail(newEmail: String, password: String) async -> Bool {
    let cleanEmail = newEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard cleanEmail.contains("@"), cleanEmail.contains(".") else {
      show("Enter a valid email address.", isError: true)
      return false
    }
    guard !password.isEmpty else {
      show("Enter your current password to update email.", isError: true)
      return false
    }
    isSavingEmail = true
    defer { isSavingEmail = false }
    do {
      let updated: MIRAUser = try await api.put(
        "/users/me/email",
        body: SettingsEmailBody(email: cleanEmail, password: password)
      )
      apply(user: updated)
      authSession?.replaceUser(updated)
      show("Email updated.")
      return true
    } catch {
      show("Could not update email. Check your password and try again.", isError: true)
      return false
    }
  }

  func updatePassword(currentPassword: String, newPassword: String) async -> Bool {
    guard !currentPassword.isEmpty, !newPassword.isEmpty else {
      show("Fill in both password fields.", isError: true)
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
        body: SettingsPasswordBody(oldPassword: currentPassword, newPassword: newPassword)
      )
      show("Password updated.")
      return true
    } catch {
      show("Could not update password. Check your current password.", isError: true)
      return false
    }
  }

  func deleteAccount() async -> Bool {
    isDeletingAccount = true
    defer { isDeletingAccount = false }
    do {
      let _: SettingsMessageResponse = try await api.delete("/users/me")
      authSession?.logout()
      return true
    } catch {
      show("Could not delete your account right now.", isError: true)
      return false
    }
  }

  func logout() {
    authSession?.logout()
  }

  private func apply(user: MIRAUser?) {
    self.user = user
    isPrivate = user?.isPrivate == true
    language = supportedLanguage(user?.language)
    email = user?.email ?? ""
  }

  private func show(_ message: String, isError: Bool = false) {
    bannerMessage = message
    bannerIsError = isError
  }

  private func supportedLanguage(_ raw: String?) -> String {
    let normalized = (raw ?? "en").lowercased()
    return ["en", "fr", "es"].contains(normalized) ? normalized : "en"
  }
}

public struct SettingsNativeView: View {
  @StateObject private var model: SettingsNativeModel

  public init(api: MIRAAPIClient, authSession: MIRAAuthSession? = nil) {
    _model = StateObject(wrappedValue: SettingsNativeModel(api: api, authSession: authSession))
  }

  public var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
        settingsHero

        if let message = model.bannerMessage {
          SettingsBanner(message: message, isError: model.bannerIsError)
        }

        SettingsCard(title: "Account") {
          SettingsNavigationRow(
            title: "Privacy",
            subtitle: model.isPrivate ? "Private account is on" : "Public account",
            systemImage: "lock",
            destination: PrivacySettingsNativeView(model: model)
          )
          SettingsNavigationRow(
            title: "Notifications",
            subtitle: "Push, likes, comments, messages",
            systemImage: "bell",
            destination: NotificationSettingsNativeView()
          )
          SettingsNavigationRow(
            title: "Security",
            subtitle: "Email, password, account actions",
            systemImage: "shield",
            destination: SecuritySettingsNativeView(model: model)
          )
        }

        SettingsCard(title: "Preferences") {
          SettingsNavigationRow(
            title: "Language",
            subtitle: languageLabel(model.language),
            systemImage: "globe",
            destination: PreferenceSettingsNativeView(model: model)
          )
          SettingsNavigationRow(
            title: "App permissions",
            subtitle: "Camera, photos, microphone, notifications",
            systemImage: "switch.2",
            destination: PermissionSettingsNativeView()
          )
        }

        SettingsCard(title: "Support") {
          SettingsLinkRow(title: "Help", subtitle: "Get support", systemImage: "questionmark.circle", url: MIRAProductionBackend.siteURL("help-support"))
          SettingsLinkRow(title: "Community Guidelines", subtitle: "Safety rules", systemImage: "person.2", url: MIRAProductionBackend.siteURL("community-guidelines"))
          SettingsLinkRow(title: "Terms", subtitle: "Terms of service", systemImage: "doc.text", url: MIRAProductionBackend.siteURL("terms-of-service"))
          SettingsLinkRow(title: "Privacy Policy", subtitle: "How privacy works", systemImage: "hand.raised", url: MIRAProductionBackend.siteURL("privacy-policy"))
          SettingsLinkRow(title: "Contact privacy", subtitle: "privacy@flames-up.com", systemImage: "envelope", url: URL(string: "mailto:privacy@flames-up.com")!)
        }
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.top, MIRATheme.Space.md)
      .padding(.bottom, MIRATheme.Space.xxl)
    }
    .background(MIRATheme.Color.appBackground.ignoresSafeArea())
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
    .task { await model.load() }
  }

  private var settingsHero: some View {
    HStack(spacing: MIRATheme.Space.md) {
      RemoteAvatar(url: model.user?.profileImage, size: 58)
      VStack(alignment: .leading, spacing: 3) {
        Text(model.user?.displayName ?? "MIRA")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
        Text(model.email.isEmpty ? "Manage your account" : model.email)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(1)
      }
      Spacer()
      if model.isLoading {
        ProgressView()
          .tint(MIRATheme.Color.forest)
      }
    }
    .padding(MIRATheme.Space.md)
    .miraCardSurface(cornerRadius: 22)
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
        SettingsLinkRow(title: "Privacy Policy", subtitle: "Read how data is handled", systemImage: "hand.raised", url: MIRAProductionBackend.siteURL("privacy-policy"))
        SettingsLinkRow(title: "Data deletion", subtitle: "Learn how account deletion works", systemImage: "trash", url: MIRAProductionBackend.siteURL("data-deletion"))
      }
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
  @State private var emailPassword = ""
  @State private var currentPassword = ""
  @State private var newPassword = ""
  @State private var showDeleteConfirm = false
  @State private var showLogoutConfirm = false

  var body: some View {
    SettingsDetailScaffold(title: "Security") {
      SettingsCard(title: "Email") {
        SettingsTextField(title: "Email", text: $newEmail, keyboardType: .emailAddress)
        SettingsSecureField(title: "Current password", text: $emailPassword)
        SettingsActionButton(title: model.isSavingEmail ? "Saving..." : "Update email", disabled: model.isSavingEmail) {
          Task {
            if await model.updateEmail(newEmail: newEmail, password: emailPassword) {
              emailPassword = ""
            }
          }
        }
      }

      SettingsCard(title: "Password") {
        SettingsSecureField(title: "Current password", text: $currentPassword)
        SettingsSecureField(title: "New password", text: $newPassword)
        SettingsActionButton(title: model.isSavingPassword ? "Saving..." : "Update password", disabled: model.isSavingPassword) {
          Task {
            if await model.updatePassword(currentPassword: currentPassword, newPassword: newPassword) {
              currentPassword = ""
              newPassword = ""
            }
          }
        }
      }

      SettingsCard(title: "Account") {
        SettingsButtonRow(title: "Log out", subtitle: "Sign out on this device.", systemImage: "rectangle.portrait.and.arrow.right", tint: .red) {
          showLogoutConfirm = true
        }
        SettingsButtonRow(title: model.isDeletingAccount ? "Deleting..." : "Delete account", subtitle: "Soft-delete your account and remove public content.", systemImage: "trash", tint: .red) {
          showDeleteConfirm = true
        }
      }
    }
    .onAppear {
      if newEmail.isEmpty { newEmail = model.email }
    }
    .confirmationDialog("Log out?", isPresented: $showLogoutConfirm) {
      Button("Log out", role: .destructive) { model.logout() }
      Button("Cancel", role: .cancel) {}
    }
    .confirmationDialog("Delete account?", isPresented: $showDeleteConfirm) {
      Button("Delete account", role: .destructive) {
        Task { _ = await model.deleteAccount() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This removes your public account content and cannot be undone from the app.")
    }
  }
}

private struct PreferenceSettingsNativeView: View {
  @ObservedObject var model: SettingsNativeModel
  @AppStorage("mira.settings.autoplay_video") private var autoplayVideo = true
  @AppStorage("mira.settings.high_quality_uploads") private var highQualityUploads = true
  @AppStorage("mira.settings.reduce_motion") private var reduceMotion = false

  var body: some View {
    SettingsDetailScaffold(title: "Preferences") {
      SettingsCard(title: "Language") {
        HStack(spacing: MIRATheme.Space.sm) {
          ForEach(languageOptions.indices, id: \.self) { index in
            let option = languageOptions[index]
            Button {
              Task { await model.updateLanguage(option.code) }
            } label: {
              Text(option.label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(model.language == option.code ? .white : MIRATheme.Color.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(model.language == option.code ? MIRATheme.Color.forest : MIRATheme.Color.surfaceSoft)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.isSavingLanguage)
          }
        }
      }

      SettingsCard(title: "Media") {
        SettingsToggleRow(title: "Autoplay videos", subtitle: "Play visible videos automatically.", systemImage: "play.circle", isOn: $autoplayVideo)
        SettingsToggleRow(title: "High quality uploads", subtitle: "Keep uploads sharp when possible.", systemImage: "arrow.up.circle", isOn: $highQualityUploads)
        SettingsToggleRow(title: "Reduce motion", subtitle: "Use simpler animations.", systemImage: "figure.walk.motion", isOn: $reduceMotion)
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

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
        content
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.top, MIRATheme.Space.md)
      .padding(.bottom, MIRATheme.Space.xxl)
    }
    .background(MIRATheme.Color.appBackground.ignoresSafeArea())
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
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
    VStack(alignment: .leading, spacing: 0) {
      Text(title.uppercased())
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .padding(.horizontal, MIRATheme.Space.md)
        .padding(.top, MIRATheme.Space.md)
        .padding(.bottom, MIRATheme.Space.xs)

      VStack(spacing: 0) {
        content
      }
    }
    .background(MIRATheme.Color.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(MIRATheme.Color.hairline, lineWidth: 1))
    .modifier(MIRATheme.softShadow())
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
    .buttonStyle(.plain)
  }
}

private struct SettingsLinkRow: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let url: URL
  @Environment(\.openURL) private var openURL

  var body: some View {
    Button { openURL(url) } label: {
      SettingsRowContent(title: title, subtitle: subtitle, systemImage: systemImage) {
        Image(systemName: "arrow.up.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
    }
    .buttonStyle(.plain)
  }
}

private struct SettingsButtonRow: View {
  let title: String
  let subtitle: String
  let systemImage: String
  var tint: Color = MIRATheme.Color.textPrimary
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      SettingsRowContent(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint) {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }
    }
    .buttonStyle(.plain)
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
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 42, height: 42)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(tint)
        Text(subtitle)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(2)
      }

      Spacer(minLength: MIRATheme.Space.sm)
      trailing
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.vertical, 13)
    .contentShape(Rectangle())
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
      .padding(.horizontal, MIRATheme.Space.md)
      .frame(height: 48)
      .background(MIRATheme.Color.surfaceSoft)
      .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.bottom, MIRATheme.Space.sm)
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
      .padding(.horizontal, MIRATheme.Space.md)
      .frame(height: 48)
      .background(MIRATheme.Color.surfaceSoft)
      .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.bottom, MIRATheme.Space.sm)
  }
}

private struct SettingsActionButton: View {
  let title: String
  let disabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(disabled ? MIRATheme.Color.textMuted.opacity(0.45) : MIRATheme.Color.forest)
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .padding(.horizontal, MIRATheme.Space.md)
    .padding(.bottom, MIRATheme.Space.md)
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
    .padding(MIRATheme.Space.md)
    .background((isError ? Color.red : MIRATheme.Color.forest).opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

private let languageOptions: [(code: String, label: String)] = [
  ("en", "English"),
  ("fr", "Français"),
  ("es", "Español"),
]

private func languageLabel(_ code: String) -> String {
  languageOptions.first { $0.code == code }?.label ?? "English"
}

private func openAppSettings() {
  guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
  UIApplication.shared.open(url)
}
