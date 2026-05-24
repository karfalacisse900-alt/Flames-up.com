import AuthenticationServices
import SwiftUI

public struct AuthNativeView: View {
  @ObservedObject var session: MIRAAuthSession
  let api: MIRAAPIClient

  @State private var email = ""
  @State private var password = ""
  @State private var username = ""
  @State private var fullName = ""
  @State private var isCreatingAccount = false

  public init(session: MIRAAuthSession, api: MIRAAPIClient) {
    self.session = session
    self.api = api
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MIRATheme.Space.xl) {
          brandBlock
          formBlock
          appleButton
          legalFooter
        }
        .padding(.horizontal, MIRATheme.Space.xl)
        .padding(.top, 70)
        .padding(.bottom, MIRATheme.Space.xxl)
      }
      .background(MIRATheme.Color.appBackground.ignoresSafeArea())
      .toolbar(.hidden, for: .navigationBar)
    }
  }

  private var brandBlock: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      Text("MIRA")
        .font(.system(size: 44, weight: .semibold, design: .rounded))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Text("Share what you see. Discover what feels real.")
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var formBlock: some View {
    VStack(spacing: MIRATheme.Space.md) {
      if isCreatingAccount {
        authField("Username", text: $username, systemImage: "person")
        authField("Full name", text: $fullName, systemImage: "textformat")
      }
      authField("Email", text: $email, systemImage: "envelope", keyboard: .emailAddress)
      secureField

      if let error = session.errorMessage {
        Text(error)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.red.opacity(0.82))
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      Button {
        Task { await submit() }
      } label: {
        HStack {
          Spacer()
          if session.isWorking {
            ProgressView().tint(.white)
          } else {
            Text(isCreatingAccount ? "Create account" : "Log in")
              .font(.system(size: 16, weight: .semibold))
          }
          Spacer()
        }
        .foregroundStyle(.white)
        .frame(height: 50)
        .background(MIRATheme.Color.forest)
        .clipShape(Capsule())
      }
      .buttonStyle(.plain)
      .disabled(session.isWorking || !canSubmit)

      Button {
        withAnimation(.snappy(duration: 0.2)) {
          isCreatingAccount.toggle()
          session.errorMessage = nil
        }
      } label: {
        Text(isCreatingAccount ? "Already have an account? Log in" : "New here? Create an account")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .frame(maxWidth: .infinity)
          .frame(height: 44)
      }
      .buttonStyle(.plain)
    }
    .padding(MIRATheme.Space.lg)
    .miraCardSurface(cornerRadius: 26)
  }

  private var appleButton: some View {
    SignInWithAppleButton(.continue) { request in
      request.requestedScopes = [.fullName, .email]
    } onCompletion: { result in
      guard case .success(let authorization) = result,
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8) else {
        session.errorMessage = "Apple sign in could not finish."
        return
      }
      let fullName = PersonNameComponentsFormatter().string(from: credential.fullName ?? PersonNameComponents())
      Task {
        await session.signInWithApple(
          idToken: idToken,
          email: credential.email,
          fullName: fullName.isEmpty ? nil : fullName,
          appleUser: credential.user,
          api: api
        )
      }
    }
    .signInWithAppleButtonStyle(.black)
    .frame(height: 50)
    .clipShape(Capsule())
  }

  private var legalFooter: some View {
    VStack(spacing: MIRATheme.Space.sm) {
      Text("By continuing, you agree to Captro's legal and safety terms.")
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MIRATheme.Space.sm) {
        NavigationLink(destination: TermsOfServiceView()) {
          legalFooterPill("Terms")
        }
        NavigationLink(destination: PrivacyPolicyView()) {
          legalFooterPill("Privacy")
        }
        NavigationLink(destination: CommunityGuidelinesView()) {
          legalFooterPill("Guidelines")
        }
        NavigationLink(destination: SafetyReportingView()) {
          legalFooterPill("Safety")
        }
      }

      Text("Support: karfalacisse900@gmail.com")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .textSelection(.enabled)
    }
  }

  private func legalFooterPill(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 12.5, weight: .semibold))
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .frame(maxWidth: .infinity)
      .frame(height: 36)
      .background(MIRATheme.Color.surfaceSoft)
      .clipShape(Capsule())
  }

  private func authField(
    _ placeholder: String,
    text: Binding<String>,
    systemImage: String,
    keyboard: UIKeyboardType = .default
  ) -> some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Image(systemName: systemImage)
        .foregroundStyle(MIRATheme.Color.textMuted)
        .frame(width: 22)
      TextField(placeholder, text: text)
        .keyboardType(keyboard)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textPrimary)
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .frame(height: 50)
    .background(MIRATheme.Color.surfaceSoft)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var secureField: some View {
    HStack(spacing: MIRATheme.Space.sm) {
      Image(systemName: "lock")
        .foregroundStyle(MIRATheme.Color.textMuted)
        .frame(width: 22)
      SecureField("Password", text: $password)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textPrimary)
    }
    .padding(.horizontal, MIRATheme.Space.md)
    .frame(height: 50)
    .background(MIRATheme.Color.surfaceSoft)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var canSubmit: Bool {
    email.contains("@") && password.count >= 6 && (!isCreatingAccount || username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3)
  }

  @MainActor
  private func submit() async {
    if isCreatingAccount {
      await session.register(email: email, password: password, username: username, fullName: fullName, api: api)
    } else {
      await session.login(email: email, password: password, api: api)
    }
  }
}

private struct UsernameAvailabilityResponse: Decodable {
  let available: Bool
  let username: String?
  let code: String?
  let reason: String?
}

private struct UsernameClaimBody: Encodable {
  let username: String
}

private struct UsernameProfileFallbackBody: Encodable {
  let username: String
}

private enum UsernameAvailabilityState: Equatable {
  case idle
  case invalid(String)
  case checking
  case available
  case taken(String)
  case failed(String)

  var helperText: String {
    switch self {
    case .idle:
      return "3-20 characters. Letters, numbers, underscores, and periods only."
    case .invalid(let message), .taken(let message), .failed(let message):
      return message
    case .checking:
      return "Checking..."
    case .available:
      return "Username available"
    }
  }

  var isAvailable: Bool {
    if case .available = self { return true }
    return false
  }
}

public struct ChooseUsernameNativeView: View {
  let user: MIRAUser
  let api: MIRAAPIClient
  @ObservedObject var session: MIRAAuthSession

  @State private var username = ""
  @State private var availability: UsernameAvailabilityState = .idle
  @State private var suggestions: [String] = []
  @State private var isSaving = false
  @State private var appeared = false
  @FocusState private var isFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(user: MIRAUser, api: MIRAAPIClient, session: MIRAAuthSession) {
    self.user = user
    self.api = api
    self.session = session
  }

  public var body: some View {
    ZStack {
      MIRATheme.Color.appBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: MIRATheme.Space.xl) {
          VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
            Text("Choose your username")
              .font(.system(size: 36, weight: .semibold, design: .rounded))
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .fixedSize(horizontal: false, vertical: true)

            Text("This is how people will find you on Captro.")
              .font(.system(size: 16, weight: .medium))
              .foregroundStyle(MIRATheme.Color.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
            HStack(spacing: 10) {
              Text("@")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(MIRATheme.Color.textMuted)

              TextField("username", text: $username)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(MIRATheme.Color.textPrimary)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.continue)
                .onSubmit {
                  Task { await saveIfReady() }
                }

              availabilityIcon
            }
            .padding(.horizontal, MIRATheme.Space.md)
            .frame(height: 58)
            .background(MIRATheme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(borderColor, lineWidth: 1))

            Text(availability.helperText)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(helperColor)
              .fixedSize(horizontal: false, vertical: true)

            if !suggestions.isEmpty {
              VStack(alignment: .leading, spacing: 10) {
                Text("Suggestions")
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(MIRATheme.Color.textMuted)

                FlowSuggestionGrid(values: suggestions) { value in
                  UIImpactFeedbackGenerator(style: .light).impactOccurred()
                  username = value
                  isFocused = true
                }
              }
              .transition(.opacity.combined(with: .move(edge: .top)))
            }
          }
          .padding(MIRATheme.Space.lg)
          .miraCardSurface(cornerRadius: 26)

          Button {
            Task { await saveIfReady() }
          } label: {
            HStack {
              Spacer()
              if isSaving {
                ProgressView().tint(.white)
              } else {
                Text("Continue")
                  .font(.system(size: 16, weight: .semibold))
              }
              Spacer()
            }
            .foregroundStyle(.white)
            .frame(height: 52)
            .background(availability.isAvailable && !isSaving ? MIRATheme.Color.forest : MIRATheme.Color.textMuted.opacity(0.42))
            .clipShape(Capsule())
          }
          .buttonStyle(.miraPress)
          .disabled(!availability.isAvailable || isSaving)
        }
        .padding(.horizontal, MIRATheme.Space.xl)
        .padding(.top, 78)
        .padding(.bottom, 44)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 10)
      }
    }
    .onAppear {
      suggestions = makeSuggestions()
      if username.isEmpty {
        username = suggestions.first ?? ""
      }
      withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.26)) {
        appeared = true
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
        isFocused = true
      }
    }
    .task(id: username) {
      await validateUsernameAfterPause()
    }
  }

  @ViewBuilder
  private var availabilityIcon: some View {
    switch availability {
    case .checking:
      ProgressView()
        .tint(MIRATheme.Color.textMuted)
        .frame(width: 24, height: 24)
    case .available:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .font(.system(size: 22, weight: .semibold))
    case .taken, .invalid, .failed:
      Image(systemName: "exclamationmark.circle.fill")
        .foregroundStyle(.red.opacity(0.78))
        .font(.system(size: 22, weight: .semibold))
    case .idle:
      EmptyView()
    }
  }

  private var borderColor: Color {
    switch availability {
    case .available:
      return .green.opacity(0.45)
    case .taken, .invalid, .failed:
      return .red.opacity(0.32)
    default:
      return MIRATheme.Color.hairline
    }
  }

  private var helperColor: Color {
    switch availability {
    case .available:
      return .green.opacity(0.86)
    case .taken, .invalid, .failed:
      return .red.opacity(0.82)
    default:
      return MIRATheme.Color.textMuted
    }
  }

  @MainActor
  private func validateUsernameAfterPause() async {
    let clean = MIRAUsernameRules.normalized(username)
    if username != clean {
      username = clean
      return
    }
    guard !clean.isEmpty else {
      availability = .idle
      return
    }
    guard MIRAUsernameRules.isValidPublicUsername(clean) else {
      availability = .invalid(localValidationMessage(for: clean))
      return
    }
    availability = .checking
    try? await Task.sleep(nanoseconds: 320_000_000)
    guard !Task.isCancelled else { return }
    do {
      let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? clean
      let response: UsernameAvailabilityResponse = try await api.get("/users/check-username/\(encoded)")
      guard MIRAUsernameRules.normalized(username) == clean else { return }
      if response.available {
        availability = .available
      } else {
        availability = .taken(response.reason ?? "Username already taken")
        suggestions = makeSuggestions(excluding: clean)
      }
    } catch {
      availability = .failed("Could not check that username. Try again.")
    }
  }

  @MainActor
  private func saveIfReady() async {
    guard availability.isAvailable, !isSaving else { return }
    let clean = MIRAUsernameRules.normalized(username)
    isSaving = true
    defer { isSaving = false }
    do {
      let updated: MIRAUser = try await api.put("/users/me/username", body: UsernameClaimBody(username: clean))
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      session.replaceUser(updated)
    } catch {
      if await saveThroughProfileFallback(clean) {
        return
      }
      availability = .failed("Could not save username. Try another one.")
    }
  }

  @MainActor
  private func saveThroughProfileFallback(_ clean: String) async -> Bool {
    do {
      let updated: MIRAUser = try await api.put("/users/me", body: UsernameProfileFallbackBody(username: clean))
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      session.replaceUser(updated)
      return true
    } catch {
      return false
    }
  }

  private func localValidationMessage(for value: String) -> String {
    if value.count < 3 { return "Username must be at least 3 characters." }
    if value.count > 20 { return "Username must be 20 characters or fewer." }
    if value.range(of: #"^[a-z0-9_.]+$"#, options: .regularExpression) == nil {
      return "Use only letters, numbers, underscores, and periods."
    }
    if value.hasPrefix(".") || value.hasSuffix(".") || value.contains("..") {
      return "Username cannot start or end with a period or contain double periods."
    }
    return "Username cannot be used."
  }

  private func makeSuggestions(excluding excluded: String? = nil) -> [String] {
    var values: [String] = []
    let nameParts = nameTokens(from: user.fullName)
    let first = nameParts.first ?? ""
    let last = nameParts.dropFirst().first ?? ""
    if !first.isEmpty {
      values.append(first)
      if !last.isEmpty {
        values.append("\(first).\(last)")
        values.append("\(first)_\(last)")
      }
      values.append("real.\(first)")
      values.append("\(first)01")
    }

    if let emailPrefix = safeEmailPrefix(user.email) {
      values.append(emailPrefix)
      let noDigits = emailPrefix.replacingOccurrences(of: #"\d+$"#, with: "", options: .regularExpression)
      if noDigits.count >= 3 { values.append(noDigits) }
      if let numberSuffix = emailPrefix.range(of: #"\d+$"#, options: .regularExpression).map({ String(emailPrefix[$0]) }),
         !first.isEmpty {
        values.append("\(first)_\(numberSuffix)")
      }
    }

    values.append(contentsOf: ["captro.\(first.isEmpty ? "creator" : first)", "real.\(first.isEmpty ? "captro" : first)"])

    var seen = Set<String>()
    return values
      .map(cleanSuggestion)
      .filter { $0 != excluded }
      .filter { MIRAUsernameRules.isValidPublicUsername($0) }
      .filter { seen.insert($0).inserted }
      .prefix(5)
      .map { $0 }
  }

  private func nameTokens(from value: String?) -> [String] {
    let folded = (value ?? "")
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .lowercased()
    return folded
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .map(cleanSuggestion)
      .filter { $0.count >= 2 }
  }

  private func safeEmailPrefix(_ email: String?) -> String? {
    let clean = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard let atIndex = clean.firstIndex(of: "@") else { return nil }
    let domain = String(clean[clean.index(after: atIndex)...])
    guard !domain.contains("privaterelay.appleid.com"),
          !domain.contains("oauth.flames-up.local"),
          !domain.contains("phone.flames-up.local") else {
      return nil
    }
    let prefix = cleanSuggestion(String(clean[..<atIndex]))
    return prefix.count >= 3 ? prefix : nil
  }

  private func cleanSuggestion(_ value: String) -> String {
    value
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9_.]+"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\.+"#, with: ".", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
  }
}

private struct FlowSuggestionGrid: View {
  let values: [String]
  let onTap: (String) -> Void

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], alignment: .leading, spacing: 8) {
      ForEach(values, id: \.self) { value in
        Button {
          onTap(value)
        } label: {
          Text("@\(value)")
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(MIRATheme.Color.surfaceSoft)
            .clipShape(Capsule())
        }
        .buttonStyle(.miraPress)
      }
    }
  }
}
