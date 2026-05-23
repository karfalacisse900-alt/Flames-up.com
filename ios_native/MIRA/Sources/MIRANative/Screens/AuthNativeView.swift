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
