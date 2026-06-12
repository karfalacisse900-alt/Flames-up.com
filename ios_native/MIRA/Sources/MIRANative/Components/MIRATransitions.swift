import SwiftUI
import UIKit

public enum CaptroMotion {
  public enum Duration {
    public static let reduced: Double = 0.08
    public static let buttonPress: Double = 0.10
    public static let smallMenuOpen: Double = 0.20
    public static let smallMenuClose: Double = 0.16
    public static let bottomSheetOpen: Double = 0.32
    public static let bottomSheetClose: Double = 0.26
    public static let fullScreenOpen: Double = 0.28
    public static let fullScreenClose: Double = 0.24
    public static let mediaFade: Double = 0.16
    public static let feedChrome: Double = 0.16
    public static let pagePush: Double = 0.22
    public static let pageModal: Double = 0.26
    public static let pageTab: Double = 0.18
    public static let actionModalOpen: Double = 0.28
    public static let actionModalClose: Double = 0.22
  }

  public enum Scale {
    public static let buttonPressed: CGFloat = 0.97
    public static let smallMenuInitial: CGFloat = 0.965
    public static let fullScreenInitial: CGFloat = 0.985
    public static let actionModalInitial: CGFloat = 0.96
  }

  public static func buttonPressAnimation(reduceMotion: Bool) -> Animation {
    .easeOut(duration: reduceMotion ? Duration.reduced : Duration.buttonPress)
  }

  public static func smallMenuAnimation(reduceMotion: Bool) -> Animation {
    .easeOut(duration: reduceMotion ? Duration.reduced : Duration.smallMenuOpen)
  }

  public static func bottomSheetAnimation(reduceMotion: Bool) -> Animation {
    reduceMotion
      ? .easeOut(duration: Duration.reduced)
      : .spring(response: Duration.bottomSheetOpen, dampingFraction: 0.90, blendDuration: 0.02)
  }

  public static func fullScreenAnimation(reduceMotion: Bool) -> Animation {
    reduceMotion
      ? .easeOut(duration: Duration.reduced)
      : .spring(response: Duration.fullScreenOpen, dampingFraction: 0.92, blendDuration: 0.02)
  }

  public static func actionModalAnimation(reduceMotion: Bool) -> Animation {
    reduceMotion
      ? .easeOut(duration: Duration.reduced)
      : .spring(response: Duration.actionModalOpen, dampingFraction: 0.88, blendDuration: 0.02)
  }

  public static func mediaFadeAnimation(reduceMotion: Bool) -> Animation {
    .easeOut(duration: reduceMotion ? Duration.reduced : Duration.mediaFade)
  }

  public static func feedChromeAnimation(reduceMotion: Bool) -> Animation {
    .easeOut(duration: reduceMotion ? Duration.reduced : Duration.feedChrome)
  }

  public static func pageEnterAnimation(reduceMotion: Bool, duration: Double) -> Animation {
    .easeOut(duration: reduceMotion ? Duration.reduced : duration)
  }
}

public enum CaptroHaptics {
  public static func light() {
  }

  public static func medium() {
  }

  public static func success() {
  }

  public static func warning() {
  }

  public static func error() {
  }
}

public enum MIRATransitionTiming {
  public static let buttonPress: Double = CaptroMotion.Duration.buttonPress
  public static let popupOpen: Double = CaptroMotion.Duration.smallMenuOpen
  public static let popupClose: Double = CaptroMotion.Duration.smallMenuClose
  public static let sheetOpen: Double = CaptroMotion.Duration.bottomSheetOpen
  public static let sheetClose: Double = CaptroMotion.Duration.bottomSheetClose
  public static let fullScreenOpen: Double = CaptroMotion.Duration.fullScreenOpen
  public static let fullScreenClose: Double = CaptroMotion.Duration.fullScreenClose
  public static let actionModalOpen: Double = CaptroMotion.Duration.actionModalOpen
  public static let actionModalClose: Double = CaptroMotion.Duration.actionModalClose
}

private enum MIRAPresentationGeometry {
  static func sheetHeight(for proxy: GeometryProxy, preferredFraction: CGFloat, maxHeight: CGFloat) -> CGFloat {
    let available = max(320, proxy.size.height - 10)
    let preferred = proxy.size.height * preferredFraction
    return min(max(340, preferred), min(maxHeight, available))
  }
}

public extension View {
  func miraBottomSheet<Sheet: View>(
    isPresented: Binding<Bool>,
    preferredHeightFraction: CGFloat = 0.76,
    maxHeight: CGFloat = 720,
    scrimOpacity: Double = 0.22,
    onDismissed: (() -> Void)? = nil,
    @ViewBuilder sheet: @escaping (_ dismiss: @escaping () -> Void) -> Sheet
  ) -> some View {
    modifier(
      MIRABottomSheetModifier(
        isPresented: isPresented,
        preferredHeightFraction: preferredHeightFraction,
        maxHeight: maxHeight,
        scrimOpacity: scrimOpacity,
        onDismissed: onDismissed,
        sheet: sheet
      )
    )
  }

  func miraFadeScaleOverlay<Overlay: View>(
    isPresented: Binding<Bool>,
    scrimOpacity: Double = 0.18,
    onDismissed: (() -> Void)? = nil,
    @ViewBuilder overlay: @escaping (_ dismiss: @escaping () -> Void) -> Overlay
  ) -> some View {
    modifier(
      MIRAFadeScaleOverlayModifier(
        isPresented: isPresented,
        scrimOpacity: scrimOpacity,
        onDismissed: onDismissed,
        overlay: overlay
      )
    )
  }

  func miraFullScreenOverlay<Overlay: View>(
    isPresented: Binding<Bool>,
    background: Color = .black,
    onDismissed: (() -> Void)? = nil,
    @ViewBuilder overlay: @escaping (_ dismiss: @escaping () -> Void) -> Overlay
  ) -> some View {
    modifier(
      MIRAFullScreenBoolOverlayModifier(
        isPresented: isPresented,
        background: background,
        onDismissed: onDismissed,
        overlay: overlay
      )
    )
  }

  func miraFullScreenOverlay<Item: Identifiable, Overlay: View>(
    item: Binding<Item?>,
    background: Color = .black,
    onDismissed: (() -> Void)? = nil,
    @ViewBuilder overlay: @escaping (_ item: Item, _ dismiss: @escaping () -> Void) -> Overlay
  ) -> some View {
    modifier(
      MIRAFullScreenItemOverlayModifier(
        item: item,
        background: background,
        onDismissed: onDismissed,
        overlay: overlay
      )
    )
  }

  func miraHideTabBarOnAppear() -> some View {
    modifier(MIRAHideTabBarModifier())
  }

  func miraActionModal<ModalContent: View>(
    isPresented: Binding<Bool>,
    onDismissed: (() -> Void)? = nil,
    @ViewBuilder content: @escaping (_ dismiss: @escaping () -> Void) -> ModalContent
  ) -> some View {
    modifier(
      MIRAPremiumActionModalModifier(
        isPresented: isPresented,
        onDismissed: onDismissed,
        modalContent: content
      )
    )
  }

  func miraStatusBarHidden(_ hidden: Bool) -> some View {
    preference(key: MIRAStatusBarHiddenPreferenceKey.self, value: hidden)
  }
}

public struct MIRAActionModalCard<Content: View>: View {
  private let content: Content

  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  public var body: some View {
    VStack(spacing: 7) {
      content
    }
    .padding(10)
    .frame(maxWidth: 320)
    .background {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(Color(red: 0.945, green: 0.933, blue: 0.929).opacity(0.94))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    .shadow(color: .black.opacity(0.09), radius: 14, x: 0, y: 7)
    .shadow(color: .white.opacity(0.28), radius: 1, x: 0, y: 1)
    .accessibilityElement(children: .contain)
  }
}

public struct MIRAActionModalButton: View {
  let title: String
  let systemImage: String
  let isDestructive: Bool
  let staggerIndex: Int
  let action: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isVisible = false

  public init(
    title: String,
    systemImage: String,
    isDestructive: Bool = false,
    staggerIndex: Int = 0,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.systemImage = systemImage
    self.isDestructive = isDestructive
    self.staggerIndex = staggerIndex
    self.action = action
  }

  public var body: some View {
    Button {
      CaptroHaptics.light()
      action()
    } label: {
      MIRAActionModalPillLabel(
        title: title,
        systemImage: systemImage,
        isDestructive: isDestructive
      )
      .opacity(isVisible || reduceMotion ? 1 : 0)
      .offset(y: isVisible || reduceMotion ? 0 : 8)
    }
    .buttonStyle(.miraPress)
    .accessibilityLabel(title)
    .onAppear {
      guard !reduceMotion else {
        isVisible = true
        return
      }
      let delay = min(0.12, Double(staggerIndex) * 0.035)
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        withAnimation(.easeOut(duration: 0.18)) {
          isVisible = true
        }
      }
    }
  }
}

public struct MIRAActionModalPillLabel: View {
  let title: String
  let systemImage: String
  let isDestructive: Bool

  public init(title: String, systemImage: String, isDestructive: Bool = false) {
    self.title = title
    self.systemImage = systemImage
    self.isDestructive = isDestructive
  }

  public var body: some View {
    let tint = isDestructive ? Color(red: 1.0, green: 0.176, blue: 0.176) : Color(red: 0.02, green: 0.02, blue: 0.02)
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 18, weight: .semibold))
        .symbolRenderingMode(.monochrome)
        .frame(width: 21, height: 21)

      Text(title)
        .font(.system(size: 16, weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.78)

      Spacer(minLength: 0)
    }
    .foregroundStyle(tint)
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 44)
    .background(Color.white, in: Capsule())
    .contentShape(Capsule())
  }
}

struct MIRAStatusBarHiddenPreferenceKey: PreferenceKey {
  static var defaultValue = false

  static func reduce(value: inout Bool, nextValue: () -> Bool) {
    value = value || nextValue()
  }
}

private struct MIRAHideTabBarModifier: ViewModifier {
  @State private var token = UUID()

  func body(content: Content) -> some View {
    content
      .toolbar(.hidden, for: .tabBar)
      .onAppear {
        Task { @MainActor in
          MIRATabBarVisibilityStore.hide(token)
        }
      }
      .onDisappear {
        Task { @MainActor in
          MIRATabBarVisibilityStore.show(token)
        }
      }
  }
}

private struct MIRAPremiumActionModalModifier<ModalContent: View>: ViewModifier {
  @Binding var isPresented: Bool
  let onDismissed: (() -> Void)?
  let modalContent: (_ dismiss: @escaping () -> Void) -> ModalContent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isMounted = false
  @State private var isVisible = false
  @GestureState private var dragOffset: CGFloat = 0

  func body(content: Content) -> some View {
    content
      .overlay {
        if isMounted {
          GeometryReader { proxy in
            ZStack(alignment: .bottom) {
              Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(isVisible ? 0.88 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

              Color.black
                .opacity(isVisible ? 0.24 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)

              modalContent(dismiss)
                .padding(.horizontal, proxy.size.width > 700 ? 180 : 62)
                .padding(.bottom, max(18, proxy.safeAreaInsets.bottom + 12))
                .opacity(isVisible ? 1 : 0)
                .scaleEffect(reduceMotion || isVisible ? 1 : CaptroMotion.Scale.actionModalInitial)
                .offset(y: modalOffset(proxy: proxy))
                .compositingGroup()
                .simultaneousGesture(actionModalDragGesture(threshold: 78))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
          }
          .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
          .zIndex(920)
          .allowsHitTesting(isMounted)
        }
      }
      .onAppear {
        if isPresented {
          present()
        }
      }
      .onChange(of: isPresented) { _, newValue in
        newValue ? present() : dismissFromExternalState()
      }
      .animation(animation, value: isVisible)
      .animation(animation, value: dragOffset)
  }

  private var animation: Animation {
    CaptroMotion.actionModalAnimation(reduceMotion: reduceMotion)
  }

  private var dismissDelay: Double {
    reduceMotion ? CaptroMotion.Duration.reduced : CaptroMotion.Duration.actionModalClose
  }

  private func modalOffset(proxy: GeometryProxy) -> CGFloat {
    guard isVisible else { return 28 }
    return max(0, dragOffset)
  }

  private func actionModalDragGesture(threshold: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 14, coordinateSpace: .global)
      .updating($dragOffset) { value, state, _ in
        guard value.translation.height > 0, abs(value.translation.height) > abs(value.translation.width) else { return }
        state = value.translation.height
      }
      .onEnded { value in
        let shouldDismiss = value.translation.height > threshold || value.predictedEndTranslation.height > threshold * 1.45
        if shouldDismiss {
          dismiss()
        }
      }
  }

  private func present() {
    guard !isMounted else {
      if !isVisible {
        withAnimation(animation) { isVisible = true }
      }
      return
    }
    isMounted = true
    MIRAApplePerformanceLogger.event("modal_open", detail: "premium_action")
    DispatchQueue.main.async {
      withAnimation(animation) {
        isVisible = true
      }
    }
  }

  private func dismiss() {
    guard isMounted, isVisible else { return }
    MIRAApplePerformanceLogger.event("modal_close", detail: "premium_action")
    withAnimation(animation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      isPresented = false
      isMounted = false
      onDismissed?()
    }
  }

  private func dismissFromExternalState() {
    guard isMounted else { return }
    MIRAApplePerformanceLogger.event("modal_close", detail: "premium_action_external")
    withAnimation(animation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      guard !isPresented else { return }
      isMounted = false
      onDismissed?()
    }
  }
}

@MainActor
private enum MIRATabBarVisibilityStore {
  private static var hiddenTokens = Set<UUID>()

  static func hide(_ token: UUID) {
    hiddenTokens.insert(token)
    setTabBarHidden(true)
  }

  static func show(_ token: UUID) {
    hiddenTokens.remove(token)
    setTabBarHidden(!hiddenTokens.isEmpty)
  }

  private static func setTabBarHidden(_ hidden: Bool) {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .compactMap(\.rootViewController)
      .compactMap { $0.miraTabBarController }
      .forEach { tabBarController in
        guard tabBarController.tabBar.isHidden != hidden else { return }
        tabBarController.tabBar.isHidden = hidden
      }
  }
}

private extension UIViewController {
  var miraTabBarController: UITabBarController? {
    if let tabBarController = self as? UITabBarController {
      return tabBarController
    }
    if let owningTabBar = self.tabBarController {
      return owningTabBar
    }
    if let navigationController = self as? UINavigationController {
      return navigationController.visibleViewController?.miraTabBarController
        ?? navigationController.topViewController?.miraTabBarController
    }
    if let presentedViewController {
      return presentedViewController.miraTabBarController
    }
    for child in children {
      if let found = child.miraTabBarController {
        return found
      }
    }
    return nil
  }
}

private struct MIRABottomSheetModifier<Sheet: View>: ViewModifier {
  @Binding var isPresented: Bool
  let preferredHeightFraction: CGFloat
  let maxHeight: CGFloat
  let scrimOpacity: Double
  let onDismissed: (() -> Void)?
  let sheet: (_ dismiss: @escaping () -> Void) -> Sheet
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isMounted = false
  @State private var isVisible = false
  @State private var isContentVisible = false
  @GestureState private var dragOffset: CGFloat = 0

  func body(content: Content) -> some View {
    content
      .overlay {
        if isMounted {
          GeometryReader { proxy in
            let height = MIRAPresentationGeometry.sheetHeight(
              for: proxy,
              preferredFraction: preferredHeightFraction,
              maxHeight: maxHeight
            )
            ZStack(alignment: .bottom) {
              Color.black
                .opacity(isVisible ? scrimOpacity : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)

              ZStack(alignment: .top) {
                MIRATheme.Color.surface

                sheet(dismiss)
                  .opacity(isContentVisible ? 1 : 0)
                  .offset(y: isContentVisible || reduceMotion ? 0 : 10)
              }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(MIRATheme.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.sheet, style: .continuous))
                .overlay(alignment: .top) {
                  RoundedRectangle(cornerRadius: MIRATheme.Radius.sheet, style: .continuous)
                    .strokeBorder(Color.white.opacity(isVisible ? 0.12 : 0), lineWidth: 0.6)
                    .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(isVisible ? 0.18 : 0), radius: 26, x: 0, y: -8)
                .padding(.horizontal, proxy.size.width > 700 ? 76 : 0)
                .offset(y: sheetOffset(height: height, safeAreaBottom: proxy.safeAreaInsets.bottom))
                .simultaneousGesture(sheetDragGesture(threshold: min(180, height * 0.24)))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
          }
          .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
          .zIndex(900)
          .allowsHitTesting(isMounted)
        }
      }
      .onAppear {
        if isPresented {
          present()
        }
      }
      .onChange(of: isPresented) { _, newValue in
        newValue ? present() : dismissFromExternalState()
      }
      .animation(sheetAnimation, value: isVisible)
      .animation(sheetContentAnimation, value: isContentVisible)
      .animation(sheetAnimation, value: dragOffset)
  }

  private var sheetAnimation: Animation {
    CaptroMotion.bottomSheetAnimation(reduceMotion: reduceMotion)
  }

  private var sheetContentAnimation: Animation {
    reduceMotion
      ? .easeOut(duration: CaptroMotion.Duration.reduced)
      : .easeOut(duration: 0.18)
  }

  private var dismissDelay: Double {
    reduceMotion ? CaptroMotion.Duration.reduced : CaptroMotion.Duration.bottomSheetClose
  }

  private func sheetOffset(height: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
    guard isVisible else { return height + safeAreaBottom + 56 }
    return max(0, dragOffset)
  }

  private func sheetDragGesture(threshold: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 18, coordinateSpace: .global)
      .updating($dragOffset) { value, state, _ in
        guard value.translation.height > 0, abs(value.translation.height) > abs(value.translation.width) else { return }
        state = value.translation.height
      }
      .onEnded { value in
        let downward = value.translation.height > threshold || value.predictedEndTranslation.height > threshold * 1.35
        if downward {
          dismiss()
        }
      }
  }

  private func present() {
    guard !isMounted else {
      if !isVisible {
        isContentVisible = false
        withAnimation(sheetAnimation) { isVisible = true }
        revealSheetContent()
      }
      return
    }
    isMounted = true
    isContentVisible = false
    MIRAApplePerformanceLogger.event("modal_open", detail: "bottom_sheet")
    DispatchQueue.main.async {
      withAnimation(sheetAnimation) {
        isVisible = true
      }
      revealSheetContent()
    }
  }

  private func dismiss() {
    guard isMounted, isVisible else { return }
    MIRAApplePerformanceLogger.event("modal_close", detail: "bottom_sheet")
    withAnimation(sheetAnimation) {
      isContentVisible = false
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      isPresented = false
      isMounted = false
      onDismissed?()
    }
  }

  private func dismissFromExternalState() {
    guard isMounted else { return }
    MIRAApplePerformanceLogger.event("modal_close", detail: "bottom_sheet_external")
    withAnimation(sheetAnimation) {
      isContentVisible = false
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      guard !isPresented else { return }
      isMounted = false
      onDismissed?()
    }
  }

  private func revealSheetContent() {
    let delay = reduceMotion ? 0 : 0.055
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      guard isMounted, isVisible else { return }
      withAnimation(sheetContentAnimation) {
        isContentVisible = true
      }
    }
  }
}

private struct MIRAFadeScaleOverlayModifier<Overlay: View>: ViewModifier {
  @Binding var isPresented: Bool
  let scrimOpacity: Double
  let onDismissed: (() -> Void)?
  let overlay: (_ dismiss: @escaping () -> Void) -> Overlay
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isMounted = false
  @State private var isVisible = false

  func body(content: Content) -> some View {
    content
      .overlay {
        if isMounted {
          ZStack {
            Color.black
              .opacity(isVisible ? scrimOpacity : 0)
              .ignoresSafeArea()
              .contentShape(Rectangle())
              .onTapGesture(perform: dismiss)

            overlay(dismiss)
              .opacity(isVisible ? 1 : 0)
              .scaleEffect(reduceMotion || isVisible ? 1 : CaptroMotion.Scale.smallMenuInitial)
              .offset(y: reduceMotion || isVisible ? 0 : 6)
              .compositingGroup()
          }
          .zIndex(850)
          .allowsHitTesting(isMounted)
        }
      }
      .onAppear {
        if isPresented {
          present()
        }
      }
      .onChange(of: isPresented) { _, newValue in
        newValue ? present() : dismissFromExternalState()
      }
      .animation(animation, value: isVisible)
  }

  private var animation: Animation {
    CaptroMotion.smallMenuAnimation(reduceMotion: reduceMotion)
  }

  private var dismissDelay: Double {
    reduceMotion ? CaptroMotion.Duration.reduced : CaptroMotion.Duration.smallMenuClose
  }

  private func present() {
    guard !isMounted else {
      if !isVisible {
        withAnimation(animation) { isVisible = true }
      }
      return
    }
    isMounted = true
    MIRAApplePerformanceLogger.event("modal_open", detail: "fade_scale")
    DispatchQueue.main.async {
      withAnimation(animation) {
        isVisible = true
      }
    }
  }

  private func dismiss() {
    guard isMounted, isVisible else { return }
    MIRAApplePerformanceLogger.event("modal_close", detail: "fade_scale")
    withAnimation(animation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      isPresented = false
      isMounted = false
      onDismissed?()
    }
  }

  private func dismissFromExternalState() {
    guard isMounted else { return }
    MIRAApplePerformanceLogger.event("modal_close", detail: "fade_scale_external")
    withAnimation(animation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      guard !isPresented else { return }
      isMounted = false
      onDismissed?()
    }
  }
}

private struct MIRAFullScreenBoolOverlayModifier<Overlay: View>: ViewModifier {
  @Binding var isPresented: Bool
  let background: Color
  let onDismissed: (() -> Void)?
  let overlay: (_ dismiss: @escaping () -> Void) -> Overlay
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isMounted = false
  @State private var isVisible = false

  func body(content: Content) -> some View {
    content
      .overlay {
        if isMounted {
          ZStack {
            background
              .opacity(isVisible ? 1 : 0)
              .ignoresSafeArea()
            overlay(dismiss)
              .opacity(isVisible ? 1 : 0)
              .scaleEffect(reduceMotion || isVisible ? 1 : CaptroMotion.Scale.fullScreenInitial)
              .offset(y: reduceMotion || isVisible ? 0 : 8)
              .compositingGroup()
          }
          .ignoresSafeArea()
          .zIndex(950)
          .allowsHitTesting(isMounted)
        }
      }
      .onAppear {
        if isPresented {
          present()
        }
      }
      .onChange(of: isPresented) { _, newValue in
        newValue ? present() : dismissFromExternalState()
      }
      .animation(animation, value: isVisible)
  }

  private var animation: Animation {
    CaptroMotion.fullScreenAnimation(reduceMotion: reduceMotion)
  }

  private var dismissDelay: Double {
    reduceMotion ? CaptroMotion.Duration.reduced : CaptroMotion.Duration.fullScreenClose
  }

  private func present() {
    guard !isMounted else {
      if !isVisible {
        withAnimation(animation) { isVisible = true }
      }
      return
    }
    isMounted = true
    MIRAApplePerformanceLogger.event("modal_open", detail: "fullscreen")
    DispatchQueue.main.async {
      withAnimation(animation) {
        isVisible = true
      }
    }
  }

  private func dismiss() {
    guard isMounted, isVisible else { return }
    MIRAApplePerformanceLogger.event("modal_close", detail: "fullscreen")
    withAnimation(animation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      isPresented = false
      isMounted = false
      onDismissed?()
    }
  }

  private func dismissFromExternalState() {
    guard isMounted else { return }
    MIRAApplePerformanceLogger.event("modal_close", detail: "fullscreen_external")
    withAnimation(animation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      guard !isPresented else { return }
      isMounted = false
      onDismissed?()
    }
  }
}

private struct MIRAFullScreenItemOverlayModifier<Item: Identifiable, Overlay: View>: ViewModifier {
  @Binding var item: Item?
  let background: Color
  let onDismissed: (() -> Void)?
  let overlay: (_ item: Item, _ dismiss: @escaping () -> Void) -> Overlay
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var mountedItem: Item?
  @State private var isVisible = false

  func body(content: Content) -> some View {
    content
      .overlay {
        if let presentedItem = mountedItem {
          ZStack {
            background
              .opacity(isVisible ? 1 : 0)
              .ignoresSafeArea()
            overlay(presentedItem, dismiss)
              .opacity(isVisible ? 1 : 0)
              .scaleEffect(reduceMotion || isVisible ? 1 : CaptroMotion.Scale.fullScreenInitial)
              .offset(y: reduceMotion || isVisible ? 0 : 8)
              .compositingGroup()
          }
          .ignoresSafeArea()
          .zIndex(950)
          .allowsHitTesting(true)
        }
      }
      .onAppear(perform: syncWithBinding)
      .onChange(of: item?.id) { _, _ in
        syncWithBinding()
      }
      .animation(animation, value: isVisible)
  }

  private var animation: Animation {
    CaptroMotion.fullScreenAnimation(reduceMotion: reduceMotion)
  }

  private var dismissDelay: Double {
    reduceMotion ? CaptroMotion.Duration.reduced : CaptroMotion.Duration.fullScreenClose
  }

  private func syncWithBinding() {
    if let item {
      if mountedItem?.id == item.id, isVisible {
        return
      }
      mountedItem = item
      MIRAApplePerformanceLogger.event("modal_open", detail: "fullscreen_item")
      DispatchQueue.main.async {
        withAnimation(animation) {
          isVisible = true
        }
      }
    } else {
      dismissFromExternalState()
    }
  }

  private func dismiss() {
    guard mountedItem != nil, isVisible else { return }
    MIRAApplePerformanceLogger.event("modal_close", detail: "fullscreen_item")
    withAnimation(animation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      item = nil
      mountedItem = nil
      onDismissed?()
    }
  }

  private func dismissFromExternalState() {
    guard mountedItem != nil else { return }
    MIRAApplePerformanceLogger.event("modal_close", detail: "fullscreen_item_external")
    withAnimation(animation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      guard item == nil else { return }
      mountedItem = nil
      onDismissed?()
    }
  }
}
