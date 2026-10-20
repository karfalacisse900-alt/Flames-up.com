import AuthenticationServices
import CoreText
import SwiftUI

/// Welcome-only geometry. The approved raster is never redrawn or aspect-filled.
enum CaptroWelcomeLayout {
  // Exact supplied logo-free raster. Export dimensions do not establish original detail.
  static let sourceSize = CGSize(width: 1254, height: 1254)
  static let maximumWidth: CGFloat = 480
  static let maximumZoom: CGFloat = 1.03
  static func artworkHeight(width: CGFloat) -> CGFloat {
    min(maximumWidth, max(0, width)) * sourceSize.height / sourceSize.width * maximumZoom
  }
  static var requiredThreeXSource: CGSize {
    let base = fittedImageSize(width: maximumWidth, height: artworkHeight(width: maximumWidth))
    return CGSize(width: ceil(base.width * maximumZoom * 3),
                  height: ceil(base.height * maximumZoom * 3))
  }
  static func fittedImageSize(width: CGFloat, height: CGFloat) -> CGSize {
    let ratio = sourceSize.height / sourceSize.width
    // Reserve the zoom in BOTH axes. The final 1.03x image stays inside its
    // frame, including on narrow phones; no stamp edge is clipped by the zoom.
    let imageWidth = min(min(maximumWidth, max(0, width)) / maximumZoom,
                         max(0, height) / (ratio * maximumZoom))
    return CGSize(width: imageWidth, height: imageWidth * ratio)
  }
  static func fittedArtworkHeight(width: CGFloat, availableHeight: CGFloat, controlsHeight: CGFloat) -> CGFloat {
    min(artworkHeight(width: width), max(0, availableHeight - controlsHeight))
  }
}

/// Measure the native controls once per layout pass, then give the illustration
/// the remaining space. No geometry-to-state loop and no scroll view at normal sizes.
private struct CaptroWelcomeFixedLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    guard subviews.count == 2 else { return }
    let controls = subviews[1].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
    let heroHeight = CaptroWelcomeLayout.fittedArtworkHeight(width: bounds.width,
      availableHeight: bounds.height, controlsHeight: controls.height)
    subviews[0].place(at: bounds.origin, anchor: .topLeading,
      proposal: ProposedViewSize(width: bounds.width, height: heroHeight))
    subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.maxY - controls.height), anchor: .topLeading,
      proposal: ProposedViewSize(width: bounds.width, height: controls.height))
  }
}

enum CaptroWelcomePalette {
  static let paper = Color(red: 0.95, green: 0.92, blue: 0.85)
  static let ink = Color(red: 0.043, green: 0.043, blue: 0.043)
  static let secondary = Color(white: 0.76)
}

struct CaptroWelcomeView<AppleControl: View>: View {
  @ViewBuilder let appleControl: () -> AppleControl
  let onGoogle: () -> Void
  let onGuest: () -> Void
  let onEmail: () -> Void
  let busy: Bool
  let error: String?
  @Binding var hasRevealedArtwork: Bool
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
#if DEBUG
  @Environment(\.captroWelcomeReducedMotion) private var reviewReducedMotion
#endif
  @Environment(\.dynamicTypeSize) private var dynamicType
  @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 43
  @ScaledMetric(relativeTo: .body) private var subtitleSize: CGFloat = 17
  @State private var revealed = false
  @State private var zoomed = false

  private var reduceMotion: Bool {
#if DEBUG
    reviewReducedMotion ?? systemReduceMotion
#else
    systemReduceMotion
#endif
  }

  var body: some View {
    GeometryReader { geometry in
      let width = min(geometry.size.width, CaptroWelcomeLayout.maximumWidth)
      Group {
        if dynamicType.isAccessibilitySize {
          // Extreme text sizes cannot fit all authentication/legal actions on
          // one phone-height page. Keep readable type and explicit access to all.
          ScrollView {
            VStack(spacing: 0) {
              artwork(width: width, height: CaptroWelcomeLayout.artworkHeight(width: width))
              controls(width: width, compact: false)
            }
            .frame(width: width).frame(maxWidth: .infinity)
          }
          .scrollIndicators(.hidden)
          .accessibilityIdentifier("welcome.accessibilityScroll")
        } else {
          let safeTop = geometry.safeAreaInsets.top
          let topPadding = max(0, safeTop - 30)
          CaptroWelcomeFixedLayout {
            GeometryReader { hero in artwork(width: width, height: hero.size.height) }
            controls(width: width, compact: geometry.size.height < 850)
          }
          .background(CaptroWelcomePalette.ink)
          .padding(.top, topPadding)
          .background(CaptroWelcomePalette.paper)
          .frame(width: width, height: geometry.size.height + safeTop)
          .offset(y: -safeTop)
          .frame(maxWidth: .infinity, alignment: .top)
        }
      }
      .background(CaptroWelcomePalette.ink)
      .overlay(alignment: .top) {
        // SwiftUI's surrounding background fills the unsafe region with ink.
        // Cover only the empty band above the artwork, never the artwork itself.
        CaptroWelcomePalette.paper
          .frame(height: dynamicType.isAccessibilitySize ? geometry.safeAreaInsets.top
            : max(0, geometry.safeAreaInsets.top - 30))
          .offset(y: -geometry.safeAreaInsets.top)
          .allowsHitTesting(false).accessibilityHidden(true)
      }
    }
    .background {
      VStack(spacing: 0) {
        CaptroWelcomePalette.paper.frame(height: 120)
        CaptroWelcomePalette.ink
      }.ignoresSafeArea()
    }
    .buttonStyle(.plain)
    .task { await revealArtworkOnce() }
    .onChange(of: reduceMotion) { _, reduced in
      if reduced { settleArtwork() }
    }
    .onDisappear { settleArtwork() }
  }

  private func controls(width: CGFloat, compact: Bool) -> some View {
          VStack(spacing: 0) {
            Group {
              if dynamicType.isAccessibilitySize {
                Text("Turn your moments into memories.")
              } else {
                // Negative Text.lineSpacing is not honored consistently. Native
                // line views reproduce the approved tight editorial leading.
                VStack(spacing: -10 * width / 435) {
                  Text("Turn your")
                  Text("moments into")
                  Text("memories.")
                }
              }
            }
              .font(.system(size: headlineSize * width / 435, weight: .bold))
              .tracking(-1.35)
              .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
              .foregroundStyle(.white)
              .accessibilityElement(children: .ignore)
              .accessibilityLabel("Turn your moments into memories.")
              .accessibilityAddTraits(.isHeader).accessibilityIdentifier("welcome.headline")
              .padding(.horizontal, 30)
              .padding(.top, dynamicType.isAccessibilitySize ? 0 : -9)

            Text(dynamicType.isAccessibilitySize ? "Capture moments. Discover places. Keep what matters." : "Capture moments. Discover places.\nKeep what matters.")
              .font(.system(size: subtitleSize)).foregroundStyle(CaptroWelcomePalette.secondary)
              .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
              .padding(.horizontal, 34).padding(.top, compact ? 6 : 14)

            VStack(spacing: compact ? 8 : 11) {
              appleControl()
                .frame(height: 50).clipShape(Capsule())
                .accessibilityIdentifier("welcome.apple")
                .contextMenu { emailOption }
                .accessibilityAction(named: "Use email instead", onEmail)
              CaptroWelcomeGoogleButton(isEnabled: !busy, action: onGoogle)
                .accessibilityIdentifier("welcome.google")
                .contextMenu { emailOption }
                .accessibilityAction(named: "Use email instead", onEmail)
            }
            .padding(.horizontal, width * 0.091).padding(.top, compact ? 12 : 24)

            if let error, !error.isEmpty {
              Text(error).font(.callout).foregroundStyle(Color(red: 1, green: 0.72, blue: 0.68))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28).padding(.top, 12)
                .accessibilityIdentifier("welcome.error")
            }

            Button("Continue as guest", action: onGuest)
              .font(.body.weight(.medium)).foregroundStyle(CaptroWelcomePalette.secondary)
              .frame(minHeight: 44).padding(.top, compact ? 2 : 8).disabled(busy)
              .accessibilityIdentifier("welcome.guest")

            ViewThatFits(in: .horizontal) {
              HStack(spacing: 9) { termsLink; Text("·").accessibilityHidden(true); privacyLink }
              VStack(spacing: 0) { termsLink; privacyLink }
            }
            .font(.footnote).foregroundStyle(Color(white: 0.66))
            .padding(.horizontal, 20).padding(.top, compact ? 0 : 8).padding(.bottom, compact ? 0 : 8)
          }
          .background(CaptroWelcomePalette.ink)
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

  private func artwork(width: CGFloat, height: CGFloat) -> some View {
    let imageSize = CaptroWelcomeLayout.fittedImageSize(width: width, height: height)
    return
    ZStack(alignment: .top) {
      Image("CaptroWelcomeHero", bundle: .module)
        .resizable().interpolation(.high).scaledToFit()
        .frame(width: imageSize.width, height: imageSize.height)
        // Feather only the outer paper/black canvas into the matching surround.
        // The supplied pixels, proportions and all ticket edges stay unchanged;
        // the narrow edge blend avoids a rectangular seam in the still/1x state.
        .mask {
          LinearGradient(stops: [.init(color: .clear, location: 0),
            .init(color: .black, location: 0.012), .init(color: .black, location: 0.992),
            .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
              .init(color: .black, location: 0.006), .init(color: .black, location: 0.994),
              .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
        }
        .scaleEffect(reduceMotion ? 1 : (zoomed ? CaptroWelcomeLayout.maximumZoom : 1), anchor: .top)
        .opacity(reduceMotion || revealed ? 1 : 0)
      // Separate supplied lockup in the cleared paper area. It does not move
      // with the artwork, duplicate baked-in lettering, or affect control layout.
      CaptroBrandLogo()
        .frame(width: imageSize.width * 0.25, height: imageSize.width * 0.25 * 624 / 2400)
        .padding(.top, imageSize.width * 0.045)
    }
      .frame(width: width, height: height, alignment: .top)
      // Fade only the empty black margin below the ribbon; no stamp pixels are
      // changed. This joins the supplied printed black to the native black UI.
      .background {
        // Only the quiet surround changes when a short screen needs smaller art;
        // the approved illustration itself is always uniformly fitted, untouched.
        LinearGradient(stops: [.init(color: CaptroWelcomePalette.paper, location: 0.55),
          .init(color: CaptroWelcomePalette.ink, location: 0.85)], startPoint: .top, endPoint: .bottom)
      }
      .clipped()
      .accessibilityHidden(true)
      .allowsHitTesting(false)
  }

  @MainActor private func revealArtworkOnce() async {
    guard !hasRevealedArtwork, !reduceMotion else { settleArtwork(); return }
    hasRevealedArtwork = true
    withAnimation(.easeOut(duration: 0.6)) { revealed = true }
    do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
    guard !Task.isCancelled, !reduceMotion else { return }
    withAnimation(.easeInOut(duration: 8)) { zoomed = true }
  }

  private func settleArtwork() {
    var transaction = Transaction(); transaction.disablesAnimations = true
    withTransaction(transaction) { revealed = true; zoomed = !reduceMotion; hasRevealedArtwork = true }
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
