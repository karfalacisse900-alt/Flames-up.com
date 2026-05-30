import AuthenticationServices
import AVFoundation
import GoogleSignIn
import SwiftUI
import UIKit

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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(session: MIRAAuthSession, api: MIRAAPIClient) {
    self.session = session
    self.api = api
  }

  public var body: some View {
    NavigationStack {
      ZStack {
        CaptroWelcomePager(
          selectedPage: $selectedWelcomePage,
          onLogin: { presentAuthPanel(createAccount: false) },
          onSignup: { presentAuthPanel(createAccount: true) }
        )

        if isAuthPanelVisible {
          Color.black.opacity(0.24)
            .ignoresSafeArea()
            .transition(.opacity)
            .onTapGesture {
              closeAuthPanel()
            }
            .zIndex(1)

          authPanel
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(2)
        }
      }
      .animation(CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion), value: isAuthPanelVisible)
      .toolbar(.hidden, for: .navigationBar)
    }
    .onOpenURL { url in
      _ = GIDSignIn.sharedInstance.handle(url)
    }
  }

  private var authPanel: some View {
    VStack(spacing: 0) {
      Capsule()
        .fill(MIRATheme.Color.textMuted.opacity(0.28))
        .frame(width: 42, height: 5)
        .padding(.top, 10)
        .padding(.bottom, MIRATheme.Space.md)

      HStack(spacing: MIRATheme.Space.sm) {
        VStack(alignment: .leading, spacing: 3) {
          Text(isCreatingAccount ? "Sign up" : "Log in")
            .font(.system(size: 28, weight: .black, design: .rounded))
            .foregroundStyle(MIRATheme.Color.textPrimary)
          Text(isCreatingAccount ? "Create your Captro account." : "Welcome back to Captro.")
            .font(.system(size: 14.5, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textSecondary)
        }

        Spacer()

        Button {
          closeAuthPanel()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .frame(width: 44, height: 44)
            .background(MIRATheme.Color.surfaceSoft)
            .clipShape(Circle())
        }
        .buttonStyle(.miraPress)
        .accessibilityLabel("Close")
      }
      .padding(.horizontal, MIRATheme.Space.xl)

      ScrollView {
        VStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
          socialAuthBlock
          authDivider
          formBlock
          legalFooter
        }
        .padding(.horizontal, MIRATheme.Space.xl)
        .padding(.top, MIRATheme.Space.lg)
        .padding(.bottom, MIRATheme.Space.xxl)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(maxHeight: isCreatingAccount ? 740 : 680, alignment: .bottom)
    .background(MIRATheme.Color.launchBackground)
    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    .modifier(MIRATheme.floatingShadow())
    .frame(maxHeight: .infinity, alignment: .bottom)
    .ignoresSafeArea(edges: .bottom)
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
      Text(isCreatingAccount ? "Create with email" : "Continue with email")
        .font(.system(size: 15, weight: .black, design: .rounded))
        .foregroundStyle(MIRATheme.Color.textPrimary)

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
    }
  }

  private var socialAuthBlock: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      Text(isCreatingAccount ? "Create your account" : "Sign in faster")
        .font(.system(size: 15, weight: .black, design: .rounded))
        .foregroundStyle(MIRATheme.Color.textPrimary)

      VStack(spacing: MIRATheme.Space.sm) {
        googleButton
        appleButton
      }
    }
  }

  private var googleButton: some View {
    Button {
      startGoogleSignIn()
    } label: {
      HStack(spacing: MIRATheme.Space.sm) {
        Text("G")
          .font(.system(size: 18, weight: .black, design: .rounded))
          .foregroundStyle(MIRATheme.Color.forest)
          .frame(width: 28, height: 28)
          .background(.white)
          .clipShape(Circle())
          .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))

        Text("Continue with Google")
          .font(.system(size: 16, weight: .black, design: .rounded))
      }
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .frame(maxWidth: .infinity)
      .frame(height: 52)
      .background(.white)
      .clipShape(Capsule())
      .overlay(Capsule().stroke(Color.black.opacity(0.12), lineWidth: 1))
    }
    .buttonStyle(.miraPress)
    .disabled(session.isWorking)
    .accessibilityLabel("Continue with Google")
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

  private var googleClientID: String {
    Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
      ?? "702354172189-9gg83vd92n3s217n5pb4ddqqsnme8ocb.apps.googleusercontent.com"
  }

  @MainActor
  private func startGoogleSignIn() {
    CaptroHaptics.light()
    session.errorMessage = nil
    GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientID)

    guard let presenter = UIApplication.shared.miraTopPresentedViewController() else {
      session.errorMessage = "Google sign in is not ready. Please try again."
      return
    }

    GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
      if error != nil {
        Task { @MainActor in
          session.errorMessage = "Google sign in could not finish."
        }
        return
      }

      guard let idToken = result?.user.idToken?.tokenString else {
        Task { @MainActor in
          session.errorMessage = "Google sign in did not return a valid token."
        }
        return
      }

      Task {
        await session.signInWithGoogle(idToken: idToken, api: api)
      }
    }
  }
}

private enum CaptroWelcomeVisualStyle {
  case capture
  case discover
  case people
}

private struct CaptroWelcomePage: Identifiable {
  let id: Int
  let titleKey: String
  let subtitleKey: String
  let background: Color
  let accent: Color
  let secondaryAccent: Color
  let textColor: Color
  let mutedTextColor: Color
  let imageName: String
  let visualStyle: CaptroWelcomeVisualStyle

  static let all: [CaptroWelcomePage] = [
    CaptroWelcomePage(
      id: 0,
      titleKey: "welcome.capture.title",
      subtitleKey: "welcome.capture.subtitle",
      background: Color(red: 0.090, green: 0.175, blue: 0.105),
      accent: Color(red: 0.580, green: 0.850, blue: 0.470),
      secondaryAccent: Color(red: 0.980, green: 0.820, blue: 0.420),
      textColor: .white,
      mutedTextColor: .white.opacity(0.82),
      imageName: "CaptroWelcomeCapture",
      visualStyle: .capture
    ),
    CaptroWelcomePage(
      id: 1,
      titleKey: "welcome.discover.title",
      subtitleKey: "welcome.discover.subtitle",
      background: Color(red: 0.030, green: 0.455, blue: 0.810),
      accent: Color(red: 0.480, green: 0.890, blue: 0.950),
      secondaryAccent: Color(red: 1.000, green: 0.600, blue: 0.350),
      textColor: .white,
      mutedTextColor: .white.opacity(0.84),
      imageName: "CaptroWelcomeDiscover",
      visualStyle: .discover
    ),
    CaptroWelcomePage(
      id: 2,
      titleKey: "welcome.people.title",
      subtitleKey: "welcome.people.subtitle",
      background: Color(red: 0.560, green: 0.075, blue: 0.590),
      accent: Color(red: 1.000, green: 0.475, blue: 0.650),
      secondaryAccent: Color(red: 0.970, green: 0.890, blue: 0.260),
      textColor: .white,
      mutedTextColor: .white.opacity(0.84),
      imageName: "CaptroWelcomePeople",
      visualStyle: .people
    )
  ]
}

private struct CaptroWelcomePager: View {
  @Binding var selectedPage: Int
  let onLogin: () -> Void
  let onSignup: () -> Void
  @StateObject private var audio = CaptroWelcomeAudioController()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var localization: MIRALocalization

  private var currentPage: CaptroWelcomePage {
    let pages = CaptroWelcomePage.all
    let index = min(max(selectedPage, 0), pages.count - 1)
    return pages[index]
  }

  var body: some View {
    ZStack {
      TabView(selection: $selectedPage) {
        ForEach(CaptroWelcomePage.all) { page in
          CaptroWelcomeSlide(page: page)
            .tag(page.id)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .ignoresSafeArea()

      VStack(spacing: 0) {
        HStack(alignment: .center, spacing: MIRATheme.Space.md) {
          CaptroWelcomeWordmark(color: currentPage.textColor)
          Spacer()
          CaptroWelcomeAudioButton(
            isPlaying: audio.isPlaying,
            tint: currentPage.textColor,
            action: { audio.toggle() }
          )
          CaptroWelcomePageIndicator(selectedPage: selectedPage, tint: currentPage.textColor)
        }
        .padding(.horizontal, 28)
        .padding(.top, 58)
        .animation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion), value: selectedPage)

        Spacer()

        HStack(spacing: MIRATheme.Space.md) {
          CaptroWelcomeActionButton(title: localization.string("auth.login"), style: .filled, action: onLogin)
          CaptroWelcomeActionButton(title: localization.string("auth.signup"), style: .light, action: onSignup)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 34)
      }
      .ignoresSafeArea()
    }
    .background(currentPage.background.ignoresSafeArea())
    .onAppear {
      audio.resumeIfAllowed()
    }
    .onDisappear {
      audio.stop()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        audio.resumeIfAllowed()
      } else {
        audio.pauseForInterruption()
      }
    }
  }
}

private struct CaptroWelcomeSlide: View {
  let page: CaptroWelcomePage
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @EnvironmentObject private var localization: MIRALocalization

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        page.background.ignoresSafeArea()

        CaptroWelcomeAnimatedScene(page: page)
          .allowsHitTesting(false)

        VStack(alignment: .leading, spacing: MIRATheme.Space.xl) {
          Spacer()

          VStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
            Text(localization.string(page.titleKey))
              .font(.system(size: 60, weight: .black, design: .rounded))
              .foregroundStyle(page.textColor)
              .lineLimit(3)
              .minimumScaleFactor(0.74)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityAddTraits(.isHeader)

            Text(localization.string(page.subtitleKey))
              .font(.system(size: 22, weight: .bold, design: .rounded))
              .foregroundStyle(page.mutedTextColor)
              .lineLimit(4)
              .minimumScaleFactor(0.82)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.bottom, max(145, geometry.safeAreaInsets.bottom + 130))
        }
        .padding(.horizontal, 28)
      }
      .animation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion), value: page.id)
    }
  }
}

private struct CaptroWelcomeAnimatedScene: View {
  let page: CaptroWelcomePage
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation) { timeline in
      GeometryReader { geometry in
        let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
        ZStack {
          switch page.visualStyle {
          case .capture:
            captureScene(size: geometry.size, time: time)
          case .discover:
            discoverScene(size: geometry.size, time: time)
          case .people:
            peopleScene(size: geometry.size, time: time)
          }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
      }
    }
  }

  @ViewBuilder
  private func captureScene(size: CGSize, time: TimeInterval) -> some View {
    CaptroWelcomePhotoCard(
      imageName: page.imageName,
      label: "Camera ready",
      badgeSystemImage: "camera.fill",
      accent: page.accent
    )
    .frame(width: min(size.width * 0.45, 178), height: min(size.height * 0.28, 228))
    .rotationEffect(.degrees(-7 + sin(time * 0.8) * 2.5))
    .position(x: size.width * 0.70, y: size.height * 0.24 + sin(time) * 10)

    CaptroFloatingCapsule(
      systemImage: "play.fill",
      label: "Short video",
      background: page.secondaryAccent,
      foreground: page.background
    )
    .frame(width: 172, height: 66)
    .rotationEffect(.degrees(7 + cos(time * 0.9) * 2))
    .position(x: size.width * 0.38, y: size.height * 0.35 + cos(time * 0.8) * 8)

    CaptroWelcomeStarAvatarCluster(
      imageName: "CaptroWelcomeProfile",
      accent: page.secondaryAccent,
      ring: page.textColor
    )
    .frame(width: 142, height: 118)
    .rotationEffect(.degrees(5 + sin(time * 0.85) * 2))
    .position(x: size.width * 0.80, y: size.height * 0.43 + sin(time * 1.2) * 8)
  }

  @ViewBuilder
  private func discoverScene(size: CGSize, time: TimeInterval) -> some View {
    CaptroWelcomePhotoCard(
      imageName: page.imageName,
      label: "Travel",
      badgeSystemImage: "location.fill",
      accent: page.secondaryAccent
    )
    .frame(width: min(size.width * 0.50, 208), height: min(size.height * 0.27, 214))
    .rotationEffect(.degrees(-8 + sin(time * 0.7) * 2.5))
    .position(x: size.width * 0.34, y: size.height * 0.22 + sin(time * 0.9) * 10)

    CaptroWelcomeMiniPhotoCard(
      imageName: "CaptroWelcomePeople",
      label: "Art",
      background: page.accent,
      foreground: page.background
    )
    .frame(width: 136, height: 172)
    .rotationEffect(.degrees(10 + cos(time * 0.8) * 3))
    .position(x: size.width * 0.66, y: size.height * 0.28 + cos(time) * 8)

    CaptroFloatingCapsule(
      systemImage: "fork.knife",
      label: "Food",
      background: page.secondaryAccent,
      foreground: page.background
    )
    .frame(width: 150, height: 66)
    .position(x: size.width * 0.55, y: size.height * 0.43 + sin(time * 1.1) * 7)
  }

  @ViewBuilder
  private func peopleScene(size: CGSize, time: TimeInterval) -> some View {
    CaptroWelcomePhotoCard(
      imageName: page.imageName,
      label: "Create",
      badgeSystemImage: "sparkles",
      accent: page.secondaryAccent
    )
    .frame(width: min(size.width * 0.50, 202), height: min(size.height * 0.29, 236))
    .rotationEffect(.degrees(-5 + sin(time * 0.7) * 2))
    .position(x: size.width * 0.62, y: size.height * 0.24 + sin(time * 0.9) * 9)

    CaptroFloatingCapsule(
      systemImage: "heart.fill",
      label: "Loved it",
      background: page.accent.opacity(0.92),
      foreground: .white
    )
    .frame(width: 162, height: 66)
    .position(x: size.width * 0.36, y: size.height * 0.39 + cos(time * 1.1) * 8)

    CaptroFloatingCircle(
      systemImage: "person.2.fill",
      background: .white.opacity(0.20),
      foreground: page.textColor
    )
    .frame(width: 88, height: 88)
    .position(x: size.width * 0.78, y: size.height * 0.42 + sin(time) * 7)
  }
}

private struct CaptroWelcomeStarAvatarCluster: View {
  let imageName: String
  let accent: Color
  let ring: Color

  var body: some View {
    ZStack {
      CaptroWelcomeStarAvatar(imageName: imageName, size: 74, ring: ring)
        .rotationEffect(.degrees(-9))
        .position(x: 48, y: 52)

      CaptroWelcomeStarAvatar(imageName: imageName, size: 58, ring: accent)
        .rotationEffect(.degrees(12))
        .position(x: 98, y: 34)

      CaptroWelcomeStarAvatar(imageName: imageName, size: 50, ring: .white.opacity(0.9))
        .rotationEffect(.degrees(-18))
        .position(x: 100, y: 88)
    }
    .background(
      Capsule()
        .fill(.white.opacity(0.15))
        .blur(radius: 0.5)
    )
    .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
    .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 12)
  }
}

private struct CaptroWelcomeStarAvatar: View {
  let imageName: String
  let size: CGFloat
  let ring: Color

  var body: some View {
    Image(imageName, bundle: .main)
      .resizable()
      .scaledToFill()
      .frame(width: size, height: size)
      .clipShape(CaptroWelcomeStarShape())
      .overlay(
        CaptroWelcomeStarShape()
          .stroke(ring.opacity(0.92), lineWidth: max(2, size * 0.04))
      )
      .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 7)
      .accessibilityHidden(true)
  }
}

private struct CaptroWelcomeStarShape: Shape {
  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let outerRadius = min(rect.width, rect.height) / 2
    let innerRadius = outerRadius * 0.48
    let points = 5
    var path = Path()

    for index in 0..<(points * 2) {
      let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
      let angle = CGFloat(index) * .pi / CGFloat(points) - .pi / 2
      let point = CGPoint(
        x: center.x + CGFloat(cos(Double(angle))) * radius,
        y: center.y + CGFloat(sin(Double(angle))) * radius
      )

      if index == 0 {
        path.move(to: point)
      } else {
        path.addLine(to: point)
      }
    }

    path.closeSubpath()
    return path
  }
}

private struct CaptroWelcomeWordmark: View {
  let color: Color

  var body: some View {
    HStack(spacing: 10) {
      Image("CaptroLaunchLogo", bundle: .main)
        .resizable()
        .scaledToFit()
        .frame(width: 34, height: 34)

      Text("Captro")
        .font(.system(size: 20, weight: .black, design: .rounded))
        .foregroundStyle(color)
    }
    .accessibilityLabel("Captro")
  }
}

private struct CaptroWelcomePageIndicator: View {
  let selectedPage: Int
  let tint: Color
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 8) {
      ForEach(CaptroWelcomePage.all.indices, id: \.self) { index in
        Capsule()
          .fill(tint.opacity(index == selectedPage ? 1 : 0.42))
          .frame(width: index == selectedPage ? 34 : 10, height: 9)
      }
    }
    .animation(CaptroMotion.feedChromeAnimation(reduceMotion: reduceMotion), value: selectedPage)
    .accessibilityLabel("Welcome screen \(selectedPage + 1) of \(CaptroWelcomePage.all.count)")
  }
}

private enum CaptroWelcomeActionStyle {
  case filled
  case light
}

@MainActor
private final class CaptroWelcomeAudioController: ObservableObject {
  @Published private(set) var isPlaying = false
  private var player: AVAudioPlayer?
  private var userMuted = false

  func resumeIfAllowed() {
    guard !userMuted else { return }
    startPlayback()
  }

  private func startPlayback() {
    guard player == nil else {
      play()
      return
    }
    guard let url = Bundle.main.url(forResource: "captro-welcome-loksii", withExtension: "mp3") ??
            Bundle.main.url(forResource: "captro-welcome-loksii", withExtension: "mp3", subdirectory: "Resources") else {
      isPlaying = false
      return
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
      let audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer.numberOfLoops = -1
      audioPlayer.volume = 0.22
      audioPlayer.prepareToPlay()
      player = audioPlayer
      play()
    } catch {
      isPlaying = false
    }
  }

  func toggle() {
    if isPlaying {
      userMuted = true
      pause()
    } else {
      userMuted = false
      startPlayback()
    }
  }

  func pauseForInterruption() {
    pause()
  }

  func stop() {
    player?.stop()
    player?.currentTime = 0
    isPlaying = false
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }

  private func play() {
    player?.play()
    isPlaying = player?.isPlaying == true
  }

  private func pause() {
    player?.pause()
    isPlaying = false
  }
}

private struct CaptroWelcomeAudioButton: View {
  let isPlaying: Bool
  let tint: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
        .font(.system(size: 14, weight: .black))
        .foregroundStyle(tint)
        .frame(width: 40, height: 40)
        .background(.white.opacity(0.18))
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
    }
    .buttonStyle(.miraPress)
    .accessibilityLabel(isPlaying ? "Mute welcome music" : "Play welcome music")
  }
}

private struct CaptroWelcomeActionButton: View {
  let title: String
  let style: CaptroWelcomeActionStyle
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 20, weight: .black, design: .rounded))
        .foregroundStyle(style == .filled ? .white : MIRATheme.Color.textPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(style == .filled ? Color.black : Color.white)
        .clipShape(Capsule())
        .overlay(
          Capsule()
            .stroke(style == .filled ? Color.black.opacity(0.18) : Color.black.opacity(0.16), lineWidth: 1)
        )
    }
    .buttonStyle(.miraPress)
    .accessibilityLabel(title)
  }
}

private struct CaptroWelcomePhotoCard: View {
  let imageName: String
  let label: String
  let badgeSystemImage: String
  let accent: Color

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      Image(imageName, bundle: .main)
        .resizable()
        .scaledToFill()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()

      LinearGradient(
        colors: [.clear, .black.opacity(0.54)],
        startPoint: .center,
        endPoint: .bottom
      )

      HStack(spacing: 8) {
        Image(systemName: badgeSystemImage)
          .font(.system(size: 13, weight: .black))
        Text(label)
          .font(.system(size: 13.5, weight: .black, design: .rounded))
          .lineLimit(1)
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 12)
      .frame(height: 36)
      .background(accent.opacity(0.86))
      .clipShape(Capsule())
      .padding(12)
    }
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .stroke(.white.opacity(0.26), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 16)
  }
}

private struct CaptroWelcomeMiniPhotoCard: View {
  let imageName: String
  let label: String
  let background: Color
  let foreground: Color

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      Image(imageName, bundle: .main)
        .resizable()
        .scaledToFill()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()

      LinearGradient(colors: [.clear, .black.opacity(0.48)], startPoint: .top, endPoint: .bottom)

      Text(label)
        .font(.system(size: 13, weight: .black, design: .rounded))
        .foregroundStyle(foreground)
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(background)
        .clipShape(Capsule())
        .padding(10)
    }
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.22), lineWidth: 1))
    .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 12)
  }
}

private struct CaptroFloatingMediaTile: View {
  let systemImage: String
  let label: String
  let background: Color
  let foreground: Color

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .fill(
          LinearGradient(
            colors: [background.opacity(0.95), background.opacity(0.62)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )

      Image(systemName: systemImage)
        .font(.system(size: 44, weight: .black))
        .foregroundStyle(foreground.opacity(0.88))
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      Text(label)
        .font(.system(size: 14, weight: .black, design: .rounded))
        .foregroundStyle(foreground)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.22), lineWidth: 1))
    .shadow(color: .black.opacity(0.16), radius: 20, x: 0, y: 12)
  }
}

private struct CaptroFloatingCapsule: View {
  let systemImage: String
  let label: String
  let background: Color
  let foreground: Color

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 18, weight: .black))
      Text(label)
        .font(.system(size: 15, weight: .black, design: .rounded))
        .lineLimit(1)
    }
    .foregroundStyle(foreground)
    .padding(.horizontal, 18)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(background)
    .clipShape(Capsule())
    .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
    .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 12)
  }
}

private struct CaptroFloatingCircle: View {
  let systemImage: String
  let background: Color
  let foreground: Color

  var body: some View {
    Circle()
      .fill(background)
      .overlay(
        Image(systemName: systemImage)
          .font(.system(size: 32, weight: .black))
          .foregroundStyle(foreground)
      )
      .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 1))
      .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 10)
  }
}

private struct CaptroFloatingAvatarPair: View {
  let accent: Color
  let secondaryAccent: Color
  let foreground: Color

  var body: some View {
    HStack(spacing: -12) {
      CaptroAvatarBubble(systemImage: "person.crop.circle.fill", background: accent, foreground: foreground)
      CaptroAvatarBubble(systemImage: "camera.fill", background: secondaryAccent, foreground: foreground)
      CaptroAvatarBubble(systemImage: "sparkles", background: .white.opacity(0.26), foreground: .white)
    }
    .padding(.horizontal, 18)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.white.opacity(0.18))
    .clipShape(Capsule())
    .overlay(Capsule().stroke(.white.opacity(0.24), lineWidth: 1))
    .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 12)
  }
}

private struct CaptroAvatarBubble: View {
  let systemImage: String
  let background: Color
  let foreground: Color

  var body: some View {
    Circle()
      .fill(background)
      .frame(width: 64, height: 64)
      .overlay(
        Image(systemName: systemImage)
          .font(.system(size: 27, weight: .black))
          .foregroundStyle(foreground)
      )
      .overlay(Circle().stroke(.white.opacity(0.38), lineWidth: 2))
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
