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
    DispatchQueue.main.async { UISelectionFeedbackGenerator().selectionChanged() }
  }

  public static func medium() {
    DispatchQueue.main.async { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
  }

  public static func success() {
    DispatchQueue.main.async { UINotificationFeedbackGenerator().notificationOccurred(.success) }
  }

  public static func warning() {
    DispatchQueue.main.async { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
  }

  public static func error() {
    DispatchQueue.main.async { UINotificationFeedbackGenerator().notificationOccurred(.error) }
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
    VStack(spacing: 0) {
      content
    }
    .frame(maxWidth: .infinity)
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
    let tint = isDestructive ? Color.red : MIRATheme.Color.textPrimary
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 18, weight: .semibold))
        .symbolRenderingMode(.monochrome)
        .frame(width: 21, height: 21)

      Text(title)
        .font(.body.weight(.medium))
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 0)
    }
    .foregroundStyle(tint)
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, minHeight: 48)
    .overlay(alignment: .bottom) { Rectangle().fill(MIRATheme.Color.hairline).frame(height: 0.5) }
    .contentShape(Rectangle())
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

/// Small actions use one native sheet. Content is measured, not a floating
/// panel with a competing drag recognizer over the scroll view.
private struct MIRAPremiumActionModalModifier<ModalContent: View>: ViewModifier {
  @Binding var isPresented: Bool
  let onDismissed: (() -> Void)?
  let modalContent: (_ dismiss: @escaping () -> Void) -> ModalContent
  @State private var contentHeight: CGFloat = 280

  func body(content: Content) -> some View {
    content.sheet(isPresented: $isPresented, onDismiss: onDismissed) {
      ScrollView {
        modalContent { isPresented = false }
          .frame(maxWidth: 560)
          .frame(maxWidth: .infinity)
          .background {
            GeometryReader { proxy in
              Color.clear.preference(key: CaptroActionSheetHeight.self, value: proxy.size.height)
            }
          }
          .padding(.horizontal, 16)
          .padding(.top, 20)
          .padding(.bottom, 16)
      }
      .onPreferenceChange(CaptroActionSheetHeight.self) { height in
        guard height.isFinite, height > 0 else { return }
        contentHeight = height + 36
      }
      .presentationDetents([.height(min(560, max(160, contentHeight))), .large])
      .presentationDragIndicator(.visible)
      .presentationBackground(MIRATheme.Color.surface)
      .tint(MIRATheme.Color.forest)
      .scrollDismissesKeyboard(.interactively)
      .onAppear { MIRAApplePerformanceLogger.event("modal_open", detail: "native_actions") }
      .onDisappear { MIRAApplePerformanceLogger.event("modal_close", detail: "native_actions") }
    }
  }
}

private struct CaptroActionSheetHeight: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
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

/// Compatibility entry point for existing search/edit flows. UIKit owns
/// safe areas, keyboard avoidance, VoiceOver modality and interactive dismissal.
/// Existing callers retain their dismiss closure and exactly-once cleanup.
private struct MIRABottomSheetModifier<Sheet: View>: ViewModifier {
  @Binding var isPresented: Bool
  let preferredHeightFraction: CGFloat
  let maxHeight: CGFloat
  let scrimOpacity: Double
  let onDismissed: (() -> Void)?
  let sheet: (_ dismiss: @escaping () -> Void) -> Sheet

  func body(content: Content) -> some View {
    content.sheet(isPresented: $isPresented, onDismiss: onDismissed) {
      sheet { isPresented = false }
        .presentationDetents([.fraction(min(0.95, max(0.35, preferredHeightFraction))), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(MIRATheme.Color.surface)
        .tint(MIRATheme.Color.forest)
        .onAppear { MIRAApplePerformanceLogger.event("modal_open", detail: "native_sheet") }
        .onDisappear { MIRAApplePerformanceLogger.event("modal_close", detail: "native_sheet") }
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
      .accessibilityHidden(isMounted)
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
          .accessibilityAddTraits(.isModal)
          .accessibilityAction(.escape) { dismiss() }
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
      guard isMounted, !isVisible else { return }
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
      guard isMounted, !isPresented, !isVisible else { return }
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
      .accessibilityHidden(isMounted)
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
          .accessibilityAddTraits(.isModal)
          .accessibilityAction(.escape) { dismiss() }
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
      guard isMounted, !isVisible else { return }
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
      guard isMounted, !isPresented, !isVisible else { return }
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
      .accessibilityHidden(mountedItem != nil)
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
          .accessibilityAddTraits(.isModal)
          .accessibilityAction(.escape) { dismiss() }
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
    let dismissedID = mountedItem?.id
    MIRAApplePerformanceLogger.event("modal_close", detail: "fullscreen_item")
    withAnimation(animation) {
      isVisible = false
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
      guard mountedItem?.id == dismissedID, item?.id == dismissedID, !isVisible else { return }
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
