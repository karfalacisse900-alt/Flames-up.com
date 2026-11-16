import AuthenticationServices
import CoreText
import SwiftUI

/// A fitted, bundled lockup; no remote artwork or startup work gates sign-in.
enum CaptroWelcomeLayout {
  static let maximumWidth: CGFloat = 480
  static func logoWidth(availableWidth: CGFloat) -> CGFloat {
    min(240, max(0, availableWidth - 64))
  }
  static func logoHeight(width: CGFloat) -> CGFloat { width * 624 / 2400 }
}

struct CaptroWelcomeView<AppleControl: View>: View {
  @ViewBuilder let appleControl: () -> AppleControl
  let onGoogle: () -> Void
  let onGuest: () -> Void
  let onEmail: () -> Void
  let busy: Bool
  let error: String?
  @Binding var hasRevealedArtwork: Bool
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 24) {
          Spacer(minLength: 24)
          CaptroBrandLogo(onDark: colorScheme == .dark)
            .frame(width: CaptroWelcomeLayout.logoWidth(availableWidth: geometry.size.width),
                   height: CaptroWelcomeLayout.logoHeight(width: CaptroWelcomeLayout.logoWidth(availableWidth: geometry.size.width)))
            .accessibilityHidden(true)
          VStack(spacing: 12) {
            Text("Turn your moments into memories.")
              .font(.largeTitle.bold()).foregroundStyle(MIRATheme.Color.textPrimary)
              .accessibilityAddTraits(.isHeader).accessibilityIdentifier("welcome.headline")
            Text("Capture moments. Discover places. Keep what matters.")
              .font(.body).foregroundStyle(MIRATheme.Color.textSecondary)
          }
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 16)
          VStack(spacing: 12) {
            appleControl()
              .frame(height: 50).clipShape(Capsule())
              .accessibilityIdentifier("welcome.apple")
              .contextMenu { emailOption }
              .accessibilityAction(named: "Use email instead", onEmail)
            CaptroWelcomeGoogleButton(isEnabled: !busy, action: onGoogle)
              .accessibilityIdentifier("welcome.google")
              .contextMenu { emailOption }
              .accessibilityAction(named: "Use email instead", onEmail)
            if let error, !error.isEmpty {
              Text(error).font(.callout).foregroundStyle(MIRATheme.Color.textError)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("welcome.error")
            }
            Button("Continue as guest", action: onGuest)
              .font(.body.weight(.medium)).foregroundStyle(MIRATheme.Color.textSecondary)
              .frame(minHeight: 44).disabled(busy).accessibilityIdentifier("welcome.guest")
            ViewThatFits(in: .horizontal) {
              HStack(spacing: 9) { termsLink; Text("·").accessibilityHidden(true); privacyLink }
              VStack(spacing: 0) { termsLink; privacyLink }
            }
            .font(.footnote).foregroundStyle(MIRATheme.Color.textSecondary)
          }
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .frame(maxWidth: CaptroWelcomeLayout.maximumWidth)
        .frame(minHeight: geometry.size.height)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .scrollBounceBehavior(.basedOnSize)
      .accessibilityIdentifier("welcome.accessibilityScroll")
    }
    .background(MIRATheme.Color.appBackground.ignoresSafeArea())
    .buttonStyle(.plain)
    // Keep the existing parent's presentation binding, without delaying actions
    // or replaying motion when returning from a sheet or the background.
    .onAppear { hasRevealedArtwork = true }
  }
  private var emailOption: some View {
    Button("Use email instead", action: onEmail).disabled(busy)
  }
  private var termsLink: some View {
    NavigationLink { TermsOfServiceView().toolbar(.visible, for: .navigationBar) } label: {
      Text("Terms of Service").frame(minHeight: 44)
    }.accessibilityIdentifier("welcome.terms")
  }
  private var privacyLink: some View {
    NavigationLink { PrivacyPolicyView().toolbar(.visible, for: .navigationBar) } label: {
      Text("Privacy Policy").frame(minHeight: 44)
    }.accessibilityIdentifier("welcome.privacy")
  }
}

#if DEBUG
private struct CaptroWelcomeReducedMotionKey: EnvironmentKey {
  static let defaultValue: Bool? = nil
}
extension EnvironmentValues {
  var captroWelcomeReducedMotion: Bool? {
    get { self[CaptroWelcomeReducedMotionKey.self] }
    set { self[CaptroWelcomeReducedMotionKey.self] = newValue }
  }
}
#endif

/// Uses the unmodified provider mark and Google's published dark button colors.
/// Text is native and grows for accessibility; no flattened authentication UI.
struct CaptroWelcomeGoogleButton: View {
  let isEnabled: Bool
  let action: () -> Void
  @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 17
  private static let registerFont: Void = {
    guard let url = Bundle.module.url(forResource: "GoogleSans-Medium", withExtension: "ttf") else { return }
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
  }()
  var body: some View {
    let _ = Self.registerFont
    Button(action: action) {
      HStack(spacing: 12) {
        Image("CaptroGoogleMark", bundle: .module).resizable().scaledToFit()
          .frame(width: 24, height: 24).accessibilityHidden(true)
        // ScaledMetric already applies Dynamic Type. The custom font's size:
        // initializer would apply it a second time at accessibility sizes.
        Text("Continue with Google").font(.custom("GoogleSans-Medium", fixedSize: fontSize))
          .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
      }
      .foregroundStyle(Color(white: 0.89)).padding(.horizontal, 16).padding(.vertical, 11)
      .frame(maxWidth: .infinity, minHeight: 50)
      .background(Color(red: 19 / 255, green: 19 / 255, blue: 20 / 255))
      .clipShape(RoundedRectangle(cornerRadius: 25))
      .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(Color(red: 142 / 255, green: 145 / 255, blue: 143 / 255), lineWidth: 1))
      .contentShape(RoundedRectangle(cornerRadius: 25))
    }
    .disabled(!isEnabled).opacity(isEnabled ? 1 : 0.5)
    .accessibilityLabel("Continue with Google")
  }
}
