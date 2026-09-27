import AuthenticationServices
import CryptoKit
import Foundation
import GoogleSignIn
import Security
import SwiftUI
import UIKit

private let captroTermsVersion = "2026-07-03"

public struct AuthNativeView: View {
  @ObservedObject var session: MIRAAuthSession
  let api: MIRAAPIClient

  @State private var email = ""
  @State private var password = ""
  @State private var username = ""
  @State private var fullName = ""
  @State private var isCreatingAccount = false
  @State private var selectedWelcomePage = 0
  @State private var isAuthPanelVisible = false
  @State private var isForgotPasswordVisible = false
  @State private var forgotPasswordEmail = ""
  @State private var forgotPasswordNotice = ""
  @State private var resetPassword = ""
  @State private var confirmResetPassword = ""
  @State private var appleSignInNonce: String?
  @State private var isSocialSignInWorking = false
  @AppStorage("captro.terms.accepted.version") private var acceptedTermsVersion = ""
  @AppStorage("captro.terms.accepted.at") private var acceptedTermsAt = ""
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(session: MIRAAuthSession, api: MIRAAPIClient) {
    self.session = session
    self.api = api
  }

  public var body: some View {
    NavigationStack {
      CaptroWelcomePager(
        selectedPage: $selectedWelcomePage,
        onLogin: { presentAuthPanel(createAccount: false) },
        onSignup: { presentAuthPanel(createAccount: true) },
        onGuest: { session.continueAsGuest() }
      )
      .toolbar(.hidden, for: .navigationBar)
      .navigationDestination(isPresented: $isAuthPanelVisible) { authPanel }
    }
    .tint(MIRATheme.Color.forest)
    .sheet(isPresented: Binding(
      get: { session.passwordResetContext != nil },
      set: { if !$0 { session.clearPasswordResetContext() } }
    )) {
      NavigationStack {
        resetPasswordPanel
          .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { session.clearPasswordResetContext(); resetPassword = ""; confirmResetPassword = "" }
              .disabled(session.isWorking)
          } }
      }
      .interactiveDismissDisabled(session.isWorking)
    }
  }

  private var authPanel: some View {
    ScrollView {
      VStack(spacing: 24) {
        VStack(spacing: 12) {
          Text("Captro").font(.title.weight(.bold)).foregroundStyle(MIRATheme.Color.forest)
          Text(isCreatingAccount ? "Create account" : "Log in").font(.title2.weight(.bold))
          Text(isCreatingAccount ? "Join Captro and start sharing." : "Welcome back.")
            .font(.body).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 12)
        formBlock
        authDivider
        socialAuthBlock
        legalFooter
      }
      .frame(maxWidth: 480)
      .padding(.horizontal, 24).padding(.bottom, 24)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(MIRATheme.Color.appBackground)
    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    .navigationDestination(isPresented: $isForgotPasswordVisible) { forgotPasswordPanel }
  }

  private func presentAuthPanel(createAccount: Bool) {
    CaptroHaptics.light()
    session.errorMessage = nil
    isCreatingAccount = createAccount
    withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
      isAuthPanelVisible = true
    }
  }

  private func closeAuthPanel() {
    CaptroHaptics.light()
    withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
      isAuthPanelVisible = false
    }
  }

  private var formBlock: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      if isCreatingAccount {
        authField("Username", text: $username, systemImage: "person")
        authField("Full name", text: $fullName, systemImage: "textformat")
      }
      authField("Email", text: $email, systemImage: "envelope", keyboard: .emailAddress)
      secureField
      termsAcceptanceBlock

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
              .font(.body.weight(.semibold))
          }
          Spacer()
        }
        .foregroundStyle(MIRATheme.Color.onPrimary)
        .padding(.vertical, 12)
        .frame(minHeight: 50)
        .background(MIRATheme.Color.forest)
        .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.small))
      }
      .buttonStyle(.miraPress)
      .disabled(session.isWorking || !canSubmit)

      Button {
        withAnimation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion)) {
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

      if !isCreatingAccount {
        Button {
          forgotPasswordEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
          forgotPasswordNotice = ""
          session.errorMessage = nil
          CaptroHaptics.light()
          withAnimation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)) {
            isForgotPasswordVisible = true
          }
        } label: {
          Text("Forgot password?")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.forest)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var forgotPasswordPanel: some View {
    SettingsDetailScaffold(title: "Reset password") {
      Section {
        TextField("Email address", text: $forgotPasswordEmail).keyboardType(.emailAddress)
          .textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
      } footer: { Text("We’ll send a secure reset link to your email.") }
      Section {
        Button {
          Task {
            if await session.requestPasswordReset(email: forgotPasswordEmail, api: api) {
              forgotPasswordNotice = "Check your email for a reset link."
            }
          }
        } label: {
          HStack { Text("Send reset link"); Spacer(); if session.isWorking { ProgressView() } }
        }.disabled(session.isWorking || !forgotPasswordEmail.contains("@"))
      }
      if !forgotPasswordNotice.isEmpty { Text(forgotPasswordNotice).foregroundStyle(MIRATheme.Color.forest) }
      if let error = session.errorMessage { Text(error).foregroundStyle(.red) }
    }
  }

  private var resetPasswordPanel: some View {
    SettingsDetailScaffold(title: "New password") {
      Section {
        SecureField("New password", text: $resetPassword).textContentType(.newPassword)
        SecureField("Confirm password", text: $confirmResetPassword).textContentType(.newPassword)
      } footer: { Text("Use at least 8 characters.") }
      Section {
        Button {
          Task {
            if await session.completePasswordReset(password: resetPassword, api: api) {
              resetPassword = ""; confirmResetPassword = ""
              session.clearPasswordResetContext()
              isForgotPasswordVisible = false
              isAuthPanelVisible = false
            }
          }
        } label: { HStack { Text("Save new password"); Spacer(); if session.isWorking { ProgressView() } } }
          .disabled(session.isWorking || resetPassword.count < 8 || resetPassword != confirmResetPassword)
      }
      if !confirmResetPassword.isEmpty && resetPassword != confirmResetPassword { Text("Passwords do not match.").foregroundStyle(.red) }
      if let error = session.errorMessage { Text(error).foregroundStyle(.red) }
    }
  }

  private var socialAuthBlock: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      VStack(spacing: MIRATheme.Space.sm) {
        appleButton
        googleButton
      }
    }
  }

  private var googleButton: some View {
    MIRAGoogleSignInControl(isEnabled: !session.isWorking && !isSocialSignInWorking, action: startGoogleSignIn)
      .frame(height: 50)
      .opacity(session.isWorking || isSocialSignInWorking ? 0.45 : 1)
  }

  private var authDivider: some View {
    HStack(spacing: MIRATheme.Space.md) {
      Rectangle()
        .fill(MIRATheme.Color.textMuted.opacity(0.16))
        .frame(height: 1)
      Text("or")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
      Rectangle()
        .fill(MIRATheme.Color.textMuted.opacity(0.16))
        .frame(height: 1)
    }
    .padding(.vertical, 2)
  }

  private var appleButton: some View {
    ZStack {
      SignInWithAppleButton(.continue) { request in
        request.requestedScopes = [.fullName, .email]
        let nonce = randomNonceString()
        appleSignInNonce = nonce
        isSocialSignInWorking = true
        request.nonce = sha256(nonce)
        MIRAAuthDiagnostics.stage(.apple, "authorization_started")
      } onCompletion: { result in
        Task { @MainActor in
          finishAppleSignIn(result)
        }
      }
      .signInWithAppleButtonStyle(.whiteOutline)
      .allowsHitTesting(hasAcceptedCurrentTerms && !session.isWorking && !isSocialSignInWorking)

      if !hasAcceptedCurrentTerms {
        Button {
          session.errorMessage = termsRequiredMessage
          CaptroHaptics.error()
        } label: {
          Color.clear
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Accept Captro's terms before continuing with Apple")
      }
    }
    .frame(height: 50)
    .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.small))
    .opacity(session.isWorking || isSocialSignInWorking ? 0.56 : 1)
  }

  private var termsAcceptanceBlock: some View {
    Toggle(isOn: Binding(
      get: { hasAcceptedCurrentTerms },
      set: { accepted in
        acceptedTermsVersion = accepted ? captroTermsVersion : ""
        acceptedTermsAt = accepted ? ISO8601DateFormatter().string(from: Date()) : ""
        session.errorMessage = nil
      }
    )) {
      Text("I am 16 or older and accept the Terms and Community Guidelines.")
        .font(.footnote).fixedSize(horizontal: false, vertical: true)
    }
    .tint(MIRATheme.Color.forest)
    .frame(minHeight: 44)
  }

  private var legalFooter: some View {
    VStack(spacing: 4) {
      HStack(spacing: 16) {
        NavigationLink(destination: TermsOfServiceView()) { Text("Terms").frame(minWidth: 44, minHeight: 44) }
        NavigationLink(destination: PrivacyPolicyView()) { Text("Privacy").frame(minWidth: 44, minHeight: 44) }
      }
      NavigationLink(destination: CommunityGuidelinesView()) { Text("Community Guidelines").frame(minHeight: 44) }
    }
    .font(.footnote).foregroundStyle(.secondary)
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .environment(\.defaultMinListRowHeight, 44)
  }

  private func authField(
    _ placeholder: String,
    text: Binding<String>,
    systemImage: String,
    keyboard: UIKeyboardType = .default
  ) -> some View {
    MIRAFormInput(title: placeholder, text: text, keyboardType: keyboard,
                  contentType: keyboard == .emailAddress ? .emailAddress : nil)
  }

  private var secureField: some View {
    MIRAFormInput(title: "Password", text: $password, secure: true,
                  contentType: isCreatingAccount ? .newPassword : .password)
  }

  private var canSubmit: Bool {
    email.contains("@") && password.count >= 6 && (!isCreatingAccount || username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3)
  }

  @MainActor
  private func submit() async {
    guard requireTermsAcceptance() else { return }
    if isCreatingAccount {
      await session.register(email: email, password: password, username: username, fullName: fullName, termsVersion: acceptedTermsVersion, termsAcceptedAt: acceptedTermsAt, api: api)
    } else {
      await session.login(email: email, password: password, termsVersion: acceptedTermsVersion, termsAcceptedAt: acceptedTermsAt, api: api)
    }
  }

  private var googleClientID: String {
    Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
      ?? "702354172189-9gg83vd92n3s217n5pb4ddqqsnme8ocb.apps.googleusercontent.com"
  }

  private func secureResetField(_ placeholder: String, text: Binding<String>) -> some View {
    MIRAFormInput(title: placeholder, text: text, secure: true, contentType: .newPassword)
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
  private func startGoogleSignIn() {
    CaptroHaptics.light()
    session.errorMessage = nil
    guard !session.isWorking && !isSocialSignInWorking else {
      MIRAAuthDiagnostics.stage(.google, "duplicate_request_ignored")
      return
    }
    guard requireTermsAcceptance() else { return }
    guard let googleServerClientID else {
      session.errorMessage = "Google sign in is temporarily unavailable."
      MIRAApplePerformanceLogger.event("oauth_google_configuration_missing")
      MIRAAuthDiagnostics.failure(
        .google,
        stage: "configuration",
        category: .providerConfiguration,
        error: NSError(domain: "Captro.Auth.Configuration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Google server client ID is missing"])
      )
      return
    }
    GIDSignIn.sharedInstance.configuration = GIDConfiguration(
      clientID: googleClientID,
      serverClientID: googleServerClientID
    )

    guard let presenter = UIApplication.shared.miraTopPresentedViewController() else {
      session.errorMessage = "Google sign in is not ready. Please try again."
      return
    }

    isSocialSignInWorking = true
    MIRAAuthDiagnostics.stage(.google, "authorization_started")
    Task { @MainActor in
      defer { isSocialSignInWorking = false }
      do {
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        MIRAAuthDiagnostics.stage(.google, "provider_callback_received")
        let googleUser = try await result.user.refreshTokensIfNeeded()
        guard let idToken = googleUser.idToken?.tokenString, !idToken.isEmpty else {
          session.errorMessage = "Google sign in did not return a valid token."
          MIRAApplePerformanceLogger.event("oauth_google_id_token_missing")
          MIRAAuthDiagnostics.failure(
            .google,
            stage: "provider_callback",
            category: .callbackFailure,
            error: NSError(domain: "Captro.Auth.Google", code: 2, userInfo: [NSLocalizedDescriptionKey: "Provider credential missing"])
          )
          return
        }

        MIRAAuthDiagnostics.stage(.google, "provider_credential_received")
        await session.signInWithGoogle(
          idToken: idToken,
          accessToken: googleUser.accessToken.tokenString,
          termsVersion: acceptedTermsVersion,
          termsAcceptedAt: acceptedTermsAt,
          api: api
        )
      } catch {
        if isGoogleCancellation(error) {
          session.errorMessage = nil
          MIRAAuthDiagnostics.stage(.google, "provider_cancelled")
          return
        }
        MIRAAuthDiagnostics.failure(.google, stage: "provider_authorization", category: .callbackFailure, error: error)
        session.errorMessage = "Google sign in could not finish. Please try again."
      }
    }
  }

  @MainActor
  private func finishAppleSignIn(_ result: Result<ASAuthorization, Error>) {
    guard hasAcceptedCurrentTerms else {
      appleSignInNonce = nil
      isSocialSignInWorking = false
      session.errorMessage = termsRequiredMessage
      return
    }
    guard case .success(let authorization) = result else {
      appleSignInNonce = nil
      isSocialSignInWorking = false
      if case .failure(let error) = result, isAppleCancellation(error) {
        session.errorMessage = nil
        MIRAAuthDiagnostics.stage(.apple, "provider_cancelled")
        return
      }
      if case .failure(let error) = result {
        MIRAAuthDiagnostics.failure(.apple, stage: "provider_authorization", category: .callbackFailure, error: error)
      }
      session.errorMessage = "Apple sign in could not finish. Please try again."
      return
    }
    MIRAAuthDiagnostics.stage(.apple, "provider_callback_received")
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
          let tokenData = credential.identityToken,
          let idToken = String(data: tokenData, encoding: .utf8),
          !idToken.isEmpty,
          let nonce = appleSignInNonce,
          !nonce.isEmpty else {
      appleSignInNonce = nil
      isSocialSignInWorking = false
      MIRAApplePerformanceLogger.event("oauth_apple_credential_missing")
      MIRAAuthDiagnostics.failure(
        .apple,
        stage: "provider_callback",
        category: .callbackFailure,
        error: NSError(domain: "Captro.Auth.Apple", code: 2, userInfo: [NSLocalizedDescriptionKey: "Provider credential or nonce missing"])
      )
      session.errorMessage = "Apple sign in could not finish. Please try again."
      return
    }
    let fullName = PersonNameComponentsFormatter().string(from: credential.fullName ?? PersonNameComponents())
    MIRAAuthDiagnostics.stage(.apple, "provider_credential_received")
    Task { @MainActor in
      defer {
        appleSignInNonce = nil
        isSocialSignInWorking = false
      }
      await session.signInWithApple(
        idToken: idToken,
        email: credential.email,
        fullName: fullName.isEmpty ? nil : fullName,
        appleUser: credential.user,
        nonce: nonce,
        termsVersion: acceptedTermsVersion,
        termsAcceptedAt: acceptedTermsAt,
        api: api
      )
    }
  }

  private func isGoogleCancellation(_ error: Error) -> Bool {
    let providerError = error as NSError
    return providerError.code == -5 && providerError.domain.lowercased().contains("gidsignin")
  }

  private func isAppleCancellation(_ error: Error) -> Bool {
    let providerError = error as NSError
    return providerError.code == 1001 && providerError.domain.lowercased().contains("authenticationservices")
  }

  private var hasAcceptedCurrentTerms: Bool {
    acceptedTermsVersion == captroTermsVersion && !acceptedTermsAt.isEmpty
  }

  private var termsRequiredMessage: String {
    "Please accept Captro's Terms and Community Rules before continuing."
  }

  @MainActor
  private func requireTermsAcceptance() -> Bool {
    guard hasAcceptedCurrentTerms else {
      session.errorMessage = termsRequiredMessage
      CaptroHaptics.error()
      return false
    }
    return true
  }

  private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length

    while remainingLength > 0 {
      var randoms = [UInt8](repeating: 0, count: 16)
      let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
      if status != errSecSuccess {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
      }

      randoms.forEach { random in
        if remainingLength == 0 {
          return
        }
        if Int(random) < charset.count {
          result.append(charset[Int(random)])
          remainingLength -= 1
        }
      }
    }

    return result
  }

  private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashedData = SHA256.hash(data: inputData)
    return hashedData.compactMap { String(format: "%02x", $0) }.joined()
  }
}


private struct CaptroWelcomePager: View {
  @Binding var selectedPage: Int
  let onLogin: () -> Void
  let onSignup: () -> Void
  let onGuest: () -> Void
  @EnvironmentObject private var localization: MIRALocalization

  var body: some View {
    VStack(spacing: 0) {
      Text("Captro").font(.title.weight(.bold)).foregroundStyle(MIRATheme.Color.forest)
        .padding(.top, 32).padding(.bottom, 16)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("Find your people.")
            .font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
          Text("Share moments, discover places, and connect through what matters.")
            .font(.title3).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 480, alignment: .leading)
        .padding(.horizontal, 24).padding(.vertical, 48)
        .frame(maxWidth: .infinity)
      }
      VStack(spacing: 12) {
        CaptroWelcomeActionButton(title: localization.string("auth.login"), style: .filled, action: onLogin)
        CaptroWelcomeActionButton(title: localization.string("auth.signup"), style: .light, action: onSignup)
        Button("Continue as Guest", action: onGuest)
          .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }
      .frame(maxWidth: 480).padding(.horizontal, 24).padding(.bottom, 16)
    }
    .background(MIRATheme.Color.appBackground.ignoresSafeArea())
  }
}


private enum CaptroWelcomeActionStyle {
  case filled
  case light
}

private struct CaptroWelcomeActionButton: View {
  let title: String
  let style: CaptroWelcomeActionStyle
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.body.weight(.semibold))
        .foregroundStyle(style == .filled ? MIRATheme.Color.onPrimary : MIRATheme.Color.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .frame(minHeight: 50)
        .background(style == .filled ? MIRATheme.Color.forest : MIRATheme.Color.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.small))
        .overlay(
          RoundedRectangle(cornerRadius: MIRATheme.Radius.small)
            .stroke(MIRATheme.Color.hairline, lineWidth: 1)
        )
    }
    .buttonStyle(.miraPress)
    .accessibilityLabel(title)
  }
}

private extension UIApplication {
  @MainActor
  func miraTopPresentedViewController() -> UIViewController? {
    let activeScene = connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }

    let root = activeScene?
      .windows
      .first { $0.isKeyWindow }?
      .rootViewController

    return root?.miraTopPresentedViewController()
  }
}

private extension UIViewController {
  @MainActor
  func miraTopPresentedViewController() -> UIViewController {
    if let navigationController = self as? UINavigationController,
       let visibleViewController = navigationController.visibleViewController {
      return visibleViewController.miraTopPresentedViewController()
    }

    if let tabBarController = self as? UITabBarController,
       let selectedViewController = tabBarController.selectedViewController {
      return selectedViewController.miraTopPresentedViewController()
    }

    if let presentedViewController {
      return presentedViewController.miraTopPresentedViewController()
    }

    return self
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

  func helperText(localization: MIRALocalization) -> String {
    switch self {
    case .idle:
      return localization.string("auth.username_helper")
    case .invalid(let message), .taken(let message), .failed(let message):
      return message
    case .checking:
      return localization.string("auth.username_checking")
    case .available:
      return localization.string("auth.username_available")
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
  @EnvironmentObject private var localization: MIRALocalization

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
            Text(localization.string("auth.choose_username"))
              .font(.system(size: 36, weight: .semibold, design: .rounded))
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .fixedSize(horizontal: false, vertical: true)

            Text(localization.string("auth.username_subtitle"))
              .font(.system(size: 16, weight: .medium))
              .foregroundStyle(MIRATheme.Color.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
            HStack(spacing: 10) {
              Text("@")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(MIRATheme.Color.textMuted)

              TextField(localization.string("auth.username_placeholder"), text: $username)
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

            Text(availability.helperText(localization: localization))
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(helperColor)
              .fixedSize(horizontal: false, vertical: true)

            if !suggestions.isEmpty {
              VStack(alignment: .leading, spacing: 10) {
                Text(localization.string("auth.username_suggestions"))
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(MIRATheme.Color.textMuted)

                FlowSuggestionGrid(values: suggestions) { value in
                  CaptroHaptics.light()
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
                Text(localization.string("auth.continue"))
                  .font(.body.weight(.semibold))
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
      withAnimation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion)) {
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
        availability = .taken(usernameAvailabilityMessage(code: response.code, fallback: response.reason))
        suggestions = makeSuggestions(excluding: clean)
      }
    } catch {
      availability = .failed(localization.string("auth.username_check_failed"))
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
      CaptroHaptics.medium()
      session.replaceUser(updated)
    } catch {
      if await saveThroughProfileFallback(clean) {
        return
      }
      availability = .failed(localization.string("auth.username_save_failed"))
    }
  }

  @MainActor
  private func saveThroughProfileFallback(_ clean: String) async -> Bool {
    do {
      let updated: MIRAUser = try await api.put("/users/me", body: UsernameProfileFallbackBody(username: clean))
      CaptroHaptics.medium()
      session.replaceUser(updated)
      return true
    } catch {
      return false
    }
  }

  private func localValidationMessage(for value: String) -> String {
    if value.count < 3 { return localization.string("auth.username_too_short") }
    if value.count > 20 { return localization.string("auth.username_too_long") }
    if value.range(of: #"^[a-z0-9_.]+$"#, options: .regularExpression) == nil {
      return localization.string("auth.username_format")
    }
    if value.hasPrefix(".") || value.hasSuffix(".") || value.contains("..") {
      return localization.string("auth.username_period_rule")
    }
    return localization.string("auth.username_cannot_use")
  }

  private func usernameAvailabilityMessage(code: String?, fallback: String?) -> String {
    switch code?.lowercased() {
    case "taken":
      return localization.string("auth.username_taken")
    case "too_short":
      return localization.string("auth.username_too_short")
    case "too_long":
      return localization.string("auth.username_too_long")
    case "invalid_format":
      return localization.string("auth.username_format")
    case "reserved", "blocked_word":
      return localization.string("auth.username_cannot_use")
    default:
      return fallback?.isEmpty == false ? fallback! : localization.string("auth.username_taken")
    }
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
